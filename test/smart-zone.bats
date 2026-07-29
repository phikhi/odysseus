#!/usr/bin/env bats
#
# The smart-zone net: the runtime guarantee that no session reaches the dumb
# zone, independent of how well the tickets were sliced.

load helpers/harness
load helpers/assert

setup() {
  harness_setup
  use_tickets 01-alpha 02-beta
}

teardown() {
  if [ -n "${PACK_BG_PID:-}" ]; then
    kill -KILL "$PACK_BG_PID" 2>/dev/null || true
  fi
  harness_teardown
}

# A session that reports the given context size and then keeps going — what an
# oversized ticket looks like from outside. Bounded at 30s so that a broken
# monitor fails the test instead of hanging the suite.
script_runaway_session() {
  local tokens="$1"
  script_claude <<FAKE
#!/usr/bin/env bash
echo '{"type":"system","subtype":"init","session_id":"s","model":"test-model"}'
echo '{"type":"assistant","message":{"role":"assistant","usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":$tokens,"output_tokens":5}},"session_id":"s"}'
: >"\$(pwd)/session-running"
i=0
while [ \$i -lt 300 ]; do
  sleep 0.1
  i=\$((i + 1))
done
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":9,"total_cost_usd":0.5}'
FAKE
}

# Same context size, but the session finishes on its own.
script_sized_session() {
  local tokens="$1"
  script_claude <<FAKE
#!/usr/bin/env bash
echo '{"type":"system","subtype":"init","session_id":"s","model":"test-model"}'
echo '{"type":"assistant","message":{"role":"assistant","usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":$tokens,"output_tokens":5}},"session_id":"s"}'
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":3,"total_cost_usd":0.05}'
FAKE
}

# ── auto-compact ─────────────────────────────────────────────────────────────

@test "auto-compact is off for every session the loop spawns" {
  run_loop
  assert_success

  run claude_call_env 1
  assert_output_contains "DISABLE_AUTO_COMPACT=1"

  run claude_call_env 2
  assert_output_contains "DISABLE_AUTO_COMPACT=1"

  # And the shipped posture says the same, so an interactive session in the
  # target project is covered too.
  assert_file_contains "$PACK_DIR/settings.json" '"autoCompactEnabled": false'
}

# ── the soft limit ───────────────────────────────────────────────────────────

@test "a session crossing the soft limit is terminated" {
  set_config SOFT_LIMIT_TOKENS 5000
  set_config STERILE_K 1
  script_runaway_session 9000

  run_loop
  assert_failure 4
  assert_output_contains "crossed the 5000-token soft limit"
  assert_output_contains "peak 9015"

  # Asserting the log line alone would pass even if the kill never landed.
  # A runaway session that survives reaches its own ending and reports
  # num_turns=9; a terminated one never gets there.
  assert_file_contains "$FEATURE_DIR/run.log" "turns=0"
  run bash -c "grep -c 'turns=9' '$FEATURE_DIR/run.log' || true"
  assert_equal "$output" "0"
}

@test "a session that survives its SIGTERM still does not count as resolved" {
  # A slice too big for one session is what the failure policy makes of it, so
  # the ticket ends up in the human sink here rather than back on the frontier:
  # the fake re-slice session runs out of context too, and a split nobody can
  # produce is the one case that needs a human.
  set_config SOFT_LIMIT_TOKENS 5000
  set_config STERILE_K 1

  # Claude Code traps SIGTERM and can shut down cleanly with exit 0. The exit
  # code alone would then say "success" about a session we cut short.
  script_claude <<'FAKE'
#!/usr/bin/env bash
trap 'echo "{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"num_turns\":4,\"total_cost_usd\":0.2}"; exit 0' TERM
echo '{"type":"system","subtype":"init","session_id":"s"}'
echo '{"type":"assistant","message":{"role":"assistant","usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":9000,"output_tokens":5}},"session_id":"s"}'
i=0
while [ $i -lt 300 ]; do
  sleep 0.1
  i=$((i + 1))
done
FAKE

  run_loop
  assert_failure 4
  assert_output_contains "crossed the 5000-token soft limit"

  assert_ticket_status 01-alpha ready-for-human
  assert_file_contains "$FEATURE_DIR/run.log" "over-soft-limit"
  run bash -c "grep -c resolved '$FEATURE_DIR/run.log' || true"
  assert_equal "$output" "0"
}

@test "a terminated session resolves nothing and the ticket stops being claimed" {
  set_config SOFT_LIMIT_TOKENS 5000
  set_config STERILE_K 1
  script_runaway_session 9000

  run_loop
  assert_failure 4

  assert_ticket_status 01-alpha ready-for-human
  run ticket_has_field 01-alpha Claimed
  assert_failure
}

@test "the journal records the outcome and the peak context" {
  set_config SOFT_LIMIT_TOKENS 5000
  set_config STERILE_K 1
  script_runaway_session 9000

  run_loop
  assert_failure 4

  assert_file_contains "$FEATURE_DIR/run.log" "over-soft-limit"
  assert_file_contains "$FEATURE_DIR/run.log" "tokens=9015"
}

@test "the threshold is the configured one, not a hard-coded 150K" {
  # Above 150K on purpose, and that is the whole point of the test. An earlier
  # version used 20000 against a 9015-token session: 9015 is under 20000 *and*
  # under 150000, so replacing the config read with a hard-coded 150000 changed
  # nothing and the test stayed green. A threshold test has to sit on the side of
  # the line the other tests cannot reach.
  set_config SOFT_LIMIT_TOKENS 300000
  script_sized_session 200000

  run_loop
  assert_success
  refute_output_contains "soft limit"

  assert_ticket_status 01-alpha resolved
  assert_file_contains "$FEATURE_DIR/run.log" "tokens=200015"
}

# ── the happy path is untouched ──────────────────────────────────────────────

@test "a session under the limit runs to completion, unhindered" {
  set_config SOFT_LIMIT_TOKENS 150000

  run_loop
  assert_success
  refute_output_contains "soft limit"

  assert_ticket_status 01-alpha resolved
  assert_ticket_status 02-beta resolved
  assert_equal "$(claude_call_count)" "2"
}

@test "the peak context of a normal session is journalled" {
  run_loop
  assert_success

  # The default fake stream reports 1000 + 200 on each assistant event, and the
  # same figures again on the result. Until [20] the assistant events carried no
  # usage at all and this 1200 came from the result alone — a peak the monitor
  # could only ever read once the session was already over, which is not where
  # the real signal comes from.
  assert_file_contains "$FEATURE_DIR/run.log" "tokens=1200"
}

@test "no monitor sidecar is left behind" {
  run_loop
  assert_success

  run bash -c "ls -a '$FEATURE_DIR' | grep '\.tokens' || true"
  assert_equal "$output" ""
}

# ── counting context ─────────────────────────────────────────────────────────

@test "context counts cached tokens: they occupy the window all the same" {
  pack_run 'monitor_context_tokens "{\"type\":\"assistant\",\"message\":{\"usage\":{\"input_tokens\":9,\"cache_creation_input_tokens\":6632,\"cache_read_input_tokens\":17900,\"cache_creation\":{\"ephemeral_1h_input_tokens\":6632},\"output_tokens\":3}}}"'
  assert_success
  # A key must not match a longer one: 9 + 6632 + 17900 + 3, and the nested
  # ephemeral counter is not double-counted.
  assert_equal "$output" "24544"
}

@test "an event without usage reports no context" {
  pack_run 'monitor_context_tokens "{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"s\"}"; echo "[end]"'
  assert_success
  assert_equal "$output" "[end]"
}

# ── reading a stream that is still being written ─────────────────────────────

@test "a usage event split across two writes is counted whole, once" {
  set_config SOFT_LIMIT_TOKENS 5000
  set_config STERILE_K 1

  # The monitor reads the stream forward through an open descriptor, so a tick
  # can land in the middle of a line. Half an event says 5 tokens; the whole one
  # says 9015 and crosses the limit. Nothing may act on the half.
  script_claude <<'FAKE'
#!/usr/bin/env bash
echo '{"type":"system","subtype":"init","session_id":"s"}'
printf '{"type":"assistant","message":{"role":"assistant","usage":{"input_tokens":10,"cache_read'
sleep 0.4
printf '_input_tokens":9000,"output_tokens":5}}},"session_id":"s"}\n'
i=0
while [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":9,"total_cost_usd":0.5}'
FAKE

  run_loop
  assert_failure 4
  assert_output_contains "crossed the 5000-token soft limit"
  assert_output_contains "peak 9015"

  # The runaway ends at num_turns=9 if it was never stopped.
  run bash -c "grep -c 'turns=9' '$FEATURE_DIR/run.log' || true"
  assert_equal "$output" "0"
}
