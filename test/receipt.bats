#!/usr/bin/env bats
#
# The audit receipt, and the journal it deliberately does not read.
#
# Two of the four observability layers live here. What each of them may be
# believed for is the whole subject, and it is not symmetrical:
#
#   `run.log`   the run journal, written by the pilot, one line per event of the
#               run. It lives under `.scratch/<feature>/`, which nothing in this
#               pack guards and nothing can guard ([21]), so a session can rewrite
#               the journal of the run judging it. It is never read back to decide
#               or to mark — that is an acceptance criterion — and this file
#               asserts the one thing that makes it worth reading anyway: the run
#               keeps its own copy and says so when the file no longer matches.
#   the receipt one markdown document per ticket the loop finished with, built out
#               of what the loop measured and the objects it wrote. Never out of
#               the journal, and a test here says so with a session that rewrites
#               it under the run.
#
# Most of the assertions below are about what a receipt refuses to claim, and that
# is not a stylistic choice: every route through an iteration ends in a document,
# and three of those routes have no verdict to show ([23], [35]), one has a red
# verdict that is not a finding about the ticket ([43]), and one has three green
# branches and a failure ([21]). A receipt that rendered them all the same way
# would send a human to read passing tests, or an absent branch, or a `failed/`
# ref that was never written.

load helpers/harness
load helpers/assert

setup() {
  harness_setup
}

teardown() {
  harness_teardown
}

# Where the local backend puts a receipt. Not a path this file invents: the
# adapter decides, and a test that hard-coded a second spelling would go on
# passing the day the adapter moved it.
receipt_path() {
  printf '%s/receipts/%s/%s.md\n' "$PROJECT_DIR" "$RALPH_TEST_FEATURE" "$1"
}

# ── a ticket the loop finished with gets a document ──────────────────────────

@test "a resolved iteration leaves an audit receipt naming its verdicts" {
  use_tickets 01-alpha

  run_loop
  assert_success

  assert_file_exists "$(receipt_path 01-alpha)"
  assert_file_contains "$(receipt_path 01-alpha)" "01-alpha — resolved"
  # The verdicts as the gate published them, and not a sentence about them: a
  # receipt that summarised "all green" would be a second author for a string the
  # gate already owns.
  assert_file_contains "$(receipt_path 01-alpha)" "tests=green"
  assert_file_contains "$(receipt_path 01-alpha)" "scope=green"
  # And the half a reader would otherwise supply themselves. An absent branch is
  # not a passing one ([17] on `lang=`, [05] on an unconfigured type check), and
  # the only place that can be said is beside the verdicts.
  assert_file_contains "$(receipt_path 01-alpha)" "absent"
}

@test "the receipt references the work and never inlines it" {
  use_tickets 01-alpha

  run_loop
  assert_success

  # A commit to read, by object name.
  assert_file_contains "$(receipt_path 01-alpha)" 'git show '
  assert_file_contains "$(receipt_path 01-alpha)" 'git diff-tree -r '
  # And not one byte of what the session wrote. `src/alpha.txt` contains `alpha`,
  # so a receipt that inlined the diff would carry that word — this is the
  # assertion the acceptance criterion is written as ("diff par référence, jamais
  # inliné"), and the only one that can tell a reference from a copy.
  refute_file_contains "$(receipt_path 01-alpha)" "alpha marker"
  run bash -c "grep -c '^+' '$(receipt_path 01-alpha)' || true"
  assert_equal "$output" "0"
}

@test "a final escalation gets a receipt, and a fresh retry does not" {
  # The trigger is the failure policy's *action* and never the outcome, which is
  # the distinction [07] left open: `gate-red` retried and `gate-red` escalated are
  # the same word, and only the second one ends the ticket. Asserted in both
  # directions in one test, because the positive half alone passes on an
  # implementation that writes a receipt per attempt — three documents where the
  # first two were superseded.
  use_tickets 01-alpha
  set_config RETRY_N 2
  set_config STERILE_K 4
  stub_exit tests 1

  # Exit 0 and not 4: the frontier really is drained — the ticket left it for the
  # human sink, which is what "this run ground everything it could" means.
  run_loop
  assert_success

  assert_ticket_status 01-alpha ready-for-human
  assert_file_exists "$(receipt_path 01-alpha)"
  assert_file_contains "$(receipt_path 01-alpha)" "escalated:failed-impl"
  # Three attempts, one document.
  run bash -c "grep -c 'gate-red' '$FEATURE_DIR/run.log'"
  assert_equal "$output" "3"
  run bash -c "grep -c 'action=retry:' '$FEATURE_DIR/run.log'"
  assert_equal "$output" "2"
  # And the forensic branch it tells a human to read really exists.
  assert_file_contains "$(receipt_path 01-alpha)" "failed/01-alpha"
  run git -C "$PROJECT_DIR" rev-parse --verify -q "refs/heads/failed/01-alpha"
  assert_success
}

@test "no receipt is written for an iteration that only goes back to the frontier" {
  # The bound on the test above, taken on its own so that a change which makes
  # every iteration emit is red here rather than merely noisy there.
  use_tickets 01-alpha
  set_config RETRY_N 5
  set_config STERILE_K 2
  stub_exit tests 1

  run_loop
  assert_failure 4

  assert_ticket_status 01-alpha ready-for-agent
  refute_file_exists "$(receipt_path 01-alpha)"
}

@test "a green gate whose work never reached the branch leaves a document" {
  # The acceptance criterion [10] wrote and could not reach ([45]). It names
  # `not-integrated` and `receipt__summary` has carried its paragraph ever since —
  # but the trigger fired on `resolved` and on an escalation only, and this route
  # skips `failures_handle` altogether (the `case` that exempts it with
  # `resolved`), so the action stayed `none` and nothing was emitted. Dead prose,
  # and on the one route where a human has most to read: the gate was green, the
  # work was committed inside a worktree this run then destroyed, and there is no
  # commit on any branch, no `failed/` ref and no change to the ticket to find it
  # by afterwards.
  use_tickets 01-alpha
  # A lock a crashed git forgot is enough, and it puts the failure exactly where
  # the route needs it: the commit inside the worktree succeeds, and the fold onto
  # the branch cannot take the ref.
  : >"$PROJECT_DIR/.git/refs/heads/main.lock"

  run_loop
  assert_failure 4

  assert_ticket_status 01-alpha ready-for-agent
  assert_file_exists "$(receipt_path 01-alpha)"
  assert_file_contains "$(receipt_path 01-alpha)" "01-alpha — not-integrated"
  assert_file_contains "$(receipt_path 01-alpha)" "the work never reached the branch"
  # And what the loop did about the ticket, in the vocabulary the failure policy
  # already owns. `action=none` on an iteration that gave a ticket back is the kind
  # of line a human reads in the morning and believes.
  assert_file_contains "$(receipt_path 01-alpha)" "what the loop then did: given-back"
  assert_file_contains "$FEATURE_DIR/run.log" "action=given-back"
}

# ── what the gate collected, kept past the gate ──────────────────────────────

@test "a red branch's whole output outlives the gate that collected it" {
  # Twenty lines reach stdout ([05]); the receipt is the surface that has room for
  # the rest. Fifty numbered lines make the difference measurable: the tail is
  # lines 31 to 50, so line 1 is in the receipt if and only if the receipt kept
  # more than what scrolled past.
  use_tickets 01-alpha
  set_config RETRY_N 0
  set_config TEST_CMD 'i=1; while [ $i -le 50 ]; do echo "suite line $i"; i=$((i + 1)); done; exit 1'

  run_loop
  assert_success

  assert_output_contains "suite line 50"
  # Counted rather than grepped for a name: `suite line 1` is a prefix of ten of
  # the fifty, so a substring assertion would pass on a receipt that kept only the
  # tail — which is the very thing this test exists to tell apart.
  run bash -c "grep -c 'suite line' <<'OUT'
$output
OUT"
  assert_equal "$output" "20"
  assert_file_contains "$(receipt_path 01-alpha)" "### tests — red"
  run bash -c "grep -c 'suite line' '$(receipt_path 01-alpha)'"
  assert_equal "$output" "50"
}

@test "what a red branch dropped is counted rather than silently cut" {
  # A cap that truncates without saying so is the half-truth this pack has a
  # document about: a reviewer reading the top of a quoted branch has to know
  # whether they are reading its beginning.
  use_tickets 01-alpha
  set_config RETRY_N 0
  set_config RECEIPT_MAX_LINES 10
  set_config TEST_CMD 'i=1; while [ $i -le 30 ]; do echo "suite line $i"; i=$((i + 1)); done; exit 1'

  run_loop
  assert_success

  assert_file_contains "$(receipt_path 01-alpha)" "the first 20 line(s) of 30 are not kept here"
  assert_file_contains "$(receipt_path 01-alpha)" "suite line 30"
  run bash -c "grep -c 'suite line' '$(receipt_path 01-alpha)'"
  assert_equal "$output" "10"
}

@test "the findings of a red review lens survive the gate's own tmpdir" {
  # The one [06] left to this ticket. A lens's prompt and stream live under the
  # gate's temporary directory and `gate_run` removes it, so after the iteration
  # the only trace of what a model found is whatever was copied out in time. A
  # session retried without them rewrites the same code and is reddened
  # identically, to the ceiling.
  use_tickets 01-alpha
  set_config LENSES "$(config_default LENSES)"
  set_config RETRY_N 0
  lens_verdict standards fail

  run_loop
  assert_success

  assert_file_contains "$(receipt_path 01-alpha)" "### standards — red"
  assert_file_contains "$(receipt_path 01-alpha)" "findings from the standards lens"
  # And the objective branches, which were green, are not quoted as findings.
  refute_file_contains "$(receipt_path 01-alpha)" "### tests — red"
}

@test "the receipt names the zone nothing in the gate judged" {
  # [24]'s line, on the surface where it lasts. It is said on every iteration and
  # scrolls past; a human deciding in the morning whether to believe a `resolved`
  # is exactly the reader it was written for.
  use_tickets 01-alpha
  printf 'cache/\n' >>"$PROJECT_DIR/.gitignore"
  git -C "$PROJECT_DIR" add -A
  git -C "$PROJECT_DIR" -c user.email=t@t -c user.name=t commit -q -m "test: a project that ignores its cache"
  # Written by the session and not seeded here: since [13] an iteration runs in a
  # worktree of its own, which carries what is committed and nothing else — an
  # ignored file lying in the tree the run was started in is not in the tree the
  # gate judges, which is exactly what that ticket closed.
  script_claude <<'FAKE'
#!/usr/bin/env bash
cat >/dev/null
mkdir -p src cache
printf 'written\n' >src/alpha.txt
printf 'x\n' >cache/thing
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_success

  assert_file_contains "$(receipt_path 01-alpha)" "What nothing here judged"
  assert_file_contains "$(receipt_path 01-alpha)" "nothing in this gate judged 1 ignored path(s): cache/"
}

# ── the routes with nothing to show ──────────────────────────────────────────

@test "an iteration that delivered nothing is not rendered as a judged one" {
  # [35]: the gate refuses before starting a branch, so the verdict line is
  # `delivery=red` alone — no `tests=`, no `typecheck=`, no `scope=` — and there is
  # nothing at all to go and read.
  use_tickets 01-alpha
  set_config RETRY_N 0
  session_writes_nothing

  run_loop
  assert_success

  assert_file_exists "$(receipt_path 01-alpha)"
  assert_file_contains "$(receipt_path 01-alpha)" "changed no file this gate can see"
  assert_file_contains "$(receipt_path 01-alpha)" "delivery=red"
  refute_file_contains "$(receipt_path 01-alpha)" "tests="
  # The branch it must not send anyone to read: [35] does not write one, on
  # purpose — it would hold the tree the session was handed. Nor a diff of a tree
  # against itself, which is what "changed no file" means in objects.
  refute_file_contains "$(receipt_path 01-alpha)" "git log -p failed/01-alpha"
  refute_file_contains "$(receipt_path 01-alpha)" "git diff-tree"
  assert_file_contains "$(receipt_path 01-alpha)" "nothing of the work itself"
}

@test "an iteration no gate judged says so instead of showing an empty verdict line" {
  # The other shape, and the one [23] warned about: a session that died takes the
  # gate with it, so `RALPH_GATE_VERDICTS` is empty. A blank line where the
  # verdicts go reads as "nothing was found wrong", which is the opposite of
  # "nothing looked".
  use_tickets 01-alpha
  set_config RETRY_N 0
  script_claude <<'FAKE'
#!/usr/bin/env bash
cat >/dev/null
echo '{"type":"system","subtype":"init","session_id":"s","model":"test-model"}'
exit 1
FAKE

  run_loop
  assert_success

  assert_file_exists "$(receipt_path 01-alpha)"
  assert_file_contains "$(receipt_path 01-alpha)" "No gate ran on this iteration"
  assert_file_contains "$(receipt_path 01-alpha)" "An empty verdict line is not a green one."
  # And it still says where the attempt was kept: this route does write one.
  assert_file_contains "$(receipt_path 01-alpha)" "git log -p failed/01-alpha"
}

@test "an iteration that walked no zone does not report an empty one" {
  # The refusal above, made where it was missing ([45]). The same route: no gate
  # ran, so nothing enumerated the ignored paths, the ignore frontier or what was
  # written after the tree was taken — and the section simply vanished, which reads
  # as "those zones were empty" instead of "nobody looked at them". These sentences
  # are written where the fact becomes known, by the gate as it judges and by the
  # rollback as it puts the tree back, so an iteration neither of them reached
  # produces none of them.
  use_tickets 01-alpha
  set_config RETRY_N 0
  script_claude <<'FAKE'
#!/usr/bin/env bash
cat >/dev/null
echo '{"type":"system","subtype":"init","session_id":"s","model":"test-model"}'
exit 1
FAKE

  run_loop
  assert_success

  assert_file_contains "$(receipt_path 01-alpha)" "What nothing here judged"
  assert_file_contains "$(receipt_path 01-alpha)" "An empty list here is not an empty zone."
}

@test "a branch the gate's own deadline killed says nothing ran" {
  # [43] one door down, by the other cause of a missing verdict ([45]). The reason
  # went out through `gate__log`, so stdout only, and a killed branch's output file
  # is empty — `receipt_keep_branch` drops it — so there was no findings section to
  # read the absence off either. What a human got was `tests=red` and
  # `escalated:failed-impl`: the claim that an implementation was judged and found
  # wrong, for a suite nobody ever ran to the end.
  use_tickets 01-alpha
  set_config RETRY_N 0
  set_config GATE_TIMEOUT 1
  set_config TEST_CMD "sleep 30"

  run_loop
  assert_success

  assert_ticket_status 01-alpha ready-for-human
  assert_file_contains "$(receipt_path 01-alpha)" "tests=red"
  assert_file_contains "$(receipt_path 01-alpha)" \
    "tests red (timed out after 1s): this branch was killed at the gate's own deadline"
  # The channel is what was missing and the colour is not: the verdict stays red
  # and the escalation stays what it was. A receipt that inferred anything else
  # from the verdict is precisely what [43] says cannot be done.
  assert_file_contains "$(receipt_path 01-alpha)" "escalated:failed-impl"
}

@test "a branch that left no verdict at all says so too" {
  # The sibling arm, and the reason both had to move together: `no verdict` and
  # `timed out` are one admission — this branch judged nothing — while an exit code
  # is a verdict whose output travels to the findings on its own.
  #
  # Staged by killing the subshell that collects the branch rather than the command
  # under it: `gate__branch` writes the `.rc` after its command returns, so a
  # command that dies of a signal still leaves one and only this does not.
  use_tickets 01-alpha
  set_config RETRY_N 0
  set_config TEST_CMD 'kill -9 $PPID'

  run_loop
  assert_success

  assert_file_contains "$(receipt_path 01-alpha)" \
    "tests red (no verdict): this branch ended without leaving one"
}

@test "a red branch the API merely refused is named as such in the receipt" {
  # [43] where it can actually reach a document, and finding that route is half the
  # work. A gate whose *every* red branch is a refused lens is `budget-pause`: the
  # ticket goes back with no retry charged, the loop has not finished with it, and
  # no receipt is written at all. The route that does reach one is the mixed gate —
  # a lens the API never let start beside a lens that answered `fail`. There the
  # gate is billable, the ticket escalates at its ceiling, and the verdict line
  # really does say `standards=red` for a branch that judged nothing.
  #
  # So the receipt has to carry the gate's own sentence about it. Inferring it from
  # the verdict is precisely what [43] says cannot be done.
  use_tickets 01-alpha
  set_config LENSES "$(config_default LENSES)"
  set_config RETRY_N 0
  lens_refused standards
  lens_verdict spec fail

  run_loop
  assert_success

  assert_ticket_status 01-alpha ready-for-human
  assert_file_exists "$(receipt_path 01-alpha)"
  assert_file_contains "$(receipt_path 01-alpha)" "standards=red"
  assert_file_contains "$(receipt_path 01-alpha)" \
    "the standards lens judged nothing because the API refused its session (five_hour)"
}

@test "a gate whose every red branch was refused writes no receipt at all" {
  # The other half of the pair, and it is what makes the one above a statement
  # about the mixed case rather than about lenses in general: a ticket given back
  # with no retry consumed has not been finished with, so there is nothing to
  # review asynchronously and the document that would say `standards=red` about a
  # session that never started is never written.
  use_tickets 01-alpha
  set_config LENSES "$(config_default LENSES)"
  set_config STERILE_K 1
  lens_refused standards

  run_loop
  assert_failure 4

  assert_ticket_status 01-alpha ready-for-agent
  run ticket_has_field 01-alpha Failures
  assert_failure
  refute_file_exists "$(receipt_path 01-alpha)"
  assert_file_contains "$FEATURE_DIR/run.log" "budget-pause"
  assert_file_contains "$FEATURE_DIR/run.log" "action=given-back"
}

@test "a session that edited the tracker is not reported as a red gate" {
  # [21]'s own constraint on this ticket: the three branches can all be green, and
  # a receipt that said `gate-red` would send a human to read tests that pass.
  use_tickets 01-alpha
  set_config RETRY_N 0
  script_claude <<'FAKE'
#!/usr/bin/env bash
cat >/dev/null
mkdir -p src
printf 'written\n' >src/alpha.txt
perl -pi -e 's/^\*\*Write-surface:\*\* .*/**Write-surface:** `*`/' \
  "$(cat "$RALPH_SHIM_STATE/tracker-dir")/01-alpha.md"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_success

  assert_file_contains "$(receipt_path 01-alpha)" "edited the tracker"
  assert_file_contains "$(receipt_path 01-alpha)" "outcome: \`tracker-write\`"
  refute_file_contains "$(receipt_path 01-alpha)" "The gate on \`01-alpha\` was red"
}

# ── what a receipt may not claim ─────────────────────────────────────────────

@test "a forensic branch git refused is not offered as something to read" {
  # The half `|| true` hides. `failures_preserve_attempt` is called without its
  # status being consumed — a ref named `failed` already in the way, a lock a
  # crashed git left — so an escalation can land with nothing behind it. A receipt
  # that named the branch anyway would send a human to `git log -p` a ref that does
  # not exist, which is the misrouting this whole document is written against.
  #
  # Found by the mutation gate: the entry that goes back to `|| true` plus an
  # unconditional name reported VACUOUS, because every other test on this path has
  # a git that says yes.
  use_tickets 01-alpha
  set_config RETRY_N 0
  stub_exit tests 1
  # A project with a branch called `failed` cannot also have `failed/01-alpha`.
  git -C "$PROJECT_DIR" branch failed

  run_loop
  assert_success

  assert_output_contains "could not write branch failed/01-alpha"
  assert_ticket_status 01-alpha ready-for-human
  assert_file_exists "$(receipt_path 01-alpha)"
  # The line that would misroute, named exactly ([45]). A blanket refusal of the
  # branch name was the right assertion while the only way the document could
  # mention it was to offer it as evidence; the receipt now says out loud that git
  # refused to write it, which is the opposite claim and the one a human needs.
  refute_file_contains "$(receipt_path 01-alpha)" "git log -p failed/01-alpha"
  refute_file_contains "$(receipt_path 01-alpha)" "the attempt, kept before the rollback"
  assert_file_contains "$(receipt_path 01-alpha)" \
    "could not write branch failed/01-alpha"
}

# ── what did not happen ──────────────────────────────────────────────────────
#
# The second channel ([45]). The notes above are about coverage — the zones nobody
# walked — and they are on every iteration, green ones included. These are about
# the pack's own actions coming back short, they are rare, and what a human does
# about them is different: a tree that is not back where the session found it, a
# reference that was promised and never written. [10] wired the sentences it had
# in front of it and half of `failures.sh`'s admissions had no way to a document
# at all — including the five reasons the `failed/<ticket>` it sends a human to
# read may not exist.

@test "a rollback that could not act leaves the document that says so" {
  # Both halves of the gap in one run.
  #
  # The trigger: this iteration is on a fresh retry that nothing will ever spend,
  # because the run stops over the rollback ([34]). The escalation clause therefore
  # never fires, and the strongest failure this pack can report produced no
  # document whatsoever.
  #
  # The channel: `failures_rollback`'s three refusals were `failures__log`, so even
  # on the iterations that did get a receipt they were on stdout only.
  #
  # Probe B of [34] as the stage, because it is the one scenario that closes the
  # instrument for real — the session destroys the pinned ignore rules, so the
  # snapshot refuses and there is nothing the rollback can act on.
  use_tickets 01-alpha 02-beta
  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src lib
printf 'written\n' >src/alpha.txt
printf 'rogue\n' >lib/rogue.sh
rm -rf "${TMPDIR:-/tmp}"/ralph-ignore.*
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop_own_tmp
  assert_failure 4

  assert_file_exists "$(receipt_path 01-alpha)"
  assert_file_contains "$(receipt_path 01-alpha)" "What did not happen"
  assert_file_contains "$(receipt_path 01-alpha)" \
    "cannot read the working tree — nothing was rolled back"
  # And the meta line stops reading as a plan. `retry:1/2` is an honest account of
  # what the policy decided and a misleading one to read alone here: no later
  # iteration is coming to spend it.
  assert_file_contains "$(receipt_path 01-alpha)" "the run stops on this iteration"
  # The bound: the ticket was never handed to a human, so nothing about the
  # escalation clause is what produced this document.
  assert_ticket_status 01-alpha ready-for-agent
}

@test "the context figure is a peak and never a total" {
  # [20]: the number comes from the `assistant` events and the `usage` block of a
  # multi-turn `result` repeats the last turn's counters instead of summing them.
  # A receipt presenting it as an audited total would lie about exactly the
  # session that used the most.
  use_tickets 01-alpha

  run_loop
  assert_success

  assert_file_contains "$(receipt_path 01-alpha)" "the peak observed in the session"
  assert_file_contains "$(receipt_path 01-alpha)" "Not a total"
}

@test "the attempt number survives the counter that gets cleared on delivery" {
  # [26]: `Failures:` is a retry budget and `mark_resolved` drops it, so the
  # delivered ticket cannot say it took three tries. Read after the tracker was
  # restored from its pre-session snapshot — which is what makes it the loop's
  # number and not one a session could have written into its own ticket — and
  # before the marking.
  use_tickets 01-alpha
  set_config RETRY_N 5
  set_config STERILE_K 5
  stub_exit tests 1

  # Two red attempts, then a green one in the same run.
  script_claude <<'FAKE'
#!/usr/bin/env bash
cat >/dev/null
n="$(cat "$RALPH_SHIM_STATE/attempts" 2>/dev/null || echo 0)"
n=$((n + 1))
printf '%s\n' "$n" >"$RALPH_SHIM_STATE/attempts"
mkdir -p src
printf 'written %s\n' "$n" >src/alpha.txt
[ "$n" -lt 3 ] || printf '0\n' >"$RALPH_SHIM_STATE/stub-tests.exit"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_success

  assert_ticket_status 01-alpha resolved
  # The counter really is gone from the ticket, which is what makes the receipt the
  # only place the number survives ([26]).
  run ticket_has_field 01-alpha Failures
  assert_failure
  assert_file_contains "$(receipt_path 01-alpha)" "attempt: 3"
}

@test "the receipt is not built out of the run journal" {
  # The decision this ticket exists to take ([21]). `run.log` is inside the one
  # part of the loop's state a session can reach, so a receipt assembled from it is
  # a session's account of itself. A session that rewrites the journal into a
  # different night must change nothing in the document.
  use_tickets 01-alpha
  script_claude <<'FAKE'
#!/usr/bin/env bash
cat >/dev/null
mkdir -p src
printf 'written\n' >src/alpha.txt
printf '2020-01-01T00:00:00Z\t01-alpha\tresolved\tturns=99\tcost=99\ttokens=99\taction=none\n' \
  >"$(cat "$RALPH_SHIM_STATE/project-dir")/.scratch/demo/run.log"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":4,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_success

  assert_file_contains "$(receipt_path 01-alpha)" "turns: 4"
  refute_file_contains "$(receipt_path 01-alpha)" "turns: 99"
  refute_file_contains "$(receipt_path 01-alpha)" "2020-01-01"
}

@test "writing a receipt is not a write in the tracker" {
  # The register [13] keeps is about tickets: it tells the restore and the
  # quarantine which entries under `issues/` are the loop's own doing. A receipt is
  # a document under `receipts/`, which neither guard ever looks at — noting it
  # would hand them an id to skip, and the skip would land on whichever sibling
  # iteration was in flight at the time.
  use_tickets 01-alpha
  pack_run "
    RALPH_TRACKER_LOG='$RALPH_TEST_DIR/register'
    : >\"\$RALPH_TRACKER_LOG\"
    printf 'body\n' | tracker_emit_receipt 01-alpha >/dev/null
    tracker_append_note 01-alpha </dev/null
    printf 'register=[%s]\n' \"\$(tracker_writes_since 0)\"
  "
  assert_success
  # The note is there and the receipt is not: this is an equality, not a subset,
  # so an implementation that noted neither would be red here too.
  assert_output_contains "register=[ 01-alpha ]"
  run bash -c "grep -c . '$RALPH_TEST_DIR/register'"
  assert_equal "$output" "1"
}

# ── the journal, and the one thing that makes it worth reading ───────────────

@test "the journal says what the loop then did about the ticket" {
  # [07] left the failure policy's action on stdout only, so a reader of the
  # journal alone could not tell a red gate that was retried from a red gate that
  # was escalated. Two consequences, one word.
  use_tickets 01-alpha
  set_config RETRY_N 1
  set_config STERILE_K 4
  stub_exit tests 1

  run_loop
  assert_success

  assert_file_contains "$FEATURE_DIR/run.log" "action=retry:1/1"
  assert_file_contains "$FEATURE_DIR/run.log" "action=escalated:failed-impl"
}

@test "a journal rewritten under the run is named, with the run's own lines" {
  # Nothing can stop the write: the file is in the one directory this pack cannot
  # guard, and moving it out of reach would move it out of the morning. So the
  # journal is not tamper-proof, it is tamper-evident — the run keeps its own copy,
  # in a variable of the pilot, and prints it when the file no longer ends with it.
  use_tickets 01-alpha 02-beta
  script_claude <<'FAKE'
#!/usr/bin/env bash
cat >/dev/null
mkdir -p src
printf 'written\n' >"src/$(basename "$PWD").txt"
printf 'a night that never happened\n' \
  >"$(cat "$RALPH_SHIM_STATE/project-dir")/.scratch/demo/run.log"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop

  assert_output_contains "does not hold exactly"
  # The copy has to go somewhere: after this the file is the only one left, and it
  # is a lie.
  assert_output_contains "ralph: journal: "
  assert_output_contains "01-alpha"
}

@test "an honest run does not accuse itself, reclaims included" {
  # The refutation the pair needs, and it is not decoration: the reclaim lines were
  # written from the right-hand side of a pipeline, which is a subshell, so the
  # run's copy of them died there — every run that reclaimed anything would have
  # ended by reporting its own journal rewritten.
  use_tickets 01-alpha 02-beta
  stamp_claim 02-beta "pid:999999" "2026-07-25T08:00:00Z"

  run_loop
  assert_success

  refute_output_contains "does not hold exactly"
  assert_file_contains "$FEATURE_DIR/run.log" "reclaimed-"
  # And the file really is what the run says it is.
  run bash -c "grep -c 'action=' '$FEATURE_DIR/run.log'"
  assert_equal "$output" "3"
}

@test "a receipt that would keep no lines is refused at the door" {
  # The value that switches this module off without a word. Refused before the
  # locks and before a session, like every other key that would leave a control
  # reporting green on nothing ([17], [31]).
  use_tickets 01-alpha
  set_config RECEIPT_MAX_LINES 0

  run_loop
  assert_failure 2

  assert_output_contains "RECEIPT_MAX_LINES"
  assert_equal "$(claude_call_count)" "0"
}

@test "two iterations in flight write two receipts, each about its own ticket" {
  # The question [13] makes every ticket ask: what does the harness count. The
  # receipt's workspace is a `mktemp -d` per iteration held in a variable of that
  # iteration's subshell, so two in flight cannot see each other's — and a single
  # shared path would show up here as one document carrying both tickets' zones.
  use_tickets 01-alpha 02-beta
  set_config MAX_PARALLEL 3

  run_loop
  assert_success

  assert_file_contains "$(receipt_path 01-alpha)" "01-alpha — resolved"
  assert_file_contains "$(receipt_path 02-beta)" "02-beta — resolved"
  refute_file_contains "$(receipt_path 01-alpha)" "02-beta"
  refute_file_contains "$(receipt_path 02-beta)" "01-alpha"
  # Two commits, two objects, and neither receipt names the other's.
  run bash -c "grep -c 'git show' '$(receipt_path 01-alpha)'"
  assert_equal "$output" "1"
}

@test "the journal is still never read to decide anything" {
  # The acceptance criterion, asserted as a property of the run rather than as a
  # claim in a comment: a journal that says the frontier is drained changes
  # nothing, because the tracker is the only authority.
  use_tickets 01-alpha
  mkdir -p "$FEATURE_DIR"
  printf '2020-01-01T00:00:00Z\t01-alpha\tresolved\tturns=1\tcost=0\ttokens=0\taction=none\n' \
    >"$FEATURE_DIR/run.log"

  run_loop
  assert_success

  assert_ticket_status 01-alpha resolved
  assert_file_exists "$(receipt_path 01-alpha)"
}
