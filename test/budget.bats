#!/usr/bin/env bats
#
# The usage budget ([08]).
#
# Two sources answer the same question — how much of the subscription is left —
# and they are not interchangeable, which is what most of this file is about. The
# endpoint is asked before a session exists and is out of reach of the session
# being judged. The in-band `rate_limit_event` is free and arrives in a file that
# session can write ([23]), so it may make the run more cautious and never less,
# and what it can cost is bounded by things no session writes.
#
# What every test here has to keep honest:
#
#   - a figure this pack could not read is never read as zero. A budget watch
#     that passes everything in silence is the false green this pack exists for;
#   - a pause never touches `Failures:`, and a red gate is never forgiven for
#     being hungry. The classifier is only allowed in front of the outcomes where
#     *nothing was judged*;
#   - the run comes back. Every deadline in this file is short on purpose, and a
#     test that asserts a pause happened also asserts the loop came out of it.

load helpers/harness
load helpers/assert

setup() {
  harness_setup
}

teardown() {
  harness_teardown
}

# An instant, N seconds from now, as an epoch — which is one of the two shapes
# the endpoint is allowed to answer in.
budget_soon() {
  printf '%s\n' "$(($(date +%s) + ${1:-2}))"
}

# A usage payload. Utilisations are ratios here because that is what the shipped
# thresholds are compared against; the percent form has a test of its own.
budget_payload() {
  local five="$1" five_reset="$2" week="${3:-0.05}" week_reset="${4:-$2}"
  local opus="${5:-0.01}"
  printf '{"five_hour":{"utilization":%s,"resets_at":%s},' "$five" "$five_reset"
  printf '"seven_day":{"utilization":%s,"resets_at":%s},' "$week" "$week_reset"
  printf '"seven_day_opus":{"utilization":%s,"resets_at":%s}}\n' "$opus" "$week_reset"
}

# A session the API refused: it emits the in-band event and dies non-zero,
# without writing a line of the ticket. That is the shape the classifier has to
# tell apart from a crash, and the exit code alone cannot.
#
# The fourth argument is whatever the session does before it dies — the half a
# refused session leaves behind, which is what the rollback has to deal with.
script_refused_session() {
  local status="${1:-blocked}" window="${2:-five_hour}" reset="${3:-0}"
  local extra="${4:-}"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'cat >/dev/null\n'
    [ -z "$extra" ] || printf '%s\n' "$extra"
    printf "printf '%%s\\\\n' '%s'\n" \
      '{"type":"system","subtype":"init","session_id":"s","model":"test-model"}'
    printf "printf '%%s\\\\n' '{\"type\":\"rate_limit_event\",\"rate_limit_info\":{\"status\":\"%s\",\"resetsAt\":%s,\"rateLimitType\":\"%s\",\"isUsingOverage\":false}}'\n" \
      "$status" "$reset" "$window"
    printf "printf '%%s\\\\n' '%s'\n" \
      '{"type":"result","subtype":"error_during_execution","is_error":true,"num_turns":0,"total_cost_usd":0}'
    printf 'exit 1\n'
  } | script_claude
}

# Wait until a line shows up in a background run's output. `wait_for_file` cannot
# do this: the file exists from the first line the loop prints.
budget_wait_for_line() {
  local file="$1" needle="$2" tries="${3:-200}"
  while [ "$tries" -gt 0 ]; do
    grep -qF -- "$needle" "$file" 2>/dev/null && return 0
    tries=$((tries - 1))
    sleep 0.05
  done
  return 1
}

# Collect a background run, with a deadline of its own, and answer 99 if it had
# to be killed to get one.
#
# Every guarantee in this file that bounds a *wait* has this shape: removed, it
# does not fail, it sleeps. A test that simply ran the loop and asserted on its
# exit code would leave `bash test/mutate.sh` sitting on a planted defect
# instead of reporting it ([25] wrote this down for the gate's deadline).
budget_wait_for_exit() {
  local pid="$1" limit="${2:-30}" waited=0 rc=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$limit" ]; then
      kill -KILL "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 99
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$pid" || rc=$?
  return "$rc"
}

# ── reading the payload ──────────────────────────────────────────────────────

@test "a window this pack cannot read is not read as zero" {
  # The unit test the spec allows itself here, and the reason is that this is
  # where a budget watch goes quietly wrong: an absent figure read as 0% is a
  # gate that passes everything and reports green. Driving the six shapes below
  # through the loop would be six runs measuring one `sed`.
  pack_run 'budget__window "{\"five_hour\":{\"utilization\":0.42,\"resets_at\":1785952800}}" five_hour'
  assert_success
  assert_output_contains "42 1785952800"

  # The percent form of the same figure. The schema is undocumented, so both are
  # accepted and converted — but only inside a range that could be either.
  pack_run 'budget__window "{\"five_hour\":{\"utilization\":42,\"resets_at\":1785952800}}" five_hour'
  assert_success
  assert_output_contains "42 1785952800"

  # An ISO instant, which is the shape the spec names.
  pack_run 'budget__window "{\"five_hour\":{\"utilization\":0.5,\"resets_at\":\"2026-08-05T18:00:00Z\"}}" five_hour'
  assert_success
  assert_output_contains "50 "

  # And the three refusals. A window that is not there, a utilisation that is not
  # a number, and a figure outside any range this pack can interpret: all three
  # print nothing, and `budget_check` counts that as "not watched" rather than as
  # "nothing used".
  pack_run 'budget__window "{\"seven_day\":{\"utilization\":0.1}}" five_hour || printf "refused\n"'
  assert_success
  assert_output_contains "refused"

  pack_run 'budget__window "{\"five_hour\":{\"utilization\":\"lots\"}}" five_hour || printf "refused\n"'
  assert_success
  assert_output_contains "refused"

  pack_run 'budget__window "{\"five_hour\":{\"utilization\":420}}" five_hour || printf "refused\n"'
  assert_success
  assert_output_contains "refused"
}

@test "an endpoint that answers nothing readable does not look like an empty budget" {
  # The direction that would be a false green: no answer, no complaint, spawn
  # anyway *and say nothing*. The run flies on the in-band signal alone here, and
  # a human reading the log in the morning has to be able to see that.
  use_tickets 01-alpha
  usage_respond ''

  run_loop
  assert_success
  assert_ticket_status 01-alpha resolved
  assert_output_contains "the usage endpoint could not be read"
  assert_output_contains "in-band signal alone"
}

# ── the proactive gate ───────────────────────────────────────────────────────

@test "under the thresholds the endpoint is asked, with its User-Agent, and nothing else changes" {
  use_tickets 01-alpha
  usage_respond "$(budget_payload 0.10 "$(budget_soon 3600)")"

  run_loop
  assert_success
  assert_ticket_status 01-alpha resolved
  # Nothing said about a budget that is not in the way: the fifth acceptance
  # criterion is that the happy path is untouched.
  refute_output_contains "pausing"
  refute_output_contains "could not be read"

  # The endpoint demands a plausible User-Agent or it answers 429s for ever.
  run curl_calls
  assert_output_contains "User-Agent: claude-code"
  assert_output_contains "/api/oauth/usage"
}

@test "the answer is cached: two iterations, one question" {
  use_tickets 01-alpha 02-beta
  usage_respond "$(budget_payload 0.10 "$(budget_soon 3600)")"

  run_loop
  assert_success
  assert_ticket_status 01-alpha resolved
  assert_ticket_status 02-beta resolved
  # Three turns ask the budget — two iterations and the one that finds the
  # frontier empty — and one of them fetches. The cache is in this run's own
  # memory and never on disk: a cache file would be a file the judged session can
  # write, and a control that reads what the controlled writes is not a control.
  assert_equal "$(curl_call_count)" "1"
}

@test "a cache that expires is a cache that asks again" {
  # The other half, and without it the count above measures a constant: a budget
  # module that never asked twice would pass that test with the TTL removed. The
  # code path that produces the second call is the TTL running out, so the test
  # sets it to nothing.
  use_tickets 01-alpha 02-beta
  set_config USAGE_CACHE_TTL 0
  usage_respond "$(budget_payload 0.10 "$(budget_soon 3600)")"

  run_loop
  assert_success
  assert_equal "$(curl_call_count)" "3"
}

@test "a spent session window is waited out, and the run carries on afterwards" {
  # The third acceptance criterion end to end: over THRESH_5H, sleep to the
  # reset, then grind. Both halves matter — a gate that paused and stopped would
  # satisfy "it paused".
  use_tickets 01-alpha
  usage_respond \
    "$(budget_payload 0.99 "$(budget_soon 2)")" \
    "$(budget_payload 0.10 "$(budget_soon 3600)")"

  run_loop
  assert_success
  assert_output_contains "five_hour is at 99% of the subscription and this project stops at 95%"
  assert_output_contains "the session window is spent — pausing"
  # It came back out, and the ticket was ground after the wall rather than
  # before it: no session was spawned until the window had reset.
  assert_ticket_status 01-alpha resolved
  assert_equal "$(claude_call_count)" "1"
  assert_file_contains "$FEATURE_DIR/run.log" "budget-pause"
}

@test "a window that is still blocked after its own reset stops the run" {
  # The bound on the pause itself. Sleeping again on a signal that did not move
  # is how an AFK night is spent with nothing to show for it, and the second
  # source of that signal is a file a session can write.
  #
  # Run in the background with a deadline: without this bound the loop pauses,
  # wakes, finds the same wall and pauses again — for ever, since a pause is not
  # an iteration and `ITER_CAP` never sees it. A test that asserted on an exit
  # code would hang rather than fail.
  use_tickets 01-alpha
  usage_respond "$(budget_payload 0.99 "$(budget_soon 1)")"

  bash "$PACK_DIR/loop.sh" >"$RALPH_TEST_DIR/loop.out" 2>&1 &
  PACK_BG_PID=$!

  rc=0
  budget_wait_for_exit "$PACK_BG_PID" 25 || rc=$?
  PACK_BG_PID=""
  [ "$rc" != 99 ] || fail "the run never came back: it is still waiting out a window that never moves"

  assert_equal "$rc" "4"
  assert_file_contains "$RALPH_TEST_DIR/loop.out" "the session window is spent — pausing"
  assert_file_contains "$RALPH_TEST_DIR/loop.out" "still says blocked after a pause that ran all the way to its reset"
  assert_equal "$(claude_call_count)" "0"
  assert_ticket_status 01-alpha ready-for-agent
}

@test "a weekly limit stops the run instead of holding a process open for days" {
  use_tickets 01-alpha
  usage_respond "$(budget_payload 0.10 "$(budget_soon 3600)" 0.85 "$(budget_soon 200000)")"

  run_loop
  # Exit 6 and not 4: this is the one stop that lifts on its own at a known
  # instant, which is what a one-shot successor is scheduled on ([09]).
  assert_failure 6
  assert_output_contains "the weekly usage limit blocks this run (seven_day"
  assert_output_contains "[09]"
  assert_equal "$(claude_call_count)" "0"
  assert_ticket_status 01-alpha ready-for-agent
  assert_file_contains "$FEATURE_DIR/run.log" "budget-wall"
}

@test "the weekly opus limit is watched only by a run that spends it" {
  # A haiku night gated on a limit it does not touch would be a refusal nobody
  # could act on: the ticket is fine, the model is fine, and there is nothing to
  # do but wait a week.
  use_tickets 01-alpha
  set_config MODEL "test-model"
  usage_respond "$(budget_payload 0.10 "$(budget_soon 3600)" 0.05 "$(budget_soon 200000)" 0.99)"

  run_loop
  assert_success
  assert_ticket_status 01-alpha resolved
}

@test "the weekly opus limit stops a run that does spend it" {
  # The twin of the test above: without it, a module that ignored the opus window
  # outright would pass that one.
  use_tickets 01-alpha
  set_config MODEL "claude-opus-5"
  usage_respond "$(budget_payload 0.10 "$(budget_soon 3600)" 0.05 "$(budget_soon 200000)" 0.99)"

  run_loop
  assert_failure 6
  assert_output_contains "seven_day_opus is at 99%"
  assert_equal "$(claude_call_count)" "0"
}

@test "a reset further out than the cap is not slept to, it is reported" {
  # A session window resets within five hours. Further out than the cap means a
  # clock that is wrong, an endpoint that is wrong, or a stream a session wrote —
  # and a run that clamped would sleep the cap and find the same wall. Stopping
  # is visible in the morning; six hours of sleeping is a night nobody hears about.
  #
  # The reset is fifteen seconds out and the cap is three, rather than the day
  # out a real skew would give: without the cap this run sleeps to the reset,
  # finds the same wall and stops as the *previous* test's case, so the exit code
  # is wrong and the assertion is red after fifteen seconds rather than never.
  use_tickets 01-alpha
  set_config BUDGET_MAX_PAUSE 3
  usage_respond "$(budget_payload 0.99 "$(budget_soon 15)")"

  run_loop
  assert_failure 6
  assert_output_contains "not an instant this run can wait for"
  refute_output_contains "the session window is spent — pausing"
  assert_equal "$(claude_call_count)" "0"
}

@test "a stop asked for during a pause is honoured now, not at the reset" {
  # `sleep 3600` would hold a trapped signal for an hour: bash defers a trap
  # until the running external command returns ([25] paid for this once already,
  # in the gate's fan). The pause is stepped for exactly this, and the assertion
  # is the wall clock — a run that ignored the stop would come back in a minute.
  use_tickets 01-alpha
  usage_respond "$(budget_payload 0.99 "$(budget_soon 20)")"

  bash "$PACK_DIR/loop.sh" >"$RALPH_TEST_DIR/loop.out" 2>&1 &
  PACK_BG_PID=$!

  budget_wait_for_line "$RALPH_TEST_DIR/loop.out" "the session window is spent" ||
    fail "the loop never reached the pause"
  started="$(date +%s)"
  kill -TERM "$PACK_BG_PID"

  rc=0
  budget_wait_for_exit "$PACK_BG_PID" 40 || rc=$?
  PACK_BG_PID=""
  elapsed=$(($(date +%s) - started))

  assert_equal "$rc" "4"
  assert_file_contains "$RALPH_TEST_DIR/loop.out" "stopped on request during a budget pause"
  # The margin is what makes this an assertion rather than a hope: a pause that
  # held the trap comes back when the window resets, twenty seconds from now.
  [ "$elapsed" -lt 10 ] ||
    fail "the stop waited for the reset: $elapsed seconds to come back from a 20s pause"
}

# ── the classifier ───────────────────────────────────────────────────────────

@test "a session the API refused is not an attempt at the ticket" {
  # The fourth acceptance criterion. The session exits non-zero, which on its own
  # is a crash — and a crash costs the ticket one of its retries and escalates it
  # to a human as a failed implementation. Nothing about this ticket failed.
  use_tickets 01-alpha
  set_config STERILE_K 1
  script_refused_session blocked five_hour "$(budget_soon 1)"

  run_loop
  # Exit 4: the sterile detector, which is what bounds this path — and it is
  # measured by the loop rather than read out of the stream, so a session cannot
  # buy itself an unbounded number of free attempts by forging the event.
  assert_failure 4
  assert_output_contains "the session was refused for quota (five_hour)"
  assert_output_contains "given back with no retry consumed"
  assert_output_contains "sterile run"

  assert_ticket_status 01-alpha ready-for-agent
  run ticket_has_field 01-alpha Failures
  assert_failure
  assert_file_contains "$FEATURE_DIR/run.log" "budget-pause"
}

@test "a refused session does not leave half a file for the next iteration to adopt" {
  # [07] wrote that a budget pause must not roll the tree back, and two tickets
  # have moved the ground since. What an iteration leaves in the tree becomes the
  # *base* of the next one ([34], [35]): a half-written file nobody undoes stops
  # being anybody's change, and the ticket that inherits it goes green carrying
  # it. Not billing the ticket is one thing; leaving the repository dirty is
  # another, and only the first of the two was ever the point.
  use_tickets 01-alpha
  set_config STERILE_K 1
  script_refused_session blocked five_hour "$(budget_soon 1)" \
    'mkdir -p src && printf "half\n" >src/half-written.txt'

  run_loop
  assert_failure 4
  assert_output_contains "given back with no retry consumed"
  refute_file_exists "$PROJECT_DIR/src/half-written.txt"
}

@test "an ignore rule widened by a refused session goes back with the rest" {
  # Which classes reach `failures_handle` with nobody having put the ignore rules
  # back is a `case`, and reading it rather than remembering it is the whole
  # method of [32] — that ticket closed the one path it had in mind and missed
  # the two [23] had added two days earlier. `budget` is the sixth entry, and it
  # is on the list because the list was read.
  use_tickets 01-alpha
  set_config STERILE_K 1
  script_refused_session blocked five_hour "$(budget_soon 1)" \
    'printf "rogue/\n" >>.git/info/exclude; mkdir -p rogue && printf "backdoor\n" >rogue/backdoor'

  run_loop
  assert_failure 4
  assert_output_contains "moved the ignore frontier in .git/info/exclude"
  assert_output_contains "(put back)"
  refute_file_contains "$PROJECT_DIR/.git/info/exclude" "rogue/"
  refute_file_exists "$PROJECT_DIR/rogue/backdoor"
}

@test "a session that died with the budget intact is still a crash" {
  # The twin of the test above, and the reason it has to exist: a classifier that
  # answered "budget" to every non-zero exit would satisfy that one completely.
  use_tickets 01-alpha
  set_config STERILE_K 1
  set_config RETRY_N 2
  script_refused_session allowed five_hour "$(budget_soon 3600)"

  run_loop
  assert_failure 4
  assert_output_contains "01-alpha: crash -> fresh retry (1 of 2)"
  assert_equal "$(ticket_field 01-alpha Failures)" "1"
  refute_output_contains "given back with no retry consumed"
}

@test "a red gate is not forgiven for being hungry" {
  # The boundary of the classifier, and it is the one that keeps it honest. A red
  # gate is evidence that something was looked at and found wrong; the
  # subscription running out afterwards does not take that evidence away. If it
  # did, a red gate would be free to any session willing to write one line into
  # its own stream.
  use_tickets 01-alpha
  set_config STERILE_K 1
  set_config RETRY_N 2
  stub_exit tests 1
  claude_rate_limit "{\"status\":\"blocked\",\"resetsAt\":$(budget_soon 1),\"rateLimitType\":\"five_hour\",\"isUsingOverage\":false}"

  run_loop
  assert_failure 4
  assert_output_contains "01-alpha: gate-red -> fresh retry (1 of 2)"
  assert_equal "$(ticket_field 01-alpha Failures)" "1"
}

@test "a session that delivered nothing on an empty subscription is not billed for it" {
  # The [35] interaction, and it is why "budget?" is asked of more than a non-zero
  # exit. A session the API refused writes nothing, so the delivery refusal fires
  # first — and it would bill a retry and send a human to work out why this ticket
  # makes a session do nothing. The answer would have been "the subscription was
  # empty".
  use_tickets 01-alpha
  set_config STERILE_K 1
  session_writes_nothing
  claude_rate_limit "{\"status\":\"blocked\",\"resetsAt\":$(budget_soon 1),\"rateLimitType\":\"five_hour\",\"isUsingOverage\":false}"

  run_loop
  assert_failure 4
  assert_output_contains "given back with no retry consumed"
  refute_output_contains "nothing-delivered -> fresh retry"
  run ticket_has_field 01-alpha Failures
  assert_failure
}

@test "a session a deadline cut is a timeout, whatever its stream says about quota" {
  # A reason the monitor took is a fact this pack measured; a reason read out of
  # the session's own stream is a claim ([23]). The claim must not overwrite the
  # measurement — a session that hangs would otherwise be free for the price of
  # one forged line, and the re-slice and retry policy would never see it.
  use_tickets 01-alpha
  set_config SESSION_STALL_TIMEOUT 2
  set_config STERILE_K 1

  script_claude <<FAKE
#!/usr/bin/env bash
cat >/dev/null
echo '{"type":"system","subtype":"init","session_id":"s"}'
echo '{"type":"rate_limit_event","rate_limit_info":{"status":"blocked","resetsAt":$(budget_soon 1),"rateLimitType":"five_hour"}}'
i=0
while [ \$i -lt 300 ]; do sleep 0.1; i=\$((i + 1)); done
exit 0
FAKE

  run_loop
  assert_failure 4
  assert_output_contains "hung, terminated"
  assert_equal "$(ticket_field 01-alpha Failures)" "1"
  refute_output_contains "given back with no retry consumed"
}

@test "the in-band signal decides the next spawn when the endpoint says nothing" {
  # What the free source is for: the endpoint is unreadable here — no token, no
  # network, the ordinary case — and the loop still declines to spawn into a wall
  # it has already been told about. It may only ever make this run more cautious.
  use_tickets 01-alpha 02-beta
  set_config STERILE_K 3
  set_config BUDGET_MAX_PAUSE 60
  usage_respond ''
  script_refused_session blocked seven_day "$(budget_soon 200)"

  run_loop
  # The stream said a *weekly* window, which this run must not sleep through.
  assert_failure 6
  assert_output_contains "the last session was told it is blocked (seven_day)"
  assert_output_contains "the weekly usage limit blocks this run"
  # One session, and the second ticket was never started.
  assert_equal "$(claude_call_count)" "1"
  assert_ticket_status 02-beta ready-for-agent
}

# ── the switch, and the preflight ────────────────────────────────────────────

@test "a project can run without a usage budget, and the run says so" {
  use_tickets 01-alpha
  set_config BUDGET_CHECK off

  run_loop
  assert_success
  assert_ticket_status 01-alpha resolved
  assert_output_contains "the usage budget is not watched (BUDGET_CHECK=off)"
  # Nothing asked, which is the point of the switch — and the assertion that
  # keeps `off` from meaning "ask and ignore".
  assert_equal "$(curl_call_count)" "0"
}

@test "a BUDGET_CHECK that is neither on nor off is refused, not read as off" {
  use_tickets 01-alpha
  set_config BUDGET_CHECK ON

  run_loop
  assert_failure 2
  assert_output_contains "BUDGET_CHECK"
  assert_output_contains "it has to be on or off"
  assert_equal "$(claude_call_count)" "0"
}

@test "a threshold that is not a fraction is refused at the door" {
  # Both directions of the same shape: read as zero it blocks every spawn and the
  # run pauses for ever, and above 1 nothing ever crosses it. Neither says so.
  use_tickets 01-alpha

  set_config THRESH_5H "95%"
  run_loop
  assert_failure 2
  assert_output_contains "THRESH_5H"

  set_config THRESH_5H "0.95"
  set_config THRESH_WEEK "0"
  run_loop
  assert_failure 2
  assert_output_contains "THRESH_WEEK"
}

@test "the three keys that would leave the budget unmeasured in silence are refused too" {
  # Written against the criterion — which value of which key leaves this watch
  # looking exactly like a watch while measuring nothing ([31]) — rather than
  # against the cases that prompted it. An empty User-Agent gets 429s for ever, an
  # empty URL asks nobody, and a cap of zero turns every window into a stopped run.
  use_tickets 01-alpha

  set_config USAGE_UA ""
  run_loop
  assert_failure 2
  assert_output_contains "USAGE_UA is empty"

  set_config USAGE_UA "claude-code/2.1.220"
  set_config USAGE_URL ""
  run_loop
  assert_failure 2
  assert_output_contains "USAGE_URL is empty"

  set_config USAGE_URL "https://api.anthropic.com/api/oauth/usage"
  set_config BUDGET_MAX_PAUSE "0"
  run_loop
  assert_failure 2
  assert_output_contains "BUDGET_MAX_PAUSE"

  set_config BUDGET_MAX_PAUSE "21600"
  set_config USAGE_CACHE_TTL "three minutes"
  run_loop
  assert_failure 2
  assert_output_contains "USAGE_CACHE_TTL"

  # And the refutation: put them all back and the same project runs. Without it,
  # a preflight that refused everything would satisfy every assertion above.
  set_config USAGE_CACHE_TTL "180"
  usage_respond "$(budget_payload 0.10 "$(budget_soon 3600)")"
  run_loop
  assert_success
  assert_ticket_status 01-alpha resolved
}

# ── against the real endpoint ────────────────────────────────────────────────

@test "the real usage endpoint answers something this pack can read" {
  # The other half of what [20] does for the session stream, and the reason it is
  # opt-in is the same: network, a credential, and a live account. Everything
  # above drives a fake whose payload this repository invented, so until a human
  # runs this, "the pack can read that payload" is an assumption — and it is
  # written down as one in docs/frontiere-de-confiance.md rather than implied by
  # a green suite.
  #
  #   RALPH_REAL_USAGE=1 USAGE_TOKEN_CMD='...' test/run.sh test/budget.bats
  if [ "${RALPH_REAL_USAGE:-0}" != 1 ]; then
    skip "set RALPH_REAL_USAGE=1 to run this against the real endpoint (network + a credential)"
  fi
  if [ -z "${USAGE_TOKEN_CMD:-}" ]; then
    skip "USAGE_TOKEN_CMD is not set: the endpoint needs a bearer token"
  fi

  # The real curl, not the shim: the whole point is what the endpoint answers.
  run env PATH="$(printf '%s' "$PATH" | sed "s#$SHIM_BIN:##")" \
    RALPH_CONFIG="$RALPH_CONFIG_FILE" bash -c '
      set -uo pipefail
      RALPH_DIR="$1"
      export RALPH_DIR
      . "$RALPH_CONFIG"
      for lib in "$RALPH_DIR"/lib/*.sh; do . "$lib"; done
      USAGE_TOKEN_CMD="$2"
      body="$(budget__request)"
      for window in five_hour seven_day seven_day_opus; do
        printf "%s: %s\n" "$window" "$(budget__window "$body" "$window" || echo UNREADABLE)"
      done
    ' _ "$PACK_DIR" "${USAGE_TOKEN_CMD:-}"

  assert_success
  refute_output_contains "UNREADABLE"
}
