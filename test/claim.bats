#!/usr/bin/env bats
#
# Claim liveness: who still holds a ticket, and what happens to one nobody holds.
#
# The fault this closes was probed on 28/07/2026: SIGKILL a run mid-session and
# its ticket stays `claimed` for ever, because the frontier is `ready-for-agent`
# and nothing asked whether the owner still existed. The next run then grinds
# whatever is left and reports `exit 0` — "this run ground everything it could" —
# which is true and hides a ticket that has quietly left the board.
#
# Two halves, and both belong here. The sweep is external behaviour: a run either
# grinds the reclaimed ticket or it does not, which is what the end-to-end tests
# below assert. The policy is the exception the spec grants to unit testing
# (§202): pid, TTL and fail-open are pure decisions whose combinatorics an
# end-to-end test would cover badly and slowly.

load helpers/harness
load helpers/assert

setup() {
  harness_setup
}

teardown() {
  harness_teardown
}

# A pid above the default maximum on both macOS and Linux, so it belongs to
# nothing and `kill -0` says so.
DEAD_PID=999999
LAST_WEEK=2026-07-25T08:00:00Z

now_iso() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# The claim record as the tracker writes it, for a process that is really alive.
live_record() {
  printf 'owner=pid:%s at=%s' "$$" "$(now_iso)"
}

# ── the policy ───────────────────────────────────────────────────────────────

@test "a claim whose owner is still running is held" {
  use_tickets 01-alpha
  pack_run "claim_is_held '$(live_record)' && echo held"
  assert_success
  assert_output_contains "held"
}

@test "a claim whose owner is gone is reclaimable" {
  use_tickets 01-alpha
  pack_run "claim_is_held 'owner=pid:$DEAD_PID at=$(now_iso)'"
  assert_failure
}

@test "the TTL reclaims a claim whose owner still answers, and the TTL comes from the config" {
  # The anti-pid-recycling backstop: a recycled pid answers `kill -0` on behalf of
  # a process that has nothing to do with the run that took the claim, for ever.
  # Asserted on both sides of one claim — same live owner, same timestamp, three
  # TTLs — because a test that checked one side only would pass just as happily
  # against a hard-coded number.
  use_tickets 01-alpha
  local stale="owner=pid:$$ at=$LAST_WEEK"

  set_config CLAIM_TTL 5400
  pack_run "claim_is_held '$stale'"
  assert_failure

  set_config CLAIM_TTL 999999999
  pack_run "claim_is_held '$stale' && echo held"
  assert_success
  assert_output_contains "held"

  # Zero is "no backstop", the reading GATE_TIMEOUT gives a missing deadline.
  set_config CLAIM_TTL 0
  pack_run "claim_is_held '$stale' && echo held"
  assert_success
  assert_output_contains "held"
}

@test "everything uncertain counts as reclaimable, never as held" {
  # Fail-open, strictly. A claim nobody can prove alive has to come back, or one
  # crashed run costs a ticket permanently — the whole fault being closed here.
  use_tickets 01-alpha
  local record

  for record in \
    "" \
    "owner=pid:$$" \
    "at=$(now_iso)" \
    "owner=pid: at=$(now_iso)" \
    "owner=pid:abc at=$(now_iso)" \
    "owner=pid:$$ at=yesterday" \
    "owner=pid:$$ at=2026-07-25" \
    "owner=pid:$$ at=2099-01-01T00:00:00Z"; do
    pack_run "claim_is_held '$record' && echo held"
    assert_failure
  done
}

@test "an owner this pack cannot ping waits out the TTL instead of being reclaimed on sight" {
  # A remote backend renders the claim as an assignee (spec §152). Reclaiming it
  # because `kill -0` cannot be asked would steal a ticket from a human; the
  # backstop is what keeps it from wedging for ever.
  use_tickets 01-alpha
  set_config CLAIM_TTL 5400

  pack_run "claim_is_held 'owner=assignee:alice at=$(now_iso)' && echo held"
  assert_success
  assert_output_contains "held"

  pack_run "claim_is_held 'owner=assignee:alice at=$LAST_WEEK'"
  assert_failure
}

@test "the age of a claim is read without asking date to parse anything" {
  # `date -d` is GNU and `date -j -f` is BSD; the pack runs on a stock macOS
  # shell, so the conversion is arithmetic. Checked against three fixed points —
  # the epoch, a leap day, the timestamp the fixtures use — whose values come from
  # `date -u -jf %Y-%m-%dT%H:%M:%SZ`: a wrong leap rule shifts every TTL decision
  # by a day, and no behavioural test in this file would notice.
  use_tickets 01-alpha

  pack_run 'claim__epoch_of_iso 1970-01-01T00:00:00Z'
  assert_success
  assert_equal "$output" "0"

  pack_run 'claim__epoch_of_iso 2024-02-29T00:00:00Z'
  assert_success
  assert_equal "$output" "1709164800"

  pack_run "claim__epoch_of_iso $LAST_WEEK"
  assert_success
  assert_equal "$output" "1784966400"

  # And the age of a claim taken now is a few seconds, not a count since 1970.
  pack_run 'claim_age_seconds "owner=pid:$$ at=$(ralph_now)"'
  assert_success
  case "$output" in
    0 | 1 | 2) ;;
    *) fail "a claim taken this second came back $output seconds old" ;;
  esac
}

# ── the sweep ────────────────────────────────────────────────────────────────

@test "a ticket claimed by a run that died comes back to the frontier and is ground" {
  use_tickets 01-alpha
  stamp_claim 01-alpha "pid:$DEAD_PID" "$LAST_WEEK"

  run_loop
  assert_success
  assert_output_contains "reclaimed 01-alpha from an owner that is gone -> retry"
  assert_output_contains "iteration 1: 01-alpha -> resolved"

  assert_ticket_status 01-alpha resolved

  # Ground, not just marked: a session really ran for it.
  # 1 delivery session and the terminal value gate the drained
  # frontier runs ([11]) — counted apart, so the total says which they were.
  assert_equal "$(claude_call_count)" "2"
  assert_equal "$(playthrough_call_count)" "1"
  run claude_call_stdin 1
  assert_output_contains "01-alpha"
}

@test "a run whose only ticket was claimed by a dead owner does not report an empty frontier" {
  # Exit 5 is "nothing to grind" and exit 0 is "the frontier was drained". Before
  # the sweep, a tracker holding one ticket claimed by a run that had been killed
  # answered one of those for a night in which the ticket was perfectly grindable
  # — the distinction the loop takes care to make, undone.
  use_tickets 01-alpha
  stamp_claim 01-alpha "pid:$DEAD_PID" "$LAST_WEEK"

  run_loop
  assert_success
  assert_output_contains "frontier empty after 1 iterations"
  refute_output_contains "nothing to grind"
}

@test "a claim held by a live run is left alone by the sweep" {
  # The other half, and the one that makes the first mean something: the sweep
  # reclaims because the owner is gone, not because a ticket is claimed.
  use_tickets 01-alpha 04-claimed

  run_loop
  assert_success
  refute_output_contains "reclaimed 04-claimed"

  assert_ticket_status 04-claimed claimed
  assert_ticket_status 01-alpha resolved
  refute_file_exists "$PROJECT_DIR/src/delta.txt"
  run ticket_field 04-claimed Claimed
  assert_output_contains "owner=pid:$$"
}

# ── an id is the name of a file somebody chose ───────────────────────────────

@test "a claim on a ticket whose name carries a space is still swept" {
  # [37]. The sweep walked `for id in $(tracker_ids)`, so `01-alpha bis` was two
  # ids nothing carries: both `tracker_field` reads failed, `continue` took the
  # loop past them, and the ticket that really was claimed by a dead run was never
  # looked at. `claimed` for ever, out of the frontier, and nothing in the log to
  # say a ticket had left the board — the fault [12] closed, reopened for any
  # tracker whose file names are not one word.
  use_tickets 01-alpha
  mv "$(ticket_file 01-alpha)" "$TRACKER_DIR/01-alpha bis.md"
  stamp_claim "01-alpha bis" "pid:$DEAD_PID" "$LAST_WEEK"

  pack_run 'claim_reclaim_stale ""'
  assert_success
  assert_output_contains "01-alpha bis retry"
  assert_ticket_status "01-alpha bis" ready-for-agent
}

@test "a ticket in flight does not exempt another one that shares a word with it" {
  # The exemption list is the ids *this run* is holding ([13]), and it had the
  # mirror defect: a sibling called `02-beta bis` in flight fenced as
  # ` 02-beta bis `, which answered yes for a stale claim on `02-beta`. The
  # backstop that exists against a recycled pid was then switched off by a word.
  use_tickets 01-alpha 02-beta
  cp "$(ticket_file 02-beta)" "$TRACKER_DIR/02-beta bis.md"
  stamp_claim 02-beta "pid:$DEAD_PID" "$LAST_WEEK"

  pack_run 'claim_reclaim_stale "02-beta bis"'
  assert_success
  assert_output_contains "02-beta retry"
  assert_ticket_status 02-beta ready-for-agent

  # And the ticket the run really is holding is left alone, which is what makes
  # the assertion above about the words rather than about a sweep that ignores
  # its exemption list altogether.
  stamp_claim 01-alpha "pid:$DEAD_PID" "$LAST_WEEK"
  pack_run 'claim_reclaim_stale "01-alpha"'
  assert_success
  assert_equal "$output" ""
  assert_ticket_status 01-alpha claimed
}

@test "a reclaim consumes a retry, and a ticket that runs out of them goes to the human sink" {
  # A claim left behind by one of this pack's own runs is a crash nobody was alive
  # to classify, so it is counted like one. Without the counter, a ticket whose
  # session reliably kills the run would be reclaimed and killed again every night,
  # for ever, with nothing saying so.
  use_tickets 01-alpha
  stamp_claim 01-alpha "pid:$DEAD_PID" "$LAST_WEEK"
  set_config RETRY_N 0

  run_loop
  assert_failure 5

  assert_ticket_status 01-alpha ready-for-human
  run ticket_field 01-alpha Failures
  assert_output_contains "1"

  # And not as `failed-impl`: nothing was ever judged on this ticket, so a human
  # routed to implement/pair would go looking for a `failed/01-alpha` branch and a
  # red test suite that were never written ([26]). The note says which.
  run ticket_field 01-alpha Escalation
  assert_equal "$output" "decision"
  refute_output_contains "failed-impl"
  assert_file_contains "$(ticket_file 01-alpha)" "ran out on a reclaim, not on a verdict"
  assert_file_contains "$(ticket_file 01-alpha)" "pid:$DEAD_PID"

  # Escalated, so never spawned: the point of the ceiling is to stop grinding it.
  assert_equal "$(claude_call_count)" "0"
}

@test "an owner this pack never pinged costs the ticket nothing when the TTL takes it back" {
  # The other half of [26], and the one a human pays for. `claim.sh` refuses to
  # reclaim an owner it cannot ping on sight, on the grounds that stealing a human's
  # ticket would be worse than waiting out the backstop — and then the backstop
  # falls and the ticket is taken anyway. Fail-open is deliberate; billing an
  # implementation failure for it is the defect. With RETRY_N=0 the old behaviour
  # escalated on the very first sweep, without spawning anything.
  use_tickets 01-alpha
  stamp_claim 01-alpha "assignee:alice" "$LAST_WEEK"
  set_config RETRY_N 0

  run_loop
  assert_success
  assert_output_contains "reclaimed 01-alpha"

  # Ground, delivered, and never billed for the claim it was taken from.
  assert_ticket_status 01-alpha resolved
  run ticket_has_field 01-alpha Failures
  assert_failure
  # 1 delivery session and the terminal value gate the drained
  # frontier runs ([11]) — counted apart, so the total says which they were.
  assert_equal "$(claude_call_count)" "2"
  assert_equal "$(playthrough_call_count)" "1"

  # The steal is admitted where the person who lost the claim will look, and the
  # record is in it: `unclaim` drops the field, so this note is the last copy.
  assert_file_contains "$(ticket_file 01-alpha)" "assignee:alice"
  assert_file_contains "$(ticket_file 01-alpha)" "No retry was charged"
  assert_file_contains "$FEATURE_DIR/run.log" "reclaimed-returned"
}

@test "the probe [26] came from: three claims taken back, three green deliveries, no escalation" {
  # The scenario as it was probed on 29/07/2026, with the default RETRY_N — the two
  # defects had to compose to produce it, so neither fix alone closes it. A human
  # assigns themselves the ticket each morning and does not touch it; the run takes
  # it back each night once CLAIM_TTL has fallen, and delivers it green:
  #
  #   run 1 -> status=resolved        failures=[1]  escalation=[]
  #   run 2 -> status=resolved        failures=[2]  escalation=[]
  #   run 3 -> status=ready-for-human failures=[3]  escalation=[failed-impl]
  #
  # On the third night the ticket was escalated as a failed implementation without a
  # session being spawned at all, on a counter fed by claims nobody had judged and
  # cleared by nothing.
  use_tickets 01-alpha
  local n

  # Delivering something *new* each night, because the scenario is three green
  # deliveries and the default fake writes the same bytes every time: a second
  # night that leaves the tree exactly as it found it delivers nothing since [35],
  # and this test would be measuring that instead of the counter.
  script_claude <<'FAKE'
#!/usr/bin/env bash
cat >/dev/null
mkdir -p src && printf 'one more night\n' >>src/alpha.txt
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  for n in 1 2 3; do
    stamp_claim 01-alpha "assignee:alice" "$LAST_WEEK"
    run_loop
    assert_success
    assert_ticket_status 01-alpha resolved
    # Never charged, so never at the ceiling either — on any of the three nights.
    run ticket_has_field 01-alpha Failures
    assert_failure
    run ticket_has_field 01-alpha Escalation
    assert_failure
  done

  # And really ground each night, not marked from the sweep: three deliveries,
  # plus the terminal value gate each of those three nights closed on ([11]).
  # Counted apart, so the total says which sessions they were.
  assert_equal "$(claude_call_count)" "6"
  assert_equal "$(playthrough_call_count)" "3"

  # The end state alone cannot carry this test. Probed while writing it: with the
  # counter cleared on delivery, charging every reclaim leaves no trace by morning,
  # and with nothing charged the reset is never reached — either fix alone closes
  # the scenario, so neither can be caught here by removing the other. What the
  # journal says about each night can be: three claims handed back unbilled.
  run bash -c "grep -c 'reclaimed-returned' '$FEATURE_DIR/run.log'"
  assert_equal "$output" "3"
  run bash -c "grep -c 'reclaimed-retry' '$FEATURE_DIR/run.log' || true"
  assert_equal "$output" "0"
}

@test "the two causes of a retry are told apart: a reclaim, then a verdict" {
  # The counter has two causes and one field, so the escalation reason is what says
  # which one spent the last retry. Same ticket, one of each: a run that died
  # (charged, no verdict) and then a session judged red (charged, a verdict). The
  # ceiling falls on the second, so the reason is `failed-impl` and there is a
  # branch to read — which is exactly what the first cause may not claim.
  use_tickets 01-alpha
  stamp_claim 01-alpha "pid:$DEAD_PID" "$LAST_WEEK"
  set_config RETRY_N 1
  set_config STERILE_K 5
  stub_exit tests 1

  run_loop
  assert_success
  assert_output_contains "reclaimed 01-alpha from an owner that is gone -> retry"
  assert_output_contains "escalated to the human sink (failed-impl)"

  assert_ticket_status 01-alpha ready-for-human
  assert_equal "$(ticket_field 01-alpha Escalation)" "failed-impl"
  # One reclaim, one judged attempt, one session spawned for it.
  # 1 delivery session and the terminal value gate the drained
  # frontier runs ([11]) — counted apart, so the total says which they were.
  assert_equal "$(claude_call_count)" "2"
  assert_equal "$(playthrough_call_count)" "1"

  run git -C "$PROJECT_DIR" rev-parse --verify "refs/heads/failed/01-alpha"
  assert_success
}

@test "the reclaim is in the run journal, with what it decided" {
  # run.log is what an operator reads in the morning. A ticket that changed hands
  # because a run died has to be visible there without diffing the tracker.
  use_tickets 01-alpha 02-beta
  stamp_claim 02-beta "pid:$DEAD_PID" "$LAST_WEEK"

  run_loop
  assert_success

  run grep 02-beta "$FEATURE_DIR/run.log"
  assert_success
  assert_output_contains "reclaimed-retry"
  assert_ticket_status 02-beta resolved
}

@test "a run killed mid-session leaves a claim, and the next run reclaims it and grinds the ticket" {
  # The probe this ticket was opened from, run for real rather than staged: not a
  # stamped record but a run put down with SIGKILL while its session was live. No
  # trap fires, so the claim, the run lock and the session stream are all left
  # exactly where they were — which is the state a cron-started run actually
  # finds in the morning, and the one the rest of this file only imitates.
  use_tickets 01-alpha

  script_claude <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$$" >"$RALPH_SHIM_STATE/session.pid"
: >"$RALPH_SHIM_STATE/session.started"
# exec, so the recorded pid *is* the sleeping process: killing the script's shell
# would otherwise orphan a sleep of its own and the suite would leak one per run.
exec sleep 60
FAKE

  bash "$PACK_DIR/loop.sh" >"$RALPH_TEST_DIR/killed.log" 2>&1 &
  local killed=$!
  wait_for_file "$SHIM_STATE/session.started" || fail "the session never started"

  kill -KILL "$killed" 2>/dev/null || true
  wait "$killed" 2>/dev/null || true
  # The session is an orphan now, exactly as it would be after a real crash.
  # Nothing in the pack can reap it; the test does, so the suite leaves nothing.
  kill -KILL "$(cat "$SHIM_STATE/session.pid")" 2>/dev/null || true

  # If either of these is false this is not the scenario, and the assertions
  # below would prove something else.
  assert_ticket_status 01-alpha claimed
  [ -d "$(run_lock_dir)" ] || fail "SIGKILL somehow released the run lock"

  # An ordinary session for the run that comes next.
  rm -f "$SHIM_STATE/claude.script"

  run_loop
  assert_success
  assert_output_contains "reclaimed 01-alpha from an owner that is gone -> retry"
  assert_output_contains "frontier empty after 1 iterations"

  assert_ticket_status 01-alpha resolved
  # The reclaim charged a retry — the journal is where that is recorded — and the
  # green delivery that followed cleared the counter ([26]): a ticket that has just
  # been delivered starts its next visit to the frontier with its whole budget.
  assert_file_contains "$FEATURE_DIR/run.log" "reclaimed-retry"
  run ticket_has_field 01-alpha Failures
  assert_failure
}

@test "a claimed ticket with no claim record at all is reclaimed rather than wedged" {
  # `Status: claimed` and nothing else: a hand-edited ticket, a crash between the
  # two field writes, a session that forged the status. Unprovable, so reclaimable.
  use_tickets 01-alpha
  stamp_claim 01-alpha ''
  # RETRY_N=0: a record the pack cannot attribute to one of its own runs cannot be
  # called a crash either, so it charges nothing — otherwise this ticket would go
  # straight to the human sink instead of being ground.
  set_config RETRY_N 0

  run ticket_has_field 01-alpha Claimed
  assert_failure

  run_loop
  assert_success
  assert_ticket_status 01-alpha resolved
  run ticket_has_field 01-alpha Failures
  assert_failure
  assert_file_contains "$(ticket_file 01-alpha)" "no readable claim record"
}
