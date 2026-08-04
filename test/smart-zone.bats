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

# What both fakes below write before anything else: the write-surface of the
# ticket they were handed, read out of their own prompt the way the canary's
# honest session reads it.
#
# It is not decoration. Since [35] a session that reaches its own ending having
# changed no file resolves nothing, so a fake that delivered nothing would put a
# test about a threshold or a disabled deadline on the refusal path instead —
# and reading the surface rather than hard-coding `src/alpha.txt` matters just as
# much, because this file grinds two tickets and the second one writing the
# first one's file delivers nothing either.
SCRIPT_DELIVERS='prompt="$(cat)"
for target in $(printf "%s" "$prompt" | sed -n "s/^\*\*Write-surface:\*\* //p" |
  head -1 | tr -d "\`\r" | tr "," " "); do
  mkdir -p "$(dirname "$target")" && printf "written\n" >"$target"
done'

# A session that writes its opening events and then goes quiet for as long as it
# is given, in tenths of a second — a hang, seen from outside. Bounded, so that a
# deadline which never fires makes an assertion fail instead of hanging the suite.
#
# The wait is a run of short sleeps rather than one long one on purpose: the
# monitor TERMs the whole process tree, so a single `sleep` would be killed with
# the session and the fake would end for the wrong reason.
script_quiet_session() {
  local ticks="${1:-300}"
  script_claude <<FAKE
#!/usr/bin/env bash
$SCRIPT_DELIVERS
echo '{"type":"system","subtype":"init","session_id":"s","model":"test-model"}'
echo '{"type":"assistant","message":{"role":"assistant","usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":100,"output_tokens":5}},"session_id":"s"}'
i=0
while [ \$i -lt $ticks ]; do
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
$SCRIPT_DELIVERS
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

@test "a graceful kill during a session's shutdown waits for it" {
  # The second window the bare `wait` left open ([28]), and the longer of the two
  # in a real run. On the normal path `monitor_watch` only returns once it has seen
  # the process gone, so the `wait` after it does not block. On the soft-limit path
  # it sends its TERM and returns straight away, so that `wait` spans the whole of
  # the session's shutdown — and bash cuts `wait` short the moment a trapped signal
  # arrives. The loop then judged, rolled back, `rm -f`ed the stream and left the
  # run with a live `claude` still burning quota into it.
  set_config SOFT_LIMIT_TOKENS 5000
  set_config STERILE_K 1

  # Only the first session is slow. Left slow for all of them, the re-slice
  # session outlives the one under observation and the orphan has time to finish on
  # its own — which hid this on the first probe. `trap '' TERM` is what a real
  # `claude` looks like from outside: it does not vanish the instant the monitor
  # fires, it shuts down.
  script_claude <<'FAKE'
#!/usr/bin/env bash
if [ -e "$RALPH_SHIM_STATE/first-session" ]; then
  echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.01}'
  exit 0
fi
: >"$RALPH_SHIM_STATE/first-session"
trap '' TERM
echo '{"type":"system","subtype":"init","session_id":"s"}'
echo '{"type":"assistant","message":{"role":"assistant","usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":9000,"output_tokens":5}},"session_id":"s"}'
# Load-bearing, the same way it is in the gate's own stop test: the marker must
# not appear before the loop is actually blocked in `wait`, because a signal that
# lands between two commands runs its trap there, interrupts nothing, and the test
# would pass against the broken code.
#
# In tenths and not as one `sleep 0.6`, and that is the delay staying a delay:
# since [23] the monitor TERMs the whole process tree, so a single sleep would be
# killed along with the session and the marker would appear at once. Six sleeps
# lose one of them and keep the cushion — a constant of coverage, in a test whose
# guarantee is about a window.
i=0
while [ $i -lt 6 ]; do sleep 0.1; i=$((i + 1)); done
: >"$RALPH_SHIM_STATE/session-terminating"
sleep 2
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":7,"total_cost_usd":0.3}'
: >"$RALPH_SHIM_STATE/session-finished"
FAKE

  bash "$PACK_DIR/loop.sh" >"$RALPH_TEST_DIR/loop.out" 2>&1 &
  PACK_BG_PID=$!

  wait_for_file "$SHIM_STATE/session-terminating" 200 ||
    fail "the monitor never terminated the oversized session"
  kill -TERM "$PACK_BG_PID"

  rc=0
  wait "$PACK_BG_PID" || rc=$?
  PACK_BG_PID=""

  assert_equal "$rc" "4"
  assert_file_contains "$RALPH_TEST_DIR/loop.out" "stop requested"
  assert_file_contains "$RALPH_TEST_DIR/loop.out" "crossed the 5000-token soft limit"

  # No `claude` outlives the run: the session had written its last marker before
  # the loop returned.
  assert_file_exists "$SHIM_STATE/session-finished"

  # And the stream was still readable when it did. num_turns comes off the result
  # event the session emitted *after* the stop landed: a loop that gave up on
  # `wait` journals turns=0 and then `rm -f`s a file a live process is writing to.
  assert_file_contains "$FEATURE_DIR/run.log" "turns=7"
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

# ── the two deadlines ────────────────────────────────────────────────────────
#
# What the net above cannot do: it watches the stream, so a session that writes
# nothing is bounded by nothing at all ([23]). Every delay in this section is a
# constant of coverage twice over — once because the guarantee is a termination,
# and once because the deadlines are measured with SECONDS, an integer clock that
# fires anywhere between limit-1 and limit+1 seconds.

@test "a session that stops writing is terminated as a hang, not as a slice too big" {
  set_config SESSION_STALL_TIMEOUT 2
  set_config SESSION_TIMEOUT 0
  set_config STERILE_K 1
  script_quiet_session

  run_loop
  assert_failure 4
  assert_output_contains "wrote nothing for 2s — hung, terminated"
  # The distinction the whole ticket is about: a session cut for context says the
  # slice was too big, a session that hung says nothing about the ticket at all.
  refute_output_contains "soft limit"
  assert_file_contains "$FEATURE_DIR/run.log" "session-stalled"

  # Asserting the message alone would pass with no kill behind it: a quiet session
  # left alone reaches its own ending and reports num_turns=9.
  run bash -c "grep -c 'turns=9' '$FEATURE_DIR/run.log' || true"
  assert_equal "$output" "0"

  # Retried fresh, and never re-sliced — one `claude` is the proof, since a
  # re-slice spawns a second one to produce the split.
  assert_ticket_status 01-alpha ready-for-agent
  assert_equal "$(ticket_field 01-alpha Failures)" "1"
  assert_equal "$(claude_call_count)" "1"
}

@test "a session that never stops writing is bounded by the wall clock" {
  set_config SESSION_STALL_TIMEOUT 0
  set_config SESSION_TIMEOUT 3
  set_config STERILE_K 1

  # Twice a second, for ever, without ever finishing: never silent, never near
  # the token ceiling, and nothing but the wall clock notices. The stall deadline
  # is switched off here so that the wall clock is the only thing that can fire.
  script_claude <<'FAKE'
#!/usr/bin/env bash
echo '{"type":"system","subtype":"init","session_id":"s","model":"test-model"}'
i=0
while [ $i -lt 60 ]; do
  echo '{"type":"assistant","message":{"role":"assistant","usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":100,"output_tokens":5}},"session_id":"s"}'
  sleep 0.5
  i=$((i + 1))
done
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":9,"total_cost_usd":0.5}'
FAKE

  run_loop
  assert_failure 4
  assert_output_contains "ran past the 3s wall clock"
  assert_file_contains "$FEATURE_DIR/run.log" "session-timeout"
  run bash -c "grep -c 'turns=9' '$FEATURE_DIR/run.log' || true"
  assert_equal "$output" "0"
}

@test "a session that answers the deadline's TERM by exiting cleanly is not resolved" {
  # Claude Code traps SIGTERM and shuts down with exit 0, so the exit status of a
  # terminated session says success about work the loop cut short. That is why
  # the reason comes back beside the status and not inside it — the same trap the
  # soft limit fell into ([04]), one deadline further on.
  set_config SESSION_STALL_TIMEOUT 2
  set_config SESSION_TIMEOUT 0
  set_config STERILE_K 1

  script_claude <<'FAKE'
#!/usr/bin/env bash
trap 'echo "{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"num_turns\":4,\"total_cost_usd\":0.2}"; exit 0' TERM
echo '{"type":"system","subtype":"init","session_id":"s"}'
i=0
while [ $i -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
FAKE

  run_loop
  assert_failure 4
  assert_file_contains "$FEATURE_DIR/run.log" "session-stalled"
  run bash -c "grep -c resolved '$FEATURE_DIR/run.log' || true"
  assert_equal "$output" "0"
  assert_ticket_status 01-alpha ready-for-agent

  # And the deadline asked before it took: turns=4 is the result event this fake
  # only ever emits from its TERM handler, so it is the proof that the session was
  # given the chance to shut down rather than killed outright. A deadline that
  # went straight to KILL would journal turns=0 and nothing else would notice.
  assert_file_contains "$FEATURE_DIR/run.log" "turns=4"
}

@test "a session that ignores the deadline's TERM is killed after the grace" {
  # The half a TERM cannot promise. A TERM is a request, and the loop waits for
  # the exit status of what it asked to stop: without the KILL that follows, this
  # run does not come back at all. So the deadline for this one lives in the
  # test rather than in an assertion about a run that would never return — which
  # is what makes its mutation runnable (see test/mutate.sh).
  set_config SESSION_STALL_TIMEOUT 1
  set_config SESSION_KILL_GRACE 2
  set_config SESSION_TIMEOUT 0
  set_config STERILE_K 1

  script_claude <<'FAKE'
#!/usr/bin/env bash
trap '' TERM
echo '{"type":"system","subtype":"init","session_id":"s"}'
i=0
while [ $i -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
: >"$RALPH_SHIM_STATE/session-ran-to-the-end"
FAKE

  bash "$PACK_DIR/loop.sh" >"$RALPH_TEST_DIR/loop.out" 2>&1 &
  PACK_BG_PID=$!

  # Twelve seconds against a stall of one and a grace of two, so that a run which
  # only comes back when the fake gives up says so here rather than passing
  # slowly.
  wait_for_file "$FEATURE_DIR/run.log" 240 ||
    fail "the run never finished its iteration: the session ignored its TERM and nothing killed it"

  rc=0
  wait "$PACK_BG_PID" || rc=$?
  PACK_BG_PID=""

  assert_equal "$rc" "4"
  assert_file_contains "$FEATURE_DIR/run.log" "session-stalled"
  assert_file_contains "$RALPH_TEST_DIR/loop.out" "hung, terminated"

  # And the assertion that does not depend on how long this test was willing to
  # wait. `wait_for_file` counts *tries*, not seconds, so under load its deadline
  # stretches — during a full mutate.sh run it outlasted the session's own thirty
  # seconds, the fake ended by itself, every assertion above held and the mutation
  # that removes the KILL came back VACUOUS. What cannot stretch is this marker:
  # the session reaches it only by running to its own end, which is exactly what
  # the KILL exists to prevent.
  refute_file_exists "$SHIM_STATE/session-ran-to-the-end"
}

@test "a deadline of zero, or of nonsense, is no deadline at all" {
  # The reading GATE_TIMEOUT gives a missing deadline, and the one that lets a
  # project say "off" without inventing a huge number.
  set_config SESSION_STALL_TIMEOUT off
  set_config SESSION_TIMEOUT 0
  set_config ITER_CAP 1
  # Quiet for three seconds and then done: a session either deadline would have
  # killed if a nonsense value or a zero had been read as a number.
  script_quiet_session 30

  run_loop
  assert_failure 4
  refute_output_contains "hung, terminated"
  refute_output_contains "wall clock"
  assert_ticket_status 01-alpha resolved
}

@test "a stream arriving in slow halves is not silence" {
  # The corollary of reading the stream through an open descriptor: a tick can
  # land in the middle of a `printf`, and half a line is still the session
  # writing. Counting only whole lines would kill a session *for* writing — here
  # the halves are 2.5s apart and the whole lines 5s apart, on either side of a
  # four-second deadline.
  set_config SESSION_STALL_TIMEOUT 4
  set_config SESSION_TIMEOUT 0
  set_config ITER_CAP 1

  script_claude <<'FAKE'
#!/usr/bin/env bash
# Delivering, because the assertion below is that this iteration was resolved and
# not merely left alone: a session that writes nothing resolves nothing since [35],
# and the test would then be green with the deadline firing.
mkdir -p src && printf 'alpha\n' >src/alpha.txt
echo '{"type":"system","subtype":"init","session_id":"s"}'
i=0
while [ $i -lt 2 ]; do
  printf '{"type":"assistant","message":{"role":"assistant","usage":{"input_tokens":10,"cache_read'
  sleep 2.5
  printf '_input_tokens":100,"output_tokens":5}}},"session_id":"s"}\n'
  sleep 2.5
  i=$((i + 1))
done
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":3,"total_cost_usd":0.05}'
FAKE

  run_loop
  assert_failure 4
  refute_output_contains "hung, terminated"
  assert_ticket_status 01-alpha resolved
}

@test "a ticket whose sessions keep hanging goes to the human sink under its own name" {
  set_config SESSION_STALL_TIMEOUT 2
  set_config SESSION_TIMEOUT 0
  set_config RETRY_N 1
  set_config STERILE_K 2
  script_quiet_session

  run_loop
  assert_failure 4
  assert_ticket_status 01-alpha ready-for-human
  # Not `failed-impl`: no gate ever judged these sessions, and a human sent to
  # read a verdict that was never returned has been misrouted ([26]).
  assert_equal "$(ticket_field 01-alpha Escalation)" "session-timeout"
  assert_equal "$(ticket_field 01-alpha Failures)" "2"

  # The attempt is kept all the same, and on this path it is the only thing there
  # is to read.
  run git -C "$PROJECT_DIR" rev-parse --verify "refs/heads/failed/01-alpha"
  assert_success
}

@test "the shipped configuration bounds a session rather than leaving it to the night" {
  # A deadline nobody sets is a deadline nobody has, so the defaults are part of
  # the guarantee and not a matter of taste. Read out of the example a project
  # installs, never retyped.
  stall="$(config_default SESSION_STALL_TIMEOUT)"
  wall="$(config_default SESSION_TIMEOUT)"
  grace="$(config_default SESSION_KILL_GRACE)"

  # And the wall clock is the generous one of the two: a session may legitimately
  # be long, it may not legitimately be silent.
  run bash -c "[ \"$stall\" -gt 0 ] && [ \"$grace\" -gt 0 ] &&
    [ \"$wall\" -gt \"$stall\" ] && echo bounded"
  assert_success
  assert_output_contains "bounded"
}

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
