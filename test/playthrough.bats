#!/usr/bin/env bats
#
# The terminal value gate ([11]): what happens when the frontier empties.
#
# Every other gate in this pack judges a change. This one judges the **feature**,
# once, at the end, and it is the only thing standing between "every ticket went
# green" and "the thing works". So the properties under test here are not about a
# verdict being computed — they are about what the loop is entitled to report:
#
#   - a run may not exit successfully without a green playthrough **on disk**;
#   - a red one is handled hybrid and bounded, and never spins;
#   - the material half really runs (the project's own commands), and the model
#     half writes nothing;
#   - nothing was judged is not the same as judged red, and only one of the two
#     accuses anybody.
#
# The tests drive the real `loop.sh` as a process and assert on what a human or
# the next run would find: the tracker, the artefact, the journal, the exit code.

load helpers/harness
load helpers/assert

setup() {
  harness_setup
}

teardown() {
  harness_teardown
}

# The answer of a value gate that found an internal wiring hole. Written once
# here because four tests need the same four tagged lines and a fifth needs them
# with one field changed.
answer_internal_hole() {
  playthrough_answer \
    'the marker is written but the demo never prints it.' \
    'RALPH-PLAYTHROUGH-STEP: the user runs the demo and sees nothing' \
    'RALPH-PLAYTHROUGH-HOLE: the markers are written and nothing renders them' \
    'RALPH-PLAYTHROUGH-CLASS: internal' \
    'RALPH-PLAYTHROUGH-TITLE: render the markers the demo writes' \
    'RALPH-PLAYTHROUGH-SURFACE: `src/wired.txt`' \
    'RALPH-PLAYTHROUGH-VERDICT: fail'
}

# Every ticket the tracker holds that this test did not seed, one per line — how
# a test says "the loop opened a ticket" without knowing what number the adapter
# allocated. The seeded ids are given rather than inferred from the number: the
# next number the adapter hands out is `02`, which is also a fixture's, so a rule
# written on the shape of an id would have called the first opened ticket a
# fixture and read every one of these assertions the wrong way round.
#
#   opened_tickets 01-alpha
opened_tickets() {
  local seeded=" $* " f id
  for f in "$TRACKER_DIR"/*.md; do
    [ -e "$f" ] || continue
    id="$(basename "$f" .md)"
    case "$seeded" in
      *" $id "*) continue ;;
    esac
    printf '%s\n' "$id"
  done
}

# How many of them carry one of the two slugs this module opens tickets under.
opened_of_kind() {
  local kind="$1" n=0 id
  shift
  for id in $(opened_tickets "$@"); do
    case "$id" in
      *-playthrough-"$kind"-*) n=$((n + 1)) ;;
    esac
  done
  printf '%s\n' "$n"
}

# ── the module on its own ────────────────────────────────────────────────────

@test "the preflight refuses a bound nothing can compare against, and keeps zero" {
  # Zero is not "off", it is "always ask a human", and refusing it would take a
  # legitimate posture away. Anything that is not a number is a bound `[ -ge ]`
  # reads as an error on the one line that decides whether a night keeps going.
  set_config PLAYTHROUGH_REINJECT_MAX 0
  pack_run 'playthrough_preflight'
  assert_success

  set_config PLAYTHROUGH_REINJECT_MAX later
  pack_run 'playthrough_preflight'
  assert_failure
  assert_output_contains "PLAYTHROUGH_REINJECT_MAX"

  run_loop
  assert_failure
  assert_equal "$status" "2"
  assert_output_contains "PLAYTHROUGH_REINJECT_MAX"
}

@test "the playthrough is kept per feature, where a human reads it" {
  pack_run 'playthrough_path'
  assert_success
  assert_equal "$output" "$(playthrough_file)"
}

# ── a green feature ──────────────────────────────────────────────────────────

@test "a drained frontier is played through before the run reports a night done" {
  use_tickets 01-alpha

  run_loop
  assert_success
  loop_output="$output"

  # One value gate, after the delivery session and before the exit.
  assert_equal "$(playthrough_call_count)" "1"
  assert_ticket_status 01-alpha resolved

  # The artefact is the condition of closing, so it is what is asserted — not the
  # exit code alone, which a run that wrote nothing would also have.
  assert_file_exists "$(playthrough_file)"
  assert_file_contains "$(playthrough_file)" "**Verdict:** pass"
  assert_file_contains "$(playthrough_file)" "the feature closes"
  # The narration the session wrote, in the document a human reads tomorrow.
  assert_file_contains "$(playthrough_file)" "the user runs the demo and sees the markers"

  output="$loop_output"
  assert_output_contains "frontier empty"
  assert_file_contains "$FEATURE_DIR/run.log" "playthrough-green"
}

@test "the material half really runs: the project's own commands, on its own tree" {
  use_tickets 01-alpha
  printf 'the demo printed alpha and beta\n' >"$SHIM_STATE/stub-run.out"

  run_loop
  assert_success

  # The commands ran, once each. This is the half no model is asked about: they
  # come from the sealed configuration, and their transcripts are the evidence.
  assert_equal "$(stub_call_count run)" "1"
  assert_equal "$(stub_call_count visual)" "1"

  # And what they answered reached both the prompt and the document.
  run bash -c "printf '%s' \"\$(cat '$SHIM_STATE/claude.calls/2/stdin')\""
  assert_output_contains "the demo printed alpha and beta"
  assert_file_contains "$(playthrough_file)" "the demo printed alpha and beta"
  assert_file_contains "$(playthrough_file)" "exit 0"
}

@test "the value gate is handed the user flow it is replaying, and the tree it ran on" {
  use_tickets 01-alpha

  run_loop
  assert_success

  prompt="$(playthrough_call_stdin)"
  # The spec's own user flow, verbatim: this gate replays what the feature
  # promised, not what a ticket asked for.
  case "$prompt" in
    *"The user runs \`make demo\`"*) ;;
    *) fail "the value gate was not handed the spec's user flow" ;;
  esac
  case "$prompt" in
    *"## The user flow you are replaying"*) ;;
    *) fail "the prompt has no flow section" ;;
  esac
  # The tree the commands ran on, named in the prompt and in the document, so
  # that a verdict is about a state of the repository somebody can go and read.
  tree="$(git -C "$PROJECT_DIR" log -1 --format=%T)"
  case "$prompt" in
    *"The tree this ran on:"*) ;;
    *) fail "the prompt does not name the tree" ;;
  esac
  assert_file_contains "$(playthrough_file)" "**Tree:**"
  refute_file_contains "$(playthrough_file)" "**Tree:** none"
  [ -n "$tree" ] || fail "the fixture has no commit"
}

@test "the value gate cannot write: it is spawned with the read-only posture" {
  use_tickets 01-alpha

  run_loop
  assert_success

  argv="$(playthrough_call_argv)"
  case "$argv" in
    *"Read,Grep,Glob"*) ;;
    *) fail "the value gate was not restricted to the read-only tool set" ;;
  esac
  case "$argv" in
    *--strict-mcp-config*) ;;
    *) fail "the value gate would load the judged tree's MCP servers" ;;
  esac
  # And the document is the pack's, not the session's: the model answered tagged
  # lines and this file was written by the loop.
  assert_file_contains "$(playthrough_file)" "# Playthrough — demo"
}

@test "a frontier that was empty from the start closes nothing and spends nothing" {
  # Exit 5 is "this run ground nothing", which is not a feature to close. A value
  # gate here would spend a session and the project's own commands on every run
  # started against the wrong tracker.
  run_loop
  assert_failure
  assert_equal "$status" "5"
  assert_equal "$(playthrough_call_count)" "0"
  assert_equal "$(stub_call_count run)" "0"
  refute_file_exists "$(playthrough_file)"
}

@test "the flow replayed is the one this run started with, not what a session rewrote" {
  # The trust-boundary question of this ticket, and the corollary [21] left the
  # project: a control that reads a file the session can write is not a control.
  # `spec.md` lives in `.scratch/<feature>/`, which the scope-guard steps over and
  # the rollback does not undo — so a delivery session can rewrite the user flow
  # this gate replays, and nothing anywhere would say so.
  use_tickets 01-alpha

  script_claude <<'FAKE'
#!/usr/bin/env bash
cat >/dev/null
project="$(cat "$RALPH_SHIM_STATE/project-dir")"
cat >"$project/.scratch/demo/spec.md" <<'SPEC'
# Spec — Demo feature

## User Flow

1. The user does nothing at all, and the feature is finished.
SPEC
mkdir -p src
printf 'alpha\n' >src/alpha.txt
echo '{"type":"system","subtype":"init","session_id":"s","model":"test-model"}'
echo '{"type":"result","subtype":"success","is_error":false,"result":"done","num_turns":1,"total_cost_usd":0.01}'
FAKE

  run_loop
  assert_success

  prompt="$(playthrough_call_stdin)"
  case "$prompt" in
    *"The user runs \`make demo\`"*) ;;
    *) fail "the value gate was not handed the flow this run started with" ;;
  esac
  case "$prompt" in
    *"does nothing at all"*) fail "a flow a session rewrote reached the value gate" ;;
  esac

  # And the rewrite really happened, in the tree the run was started in. Without
  # this the test would be green on a session that could not write there at all,
  # which is the shape of a guarantee verified against nothing.
  assert_file_contains "$FEATURE_DIR/spec.md" "does nothing at all"
}

# ── a feature that does not close ────────────────────────────────────────────

@test "a contractual hole goes to a human, and the run does not report a night done" {
  use_tickets 01-alpha
  playthrough_answer \
    'RALPH-PLAYTHROUGH-HOLE: the spec asks for a summary nothing was ever built for' \
    'RALPH-PLAYTHROUGH-CLASS: contract' \
    'RALPH-PLAYTHROUGH-TITLE: the summary the spec asks for does not exist' \
    'RALPH-PLAYTHROUGH-VERDICT: fail'

  run_loop
  assert_failure
  assert_equal "$status" "4"
  assert_output_contains "the feature does not close"

  # The ticket the loop opened is on the human sink and never on the frontier: a
  # hole this loop must not close by itself is a decision, and a session that
  # picked it up would spend a night on it.
  opened="$(opened_tickets 01-alpha)"
  [ -n "$opened" ] || fail "no ticket was opened for a contractual hole"
  assert_equal "$(ticket_status "$opened")" "ready-for-human"
  assert_file_contains "$(ticket_file "$opened")" "the summary the spec asks for"

  assert_file_contains "$(playthrough_file)" "**Verdict:** fail"
  assert_file_contains "$(playthrough_file)" "a hole this loop must not close by itself"
  assert_file_contains "$FEATURE_DIR/run.log" "playthrough-blocked"
}

@test "an unclassified hole is treated as one for a human" {
  use_tickets 01-alpha
  playthrough_answer \
    'RALPH-PLAYTHROUGH-HOLE: something is wrong and I could not tell what kind' \
    'RALPH-PLAYTHROUGH-VERDICT: fail'

  run_loop
  assert_failure
  assert_equal "$status" "4"

  opened="$(opened_tickets 01-alpha)"
  [ -n "$opened" ] || fail "an unclassified hole opened nothing at all"
  assert_equal "$(ticket_status "$opened")" "ready-for-human"
  assert_file_contains "$(playthrough_file)" "unclassified"
}

@test "a value gate that cannot see the tree it would conclude on closes nothing" {
  # The ninth reader of a tree object, and the discipline [59] left every one of
  # them: a refusal travels by the status, and an empty tree is not "nothing to
  # judge". A value gate that read an unreadable repository as a feature with
  # nothing wrong with it would be [35]'s false delivered through a new door.
  use_tickets 01-alpha
  printf 'locked\n' >"$PROJECT_DIR/locked.txt"
  chmod 000 "$PROJECT_DIR/locked.txt"

  run_loop
  seen="$status"
  loop_output="$output"
  chmod 644 "$PROJECT_DIR/locked.txt"

  assert_equal "$seen" "4"
  # Refused before a session is spent: there is nothing to conclude on, so
  # spawning one would spend quota to judge a repository nobody could read.
  assert_equal "$(playthrough_call_count)" "0"
  assert_equal "$(opened_tickets 01-alpha)" ""
  assert_file_contains "$(playthrough_file)" "could not read the tree"

  output="$loop_output"
  assert_output_contains "the feature does not close"
}

@test "a value gate that answered without a verdict closes nothing and accuses nobody" {
  use_tickets 01-alpha
  playthrough_answer 'I had a look around and here are some thoughts.'

  run_loop
  assert_failure
  assert_equal "$status" "4"
  assert_output_contains "ended without a verdict line"

  # Nothing was judged, so nothing is on anybody's desk: a ticket opened here
  # would accuse a feature of a hole no session found.
  assert_equal "$(opened_tickets 01-alpha)" ""
  assert_file_contains "$(playthrough_file)" "**Verdict:** none"
}

@test "a value gate the API refused closes nothing and opens no ticket" {
  use_tickets 01-alpha
  playthrough_refused blocked five_hour 0

  run_loop
  assert_failure
  assert_equal "$status" "4"

  # [43]'s direction, one tier further: a session that never started looked at
  # nothing, so the feature does not close and no hole is named.
  assert_equal "$(opened_tickets 01-alpha)" ""
  assert_file_contains "$(playthrough_file)" "the API refused"
}

@test "a value gate that answered while the window was blocked still closes the feature" {
  # The paired witness of the test above, and the ordering [43] wrote for the lens
  # tier: **the verdict outranks the event**. The in-band signal can say `blocked`
  # for the window *after* the one this session is spending, and a gate that
  # answered `pass` looked. Asked the other way round, a feature would fail to
  # close on a subscription warning about tomorrow — and nothing would say so.
  use_tickets 01-alpha
  playthrough_rate_limit \
    '{"status":"blocked","resetsAt":4102444800,"rateLimitType":"five_hour","isUsingOverage":false}'

  run_loop
  assert_success

  assert_equal "$(playthrough_call_count)" "1"
  assert_file_contains "$(playthrough_file)" "**Verdict:** pass"
  refute_file_contains "$(playthrough_file)" "the API refused"
  assert_file_contains "$FEATURE_DIR/run.log" "playthrough-green"
}

@test "a project that has not claimed real assets cannot close a feature" {
  use_tickets 01-alpha
  set_config VISUAL_REAL_ASSETS 0

  run_loop
  assert_failure
  assert_equal "$status" "4"

  # Refused before a session is spent: nothing here could have been measured, so
  # spawning one would spend quota to learn what the configuration already says.
  assert_equal "$(playthrough_call_count)" "0"
  assert_output_contains "VISUAL_REAL_ASSETS"

  opened="$(opened_tickets 01-alpha)"
  [ -n "$opened" ] || fail "a feature that cannot be closed asked nobody"
  assert_equal "$(ticket_status "$opened")" "ready-for-human"
  assert_file_contains "$(playthrough_file)" "VISUAL_REAL_ASSETS"
}

@test "an unconfigured value gate names every key it is missing" {
  use_tickets 01-alpha
  set_config RUN_CMD ""
  set_config VISUAL_CMD ""

  run_loop
  assert_failure
  assert_equal "$status" "4"
  assert_output_contains "RUN_CMD"
  assert_output_contains "VISUAL_CMD"
  assert_equal "$(stub_call_count run)" "0"
}

@test "a green verdict nobody can read tomorrow does not close the feature" {
  use_tickets 01-alpha
  # The document's own directory, taken by a file: the write fails, and the
  # verdict was green. A closure that survived this would be a feature reported
  # done on a proof that exists nowhere.
  printf 'not a directory\n' >"$PROJECT_DIR/docs"
  git -C "$PROJECT_DIR" add -A
  git -C "$PROJECT_DIR" commit -q -m "test: docs is a file"

  run_loop
  assert_failure
  assert_equal "$status" "4"
  assert_output_contains "could not be written"
  assert_file_contains "$FEATURE_DIR/run.log" "playthrough-blocked"
}

# ── the hybrid, and its bound ────────────────────────────────────────────────

@test "an internal wiring hole comes back as a ticket the same run then grinds" {
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
  loop_output="$output"

  # Two value gates and two deliveries: the first playthrough put work back on
  # the frontier, the loop ground it, and the second closed the feature. That is
  # the whole of the hybrid, end to end.
  assert_equal "$(playthrough_call_count)" "2"
  opened="$(opened_tickets 01-alpha)"
  [ -n "$opened" ] || fail "the internal hole opened no ticket"
  assert_equal "$(ticket_status "$opened")" "resolved"
  assert_file_exists "$PROJECT_DIR/src/wired.txt"

  # The ticket a session was handed carried the surface the gate will judge it
  # on, and the hole it exists for.
  assert_file_contains "$(ticket_file "$opened")" "src/wired.txt"
  assert_file_contains "$(ticket_file "$opened")" "nothing renders them"
  # A new ticket, so no retry budget is inherited and none is cleared: the
  # question [26] and [16] left to this path, answered by construction.
  ticket_has_field "$opened" Failures && fail "a wiring ticket inherited a retry budget"

  output="$loop_output"
  assert_output_contains "is on the frontier (1 of 2)"
  assert_file_contains "$FEATURE_DIR/run.log" "playthrough-reinjected"
  assert_file_contains "$FEATURE_DIR/run.log" "playthrough-green"
  assert_file_contains "$(playthrough_file)" "**Verdict:** pass"
}

@test "past its bound the same feature asks a human instead of re-injecting" {
  use_tickets 01-alpha
  set_config PLAYTHROUGH_REINJECT_MAX 1
  playthrough_answer_nth 1 \
    'RALPH-PLAYTHROUGH-HOLE: the markers are written and nothing renders them' \
    'RALPH-PLAYTHROUGH-CLASS: internal' \
    'RALPH-PLAYTHROUGH-TITLE: render the markers the demo writes' \
    'RALPH-PLAYTHROUGH-SURFACE: `src/wired.txt`' \
    'RALPH-PLAYTHROUGH-VERDICT: fail'
  playthrough_answer_nth 2 \
    'RALPH-PLAYTHROUGH-HOLE: the rendering is there and the demo still shows nothing' \
    'RALPH-PLAYTHROUGH-CLASS: internal' \
    'RALPH-PLAYTHROUGH-TITLE: call the renderer from the demo entry point' \
    'RALPH-PLAYTHROUGH-SURFACE: `src/entry.txt`' \
    'RALPH-PLAYTHROUGH-VERDICT: fail'

  run_loop
  assert_failure
  assert_equal "$status" "4"
  assert_output_contains "past the 1 re-injection(s)"

  # One wiring ticket, ground; the second hole went to a human rather than onto
  # the frontier. Both halves are counted, because a bound that opened nothing at
  # all would satisfy the second on its own.
  assert_equal "$(opened_of_kind wiring 01-alpha)" "1"
  assert_equal "$(opened_of_kind gap 01-alpha)" "1"
  refute_file_exists "$PROJECT_DIR/src/entry.txt"
}

@test "the same hole twice opens one ticket, and the second round asks a human" {
  use_tickets 01-alpha
  # The same title on both rounds: a session that closed nothing, a hole that
  # came back. Without this the loop would re-inject the same work every round
  # until the bound, and with a high bound it would not terminate at all.
  answer_internal_hole

  run_loop
  assert_failure
  assert_equal "$status" "4"
  assert_output_contains "already carries a ticket for"

  # One wiring ticket for two rounds, and a human asked on the second.
  assert_equal "$(opened_of_kind wiring 01-alpha)" "1"
  assert_equal "$(opened_of_kind gap 01-alpha)" "1"
}

@test "a hole whose surface would cover the harness's own configuration is not handed to a session" {
  use_tickets 01-alpha
  playthrough_answer \
    'RALPH-PLAYTHROUGH-HOLE: the gate never runs the demo' \
    'RALPH-PLAYTHROUGH-CLASS: internal' \
    'RALPH-PLAYTHROUGH-TITLE: make the gate run the demo' \
    'RALPH-PLAYTHROUGH-SURFACE: `.claude/ralph.config.sh`' \
    'RALPH-PLAYTHROUGH-VERDICT: fail'

  run_loop
  assert_failure
  assert_equal "$status" "4"
  assert_output_contains "write-surface cannot be handed to a session"

  # A ticket declaring the harness's own configuration would send a session to
  # spend a night on work `gate_is_sealed` reds every time. It goes to a human,
  # and never onto the frontier. Counted both ways: a run that opened nothing
  # would satisfy the refutation on its own.
  assert_equal "$(opened_of_kind wiring 01-alpha)" "0"
  assert_equal "$(opened_of_kind gap 01-alpha)" "1"
  assert_equal "$(ticket_status "$(opened_tickets 01-alpha)")" "ready-for-human"
}

@test "an internal hole with no write-surface is not handed to a session either" {
  use_tickets 01-alpha
  playthrough_answer \
    'RALPH-PLAYTHROUGH-HOLE: the demo prints nothing' \
    'RALPH-PLAYTHROUGH-CLASS: internal' \
    'RALPH-PLAYTHROUGH-TITLE: print the markers' \
    'RALPH-PLAYTHROUGH-VERDICT: fail'

  run_loop
  assert_failure
  assert_equal "$status" "4"
  # A ticket with no declared surface is the scope-guard's fail-safe case: every
  # path it writes is an overflow, so it could never be delivered by anybody.
  assert_output_contains "none named"
  assert_equal "$(opened_of_kind wiring 01-alpha)" "0"
  assert_equal "$(opened_of_kind gap 01-alpha)" "1"
  assert_equal "$(ticket_status "$(opened_tickets 01-alpha)")" "ready-for-human"
}

# ── the layer next door ──────────────────────────────────────────────────────

@test "the audit receipt names the playthrough by path and never by content" {
  use_tickets 01-alpha 02-beta
  # A playthrough from an earlier round, which is the case a receipt's reader
  # meets: the wiring ticket exists *because* that document is red.
  mkdir -p "$PROJECT_DIR/docs/playthroughs"
  printf '# Playthrough — demo\n\n**Verdict:** fail\n\nthe secret narration\n' \
    >"$(playthrough_file)"

  run_loop
  assert_success

  receipt="$PROJECT_DIR/receipts/demo/01-alpha.md"
  assert_file_exists "$receipt"
  assert_file_contains "$receipt" "docs/playthroughs/demo.md"
  # By reference, like the commit and the branch. A receipt that carried the text
  # would make the proof that a feature works a paragraph of a document
  # RECEIPTS_RETENTION_DAYS deletes.
  refute_file_contains "$receipt" "the secret narration"
}
