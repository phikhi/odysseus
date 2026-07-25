#!/usr/bin/env bats
#
# The `local` tracker adapter and the state model it carries.
#
# Everything is asserted on the markdown itself, read by the harness rather
# than by the pack: a reader shared with the implementation could not catch the
# implementation writing nonsense.

load helpers/harness
load helpers/assert

setup() {
  harness_setup
  use_tickets
}

teardown() {
  harness_teardown
}

# ── frontier ─────────────────────────────────────────────────────────────────

@test "the frontier is open, unblocked, ready-for-agent, unclaimed — min-NN first" {
  pack_run 'tracker_frontier'
  assert_success
  assert_equal "$output" "01-alpha
02-beta
07-overlaps-alpha
08-no-write-surface"
}

@test "resolving a blocker moves the blocked ticket into the frontier" {
  pack_run 'tracker_frontier'
  refute_output_contains "03-blocked"

  pack_run 'tracker_mark_resolved 01-alpha'
  assert_success
  assert_ticket_status 01-alpha resolved

  pack_run 'tracker_frontier'
  assert_output_contains "03-blocked"
  refute_output_contains "01-alpha"
}

@test "a blocker pointing at nothing keeps the ticket out of the frontier" {
  cat >"$(ticket_file 10-ghost-blocker)" <<'TICKET'
# 10 — Ghost blocker

**Blocked by:** 42

**Status:** ready-for-agent
TICKET

  pack_run 'tracker_frontier'
  assert_success
  refute_output_contains "10-ghost-blocker"
}

@test "every blocker must be resolved, not just the first" {
  cat >"$(ticket_file 11-two-blockers)" <<'TICKET'
# 11 — Two blockers

**Blocked by:** 01, 02

**Status:** ready-for-agent
TICKET

  pack_run 'tracker_mark_resolved 01-alpha; tracker_frontier'
  assert_success
  refute_output_contains "11-two-blockers"

  pack_run 'tracker_mark_resolved 02-beta; tracker_frontier'
  assert_output_contains "11-two-blockers"
}

@test "select_next_ticket takes the lowest NN, and nothing on an empty frontier" {
  pack_run 'select_next_ticket'
  assert_success
  assert_equal "$output" "01-alpha"

  pack_run 'select_frontier_count'
  assert_equal "$output" "4"

  # Resolving the frontier unblocks 03, so grind until nothing is left.
  pack_run 'while [ -n "$(tracker_frontier)" ]; do
              for t in $(tracker_frontier); do tracker_mark_resolved "$t"; done
            done
            select_next_ticket'
  assert_success
  assert_equal "$output" ""

  pack_run 'select_frontier_count'
  assert_equal "$output" "0"
}

# ── claim ────────────────────────────────────────────────────────────────────

@test "claim stamps an owner and takes the ticket out of the frontier" {
  pack_run 'tracker_claim 01-alpha pid:4242'
  assert_success

  assert_ticket_status 01-alpha claimed
  run ticket_field 01-alpha Claimed
  assert_output_contains "owner=pid:4242"
  assert_output_contains "at=20"

  pack_run 'tracker_frontier'
  refute_output_contains "01-alpha"
}

@test "a second claim on the same ticket loses" {
  pack_run 'tracker_claim 01-alpha pid:1'
  assert_success

  pack_run 'tracker_claim 01-alpha pid:2'
  assert_failure

  run ticket_field 01-alpha Claimed
  assert_output_contains "owner=pid:1"
}

@test "a claim being taken by a live picker is not stolen" {
  guard="$(ticket_file 01-alpha).guard"
  mkdir -p "$guard"
  printf '%s\n' "$$" >"$guard/pid" # this very test process: unquestionably alive

  pack_run 'tracker_claim 01-alpha pid:2'
  assert_failure
  assert_ticket_status 01-alpha ready-for-agent
  assert_equal "$(cat "$guard/pid")" "$$"
}

@test "a claim guard whose holder died is recovered" {
  bash -c 'exit 0' &
  dead=$!
  wait "$dead" 2>/dev/null || true

  guard="$(ticket_file 01-alpha).guard"
  mkdir -p "$guard"
  printf '%s\n' "$dead" >"$guard/pid"

  pack_run 'tracker_claim 01-alpha pid:2'
  assert_success
  assert_output_contains "stale claim guard"
  assert_ticket_status 01-alpha claimed

  [ ! -d "$guard" ] || fail "the guard outlived the claim"
}

@test "the claim guard is released and never shows up as a ticket" {
  pack_run 'tracker_claim 01-alpha pid:1'
  assert_success

  [ ! -d "$(ticket_file 01-alpha).guard" ] || fail "the guard outlived the claim"

  run bash -c "ls '$TRACKER_DIR' | grep -v '\.md\$' || true"
  assert_equal "$output" ""
}

@test "unclaim gives the ticket back and clears the stamp" {
  pack_run 'tracker_claim 01-alpha pid:1; tracker_unclaim 01-alpha'
  assert_success

  assert_ticket_status 01-alpha ready-for-agent
  run ticket_has_field 01-alpha Claimed
  assert_failure

  pack_run 'tracker_frontier'
  assert_output_contains "01-alpha"
}

# ── marking ──────────────────────────────────────────────────────────────────

@test "mark_escalated records a reason and leaves the AFK frontier" {
  pack_run 'tracker_claim 01-alpha pid:1; tracker_mark_escalated 01-alpha failed-impl'
  assert_success

  assert_ticket_status 01-alpha ready-for-human
  run ticket_field 01-alpha Escalation
  assert_equal "$output" "failed-impl"
  run ticket_has_field 01-alpha Claimed
  assert_failure

  pack_run 'tracker_frontier'
  refute_output_contains "01-alpha"
}

@test "mark_escalated refuses to escalate without a reason" {
  pack_run 'tracker_mark_escalated 01-alpha'
  assert_failure
  assert_ticket_status 01-alpha ready-for-agent
}

@test "mark_ready re-injects an escalated ticket and clears the escalation" {
  pack_run 'tracker_mark_ready 09-escalated'
  assert_success

  assert_ticket_status 09-escalated ready-for-agent
  run ticket_has_field 09-escalated Escalation
  assert_failure

  pack_run 'tracker_frontier'
  assert_output_contains "09-escalated"
}

@test "bump_failures counts from zero and from an existing count" {
  pack_run 'tracker_bump_failures 01-alpha'
  assert_success
  assert_equal "$output" "1"
  run ticket_field 01-alpha Failures
  assert_equal "$output" "1"

  pack_run 'tracker_bump_failures 01-alpha'
  assert_equal "$output" "2"

  # 09 already carries Failures: 2
  pack_run 'tracker_bump_failures 09-escalated'
  assert_equal "$output" "3"
}

@test "marking preserves everything else in the ticket" {
  pack_run 'tracker_mark_resolved 07-overlaps-alpha'
  assert_success

  file="$(ticket_file 07-overlaps-alpha)"
  assert_file_contains "$file" "# 07 — Overlaps alpha"
  assert_file_contains "$file" '**Write-surface:** `src/alpha.txt`, `src/eta.txt`'
  assert_file_contains "$file" "- [ ] \`src/eta.txt\` exists."
}

# ── the remaining operations ─────────────────────────────────────────────────

@test "read_ticket returns the ticket and field reads one field" {
  pack_run 'tracker_read_ticket 01-alpha'
  assert_success
  assert_output_contains "# 01 — Alpha"
  assert_output_contains "src/alpha.txt"

  pack_run 'tracker_field 07-overlaps-alpha Write-surface'
  assert_equal "$output" '`src/alpha.txt`, `src/eta.txt`'

  pack_run 'tracker_read_ticket 99-nope'
  assert_failure
}

@test "a ticket can be addressed by number alone" {
  pack_run 'tracker_field 01 Status'
  assert_success
  assert_equal "$output" "ready-for-agent"
}

@test "open_ticket creates the next NN and lands it in the frontier" {
  pack_run 'printf "%s\n" "**What to build:** Wire the marker into the page." | tracker_open_ticket wiring "Wire the marker"'
  assert_success
  assert_equal "$output" "10-wiring"

  assert_ticket_status 10-wiring ready-for-agent
  assert_file_contains "$(ticket_file 10-wiring)" "# 10 — Wire the marker"
  assert_file_contains "$(ticket_file 10-wiring)" "Wire the marker into the page."
  assert_file_contains "$(ticket_file 10-wiring)" "**Blocked by:** None"

  pack_run 'tracker_frontier'
  assert_output_contains "10-wiring"
}

@test "append_note opens the Comments section once and appends under it" {
  pack_run 'printf "%s\n" "first note" | tracker_append_note 01-alpha'
  assert_success
  pack_run 'printf "%s\n" "second note" | tracker_append_note 01-alpha'
  assert_success

  file="$(ticket_file 01-alpha)"
  assert_file_contains "$file" "first note"
  assert_file_contains "$file" "second note"
  run bash -c "grep -c '^## Comments' '$file'"
  assert_equal "$output" "1"

  # An existing Comments section is reused, not duplicated.
  pack_run 'printf "%s\n" "third note" | tracker_append_note 09-escalated'
  run bash -c "grep -c '^## Comments' '$(ticket_file 09-escalated)'"
  assert_equal "$output" "1"
}

@test "emit_receipt writes the receipt outside the tracker" {
  pack_run 'printf "%s\n" "gate: 4 green" | tracker_emit_receipt 01-alpha'
  assert_success
  assert_equal "$output" "$PROJECT_DIR/receipts/demo/01-alpha.md"

  assert_file_contains "$PROJECT_DIR/receipts/demo/01-alpha.md" "gate: 4 green"
  refute_file_exists "$TRACKER_DIR/01-alpha.md.tmp"
}

# ── the interface itself ─────────────────────────────────────────────────────

@test "an unimplemented backend fails loudly instead of silently" {
  set_config TRACKER_BACKEND github
  pack_run 'tracker_frontier'
  assert_failure 3
  assert_output_contains 'backend "github" does not implement frontier'
}

# ── atomicity ────────────────────────────────────────────────────────────────

# Racing a reader against a writer proves nothing here: the truncation window
# is microseconds and a bash reader is milliseconds, so such a test passes just
# as happily without any atomicity at all. These two are deterministic instead.

@test "marking publishes by rename, never by rewriting the ticket in place" {
  file="$(ticket_file 01-alpha)"
  before="$(ls -i "$file" | awk '{print $1}')"

  pack_run 'tracker_mark_resolved 01-alpha'
  assert_success

  after="$(ls -i "$file" | awk '{print $1}')"
  [ "$before" != "$after" ] ||
    fail "the ticket kept inode $before: it was written in place, so a crash mid-write truncates it"

  assert_ticket_status 01-alpha resolved
  assert_file_contains "$file" "# 01 — Alpha"
}

@test "a read-only ticket is still markable — the rename goes through the directory" {
  file="$(ticket_file 01-alpha)"
  chmod 444 "$file"

  pack_run 'tracker_mark_resolved 01-alpha'
  assert_success

  assert_ticket_status 01-alpha resolved
  assert_file_contains "$file" "# 01 — Alpha"
}

@test "no temp file is ever left where a frontier scan would find it" {
  pack_run 'tracker_claim 01-alpha pid:1
            tracker_mark_resolved 01-alpha
            tracker_bump_failures 02-beta
            tracker_mark_escalated 02-beta failed-impl'
  assert_success

  run bash -c "ls '$TRACKER_DIR' | grep -v '\.md\$' || true"
  assert_equal "$output" ""

  pack_run 'tracker_frontier'
  assert_equal "$output" "03-blocked
07-overlaps-alpha
08-no-write-surface"
}

# ── the tracker is the only authority ────────────────────────────────────────

@test "the tracker alone rebuilds the state" {
  pack_run 'tracker_claim 02-beta pid:7
            tracker_mark_escalated 07-overlaps-alpha spec-gap
            tracker_bump_failures 01-alpha'
  assert_success

  pack_run 'tracker_frontier'
  before="$output"

  # Move the tracker into an otherwise empty project: same answers, so nothing
  # a run needs lives outside it.
  mkdir -p "$RALPH_TEST_DIR/clone"
  cp -R "$PROJECT_DIR/.scratch" "$RALPH_TEST_DIR/clone/.scratch"

  pack_run "export RALPH_PROJECT_ROOT='$RALPH_TEST_DIR/clone'; tracker_frontier"
  assert_success
  assert_equal "$output" "$before"

  pack_run "export RALPH_PROJECT_ROOT='$RALPH_TEST_DIR/clone'; tracker_field 07-overlaps-alpha Escalation"
  assert_equal "$output" "spec-gap"

  pack_run "export RALPH_PROJECT_ROOT='$RALPH_TEST_DIR/clone'; tracker_field 01-alpha Failures"
  assert_equal "$output" "1"

  pack_run "export RALPH_PROJECT_ROOT='$RALPH_TEST_DIR/clone'; tracker_field 02-beta Claimed"
  assert_output_contains "owner=pid:7"
}
