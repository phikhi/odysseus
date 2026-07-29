#!/usr/bin/env bats
#
# The objective gate: the tier of the quality gate a session cannot talk its
# way past. Tests, type check and scope-guard are run by the loop itself, in
# parallel, and *resolved* is only ever pronounced when every triggered branch
# came back green.

load helpers/harness
load helpers/assert

setup() {
  harness_setup
}

teardown() {
  # A collection that never returns is one of the failures this file covers, so a
  # test here can leave a spinning process behind. Killed before the tmpdir goes.
  if [ -n "${PACK_BG_PID:-}" ]; then
    kill -KILL "$PACK_BG_PID" 2>/dev/null || true
  fi
  harness_teardown
}

# A session that writes the given files, relative to the project root, then
# reports success. What the gate sees afterwards is the whole point.
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

# ── the branches run concurrently ────────────────────────────────────────────

@test "the objective checks run concurrently, not one after the other" {
  use_tickets 01-alpha

  # Each side exits 0 only if it sees the other one already running. Run in
  # sequence, whichever goes first waits for a marker that cannot appear yet,
  # times out, and the gate is red — no wall-clock measurement involved.
  cat >"$SHIM_BIN/rendezvous" <<'RENDEZVOUS'
#!/usr/bin/env bash
: >"$RALPH_SHIM_STATE/rv.$1"
i=0
while [ "$i" -lt 30 ]; do
  [ -e "$RALPH_SHIM_STATE/rv.$2" ] && exit 0
  sleep 0.1
  i=$((i + 1))
done
echo "rendezvous: $1 never saw $2"
exit 1
RENDEZVOUS
  chmod +x "$SHIM_BIN/rendezvous"

  set_config TEST_CMD "rendezvous tests typecheck"
  set_config TYPECHECK_CMD "rendezvous typecheck tests"

  run_loop
  assert_success
  assert_ticket_status 01-alpha resolved

  # One session, so the rendezvous was really met the first time. Without this the
  # test was vacuous, and the retry policy is what made it so: the markers live in
  # the shim state for the whole run, so a sequential first attempt fails, and the
  # second attempt finds both markers already lying there and passes without the
  # two branches ever having run together. A guarantee undone by a later ticket,
  # in a test nobody had reason to re-read.
  assert_equal "$(claude_call_count)" "1"
}

@test "a red branch does not short-circuit the others" {
  use_tickets 01-alpha
  stub_exit tests 1
  set_config STERILE_K 1

  run_loop
  assert_failure 4

  # Both verdicts are needed to know what is broken, so both branches run.
  assert_equal "$(stub_call_count tests)" "1"
  assert_equal "$(stub_call_count typecheck)" "1"
  assert_output_contains "typecheck=green"
}

# ── resolved means every triggered branch was green ──────────────────────────

@test "a red test suite resolves nothing" {
  use_tickets 01-alpha
  stub_exit tests 1
  set_config STERILE_K 1

  run_loop
  assert_failure 4
  assert_output_contains "tests red"

  assert_ticket_status 01-alpha ready-for-agent
  run ticket_has_field 01-alpha Claimed
  assert_failure
}

@test "a red type check resolves nothing either" {
  use_tickets 01-alpha
  stub_exit typecheck 2
  set_config STERILE_K 1

  run_loop
  assert_failure 4
  assert_output_contains "typecheck red (exit 2)"

  assert_ticket_status 01-alpha ready-for-agent
}

@test "a fake claude that breaks the tests never gets a resolved" {
  use_tickets 01-alpha 02-beta
  set_config STERILE_K 2

  # The session reports a triumphant success; the suite it left behind is red.
  script_claude <<'FAKE'
#!/usr/bin/env bash
printf '1\n' >"$RALPH_SHIM_STATE/stub-tests.exit"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":3,"total_cost_usd":0.04}'
FAKE

  run_loop
  assert_failure 4

  assert_ticket_status 01-alpha ready-for-agent
  assert_ticket_status 02-beta ready-for-agent
}

@test "green on every branch is what resolves a ticket" {
  use_tickets 01-alpha

  run_loop
  assert_success
  assert_output_contains "tests=green"
  assert_output_contains "typecheck=green"
  assert_output_contains "scope=green"

  assert_ticket_status 01-alpha resolved
  assert_equal "$(stub_call_count tests)" "1"
  assert_equal "$(stub_call_count typecheck)" "1"
}

@test "a red gate is journalled as such, not as a crashed session" {
  use_tickets 01-alpha
  stub_exit tests 1
  set_config STERILE_K 1

  run_loop
  assert_failure 4

  assert_file_contains "$FEATURE_DIR/run.log" "gate-red"
  run bash -c "grep -c 'failed' '$FEATURE_DIR/run.log' || true"
  assert_equal "$output" "0"
}

# ── anti-false-green ─────────────────────────────────────────────────────────

@test "an empty TEST_CMD stops the run instead of gating on nothing" {
  use_tickets 01-alpha
  set_config TEST_CMD ""

  run_loop
  assert_failure 2
  assert_output_contains "TEST_CMD is empty"

  assert_equal "$(claude_call_count)" "0"
  assert_ticket_status 01-alpha ready-for-agent
}

@test "an empty TYPECHECK_CMD stops the run too" {
  use_tickets 01-alpha
  set_config TYPECHECK_CMD ""

  run_loop
  assert_failure 2
  assert_output_contains "TYPECHECK_CMD is empty"
  assert_equal "$(claude_call_count)" "0"
}

@test "'none' is how a project declares it genuinely has no type check" {
  use_tickets 01-alpha
  set_config TYPECHECK_CMD "none"

  run_loop
  assert_success
  assert_ticket_status 01-alpha resolved

  # Not triggered, so not part of the verdict — and never silently green.
  assert_equal "$(stub_call_count typecheck)" "0"
  refute_output_contains "typecheck=green"
}

@test "a command that does not exist is red, never green" {
  use_tickets 01-alpha
  set_config TEST_CMD "definitely-not-a-command --all"
  set_config STERILE_K 1

  run_loop
  assert_failure 4
  assert_output_contains "tests red"
  assert_ticket_status 01-alpha ready-for-agent
}

@test "a branch that leaves no verdict at all counts red" {
  use_tickets 01-alpha
  set_config STERILE_K 1
  # Kills the branch that runs it, so no exit code is ever recorded. A gate
  # that only looks at the branches that reported back would call this green.
  set_config TEST_CMD 'kill -KILL $PPID'

  run_loop
  assert_failure 4
  assert_output_contains "tests red (no verdict)"
  assert_ticket_status 01-alpha ready-for-agent
}

@test "no git repository: the loop refuses rather than trust a blind scope-guard" {
  use_tickets 01-alpha
  rm -rf "$PROJECT_DIR/.git"

  run_loop
  assert_failure 2
  assert_output_contains "not a git repository"
  assert_equal "$(claude_call_count)" "0"
}

# ── the scope-guard ──────────────────────────────────────────────────────────

@test "a session that stays inside its write-surface passes" {
  use_tickets 01-alpha
  script_session_writing src/alpha.txt

  # The loop's own writes land in the tracker and the journal while this runs;
  # they are bookkeeping, not the session's doing, and must not trip the guard.
  run_loop
  assert_success
  assert_ticket_status 01-alpha resolved
  assert_file_contains "$PROJECT_DIR/src/alpha.txt" "written"
}

@test "a new file outside the write-surface makes the gate red" {
  use_tickets 01-alpha
  set_config STERILE_K 1
  script_session_writing src/alpha.txt src/rogue.txt

  run_loop
  assert_failure 4
  assert_output_contains "src/rogue.txt"
  assert_output_contains "outside the declared write-surface"

  # A neutral file means the declaration was too narrow — an internal matter.
  assert_output_contains "scope overflow on 01-alpha: internal"

  assert_ticket_status 01-alpha ready-for-agent
}

@test "editing a tracked file outside the write-surface is caught too" {
  use_tickets 01-alpha
  set_config STERILE_K 1
  # CONTEXT.md is committed, so it never shows up as an untracked file.
  script_session_writing CONTEXT.md

  run_loop
  assert_failure 4
  assert_output_contains "CONTEXT.md"
  assert_ticket_status 01-alpha ready-for-agent
}

@test "an overflow the session committed is caught all the same" {
  use_tickets 01-alpha
  set_config STERILE_K 1

  script_claude <<'FAKE'
#!/usr/bin/env bash
printf 'written\n' >rogue.txt
git add -A
git commit -q -m "session: work"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_failure 4
  assert_output_contains "rogue.txt"
  assert_ticket_status 01-alpha ready-for-agent
}

@test "an overflow into another ticket's write-surface is named as drift" {
  use_tickets 01-alpha 02-beta
  set_config STERILE_K 1
  script_session_writing src/beta.txt

  run_loop
  assert_failure 4

  # A neutral file is a too-narrow declaration, retryable; another ticket's
  # surface is a scoping conflict the discovery has to settle.
  assert_output_contains "02-beta"
  assert_output_contains "drift"
  assert_output_contains "scope overflow on 01-alpha: contract"
  refute_output_contains "outside the declared write-surface"

  # And it does not go back to the frontier: retrying a scoping conflict cannot
  # settle it, so the failure policy sends it straight to the human sink.
  assert_ticket_status 01-alpha ready-for-human
  assert_ticket_status 02-beta ready-for-agent
}

@test "a ticket that declares no write-surface may not write at all" {
  use_tickets 08-no-write-surface
  set_config STERILE_K 1
  script_session_writing src/somewhere.txt

  run_loop
  assert_failure 4
  assert_output_contains "src/somewhere.txt"
  assert_ticket_status 08-no-write-surface ready-for-agent
}

@test "a ticket with no write-surface that writes nothing is still resolvable" {
  use_tickets 08-no-write-surface

  run_loop
  assert_success
  assert_ticket_status 08-no-write-surface resolved
}

# ── unit: matching a path against a declared surface ─────────────────────────

@test "the write-surface is read as globs, whatever the markdown around it" {
  use_tickets 07-overlaps-alpha

  # Backticks and commas are for the human reader; the guard sees two globs.
  pack_run 'gate_write_surface 07-overlaps-alpha'
  assert_success
  assert_output_contains "src/alpha.txt src/eta.txt"
  refute_output_contains '`'
}

@test "a glob in the write-surface covers what it should, and no more" {
  pack_run 'gate_in_surface "src/deep/thing.ts" "src/*" && echo in || echo out'
  assert_equal "$output" "in"

  pack_run 'gate_in_surface "test/gate.bats" "src/*" && echo in || echo out'
  assert_equal "$output" "out"

  # A directory covers what is under it, with or without the trailing slash.
  pack_run 'gate_in_surface "docs/adr/0001.md" "docs/adr/" && echo in || echo out'
  assert_equal "$output" "in"

  pack_run 'gate_in_surface "docs/adr/0001.md" "docs/adr" && echo in || echo out'
  assert_equal "$output" "in"

  # It covers what is under the directory, not what merely starts like it.
  pack_run 'gate_in_surface "docs/adr.md" "docs/adr" && echo in || echo out'
  assert_equal "$output" "out"

  # An empty surface is the fail-safe case: nothing is inside it.
  pack_run 'gate_in_surface "src/alpha.txt" "" && echo in || echo out'
  assert_equal "$output" "out"
}

# ── one iteration is judged on its own writes ────────────────────────────────

@test "an iteration is not charged with what the previous one left in the tree" {
  use_tickets 01-alpha 02-beta
  set_config STERILE_K 1

  # Nothing commits a green iteration's work today, so the first ticket's file
  # is still lying there when the second session starts. Judged against HEAD,
  # the second iteration inherits it as its own overflow — and gets it called
  # drift into the very ticket that produced it.
  script_claude <<'FAKE'
#!/usr/bin/env bash
n="$(cat "$RALPH_SHIM_STATE/seq" 2>/dev/null || echo 0)"
n=$((n + 1)); echo "$n" >"$RALPH_SHIM_STATE/seq"
mkdir -p src
case "$n" in
  1) printf 'alpha\n' >src/alpha.txt ;;
  2) printf 'beta\n' >src/beta.txt ;;
esac
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_success
  refute_output_contains "scope=red"

  assert_ticket_status 01-alpha resolved
  assert_ticket_status 02-beta resolved
}

@test "a tree that was already dirty when the run started is not the ticket's doing" {
  use_tickets 01-alpha
  set_config STERILE_K 1

  # Someone's work in progress, uncommitted, nothing to do with this ticket.
  mkdir -p "$PROJECT_DIR/src"
  printf 'mine\n' >"$PROJECT_DIR/src/wip.txt"
  printf 'edited\n' >>"$PROJECT_DIR/CONTEXT.md"

  script_session_writing src/alpha.txt

  run_loop
  assert_success
  refute_output_contains "src/wip.txt"
  refute_output_contains "CONTEXT.md"
  assert_ticket_status 01-alpha resolved
}

@test "a scope-guard that cannot read the tree refuses to pass the ticket" {
  use_tickets 01-alpha
  set_config STERILE_K 1

  # No baseline, no verdict. Silence here would be a permanent false green.
  pack_run 'gate__scope_guard 01-alpha "" /dev/null'
  assert_failure
  assert_output_contains "could not read the working tree"
}

# ── the zone git does not show ───────────────────────────────────────────────
#
# Every check here is built on a git tree object, so every check is blind to what
# the *target project* chose to gitignore — and the fixture project deliberately
# has no `.gitignore` at all, which is why nothing in this file noticed for
# twenty-two tickets. Each test below writes the ignore rule it means.

# What a real project does to the pack's own directory, and to a build cache.
ignore_paths() {
  local pattern
  for pattern in "$@"; do
    printf '%s\n' "$pattern" >>"$PROJECT_DIR/.gitignore"
  done
  harness__commit "test: the project ignores $*"
}

@test "an ignored file under a guarded path is caught and undone all the same" {
  use_tickets 01-alpha
  set_config STERILE_K 1
  ignore_paths '.claude/cache/'
  script_session_writing src/alpha.txt .claude/cache/rogue

  run_loop
  assert_failure 4

  # Without the forced add, `git add -A` skips it: both snapshots agree, the
  # scope-guard reports nothing, the ticket resolves and the file stays.
  assert_output_contains ".claude/cache/rogue"
  assert_output_contains "outside the declared write-surface"
  assert_ticket_status 01-alpha ready-for-agent
  refute_file_exists "$PROJECT_DIR/.claude/cache/rogue"
  # And what it was allowed to write is undone as before, ignored or not.
  refute_file_exists "$PROJECT_DIR/src/alpha.txt"

  # The only ignored path this project has is a guarded one, so both reports have
  # nothing to say. A guarded path listed as unjudged would be a lie in the other
  # direction — the gate judged it, and that is why the ticket went red.
  refute_output_contains "nothing in this gate judged"
  refute_output_contains "could not undo"
}

@test "the guarded paths are the configured ones, not a constant" {
  use_tickets 01-alpha
  set_config STERILE_K 1
  set_config GUARDED_PATHS "vendor"
  ignore_paths 'vendor/'
  script_session_writing vendor/rogue

  run_loop
  assert_failure 4
  assert_output_contains "vendor/rogue"
  assert_ticket_status 01-alpha ready-for-agent
  refute_file_exists "$PROJECT_DIR/vendor/rogue"
}

@test "an ignored file outside the guarded paths is not judged, and the gate says so" {
  use_tickets 01-alpha
  ignore_paths 'cache/'
  script_session_writing src/alpha.txt cache/payload

  run_loop
  assert_success

  # The declared limit, pinned in both directions. The pack cannot see this file:
  # the iteration is green and the file survives. What it must not do is stay
  # quiet about the zone it did not look at.
  assert_ticket_status 01-alpha resolved
  assert_output_contains "nothing in this gate judged"
  assert_output_contains "cache/"
  assert_file_exists "$PROJECT_DIR/cache/payload"
}

@test "the loop's own bookkeeping is not named as an unjudged ignored path" {
  # The three entries [19] provisions in every target project. They are ignored
  # *and* written during the very window being watched — the journal, the lock and
  # the session stream — so a check that reddened or reported every ignored path
  # would report the loop's own writes on every iteration of every project.
  use_tickets 01-alpha 02-beta
  ignore_paths '.scratch/*/run.log' '.scratch/*/.run.lock/' \
    '.scratch/*/.session.*.jsonl' 'cache/'
  script_session_writing src/alpha.txt cache/payload

  run_loop
  assert_success

  # The second iteration, so that run.log already exists while the gate runs.
  local named
  named="$(printf '%s\n' "$output" | grep 'nothing in this gate judged' | tail -1)"
  [ -n "$named" ] || fail "the gate never named the zone it did not judge"
  case "$named" in
    *cache/*) ;;
    *) fail "the session's ignored write is missing from: $named" ;;
  esac
  case "$named" in
    *run.log* | *.session.* | *.run.lock*)
      fail "the loop's own bookkeeping was reported as unjudged: $named"
      ;;
  esac
}

@test "a session cannot configure the harness that judges the next one" {
  # The armed case. `.claude/settings.local.json` is ignored by convention in
  # every Claude Code project, so nothing in this pack could see it, and a hook in
  # it takes effect on the next spawn — a session configuring the harness that
  # judges its successors. Declared by the ticket here, which is the half a forced
  # snapshot alone does not close: the seal is what refuses it anyway.
  use_tickets 01-alpha
  ignore_paths '.claude/settings.local.json'
  perl -pi -e \
    's|^\*\*Write-surface:\*\* .*|**Write-surface:** `src/alpha.txt`, `.claude/settings.local.json`|' \
    "$(ticket_file 01-alpha)"
  harness__commit "test: a ticket that declares the harness's own settings"

  script_claude <<'FAKE'
#!/usr/bin/env bash
n="$(cat "$RALPH_SHIM_STATE/seq" 2>/dev/null || echo 0)"
n=$((n + 1)); echo "$n" >"$RALPH_SHIM_STATE/seq"
if [ -e .claude/settings.local.json ]; then
  printf '%s\n' "$n" >>"$RALPH_SHIM_STATE/inherited"
fi
mkdir -p src && printf 'written\n' >src/alpha.txt
if [ "$n" = 1 ]; then
  printf '{"hooks":{"PreToolUse":[{"matcher":"Write"}]}}\n' >.claude/settings.local.json
fi
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_success

  # First attempt red on the sealed write, second one delivers: the ticket is not
  # lost, and the second session never saw the file.
  assert_output_contains "configures the harness itself"
  assert_equal "$(claude_call_count)" "2"
  assert_ticket_status 01-alpha resolved
  refute_file_exists "$PROJECT_DIR/.claude/settings.local.json"
  refute_file_exists "$SHIM_STATE/inherited"
}

@test "a ticket green on what an earlier session left in the ignored zone is named" {
  # Question 4 in its purest form, and the reason this zone is a ticket of its
  # own: the defect is false in neither iteration taken alone. A suite that reads
  # an ignored file — an `.env`, a fixture cache, a test database, node_modules —
  # is any real suite.
  use_tickets 01-alpha 02-beta
  ignore_paths 'cache/'
  set_config TEST_CMD 'test -e cache/unlock'

  script_claude <<'FAKE'
#!/usr/bin/env bash
n="$(cat "$RALPH_SHIM_STATE/seq" 2>/dev/null || echo 0)"
n=$((n + 1)); echo "$n" >"$RALPH_SHIM_STATE/seq"
mkdir -p src
case "$n" in
  1) mkdir -p cache && printf 'unlocked\n' >cache/unlock
     printf 'alpha\n' >src/alpha.txt ;;
  2) printf 'beta\n' >src/beta.txt ;;
esac
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_success

  # Both green, the second one only because of the first one's write, and the pack
  # cannot tell. What it can do is say, on the iteration that benefited, that a
  # zone went unjudged — the line a human reads before believing the second one.
  assert_ticket_status 01-alpha resolved
  assert_ticket_status 02-beta resolved
  local named
  named="$(printf '%s\n' "$output" | grep 'nothing in this gate judged' | tail -1)"
  case "$named" in
    *cache/*) ;;
    *) fail "the inherited ignored file is not named on the second iteration: $named" ;;
  esac
}

# ── collecting the branches ──────────────────────────────────────────────────

@test "collecting a branch the deadline killed ends instead of spinning" {
  # The collection re-waits for as long as `wait` answers over 128, because that
  # is what a trapped signal looks like — see gate__collect. A branch the watchdog
  # killed answers over 128 as well, and on bash 3.2 it keeps answering 143 on
  # every later wait instead of "not a child of this shell": probed. The liveness
  # check is therefore the only thing that ends the loop, and taking it out hangs
  # the gate rather than failing an assertion — so the deadline for this one lives
  # in the test, which is what lets its mutation be run at all.
  pack_run_bg '
    sleep 30 &
    victim=$!
    kill -TERM "$victim"
    gate__collect "$victim"
    : >"$RALPH_SHIM_STATE/collected"
  '

  wait_for_file "$SHIM_STATE/collected" 100 ||
    fail "gate__collect never came back on a branch that had been killed"
}
