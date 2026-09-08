#!/usr/bin/env bats
#
# [70] — the record a human is sent to read about a ticket.
#
# The human sink's dossier names three pieces of evidence. `run.log` has carried
# its reserve since [67]. The other two — `refs/heads/failed/<id>` and
# `receipts/<feature>/<id>.md` — are written by an **AFK run**, into two zones no
# check of that run's own path looks at: a ref is a path in no working tree at
# all, and the audit receipts live in the **main** tree, which `git worktree list`
# names to anyone who asks and which is not the worktree a scope-guard compares.
#
# Measured by the pass of 07/09/2026, on a **green** iteration each time — four
# axes green, ticket `resolved`, run rc 0 — and with zero words said anywhere:
# a session writing one `git update-ref` moved the next drain's desk from `admit`
# to `arbitrate`; the same session erasing a real ref made the dossier say
# "nothing ever ran on this ticket" about a ticket a run had judged; a session
# writing one file under `receipts/<feature>/` had it shown as the audit receipt.
#
# What is asserted here is the answer this ticket chose: a run-level witness that
# **names** and never puts back or refuses, plus the reserve the dossier now
# carries because a witness cannot see a forgery laid down by a run nobody has
# started since. Both halves, because either alone was refused: form (1) without
# form (3) trades one silence for a narrower one.

load helpers/harness
load helpers/assert

setup() {
  harness_setup
}

teardown() {
  harness_teardown
}

receipt_path() {
  printf '%s/receipts/%s/%s.md\n' "$PROJECT_DIR" "$RALPH_TEST_FEATURE" "$1"
}

# A ticket in the human sink, so a drain has something to build a dossier for.
forensic__sink_ticket() {
  {
    printf '# 20-decision — for the drain\n\n'
    printf '**What to build:** Something a human has to arbitrate.\n\n'
    printf '**Status:** ready-for-human\n\n'
    printf '**Escalation:** decision\n\n'
    printf '**Write-surface:** `src/one.txt`\n\n'
    printf '**Blocked by:** None\n'
  } >"$TRACKER_DIR/20-decision.md"
  harness__commit "test: a ticket for the sink"
}

# A session that delivers its ticket and, on the way, writes what the argument
# asks for in the **main** tree or in the common git directory — which is what a
# session reaches with `git worktree list` and, for the refs, with nothing at all.
#
# Green on purpose, every time: a red iteration is rolled back and retried, and
# what this ticket is about is the run nobody has any reason to look at.
forensic__green_session_that() {
  {
    printf '#!/usr/bin/env bash\n'
    printf 'prompt="$(cat)"\n'
    printf 'main="$(cat "$RALPH_SHIM_STATE/project-dir")"\n'
    printf 'feature="$(basename "$(ls -d "$main"/.scratch/*/ | head -1)")"\n'
    cat
    printf 'surface="$(printf %%s "$prompt" |\n'
    printf "  sed -n 's/^\\\\*\\\\*Write-surface:\\\\*\\\\* //p' | head -1 | tr -d '\\\`\\\\r' | tr ',' ' ')\"\n"
    printf 'for t in $surface; do mkdir -p "$(dirname "$t")" && printf "written\\n" >"$t"; done\n'
    printf "echo '{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"num_turns\":1,\"total_cost_usd\":0.02}'\n"
  } | script_claude
}

# ── the witness itself ───────────────────────────────────────────────────────

@test "the witness holds the three zones the loop writes outside every tree it judges" {
  # The list is derived from a criterion — what this pack writes durably, outside
  # every tree it judges, for a human to read after the run is over — and not from
  # the two objects the pass measured ([31], [45]). The playthrough is the third
  # member and it is here for that reason alone: nothing in this pack reads it
  # back, and the dossier does not show it, so no probe would ever have found it.
  git -C "$PROJECT_DIR" update-ref refs/heads/failed/01-alpha \
    "$(git -C "$PROJECT_DIR" rev-parse HEAD)"
  mkdir -p "$PROJECT_DIR/receipts/$RALPH_TEST_FEATURE" \
    "$PROJECT_DIR/docs/playthroughs"
  printf 'a receipt\n' >"$(receipt_path 01-alpha)"
  printf 'a playthrough\n' >"$PROJECT_DIR/docs/playthroughs/$RALPH_TEST_FEATURE.md"

  mkdir -p "$RALPH_TEST_DIR/witness"
  pack_run 'forensic_witness "'"$RALPH_TEST_DIR"'/witness"'
  assert_success

  assert_file_contains "$RALPH_TEST_DIR/witness/forensic.witness" \
    "refs/heads/failed/01-alpha"
  assert_file_contains "$RALPH_TEST_DIR/witness/forensic.witness" \
    "$(receipt_path 01-alpha)"
  assert_file_contains "$RALPH_TEST_DIR/witness/forensic.witness" \
    "$PROJECT_DIR/docs/playthroughs/$RALPH_TEST_FEATURE.md"

  # Each of them with a digest beside it and never a bare name: a witness that
  # only recorded which objects existed would say nothing about the one that is
  # still called what it was called and now holds something else.
  run bash -c "awk -F'\t' 'NF != 3 { print \"malformed: \" \$0 }' '$RALPH_TEST_DIR/witness/forensic.witness'"
  assert_success
  assert_equal "$output" ""
}

@test "git refusing to list the forensic refs is not a namespace somebody emptied" {
  # [59]'s rule, one turn lower. Read as an empty list, a refusal turns every ref
  # this run started with into a ref a session deleted — and the sentence for that
  # accuses somebody of destroying evidence. So the witness refuses to be taken
  # and the comparison refuses to be made, rather than reporting a night of
  # deletions nobody committed.
  mkdir -p "$RALPH_TEST_DIR/witness"
  pack_run 'forensic_failed_refs() { return 1; }
    forensic_witness "'"$RALPH_TEST_DIR"'/witness" || printf "(no witness)\n"'
  assert_success
  assert_output_contains "(no witness)"
  refute_file_exists "$RALPH_TEST_DIR/witness/forensic.witness"

  # The paired witness: the same call with git answering really does take one, so
  # what is measured above is the refusal and not a witness that stopped working.
  pack_run 'forensic_witness "'"$RALPH_TEST_DIR"'/witness" || printf "(no witness)\n"'
  assert_success
  refute_output_contains "(no witness)"
  assert_file_exists "$RALPH_TEST_DIR/witness/forensic.witness"

  # And the other end: a comparison made after git stops answering says nothing
  # rather than naming every ref in the witness as gone.
  git -C "$PROJECT_DIR" update-ref refs/heads/failed/01-alpha \
    "$(git -C "$PROJECT_DIR" rev-parse HEAD)"
  pack_run 'forensic_witness "'"$RALPH_TEST_DIR"'/witness"
    forensic_failed_refs() { return 1; }
    receipt_gap() { :; }
    forensic_drift "'"$RALPH_TEST_DIR"'/witness"
    printf "(said %s)\n" "$?"'
  assert_success
  assert_output_contains "(said 0)"
  refute_output_contains "failed/01-alpha"
}

@test "a receipt that is there and cannot be read is not a receipt that is gone" {
  # `-` is the digest of "not there", and a document whose mode changed under this
  # run would take that value under the obvious spelling — so the comparison would
  # report the evidence as *destroyed*, over a file still sitting exactly where
  # the human sink points. Replaced by a directory here rather than chmod-ed,
  # because a suite that happens to run as root would defeat the mode and go green
  # on a guarantee it never exercised.
  mkdir -p "$PROJECT_DIR/receipts/$RALPH_TEST_FEATURE" "$RALPH_TEST_DIR/witness"
  printf 'a receipt\n' >"$(receipt_path 01-alpha)"
  pack_run 'forensic_witness "'"$RALPH_TEST_DIR"'/witness"'
  assert_success

  rm -f "$(receipt_path 01-alpha)"
  mkdir -p "$(receipt_path 01-alpha)"

  pack_run 'receipt_gap() { :; }
    forensic_drift "'"$RALPH_TEST_DIR"'/witness"'
  assert_success
  assert_output_contains "is a name this run cannot read"
  refute_output_contains "is gone, and this run did not remove it"

  # The paired witness: really removing it does say the other sentence, so what is
  # measured above is the third digest state and not a comparison gone quiet.
  rmdir "$(receipt_path 01-alpha)"
  pack_run 'receipt_gap() { :; }
    forensic_drift "'"$RALPH_TEST_DIR"'/witness"'
  assert_success
  assert_output_contains "is gone, and this run did not remove it"
}

@test "find refusing to walk the receipts is not a directory somebody emptied" {
  # The same rule as the refs above, on the other zone, and it needed its own
  # measurement: `find` answers non-zero for a directory it could not walk as well
  # as for one that is not there, and only the first of those is a refusal. Read as
  # an empty listing it turns every receipt this run started with into a receipt
  # somebody deleted — which is the sentence that accuses a session of destroying
  # a ticket's whole audit trail.
  mkdir -p "$PROJECT_DIR/receipts/$RALPH_TEST_FEATURE" "$RALPH_TEST_DIR/witness"
  printf 'a receipt\n' >"$(receipt_path 01-alpha)"
  pack_run 'forensic_witness "'"$RALPH_TEST_DIR"'/witness"'
  assert_success
  assert_file_contains "$RALPH_TEST_DIR/witness/forensic.witness" \
    "$(receipt_path 01-alpha)"

  pack_run 'find() { return 1; }
    receipt_gap() { :; }
    forensic_drift "'"$RALPH_TEST_DIR"'/witness"
    printf "(said %s)\n" "$?"'
  assert_success
  assert_output_contains "(said 0)"
  refute_output_contains "is gone, and this run did not remove it"
}

@test "a backend that keeps no receipt directory is named once, not silently uncovered" {
  # A control that excludes a zone has to say who guards it. On a backend whose
  # receipts are pull requests there is no directory to walk, so nothing here
  # witnesses them at all — and the dossier still points a human at one. The run
  # says so out loud instead of being narrower than its own sentence, and the
  # question of what attests a remote receipt is [18]'s.
  pack_run 'TRACKER_BACKEND=nowhere
    tracker_nowhere_ids() { :; }
    forensic_uncovered || printf "(nothing to say)\n"'
  assert_success
  assert_output_contains "does not keep audit receipts in a directory"
  assert_output_contains "[18]"
  refute_output_contains "(nothing to say)"

  # The paired witness: the local backend does keep them in one, so the sentence
  # is about the backend and not printed on every run there is.
  pack_run 'forensic_uncovered || printf "(nothing to say)\n"'
  assert_success
  assert_output_contains "(nothing to say)"
}

# ── what a run says about a session that wrote one ───────────────────────────

@test "a green iteration whose session writes a forensic ref is named on both documents" {
  # Q1a of the pass, and the whole shape of the defect: nothing is refused,
  # nothing goes red, the ticket resolves — and the ref is there afterwards,
  # deciding the desk of a ticket in the human sink and sending a human to read a
  # tree no run judged.
  forensic__sink_ticket
  use_tickets 01-alpha
  forensic__green_session_that <<'FORGE'
printf 'forged\n' >forged.txt
git add forged.txt >/dev/null 2>&1
commit="$(git commit-tree "$(git write-tree)" -m 'ralph: failed attempt on 20-decision' 2>/dev/null)"
git update-ref refs/heads/failed/20-decision "$commit" 2>/dev/null
git reset -q >/dev/null 2>&1
rm -f forged.txt
FORGE

  run_loop
  assert_success
  assert_ticket_status 01-alpha resolved
  run git -C "$PROJECT_DIR" rev-parse --verify -q refs/heads/failed/20-decision
  assert_success

  # The journal, which is the only durable document on the iteration a run stops
  # on, with the ref name as the subject: a line reading `forensic-drift` alone
  # sends a human looking without saying where ([15] via [52]).
  assert_file_contains "$FEATURE_DIR/run.log" "forensic-drift"
  assert_file_contains "$FEATURE_DIR/run.log" "refs/heads/failed/20-decision"
  # And the receipt of the iteration it happened under, with what it costs named
  # and not merely counted: the desk of the next drain, and a tree no gate judged.
  assert_file_contains "$(receipt_path 01-alpha)" \
    "was written while this run was in flight, and no iteration of this run wrote it"
  assert_file_contains "$(receipt_path 01-alpha)" "the \`arbitrate\` desk"
}

@test "a green iteration that erases the ref of a real attempt says the evidence is lost" {
  # The other direction, Q1c, and the more expensive one: the drain then affirms
  # "nothing ever ran on this ticket" about a ticket a run really judged. Nothing
  # here puts the ref back — this pack is not its author and the commit it named
  # may already be unreachable — so what is asserted is the sentence.
  use_tickets 01-alpha
  git -C "$PROJECT_DIR" update-ref refs/heads/failed/20-decision \
    "$(git -C "$PROJECT_DIR" rev-parse HEAD)"
  forensic__green_session_that <<'FORGE'
git update-ref -d refs/heads/failed/20-decision 2>/dev/null
FORGE

  run_loop
  assert_success
  assert_ticket_status 01-alpha resolved
  run git -C "$PROJECT_DIR" rev-parse --verify -q refs/heads/failed/20-decision
  assert_failure

  assert_file_contains "$FEATURE_DIR/run.log" "refs/heads/failed/20-decision"
  assert_file_contains "$(receipt_path 01-alpha)" "The evidence is lost and not moved"
  assert_file_contains "$(receipt_path 01-alpha)" \
    "a drain reading that ticket now finds no branch at all"
}

@test "a green iteration whose session forges an audit receipt is named" {
  # Q3a. `receipts/<feature>/` is a path — of the **main** tree, which is not the
  # worktree the scope-guard compares, and which `git worktree list` names to
  # anyone who asks. The dossier showed the result as the audit receipt of the
  # ticket, with no reserve on it at all.
  forensic__sink_ticket
  use_tickets 01-alpha
  forensic__green_session_that <<'FORGE'
mkdir -p "$main/receipts/$feature"
printf '# Receipt — 20-decision\n\n**Verdicts:** tests=green\n' \
  >"$main/receipts/$feature/20-decision.md"
FORGE

  run_loop
  assert_success
  assert_ticket_status 01-alpha resolved
  assert_file_exists "$(receipt_path 20-decision)"

  assert_file_contains "$FEATURE_DIR/run.log" "forensic-drift"
  assert_file_contains "$FEATURE_DIR/run.log" "$(receipt_path 20-decision)"
  assert_file_contains "$(receipt_path 01-alpha)" \
    "appeared while this run was in flight, and this run did not emit it"
  assert_file_contains "$(receipt_path 01-alpha)" \
    "a document whose author nothing here can name"
}

@test "the playthrough is watched because the criterion says so, not because a probe found it" {
  # The third object of the same family, named by [70] and sondé by nobody:
  # written by the pack in the main tree ([11]), read by a human in the morning,
  # reachable by a judged session exactly like the receipt. Nothing in this pack
  # reads it back and the dossier does not show it — so a correction that had
  # covered only the two objects a probe measured would have been narrower than
  # the sentence justifying it ([31], [45]).
  use_tickets 01-alpha
  forensic__green_session_that <<'FORGE'
mkdir -p "$main/docs/playthroughs"
printf '# Playthrough\n\nEverything works.\n' >"$main/docs/playthroughs/$feature.md"
FORGE

  run_loop
  assert_success
  assert_ticket_status 01-alpha resolved

  assert_file_contains "$FEATURE_DIR/run.log" "forensic-drift"
  assert_file_contains "$FEATURE_DIR/run.log" \
    "docs/playthroughs/$RALPH_TEST_FEATURE.md"
  assert_file_contains "$(receipt_path 01-alpha)" \
    "no value gate of this run wrote it"
}

# ── and what it says about the run's own writing, which is nothing ───────────

@test "a run that writes a real forensic ref and a real receipt says nothing about them" {
  # The paired witness this whole mechanism lives or dies on. Three attempts, a
  # real `failed/01-alpha` written by `failures_preserve_attempt` and a real
  # receipt written by `receipt_emit`: a witness that could not tell the loop's own
  # writing from a session's would accuse the run of both, on every red night there
  # is, and the channel would be noise by the third morning.
  use_tickets 01-alpha
  set_config RETRY_N 2
  set_config STERILE_K 4
  stub_exit tests 1

  run_loop
  assert_success
  assert_ticket_status 01-alpha ready-for-human
  run git -C "$PROJECT_DIR" rev-parse --verify -q refs/heads/failed/01-alpha
  assert_success
  assert_file_exists "$(receipt_path 01-alpha)"

  refute_file_contains "$FEATURE_DIR/run.log" "forensic-drift"
  refute_file_contains "$(receipt_path 01-alpha)" \
    "the record the human sink sends somebody to read moved"
}

@test "a receipt this run emitted is not drift for the iteration that comes after it" {
  # The paired witness the receipt register actually needs, and the first attempt
  # at it was a lie: a single ticket writes its receipt on the **last** iteration
  # there is, so no comparison ever runs after that write and the register entry
  # was never exercised — the mutation removing it stayed green. Found by
  # `test/mutate.sh` and not by reading, which is the whole reason that gate
  # exists.
  #
  # Two tickets, one slot, both escalating: `01-alpha` leaves a real receipt
  # behind, and `02-beta` is then ground with that receipt sitting in a directory
  # the run witnessed before it existed. Without the register the iteration that
  # follows accuses the run of forging the document the run itself emitted.
  use_tickets 01-alpha 02-beta
  set_config RETRY_N 1
  set_config STERILE_K 6
  stub_exit tests 1

  run_loop
  assert_success
  assert_ticket_status 01-alpha ready-for-human
  assert_ticket_status 02-beta ready-for-human
  assert_file_exists "$(receipt_path 01-alpha)"
  assert_file_exists "$(receipt_path 02-beta)"
  # The staging is only worth something if an iteration really ran after the first
  # receipt was written: two tickets, two attempts each, and the second ticket's
  # first attempt is that iteration.
  run bash -c "grep -c '	02-beta	' '$FEATURE_DIR/run.log'"
  assert_equal "$output" "2"

  refute_file_contains "$FEATURE_DIR/run.log" "forensic-drift"
  refute_file_contains "$(receipt_path 02-beta)" \
    "the record the human sink sends somebody to read moved"
}

@test "two failing iterations side by side accuse each other of nothing" {
  # The register is entered **before** the write and never after, and this is the
  # measurement that says why: with two iterations in flight, a register fed after
  # the fact leaves a window in which the sibling's comparison finds a ref or a
  # receipt that exists and is not registered yet — and the sentence for that
  # accuses a session of forging what the run beside it had just legitimately
  # written ([41]'s misattribution, through the door this ticket opened).
  use_tickets 01-alpha 02-beta
  set_config MAX_PARALLEL 2
  set_config RETRY_N 1
  set_config STERILE_K 6
  stub_exit tests 1

  run_loop
  assert_success

  run bash -c "git -C '$PROJECT_DIR' for-each-ref --format='%(refname)' refs/heads/failed/ | wc -l | tr -d ' '"
  assert_equal "$output" "2"
  assert_file_exists "$(receipt_path 01-alpha)"
  assert_file_exists "$(receipt_path 02-beta)"

  refute_file_contains "$FEATURE_DIR/run.log" "forensic-drift"
}

@test "a value gate that reinjects says nothing about the playthrough it wrote itself" {
  # The playthrough is the one object of the three whose only writer runs in the
  # **pilot** and after the last iteration — so on an ordinary night nothing
  # compares after it, and the register entry beside `playthrough_close` would look
  # like a line nobody needs. This is the night where it is load-bearing: an
  # internal hole comes back as a wiring ticket, the run grinds it, and the
  # iteration that follows compares against a witness taken before the document
  # existed. Without the register that iteration accuses the value gate of forging
  # the proof the value gate is there to write.
  use_tickets 01-alpha
  playthrough_answer_nth 1 \
    'RALPH-PLAYTHROUGH-HOLE: the markers are written and nothing renders them' \
    'RALPH-PLAYTHROUGH-CLASS: internal' \
    'RALPH-PLAYTHROUGH-TITLE: render the markers the demo writes' \
    'RALPH-PLAYTHROUGH-SURFACE: `src/wired.txt`' \
    'RALPH-PLAYTHROUGH-VERDICT: fail'
  playthrough_answer_nth 2 \
    'RALPH-PLAYTHROUGH-STEP: the user runs the demo and sees the markers' \
    'RALPH-PLAYTHROUGH-VERDICT: pass'

  run_loop
  assert_success
  # The staging really happened: two value gates, and a second iteration after the
  # first one wrote the document.
  assert_file_contains "$FEATURE_DIR/run.log" "playthrough-reinjected"
  assert_file_contains "$FEATURE_DIR/run.log" "playthrough-green"
  assert_file_exists "$PROJECT_DIR/docs/playthroughs/$RALPH_TEST_FEATURE.md"

  refute_file_contains "$FEATURE_DIR/run.log" "forensic-drift"
}

@test "a run whose forensic record did not move says nothing about it" {
  # The line [45] draws between the two channels: the notes are coverage and are on
  # every receipt, this is an event. A silence here says no such event was
  # recorded, which is all it ever claimed — and a sentence on every green
  # iteration is the one nobody reads by the third night.
  use_tickets 01-alpha

  run_loop
  assert_success
  assert_ticket_status 01-alpha resolved

  refute_file_contains "$FEATURE_DIR/run.log" "forensic-drift"
  refute_file_contains "$(receipt_path 01-alpha)" \
    "the record the human sink sends somebody to read moved"
}

# ── form (3): what the dossier stops claiming ────────────────────────────────

@test "the dossier puts its reserve on the two objects it shows" {
  # Form (1) without form (3) would have traded one silence for a narrower one: a
  # witness is per run, and a forgery laid down by a run nobody has started since
  # is in its baseline — and in this drain's pin too, which compares the drain to
  # itself ([66]). So the dossier says what it is showing rather than showing it
  # bare, the way it has said it about `run.log` since [67].
  forensic__sink_ticket
  git -C "$PROJECT_DIR" update-ref refs/heads/failed/20-decision \
    "$(git -C "$PROJECT_DIR" rev-parse HEAD)"
  mkdir -p "$PROJECT_DIR/receipts/$RALPH_TEST_FEATURE"
  printf '# Receipt\n' >"$(receipt_path 20-decision)"

  run bash -c 'printf "n\nq\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  assert_output_contains "branch   failed/20-decision"
  assert_output_contains "verdicts, findings, and the zones nothing judged"
  assert_output_contains "written by a run, into zones the"
  assert_output_contains "not the worktree a scope-guard compares"
  assert_output_contains "Read them, do not rely on them."
}

@test "the dossier puts no reserve on evidence there is none of" {
  # The bound, taken on its own: a caveat printed under "there is none" is a
  # caveat about an absence, which teaches a reader to distrust the one sentence
  # in this dossier that is certain.
  forensic__sink_ticket

  run bash -c 'printf "n\nq\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  assert_output_contains "branch   there is none."
  assert_output_contains "receipt  none was kept for this ticket."
  refute_output_contains "Read them, do not rely on them."
}
