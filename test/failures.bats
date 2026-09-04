#!/usr/bin/env bats
#
# Typed failures: what the loop does with an iteration that did not deliver.
#
# Four kinds, four answers — a slice too big gets cut up, a scoping conflict goes
# straight to the human, a red gate or a dead session gets fresh retries — and
# one thing they all share: the repository goes back to where the session found
# it, and nothing the gate already approved is ever taken away.

load helpers/harness
load helpers/assert

setup() {
  harness_setup
}

teardown() {
  harness_teardown
}

# A session that writes the given files, relative to the project root, then
# reports success.
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

# What the run left uncommitted, the loop's own tracker aside.
# What the run left in the tree it was started in, minus the two directories that
# are the loop's own durable artefacts and dirty here by design: `.scratch/` — the
# tracker, written on every claim and marking, and the journal — and `receipts/`,
# one audit document per ticket the loop finished with ([10]). Both are named
# rather than globbed away: anything *else* the pack leaves untracked is still a
# finding, which is the whole point of this helper. `receipts/` is written in this
# tree and not in the iteration's worktree on purpose — a worktree is destroyed at
# the end of the iteration — and, like the tracker, it is what [19]'s installer
# provisions a `.gitignore` for. A project that commits it instead puts its own
# audit trail inside reach of a write-surface; that decision is named in [19].
worktree_dirt() {
  git -C "$PROJECT_DIR" status --porcelain | grep -Ev '\.scratch/|receipts/' || true
}

git_subjects() {
  git -C "$PROJECT_DIR" log --format='%s'
}

# A session that writes exactly what its own ticket declared, whichever ticket
# it is handed — so a run of several iterations stays inside every surface.
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

# The first session runs out of context — it reports a context far over the limit
# and keeps going, so the smart-zone net has to stop it — and every session after
# it runs the script given on stdin, with the prompt in $prompt and the call
# number in $n. That first call is what the loop reads as "this slice is too big".
script_too_big_then() {
  {
    cat <<'HEAD'
#!/usr/bin/env bash
prompt="$(cat)"
n="$(cat "$RALPH_SHIM_STATE/seq" 2>/dev/null || echo 0)"
n=$((n + 1)); printf '%s\n' "$n" >"$RALPH_SHIM_STATE/seq"
if [ "$n" = 1 ]; then
  echo '{"type":"system","subtype":"init","session_id":"s"}'
  echo '{"type":"assistant","message":{"role":"assistant","usage":{"input_tokens":10,"cache_read_input_tokens":9000,"output_tokens":5}}}'
  i=0
  while [ $i -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
  exit 0
fi
HEAD
    cat
  } | script_claude
}

# ── retry, then the human sink ───────────────────────────────────────────────

@test "a red gate buys fresh retries before anybody is escalated" {
  use_tickets 01-alpha
  set_config RETRY_N 2
  set_config STERILE_K 5
  stub_exit tests 1

  run_loop
  # Exit 0: three attempts, then nothing left on the frontier to grind.
  assert_success
  assert_output_contains "01-alpha: gate-red -> fresh retry (1 of 2)"
  assert_output_contains "01-alpha: gate-red -> fresh retry (2 of 2)"
  assert_output_contains "escalated to the human sink (failed-impl)"

  # Every retry is a session of its own: nothing is resumed.
  assert_equal "$(claude_call_count)" "3"
  assert_ticket_status 01-alpha ready-for-human
  assert_equal "$(ticket_field 01-alpha Failures)" "3"
  assert_equal "$(ticket_field 01-alpha Escalation)" "failed-impl"
  run ticket_has_field 01-alpha Claimed
  assert_failure
}

@test "a ticket nothing ever delivers goes to the human sink under its own name" {
  # Not `failed-impl`, for the reason [26] had to learn about `Failures:` and [23]
  # applied to a session that hung: nothing was judged, so a human sent to read a
  # verdict has been misrouted. One step further than [23], though — there is
  # nothing to read *at all* here, so the forensic branch is not written and the
  # note carries the question instead ([35]).
  use_tickets 01-alpha
  set_config RETRY_N 1
  set_config STERILE_K 3
  session_writes_nothing

  run_loop
  # Exit 0: two attempts, then nothing left on the frontier to grind.
  assert_success
  assert_output_contains "01-alpha: nothing-delivered -> fresh retry (1 of 1)"
  assert_output_contains "escalated to the human sink (nothing-delivered)"

  assert_ticket_status 01-alpha ready-for-human
  assert_equal "$(ticket_field 01-alpha Escalation)" "nothing-delivered"
  assert_equal "$(ticket_field 01-alpha Failures)" "2"

  # No branch to send a human to: it would hold the very tree the session was
  # handed, offered as the thing to go and read.
  run git -C "$PROJECT_DIR" rev-parse --verify "refs/heads/failed/01-alpha"
  assert_failure

  # What the ticket gets instead is the question to ask.
  assert_file_contains "$(ticket_file 01-alpha)" "changed no file the gate can see"
  assert_file_contains "$(ticket_file 01-alpha)" "why this ticket makes a session do nothing"
}

@test "the retry budget is the configured one, not a number in the code" {
  use_tickets 01-alpha
  set_config RETRY_N 0
  set_config STERILE_K 5
  stub_exit tests 1

  run_loop
  assert_success
  assert_equal "$(claude_call_count)" "1"
  assert_ticket_status 01-alpha ready-for-human
  assert_equal "$(ticket_field 01-alpha Failures)" "1"
}

@test "a green delivery clears the retry counter" {
  # `Failures:` is a budget, not a history, and nothing used to clear it: probed on
  # 29/07/2026, a ticket delivered green twice was escalated `failed-impl` on its
  # third visit to the frontier, on a counter that had never been reset. Red once,
  # then green, and the counter is gone — a ticket that comes back to the frontier
  # after a delivery comes back for a new reason, with its whole budget.
  use_tickets 01-alpha
  set_config RETRY_N 2
  set_config STERILE_K 5
  stub_exit tests 1

  # The first session leaves the test command failing and the second one repairs
  # it, so the ticket is really retried rather than delivered on the first attempt.
  script_claude <<'FAKE'
#!/usr/bin/env bash
n="$(cat "$RALPH_SHIM_STATE/seq" 2>/dev/null || echo 0)"
n=$((n + 1)); printf '%s\n' "$n" >"$RALPH_SHIM_STATE/seq"
mkdir -p src
printf 'written\n' >src/alpha.txt
[ "$n" -ge 2 ] && printf '0\n' >"$RALPH_SHIM_STATE/stub-tests.exit"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_success

  # The retry really happened, so the counter really was at 1 in between: without
  # this line the assertion below would hold on a ticket that never failed at all.
  assert_output_contains "01-alpha: gate-red -> fresh retry (1 of 2)"
  assert_equal "$(claude_call_count)" "2"
  assert_ticket_status 01-alpha resolved

  run ticket_has_field 01-alpha Failures
  assert_failure
}

@test "a dead session is retried too, and journalled apart from a red gate" {
  use_tickets 01-alpha
  set_config RETRY_N 1
  set_config STERILE_K 5

  script_claude <<'FAKE'
#!/usr/bin/env bash
echo '{"type":"result","subtype":"error_during_execution","is_error":true}'
exit 1
FAKE

  run_loop
  assert_success
  assert_output_contains "01-alpha: crash -> fresh retry (1 of 1)"
  assert_equal "$(claude_call_count)" "2"
  assert_ticket_status 01-alpha ready-for-human
  assert_file_contains "$FEATURE_DIR/run.log" "failed"
}

# ── a scoping conflict is not an attempt to retry ────────────────────────────

@test "a contractual overflow escalates at once, without spending a retry" {
  use_tickets 01-alpha 02-beta
  set_config STERILE_K 5
  script_session_writing src/beta.txt

  run_loop
  assert_success
  assert_output_contains "scope overflow on 01-alpha: contract"
  assert_output_contains "escalated to the human sink (decision)"

  assert_ticket_status 01-alpha ready-for-human
  assert_equal "$(ticket_field 01-alpha Escalation)" "decision"
  # No retry burned: the counter was never touched.
  run ticket_has_field 01-alpha Failures
  assert_failure

  # One attempt on it, and the run carries on with the rest of the frontier.
  assert_equal "$(claude_call_count)" "2"
  assert_ticket_status 02-beta resolved
}

@test "the classification table, as the budget classifier will find it" {
  pack_run '
    failures_classify over-soft-limit
    failures_classify gate-red contract
    failures_classify gate-red internal
    failures_classify gate-red
    failures_classify failed
    failures_classify over-soft-limit contract'
  assert_success
  assert_equal "$output" "too-big
contract
gate-red
gate-red
crash
too-big"
}

# ── rollback ─────────────────────────────────────────────────────────────────

@test "a stray write is undone: the next session inherits none of the attempt" {
  use_tickets 01-alpha
  set_config STERILE_K 1

  # Staged but not committed, which is what an agent interrupted mid-commit
  # leaves. Undoing the files without unstaging them would leave the attempt
  # sitting in the index, ready to ride along with the next commit.
  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src
printf 'written\n' >src/alpha.txt
printf 'written\n' >src/rogue.txt
git add -A
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_failure 4
  assert_output_contains "rolled back 2 path(s) the session touched"

  # The whole attempt, not just the part that broke the gate.
  refute_file_exists "$PROJECT_DIR/src/rogue.txt"
  refute_file_exists "$PROJECT_DIR/src/alpha.txt"
  assert_equal "$(worktree_dirt)" ""
}

@test "a commit the session made does not survive its own red gate" {
  use_tickets 01-alpha
  set_config STERILE_K 1

  # Work in progress the run inherited, and never touched: it is on the way of a
  # `git reset --hard` plus `git clean -fd`, which is what the obvious rollback
  # of a session that committed would be.
  printf 'mine\n' >"$PROJECT_DIR/wip.txt"
  printf 'edited by a human\n' >>"$PROJECT_DIR/CONTEXT.md"

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src
printf 'written\n' >src/alpha.txt
printf 'written\n' >rogue.txt
git add -A
git commit -q -m "session: work"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_failure 4
  assert_output_contains "rolled back the commit the session made"

  run git_subjects
  refute_output_contains "session: work"
  refute_file_exists "$PROJECT_DIR/rogue.txt"
  refute_file_exists "$PROJECT_DIR/src/alpha.txt"

  # The commit is gone and what it committed of somebody else's work is back
  # where it was: uncommitted, and still there.
  assert_file_contains "$PROJECT_DIR/wip.txt" "mine"
  assert_file_contains "$PROJECT_DIR/CONTEXT.md" "edited by a human"
  run bash -c "git -C '$PROJECT_DIR' status --porcelain | grep -v '\.scratch/'"
  assert_output_contains "?? wip.txt"
  assert_output_contains "M CONTEXT.md"

  # The tracker was committed mid-claim by that same session. Rolling the commit
  # back must not roll the loop's own marking back with it.
  assert_ticket_status 01-alpha ready-for-agent
}

@test "an iteration never touches work nobody in this run made" {
  # This used to be "a rollback is not a reset --hard", and since [13] it proves
  # something else — still true, and stronger. A human's uncommitted work is not
  # spared by a narrow rollback any more; it is simply not in the tree the
  # iteration runs in. What keeps the name is the lib-level test further down,
  # where the width of the rollback is still visible.

  use_tickets 01-alpha
  set_config STERILE_K 1

  # Someone's work in progress: an untracked file and an uncommitted edit. A
  # blanket `git reset --hard` plus `git clean -fd` would delete both.
  mkdir -p "$PROJECT_DIR/src"
  printf 'mine\n' >"$PROJECT_DIR/wip.txt"
  printf 'edited by a human\n' >>"$PROJECT_DIR/CONTEXT.md"

  script_session_writing src/alpha.txt src/rogue.txt

  run_loop
  assert_failure 4

  assert_file_contains "$PROJECT_DIR/wip.txt" "mine"
  assert_file_contains "$PROJECT_DIR/CONTEXT.md" "edited by a human"
  refute_file_exists "$PROJECT_DIR/src/rogue.txt"
}

@test "a file the session deleted comes back" {
  use_tickets 01-alpha
  set_config STERILE_K 1

  script_claude <<'FAKE'
#!/usr/bin/env bash
rm -f CONTEXT.md
printf 'written\n' >rogue.txt
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_failure 4
  assert_file_contains "$PROJECT_DIR/CONTEXT.md" "Fixture context for the harness"
  assert_equal "$(worktree_dirt)" ""
}

# ── the rollback, driven as a lib ────────────────────────────────────────────
#
# Four mutations went VACUOUS here the day [13] landed, and they were right. An
# iteration rolls back inside a worktree that is thrown away straight afterwards,
# so a loop-level test that asserts `refute_file_exists "$PROJECT_DIR/…"` is
# asserting something that is true whether the rollback ran or not — the tree the
# run was started in never had the file. What those tests still prove is worth
# keeping (the ticket, the retries, the lines the run printed); what they stopped
# proving is proved here, on the primitive, in a tree where the effect is visible.
#
# Driven with no pre-session commit (`pre` empty), so HEAD is left alone: what is
# under test is the tree half. The commit half has its own test above.

# The state a failed session leaves, staged the way an agent interrupted mid-commit
# leaves it, plus a file nobody in this run made. Prints the pre-session tree so a
# test can hand it back.
failures__stage_a_failed_session() {
  pack_run '
    cd "$(ralph_project_root)"
    printf "human work\n" >untracked-by-nobody.txt
    printf "%s\n" "$(gate_tree_snapshot)" >.base
    mkdir -p src
    printf "written\n" >src/added.txt
    printf "edited\n" >>CONTEXT.md
    rm -f README-fixture.txt
    git add -A >/dev/null 2>&1
    printf "%s\n" "$(gate_tree_snapshot)" >.now
  '
}

@test "the rollback removes what the session added and brings back what it deleted" {
  use_tickets 01-alpha
  printf 'a file the run did not make\n' >"$PROJECT_DIR/README-fixture.txt"
  harness__commit "test: a tracked file for the session to delete"

  failures__stage_a_failed_session
  assert_success
  assert_file_exists "$PROJECT_DIR/src/added.txt"
  refute_file_exists "$PROJECT_DIR/README-fixture.txt"

  pack_run '
    cd "$(ralph_project_root)"
    failures_rollback "" "$(cat .base)" "$(cat .now)"
  '
  assert_success
  assert_output_contains "rolled back"

  refute_file_exists "$PROJECT_DIR/src/added.txt"
  assert_file_contains "$PROJECT_DIR/README-fixture.txt" "a file the run did not make"
  refute_file_contains "$PROJECT_DIR/CONTEXT.md" "edited"
}

@test "the rollback unstages what it put back, and only those paths" {
  use_tickets 01-alpha
  printf 'a file the run did not make\n' >"$PROJECT_DIR/README-fixture.txt"
  harness__commit "test: a tracked file for the session to delete"

  failures__stage_a_failed_session
  assert_success
  pack_run '
    cd "$(ralph_project_root)"
    failures_rollback "" "$(cat .base)" "$(cat .now)"
  '
  assert_success

  # Undoing the files without unstaging them would leave the attempt sitting in
  # the index, ready to ride along with the next commit.
  run bash -c "git -C '$PROJECT_DIR' diff --cached --name-only"
  refute_output_contains "src/added.txt"
  refute_output_contains "CONTEXT.md"
  refute_output_contains "README-fixture.txt"
}

# ── names git does not print as themselves ([39]) ────────────────────────────

@test "the rollback really removes a name outside pure ASCII, and unstages it" {
  # `git diff-tree --name-status` C-quoted the name, so the restore ran
  # `rm -f '"docs/sp\303\251cification.md"'` — which removes nothing, says nothing,
  # and returns success — and then printed the path as one it had put back. The
  # rollback counted it, the "could not undo" line netted it out, and the file was
  # still in the tree for the next session to inherit.
  #
  # Asserted on the tree and on the index, because those are the two things the
  # rollback promises: a run that came back to where the session found it.
  use_tickets 01-alpha
  pack_run '
    cd "$(ralph_project_root)"
    printf "%s\n" "$(gate_tree_snapshot)" >.base
    mkdir -p docs
    printf "contenu\n" >docs/spécification.md
    git add -A >/dev/null 2>&1
    printf "%s\n" "$(gate_tree_snapshot)" >.now
  '
  assert_success
  assert_file_exists "$PROJECT_DIR/docs/spécification.md"

  pack_run '
    cd "$(ralph_project_root)"
    failures_rollback "" "$(cat .base)" "$(cat .now)"
  '
  assert_success
  assert_output_contains "rolled back"

  refute_file_exists "$PROJECT_DIR/docs/spécification.md"
  run bash -c "git -C '$PROJECT_DIR' diff --cached --name-only"
  refute_output_contains "spécification"
}

@test "a name nothing can address is not reported as one this rollback put back" {
  # The residue `core.quotePath=false` does not take out of the quoted set: a tab
  # in a file name. Nothing here can act on that string, and the property is that
  # the restore says so rather than printing it in the list of paths it put back —
  # an intention rendered for a result ([30]).
  #
  # Driven the way the rollback drives it, through a command substitution, because
  # that is where the second half of this lives: the admission goes to stderr, and
  # a `could not put back` printed on stdout would land in the list as though it
  # were a path that had been restored.
  use_tickets 01-alpha
  pack_run 'cd "$(ralph_project_root)"; gate_tree_snapshot'
  assert_success
  local base="$output"

  mkdir -p "$PROJECT_DIR/docs"
  printf 'written\n' >"$PROJECT_DIR/$(printf 'docs/a\tb.md')"

  pack_run "
    cd \"\$(ralph_project_root)\"
    restored=\"\$(gate_restore_tree '$base' \"\$(gate_tree_snapshot)\")\"
    printf 'restored=[%s]\n' \"\$restored\""
  assert_success
  assert_output_contains "restored=[]"
  assert_output_contains "could not put back"
}

@test "the unstaging survives a path whose name carries a space" {
  # [33] converted every list in the pack to one path per line and this caller was
  # missed: the rollback joined the restored paths back into one whitespace word
  # for `git reset -- $paths`, so `src/my file.txt` became two pathspecs matching
  # nothing and the file stayed staged, ready to ride along with the next commit —
  # under a `|| true`, and with `rolled back 2 path(s)` printed over it.
  #
  # The neighbour is asserted too, and its verdict is the *unchanged* half: probed
  # against the pre-fix code, `git reset` leaves a pathspec that matches nothing
  # alone and unstages the rest, unlike `git add`, which refuses the whole call.
  # So this asserts the repair did not trade one silent loss for another.
  use_tickets 01-alpha
  pack_run '
    cd "$(ralph_project_root)"
    printf "%s\n" "$(gate_tree_snapshot)" >.base
    mkdir -p src
    printf "written\n" >"src/my file.txt"
    printf "written\n" >src/added.txt
    git add -A >/dev/null 2>&1
    printf "%s\n" "$(gate_tree_snapshot)" >.now
  '
  assert_success

  pack_run '
    cd "$(ralph_project_root)"
    failures_rollback "" "$(cat .base)" "$(cat .now)"
  '
  assert_success

  run bash -c "git -C '$PROJECT_DIR' diff --cached --name-only"
  refute_output_contains "my file.txt"
  refute_output_contains "src/added.txt"
}

@test "a green iteration commits a file whose name is not ASCII" {
  # `failures_make_durable` built its commit with `git add -A -- $changed`, and
  # git refuses the C-quoted string exactly as `rm` does. The scope-guard approved
  # the file, the ticket went `resolved`, and the work was not in the history —
  # silently, because that `git add` is under a `|| true` written for a path the
  # session had deleted out of a tree that was never committed.
  use_tickets 01-alpha
  perl -pi -e \
    's|^\*\*Write-surface:\*\* .*|**Write-surface:** `src/alpha.txt`, `docs/spécification.md`|' \
    "$(ticket_file 01-alpha)"
  harness__commit "test: a ticket that declares a name outside pure ASCII"

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src docs
printf 'written\n' >src/alpha.txt
printf 'contenu\n' >docs/spécification.md
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_success
  assert_ticket_status 01-alpha resolved

  # In the history, not merely in the tree: an uncommitted file is what the next
  # rollback takes away, and what this ticket exists to stop losing.
  # `core.quotePath=false` on the assertion too: git quotes the name for *this*
  # reader as readily as it did for the pack, and an assertion on the quoted form
  # would pass on the very defect this test covers.
  run git -C "$PROJECT_DIR" -c core.quotePath=false ls-tree -r --name-only HEAD
  assert_output_contains "docs/spécification.md"
  assert_equal "$(worktree_dirt)" ""
}

@test "a green iteration commits a path whose name carries a space" {
  # The same list, cut the other way, and the worst of the three ([33], found still
  # standing here by [39]). `git add -A -- $changed` word-split `src/my file.txt`
  # into `src/my` and `file.txt`; `git add` refuses the *whole* call when one
  # pathspec matches nothing — unlike `git reset`, probed — so nothing at all was
  # staged, the rebuilt tree equalled HEAD's, the "everything approved is already
  # in HEAD" early return fired, and the iteration went `resolved` with not one of
  # its files committed and not one line about it.
  #
  # The neighbour is asserted for that reason: this is not a test about odd names,
  # it is a test about one bad pathspec taking the whole delivery with it.
  use_tickets 01-alpha
  perl -pi -e 's|^\*\*Write-surface:\*\* .*|**Write-surface:** `src/*`|' \
    "$(ticket_file 01-alpha)"
  harness__commit "test: a ticket whose surface covers a name with a space"

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src
printf 'written\n' >src/alpha.txt
printf 'written\n' >"src/my file.txt"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_success
  assert_ticket_status 01-alpha resolved

  run git -C "$PROJECT_DIR" ls-tree -r --name-only HEAD
  assert_output_contains "src/my file.txt"
  assert_output_contains "src/alpha.txt"
  # And the real index came back with them: the block that restages the same paths
  # cut the list the same way, so a staged deletion used to be left sitting there.
  assert_equal "$(worktree_dirt)" ""
}

@test "the durable commit leaves no staged reversal, a name with a space included" {
  # The twin of the test above, and it has to be driven at the module rather than
  # through the loop — which is the finding, not a convenience. Since [13] the
  # durable commit runs in a throwaway worktree, so the index it puts back is
  # thrown away with it and no end-to-end assertion can see this line at all: the
  # first version of its mutation entry came back VACUOUS against the full-loop
  # test, which was measuring `concurrency__refresh` instead.
  #
  # What it holds is real all the same: `failures_make_durable` commits with an
  # index of its own, so the caller's index still describes the state from before
  # the commit — a staged deletion of every path just delivered, waiting to ride
  # along with the next commit somebody makes. It restages the same list, and it
  # used to cut that list into words.
  use_tickets 01-alpha
  pack_run '
    cd "$(ralph_project_root)"
    pre="$(git rev-parse HEAD)"
    base="$(gate_tree_snapshot)"
    mkdir -p src
    printf "written\n" >"src/my file.txt"
    failures_make_durable 01-alpha "$pre" "$base" "$(gate_tree_snapshot)"'
  assert_success
  assert_output_contains "committed"

  run bash -c "git -C '$PROJECT_DIR' ls-tree -r --name-only HEAD"
  assert_output_contains "src/my file.txt"
  run bash -c "git -C '$PROJECT_DIR' diff --cached --name-only"
  assert_equal "$output" ""
}

@test "the durable commit leaves no staged reversal on an ignored guarded path" {
  # The twin of the test above, on the family [50] added to what this commit
  # carries, and it has to be driven at the module for the reason that one gives:
  # since [13] the durable commit runs in a throwaway worktree, so the index it puts
  # back goes with the worktree and no end-to-end assertion can see this line.
  #
  # The two halves are one decision. The commit now forces an ignored path in; an
  # index that could not take the same path would describe that very path as
  # *deleted* — the exact state this block exists to prevent, reintroduced by
  # repairing the other end.
  use_tickets 01-alpha
  set_config GUARDED_PATHS "vendor"
  printf 'vendor/\n' >>"$PROJECT_DIR/.gitignore"
  harness__commit "test: the project ignores its own guarded directory"

  pack_run '
    cd "$(ralph_project_root)"
    pre="$(git rev-parse HEAD)"
    base="$(gate_tree_snapshot)"
    mkdir -p vendor
    printf "written\n" >vendor/thing
    failures_make_durable 01-alpha "$pre" "$base" "$(gate_tree_snapshot)"'
  assert_success
  assert_output_contains "committed"

  run bash -c "git -C '$PROJECT_DIR' ls-tree -r --name-only HEAD"
  assert_output_contains "vendor/thing"
  run bash -c "git -C '$PROJECT_DIR' diff --cached --name-only"
  assert_equal "$output" ""
}

@test "a guarded path the project ignores reaches the history" {
  # The decision [50] took, on the case that opened it. A project that gitignores a
  # directory its own GUARDED_PATHS names: the snapshot forces that directory into
  # the judged tree ([24]), the scope-guard approves the file, and `git add` without
  # `-f` refuses an ignored path. The iteration used to go `resolved` with the work
  # absent from the history — named since [39], committed since this ticket.
  #
  # Held here rather than in a comment: the durable commit stages through the same
  # lens the tree was judged through. Anything else leaves an iteration that is
  # green, marked, and empty, which is this pack's own definition of a false
  # delivered ([35]).
  use_tickets 01-alpha
  set_config GUARDED_PATHS "vendor"
  # Written here rather than through gate.bats's `ignore_paths`: the fixture
  # project deliberately has no `.gitignore`, and each test writes the rule it
  # means.
  printf 'vendor/\n' >>"$PROJECT_DIR/.gitignore"
  harness__commit "test: the project ignores its own guarded directory"
  perl -pi -e \
    's|^\*\*Write-surface:\*\* .*|**Write-surface:** `src/alpha.txt`, `vendor/*`|' \
    "$(ticket_file 01-alpha)"
  harness__commit "test: a ticket that declares a guarded, ignored directory"
  script_session_writing src/alpha.txt vendor/thing

  run_loop
  assert_success
  assert_ticket_status 01-alpha resolved
  # And not merely named on the way past: the gap line of [39] is about work that
  # did not make it, so it has nothing to say about this path any more.
  refute_output_contains "vendor/thing was approved by the gate and could not be staged"

  run git -C "$PROJECT_DIR" ls-tree -r --name-only HEAD
  assert_output_contains "vendor/thing"
  # The neighbour, because one path git refused used to take every other path out
  # of the commit with it ([39]) — a single `git add` fails the whole call.
  assert_output_contains "src/alpha.txt"
  assert_equal "$(worktree_dirt)" ""
}

@test "a file the session wrote and then hid by its own rule reaches the history" {
  # The third forcing, and the one that is not the project's doing ([30]): what a
  # `.gitignore` written *during* the iteration took out of sight is forced into the
  # judged tree too, so that a session cannot widen the blind spot it is judged
  # through. Symmetrically, since [50], it cannot change what its iteration commits
  # by writing an ignore rule either — without the force this was a false delivered
  # any session could buy in two lines, and a more deliberate one than the guarded
  # case above.
  #
  # The rule itself is committed, which is the ordinary git answer and worth
  # asserting: a tracked path is not affected by a later ignore rule, so the project
  # keeps both the file and the rule it wrote about future ones.
  use_tickets 01-alpha
  perl -pi -e \
    's|^\*\*Write-surface:\*\* .*|**Write-surface:** `build/*`, `.gitignore`|' \
    "$(ticket_file 01-alpha)"
  harness__commit "test: a ticket that delivers into a directory it then ignores"

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p build
printf 'built\n' >build/out.txt
printf 'build/\n' >>.gitignore
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_success
  assert_ticket_status 01-alpha resolved

  run git -C "$PROJECT_DIR" ls-tree -r --name-only HEAD
  assert_output_contains "build/out.txt"
  assert_output_contains ".gitignore"
}

@test "a path the gate approved and git would not stage is named, not dropped" {
  # What [39] holds, kept after [50] took the force away from its loudest case. The
  # property is not "everything approved is committed", which this pack cannot
  # promise — git has reasons of its own to refuse and every one lands under a
  # `|| true`: it is that a path which was approved and did not make it into the
  # commit is *named*, exactly as the rollback names what it could not put back.
  #
  # Driven at the module, and the reason is the one the twin above carries: the
  # trigger has to sit between the tree the gate judged and the commit, which is a
  # window no full-loop test can reach into. A file the run cannot read is what is
  # left once the ignore rules are forced through — `git add` fails on the open(),
  # and the work is not in the commit.
  use_tickets 01-alpha
  pack_run '
    cd "$(ralph_project_root)"
    pre="$(git rev-parse HEAD)"
    base="$(gate_tree_snapshot)"
    mkdir -p src
    printf "written\n" >src/alpha.txt
    printf "written\n" >src/beta.txt
    tree="$(gate_tree_snapshot)"
    chmod 000 src/alpha.txt
    failures_make_durable 01-alpha "$pre" "$base" "$tree" || printf "(refused)\n"
    chmod 644 src/alpha.txt'
  assert_output_contains "src/alpha.txt was approved by the gate and could not be staged"

  # And the neighbour goes in all the same, for the reason [39] wrote this loop one
  # path at a time.
  run bash -c "git -C '$PROJECT_DIR' ls-tree -r --name-only HEAD"
  assert_output_contains "src/beta.txt"
  refute_output_contains "src/alpha.txt"
}

@test "a path the session deleted is not accused of not being staged" {
  # The other half of the same line, and the reason its status is not read alone
  # ([39] said so and [50] kept it): a path the session deleted out of a tree that
  # was never committed makes `git add` refuse the pathspec — it matches nothing —
  # while nothing whatsoever was lost. Reading the refusal as a finding would put a
  # gap line on every iteration that removes a file it had only ever written into an
  # uncommitted tree.
  use_tickets 01-alpha
  pack_run '
    cd "$(ralph_project_root)"
    pre="$(git rev-parse HEAD)"
    mkdir -p src
    printf "written\n" >src/alpha.txt
    base="$(gate_tree_snapshot)"
    rm -f src/alpha.txt
    printf "written\n" >src/beta.txt
    failures_make_durable 01-alpha "$pre" "$base" "$(gate_tree_snapshot)"'
  assert_success
  assert_output_contains "committed"
  refute_output_contains "could not be staged"
}

@test "a delivered file the suite rewrote after the gate is not accused either" {
  # And the half that answers the other way ([50]). `TEST_CMD` runs after the tree
  # was judged, so a delivered file it rewrites differs from the judged tree while
  # sitting in this commit with newer bytes. Read on the result alone, that is
  # indistinguishable from work git refused — and it is not the same finding at all:
  # the work is in the history, the tree simply moved, and `gate_unjudged_changes`
  # already names that every iteration. This line accuses git, so it asks git.
  use_tickets 01-alpha
  pack_run '
    cd "$(ralph_project_root)"
    pre="$(git rev-parse HEAD)"
    base="$(gate_tree_snapshot)"
    mkdir -p src
    printf "written\n" >src/alpha.txt
    tree="$(gate_tree_snapshot)"
    printf "rewritten by the suite\n" >src/alpha.txt
    failures_make_durable 01-alpha "$pre" "$base" "$tree"'
  assert_success
  refute_output_contains "could not be staged"

  run bash -c "git -C '$PROJECT_DIR' show HEAD:src/alpha.txt"
  assert_output_contains "rewritten by the suite"
}

@test "a rollback is not a reset --hard: work nobody in this run made stands" {
  # The whole reason the rollback is exactly as wide as the session's diff. A
  # `git reset --hard` plus `git clean -fd` is the obvious implementation and it
  # takes a human's uncommitted work down with the failed attempt.
  use_tickets 01-alpha
  printf 'a file the run did not make\n' >"$PROJECT_DIR/README-fixture.txt"
  harness__commit "test: a tracked file for the session to delete"

  failures__stage_a_failed_session
  assert_success
  pack_run '
    cd "$(ralph_project_root)"
    failures_rollback "" "$(cat .base)" "$(cat .now)"
  '
  assert_success

  # It was there before the session, it is not in the session's diff, and it is
  # still there. `git clean -fd` would have taken it.
  assert_file_contains "$PROJECT_DIR/untracked-by-nobody.txt" "human work"
}

@test "a ticket the loop wrote itself is left alone by the guard" {
  # [21] restores every ticket that moved around a session, which is exactly right
  # while one iteration is in flight and destroys a sibling's claim the moment two
  # are ([13]). The loop keeps a register of the paths it wrote itself, and the
  # guard skips them.
  #
  # Driven as a lib rather than through a parallel run, and that is the finding
  # rather than convenience: through the loop the defect only shows when the pilot
  # claims the sibling *after* the first iteration snapshotted the tickets, which
  # is a handful of command substitutions apart and flips under load. Here the
  # order is the test's to choose.
  use_tickets 01-alpha 02-beta

  pack_run '
    cd "$(ralph_project_root)"
    RALPH_TRACKER_LOG="$(mktemp "${TMPDIR:-/tmp}/ralph-slot.writes.XXXXXX")"
    export RALPH_TRACKER_LOG
    before="$(failures_tracker_tree)"
    mark="$(tracker_write_mark)"
    # What the loop legitimately does inside another iteration'"'"'s window: it
    # claims a sibling. And what a session does, which nothing may keep: it edits
    # the ticket it was handed.
    tracker_claim 02-beta "pid:$$"
    perl -pi -e "s/^\\*\\*Write-surface:\\*\\* .*/**Write-surface:** \`*\`/" \
      "$(ralph_feature_dir)/issues/01-alpha.md"
    failures_protect_tracker 01-alpha "$before" "$mark" || printf "guard-refused\n"
    rm -f "$RALPH_TRACKER_LOG"
  '
  assert_output_contains "guard-refused"

  # The sibling'"'"'s claim stands: the loop wrote it, so it is not the session'"'"'s doing.
  assert_ticket_status 02-beta claimed
  # And the session's own edit is gone, which is what the guard is for.
  assert_equal "$(ticket_field 01-alpha Write-surface)" '`src/alpha.txt`'
}

@test "a ticket the loop created itself is left alone by the quarantine" {
  # The second reader of that register, and it had none until [42]: the quarantine
  # compares *ids*, so the children a sibling's re-slice creates are ids that were
  # not there when this session started — indistinguishable, without the register,
  # from a ticket a session gave itself.
  #
  # Driven as a lib for the reason the test above is: through the loop the two
  # writes have to land inside one another's window, which is a matter of
  # milliseconds; here the order is the test's to choose.
  use_tickets 01-alpha
  pack_run '
    cd "$(ralph_project_root)"
    RALPH_TRACKER_LOG="$(mktemp "${TMPDIR:-/tmp}/ralph-slot.writes.XXXXXX")"
    mark="$(tracker_write_mark)"
    seen="$(failures_tracker_snapshot)"
    # What the loop legitimately does inside another iteration'"'"'s window: a
    # sibling re-slice puts its children on the frontier.
    printf "**Write-surface:** \`src/child.txt\`\n\n- [ ] it exists\n" |
      tracker_open_ticket child "A child of a re-slice" >/dev/null
    # And what a session does, which no register may excuse: it writes itself a
    # ticket, with the surface it would like to be judged against.
    printf "**Write-surface:** \`*\`\n\n**Status:** ready-for-agent\n" \
      >"$(ralph_feature_dir)/issues/99-invented.md"
    failures_quarantine_strays 01-alpha "$seen" "$mark" || printf "quarantined\n"
    printf "register:%s\n" "$(tracker_writes_since "$mark")"
    rm -f "$RALPH_TRACKER_LOG"
  '
  assert_output_contains "quarantined"

  # The register names the ticket the creation *produced*, not the slug it was
  # handed: a line reading `child` names no ticket, and every reader of this
  # register asks about ids. One id per line since [37].
  assert_output_contains "register:02-child"

  # The loop's own creation went to the frontier; the session's went to a human.
  assert_ticket_status 02-child ready-for-agent
  assert_ticket_status 99-invented ready-for-human
  # And the note names only what that session really wrote.
  assert_file_contains "$(ticket_file 01-alpha)" "99-invented"
  refute_file_contains "$(ticket_file 01-alpha)" "02-child"
}

@test "without the register, the same two tickets are both quarantined" {
  # The paired witness [42] asks for. Without it the test above says nothing about
  # whether the exemption did anything: one guard call away, both tickets are
  # strays and both are escalated — which is exactly what the loop did to its own
  # re-slices before this ticket.
  use_tickets 01-alpha
  pack_run '
    cd "$(ralph_project_root)"
    RALPH_TRACKER_LOG="$(mktemp "${TMPDIR:-/tmp}/ralph-slot.writes.XXXXXX")"
    seen="$(failures_tracker_snapshot)"
    printf "**Write-surface:** \`src/child.txt\`\n\n- [ ] it exists\n" |
      tracker_open_ticket child "A child of a re-slice" >/dev/null
    printf "**Write-surface:** \`*\`\n\n**Status:** ready-for-agent\n" \
      >"$(ralph_feature_dir)/issues/99-invented.md"
    failures_quarantine_strays 01-alpha "$seen" || printf "quarantined\n"
    rm -f "$RALPH_TRACKER_LOG"
  '
  assert_output_contains "quarantined"
  assert_ticket_status 02-child ready-for-human
  assert_ticket_status 99-invented ready-for-human
}

# ── an id is the name of a file somebody chose ───────────────────────────────
#
# [37]. Every list the pack hands itself has travelled one entry per line since
# [33], and the tracker's ids were the exception: `for id in $(tracker_ids)`, and
# a snapshot rendered as ` a b `. An id is not data this pack owns — it is the
# name of a file a session writes into `issues/`, which is the corollary [27]
# wrote about the *number* applied to the *splitting*.

@test "a ticket whose name carries a space is one stray, not two ghosts" {
  # Split on words, `99-my ticket` was two ids no ticket carries: the renumber
  # refused both by name, the escalation marked neither, and the loop logged
  # `quarantined 99-my ticket` — the two ghosts run together — over a ticket left
  # sitting on the frontier with the write-surface the session gave itself. The
  # control that announced having acted was the one that had not.
  use_tickets 01-alpha
  pack_run '
    seen="$(failures_tracker_snapshot)"
    printf "**Status:** ready-for-agent\n\n**Blocked by:** None\n\n**Write-surface:** \`*\`\n" \
      >"$(ralph_feature_dir)/issues/99-my ticket.md"
    printf "strays[%s]\n" "$(failures__strays "$seen" | tr "\n" "|")"
    failures_quarantine_strays 01-alpha "$seen" || printf "quarantined\n"
  '
  assert_output_contains "quarantined"
  # One stray, and it is the ticket — not `99-my`, and not `ticket`. The whole
  # list, so an implementation that found it *among* two ghosts is red here too.
  assert_output_contains "strays[99-my ticket|]"

  # What the quarantine is for, under the name the file really has.
  assert_ticket_status "99-my ticket" ready-for-human
  assert_equal "$(ticket_field "99-my ticket" Escalation)" "decision"
  # And the note a human reads names it, rather than a ticket called `99-my`.
  assert_file_contains "$(ticket_file 01-alpha)" "99-my ticket"
}

@test "the same ticket without the space ends exactly the same way" {
  # The paired witness. Without it the test above says nothing about the space —
  # it would pass on any implementation that quarantines something at all. This is
  # the same scenario minus the one character, and it was green before [37] too,
  # so the two together say that the space is what used to change the answer.
  use_tickets 01-alpha
  pack_run '
    seen="$(failures_tracker_snapshot)"
    printf "**Status:** ready-for-agent\n\n**Blocked by:** None\n\n**Write-surface:** \`*\`\n" \
      >"$(ralph_feature_dir)/issues/99-myticket.md"
    printf "strays[%s]\n" "$(failures__strays "$seen" | tr "\n" "|")"
    failures_quarantine_strays 01-alpha "$seen" || printf "quarantined\n"
  '
  assert_output_contains "quarantined"
  assert_output_contains "strays[99-myticket|]"
  assert_ticket_status 99-myticket ready-for-human
  assert_equal "$(ticket_field 99-myticket Escalation)" "decision"
}

@test "a ticket whose name carries a glob metacharacter is read literally" {
  # The other half of the same expansion, and it needs its own test: an unquoted
  # `$(tracker_ids)` is glob-expanded against the *current directory*, so
  # `99-a[0]` was replaced by whatever happened to be lying beside the run. The
  # quarantine then escalated an id nothing carries and left the real ticket on
  # the frontier — the same false green, reached by the other door.
  use_tickets 01-alpha
  pack_run '
    : >"99-a0"
    seen="$(failures_tracker_snapshot)"
    printf "**Status:** ready-for-agent\n\n**Blocked by:** None\n\n**Write-surface:** \`*\`\n" \
      >"$(ralph_feature_dir)/issues/99-a[0].md"
    printf "strays[%s]\n" "$(failures__strays "$seen" | tr "\n" "|")"
    failures_quarantine_strays 01-alpha "$seen" || printf "quarantined\n"
  '
  assert_output_contains "quarantined"
  assert_output_contains "strays[99-a[0]|]"
  assert_ticket_status "99-a[0]" ready-for-human
}

@test "a register naming one id does not exempt a stray that shares a word with it" {
  # [42] exempts what the loop itself created inside the window, by id. Rendered
  # as a fence of words, that exemption answered for every *word* of an id: the
  # loop opening `02-my child.md` put ` 02-my child ` in the fence, and a session
  # writing itself `02-my.md` matched it. Quarantine bypassed, on a ticket
  # carrying the write-surface the session chose — which is precisely what this
  # guard exists to refuse.
  use_tickets 01-alpha
  pack_run '
    cd "$(ralph_project_root)"
    RALPH_TRACKER_LOG="$(mktemp "${TMPDIR:-/tmp}/ralph-slot.writes.XXXXXX")"
    : >"$RALPH_TRACKER_LOG"
    seen="$(failures_tracker_snapshot)"
    mark="$(tracker_write_mark)"
    # What the loop wrote in the window, under a name a human may well give a
    # ticket — and what a session then wrote for itself beside it.
    printf "02-my child\n" >>"$RALPH_TRACKER_LOG"
    printf "# 02 — loop\n\n**Status:** ready-for-agent\n\n**Blocked by:** None\n" \
      >"$(ralph_feature_dir)/issues/02-my child.md"
    printf "# 02 — session\n\n**Status:** ready-for-agent\n\n**Blocked by:** None\n\n**Write-surface:** \`*\`\n" \
      >"$(ralph_feature_dir)/issues/02-my.md"
    failures_quarantine_strays 01-alpha "$seen" "$mark" || printf "quarantined\n"
    rm -f "$RALPH_TRACKER_LOG"
  '
  assert_output_contains "quarantined"
  # The loop's own creation is left alone — that is [42], and it still holds.
  assert_ticket_status "02-my child" ready-for-agent
  # And what the session wrote is not, whatever word it shares with it.
  assert_output_contains "renumbered 02-my -> 03-my"
  assert_ticket_status 03-my ready-for-human
  refute_file_exists "$(ticket_file 02-my)"
}

@test "a rollback never restores the tracker, whatever moved in it" {
  use_tickets 01-alpha

  # Driven directly, because the loop takes its post-session snapshot before it
  # writes the retry counter: at the process seam the tracker never even shows up
  # in the rollback's diff, so the exclusion looks free until the day something
  # writes the tracker earlier. What it protects is that counter — restore the
  # ticket from the pre-session snapshot and `Failures:` goes back to nothing,
  # which means no ticket is ever escalated again.
  pack_run '
    base="$(gate_tree_snapshot)"
    printf "stray\n" >stray.txt
    tracker_bump_failures 01-alpha >/dev/null
    tree="$(gate_tree_snapshot)"
    failures_rollback "" "$base" "$tree" >/dev/null
    printf "stray=%s failures=%s\n" \
      "$([ -f stray.txt ] && echo yes || echo no)" \
      "$(tracker_field 01-alpha Failures)"'
  assert_success
  assert_equal "$output" "stray=no failures=1"
}

@test "the rollback names the ignored paths it could not undo" {
  # "The tree is back where the session found it" was true except for a set of
  # paths nobody enumerated — everything this project's `.gitignore` covers. The
  # rollback cannot reach them: it diffs git trees, and they are not in either
  # one. So it says so, and this test holds both halves — the claim, and the fact
  # that the file really is still lying there.
  use_tickets 01-alpha
  set_config STERILE_K 1
  printf 'cache/\n' >>"$PROJECT_DIR/.gitignore"
  harness__commit "test: the project ignores a build cache"

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src cache
printf 'written\n' >src/alpha.txt
printf 'written\n' >src/rogue.txt
printf 'payload\n' >cache/payload
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_failure 4

  assert_output_contains "this rollback could not undo"
  assert_output_contains "cache/"
  # Named inside the iteration and gone with its worktree since [13]: the line
  # above is the guarantee — a rollback that says "the tree is back" while an
  # unenumerated set of paths is exempt — and what changed is only that the
  # exemption no longer outlives the iteration that made it.
  refute_file_exists "$PROJECT_DIR/cache/payload"
  # What it could see is undone, as before.
  refute_file_exists "$PROJECT_DIR/src/rogue.txt"
  refute_file_exists "$PROJECT_DIR/src/alpha.txt"
}

@test "a rollback with nothing to undo names the zone all the same" {
  # The probe that opened [24], second of three: a session whose only write is an
  # ignored file. The rollback finds nothing in its diff — the honest reading of
  # which is not silence, because the file is still there. A report tied to
  # "something was undone" would say nothing in exactly the case where the tree is
  # *not* back where the session found it.
  use_tickets 01-alpha
  set_config STERILE_K 1
  stub_exit tests 1
  printf 'cache/\n' >>"$PROJECT_DIR/.gitignore"
  harness__commit "test: the project ignores a build cache"

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p cache && printf 'payload\n' >cache/payload
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_failure 4

  refute_output_contains "rolled back"
  assert_output_contains "this rollback could not undo"
  assert_output_contains "cache/"
  # Named inside the iteration and gone with its worktree since [13]: the line
  # above is the guarantee — a rollback that says "the tree is back" while an
  # unenumerated set of paths is exempt — and what changed is only that the
  # exemption no longer outlives the iteration that made it.
  refute_file_exists "$PROJECT_DIR/cache/payload"
}

@test "the rollback names what the gate itself changed, and leaves it standing" {
  # The third exemption of a rollback that announces "the tree is back where the
  # session found it": the tracker it leaves on purpose, the ignored zone it cannot
  # see, and — since [29] — what the gate's own branches wrote after the tree it
  # judged was taken. That artefact is in neither of the two trees this function
  # diffs, and git does not ignore it, so [24]'s line does not name it either. A
  # suite that writes a report and then goes red is any real suite.
  use_tickets 01-alpha
  set_config STERILE_K 1
  # The suite writes the loop's own bookkeeping as well as its report, and that
  # second path is what keeps the filter honest: since [13] nothing else writes
  # under `.scratch/<feature>/` in the tree an iteration is judged on, so a gate
  # that had stopped dropping it would name it here and nowhere else.
  set_config TEST_CMD 'mkdir -p build .scratch/demo
printf report >build/coverage.xml
printf line >>.scratch/demo/run.log
exit 1'
  script_session_writing src/alpha.txt

  run_loop
  assert_failure 4

  assert_output_contains \
    "this rollback could not undo 1 path(s) the gate itself changed after the tree it judged: build/coverage.xml"
  # Named inside the iteration and gone with its worktree since [13]: the line
  # above is the guarantee — a rollback that says "the tree is back" while an
  # unenumerated set of paths is exempt — and what changed is only that the
  # exemption no longer outlives the iteration that made it.
  refute_file_exists "$PROJECT_DIR/build/coverage.xml"
  # What it could see is undone, as before.
  refute_file_exists "$PROJECT_DIR/src/alpha.txt"
}

@test "a path the rollback did put back is not named as one it could not" {
  # The lie in the other direction, which is the shape this suite has got wrong
  # before. A suite that rewrites a file the session had also touched — an updated
  # snapshot, a formatter, a code generator — differs from the judged tree just like
  # a fresh artefact does, but this rollback restores it from the pre-session
  # snapshot like any other path in its diff. Naming it would send a human looking
  # for something that is not there.
  use_tickets 01-alpha
  set_config STERILE_K 1
  set_config TEST_CMD 'printf suite >>src/alpha.txt; exit 1'
  script_session_writing src/alpha.txt

  run_loop
  assert_failure 4

  # Kept in a variable: the refutation has to be about this line and not about
  # whichever `run` happened last.
  local named
  named="$(printf '%s\n' "$output" | grep 'the gate itself changed' || true)"
  assert_equal "$named" ""
  refute_file_exists "$PROJECT_DIR/src/alpha.txt"
  assert_equal "$(worktree_dirt)" ""
}

@test "a rollback that cannot measure what the gate left says so, and does not go red" {
  # The fourth reader of the same primitive ([34]). This line is printed after a
  # rollback that has already happened, so there is nothing left to refuse — what it
  # owes is the difference between "there was nothing left" and "nobody knows what
  # was left". Driven directly: the instrument has to close *between* the trees the
  # rollback was handed and the report that comes after it, which is a window the
  # loop has no way to hand a test.
  use_tickets 01-alpha
  pack_run '
    base="$(gate_tree_snapshot)"
    printf "stray\n" >stray.txt
    tree="$(gate_tree_snapshot)"
    mkdir -p build && printf "report\n" >build/coverage.xml
    gate_tree_snapshot() { return 1; }
    failures_rollback "" "$base" "$tree"'
  # `assert_success` is the "does not go red" half: pack_run runs under `set -e`,
  # so a rollback that returned non-zero here would take the script down with it.
  assert_success
  assert_output_contains "this rollback could not check what the gate itself changed"

  # The witness: the same window with the instrument open names the artefact
  # instead. Without it this test would pass on a report that had simply stopped
  # counting.
  #
  # A different artefact, and it is not cosmetic: the two `pack_run` calls share one
  # project directory, and the first one's `build/coverage.xml` is still lying there
  # — it would be in this one's baseline, and a file that did not change is in no
  # diff, so the report would be silent for a reason that has nothing to do with
  # what is asserted here.
  pack_run '
    base="$(gate_tree_snapshot)"
    printf "stray\n" >stray.txt
    tree="$(gate_tree_snapshot)"
    mkdir -p build && printf "report\n" >build/witness.xml
    failures_rollback "" "$base" "$tree"'
  assert_success
  assert_output_contains \
    "this rollback could not undo 1 path(s) the gate itself changed after the tree it judged: build/witness.xml"
  refute_output_contains "could not check what the gate itself changed"
}

@test "a rollback that could not act stops the run instead of laundering it" {
  # Probe B of [34], end to end. Every fail-closed on the way works and none of
  # them is enough: the session writes out of its surface and destroys the pinned
  # ignore rules, so the snapshot refuses, the scope-guard refuses to pass a tree
  # it cannot read, and the rollback says out loud that it undid nothing. What
  # nothing stopped was the *next* iteration, which snapshots that tree as its own
  # pre-session baseline — after which `lib/rogue.sh` is nobody's change and the
  # ticket that inherits it goes green carrying it. One retry was the price [30]
  # wrote down; a laundered write is not.
  #
  # Two tickets on the frontier, which is what makes "the run stopped" mean
  # something: without the stop the loop goes straight on to 02-beta.
  use_tickets 01-alpha 02-beta

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src lib
printf 'written\n' >src/alpha.txt
printf 'rogue\n' >lib/rogue.sh
rm -rf "${TMPDIR:-/tmp}"/ralph-ignore.*
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop_own_tmp
  assert_failure 4
  assert_output_contains "cannot read the working tree — nothing was rolled back"
  assert_output_contains "stopping rather than grinding on an instrument that is already closed"

  # And the announcement of what the gate itself left behind says which of the two
  # it is. This one is not red and must not become one — it is printed on green
  # iterations too — but "this gate wrote nothing" and "nobody knows what this gate
  # wrote" are not the same line to read in the morning.
  assert_output_contains "this gate could not check what it changed after the tree it judged"

  # The out-of-surface write really is still there — that is what the run is
  # stopping *about*, and asserting the message alone would pass on a run that
  # stopped for any other reason.
  # It went with the worktree, which is what [13] closed here: the laundering
  # this stop exists to refuse cannot happen through an inherited tree any more.
  # The stop is kept all the same, and loop.sh says why — a rollback fails for
  # reasons that are not local to one tree, and the sibling beside it is about to
  # meet all of them.
  refute_file_exists "$PROJECT_DIR/lib/rogue.sh"

  # And the second ticket was never ground: one session, one iteration.
  assert_ticket_status 02-beta ready-for-agent
  assert_equal "$(claude_call_count)" "1"
}

@test "a rollback that could act lets the run carry on to the next ticket" {
  # The paired witness of the test above, and it carries two refutations at once.
  # Without it, a loop that stopped after every failed iteration — or a snapshot
  # that always refused — would pass there and nothing here would notice. The same
  # session, the same out-of-surface write, the pin left alone: rolled back, one
  # retry charged, and the run goes on.
  use_tickets 01-alpha 02-beta
  set_config RETRY_N 0

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src lib
printf 'written\n' >src/alpha.txt
printf 'rogue\n' >lib/rogue.sh
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop_own_tmp

  refute_output_contains "nothing was rolled back"
  refute_output_contains "stopping rather than letting the next iteration"
  refute_file_exists "$PROJECT_DIR/lib/rogue.sh"

  # 01-alpha is out of retries and escalated, so the loop moved on and ground
  # 02-beta with the same session — two calls, which is the whole point.
  assert_ticket_status 01-alpha ready-for-human
  assert_equal "$(claude_call_count)" "2"
}

# ── the ignore frontier, where no gate judged ────────────────────────────────
#
# [30] put `.git/info/exclude` and `core.excludesFile` back after every iteration
# that widened them, because the *next* iteration pins what it finds and would
# inherit the blindness as the project's own configuration. It put them back
# inside `gate_run` and inside the re-slice — and an iteration whose session
# crashed or was cut short goes through neither ([32]). The price for a session is
# a non-zero exit, which it controls.
#
# Every class of `failures_classify` is named by one test, here or elsewhere: a
# correction placed on the path that happened to be probed is exactly what [30]
# shipped. `crash` and `timeout` below; `too-big` in "the re-slice session cannot
# leave the ignore frontier widened"; `gate-red` and `nothing-delivered` in the
# two counting tests below, which is where `contract` rides too — it is a
# `gate-red` the scope-guard classified, judged by the same gate.

@test "a session that crashed cannot leave the ignore frontier widened" {
  # The probe of [32], in both halves. The first alone would pass on a correction
  # that puts the file back without anybody checking that putting it back counts
  # for anything — so what the *second* iteration inherits is asserted first.
  use_tickets 01-alpha
  set_config RETRY_N 1
  set_config STERILE_K 3

  script_claude <<'FAKE'
#!/usr/bin/env bash
cat >/dev/null
n="$(cat "$RALPH_SHIM_STATE/seq" 2>/dev/null || echo 0)"
n=$((n + 1)); printf '%s\n' "$n" >"$RALPH_SHIM_STATE/seq"
mkdir -p src rogue
printf 'written\n' >src/alpha.txt
if [ "$n" = 1 ]; then
  # A worktree answers `.git` with a *file*, so the naive `>>.git/info/exclude`
# writes nothing at all and this scenario would stage nothing while reading as
# green. The rule source git really reads is in the **common** git directory,
# which is what a session in any working tree of this repository would find,
# and what the pin looks at since [13].
printf 'rogue/\n' >>"$(git rev-parse --git-common-dir)/info/exclude"
  printf 'backdoor\n' >rogue/backdoor
  exit 1
fi
printf 'second\n' >rogue/second
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_success
  local loop_output="$output"

  # The half that matters, and the reason the restore exists at all: the second
  # session writes outside its surface behind the rule the first one wrote. Left
  # widened, `rogue/` is what this iteration pins, so nothing sees the write, the
  # gate is green and the ticket resolves carrying it.
  assert_output_contains "wrote rogue/second, outside the declared write-surface"
  refute_file_exists "$PROJECT_DIR/rogue/second"
  assert_ticket_status 01-alpha ready-for-human

  # And the half [30] already held, on a path it never reached.
  output="$loop_output"
  assert_output_contains "moved the ignore frontier in .git/info/exclude"
  assert_output_contains "(put back)"
  refute_file_contains "$PROJECT_DIR/.git/info/exclude" "rogue/"
  refute_file_exists "$PROJECT_DIR/rogue/backdoor"

  # Once for the whole run: the second iteration has nothing to put back, so a
  # second line here would mean the run is reporting a movement nobody made.
  run bash -c "grep -c 'moved the ignore frontier in .git/info/exclude' <<'OUT'
$loop_output
OUT"
  assert_equal "$output" "1"

  # And *on the iteration that had no gate*, which is the whole of this ticket and
  # which the assertions above stopped being able to tell since [41]. The shared
  # sources are witnessed once per **run** now, so the next iteration no longer
  # pins whatever the crashed session left: a run that had lost this restore would
  # still put the file back and still print this very line — one iteration late,
  # and billed to whichever ticket came next, which is [41]'s defect reached
  # through this ticket's door. The order is what distinguishes the two, so the
  # order is what is asserted.
  local put_back started
  put_back="$(printf '%s\n' "$loop_output" |
    grep -n 'moved the ignore frontier in .git/info/exclude' | head -1 | cut -d: -f1)"
  started="$(printf '%s\n' "$loop_output" |
    grep -n 'iteration 2: 01-alpha' | head -1 | cut -d: -f1)"
  if [ -z "$put_back" ] || [ -z "$started" ] || [ "$put_back" -ge "$started" ]; then
    fail "the frontier was put back at line ${put_back:-none}, and iteration 2 started at line ${started:-none} — it has to be the crashed iteration that puts it back
--- output ---
$loop_output"
  fi
}

@test "a session the loop cut short cannot leave it widened either" {
  # The other class with no caller, and the one that was two days old when [30]
  # was written ([23]). A hung session is killed, `claude` traps TERM and comes
  # back a success, and the iteration is never gated — same hole, different door.
  use_tickets 01-alpha
  set_config SESSION_STALL_TIMEOUT 2
  set_config STERILE_K 1

  script_claude <<'FAKE'
#!/usr/bin/env bash
cat >/dev/null
# A worktree answers `.git` with a *file*, so the naive `>>.git/info/exclude`
# writes nothing at all and this scenario would stage nothing while reading as
# green. The rule source git really reads is in the **common** git directory,
# which is what a session in any working tree of this repository would find,
# and what the pin looks at since [13].
printf 'rogue/\n' >>"$(git rev-parse --git-common-dir)/info/exclude"
mkdir -p rogue && printf 'backdoor\n' >rogue/backdoor
echo '{"type":"system","subtype":"init","session_id":"s"}'
echo '{"type":"assistant","message":{"role":"assistant","usage":{"input_tokens":10,"cache_read_input_tokens":9000,"output_tokens":5}}}'
i=0
while [ $i -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
exit 0
FAKE

  run_loop
  assert_failure 4
  assert_output_contains "hung, terminated"
  assert_output_contains "moved the ignore frontier in .git/info/exclude"
  assert_output_contains "(put back)"
  refute_file_contains "$PROJECT_DIR/.git/info/exclude" "rogue/"

  # What was written behind the rule goes with it: the rollback runs after the
  # restore, so it measures the tree through the rules the run was handed.
  refute_file_exists "$PROJECT_DIR/rogue/backdoor"
}

@test "an iteration a gate judged says the frontier moved once, not twice" {
  # The failure mode of the obvious correction: a restore at the head of
  # `failures_handle` covers the two missing classes and doubles the one path that
  # already had it. Two findings for one movement, and a line claiming no gate
  # judged an iteration a gate judged — the half-truth [29] refused, in the other
  # direction.
  #
  # Both sources are moved, and that is what makes this test able to fail. The
  # restore of `.git/info/exclude` is idempotent by construction — the second
  # caller finds it back where the pin says and reports nothing — so a doubled
  # call is invisible there. The tree's rules are never put back, on purpose, so
  # they are the one place a second speaker has something to say twice.
  use_tickets 01-alpha
  set_config STERILE_K 1
  stub_exit tests 1

  script_claude <<'FAKE'
#!/usr/bin/env bash
cat >/dev/null
# A worktree answers `.git` with a *file*, so the naive `>>.git/info/exclude`
# writes nothing at all and this scenario would stage nothing while reading as
# green. The rule source git really reads is in the **common** git directory,
# which is what a session in any working tree of this repository would find,
# and what the pin looks at since [13].
printf 'rogue/\n' >>"$(git rev-parse --git-common-dir)/info/exclude"
printf 'lib/\n' >>.gitignore
mkdir -p src && printf 'written\n' >src/alpha.txt
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_failure 4
  local loop_output="$output"

  assert_output_contains "tests=red"
  assert_output_contains "moved the ignore frontier in .git/info/exclude"
  refute_file_contains "$PROJECT_DIR/.git/info/exclude" "rogue/"

  # A gate ran, so the sentence a gateless path prints has no business here.
  output="$loop_output"
  refute_output_contains "no gate judged this iteration"

  run bash -c "grep -c 'moved the ignore frontier in .git/info/exclude' <<'OUT'
$loop_output
OUT"
  assert_equal "$output" "1"

  run bash -c "grep -c 'this session moved the ignore frontier: .gitignore' <<'OUT'
$loop_output
OUT"
  assert_equal "$output" "1"
}

@test "an iteration refused before the fan says it once too" {
  # The third printer, and the one that only exists since [35]: a delivery refusal
  # returns its verdict before a single branch starts, so there is no scope-guard
  # to carry the findings and `gate_run` prints them itself. A restore added in
  # `failures_handle` without looking would double this one as well.
  use_tickets 01-alpha
  set_config STERILE_K 1
  session_writes_nothing

  script_claude <<'FAKE'
#!/usr/bin/env bash
cat >/dev/null
# A worktree answers `.git` with a *file*, so the naive `>>.git/info/exclude`
# writes nothing at all and this scenario would stage nothing while reading as
# green. The rule source git really reads is in the **common** git directory,
# which is what a session in any working tree of this repository would find,
# and what the pin looks at since [13].
printf 'rogue/\n' >>"$(git rev-parse --git-common-dir)/info/exclude"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_failure 4
  local loop_output="$output"

  assert_output_contains "nothing was delivered"
  refute_file_contains "$PROJECT_DIR/.git/info/exclude" "rogue/"

  run bash -c "grep -c 'moved the ignore frontier in .git/info/exclude' <<'OUT'
$loop_output
OUT"
  assert_equal "$output" "1"
}

@test "a rule the crashed session wrote in the tree is named before it goes" {
  # The `.gitignore` of the working tree has nothing to put back — a ticket may
  # add an ignore rule, that is project work ([30]) — but on a path with no gate
  # nobody was naming it either. A human read `this rollback could not undo … lib/`
  # with no way to tell a build directory from one a session had just decided to
  # hide. And the sentence is not the gated one: here the rollback takes the rule
  # away, so "the new rules apply from the next iteration" would be false.
  use_tickets 01-alpha
  set_config STERILE_K 1

  script_claude <<'FAKE'
#!/usr/bin/env bash
cat >/dev/null
printf 'lib/\n' >>.gitignore
mkdir -p lib src
printf 'rogue\n' >lib/rogue.sh
printf 'written\n' >src/alpha.txt
exit 1
FAKE

  run_loop
  assert_failure 4
  assert_output_contains "this session moved the ignore frontier: .gitignore"
  assert_output_contains "no gate judged this iteration"

  # And it really did go: the line describes what the rollback is about to do.
  refute_file_exists "$PROJECT_DIR/.gitignore"
  refute_file_exists "$PROJECT_DIR/lib/rogue.sh"
}

# ── the attempt is kept ──────────────────────────────────────────────────────

@test "before the escalation, a branch keeps the attempt the human will read" {
  use_tickets 01-alpha
  set_config RETRY_N 0
  set_config STERILE_K 1
  script_session_writing src/alpha.txt src/rogue.txt

  run_loop
  assert_failure 4
  assert_output_contains "the attempt is kept on branch failed/01-alpha"

  run git -C "$PROJECT_DIR" show "failed/01-alpha:src/rogue.txt"
  assert_success
  assert_output_contains "written"

  # A forensic artefact, not a snapshot of the loop's own bookkeeping.
  run git -C "$PROJECT_DIR" ls-tree -r --name-only "failed/01-alpha"
  refute_output_contains ".scratch/"

  # And the branch is the only place it survives.
  refute_file_exists "$PROJECT_DIR/src/rogue.txt"
}

# ── a green iteration is durable ─────────────────────────────────────────────

@test "what a green gate approved is committed, and nothing else is" {
  use_tickets 01-alpha 02-beta
  # A suite that writes after the tree it was judged on, which is any real suite —
  # and since [13] the only thing that still separates "what the gate approved"
  # from "everything in this tree": a worktree starts clean at the branch tip, so
  # the two lists are identical unless something is written beside the session.
  set_config TEST_CMD 'mkdir -p build; printf report >build/coverage.xml; exit 0'

  script_claude <<'FAKE'
#!/usr/bin/env bash
n="$(cat "$RALPH_SHIM_STATE/seq" 2>/dev/null || echo 0)"
n=$((n + 1)); echo "$n" >"$RALPH_SHIM_STATE/seq"
mkdir -p src
case "$n" in
  1) printf 'written\n' >src/alpha.txt ;;
  2) printf 'written\n' >src/beta.txt ;;
esac
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_success

  run git_subjects
  assert_output_contains "01-alpha: iteration delivered (gate green)"
  assert_output_contains "02-beta: iteration delivered (gate green)"

  run git -C "$PROJECT_DIR" show --stat --format= HEAD
  assert_output_contains "src/beta.txt"
  refute_output_contains "src/alpha.txt"
  refute_output_contains ".scratch/"
  refute_output_contains "build/coverage.xml"

  # Nothing of the two iterations is left uncommitted.
  assert_equal "$(worktree_dirt)" ""
}

@test "a later rollback never takes away what an earlier gate had approved" {
  use_tickets 01-alpha 02-beta
  set_config STERILE_K 1

  script_claude <<'FAKE'
#!/usr/bin/env bash
n="$(cat "$RALPH_SHIM_STATE/seq" 2>/dev/null || echo 0)"
n=$((n + 1)); echo "$n" >"$RALPH_SHIM_STATE/seq"
mkdir -p src
case "$n" in
  1) printf 'written\n' >src/alpha.txt ;;
  2) printf 'written\n' >src/beta.txt; printf 'written\n' >src/rogue.txt ;;
esac
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_failure 4

  assert_ticket_status 01-alpha resolved
  assert_file_contains "$PROJECT_DIR/src/alpha.txt" "written"

  # Still in the tree is not the guarantee — being committed is. Uncommitted, it
  # would be at the mercy of the next iteration's rollback.
  run git -C "$PROJECT_DIR" log --oneline -- src/alpha.txt
  assert_output_contains "01-alpha"

  refute_file_exists "$PROJECT_DIR/src/beta.txt"
  refute_file_exists "$PROJECT_DIR/src/rogue.txt"
}

@test "a commit the session made does not survive its own green gate either" {
  # The asymmetry that was left: on a red gate the rollback moves HEAD back, on a
  # green one nothing did. So a session that ran `git add -A && git commit` — the
  # ordinary reflex of an agent told to finish its work — put the loop's own state
  # into the target project's history: the ticket frozen mid-claim at `claimed`, a
  # state that was never true, next to the run journal and a session stream that
  # can run to tens of megabytes.
  use_tickets 01-alpha

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src
printf 'written\n' >src/alpha.txt
git add -A >/dev/null 2>&1
git commit -q -m "session: committed everything I could see" >/dev/null 2>&1
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  # Where the project's history stood before the run: the tracker is committed by
  # the harness, like a real project would, so only what the run added is at issue.
  before="$(git -C "$PROJECT_DIR" rev-parse HEAD)"

  run_loop
  assert_success
  assert_ticket_status 01-alpha resolved

  # The work is durable, and it is the loop's commit that carries it.
  run git_subjects
  assert_output_contains "01-alpha: iteration delivered (gate green)"
  refute_output_contains "session: committed everything"

  # And nothing of the loop's own state went with it, ever — not on this commit
  # and not anywhere in the history the run produced. Cheaper to hold since [13]
  # than the assertion suggests, and worth saying rather than quietly banking: the
  # run journal, the lock and a session stream of any size live in the tree the run
  # was started in, so a `git add -A` inside an iteration's worktree cannot reach
  # them. What is still exercised here is the half that matters — the session's own
  # commit is undone and the loop's is the one that carries the work.
  run git -C "$PROJECT_DIR" show --stat --format= HEAD
  assert_output_contains "src/alpha.txt"
  refute_output_contains ".scratch/"

  run git -C "$PROJECT_DIR" log --format='%s' --name-only "$before..HEAD" -- .scratch
  assert_equal "$output" ""
}

# ── a slice too big for one session ──────────────────────────────────────────

# The ticket used here declares two files, so a split can hand one to each of
# two smaller tickets without inventing a surface nobody granted.
#
# Call 2 is the planning session: it reads the plan path out of its own prompt and
# writes the split there. Every call after that is an honest delivery session
# writing what its ticket declared.
script_reslice_world() {
  script_too_big_then <<'FAKE'
if [ "$n" = 2 ]; then
    plan="$(printf '%s' "$prompt" | sed -n 's/^Write the plan to \([^,]*\),.*/\1/p' | head -1)"
    printf '%s' "$plan" >"$RALPH_SHIM_STATE/plan-path"
    cat >"$plan" <<'PLAN'
--- ticket: alpha-half | The alpha half ---
**What to build:** The first half of what was too big.

**Blocked by:** None

**Write-surface:** `src/alpha.txt`

**Status:** ready-for-agent

- [ ] the alpha half exists
--- ticket: eta-half | The eta half ---
**What to build:** The second half of what was too big.

**Blocked by:** None

**Write-surface:** `src/eta.txt`

**Status:** ready-for-agent

- [ ] the eta half exists
PLAN
    echo '{"type":"result","subtype":"success","is_error":false,"num_turns":2,"total_cost_usd":0.01}'
    exit 0
fi

surface="$(printf '%s' "$prompt" |
  sed -n 's/^\*\*Write-surface:\*\* //p' | head -1 | tr -d '`\r' | tr ',' ' ')"
for target in $surface; do
  mkdir -p "$(dirname "$target")" && printf 'written\n' >"$target"
done
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":3,"total_cost_usd":0.02}'
FAKE
}

@test "a slice too big for one session is cut up, and the pieces get ground" {
  use_tickets 07-overlaps-alpha
  set_config SOFT_LIMIT_TOKENS 5000
  set_config STERILE_K 5
  script_reslice_world

  run_loop
  assert_success
  assert_output_contains "07-overlaps-alpha: too big -> re-sliced into 08-alpha-half 09-eta-half"

  # The pieces were created by the loop, on the frontier, and ground.
  assert_ticket_status 08-alpha-half resolved
  assert_ticket_status 09-eta-half resolved
  assert_file_contains "$PROJECT_DIR/src/alpha.txt" "written"
  assert_file_contains "$PROJECT_DIR/src/eta.txt" "written"
  assert_file_contains "$(ticket_file 08-alpha-half)" "- [ ] the alpha half exists"
  assert_file_contains "$(ticket_file 08-alpha-half)" "Re-sliced out of 07-overlaps-alpha"

  # The ticket that was too big waited for them, came back to the frontier, and
  # went to a human — which is what [35] changed here and it is worth reading
  # slowly. Its acceptance criteria were split into the two children by
  # construction, so once they are resolved a session on the parent has nothing
  # left to write; before [35] that empty iteration was `resolved` on three green
  # branches, which is to say the parent was rubber-stamped by a gate that had
  # nothing to judge. Now it is refused and escalated, and the note on it asks
  # exactly the right question — "why does this ticket make a session do nothing",
  # whose third answer is "the work is already done". Whether a split really added
  # up to its parent is a human's call: nothing in the pack checks that the
  # children carried every criterion, the re-slice prompt only *asks* for it.
  assert_file_contains "$(ticket_file 07-overlaps-alpha)" "Re-sliced into: 08-alpha-half, 09-eta-half"
  assert_ticket_status 07-overlaps-alpha ready-for-human
  assert_equal "$(ticket_field 07-overlaps-alpha Escalation)" "nothing-delivered"

  # The plan was written outside the repository, and the planning session never
  # became an iteration of its own.
  refute_output_contains "iteration 2: 07-overlaps-alpha"
  run bash -c "ls '$PROJECT_DIR'"
  refute_output_contains "plan"
}

@test "the planning session is fresh, and told where the plan goes" {
  use_tickets 07-overlaps-alpha
  set_config SOFT_LIMIT_TOKENS 5000
  set_config STERILE_K 1
  script_reslice_world

  run_loop

  run claude_call_stdin 2
  assert_output_contains "split it into smaller tickets"
  assert_output_contains "# 07 — Overlaps alpha"
  assert_output_contains "gains a second line"
  assert_output_contains "--- ticket: <slug> | <title> ---"

  run claude_call_argv 2
  refute_output_contains "--continue"
  refute_output_contains "--resume"

  # And it is not handed the loop's own register of tracker writes ([40]). This is
  # the spawn a reader forgets when reasoning about that register: `failures_reslice`
  # starts it from a subshell of the iteration, so it inherits the path with no
  # export at all, and the export only ever added the name to `claude`'s
  # environment. A planning session is also the one session whose output is thrown
  # away wholesale, so an id it appended would outlive everything else about it.
  run claude_call_env 2
  refute_output_contains "RALPH_TRACKER_LOG"

  # Written where the loop said, which is not inside the repository.
  run cat "$SHIM_STATE/plan-path"
  case "$output" in
    "$PROJECT_DIR"*) fail "the plan was written inside the repository: $output" ;;
  esac
}

@test "the re-slice session cannot leave the ignore frontier widened" {
  # A planning session is a session, and it is the one this pack never gates: its
  # whole output is thrown away, so nothing downstream would ever have put the
  # ignore rules back — and `.git/info/exclude` is in no tree, so the rollback
  # cannot reach it either ([30]). Left alone, one planning session would set what
  # the *next* iteration pins as if it were the project's own configuration.
  use_tickets 07-overlaps-alpha
  set_config SOFT_LIMIT_TOKENS 5000
  set_config STERILE_K 1

  script_too_big_then <<'FAKE'
if [ "$n" = 2 ]; then
    # A worktree answers `.git` with a *file*, so the naive `>>.git/info/exclude`
# writes nothing at all and this scenario would stage nothing while reading as
# green. The rule source git really reads is in the **common** git directory,
# which is what a session in any working tree of this repository would find,
# and what the pin looks at since [13].
printf 'rogue/\n' >>"$(git rev-parse --git-common-dir)/info/exclude"
    mkdir -p rogue && printf 'backdoor\n' >rogue/backdoor
    echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.01}'
    exit 0
fi
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.01}'
FAKE

  run_loop
  assert_output_contains "the re-slice session moved the ignore frontier"
  refute_file_contains "$PROJECT_DIR/.git/info/exclude" "rogue/"
  # And what it wrote behind the rule went with the rest of its output: the
  # rollback runs through the pin, so the rule bought no invisibility here either.
  refute_file_exists "$PROJECT_DIR/rogue/backdoor"
}

@test "a plan from a planning session the loop cut short is refused whole" {
  # The twin of "the re-slice session crossed the soft limit too", for the two
  # deadlines of [23] — and the one that needed writing, because a session cut for
  # *time* comes back a success: `claude` traps TERM and exits 0. The planner here
  # writes a plan that would validate perfectly and then hangs. Acting on it would
  # mean creating tickets out of what a session had written *so far*, and the
  # tracker is the one thing no rollback can take back.
  use_tickets 07-overlaps-alpha
  set_config SOFT_LIMIT_TOKENS 5000
  set_config SESSION_STALL_TIMEOUT 2
  set_config STERILE_K 1

  script_too_big_then <<'FAKE'
if [ "$n" = 2 ]; then
    plan="$(printf '%s' "$prompt" | sed -n 's/^Write the plan to \([^,]*\),.*/\1/p' | head -1)"
    cat >"$plan" <<'PLAN'
--- ticket: alpha-half | The alpha half ---
**What to build:** The first half of what was too big.

**Blocked by:** None

**Write-surface:** `src/alpha.txt`

**Status:** ready-for-agent

- [ ] the alpha half exists
--- ticket: eta-half | The eta half ---
**What to build:** The second half of what was too big.

**Blocked by:** None

**Write-surface:** `src/eta.txt`

**Status:** ready-for-agent

- [ ] the eta half exists
PLAN
    trap 'echo "{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"num_turns\":2,\"total_cost_usd\":0.01}"; exit 0' TERM
    i=0
    while [ $i -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
    exit 0
fi
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":3,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_failure 4
  assert_output_contains "the re-slice session ran out of time too (stall)"
  assert_output_contains "no re-slice plan came back"

  assert_ticket_status 07-overlaps-alpha ready-for-human
  assert_equal "$(ticket_field 07-overlaps-alpha Escalation)" "too-big"

  # And the split it had already written on disk was not acted on: one ticket in
  # the tracker, the one that was too big.
  run bash -c "ls '$TRACKER_DIR' | awk 'END { print NR }'"
  assert_equal "$output" "1"
}

@test "a slice nobody can split goes to the human, with the reason said" {
  use_tickets 07-overlaps-alpha
  set_config SOFT_LIMIT_TOKENS 5000
  set_config STERILE_K 1

  # The planner answers, and writes no plan: nothing it can do preserves the
  # acceptance criteria.
  script_too_big_then <<'FAKE'
echo 'No split preserves the acceptance criteria.'
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":2,"total_cost_usd":0.01}'
FAKE

  run_loop
  assert_failure 4
  assert_output_contains "no re-slice plan came back"

  assert_ticket_status 07-overlaps-alpha ready-for-human
  assert_equal "$(ticket_field 07-overlaps-alpha Escalation)" "too-big"
  assert_output_contains "the attempt is kept on branch failed/07-overlaps-alpha"

  # And no ticket was invented on the way.
  run bash -c "ls '$TRACKER_DIR' | awk 'END { print NR }'"
  assert_equal "$output" "1"
}

@test "a split that widens the write-surface is refused whole" {
  use_tickets 07-overlaps-alpha
  set_config SOFT_LIMIT_TOKENS 5000
  set_config STERILE_K 1

  script_too_big_then <<'FAKE'
plan="$(printf '%s' "$prompt" | sed -n 's/^Write the plan to \([^,]*\),.*/\1/p' | head -1)"
cat >"$plan" <<'PLAN'
--- ticket: alpha-half | The alpha half ---
**Write-surface:** `src/alpha.txt`

- [ ] the alpha half exists
--- ticket: land-grab | While we are here ---
**Write-surface:** `src/elsewhere.txt`

- [ ] something the original never declared
PLAN
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":2,"total_cost_usd":0.01}'
FAKE

  run_loop
  assert_failure 4
  assert_output_contains "would write src/elsewhere.txt, outside the write-surface being split"

  assert_ticket_status 07-overlaps-alpha ready-for-human
  assert_equal "$(ticket_field 07-overlaps-alpha Escalation)" "too-big"

  # Refused whole: not even the sound half was created.
  run bash -c "ls '$TRACKER_DIR' | awk 'END { print NR }'"
  assert_equal "$output" "1"
}

@test "a re-slice that could create nothing says so on the ticket, and says why" {
  use_tickets 07-overlaps-alpha
  set_config SOFT_LIMIT_TOKENS 5000
  set_config STERILE_K 1

  # The guard [47] put on the number space, held by somebody alive for the whole
  # of the run: every creation the plan asks for is refused, so a sound plan
  # produces no children at all.
  sleep 60 &
  holder=$!
  mkdir -p "$FEATURE_DIR/.open.guard"
  printf '%s\n' "$holder" >"$FEATURE_DIR/.open.guard/pid"
  printf '2026-08-28T00:00:00Z\n' >"$FEATURE_DIR/.open.guard/since"

  script_too_big_then <<'FAKE'
plan="$(printf '%s' "$prompt" | sed -n 's/^Write the plan to \([^,]*\),.*/\1/p' | head -1)"
cat >"$plan" <<'PLAN'
--- ticket: alpha-half | The alpha half ---
**Write-surface:** `src/alpha.txt`

- [ ] the alpha half exists
--- ticket: eta-half | The eta half ---
**Write-surface:** `src/eta.txt`

- [ ] the eta half exists
PLAN
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":2,"total_cost_usd":0.01}'
FAKE

  run_loop
  kill "$holder" 2>/dev/null || true
  rm -rf "$FEATURE_DIR/.open.guard"
  assert_failure 4

  assert_ticket_status 07-overlaps-alpha ready-for-human
  assert_equal "$(ticket_field 07-overlaps-alpha Escalation)" "too-big"

  # The neighbouring path — a split that got *some* of its children — writes a note
  # on the ticket, and this one wrote nothing anywhere a human sorting the sink in
  # the morning would look: the difference between a plan nothing could be made of
  # and a plan that was never written is not visible from the ticket ([49]).
  assert_file_contains "$(ticket_file 07-overlaps-alpha)" "Re-slice refused"

  # And the cause reaches a durable document. `run.log` records the ticket's own
  # escalation, `too-big`, which is the wrong cause; the two lines that name the
  # guard are `printf … >&2`, on a console nobody reads at eight in the morning.
  assert_file_contains "$PROJECT_DIR/receipts/$RALPH_TEST_FEATURE/07-overlaps-alpha.md" \
    "the ticket-open guard was held"

  # Nothing was created on the way, guard or no guard.
  run bash -c "ls '$TRACKER_DIR' | awk 'END { print NR }'"
  assert_equal "$output" "1"
}

@test "a plan that splits nothing is not a split" {
  use_tickets 07-overlaps-alpha
  set_config SOFT_LIMIT_TOKENS 5000
  set_config STERILE_K 1

  script_too_big_then <<'FAKE'
plan="$(printf '%s' "$prompt" | sed -n 's/^Write the plan to \([^,]*\),.*/\1/p' | head -1)"
cat >"$plan" <<'PLAN'
--- ticket: the-same-thing | The whole thing, again ---
**Write-surface:** `src/alpha.txt`, `src/eta.txt`

- [ ] everything the original asked for
PLAN
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":2,"total_cost_usd":0.01}'
FAKE

  run_loop
  assert_failure 4
  assert_output_contains "the plan does not split anything (1 ticket(s))"

  assert_ticket_status 07-overlaps-alpha ready-for-human
  run bash -c "ls '$TRACKER_DIR' | awk 'END { print NR }'"
  assert_equal "$output" "1"
}

# ── a session that writes the tracker itself ─────────────────────────────────
#
# The one write nothing else catches: the scope-guard drops `.scratch/<feature>/`
# as the loop's own bookkeeping and the rollback leaves it alone, so what a
# session writes there used to survive the iteration. Two shapes, two answers —
# a ticket it created is quarantined for a human, a ticket it edited is restored
# from the snapshot taken at spawn time, before the gate reads a single field.

@test "an edited ticket is put back, and the iteration pays for the edit" {
  # The canary drives the exploit — a surface widened to `*` — and a red
  # scope-guard is enough to make it fail there. This one takes the exploit away:
  # the session writes nothing but the file its ticket declared, so every gate
  # branch is green and the edited tracker is the only thing wrong with it.
  use_tickets 01-alpha
  set_config STERILE_K 1

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src
printf 'written\n' >src/alpha.txt
printf '\n- [ ] and one criterion the discovery never wrote\n' \
  >>"$(cat "$RALPH_SHIM_STATE/tracker-dir")/01-alpha.md"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_failure 4
  assert_output_contains "the session edited the tracker — restored 1 ticket file(s)"

  # Green branches, and no green iteration.
  assert_output_contains "tests=green typecheck=green scope=green"
  assert_ticket_status 01-alpha ready-for-agent
  assert_equal "$(ticket_field 01-alpha Failures)" "1"
  refute_file_contains "$(ticket_file 01-alpha)" "the discovery never wrote"

  # Reported as itself rather than folded into a red gate: the branches were all
  # green, and a receipt that said `gate-red` would send a human looking at tests.
  assert_file_contains "$FEATURE_DIR/run.log" "tracker-write"
  run bash -c "grep -c resolved '$FEATURE_DIR/run.log' || true"
  assert_equal "$output" "0"

  # And the work goes back with the attempt, like any other failed iteration.
  refute_file_exists "$PROJECT_DIR/src/alpha.txt"
  assert_file_contains "$(ticket_file 01-alpha)" "edited the tracker itself"
}

@test "a session cannot switch the guard off by writing the loop's own register" {
  # The register [13] handed `failures_protect_tracker` is an interrupter: an id in
  # it means "the loop wrote this file, leave it alone". It was exported, so the
  # session was told where it lived — one `printf` of its own id and the guard walks
  # past the ticket the session is about to rewrite ([40]).
  #
  # Staged whole rather than at the seam, because the tracker edit is not what
  # makes this the second false *delivered* of this pack. What the edit buys is: a
  # write-surface of `*`, so the scope-guard then approves a file the ticket never
  # declared, and the iteration commits it and folds it onto the branch. An
  # assertion on the ticket text alone would go green on a fix that left that half
  # open.
  use_tickets 01-alpha
  set_config STERILE_K 1

  # The append is conditional on the name being *there*, so the scenario is
  # byte-for-byte the same in both worlds and the environment is the only variable.
  # That is what makes the paired witness meaningful: put the export back and this
  # same fake buys the delivery.
  script_claude <<'FAKE'
#!/usr/bin/env bash
if [ -n "${RALPH_TRACKER_LOG:-}" ]; then
  printf '01-alpha\n' >>"$RALPH_TRACKER_LOG"
fi
perl -pi -e 's/^\*\*Write-surface:\*\* .*/**Write-surface:** `*`/' \
  "$(cat "$RALPH_SHIM_STATE/tracker-dir")/01-alpha.md"
mkdir -p src rogue
printf 'written\n' >src/alpha.txt
printf 'written\n' >rogue/backdoor
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_failure 4

  # The guard saw the edit: an id a session wrote into the register does not read
  # as an id the loop wrote.
  assert_output_contains "the session edited the tracker"
  assert_equal "$(ticket_field 01-alpha Write-surface)" '`src/alpha.txt`'
  assert_ticket_status 01-alpha ready-for-agent
  assert_output_contains "scope=red"

  # And nothing the widened surface would have bought reached the branch. On HEAD
  # and not on the working tree: the delivery this closes committed *and* folded,
  # so a tree-only assertion would have been green while the branch carried it.
  run git -C "$PROJECT_DIR" ls-tree -r --name-only HEAD
  refute_output_contains "rogue/backdoor"
  refute_file_contains "$FEATURE_DIR/run.log" "resolved"
}

@test "a session cannot resolve a ticket it was not given" {
  # The same hole seen from the other side, and the more expensive one: marking
  # somebody else's ticket resolved takes it out of the frontier for good, and the
  # run reports a night in which it was simply never picked up.
  use_tickets 01-alpha 02-beta

  # Only the first session cheats; the retry and the iteration after it are
  # honest. So the run has to reach 02 on its own, which it can only do if 02 is
  # still on the frontier after somebody else marked it resolved.
  script_claude <<'FAKE'
#!/usr/bin/env bash
prompt="$(cat)"
n="$(cat "$RALPH_SHIM_STATE/seq" 2>/dev/null || echo 0)"
n=$((n + 1)); printf '%s\n' "$n" >"$RALPH_SHIM_STATE/seq"

surface="$(printf '%s' "$prompt" |
  sed -n 's/^\*\*Write-surface:\*\* //p' | head -1 | tr -d '`\r' | tr ',' ' ')"
for target in $surface; do
  mkdir -p "$(dirname "$target")" && printf 'written\n' >"$target"
done

if [ "$n" = 1 ]; then
  perl -pi -e 's/^\*\*Status:\*\* .*/**Status:** resolved/' \
    "$(cat "$RALPH_SHIM_STATE/tracker-dir")/02-beta.md"
fi
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_success

  # 02 was really ground: the run spawned a session for it rather than walking
  # past a ticket already marked done and calling the frontier drained.
  assert_ticket_status 02-beta resolved
  assert_file_contains "$PROJECT_DIR/src/beta.txt" "written"
  assert_equal "$(claude_call_count)" "3"
  run bash -c "grep -c 'tracker-write' '$FEATURE_DIR/run.log'"
  assert_equal "$output" "1"
}

@test "a ticket the session created is quarantined, not quietly restored away" {
  # Restoring the directory wholesale would delete it — and with it the only copy
  # of what it asked for. The two checks have to agree: edits go back, additions
  # go to a human.
  use_tickets 01-alpha

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src
printf 'written\n' >src/alpha.txt
cat >"$(cat "$RALPH_SHIM_STATE/tracker-dir")/50-self-served.md" <<'TICKET'
# 50 — Self served

**Blocked by:** None

**Write-surface:** `src/anything.txt`

**Status:** ready-for-agent

- [ ] whatever this session felt like doing next
TICKET
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_success

  assert_file_exists "$(ticket_file 50-self-served)"
  assert_ticket_status 50-self-served ready-for-human
  # An addition alone is not a failure of its own: [07] settled that the work can
  # be good while the entry it smuggled in is neutralised.
  assert_ticket_status 01-alpha resolved
  refute_output_contains "the session edited the tracker"
}

@test "a renamed ticket file does not leave two tickets carrying one number" {
  # The composition the two checks above did not cover, and it is permanent when
  # it lands: a rename is a deletion plus an addition, so the restore puts the
  # ticket back and the quarantine keeps the copy — one `NN` on two files, a bare
  # number that resolves to nothing, and every ticket holding `Blocked by: NN`
  # out of the frontier for the rest of the tracker's life ([27]).
  #
  # Only the first session renames. The run has to be able to finish afterwards:
  # 03 depends on 01, so it can only be reached if the number 01 still resolves.
  use_tickets 01-alpha 03-blocked

  script_claude <<'FAKE'
#!/usr/bin/env bash
prompt="$(cat)"
n="$(cat "$RALPH_SHIM_STATE/seq" 2>/dev/null || echo 0)"
n=$((n + 1)); printf '%s\n' "$n" >"$RALPH_SHIM_STATE/seq"

surface="$(printf '%s' "$prompt" |
  sed -n 's/^\*\*Write-surface:\*\* //p' | head -1 | tr -d '`\r' | tr ',' ' ')"
for target in $surface; do
  mkdir -p "$(dirname "$target")" && printf 'written\n' >"$target"
done

if [ "$n" = 1 ]; then
  d="$(cat "$RALPH_SHIM_STATE/tracker-dir")"
  mv "$d/01-alpha.md" "$d/01-alpha-v2.md"
fi
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_success

  # The rename cost the iteration, like any other tracker edit.
  assert_output_contains "the session edited the tracker — restored 1 ticket file(s)"
  assert_file_contains "$FEATURE_DIR/run.log" "tracker-write"

  # The addition is kept — nothing a session wrote is destroyed — under a number
  # nobody else carries, and it is named as having moved.
  refute_file_exists "$TRACKER_DIR/01-alpha-v2.md"
  assert_file_exists "$(ticket_file 04-alpha-v2)"
  assert_ticket_status 04-alpha-v2 ready-for-human
  assert_equal "$(ticket_field 04-alpha-v2 Escalation)" "decision"
  assert_file_contains "$(ticket_file 04-alpha-v2)" "reached the tracker as \`01-alpha-v2\`"
  assert_output_contains "renumbered 01-alpha-v2 -> 04-alpha-v2"

  # And the frontier survives it: 01 still resolves, so 03 is reachable and the
  # run drains it instead of walking past a ticket that left the board in silence.
  assert_file_exists "$(ticket_file 01-alpha)"
  assert_ticket_status 01-alpha resolved
  assert_ticket_status 03-blocked resolved
  assert_file_contains "$PROJECT_DIR/src/gamma.txt" "written"
}

@test "a ticket the session invents on a number already taken moves too" {
  # The same collision without a rename, and the likelier half: nothing stops a
  # session writing a file called `01-anything.md` into the tracker. The repair
  # is keyed on the number, not on git calling something a rename.
  use_tickets 01-alpha 03-blocked

  script_claude <<'FAKE'
#!/usr/bin/env bash
prompt="$(cat)"
mkdir -p src
# Its own ticket's surface, and not 01-alpha's twice: the second iteration would
# otherwise be writing bytes that are already there, which delivers nothing since
# [35] — and used to deliver a `resolved` for a session that had done nothing for
# the ticket it was handed.
for target in $(printf '%s' "$prompt" | sed -n 's/^\*\*Write-surface:\*\* //p' |
  head -1 | tr -d '`\r' | tr ',' ' '); do
  mkdir -p "$(dirname "$target")" && printf 'written\n' >"$target"
done
cat >"$(cat "$RALPH_SHIM_STATE/tracker-dir")/01-self-served.md" <<'TICKET'
# 01 — Self served

**Blocked by:** None

**Write-surface:** `src/anything.txt`

**Status:** ready-for-agent

- [ ] whatever this session felt like doing next
TICKET
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_success

  refute_file_exists "$TRACKER_DIR/01-self-served.md"
  assert_file_exists "$(ticket_file 04-self-served)"
  assert_ticket_status 04-self-served ready-for-human

  # An addition alone is not a failure of its own ([07]), renumbered or not.
  assert_ticket_status 01-alpha resolved
  assert_ticket_status 03-blocked resolved
  refute_output_contains "the session edited the tracker"
}

@test "a session that deletes the whole tracker gets it back" {
  # The hostile end of the same mechanism, and the one that would end a run: the
  # tracker is the only authority on state, so a `rm -rf` in the wrong place is
  # not one lost ticket but every ticket, including the claim of the iteration
  # running. The snapshot has to be able to rebuild the directory itself, not just
  # overwrite files inside one.
  use_tickets 01-alpha 02-beta 03-blocked
  set_config STERILE_K 1

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src
printf 'written\n' >src/alpha.txt
rm -rf "$(cat "$RALPH_SHIM_STATE/tracker-dir")"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_failure 4
  assert_output_contains "the session edited the tracker — restored 3 ticket file(s)"

  # Every ticket is back, with the state it had at spawn time — and the run went
  # on to mark and journal against it rather than dying on a missing file.
  assert_ticket_status 01-alpha ready-for-agent
  assert_ticket_status 02-beta ready-for-agent
  assert_ticket_status 03-blocked ready-for-agent
  assert_equal "$(ticket_field 01-alpha Failures)" "1"
  assert_file_contains "$FEATURE_DIR/run.log" "tracker-write"
}

@test "a project that keeps its scratch out of git is guarded all the same" {
  # The probe that decided the snapshot is taken by force. Plenty of real projects
  # gitignore their scratch directory — and [19] provisions exactly that for the
  # journal and the session streams. An ignore rule the target project happens to
  # write must not be able to switch the tracker's own guard off, which is what an
  # ordinary `git add -A` would have done: both snapshots empty, no delta ever,
  # and the exploit back with no trace of the guard having declined.
  use_tickets 01-alpha
  set_config STERILE_K 1
  printf '.scratch/\n' >>"$PROJECT_DIR/.gitignore"
  harness__commit "test: a project that keeps its scratch out of git"

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src
printf 'written\n' >src/alpha.txt
printf 'written\n' >src/rogue.txt
perl -pi -e 's/^\*\*Write-surface:\*\* .*/**Write-surface:** `*`/' \
  "$(cat "$RALPH_SHIM_STATE/tracker-dir")/01-alpha.md"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_failure 4

  assert_output_contains "the session edited the tracker"
  assert_output_contains "scope=red"
  assert_equal "$(ticket_field 01-alpha Write-surface)" '`src/alpha.txt`'
  assert_ticket_status 01-alpha ready-for-agent
  refute_file_exists "$PROJECT_DIR/src/rogue.txt"
}

@test "a tracker nothing can vouch for does not pass" {
  use_tickets 01-alpha

  # The same rule the scope-guard follows: a guard that cannot see must not pass.
  # Reached when git refuses to write a tree object — the run is in trouble either
  # way, and the one thing it must not do is call the iteration clean.
  pack_run 'rc=0; failures_protect_tracker 01-alpha "" || rc=$?; printf "rc=%s\n" "$rc"'
  assert_success
  assert_output_contains "rc=1"
  assert_output_contains "cannot be vouched for"
}

@test "one unreadable ticket file does not make every ticket look deleted" {
  # The tracker guard's half of [59], and it is the outage of [49] reached from
  # the other end. `failures_tracker_tree` goes through the pathspec branch of
  # `gate_tree_snapshot`; a single ticket file git cannot open made that branch
  # answer **the empty tree with `rc=0`**, so `diff-tree before after` marked
  # every ticket `D`, this guard restored them all, refused the green and put a
  # note on a ticket accusing a session that had written nothing in there.
  use_tickets 01-alpha 02-beta

  pack_run '
before="$(failures_tracker_tree)"
chmod 000 "$(tracker_local__path 02-beta)"
rc=0
failures_protect_tracker 01-alpha "$before" "" || rc=$?
chmod 644 "$(tracker_local__path 02-beta)"
printf "rc=%s\n" "$rc"
printf "note=%s\n" "$(tracker_read_ticket 01-alpha | grep -c "edited the tracker" || true)"
'
  assert_success

  # Refused, and refused as a measurement that could not be taken rather than as
  # an edit somebody made: no ticket is restored, no note is written, and the
  # line says which of the two it is.
  assert_output_contains "rc=1"
  assert_output_contains "note=0"
  assert_output_contains "cannot read the tracker"
  refute_output_contains "restored"

  # The paired witness: the same call with both tickets readable vouches for the
  # tracker and says nothing at all.
  pack_run '
before="$(failures_tracker_tree)"
rc=0
failures_protect_tracker 01-alpha "$before" "" || rc=$?
printf "rc=%s\n" "$rc"'
  assert_success
  assert_output_contains "rc=0"
  refute_output_contains "cannot read the tracker"
}

@test "a claim guard a sibling dropped inside the window is not put back" {
  use_tickets 01-alpha 02-beta

  # `issues/` is not a directory of ticket files. `tracker_local_claim` takes its
  # guard beside the ticket it is about to stamp, and since [13] there is one
  # sibling per slot claiming wherever it falls — while this iteration's
  # pre-session snapshot, a `git add -A` over that directory, takes 35 ms. A guard
  # held across the snapshot and released during the session arrives here as a `D`.
  #
  # Staged at the module and never raced: a test that measures this window
  # measures the machine, which this harness has paid for twice ([38]).
  pack_run '
guard="$(tracker_local__path 02-beta).guard"
mkdir -p "$guard"
printf "%s\n" "$$" >"$guard/pid"
ralph_now >"$guard/since"
before="$(failures_tracker_tree)"
rm -rf "$guard"

rc=0
failures_protect_tracker 01-alpha "$before" "" || rc=$?
printf "rc=%s\n" "$rc"
if [ -d "$guard" ]; then
  printf "verdict=resurrected pid=%s\n" "$(cat "$guard/pid" 2>/dev/null)"
else
  printf "verdict=gone\n"
fi
printf "note=%s\n" "$(tracker_read_ticket 01-alpha | grep -c "edited the tracker" || true)"
printf "claim=%s\n" "$(tracker_claim 02-beta "pid:$$" && printf taken || printf refused)"
'
  assert_success

  # Three consequences of one `checkout-index`, and the third one ends the run:
  # an innocent iteration refused a green, a note on its ticket accusing a session
  # that wrote nothing in the tracker, and the lock back in place carrying the
  # pilot's own live pid — which nothing releases, `state_guard_release` following
  # a successful take and never a resurrection, so that ticket cannot be claimed
  # again for the rest of the run.
  assert_output_contains "verdict=gone"
  assert_output_contains "rc=0"
  assert_output_contains "note=0"
  assert_output_contains "claim=taken"
}

@test "an atomic write's temp file that vanished in the window is not put back" {
  use_tickets 01-alpha 02-beta

  # The second shape, and it fails differently: the claim's guard is a path one
  # level *below* the tracker, this one is a sibling of a ticket that merely does
  # not end in `.md`. `state_atomic_write` publishes by writing beside its target
  # and renaming, and removes the temp when the write itself fails — so a snapshot
  # taken while a sibling is mid-write holds a file the next one does not.
  pack_run '
dir="$(tracker_local__issues_dir)"
tmp="$(mktemp "$dir/02-beta.md.tmp.XXXXXX")"
printf "half a ticket\n" >"$tmp"
before="$(failures_tracker_tree)"
rm -f "$tmp"

rc=0
failures_protect_tracker 01-alpha "$before" "" || rc=$?
printf "rc=%s\n" "$rc"
if [ -e "$tmp" ]; then printf "verdict=resurrected\n"; else printf "verdict=gone\n"; fi
printf "note=%s\n" "$(tracker_read_ticket 01-alpha | grep -c "edited the tracker" || true)"
printf "frontier=%s\n" "$(tracker_frontier | tr "\n" " ")"
'
  assert_success

  # A resurrected temp file is not a lock, so what it costs is the other two: the
  # accusation and the green. And it stays out of the frontier either way — the
  # tracker's own scans glob `*.md` — which is why nothing downstream would ever
  # have said this happened.
  assert_output_contains "verdict=gone"
  assert_output_contains "rc=0"
  assert_output_contains "note=0"
  assert_output_contains "frontier=01-alpha 02-beta "
}

@test "what the tracker guard leaves alone because it is not a ticket is named" {
  use_tickets 01-alpha 02-beta

  # The price of restoring ticket files and only ticket files, and a session pays
  # it as much as this pack does: what lands in `issues/` under a name that is not
  # `<id>.md` is put back by nothing here, and the quarantine never looked at it
  # either ([27] globs `*.md`). A zone nobody judges is named on the window it
  # moves in rather than left to a document ([24]).
  #
  # Two shapes, because the answer has two clauses and one of them has no producer
  # inside this pack: a name that is not `*.md`, and a `.md` that is not *directly*
  # in the tracker. The second is reachable by a session alone — it creates
  # `issues/drafts/09-ghost.md` in one iteration, where it is an addition nobody
  # judges, and removes it inside the next one's window, where restoring it would
  # put a session's own file back under a name the tracker never carried.
  pack_run '
dir="$(tracker_local__issues_dir)"
mkdir -p "$dir/drafts"
cp "$dir/02-beta.md" "$dir/drafts/09-ghost.md"
before="$(failures_tracker_tree)"
rm -rf "$dir/drafts"
printf "what the session thought\n" >"$dir/session-notes.txt"

rc=0
failures_protect_tracker 01-alpha "$before" "" || rc=$?
printf "rc=%s\n" "$rc"
[ -e "$dir/session-notes.txt" ] && printf "notes=left\n"
if [ -e "$dir/drafts/09-ghost.md" ]; then printf "ghost=restored\n"; else printf "ghost=gone\n"; fi
printf "ids=%s\n" "$(tracker_ids | tr "\n" " ")"
'
  assert_success

  assert_output_contains "2 path(s) under the tracker directory that are not ticket files"
  assert_output_contains "session-notes.txt"
  assert_output_contains "drafts/09-ghost.md"
  assert_output_contains "notes=left"
  assert_output_contains "ghost=gone"
  # Named, not judged: an addition is the quarantine's business, and neither of
  # these two is even that — the tracker's own scans never saw them.
  assert_output_contains "rc=0"
  assert_output_contains "ids=01-alpha 02-beta "
}

@test "a ticket that moved under a name this guard cannot address is not vouched for" {
  use_tickets 01-alpha 02-beta

  # The residue [39] named and left: git quotes a name carrying a tab, a newline or
  # a quote whatever `core.quotePath` says, and a quoted string is one no consumer
  # of this list can hand to `checkout-index`. The fourth reader of that question,
  # and the only one that cannot even tell whether what it is looking at is a
  # ticket — so it refuses to vouch rather than counting a ticket it did not put
  # back, or dropping the path into the zone line as though it were a temp file.
  pack_run '
dir="$(tracker_local__issues_dir)"
weird="$dir/$(printf "09-a\tb").md"
cp "$dir/02-beta.md" "$weird"
before="$(failures_tracker_tree)"
rm -f "$weird"

rc=0
failures_protect_tracker 01-alpha "$before" "" || rc=$?
printf "rc=%s\n" "$rc"
if [ -e "$weird" ]; then printf "verdict=restored\n"; else printf "verdict=gone\n"; fi
'
  assert_success

  assert_output_contains "rc=1"
  assert_output_contains "under a name this guard cannot address"
  assert_output_contains "verdict=gone"
  # And not counted as a ticket it restored: the note on the ticket says how many
  # ticket files were put back, and this one was not.
  refute_output_contains "restored 1 ticket file(s)"
}

@test "a tracker the session staged does not stay staged" {
  use_tickets 01-alpha
  set_config STERILE_K 1

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src
printf 'written\n' >src/alpha.txt
perl -pi -e 's/^\*\*Write-surface:\*\* .*/**Write-surface:** `*`/' \
  "$(cat "$RALPH_SHIM_STATE/tracker-dir")/01-alpha.md"
# The *main* index, and it has to be named: a `git add` in the worktree stages
# an index that goes with it, so the guarantee this test names — the tracker
# never leaves in the target project's next commit — would be exercised by
# nothing at all ([13]).
git -C "$(cat "$RALPH_SHIM_STATE/project-dir")" add -A >/dev/null 2>&1
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_failure 4

  # Putting the file back is not enough if the index still holds the session's
  # version: it would leave with whatever a human commits next. The rollback
  # cannot do it — it unstages only the paths it restored, and the tracker is
  # deliberately outside its reach.
  run git -C "$PROJECT_DIR" diff --cached --name-only
  refute_output_contains "issues/01-alpha.md"

  # Scoped to the tickets, and the rest of `.scratch/` is not this ticket's to
  # keep: what an unfiltered `git add` stages there — the lock, the prompt, a
  # session stream of any size — is [19]'s `.gitignore` to provision. Pinned so
  # that the day it is provisioned, this line says what changed.
  assert_output_contains ".session."
}

@test "a planning session that edits the tracker has its whole plan refused" {
  use_tickets 07-overlaps-alpha
  set_config SOFT_LIMIT_TOKENS 5000
  set_config STERILE_K 2

  # A sound plan, from a session that widened the parent's write-surface on its
  # way past. Widening it is what a plan may not do — so a plan validated against
  # a surface the planner just wrote is validated against nothing.
  script_too_big_then <<'FAKE'
perl -pi -e 's/^\*\*Write-surface:\*\* .*/**Write-surface:** `*`/' \
  "$(cat "$RALPH_SHIM_STATE/tracker-dir")/07-overlaps-alpha.md"
plan="$(printf '%s' "$prompt" | sed -n 's/^Write the plan to \([^,]*\),.*/\1/p' | head -1)"
cat >"$plan" <<'PLAN'
--- ticket: everything | Everything, now that it is allowed ---
**Write-surface:** `src/alpha.txt`

- [ ] the alpha half exists
--- ticket: and-more | And the rest of the repository ---
**Write-surface:** `docs/`

- [ ] the rest exists
PLAN
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":2,"total_cost_usd":0.01}'
FAKE

  run_loop
  assert_success
  assert_output_contains "the session edited the tracker"

  assert_ticket_status 07-overlaps-alpha ready-for-human
  assert_equal "$(ticket_field 07-overlaps-alpha Escalation)" "too-big"
  assert_equal "$(ticket_field 07-overlaps-alpha Write-surface)" '`src/alpha.txt`, `src/eta.txt`'

  # Nothing was created out of the plan, sound as each half looked.
  run bash -c "ls '$TRACKER_DIR' | awk 'END { print NR }'"
  assert_equal "$output" "1"
}

@test "a delivery session does not get to put its own tickets on the frontier" {
  use_tickets 01-alpha
  set_config STERILE_K 2

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src
printf 'written\n' >src/alpha.txt
cat >"$(cat "$RALPH_SHIM_STATE/tracker-dir")/50-self-served.md" <<'TICKET'
# 50 — Self served

**Blocked by:** None

**Write-surface:** `src/anything.txt`

**Status:** ready-for-agent

- [ ] whatever this session felt like doing next
TICKET
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_success
  assert_output_contains "the session wrote the tracker itself — quarantined 50-self-served"

  # Its own work still stands or falls on the gate — this is a separate matter.
  assert_ticket_status 01-alpha resolved

  # The ticket it granted itself waits for a human, and was never ground.
  assert_ticket_status 50-self-served ready-for-human
  assert_equal "$(ticket_field 50-self-served Escalation)" "decision"
  refute_file_exists "$PROJECT_DIR/src/anything.txt"
  assert_equal "$(claude_call_count)" "1"

  # And the ticket that let it happen says so.
  assert_file_contains "$(ticket_file 01-alpha)" "wrote these tickets into the tracker itself"
}

@test "a planning session that writes tickets has its whole plan refused" {
  use_tickets 07-overlaps-alpha
  set_config SOFT_LIMIT_TOKENS 5000
  set_config STERILE_K 2

  # A plan that is perfectly sound, alongside a ticket it published on its own.
  # Sound or not, the output of a session that wrote the tracker is not read.
  script_too_big_then <<'FAKE'
cat >"$(cat "$RALPH_SHIM_STATE/tracker-dir")/50-self-served.md" <<'TICKET'
# 50 — Self served

**Blocked by:** None

**Write-surface:** `src/anything.txt`

**Status:** ready-for-agent

- [ ] whatever this session felt like doing next
TICKET
plan="$(printf '%s' "$prompt" | sed -n 's/^Write the plan to \([^,]*\),.*/\1/p' | head -1)"
cat >"$plan" <<'PLAN'
--- ticket: alpha-half | The alpha half ---
**Write-surface:** `src/alpha.txt`

- [ ] the alpha half exists
--- ticket: eta-half | The eta half ---
**Write-surface:** `src/eta.txt`

- [ ] the eta half exists
PLAN
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":2,"total_cost_usd":0.01}'
FAKE

  run_loop
  assert_success
  assert_output_contains "the session wrote the tracker itself"

  assert_ticket_status 50-self-served ready-for-human
  assert_ticket_status 07-overlaps-alpha ready-for-human
  assert_equal "$(ticket_field 07-overlaps-alpha Escalation)" "too-big"

  # The plan was not read: no half was created, however sound it looked.
  refute_file_exists "$(ticket_file 08-alpha-half)"
  run bash -c "ls '$TRACKER_DIR' | awk 'END { print NR }'"
  assert_equal "$output" "2"
}

# ── two runs on one repository ───────────────────────────────────────────────

@test "a run that lost its lock stops instead of grinding beside another one" {
  # Probed before it was written, and it was alive: a session that deletes the run
  # lock left the run going with exit 0, every ticket resolved, and not a word
  # said. From that point a second `loop.sh` starts — the lock directory is simply
  # gone — and two runs grind one repository, rolling back and committing over
  # each other. The lock lives in the tracker, the one part of the loop's state a
  # session can reach, so nothing else was ever going to notice.
  use_tickets 01-alpha 02-beta

  script_claude <<'FAKE'
#!/usr/bin/env bash
prompt="$(cat)"
surface="$(printf '%s' "$prompt" |
  sed -n 's/^\*\*Write-surface:\*\* //p' | head -1 | tr -d '`\r' | tr ',' ' ')"
for target in $surface; do
  mkdir -p "$(dirname "$target")" && printf 'written\n' >"$target"
done
rm -rf "$(cat "$RALPH_SHIM_STATE/project-dir")/.scratch/demo/.run.lock"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_failure 4
  assert_output_contains "the run lock is gone or not ours any more after 1 iterations"

  # The first iteration is not thrown away — it was gated and committed while the
  # run still held the lock. What stops is everything after it.
  assert_ticket_status 01-alpha resolved
  assert_ticket_status 02-beta ready-for-agent
  assert_equal "$(claude_call_count)" "1"
}

@test "a run that lost the tree lock stops too, though nothing normal can reach it" {
  # The tree lock lives in `.git/`, which is why an `rm -rf .scratch` or a
  # `git clean` cannot touch it. A session that deletes the directory outright
  # still can — and from that point a second `loop.sh` starts on this tree and the
  # two undo each other's work. Out of reach of an accident is not out of reach,
  # so the loop asks the question every iteration, for this lock as for the other.
  use_tickets 01-alpha 02-beta

  script_claude <<'FAKE'
#!/usr/bin/env bash
prompt="$(cat)"
surface="$(printf '%s' "$prompt" |
  sed -n 's/^\*\*Write-surface:\*\* //p' | head -1 | tr -d '`\r' | tr ',' ' ')"
for target in $surface; do
  mkdir -p "$(dirname "$target")" && printf 'written\n' >"$target"
done
rm -rf "$(cat "$RALPH_SHIM_STATE/project-dir")/.git/ralph.tree.lock"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_failure 4
  assert_output_contains "the working-tree lock is gone or not ours any more after 1 iterations"

  # The iteration that ran while the lock was still held is kept, like the run
  # lock's own case: what stops is everything after it.
  assert_ticket_status 01-alpha resolved
  assert_ticket_status 02-beta ready-for-agent
  assert_equal "$(claude_call_count)" "1"
}

@test "a durable commit never overwrites a HEAD it did not read" {
  # The window the lock check cannot cover: between reading HEAD and moving it,
  # another run can commit. Without the old value passed to `update-ref` the move
  # is a plain write, and one run's green iteration vanishes from the history
  # while both report `resolved`. Driven with a git that commits underneath us at
  # exactly that moment — the one way to stand in the window on purpose.
  use_tickets 01-alpha

  cat >"$SHIM_BIN/git" <<'GITSHIM'
#!/usr/bin/env bash
# Transparent, except once: on the commit-tree that precedes the durable commit,
# a concurrent run gets its commit in first.
real() { PATH="${PATH#"$RALPH_SHIM_BIN":}" command git "$@"; }
if [ "$1" = commit-tree ] && [ -f "$RALPH_SHIM_STATE/race-armed" ]; then
  rm -f "$RALPH_SHIM_STATE/race-armed"
  printf 'the other run was here\n' >other-run.txt
  real add -A -- other-run.txt >/dev/null 2>&1
  real -c user.name=other -c user.email=other@test.invalid \
    commit -q -m "another run committed here" >/dev/null 2>&1
fi
exec_real() { real "$@"; }
exec_real "$@"
GITSHIM
  chmod +x "$SHIM_BIN/git"
  export RALPH_SHIM_BIN="$SHIM_BIN"

  script_session_writing src/alpha.txt
  : >"$SHIM_STATE/race-armed"

  run_loop
  assert_failure 4

  # The iteration says it could not be made durable, rather than saying nothing.
  assert_output_contains "could not commit the iteration — it is not durable"

  # What is asserted about the overwrite is what survives [13]: this commit is
  # taken inside the iteration's worktree now, and that worktree is gone by the
  # time a test can look at it — so "the other run's commit is still the tip" is
  # not a question anything can be asked here any more. The refusal itself is the
  # guarantee, and its evidence is that nothing of this iteration reached the
  # history: with the old value dropped from `update-ref` the move is a plain
  # write, it succeeds, and the loop's commit shows up below.
  run git -C "$PROJECT_DIR" log --format='%s'
  refute_output_contains "01-alpha: iteration delivered"
  # The branch's own compare-and-swap — the one that now stands between two runs
  # of this pack — is a different line and has a test of its own, in
  # test/concurrency.bats.
  assert_ticket_status 01-alpha ready-for-agent
}

# ── when git itself says no ──────────────────────────────────────────────────

@test "a commit git refuses stops the run rather than resolving nothing" {
  # The guarantee this test names is the one [13] had to turn round, and it is
  # worth reading as a finding rather than as an edit. [07] wrote "a git that
  # refuses the commit is a warning, not the end of the run: the work is in the
  # tree either way, and the precise rollback does not touch what it did not put
  # there" — true while the iteration ran in the tree the run was started in, and
  # false the moment it runs in a tree that is about to be destroyed. Left alone,
  # a `main.lock` a crashed git forgot would have marked every ticket `resolved`
  # with nothing at all behind it: a whole frontier drained, a clean `exit 0`, and
  # not one line delivered. That is this pack's own definition of a false
  # delivered ([35]), reached through the door next to it.
  use_tickets 01-alpha 02-beta
  script_honest_session

  # What a crashed git leaves behind. Every `update-ref` on the current branch
  # fails from here on, so no iteration can reach it.
  : >"$PROJECT_DIR/.git/refs/heads/main.lock"

  run_loop
  assert_failure 4
  assert_output_contains "could not move the branch — this iteration is not on it"
  assert_output_contains "the gate was green and the work did not reach the branch — stopping"

  # The ticket goes back and pays nothing: the gate was green, so there is nothing
  # wrong with it to bill — the same reasoning [08] applies to a session the
  # subscription refused.
  assert_ticket_status 01-alpha ready-for-agent
  assert_equal "$(ticket_field 01-alpha Failures)" ""
  # And the run stops instead of spending a session per ticket to rediscover it.
  assert_ticket_status 02-beta ready-for-agent
  assert_equal "$(claude_call_count)" "1"
}

@test "a branch git cannot name is a warning too, and the escalation still lands" {
  use_tickets 01-alpha
  set_config RETRY_N 0
  set_config STERILE_K 1
  script_session_writing src/alpha.txt src/rogue.txt

  # A project with a branch called `failed` cannot also have `failed/01-alpha`:
  # git refuses the ref, and the forensic branch is the one thing lost.
  git -C "$PROJECT_DIR" branch failed

  run_loop
  assert_failure 4
  assert_output_contains "could not write branch failed/01-alpha"

  assert_ticket_status 01-alpha ready-for-human
  assert_equal "$(ticket_field 01-alpha Escalation)" "failed-impl"
  refute_file_exists "$PROJECT_DIR/src/rogue.txt"
}

# ── a gate branch that never comes back ──────────────────────────────────────

@test "a gate branch that hangs is red, and does not hang the run" {
  use_tickets 01-alpha
  set_config STERILE_K 1
  set_config GATE_TIMEOUT 1
  set_config TEST_CMD "sleep 30"

  run_loop
  assert_failure 4
  assert_output_contains "tests red (timed out after 1s)"

  # The deadline kills the branches, not the verdicts already in: a hung test
  # suite must not hide what the other checks found.
  assert_output_contains "scope=green"
  assert_output_contains "typecheck=green"
  assert_ticket_status 01-alpha ready-for-agent
}
