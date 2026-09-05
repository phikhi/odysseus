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

@test "mark_resolved clears the claim and the retry counter" {
  # The counter is a budget, not a history ([26]): a ticket that returns to the
  # frontier after a delivery returns for a new reason, with its whole budget.
  # Asserted at the adapter level as well as end to end, because it is an
  # obligation of the interface — a backend that keeps the field re-creates the
  # defect, and [18] is going to write one.
  pack_run 'tracker_claim 01-alpha pid:1
    tracker_bump_failures 01-alpha
    tracker_mark_resolved 01-alpha'
  assert_success

  assert_ticket_status 01-alpha resolved
  run ticket_has_field 01-alpha Claimed
  assert_failure
  run ticket_has_field 01-alpha Failures
  assert_failure
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

# ── what the tracker must survive being written by ───────────────────────────

@test "a ticket written with CRLF line endings is still on the frontier" {
  # A tracker checked out on Windows, or written by an editor that ends lines
  # the DOS way. The carriage return used to ride along in every field value,
  # so no status ever compared equal and the whole tracker went invisible —
  # a run that grinds nothing and calls it success.
  perl -pi -e 's/\n/\r\n/' "$(ticket_file 01-alpha)"

  pack_run 'tracker_frontier'
  assert_success
  assert_output_contains "01-alpha"

  pack_run 'tracker_field 01-alpha Status'
  assert_equal "$output" "ready-for-agent"
}

@test "a trailing space after a field value changes nothing" {
  perl -pi -e 's/\*\*Status:\*\* ready-for-agent$/**Status:** ready-for-agent  /' \
    "$(ticket_file 02-beta)"

  pack_run 'tracker_frontier'
  assert_output_contains "02-beta"
}

@test "a CRLF blocker line still blocks, and still unblocks" {
  perl -pi -e 's/\n/\r\n/' "$(ticket_file 03-blocked)"

  pack_run 'tracker_frontier'
  refute_output_contains "03-blocked"

  pack_run 'tracker_mark_resolved 01-alpha'
  pack_run 'tracker_frontier'
  assert_output_contains "03-blocked"
}

@test "a bare number matching two tickets is refused, not guessed" {
  # Dependencies are written as bare numbers, so resolving `01` to whichever
  # file sorts first would block — or unblock — the wrong ticket in silence.
  cp "$(ticket_file 01-alpha)" "$TRACKER_DIR/01-alpha-bis.md"

  pack_run 'tracker_field 01 Status'
  assert_failure
  assert_output_contains "ambiguous"

  # And a ticket depending on that number stays out of the frontier.
  pack_run 'tracker_frontier'
  refute_output_contains "03-blocked"
}

@test "an id that matches exactly one ticket still resolves by number alone" {
  pack_run 'tracker_field 02 Status'
  assert_success
  assert_equal "$output" "ready-for-agent"
}

# ── two tickets, one number ──────────────────────────────────────────────────
#
# The state above is not hypothetical: a session that renames a ticket file
# produces it out of two decisions that are each correct ([21] restores the
# deletion, quarantines the addition). Nothing used to get the tracker out of
# it, and every ticket holding `Blocked by: NN` left the frontier for good.

@test "renumber moves the ticket that collides and leaves the rest alone" {
  cp "$(ticket_file 01-alpha)" "$TRACKER_DIR/01-alpha-bis.md"
  pack_run 'tracker_field 01 Status'
  assert_failure

  pack_run 'tracker_renumber 01-alpha-bis'
  assert_success
  assert_equal "$output" "10-alpha-bis"

  assert_file_exists "$(ticket_file 10-alpha-bis)"
  refute_file_exists "$TRACKER_DIR/01-alpha-bis.md"
  assert_file_exists "$(ticket_file 01-alpha)"

  # The whole point: the bare number resolves again, so what depends on it can
  # come back to the frontier.
  pack_run 'tracker_field 01 Status'
  assert_success
  assert_equal "$output" "ready-for-agent"
  pack_run 'tracker_frontier'
  refute_output_contains "03-blocked"
  pack_run 'tracker_mark_resolved 01-alpha'
  pack_run 'tracker_frontier'
  assert_output_contains "03-blocked"
}

@test "renumber leaves an id nobody shares exactly where it is" {
  # The paired witness: without it the test above would pass on an implementation
  # that renumbers every ticket it is handed, which would move ids other tickets
  # point at — the very damage being repaired.
  pack_run 'tracker_renumber 02-beta'
  assert_success
  assert_equal "$output" "02-beta"
  assert_file_exists "$(ticket_file 02-beta)"
  refute_file_exists "$(ticket_file 10-beta)"
}

@test "a ticket named after the number alone is not a collision" {
  # `NN.md` is matched before the `NN-*` glob, so a bare number resolves to it
  # whatever else carries the number. Two `02-*` files are what makes this a test
  # rather than a restatement of the one above: without the exact-match rule the
  # renumber would move one of them, and nothing could have mis-resolved `02`.
  cp "$(ticket_file 02-beta)" "$TRACKER_DIR/02.md"
  cp "$(ticket_file 02-beta)" "$TRACKER_DIR/02-beta-bis.md"

  pack_run 'tracker_renumber 02-beta'
  assert_success
  assert_equal "$output" "02-beta"
  assert_file_exists "$(ticket_file 02-beta)"

  pack_run 'tracker_field 02 Status'
  assert_success
  assert_equal "$output" "ready-for-agent"
}

@test "a number too wide to be arithmetic does not stop the renumber" {
  # A session names the files it writes, so the highest number in the directory
  # is not a number the pack chose. awk renders this one in scientific notation
  # and `$(( ))` calls that a syntax error: the next free number came back empty,
  # and the renumber that keeps a bare number resolvable fell back to leaving the
  # collision exactly where it was — the guarantee above, defeated by a filename.
  cp "$(ticket_file 01-alpha)" "$TRACKER_DIR/01-alpha-bis.md"
  cp "$(ticket_file 01-alpha)" "$TRACKER_DIR/1000000000000000000000000000000-huge.md"

  pack_run 'tracker_renumber 01-alpha-bis'
  assert_success
  assert_equal "$output" "10-alpha-bis"

  pack_run 'tracker_field 01 Status'
  assert_success
}

@test "the next number is checked against the directory, not deduced from it" {
  # The other half: a ticket already carrying the number the count would hand
  # out. The count reads `NN-slug.md` names, so a ticket named after its number
  # alone is invisible to it — and the id it returns is one a file already has.
  cp "$(ticket_file 01-alpha)" "$TRACKER_DIR/10.md"

  pack_run 'printf "%s\n" "**What to build:** something" | tracker_open_ticket next "Next"'
  assert_success
  assert_equal "$output" "11-next"

  # Which is the damage being avoided: `10` used to resolve to a ticket, and a
  # second one carrying it takes every `Blocked by: 10` out of the frontier.
  assert_file_contains "$TRACKER_DIR/10.md" "# 01 — Alpha"
  refute_file_exists "$(ticket_file 10-next)"
}

@test "the preflight names the duplicate number and what it takes out of the frontier" {
  # A human can still write this by hand, and finding it ticket by ticket in the
  # middle of a night is what the scan exists to avoid.
  cp "$(ticket_file 01-alpha)" "$TRACKER_DIR/01-alpha-bis.md"

  pack_run 'tracker_preflight'
  assert_failure
  assert_output_contains "two or more tickets carry the number 01"
  assert_output_contains "01-alpha-bis, 01-alpha"
  assert_output_contains "03-blocked is blocked on 01"
  assert_output_contains "ambiguous-id"
}

@test "the preflight says nothing about a tracker with nothing wrong with it" {
  pack_run 'tracker_preflight'
  assert_success
  assert_equal "$output" ""
}

# ── an id is the name of a file somebody chose ───────────────────────────────

@test "the preflight names a carrier by the name its file really has" {
  # [37]. `for id in $ids` cut `01-alpha bis` into two ids the directory does not
  # hold, so the scan named `01-alpha` twice at a human and never mentioned the
  # file they would have to go and rename. This finding is read at 3am by somebody
  # who has to find a ticket; naming one that does not exist is the whole cost.
  cp "$(ticket_file 01-alpha)" "$TRACKER_DIR/01-alpha bis.md"

  pack_run 'tracker_preflight'
  assert_failure
  assert_output_contains "two or more tickets carry the number 01"
  assert_output_contains "01-alpha bis, 01-alpha"
  assert_output_contains "03-blocked is blocked on 01, which 2 tickets carry"
}

@test "a ticket whose name carries a space still answers to its own id" {
  # The other end of the same namespace, and the witness for the renumber the
  # quarantine performs: every write operation takes the id as an argument and has
  # to keep resolving to the file. [37] expected this to be the trap and it was
  # not — everything under `tracker_local__path` was already quoted, its glob
  # included (`"$dir/$id"-*.md`, where a metacharacter inside `$id` is literal).
  mv "$(ticket_file 02-beta)" "$TRACKER_DIR/02-beta bis.md"

  pack_run 'tracker_field "02-beta bis" Status'
  assert_success
  assert_equal "$output" "ready-for-agent"

  pack_run 'tracker_frontier | tr "\n" "|"'
  assert_success
  assert_output_contains "02-beta bis|"

  pack_run 'tracker_mark_resolved "02-beta bis"'
  assert_success
  assert_ticket_status "02-beta bis" resolved
}

@test "a ticket whose name carries a newline is handed out by no scan, out loud" {
  # [48], the limit [37] named rather than closed: one id per line is the
  # convention *and* the separator, so a file name carrying a newline came out of
  # both scans as two ids the tracker does not hold — `99-a` and `b` — which
  # entered the frontier where neither could ever be claimed.
  pack_run '
dir="$(tracker_local__issues_dir)"
cp "$dir/01-alpha.md" "$dir/$(printf "99-a\nb").md"
printf "ids[%s]\n" "$(tracker_ids | tr "\n" "|")"
printf "frontier[%s]\n" "$(tracker_frontier | tr "\n" "|")"
'
  assert_success
  refute_output_contains "|99-a|"
  refute_output_contains "|b|"
  assert_output_contains "ids[01-alpha|02-beta|03-blocked|04-claimed|05-needs-triage|06-resolved|07-overlaps-alpha|08-no-write-surface|09-escalated|]"
  assert_output_contains "frontier[01-alpha|02-beta|07-overlaps-alpha|08-no-write-surface|]"
  # Refused out loud and not skipped: a ticket nobody can reach is worse than a
  # ticket nobody can grind if nothing says which file to go and rename. The name
  # is rendered escaped, so the sentence about a newline is not itself cut in two.
  assert_output_contains 'carries a newline in its name'
  assert_output_contains '"99-a\nb.md"'
}

@test "an id carrying a newline resolves to nothing, whoever hands it in" {
  # The other end of the same rule. Nothing produces such an id any more, so what
  # is left is a caller that already had one — a human, a stale receipt — and the
  # answer has to be "no such ticket" rather than the file, or the backend would
  # hand out through the back door what it refuses at the front.
  pack_run '
dir="$(tracker_local__issues_dir)"
cp "$dir/01-alpha.md" "$dir/$(printf "99-a\nb").md"
printf "field[%s]\n" "$(tracker_field "$(printf "99-a\nb")" Status || printf "refused")"
'
  assert_success
  assert_output_contains "field[refused]"
}

@test "the paired witness: the same name on one line is a ticket like any other" {
  # Without this the test above proves nothing about newlines: a scan that had
  # simply stopped listing what it does not recognise would satisfy it just as
  # well, and so would one that had stopped listing anything new at all.
  pack_run '
dir="$(tracker_local__issues_dir)"
cp "$dir/01-alpha.md" "$dir/99-ab.md"
printf "ids[%s]\n" "$(tracker_ids | tr "\n" "|")"
printf "frontier[%s]\n" "$(tracker_frontier | tr "\n" "|")"
'
  assert_success
  assert_output_contains "09-escalated|99-ab|]"
  assert_output_contains "frontier[01-alpha|02-beta|07-overlaps-alpha|08-no-write-surface|99-ab|]"
  refute_output_contains "carries a newline in its name"
}

@test "a bare number is not made ambiguous by a file nothing can address" {
  # The damage a scan-only fix would have left behind, and it is [27]'s: a bare
  # number is how dependencies are written, `tracker_local__path` refuses one that
  # two files carry, and every ticket holding `Blocked by: 99` then leaves the
  # frontier for good. A ghost that no scan sees, no quarantine reaches and no
  # renumber can move must not be one of those two files.
  pack_run '
dir="$(tracker_local__issues_dir)"
cp "$dir/01-alpha.md" "$dir/99-real.md"
cp "$dir/01-alpha.md" "$dir/$(printf "99-a\nb").md"
printf "field[%s]\n" "$(tracker_field 99 Status)"
'
  assert_success
  assert_output_contains "field[ready-for-agent]"
  refute_output_contains "matches 2 tickets"
}

@test "the paired witness: two addressable files on one number are still refused" {
  pack_run '
dir="$(tracker_local__issues_dir)"
cp "$dir/01-alpha.md" "$dir/99-real.md"
cp "$dir/01-alpha.md" "$dir/99-ab.md"
printf "field[%s]\n" "$(tracker_field 99 Status || printf "refused")"
'
  assert_success
  assert_output_contains "field[refused]"
  assert_output_contains "matches 2 tickets"
}

@test "a number is not held back by a file nothing can address" {
  # The half that follows from the one above rather than standing on its own: a
  # file that is not a carrier of `10` cannot also be the reason `10` is taken.
  # Holding the number back for it would reserve it against nothing, and the
  # ticket that gets `11` instead is the visible half of an invisible file.
  pack_run '
dir="$(tracker_local__issues_dir)"
cp "$dir/01-alpha.md" "$dir/$(printf "10-a\nb").md"
printf "opened[%s]\n" "$(printf "**What to build:** x\n" | tracker_open_ticket fresh "Fresh")"
'
  assert_success
  assert_output_contains "opened[10-fresh]"
}

@test "the paired witness: an addressable file does hold its number back" {
  pack_run '
dir="$(tracker_local__issues_dir)"
cp "$dir/01-alpha.md" "$dir/10-ab.md"
printf "opened[%s]\n" "$(printf "**What to build:** x\n" | tracker_open_ticket fresh "Fresh")"
'
  assert_success
  assert_output_contains "opened[11-fresh]"
}

@test "a slug is not taken by a file nothing can address" {
  # `open_unique` is the deduplication a capability proposal and the retro's
  # escalation both go through ([47]). A file no scan shows a human must not be
  # able to answer "already waiting" on their behalf, for good.
  pack_run '
dir="$(tracker_local__issues_dir)"
cp "$dir/01-alpha.md" "$dir/$(printf "99-x\n-cap").md"
printf "opened[%s]\n" "$(printf "**What to build:** x\n" | tracker_open_unique cap "Cap")"
'
  assert_success
  assert_output_contains "opened[10-cap]"
}

@test "the paired witness: an addressable file does take its slug" {
  pack_run '
dir="$(tracker_local__issues_dir)"
cp "$dir/01-alpha.md" "$dir/99-x-cap.md"
printf "opened[%s]\n" "$(printf "**What to build:** x\n" | tracker_open_unique cap "Cap")"
'
  assert_success
  assert_output_contains "opened[]"
}

@test "a renumber does not move a ticket over a file nothing can address" {
  # The quarantine renumbers what a session added so that a bare number keeps
  # resolving ([27]). A ghost is not a collision, and renumbering a ticket because
  # of one would move the ticket every other ticket points at.
  pack_run '
dir="$(tracker_local__issues_dir)"
cp "$dir/01-alpha.md" "$dir/99-real.md"
cp "$dir/01-alpha.md" "$dir/$(printf "99-a\nb").md"
printf "renumbered[%s]\n" "$(tracker_renumber 99-real)"
'
  assert_success
  assert_output_contains "renumbered[99-real]"
}

@test "the paired witness: a real collision is still renumbered" {
  pack_run '
dir="$(tracker_local__issues_dir)"
cp "$dir/01-alpha.md" "$dir/99-real.md"
cp "$dir/01-alpha.md" "$dir/99-ab.md"
printf "renumbered[%s]\n" "$(tracker_renumber 99-real)"
'
  assert_success
  # `100` and not `10`: both files carry 99, so the highest number in the
  # directory really is 99 and the next free one is past it.
  assert_output_contains "renumbered[100-real]"
}

# ── one number at a time ─────────────────────────────────────────────────────
#
# Allocating an `NN` reads the directory, takes the max and writes it back, and
# there are three producers of that call now ([13]): a re-slice, the retro's
# escalation and a capability proposal, each inside its own iteration. Two of them
# in flight took the same number, and what that costs is permanent and paid
# elsewhere — a bare number stops resolving, so every ticket carrying
# `Blocked by: NN` leaves the frontier for good ([27]).
#
# The tests below drive the module rather than launching processes and hoping.
# Two openings racing on a real machine is a probe (`.scratch/ralph-pack/sondes/`)
# and never a test: it would measure the machine, which this pack has paid for
# twice. What is asserted here is what the guarantee actually is — the allocation
# happens under a guard, and the guard is not held while a body is being produced.

# A guard held by a process that really is alive, which is the only state
# `state_guard_take` refuses: an owner it cannot see is taken over.
hold_open_guard() {
  sleep 30 &
  OPEN_GUARD_HOLDER=$!
  mkdir -p "$FEATURE_DIR/.open.guard"
  printf '%s\n' "$OPEN_GUARD_HOLDER" >"$FEATURE_DIR/.open.guard/pid"
}

release_open_guard() {
  kill "$OPEN_GUARD_HOLDER" 2>/dev/null || true
  rm -rf "$FEATURE_DIR/.open.guard"
}

@test "an opening refuses a number it cannot allocate under the guard" {
  hold_open_guard
  pack_run 'printf "%s\n" "**What to build:** something" | tracker_open_ticket blocked "Blocked"'
  held_status="$status"
  held_output="$output"
  release_open_guard

  [ "$held_status" != 0 ] || fail "the opening allocated a number nothing serialised"
  case "$held_output" in
    *"could not take the ticket-open guard"*) ;;
    *) fail "the refusal says nothing about the guard: $held_output" ;;
  esac
  refute_file_exists "$(ticket_file 10-blocked)"

  # And the refusal is a refusal and not a broken function: the same call goes
  # through once the guard is free. Without this half, a guard that never let
  # anybody in would pass the assertions above.
  pack_run 'printf "%s\n" "**What to build:** something" | tracker_open_ticket blocked "Blocked"'
  assert_success
  assert_equal "$output" "10-blocked"
}

@test "a renumber refuses rather than allocating beside an opening" {
  # The other writer of the number space. The quarantine calls it from one
  # iteration while a sibling may be opening a re-slice child, so a renumber that
  # allocated outside the guard would hand out a number an opening just took.
  cp "$(ticket_file 01-alpha)" "$TRACKER_DIR/01-alpha-bis.md"

  hold_open_guard
  pack_run 'tracker_renumber 01-alpha-bis'
  held_status="$status"
  release_open_guard

  [ "$held_status" != 0 ] || fail "the renumber allocated a number nothing serialised"
  assert_file_exists "$TRACKER_DIR/01-alpha-bis.md"

  pack_run 'tracker_renumber 01-alpha-bis'
  assert_success
  assert_equal "$output" "10-alpha-bis"
}

@test "a body that is slow to arrive does not hold a number" {
  # The window is not the microsecond one would assume: `nn` used to be computed
  # **before** `body="$(cat)"` was read, so a number was chosen and not yet
  # written for as long as the caller took to produce the body — for a re-slice,
  # the time of a plan. The fifo is what makes this a test and not a race: the
  # first opening cannot finish until this test writes to it, so the ordering is
  # decided here rather than by the scheduler.
  fifo="$RALPH_TEST_DIR/body.fifo"
  mkfifo "$fifo"

  pack_run_bg 'tracker_open_ticket first "First" <'"$fifo"' >'"$RALPH_TEST_DIR"'/first.id'
  # A writer only gets through a fifo once a reader is there, so this returns
  # when the child is inside the call — and it cannot leave it without a body.
  exec 9>"$fifo"
  sleep 0.5

  pack_run 'printf "%s\n" "**What to build:** second" | tracker_open_ticket second "Second"'
  assert_success
  assert_equal "$output" "10-second"

  printf '**What to build:** first\n' >&9
  exec 9>&-
  wait "$PACK_BG_PID" || true

  # 11 and not 10: two tickets carrying 10 is the state nothing repairs.
  assert_equal "$(cat "$RALPH_TEST_DIR/first.id")" "11-first"

  pack_run 'tracker_local__path 10'
  assert_success
  assert_output_contains "10-second.md"
}

@test "open_unique opens a slug once and answers the second by silence" {
  pack_run 'printf "%s\n" "**What to build:** something" | tracker_open_unique proposal "A proposal"'
  assert_success
  assert_equal "$output" "10-proposal"

  pack_run 'printf "%s\n" "**What to build:** something" | tracker_open_unique proposal "A proposal"'
  assert_success
  assert_equal "$output" ""

  run bash -c "ls '$TRACKER_DIR' | grep -c -- '-proposal\.md'"
  assert_equal "$output" "1"
}

@test "an opening in flight does not open a slug a second one landed first" {
  # [47] by its other end. `capability_propose` read `tracker_ids`, found no
  # proposal and opened one, so two proposals in flight both found nothing and
  # both opened — the same race as the number, and a second proposal buries the
  # first on the human sink. The question and the write have to fall on the same
  # side of the guard, which is why this is an operation and not a caller's check.
  fifo="$RALPH_TEST_DIR/body.fifo"
  mkfifo "$fifo"

  pack_run_bg 'tracker_open_unique proposal "A proposal" <'"$fifo"' >'"$RALPH_TEST_DIR"'/first.id'
  exec 9>"$fifo"

  pack_run 'printf "%s\n" "**What to build:** second" | tracker_open_unique proposal "A proposal"'
  assert_success
  assert_equal "$output" "10-proposal"

  printf '**What to build:** first\n' >&9
  exec 9>&-
  wait "$PACK_BG_PID" || true

  # Nothing, because by the time it looked there was one — and it looked under
  # the guard, after its body, not before.
  assert_equal "$(cat "$RALPH_TEST_DIR/first.id")" ""

  run bash -c "ls '$TRACKER_DIR' | grep -c -- '-proposal\.md'"
  assert_equal "$output" "1"
}

@test "the guard is not left behind by an opening that finished" {
  # A guard nobody released is a tracker nobody can add to for as long as the run
  # lives: every stamp inside one run carries the pilot's pid, so `state_guard_take`
  # sees a live owner and waits it out rather than recovering it.
  pack_run 'printf "%s\n" "**What to build:** something" | tracker_open_ticket first "First"'
  assert_success
  refute_file_exists "$FEATURE_DIR/.open.guard/pid"

  pack_run 'tracker_renumber 01-alpha'
  assert_success
  refute_file_exists "$FEATURE_DIR/.open.guard/pid"
}

@test "a unique opening tells the register the id it made, not the slug it was given" {
  # The register is what keeps the two guards over `issues/` off a ticket the loop
  # itself wrote ([13]/[42]), and the one question they ask is whether an id that
  # appeared is the loop's own creation. A line carrying the slug names no ticket
  # at all, so a proposal a sibling iteration finds is quarantined as work a
  # session gave itself, under a note naming a ticket nobody can go and look at.
  #
  # Asserted at the module rather than through a run, and for the reason
  # failures.bats gives for the same assertion on `open_ticket`: the guards run
  # inside another iteration's window, which is not observable at MAX_PARALLEL=1.
  pack_run 'RALPH_TRACKER_LOG="'"$RALPH_TEST_DIR"'/register"
    : >"$RALPH_TRACKER_LOG"
    printf "%s\n" "**What to build:** something" |
      tracker_open_unique proposal "A proposal" >/dev/null
    printf "register:%s\n" "$(cat "$RALPH_TRACKER_LOG")"'
  assert_success
  assert_output_contains "register:10-proposal"
}

@test "a unique opening that opened nothing writes no line to the register" {
  # A creation that did not happen is not a write to exempt: a line here would
  # hand both guards an id to skip for a ticket this run did not touch.
  pack_run 'printf "%s\n" "**What to build:** something" | tracker_open_unique proposal "A proposal"'
  assert_success

  pack_run 'RALPH_TRACKER_LOG="'"$RALPH_TEST_DIR"'/register"
    : >"$RALPH_TRACKER_LOG"
    printf "%s\n" "**What to build:** something" |
      tracker_open_unique proposal "A proposal" >/dev/null
    printf "register:[%s]\n" "$(cat "$RALPH_TRACKER_LOG")"'
  assert_success
  assert_output_contains "register:[]"
}
