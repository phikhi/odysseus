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
  assert_equal "$(claude_call_count)" "2"
}

@test "resolving a blocker pulls the blocked ticket in, within the same run" {
  use_tickets 01-alpha 03-blocked

  run_loop
  assert_success

  assert_ticket_status 01-alpha resolved
  assert_ticket_status 03-blocked resolved
  assert_equal "$(claude_call_count)" "2"
}

@test "the loop leaves tickets it must not touch alone" {
  use_tickets

  run_loop
  assert_success

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
  assert_output_contains "LEARNINGS.md"
  assert_output_contains "The loop marks it, after the gate."
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

@test "the session runs at the project root, whatever the caller's cwd" {
  use_tickets 01-alpha

  # Markers land outside the repository on purpose: a fake that scribbles in
  # the project would be caught by the scope-guard, and this test is about the
  # working directory, not about the gate.
  script_claude <<'FAKE'
#!/usr/bin/env bash
pwd >"$RALPH_SHIM_STATE/session-cwd"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run bash -c "cd / && bash '$PACK_DIR/loop.sh'"
  assert_success
  assert_equal "$(cat "$SHIM_STATE/session-cwd")" "$PROJECT_DIR"
}

# ── who marks, and when ──────────────────────────────────────────────────────

@test "the ticket is claimed while the session runs — never resolved by it" {
  use_tickets 01-alpha

  script_claude <<'FAKE'
#!/usr/bin/env bash
sed -n 's/^\*\*Status:\*\* //p' .scratch/demo/issues/01-alpha.md |
  head -1 >"$RALPH_SHIM_STATE/status-during-session"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_success

  assert_equal "$(cat "$SHIM_STATE/status-during-session")" "claimed"
  assert_ticket_status 01-alpha resolved
}

@test "a session that fails resolves nothing and gives the ticket back" {
  use_tickets 01-alpha

  script_claude <<'FAKE'
#!/usr/bin/env bash
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

@test "sterile counts consecutive barren iterations — a success resets it" {
  use_tickets 01-alpha 02-beta

  # fail, fail, succeed, then fail forever.
  script_claude <<'FAKE'
#!/usr/bin/env bash
n="$(cat "$RALPH_SHIM_STATE/call-seq" 2>/dev/null || echo 0)"
n=$((n + 1))
echo "$n" >"$RALPH_SHIM_STATE/call-seq"
case "$n" in
  3) echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}' ;;
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

  run bash -c "awk 'END { print NR }' '$journal'"
  assert_equal "$output" "2"

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
