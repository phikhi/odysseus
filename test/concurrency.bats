#!/usr/bin/env bats
#
# Per-ticket concurrency ([13]): an isolated working tree per iteration, a
# scheduler that only runs tickets whose write-surfaces cannot meet, and a
# serialized fold back onto the branch.
#
# Two things about how the parallel cases are staged, because a test that gets
# them wrong reads exactly like a green one.
#
# **Concurrency is observed, never assumed.** Each session registers itself in a
# directory and waits for a second one to appear; what a test asserts is the peak
# it really saw. A test that merely checked "both tickets resolved" would pass on
# a run that ground them one after the other, which is the whole property.
#
# **The fake counts with `mkdir` and writes one file per process**, for the reason
# [06] paid for: a counter read-then-written by concurrent sessions is a lie, and
# a fake that cannot count is worse than no fake because it is green.
#
# The waits are bounded and the bound is part of the guarantee, not a timeout to
# be tuned away ([25]). A run that is *supposed* to overlap gets a generous one —
# it is only ever paid when the property is broken — and a run that is supposed to
# sequence gets a short one, because there the wait is expected to expire and the
# assertion is that it did.

load helpers/harness
load helpers/assert

setup() {
  harness_setup
}

teardown() {
  harness_teardown
}

# A session that announces itself, waits to see a second one, and records the
# most it ever saw. One file per process: two sessions writing one counter is the
# arrangement that made six tests of [06] fail with unrelated messages.
concurrency__barrier_session() {
  printf '%s\n' "${1:-300}" >"$SHIM_STATE/barrier-tries"
  script_claude <<'FAKE'
#!/usr/bin/env bash
prompt="$(cat)"
state="$RALPH_SHIM_STATE"
me="$$"
mkdir -p "$state/live"
mkdir "$state/live/$me"

tries="$(cat "$state/barrier-tries" 2>/dev/null || echo 300)"
peak=0
while :; do
  n=0
  for d in "$state/live"/*; do
    [ -d "$d" ] && n=$((n + 1))
  done
  [ "$n" -gt "$peak" ] && peak="$n"
  [ "$n" -ge 2 ] && break
  [ "$tries" -gt 0 ] || break
  tries=$((tries - 1))
  sleep 0.1
done
# How many ignore pins were alive at that moment: one per iteration is what [30]
# asks for, and two concurrent iterations must not be sharing one.
pins=0
for d in "${TMPDIR:-/tmp}"/ralph-ignore.*; do
  [ -d "$d" ] && pins=$((pins + 1))
done
printf '%s %s\n' "$peak" "$pins" >"$state/peak.$me"

for target in $(printf '%s' "$prompt" | sed -n 's/^\*\*Write-surface:\*\* //p' |
  head -1 | tr -d '`\r' | tr ',' ' '); do
  mkdir -p "$(dirname "$target")" && printf 'written\n' >"$target"
done

rmdir "$state/live/$me"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE
}

# The most sessions any one of them ever saw alive at the same time.
concurrency__peak() {
  local f best=0 n
  for f in "$SHIM_STATE"/peak.*; do
    [ -e "$f" ] || continue
    n="$(awk '{ print $1 }' "$f")"
    [ "${n:-0}" -gt "$best" ] && best="$n"
  done
  printf '%s\n' "$best"
}

concurrency__peak_pins() {
  local f best=0 n
  for f in "$SHIM_STATE"/peak.*; do
    [ -e "$f" ] || continue
    n="$(awk '{ print $2 }' "$f")"
    [ "${n:-0}" -gt "$best" ] && best="$n"
  done
  printf '%s\n' "$best"
}

git_subjects() {
  git -C "$PROJECT_DIR" log --format='%s'
}

# A session that writes the paths it is given, and one that writes whatever its
# ticket declared. Local copies rather than harness API, the way test/gate.bats
# and test/failures.bats each keep their own: what a fake writes is the scenario
# a file is staging, not shared machinery.
script_session_writing() {
  local target
  {
    printf '#!/usr/bin/env bash\n'
    for target in "$@"; do
      printf 'mkdir -p "$(dirname %s)" && printf "written\\n" >>%s\n' "$target" "$target"
    done
    printf '%s\n' \
      "echo '{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"num_turns\":1,\"total_cost_usd\":0.02}'"
  } | script_claude
}

script_honest_session() {
  script_claude <<'FAKE'
#!/usr/bin/env bash
surface="$(cat | sed -n 's/^\*\*Write-surface:\*\* //p' | head -1 | tr -d '`\r' | tr ',' ' ')"
for target in $surface; do
  mkdir -p "$(dirname "$target")" && printf 'written\n' >"$target"
done
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE
}

# ── how many may be in flight ────────────────────────────────────────────────

@test "MAX_PARALLEL is the cap, and 1 is the shipped value" {
  pack_run 'concurrency_cap; printf "cap=%s\n" "$CONCURRENCY_CAP"'
  assert_success
  assert_output_contains "cap=1"

  set_config MAX_PARALLEL 4
  pack_run 'concurrency_cap; printf "cap=%s\n" "$CONCURRENCY_CAP"'
  assert_success
  assert_output_contains "cap=4"
}

@test "a nearly spent window buys fewer slots, and an unmeasured one says so" {
  set_config MAX_PARALLEL 4

  # Measured and roomy: the whole cap.
  pack_run 'RALPH_BUDGET_HEADROOM=100; concurrency_cap; printf "cap=%s\n" "$CONCURRENCY_CAP"'
  assert_success
  assert_output_contains "cap=4"

  # Measured and nearly spent: down to one, and never below it — a run that may
  # not start an iteration at all is `budget_check`'s decision, not this one's.
  pack_run 'RALPH_BUDGET_HEADROOM=2; concurrency_cap; printf "cap=%s\n" "$CONCURRENCY_CAP"'
  assert_success
  assert_output_contains "cap=1"

  # Half the headroom, half the slots: proportional, which is what makes this a
  # rate and not a price per iteration ([08] — this pack cannot price one).
  pack_run 'RALPH_BUDGET_HEADROOM=50; concurrency_cap; printf "cap=%s\n" "$CONCURRENCY_CAP"'
  assert_success
  assert_output_contains "cap=2"

  # And the shipped installation, where nothing measured a window: the cap stands
  # and the exposure is named rather than silently refused. Said once and not on
  # every scheduling pass, which is why this is a variable and not a value on
  # stdout — asked twice here, printed once.
  pack_run 'concurrency_cap; concurrency_cap; printf "cap=%s\n" "$CONCURRENCY_CAP"'
  assert_success
  assert_output_contains "cap=4"
  assert_equal "$(printf '%s\n' "$output" | grep -c 'no usage window was measured')" "1"
}

# ── which may run together ───────────────────────────────────────────────────

@test "the disjunction is the scope-guard's own predicate, in both directions" {
  use_tickets 01-alpha 02-beta 07-overlaps-alpha 08-no-write-surface

  # Nothing in flight is nothing to clash with — the line that keeps the
  # scheduler from spinning on a ticket that may never run beside anything.
  pack_run 'concurrency_clashes 08-no-write-surface "" && echo CLASH || echo FREE'
  assert_output_contains "FREE"

  # Disjoint surfaces run together; 07 declares `src/alpha.txt` as well, so it
  # cannot run beside 01.
  pack_run 'concurrency_clashes 02-beta "01-alpha" && echo CLASH || echo FREE'
  assert_output_contains "FREE"
  pack_run 'concurrency_clashes 07-overlaps-alpha "01-alpha" && echo CLASH || echo FREE'
  assert_output_contains "CLASH"
  # And the direction the first pair cannot show, because a surface is a glob on
  # both sides. `src` against `src/auth/*` matches **one way only**: as a pattern,
  # `src` covers `src/auth/*`, while as a pattern `src/auth/*` covers nothing
  # called `src`. So this pair clashes through the reverse test and through
  # nothing else — with one of the two directions removed, the two tickets below
  # would be scheduled together.
  perl -pi -e 's|^\*\*Write-surface:\*\*.*|**Write-surface:** `src`|' \
    "$(ticket_file 01-alpha)"
  perl -pi -e 's|^\*\*Write-surface:\*\*.*|**Write-surface:** `src/auth/*`|' \
    "$(ticket_file 02-beta)"
  harness__commit "test: a pair that meets in one direction only"
  pack_run 'gate_in_surface "src" "src/auth/*" && echo FORWARD || echo NO-FORWARD'
  assert_output_contains "NO-FORWARD"
  pack_run 'concurrency_clashes 01-alpha "02-beta" && echo CLASH || echo FREE'
  assert_output_contains "CLASH"

  # A surface this pack cannot read is a clash and not a pass: the whole
  # disjunction rests on the declaration being complete.
  pack_run 'concurrency_clashes 08-no-write-surface "01-alpha" && echo CLASH || echo FREE'
  assert_output_contains "CLASH"
  pack_run 'concurrency_clashes 01-alpha "08-no-write-surface" && echo CLASH || echo FREE'
  assert_output_contains "CLASH"
}

@test "two tickets with disjoint write-surfaces are ground at the same time" {
  use_tickets 01-alpha 02-beta
  set_config MAX_PARALLEL 2
  concurrency__barrier_session 300

  run_loop_own_tmp
  assert_success

  assert_equal "$(concurrency__peak)" "2"
  assert_ticket_status 01-alpha resolved
  assert_ticket_status 02-beta resolved
}

@test "MAX_PARALLEL=1 grinds two disjoint tickets one after the other" {
  # The cap itself, on the pair that *could* run together: without it, two tickets
  # nothing sequences would overlap. The clash predicate cannot carry this one —
  # these two are disjoint — so it is the only test that can tell a cap that is
  # read from a cap that is decoration.
  use_tickets 01-alpha 02-beta
  set_config MAX_PARALLEL 1
  concurrency__barrier_session 30

  run_loop_own_tmp
  assert_success

  assert_equal "$(concurrency__peak)" "1"
  assert_ticket_status 01-alpha resolved
  assert_ticket_status 02-beta resolved
}

@test "two tickets whose write-surfaces meet are sequenced, whatever MAX_PARALLEL says" {
  # 07 declares `src/alpha.txt` as well as `src/eta.txt`, so it may not run beside
  # 01 however many slots there are. The wait is short here on purpose: it is
  # *expected* to expire, twice, and the assertion is that it did.
  use_tickets 01-alpha 07-overlaps-alpha
  set_config MAX_PARALLEL 2
  concurrency__barrier_session 30

  run_loop_own_tmp
  assert_success

  assert_equal "$(concurrency__peak)" "1"
  assert_ticket_status 01-alpha resolved
  assert_ticket_status 07-overlaps-alpha resolved
}

# ── where an iteration runs ──────────────────────────────────────────────────

@test "each iteration gets a worktree of its own, and gives it back" {
  use_tickets 01-alpha 02-beta
  set_config MAX_PARALLEL 2
  concurrency__barrier_session 300

  run_loop_own_tmp
  assert_success

  # Two trees, both linked worktrees of this repository, neither of them the one
  # the run was started in — and both gone afterwards, registration included.
  run git -C "$PROJECT_DIR" worktree list --porcelain
  assert_success
  local n
  n="$(printf '%s\n' "$output" | grep -c '^worktree ')"
  assert_equal "$n" "1"
  run bash -c "ls -d '$RALPH_TEST_DIR/tmp'/ralph-worktree.* 2>/dev/null | awk 'END { print NR }'"
  assert_equal "$output" "0"
}

@test "an iteration's pinned ignore rules are its own, not the run's" {
  # [30] asks for one witness per *iteration* and not one per run: that is what
  # gives a ticket the right to deliver an ignore rule for the iteration after it.
  # Two in flight must therefore hold two, taken at two instants.
  use_tickets 01-alpha 02-beta
  set_config MAX_PARALLEL 2
  concurrency__barrier_session 300

  run_loop_own_tmp
  assert_success

  assert_equal "$(concurrency__peak)" "2"
  assert_equal "$(concurrency__peak_pins)" "2"
}

@test "WORKTREE_PROVISION copies what the project names, and the run counts it" {
  use_tickets 01-alpha
  set_config WORKTREE_PROVISION '.env'
  set_config TEST_CMD 'test -e .env'
  script_session_writing src/alpha.txt
  # Written *after* the last `set_config`, and that is not tidiness: `set_config`
  # commits, so an `.env` seeded before it would be committed — and a fresh
  # worktree would then carry it for a reason that has nothing to do with this key.
  # What is being staged is an untracked file, which is the case the key exists for.
  printf 'SECRET=1\n' >"$PROJECT_DIR/.env"

  run_loop
  assert_success
  assert_ticket_status 01-alpha resolved
  # Named out loud, every iteration: what the pilot puts there is judged by
  # nothing in this pack ([24]'s doctrine, entered from the other side).
  assert_output_contains "1 path(s) provisioned into this iteration's worktree"
}

@test "without it, the worktree carries none of the project's untracked files" {
  # The refutation of the test above, and the guarantee [24] handed to this
  # ticket: a fresh worktree is what stops a ticket going green on what an earlier
  # session left lying around.
  use_tickets 01-alpha
  set_config TEST_CMD 'test -e .env'
  set_config STERILE_K 1
  script_session_writing src/alpha.txt
  printf 'SECRET=1\n' >"$PROJECT_DIR/.env"

  run_loop
  assert_failure 4
  assert_output_contains "tests=red"
  assert_ticket_status 01-alpha ready-for-agent
}

# ── folding back ─────────────────────────────────────────────────────────────

@test "at MAX_PARALLEL=1 the fold is a fast-forward onto the very commit [07] wrote" {
  # The reason the fold has two shapes rather than always replaying: a sequential
  # run has to produce the history it produced before this ticket — same tree,
  # same message, same parent — or every assertion about that history in this
  # suite would be measuring something new.
  use_tickets 01-alpha 02-beta
  script_honest_session

  local before
  before="$(git -C "$PROJECT_DIR" rev-parse HEAD)"

  run_loop
  assert_success
  assert_output_contains "folded onto the branch"
  refute_output_contains "over a sibling's commit"

  run bash -c "git -C '$PROJECT_DIR' rev-list --count '$before..HEAD'"
  assert_equal "$output" "2"
  run git_subjects
  assert_output_contains "01-alpha: iteration delivered (gate green)"
  assert_output_contains "02-beta: iteration delivered (gate green)"
  # Linear: a fast-forward has one parent, so a merge anywhere would mean the fold
  # had invented a shape of its own.
  run bash -c "git -C '$PROJECT_DIR' rev-list --merges '$before..HEAD' | awk 'END { print NR }'"
  assert_equal "$output" "0"
}

@test "two green iterations both reach the branch, one commit each" {
  use_tickets 01-alpha 02-beta
  set_config MAX_PARALLEL 2
  concurrency__barrier_session 300

  local before
  before="$(git -C "$PROJECT_DIR" rev-parse HEAD)"

  run_loop_own_tmp
  assert_success
  assert_equal "$(concurrency__peak)" "2"

  # Neither one overwrote the other: both commits are on the branch, and both
  # files are in the tree it points at.
  run bash -c "git -C '$PROJECT_DIR' rev-list --count '$before..HEAD'"
  assert_equal "$output" "2"
  run git_subjects
  assert_output_contains "01-alpha: iteration delivered (gate green)"
  assert_output_contains "02-beta: iteration delivered (gate green)"
  run bash -c "git -C '$PROJECT_DIR' show HEAD:src/alpha.txt"
  assert_output_contains "written"
  run bash -c "git -C '$PROJECT_DIR' show HEAD:src/beta.txt"
  assert_output_contains "written"
}

@test "the fold never overwrites a branch tip it did not read" {
  # The compare-and-swap that now stands between two runs of this pack. [07]'s own
  # is still there and still tested, but it guards a detached HEAD inside a
  # worktree nothing else can reach; this is the one on the branch.
  #
  # Armed on the *second* `update-ref` of the iteration, which is the fold's: the
  # first is the durable commit inside the worktree. Between the tip this fold
  # read and the move it is about to make, another run commits.
  use_tickets 01-alpha
  set_config STERILE_K 1

  cat >"$SHIM_BIN/git" <<'GITSHIM'
#!/usr/bin/env bash
real() { PATH="${PATH#"$RALPH_SHIM_BIN":}" command git "$@"; }
if [ "$1" = update-ref ]; then
  n="$(cat "$RALPH_SHIM_STATE/updaterefs" 2>/dev/null || echo 0)"
  n=$((n + 1))
  printf '%s\n' "$n" >"$RALPH_SHIM_STATE/updaterefs"
  if [ "$n" = 2 ]; then
    main="$(cat "$RALPH_SHIM_STATE/project-dir")"
    printf 'the other run was here\n' >"$main/other-run.txt"
    real -C "$main" add -A -- other-run.txt >/dev/null 2>&1
    real -C "$main" -c user.name=other -c user.email=other@test.invalid \
      commit -q -m "another run committed here" >/dev/null 2>&1
  fi
fi
real "$@"
GITSHIM
  chmod +x "$SHIM_BIN/git"
  export RALPH_SHIM_BIN="$SHIM_BIN"

  script_session_writing src/alpha.txt

  run_loop
  assert_failure 4
  assert_output_contains "could not move the branch — this iteration is not on it"

  # The other run's commit is the tip: it was not overwritten, and this run said
  # so instead of resolving a ticket whose work went with its worktree.
  run bash -c "git -C '$PROJECT_DIR' log --format='%s' -1"
  assert_output_contains "another run committed here"
  assert_ticket_status 01-alpha ready-for-agent
  assert_equal "$(ticket_field 01-alpha Failures)" ""
}

@test "the tree the run was started in follows the branch" {
  # Not cosmetic: the iterations run elsewhere, so nothing else would ever write
  # these files. A branch that moves while the tree stands still shows every
  # delivered path as an unstaged *reversal* — and a `git commit -a` in the
  # morning would undo the night.
  use_tickets 01-alpha
  script_honest_session

  run_loop
  assert_success

  assert_file_contains "$PROJECT_DIR/src/alpha.txt" "written"
  # Everything but the loop's own bookkeeping, which is dirty in this tree by
  # design and which [19] provisions a `.gitignore` for: the tracker is written on
  # every claim and marking, and the journal is appended to.
  run bash -c "git -C '$PROJECT_DIR' status --porcelain -- . ':(exclude).scratch'"
  assert_equal "$output" ""
}

# ── the sweep, with siblings in flight ───────────────────────────────────────

@test "the liveness sweep does not reclaim a claim this run is holding" {
  # `CLAIM_TTL` would otherwise become a ceiling on how long a session may run:
  # the backstop reclaims a claim older than the TTL *even when its owner answers*
  # — its job against a recycled pid, a theft when the owner is this very run
  # ([12] via [13]).
  use_tickets 01-alpha 02-beta
  set_config MAX_PARALLEL 2
  set_config CLAIM_TTL 1

  # **Staggered by ticket and never by call order**, which is what makes the sweep
  # land where it has to. Both sessions sleeping the same span finish together, so
  # the sweep that follows the first one's return finds the second already marked
  # and has nothing to spare — the test then stayed green with the exemption
  # removed, which the mutation gate reported and which is the whole reason this
  # fake reads the prompt instead of a counter.
  script_claude <<'FAKE'
#!/usr/bin/env bash
prompt="$(cat)"
state="$RALPH_SHIM_STATE"
case "$prompt" in
  *'## Ticket: 01-alpha'*) sleep 3 ;;
  *) sleep 12 ;;
esac
for target in $(printf '%s' "$prompt" | sed -n 's/^\*\*Write-surface:\*\* //p' |
  head -1 | tr -d '`\r' | tr ',' ' '); do
  mkdir -p "$(dirname "$target")" && printf 'written\n' >"$target"
done
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop_own_tmp
  assert_success

  refute_output_contains "reclaimed"
  assert_ticket_status 01-alpha resolved
  assert_ticket_status 02-beta resolved
  # Two sessions and not three: a reclaimed sibling would have been ground again.
  assert_equal "$(claude_call_count)" "2"
}

# ── stopping with iterations in flight ───────────────────────────────────────

@test "a stop request lets the iterations in flight finish" {
  # [25]'s promise — "the current iteration finishes" — read where it can still
  # mean something once there is more than one. Exiting on the signal would leave
  # a `claude` per slot writing into a stream this process is about to delete, and
  # spending quota until morning ([28]).
  #
  # **The two sessions are deliberately asymmetric, and that is what makes the
  # test able to fail.** Held open together, the pilot is blocked collecting them
  # whatever it would have decided, so a run that tears its iterations down and one
  # that waits for them are indistinguishable — the first version of this test was
  # green either way and the mutation gate said so. Here 01 returns at once and 02
  # is held: the collection comes back with one iteration still in flight, which is
  # the only moment the decision is taken.
  #
  # And the hold is a file this test writes, never a delay: written with a `sleep`,
  # what the assertion measures is how busy the machine was.
  #
  # 03 is on the frontier for the half of the promise a scenario can actually
  # fail: a stop is a decision about what to **start**. It becomes eligible the
  # moment 01 resolves, its surface is disjoint from 02's and there is a free slot
  # — so a pilot that did not stop scheduling would grind it.
  use_tickets 01-alpha 02-beta 03-blocked
  set_config MAX_PARALLEL 2

  script_claude <<'FAKE'
#!/usr/bin/env bash
prompt="$(cat)"
state="$RALPH_SHIM_STATE"
case "$prompt" in
  *'## Ticket: 02-beta'*)
    : >"$state/held"
    tries=900
    while [ ! -e "$state/release" ] && [ "$tries" -gt 0 ]; do
      tries=$((tries - 1)); sleep 0.1
    done
    ;;
esac
for target in $(printf '%s' "$prompt" | sed -n 's/^\*\*Write-surface:\*\* //p' |
  head -1 | tr -d '`\r' | tr ',' ' '); do
  mkdir -p "$(dirname "$target")" && printf 'written\n' >"$target"
done
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  mkdir -p "$RALPH_TEST_DIR/tmp"
  env TMPDIR="$RALPH_TEST_DIR/tmp" bash "$PACK_DIR/loop.sh" \
    >"$RALPH_TEST_DIR/stop.out" 2>&1 &
  local pid=$! rc=0 waited=0

  # 02 is in flight and held; 01 has been collected and journalled. The pilot is
  # therefore about to take the decision this test is about.
  wait_for_file "$SHIM_STATE/held" 600 || fail "02-beta never started"
  waited=0
  while ! grep -q '01-alpha' "$FEATURE_DIR/run.log" 2>/dev/null; do
    [ "$waited" -lt 600 ] || fail "01-alpha never finished while 02-beta was held"
    waited=$((waited + 1))
    sleep 0.1
  done
  kill -TERM "$pid"

  # It must **not** be able to come back while 02 is held, and that is asserted by
  # waiting for an exit that has to time out. A pilot that drains cannot exit here
  # whatever the load; one that breaks out exits as soon as it is scheduled.
  waited=0
  while [ "$waited" -lt 100 ]; do
    pack_still_running "$pid" ||
      fail "the run exited on the signal with an iteration still in flight"
    waited=$((waited + 1))
    sleep 0.1
  done

  : >"$SHIM_STATE/release"
  waited=0
  while pack_still_running "$pid"; do
    [ "$waited" -lt 600 ] || break
    waited=$((waited + 1))
    sleep 0.1
  done
  if pack_still_running "$pid"; then
    kill -9 "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    fail "the run never came back after its iteration was released"
  fi
  wait "$pid" || rc=$?

  assert_equal "$rc" "4"
  run cat "$RALPH_TEST_DIR/stop.out"
  assert_output_contains "stop requested"
  # The one that was in flight when the signal arrived was finished and marked
  # rather than abandoned mid-session.
  assert_ticket_status 01-alpha resolved
  assert_ticket_status 02-beta resolved
  # And nothing new was started after it: two sessions, and the ticket that became
  # eligible in the meantime is untouched.
  assert_equal "$(claude_call_count)" "2"
  assert_ticket_status 03-blocked ready-for-agent
}

@test "an iteration that dies without a verdict gives its ticket back" {
  # The other end of the sweep exemption above, and it has to exist because of it:
  # this run's own claims are no longer reclaimable by anybody, so an iteration
  # that dies without marking would leave its ticket `claimed` for the rest of the
  # run — and, with the pid alive, for the next run's sweep too until CLAIM_TTL.
  #
  # Staged by killing the iteration's own shell from inside the session, which is
  # the only way to produce "the child died without answering" on demand: the fake
  # is spawned by `session_spawn`, so its parent *is* the shell running the
  # iteration.
  #
  # The run is bounded here rather than left to `run`, and that is the rule for a
  # test whose subject is a termination ([25]): the pilot notices a dead child
  # through two questions — the marker it never wrote, and a pid that no longer
  # answers — and a mutation that removes the second must fail this test rather
  # than hang the mutation gate in it.
  use_tickets 01-alpha
  set_config STERILE_K 1
  script_claude <<'FAKE'
#!/usr/bin/env bash
cat >/dev/null
kill -9 "$PPID" 2>/dev/null
sleep 30
FAKE

  bash "$PACK_DIR/loop.sh" >"$RALPH_TEST_DIR/lost.out" 2>&1 &
  local pid=$! rc=0 waited=0
  while kill -0 "$pid" 2>/dev/null; do
    [ "$waited" -lt 300 ] || break
    waited=$((waited + 1))
    sleep 0.1
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    fail "the pilot never noticed an iteration that died without answering"
  fi
  wait "$pid" || rc=$?

  run cat "$RALPH_TEST_DIR/lost.out"
  assert_output_contains "the iteration died without a verdict — given back to the frontier"
  assert_ticket_status 01-alpha ready-for-agent
}

# ── the preflight ────────────────────────────────────────────────────────────

@test "a repository with no commit is refused before anything is claimed" {
  use_tickets 01-alpha
  # A repository that has never been committed to: git cannot make a worktree out
  # of nothing, and finding that out at the first iteration would mean finding it
  # out with a ticket already claimed.
  rm -rf "$PROJECT_DIR/.git"
  git -c init.defaultBranch=main init -q "$PROJECT_DIR"
  git -C "$PROJECT_DIR" config user.name "ralph test"
  git -C "$PROJECT_DIR" config user.email "ralph@test.invalid"

  run_loop
  assert_failure 2
  assert_output_contains "this repository has no commit yet"
  assert_ticket_status 01-alpha ready-for-agent
  assert_equal "$(claude_call_count)" "0"
}

@test "a MAX_PARALLEL nobody can read is refused rather than read as 1" {
  use_tickets 01-alpha
  set_config MAX_PARALLEL "two"

  run_loop
  assert_failure 2
  assert_output_contains "MAX_PARALLEL is \"two\""
  assert_equal "$(claude_call_count)" "0"

  set_config MAX_PARALLEL 0
  run_loop
  assert_failure 2
  assert_output_contains "MAX_PARALLEL is \"0\""
}
