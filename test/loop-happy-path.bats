#!/usr/bin/env bats
#
# The tracer bullet: a populated frontier goes in, resolved tickets come out.
#
# This is the canary the pack keeps forever — it is the only test that exercises
# the whole chain (scan -> claim -> fresh session -> gate -> mark -> journal) on
# real processes, which is where wiring bugs actually live.

load helpers/harness
load helpers/assert

setup() {
  harness_setup
}

teardown() {
  if [ -n "${PACK_BG_PID:-}" ]; then
    kill -KILL "$PACK_BG_PID" 2>/dev/null || true
  fi
  harness_teardown
}

@test "the loop grinds the whole frontier, then exits clean on empty" {
  use_tickets 01-alpha 02-beta

  run_loop
  assert_success
  assert_output_contains "frontier empty"

  assert_ticket_status 01-alpha resolved
  assert_ticket_status 02-beta resolved
  # Two delivery sessions and the terminal value gate ([11]), which runs once the
  # frontier is empty and before this run is entitled to report a finished night.
  # The third number is asserted rather than commented: a count that only says "3"
  # would go on passing if the value gate stopped running and a lens started.
  assert_equal "$(claude_call_count)" "3"
  assert_equal "$(playthrough_call_count)" "1"
}

@test "resolving a blocker pulls the blocked ticket in, within the same run" {
  use_tickets 01-alpha 03-blocked

  run_loop
  assert_success

  assert_ticket_status 01-alpha resolved
  assert_ticket_status 03-blocked resolved
  assert_equal "$(claude_call_count)" "3"
  assert_equal "$(playthrough_call_count)" "1"
}

@test "the loop leaves tickets it must not touch alone" {
  # The set is spelled out rather than "every fixture", and the reason is [35]:
  # two of the fixtures are about something else and now fail on their own. 07
  # shares a write-surface with 01 by design, so a session that writes what its
  # ticket declared drifts into 01's; 08 declares no surface at all, so it can
  # never deliver anything. Both have tests of their own, and neither has anything
  # to say about the tickets this one is about — one ground ticket beside the
  # three the loop must not touch.
  use_tickets 01-alpha 04-claimed 05-needs-triage 06-resolved 09-escalated

  run_loop
  assert_success
  assert_ticket_status 01-alpha resolved

  assert_ticket_status 04-claimed claimed
  assert_ticket_status 05-needs-triage needs-triage
  assert_ticket_status 09-escalated ready-for-human
}

@test "a frontier that was empty from the start is not reported as work done" {
  # Exit 5, not 0. A run that ground nothing — wrong FEATURE, everything still
  # in triage, a tracker the pack cannot read — must not come back looking
  # like a night of finished work.
  run_loop
  assert_failure 5
  assert_output_contains "nothing to grind"
  assert_equal "$(claude_call_count)" "0"
}

@test "a frontier this run drained is a clean exit" {
  use_tickets 01-alpha

  run_loop
  assert_success
  assert_output_contains "frontier empty after 1 iterations"
  assert_ticket_status 01-alpha resolved
}

# ── refusing to start ────────────────────────────────────────────────────────

@test "an empty FEATURE stops the run before it touches anything" {
  # The shipped example leaves FEATURE empty, so this is every first run. It
  # used to derive a lock path of "/.run.lock" — a mkdir attempt at the root of
  # the filesystem — and exit 1, which means "another run holds the lock".
  set_config FEATURE ""

  run_loop
  assert_failure 2
  assert_output_contains "FEATURE is empty"
  refute_output_contains "/.run.lock"
  assert_equal "$(claude_call_count)" "0"
}

@test "a FEATURE naming a tracker that does not exist stops the run too" {
  set_config FEATURE ghost

  run_loop
  assert_failure 2
  assert_output_contains "no tracker at"

  # And nothing was created on the way: a typo must not leave a directory
  # behind that makes the next run look plausible.
  [ ! -d "$PROJECT_DIR/.scratch/ghost" ] || fail "the run created .scratch/ghost"
}

@test "a duplicate number is named at the start, in the journal, and does not stop the run" {
  # A tracker a human left in this state: two files carrying `01`, and `03`
  # pointing at it. The bare number resolves to nothing, so 03 drops out of a
  # frontier that is a memoryless scan — for good, and until now without a word
  # anywhere ([27]). Reported rather than refused: 01 and everything that does
  # not name it are still perfectly grindable.
  use_tickets 01-alpha 03-blocked
  cp "$(ticket_file 01-alpha)" "$TRACKER_DIR/01-alpha-bis.md"
  # Its own file to write, or the second of the two would be delivering bytes
  # that are already there — which is nothing delivered since [35], and has
  # nothing to do with the duplicate number this test is about.
  perl -pi -e 's|src/alpha\.txt|src/alpha-bis.txt|' "$TRACKER_DIR/01-alpha-bis.md"

  run_loop
  assert_success
  assert_output_contains "two or more tickets carry the number 01"
  assert_output_contains "03-blocked is blocked on 01"

  # In run.log and not only on the console: that is the file a human reads in
  # the morning, and the only one a receipt will be able to read.
  assert_file_contains "$FEATURE_DIR/run.log" "ambiguous-id"
  assert_file_contains "$FEATURE_DIR/run.log" "blocked-on-ambiguous-id"

  # Said once at the start, not rediscovered on every scan.
  run bash -c "grep -c 'ambiguous-id' '$FEATURE_DIR/run.log'"
  assert_equal "$output" "2"

  # And the run did its night's work anyway.
  assert_ticket_status 01-alpha resolved
  assert_ticket_status 03-blocked ready-for-agent
}

@test "a tracker with nothing wrong with it says nothing at the start" {
  use_tickets 01-alpha 03-blocked

  run_loop
  assert_success
  refute_output_contains "ambiguous"
  refute_file_contains "$FEATURE_DIR/run.log" "ambiguous-id"
}

# ── the session ──────────────────────────────────────────────────────────────

@test "the session gets the ticket and pointers to the rest of the context" {
  use_tickets 01-alpha

  run_loop
  assert_success

  run claude_call_stdin 1
  assert_output_contains "# 01 — Alpha"
  assert_output_contains "src/alpha.txt"
  assert_output_contains "CONTEXT.md"
  assert_output_contains "docs/adr/"
  # And **not** the lesson index, which used to be a fourth pointer here ([14]).
  # It lives in the main working tree, and since [13] a session works in a
  # throwaway worktree carrying only what is committed — so the pointer named a
  # file that was not there. What replaced it is the index itself, inlined and
  # quoted, and only when there is one: see test/retro.bats.
  refute_output_contains "LEARNINGS.md"
  assert_output_contains "The loop marks them, after the gate."

  # And the rules say which of them are checked rather than merely asked. A
  # session that believes it can edit the tracker spends a whole iteration
  # finding out otherwise; saying so up front is worth a line of prompt.
  assert_output_contains "Both are checked, not just asked"
}

@test "every session is fresh: no --continue, no --resume" {
  use_tickets 01-alpha 02-beta

  run_loop
  assert_success

  run claude_call_argv 1
  assert_output_contains "-p"
  assert_output_contains "--output-format"
  assert_output_contains "stream-json"
  assert_output_contains "--dangerously-skip-permissions"
  refute_output_contains "--continue"
  refute_output_contains "--resume"

  run claude_call_argv 2
  refute_output_contains "--continue"
  refute_output_contains "--resume"
}

@test "no session is handed the loop's register of its own tracker writes" {
  # [13] put that register in `$TMPDIR` so that no write-surface could reach it,
  # and then exported it — so `session_spawn` handed `claude` the path, by name,
  # in its environment. Out of the tree is not the property that protects it; who
  # is told the name is ([40]).
  #
  # Asserted on the environment the shim recorded and not on the absence of an
  # `export` in the source: what decides is what the spawn actually passed, and a
  # keyword put back in a second place would walk past a source-reading test.
  #
  # A lens is switched on so both kinds of spawn a normal iteration makes are
  # covered by one run. The re-slice session, the third kind, is asserted where it
  # is staged (failures.bats).
  use_tickets 01-alpha
  set_config LENSES standards

  run_loop
  assert_success

  # Not vacuous: a lens really did run, so its environment is among the ones
  # checked below. Without this the loop would pass over delivery sessions alone.
  assert_equal "$(lens_call_count standards)" "1"

  n=1
  seen=''
  total="$(claude_call_count)"
  [ "$total" -ge 2 ] || fail "expected a delivery session and a lens, got $total spawn(s)"
  while [ "$n" -le "$total" ]; do
    seen="$seen
$(claude_call_env "$n")"
    n=$((n + 1))
  done
  case "$seen" in
    *RALPH_TRACKER_LOG*) fail "a spawn was handed the loop's tracker register:
$seen" ;;
  esac

  # And the register still does its job on this side of the seam, which is what
  # makes the fix free: an iteration is a subshell of the pilot and inherits an
  # unexported variable. If it had stopped working, the guard would have restored
  # the claim the pilot wrote and this iteration could not be green.
  assert_ticket_status 01-alpha resolved
  refute_output_contains "edited the tracker"
}

@test "the session runs in an isolated worktree, whatever the caller's cwd" {
  use_tickets 01-alpha

  # It used to be the project root, and since [13] it is a throwaway worktree of
  # the same repository. Both halves are asserted, because only the pair says
  # anything: a cwd that is not the caller's *and* not the tree the run was
  # started in, holding the same commit. Asserting "not /" alone would pass for a
  # session running in the main tree, which is the arrangement this ticket exists
  # to remove.
  #
  # The marker lands outside the repository on purpose: a fake that scribbled
  # anywhere in the project would be caught by the scope-guard, and this test is
  # about the working directory and not about the gate. What it does write inside
  # is exactly its own write-surface — since [35] a session that writes nothing at
  # all delivers nothing, and this test would be measuring three failed attempts
  # instead of one honest iteration.
  script_claude <<'FAKE'
#!/usr/bin/env bash
pwd >"$RALPH_SHIM_STATE/session-cwd"
git rev-parse --git-common-dir >"$RALPH_SHIM_STATE/session-common-dir"
mkdir -p src && printf 'alpha\n' >src/alpha.txt
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run bash -c "cd / && bash '$PACK_DIR/loop.sh'"
  assert_success

  cwd="$(cat "$SHIM_STATE/session-cwd")"
  [ "$cwd" != "/" ] || fail "the session inherited the caller's cwd"
  [ "$cwd" != "$PROJECT_DIR" ] ||
    fail "the session ran in the tree the run was started in, not in a worktree of its own"
  # And it is a worktree of *this* repository and not some unrelated directory:
  # the common git directory every linked worktree shares is the project's own.
  case "$(cat "$SHIM_STATE/session-common-dir")" in
    "$PROJECT_DIR"/.git | "$PROJECT_DIR"/.git/) ;;
    *) fail "the session's worktree does not share this repository: $(cat "$SHIM_STATE/session-common-dir")" ;;
  esac
}

# ── who marks, and when ──────────────────────────────────────────────────────

@test "the ticket is claimed while the session runs — never resolved by it" {
  use_tickets 01-alpha

  # The tracker is named by an absolute path and not by `.scratch/demo/...`, and
  # that is the whole of what [13] changed here: a session's working directory is
  # a worktree now, so a relative path reads the *committed* copy of the tracker
  # that worktree carries — which says `ready-for-agent` for ever and would have
  # made this assertion measure a file nobody writes.
  printf '%s\n' "$TRACKER_DIR" >"$SHIM_STATE/tracker-dir"
  script_claude <<'FAKE'
#!/usr/bin/env bash
sed -n 's/^\*\*Status:\*\* //p' \
  "$(cat "$RALPH_SHIM_STATE/tracker-dir")/01-alpha.md" |
  head -1 >"$RALPH_SHIM_STATE/status-during-session"
mkdir -p src && printf 'alpha\n' >src/alpha.txt
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_success

  assert_equal "$(cat "$SHIM_STATE/status-during-session")" "claimed"
  assert_ticket_status 01-alpha resolved
}

@test "a session that fails resolves nothing and gives the ticket back" {
  use_tickets 01-alpha

  # It writes its write-surface *and then* dies, which is both the realistic crash
  # and what keeps this test about the exit code. Found by the mutation gate: with
  # a fake that wrote nothing, a loop that ignored `rc` altogether still refused
  # the iteration — for delivering nothing ([35]) — so the guarantee this test
  # names was carried by something else and its mutation came back VACUOUS.
  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src && printf 'alpha\n' >src/alpha.txt
echo '{"type":"result","subtype":"error_during_execution","is_error":true}'
exit 1
FAKE
  set_config STERILE_K 2

  run_loop
  assert_failure 4
  assert_output_contains "sterile run"

  assert_ticket_status 01-alpha ready-for-agent
  run ticket_has_field 01-alpha Claimed
  assert_failure
}

# ── guards ───────────────────────────────────────────────────────────────────

@test "the iteration cap stops a run that would otherwise keep going" {
  use_tickets
  set_config ITER_CAP 2

  run_loop
  assert_failure 4
  assert_output_contains "iteration cap reached (2)"

  assert_equal "$(claude_call_count)" "2"
  assert_ticket_status 01-alpha resolved
  assert_ticket_status 02-beta resolved
  assert_ticket_status 07-overlaps-alpha ready-for-agent
}

@test "the sterile detector stops a run that resolves nothing" {
  use_tickets 01-alpha 02-beta

  script_claude <<'FAKE'
#!/usr/bin/env bash
exit 1
FAKE
  set_config STERILE_K 3

  run_loop
  assert_failure 4
  assert_output_contains "sterile run: 3 iterations resolved nothing"

  assert_equal "$(claude_call_count)" "3"
  # Three attempts on the same ticket: two fresh retries, then the human sink.
  assert_ticket_status 01-alpha ready-for-human
}

@test "a ticket no iteration could claim is not silent in the journal" {
  use_tickets 01-alpha 02-beta
  set_config STERILE_K 2

  # A claim guard on 02-beta whose owner stays alive for the whole run — the shape
  # a sibling leaves behind for a few milliseconds, staged here for good.
  # `tracker_claim` is a test-and-set under that guard, so nothing can claim the
  # ticket while it is held and it stays `ready-for-agent` on the frontier: the
  # loop picks it again on every iteration, and the run ends sterile against it.
  guard="$TRACKER_DIR/02-beta.md.guard"
  mkdir -p "$guard"
  printf '%s\n' "$$" >"$guard/pid"
  printf '2026-08-28T00:00:00Z\n' >"$guard/since"

  script_claude <<'FAKE'
#!/usr/bin/env bash
prompt="$(cat)"
surface="$(printf '%s' "$prompt" |
  sed -n 's/^\*\*Write-surface:\*\* //p' | head -1 | tr -d '`\r' | tr ',' ' ')"
for target in $surface; do
  mkdir -p "$(dirname "$target")" && printf 'written\n' >"$target"
done
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_failure 4

  # The whole trace this used to leave was one console line, and it named a holder
  # that does not exist: `run.log` — the file a human opens in the morning, and the
  # only one a receipt can read — had nothing at all for a ticket no iteration
  # could ever take ([45] on [49]).
  assert_file_contains "$FEATURE_DIR/run.log" "$(printf '02-beta\tclaim-refused')"
  assert_output_contains "could not claim 02-beta — its status is still ready-for-agent"
  refute_output_contains "someone else has it"

  # And the run really did end against this ticket rather than around it.
  assert_ticket_status 01-alpha resolved
  assert_ticket_status 02-beta ready-for-agent
  assert_output_contains "sterile run"
}

@test "sterile counts consecutive barren iterations — a success resets it" {
  use_tickets 01-alpha 02-beta

  # fail, fail, succeed, then fail forever.
  script_claude <<'FAKE'
#!/usr/bin/env bash
n="$(cat "$RALPH_SHIM_STATE/call-seq" 2>/dev/null || echo 0)"
n=$((n + 1))
echo "$n" >"$RALPH_SHIM_STATE/call-seq"
case "$n" in
  # Delivering, and not merely reporting success: an iteration that changes no
  # file resolves nothing since [35], so a barren third call would leave the
  # counter it is here to reset exactly where it was.
  3) mkdir -p src && printf 'alpha\n' >src/alpha.txt
     echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}' ;;
  *) exit 1 ;;
esac
FAKE
  set_config STERILE_K 3

  run_loop
  assert_failure 4
  assert_output_contains "sterile run"

  # Without the reset the run would have given up at call 4, when the third
  # cumulative — but not consecutive — barren iteration landed.
  assert_equal "$(claude_call_count)" "6"
  assert_ticket_status 01-alpha resolved
  assert_ticket_status 02-beta ready-for-human
}

@test "a graceful kill finishes the iteration, then stops and frees the lock" {
  use_tickets 01-alpha 02-beta

  script_claude <<'FAKE'
#!/usr/bin/env bash
: >"$RALPH_SHIM_STATE/session-started"
sleep 1
# The stop lands during the first iteration, so this only ever runs for 01-alpha
# — and it has to deliver something, or the iteration the stop interrupts would
# resolve nothing whether or not it was allowed to finish ([35]).
mkdir -p src && printf 'alpha\n' >src/alpha.txt
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  bash "$PACK_DIR/loop.sh" >"$RALPH_TEST_DIR/loop.out" 2>&1 &
  PACK_BG_PID=$!

  wait_for_file "$SHIM_STATE/session-started" || fail "the loop never spawned a session"
  kill -TERM "$PACK_BG_PID"

  rc=0
  wait "$PACK_BG_PID" || rc=$?
  PACK_BG_PID=""

  assert_equal "$rc" "4"
  assert_file_contains "$RALPH_TEST_DIR/loop.out" "stop requested"

  # The interrupted iteration still finished properly, and only that one ran.
  assert_ticket_status 01-alpha resolved
  assert_ticket_status 02-beta ready-for-agent
  [ ! -d "$(run_lock_dir)" ] || fail "the lock survived the stop"
}

@test "a graceful kill during the gate waits for the branches it started" {
  use_tickets 01-alpha 02-beta

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src && printf 'alpha\n' >src/alpha.txt
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  # A test suite slow enough for the stop to land while it is still running: the
  # test above sends its signal during the session, which is the one window where
  # the promise held. The leading sleep is load-bearing too — the marker must not
  # appear before the loop is actually blocked in `wait`, because a signal arriving
  # between two commands runs its trap there and never interrupts the collection at
  # all, and the test would pass against the broken code.
  set_config TEST_CMD 'sleep 0.3
: >"$RALPH_SHIM_STATE/gate-running"
sleep 3
: >"$RALPH_SHIM_STATE/gate-finished"'

  bash "$PACK_DIR/loop.sh" >"$RALPH_TEST_DIR/loop.out" 2>&1 &
  PACK_BG_PID=$!

  wait_for_file "$SHIM_STATE/gate-running" 200 ||
    fail "the gate never started its test branch"
  # To the iteration as well as to the run, and that is what [13] changed about
  # this scenario. An iteration is a child of the pilot now, and a child does not
  # inherit a trap its parent installed — so a signal sent to the run alone never
  # reaches the shell blocked collecting the gate's branches, and this test went on
  # passing while proving only that branches finish when nobody interrupts them.
  # What a human's Ctrl-C really does is reach both.
  for _pid in $(pack_iteration_pids); do kill -TERM "$_pid" 2>/dev/null || true; done
  kill -TERM "$PACK_BG_PID"

  rc=0
  wait "$PACK_BG_PID" || rc=$?
  PACK_BG_PID=""

  assert_equal "$rc" "4"
  assert_file_contains "$RALPH_TEST_DIR/loop.out" "stop requested"

  # The verdict is the one the branches produced, not the absence of one that
  # `wait` returned too early to see.
  assert_file_contains "$RALPH_TEST_DIR/loop.out" "tests=green"
  refute_file_contains "$RALPH_TEST_DIR/loop.out" "no verdict"

  # No branch outlives the run: the suite had written its last marker before the
  # loop returned, so nothing could still be writing into the gate's directory
  # when it was removed.
  assert_file_exists "$SHIM_STATE/gate-finished"

  # And the iteration really finished. The ticket is marked on the verdict its own
  # suite gave, the session's work is still in the tree instead of having been
  # rolled back while that suite was running, and the stop cost it no retry.
  assert_ticket_status 01-alpha resolved
  assert_file_exists "$PROJECT_DIR/src/alpha.txt"
  run ticket_has_field 01-alpha Failures
  assert_failure
  assert_ticket_status 02-beta ready-for-agent
}

@test "a graceful kill during the gate is still bounded by the deadline" {
  use_tickets 01-alpha
  set_config GATE_TIMEOUT 1
  set_config TEST_CMD 'sleep 0.3
: >"$RALPH_SHIM_STATE/gate-running"
sleep 30'

  bash "$PACK_DIR/loop.sh" >"$RALPH_TEST_DIR/loop.out" 2>&1 &
  PACK_BG_PID=$!

  wait_for_file "$SHIM_STATE/gate-running" 200 ||
    fail "the gate never started its test branch"
  kill -TERM "$PACK_BG_PID"

  rc=0
  wait "$PACK_BG_PID" || rc=$?
  PACK_BG_PID=""

  # Waiting for the branches is not waiting for ever, and the stop gets no
  # deadline of its own: how long an iteration may take is already GATE_TIMEOUT's
  # question, and a second answer that only applies when a human pressed Ctrl-C
  # would be a different gate. What the stop no longer is, on the other hand, is an
  # escape hatch out of a hung branch — with no deadline configured, a hung gate
  # hangs the run whether or not a stop was requested, exactly as it did before.
  assert_equal "$rc" "4"
  assert_file_contains "$RALPH_TEST_DIR/loop.out" "tests red (timed out after 1s)"
  assert_file_contains "$RALPH_TEST_DIR/loop.out" "stop requested"
  assert_ticket_status 01-alpha ready-for-agent
}

# ── the run lock ─────────────────────────────────────────────────────────────

@test "the loop refuses to start while another run holds the lock" {
  use_tickets 01-alpha
  mkdir -p "$(run_lock_dir)"
  printf '%s\n' "$$" >"$(run_lock_dir)/pid"

  run_loop
  assert_failure 1
  assert_output_contains "another run already holds"

  assert_equal "$(claude_call_count)" "0"
  assert_ticket_status 01-alpha ready-for-agent
}

@test "the lock is released when the run finishes" {
  use_tickets 01-alpha

  run_loop
  assert_success

  [ ! -d "$(run_lock_dir)" ] || fail "the lock survived the run"
}

# ── the run journal ──────────────────────────────────────────────────────────

@test "each iteration appends a line to the run journal" {
  use_tickets 01-alpha 02-beta

  run_loop
  assert_success

  journal="$FEATURE_DIR/run.log"
  assert_file_contains "$journal" "01-alpha"
  assert_file_contains "$journal" "02-beta"
  assert_file_contains "$journal" "resolved"
  assert_file_contains "$journal" "turns=2"
  assert_file_contains "$journal" "cost=0.01"

  # Two iterations and the line the terminal value gate leaves when the frontier
  # empties ([11]). It is a line and not a silence on purpose: "the frontier
  # emptied and this run closed the feature" is the one event a morning reader
  # cannot reconstruct from the tickets, and the two other outcomes — a wiring
  # ticket re-injected, a feature that did not close — are how a night that went
  # on grinding after an empty frontier is readable at all.
  assert_file_contains "$journal" "playthrough-green"

  run bash -c "awk 'END { print NR }' '$journal'"
  assert_equal "$output" "3"

  # Timestamped, and append-only across runs.
  run bash -c "head -1 '$journal' | cut -f1"
  assert_output_contains "T"
  assert_output_contains "Z"
}

@test "the journal records failures too, and is never read to decide" {
  use_tickets 01-alpha

  script_claude <<'FAKE'
#!/usr/bin/env bash
exit 1
FAKE
  set_config STERILE_K 1

  run_loop
  assert_failure 4
  assert_file_contains "$FEATURE_DIR/run.log" "failed"

  # Deleting the journal changes nothing: the tracker is the only authority.
  rm "$FEATURE_DIR/run.log"
  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src && printf 'alpha\n' >src/alpha.txt
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_success
  assert_ticket_status 01-alpha resolved
}

@test "no session scratch file is left behind in the tracker" {
  use_tickets 01-alpha 02-beta

  run_loop
  assert_success

  run bash -c "ls -a '$FEATURE_DIR' | grep '\.session\.' || true"
  assert_equal "$output" ""
}

@test "a tracker directory with no issues/ says so instead of looking drained" {
  rm -rf "$TRACKER_DIR"

  run_loop
  assert_failure 5
  assert_output_contains "no issues directory"
}
