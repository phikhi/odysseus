#!/usr/bin/env bats
#
# The hostile canary: one run, three iterations, against the world as it is
# rather than as the fixtures wish it were.
#
# Every defect this pack has shipped so far lived in the gap between the
# cooperative fake the rest of the suite drives — writes nothing, commits
# nothing, emits three perfect lines at once, finishes instantly — and a real
# session. So this file drives the opposite: sessions that actually write their
# write-surface, one that commits everything it touched, one whose stream
# arrives in pieces with a line cut in half, over a tracker that is dirty,
# CRLF-encoded and already carrying two claims — one held by a live run, one left
# behind by a run that was killed.
#
# It is a canary, not a unit test: when it goes red, something about the way the
# pack meets reality just changed. Read it before touching the assertions.

load helpers/harness
load helpers/assert

setup() {
  harness_setup
  # At the value a project installs, review lenses included. The rest of the suite
  # runs with the judgement tier off — the harness injects that so a count of
  # sessions stays a count of sessions — and a default nothing exercises end to end
  # is a default verified only in the file that declares it. Two of the tests below
  # never reach the lens phase, and that is not an oversight: their objective checks
  # are red, and the gate does not spend a session on a verdict that cannot change
  # the outcome.
  set_config LENSES "$(config_default LENSES)"
  # And the fourth layer's tier, for the same reason ([14]). The harness turns it
  # off so a count of sessions stays a count of sessions; here it is on, so the
  # hostile world really does spawn a retro after every ticket the loop finished
  # with — and the honest session below has to answer it.
  set_config RETRO "$(config_default RETRO)"
}

teardown() {
  harness_teardown
}

# A session that reads its own ticket, writes exactly the files the ticket
# declared, and reports success — the honest behaviour the pack asks for. Its
# stream is emitted differently on each call, so one run covers three shapes.
script_honest_session() {
  script_claude <<'FAKE'
#!/usr/bin/env bash
prompt="$(cat)"

# A review lens, answered the way a real one answers: findings, then a verdict
# line. It comes first because the sequence counter below is about *delivery*
# sessions — a lens taking a number from it would make iteration 2 arrive third,
# and this whole file would be driving a scenario other than the one it describes.
#
# Recorded by name and never by call index: the lens branches are concurrent, so
# which of them is the run's second `claude` is not a fact a test may assume.
case "$prompt" in
  *RALPH-LENS-VERDICT*)
    lens="$(printf '%s' "$prompt" |
      sed -n 's/^## The lens you are: \(.*\)$/\1/p' | head -1)"
    mkdir -p "$RALPH_SHIM_STATE/claude.lenses"
    printf '%s\n' "$lens" >>"$RALPH_SHIM_STATE/claude.lenses/$lens"
    printf '{"type":"system","subtype":"init","session_id":"lens","model":"test-model"}\n'
    printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"nothing to report. RALPH-LENS-VERDICT: pass"}],"usage":{"input_tokens":10,"cache_read_input_tokens":0,"output_tokens":5}}}\n'
    printf '{"type":"result","subtype":"success","is_error":false,"result":"RALPH-LENS-VERDICT: pass","num_turns":1,"total_cost_usd":0.001}\n'
    exit 0
    ;;
  # The retro subagent ([14]), answered the way the shipped prompt asks a session
  # with nothing to say to answer. Before the delivery case for the reason the lens
  # is: it must not take a number from the sequence counter below, which is about
  # *delivery* sessions — and it must not write the write-surface it can see in the
  # ticket it was handed, which is what the delivery branch would do with it.
  *RALPH-RETRO-NOTHING*)
    printf '{"type":"system","subtype":"init","session_id":"retro","model":"test-model"}\n'
    printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"nothing worth carrying. RALPH-RETRO-NOTHING"}],"usage":{"input_tokens":10,"cache_read_input_tokens":0,"output_tokens":5}}}\n'
    printf '{"type":"result","subtype":"success","is_error":false,"result":"RALPH-RETRO-NOTHING","num_turns":1,"total_cost_usd":0.001}\n'
    exit 0
    ;;
esac

n="$(cat "$RALPH_SHIM_STATE/canary-seq" 2>/dev/null || echo 0)"
n=$((n + 1))
printf '%s\n' "$n" >"$RALPH_SHIM_STATE/canary-seq"

# Read the way any sane reader would, carriage returns included: a session
# handed a CRLF ticket writes `src/beta.txt`, not `src/beta.txt\r`.
surface="$(printf '%s' "$prompt" |
  sed -n 's/^\*\*Write-surface:\*\* //p' | head -1 | tr -d '`\r' | tr ',' ' ')"
for target in $surface; do
  mkdir -p "$(dirname "$target")"
  printf 'written by the session\n' >"$target"
done

# And a build artefact in the zone the project keeps out of git, which is what
# any real session does — a compiler, a bundler, a test run. It is written here,
# inside the iteration's own worktree, and not seeded in the tree the run was
# started in: since [13] the two are different places, and only what an iteration
# puts in the zone is a zone this iteration's gate can name. Without it, the
# canary's three assertions about the unjudged zone were reading a run that had
# nothing ignored to look at, which is the shape of a false green.
mkdir -p .cache
printf 'built by the session\n' >".cache/build-$n"

echo '{"type":"system","subtype":"init","session_id":"s","model":"test-model"}'

case "$n" in
  1)
    # The plain case, plus enough volume to exercise reading a stream that is
    # still being appended to.
    i=0
    while [ $i -lt 200 ]; do
      printf '{"type":"user","message":{"content":[{"type":"tool_result","content":"line %s"}]}}\n' "$i"
      i=$((i + 1))
    done
    echo '{"type":"assistant","message":{"role":"assistant","usage":{"input_tokens":1200,"cache_creation_input_tokens":0,"cache_read_input_tokens":18000,"output_tokens":300}}}'
    ;;
  2)
    # An agent that commits its work — including, if nothing stops it, the
    # tracker in the middle of its own claim.
    git add -A >/dev/null 2>&1
    git commit -q -m "session: work on iteration 2" >/dev/null 2>&1
    echo '{"type":"assistant","message":{"role":"assistant","usage":{"input_tokens":900,"cache_read_input_tokens":9000,"output_tokens":100}}}'
    ;;
  *)
    # A usage event cut in half, with a pause: a monitor tick lands mid-write.
    printf '{"type":"assistant","message":{"role":"assistant","usage":{"input_tokens":50,"cache_read'
    sleep 0.3
    printf '_input_tokens":700,"output_tokens":25}}}\n'
    ;;
esac

echo '{"type":"result","subtype":"success","is_error":false,"result":"done","num_turns":4,"total_cost_usd":0.03,"usage":{"input_tokens":100,"output_tokens":10,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}'
FAKE
}

# The tracker as a real project hands it over: tickets saved with DOS line
# endings, a claim held by a run that is still alive, a claim left behind by a run
# that was killed, and a working tree that was already dirty when the run started.
#
# The two claims are both CRLF-encoded, and that pairing is the point. A liveness
# check that trips over a stray carriage return in `at=...Z\r` would read every
# claim as unparseable and reclaim both — including the live one. One ticket has
# to come back and the other has to be left alone, in the same run, over the same
# encoding.
seed_hostile_world() {
  use_tickets 01-alpha 02-beta 03-blocked 04-claimed

  stamp_claim 02-beta "pid:999999" "2026-07-25T08:00:00Z"

  perl -pi -e 's/\n/\r\n/' "$(ticket_file 02-beta)" "$(ticket_file 04-claimed)"
  harness__commit "test: a tracker written the DOS way"

  # A real project has a `.gitignore`, and this one had none for twenty-two
  # tickets — which is exactly how the dead zone of [24] stayed invisible in the
  # file whose job is to drive the world as it is. Every check in the pack is
  # built on a git tree object, so an ignore rule the project happens to write is
  # what decides how far any of them can see.
  #
  # The three entries [19] will provision are deliberately *not* here: the
  # assertion that the run undoes a session commit carrying the session stream
  # depends on that stream being visible to the session's own `git add -A`, and
  # changing that is [19]'s job, with its own assertions.
  #
  # Committed before the working tree is dirtied, and that order is load-bearing:
  # `harness__commit` is a `git add -A`, so seeding the ignore rule afterwards
  # would commit the very work in progress this function exists to leave
  # uncommitted. The canary caught that, which is the whole point of it.
  printf '.cache/\n' >>"$PROJECT_DIR/.gitignore"
  harness__commit "test: a project that keeps its build cache out of git"

  # And a real repository has a second ignore rule source, which nothing versions
  # and no ticket can declare: `.git/info/exclude`, where a human puts what is
  # local to their machine. It is the source [30] closed, and this is the direction
  # that matters here — the common case is not an attack ([31]). Three iterations
  # must be green *through* somebody else's local excludes, not in spite of them:
  # the pack pins the rules it was handed, so a rule that was already there costs
  # nothing, and the file behind it must still be standing at the end.
  printf 'scratchpad-of-mine/\n' >>"$PROJECT_DIR/.git/info/exclude"
  mkdir -p "$PROJECT_DIR/scratchpad-of-mine"
  printf 'a human keeps notes here\n' >"$PROJECT_DIR/scratchpad-of-mine/notes"

  # And a real project declares its own MCP servers. This one had none for
  # thirty-one tickets, which is how [31] stayed invisible here too: the file is
  # read by *every* spawn, its `command` is launched, and its tools reach the model
  # — so before the lens posture, every review session in this canary would have
  # been running the project's own commands. Committed, and no session writes it:
  # the point is that it is the project's, legitimately, and the judge must still
  # not load it.
  cat >"$PROJECT_DIR/.mcp.json" <<'MCP'
{ "mcpServers": { "projectserver": { "command": "sh", "args": ["-c", "true"] } } }
MCP
  harness__commit "test: a project that declares its own MCP servers"

  mkdir -p "$PROJECT_DIR/src" "$PROJECT_DIR/.cache"
  printf 'built before the run\n' >"$PROJECT_DIR/.cache/build"
  printf 'someone else was here\n' >"$PROJECT_DIR/wip.txt"
  printf '\nan edit nobody committed\n' >>"$PROJECT_DIR/CONTEXT.md"
}

@test "the canary: three iterations against a hostile world, all resolved" {
  seed_hostile_world
  script_honest_session

  before="$(git -C "$PROJECT_DIR" rev-parse HEAD)"

  run_loop
  assert_success
  assert_output_contains "frontier empty after 3 iterations"

  # Kept, because every `run` below overwrites $output. Two assertions here used
  # to read `grep -c`'s own output — "3" never contains "scope=red", so they could
  # not fail. A vacuous refutation in the file whose job is to catch false greens.
  loop_output="$output"

  # Every ticket the run could grind, ground — including the CRLF one, and
  # including the one that only became eligible when 01 resolved.
  assert_ticket_status 01-alpha resolved
  assert_ticket_status 02-beta resolved
  assert_ticket_status 03-blocked resolved

  # The claim of a run that is still alive was not touched; the claim of a run
  # that was killed came back to the frontier and was ground. Both read off a
  # CRLF ticket.
  assert_ticket_status 04-claimed claimed
  output="$loop_output"
  assert_output_contains "reclaimed 02-beta from an owner that is gone"
  refute_output_contains "reclaimed 04-claimed"

  # The work is really there, all three of it: an iteration must not be charged
  # with what the previous one left in the tree.
  assert_file_contains "$PROJECT_DIR/src/alpha.txt" "written by the session"
  assert_file_contains "$PROJECT_DIR/src/beta.txt" "written by the session"
  assert_file_contains "$PROJECT_DIR/src/gamma.txt" "written by the session"

  # Three green gates, no scope-guard casualty.
  run bash -c "grep -c 'scope=green' <<'OUT'
$loop_output
OUT"
  assert_equal "$output" "3"

  output="$loop_output"
  refute_output_contains "scope=red"
  refute_output_contains "gate-red"
  refute_output_contains "edited the tracker"

  # And on each of the three iterations, the run said out loud that this project
  # has a zone no check of the pack looked at. Three greens on a project with a
  # `.gitignore` are three greens with an asterisk, and the asterisk has to be
  # printed rather than remembered ([24]).
  run bash -c "grep -c 'nothing in this gate judged' <<'OUT'
$loop_output
OUT"
  assert_equal "$output" "3"

  # And the judgement tier really ran, three times, on the two lenses no ticket is
  # exempt from. Without this the `set_config LENSES` in setup would be decoration:
  # a tier the loop never reached looks exactly like a tier nobody switched on, and
  # the `refute gate-red` above would be passing for the wrong reason. The three
  # gated lenses stay out because these tickets carry no tag and this project
  # configures no sensitive or visible paths — five sessions an iteration is what a
  # predicate exists to prevent.
  assert_equal "$(lenses_that_ran)" "spec standards"
  assert_equal "$(lens_call_count standards)" "3"

  # And none of those six review sessions loaded the project's own MCP servers,
  # while the delivery sessions did ([31]). At the shipped default of LENSES, in a
  # project that declares its servers the way a real one does — which is the case
  # that made this a hole rather than an attack.
  run lens_call_mcp_loaded standards
  assert_equal "$output" ""
  run lens_call_mcp_loaded spec
  assert_equal "$output" ""
  run claude_call_mcp_loaded 1
  assert_output_contains ".mcp.json"

  # Iteration 2's session commits everything it can see. What the run added to
  # the project's history is its own commits and nothing else: not the session's
  # commit, and not one byte of the loop's state — the ticket frozen mid-claim at
  # `claimed`, the journal, a session stream of any size.
  run git -C "$PROJECT_DIR" log --format='%s' "$before..HEAD"
  assert_output_contains "02-beta: iteration delivered (gate green)"
  refute_output_contains "session: work on iteration 2"

  run git -C "$PROJECT_DIR" log --format='%s' --name-only "$before..HEAD" -- .scratch
  assert_equal "$output" ""
}

@test "the canary: the feature is played through before the run says it is done" {
  # The chain, end to end and in one run: frontier → three iterations → gate →
  # empty frontier → playthrough → exit success ([11] AC5). Every other test in
  # this file stops at "the tickets are resolved", which is exactly the claim the
  # value gate exists to distrust — three green gates say three diffs were sound,
  # and none of them says the feature does anything.
  seed_hostile_world
  script_honest_session

  before="$(git -C "$PROJECT_DIR" rev-parse HEAD)"

  run_loop
  assert_success
  loop_output="$output"
  assert_output_contains "frontier empty after 3 iterations"

  # One value gate, after the last iteration and before the exit — and the
  # project's own commands really ran, once each, which is the half no model is
  # asked about.
  assert_equal "$(playthrough_call_count)" "1"
  assert_equal "$(stub_call_count run)" "1"
  assert_equal "$(stub_call_count visual)" "1"

  # And the artefact is there, carrying the verdict the run closed on. Without
  # this file the run is not entitled to its exit code, which is the whole of the
  # acceptance criterion.
  assert_file_exists "$(playthrough_file)"
  assert_file_contains "$(playthrough_file)" "**Verdict:** pass"
  assert_file_contains "$(playthrough_file)" "the feature closes"
  assert_file_contains "$FEATURE_DIR/run.log" "playthrough-green"

  # It is **left in the working tree and not committed**, like the audit receipt
  # and the lesson index, and that is a property rather than an oversight: the
  # pack's durable commits are made inside an iteration, on the tree the gate
  # judged, and this document is written after the last iteration is gone. What
  # it costs is named where it lands — a human draining the sink afterwards is
  # told about it by `router_may_reinject`, which lists every path `HEAD` does
  # not carry and asks for it to be committed or put aside.
  run git -C "$PROJECT_DIR" status --porcelain --untracked-files=all -- docs/playthroughs
  assert_output_contains "docs/playthroughs/demo.md"
  run git -C "$PROJECT_DIR" log --format='%s' --name-only "$before..HEAD" -- docs
  assert_equal "$output" ""

  # And the session that wrote it had no way to: it is the loop that writes this
  # file, from tagged lines, and the model that answered them was spawned with the
  # read-only tool set the review lenses get.
  run playthrough_call_argv
  assert_output_contains "Read,Grep,Glob"

  output="$loop_output"
  refute_output_contains "the feature does not close"
}

@test "the canary: an overflow is not absolved by having already failed once" {
  # The hole this test was written for: with nothing putting the tree back after
  # a red gate, a second attempt on the same ticket started from a baseline that
  # already contained the overflow. Write the very same violation twice and the
  # scope-guard saw no change at all, and said green — ticket resolved, rogue
  # file still there, exit 0. A session could beat the guard by failing once.
  #
  # What closes it is the rollback: every attempt is judged against the same
  # baseline, because every failed attempt is undone before the next one starts.
  use_tickets 01-alpha
  set_config STERILE_K 3

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src
printf 'alpha\n' >src/alpha.txt
printf 'rogue\n' >src/rogue.txt
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_failure 4

  # Three attempts, three red scope-guards. Not two reds and a green.
  run bash -c "grep -c 'scope=red' <<'OUT'
$output
OUT"
  assert_equal "$output" "3"

  # Two fresh retries, then the human sink — and never a resolution.
  assert_ticket_status 01-alpha ready-for-human
  assert_equal "$(ticket_field 01-alpha Failures)" "3"
  run bash -c "grep -c resolved '$FEATURE_DIR/run.log' || true"
  assert_equal "$output" "0"

  # The tree the next run inherits carries nothing of the three attempts.
  refute_file_exists "$PROJECT_DIR/src/rogue.txt"
  refute_file_exists "$PROJECT_DIR/src/alpha.txt"
}

@test "the canary: a session cannot widen its own write-surface" {
  # The hole this test was written for. The scope-guard reads the write-surface
  # off the disk at gate time — after the session — and three mechanisms agreed
  # to hide what a session writes inside the tracker: the guard drops
  # `.scratch/<feature>/` as the loop's own bookkeeping ([05], rightly: the claim
  # and the journal live there), the rollback leaves the same prefix alone ([07],
  # rightly: otherwise the retry counter resets every attempt), and the
  # quarantine compares ids, so it saw a ticket created and not one edited.
  #
  # Reproduced, in this exact scenario: `scope=green`, ticket `resolved`, exit 0,
  # rogue file still in the tree and CONTEXT.md edited. A false green with a
  # mechanism, not a coincidence.
  #
  # What closes it is a tree object of `issues/` taken at spawn time: the edit is
  # restored from it before the gate reads a single field, so the guard measures
  # the contract the discovery wrote and not the one the session gave itself.
  use_tickets 01-alpha
  set_config STERILE_K 1

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src
printf 'written\n' >src/alpha.txt
printf 'written\n' >src/rogue.txt
printf 'written\n' >>CONTEXT.md
# The *real* tracker, by absolute path. Since [13] a session's working directory
# is a throwaway worktree, so `.scratch/demo/issues/...` reaches a committed copy
# nobody reads and nothing restores — the exploit would stage nothing, the guard
# would have nothing to put back, and this test would go green having proved that
# a session cannot reach the tracker *through a relative path*. A determined one
# finds the tree the run was started in; the mutation gate caught the difference.
perl -pi -e 's/^\*\*Write-surface:\*\* .*/**Write-surface:** `*`/' \
  "$(cat "$RALPH_SHIM_STATE/tracker-dir")/01-alpha.md"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_failure 4

  # Judged against the surface the ticket declared when the session started.
  assert_output_contains "scope=red"
  assert_output_contains "src/rogue.txt"

  # The edit itself is undone, and the iteration resolves nothing.
  assert_equal "$(ticket_field 01-alpha Write-surface)" '`src/alpha.txt`'
  assert_ticket_status 01-alpha ready-for-agent
  refute_file_exists "$PROJECT_DIR/src/rogue.txt"
}

@test "the canary: the journal tells the truth about the run" {
  seed_hostile_world
  script_honest_session

  run_loop
  assert_success

  journal="$FEATURE_DIR/run.log"
  # Five lines for three iterations: a ticket that changed hands because its
  # owner was gone is an event of the run too, and an operator reading this in
  # the morning has to see it without diffing the tracker — and the fifth is the
  # one event the tickets cannot carry at all ([11]), what the terminal value gate
  # decided when the frontier emptied.
  run bash -c "awk 'END { print NR }' '$journal'"
  assert_equal "$output" "5"

  run bash -c "grep -c 'playthrough-green' '$journal'"
  assert_equal "$output" "1"

  run bash -c "grep -c resolved '$journal'"
  assert_equal "$output" "3"

  run bash -c "grep -c 'reclaimed-retry' '$journal'"
  assert_equal "$output" "1"

  # Peak context is the whole window, cache included: 1200 + 18000 + 300.
  assert_file_contains "$journal" "tokens=19500"
  assert_file_contains "$journal" "turns=4"
}

@test "the canary: the run leaves nothing of its own behind" {
  seed_hostile_world
  script_honest_session

  run_loop
  assert_success
  # Kept before the first `run` below overwrites it. This file has shipped two
  # vacuous refutations by asserting on the output of a later `run`, and the
  # negative assertion at the bottom of this test is exactly that shape.
  loop_output="$output"

  run bash -c "ls -a '$FEATURE_DIR' | grep -E '\.session\.|\.tokens' || true"
  assert_equal "$output" ""
  [ ! -d "$(run_lock_dir)" ] || fail "the lock survived the run"

  # Six review-lens sessions ran during those three iterations, and the line above
  # is what says they left nothing here. Their prompt and their stream live in the
  # gate's temp directory, under TMPDIR, and that is on purpose: a lens whose stream
  # landed in the repository would be a judge writing into the tree it judges, which
  # is the one thing [06] had to make impossible. Counted, or the assertion above
  # would hold on a tier that never ran.
  assert_equal "$(lens_call_count standards)" "3"
  assert_equal "$(lens_call_count spec)" "3"

  # And it did not tidy up after anyone else: the work in progress that was
  # already in the tree is still exactly as it was — still uncommitted, too.
  # Iteration 2's session swept both into a commit of its own; undoing that is
  # part of leaving nothing behind, since a commit is harder to undo than a file.
  assert_file_contains "$PROJECT_DIR/wip.txt" "someone else was here"
  assert_file_contains "$PROJECT_DIR/CONTEXT.md" "an edit nobody committed"

  # Including the build cache the project keeps out of git: three green
  # iterations, and not one of them staged it, committed it or swept it. The
  # rollback's side of the same promise is asserted where a rollback actually runs
  # (`the rollback names the ignored paths it could not undo`, test/failures.bats);
  # what this line watches is that nothing on the *green* path ever starts
  # tidying the ignored zone — a `git clean` added anywhere in the loop would take
  # a project's `node_modules` down with it ([24]).
  assert_file_contains "$PROJECT_DIR/.cache/build" "built before the run"

  # And the other rule source, the one that lives in the git directory: the human's
  # local excludes are still what they were, the notes behind them are untouched,
  # and the run never once claimed somebody had moved the frontier ([30]). A pack
  # that put back rules it should have honoured, or reddened an iteration over a
  # rule that was already there, would fail here rather than in a project's
  # morning log.
  assert_file_contains "$PROJECT_DIR/.git/info/exclude" "scratchpad-of-mine/"
  assert_file_contains "$PROJECT_DIR/scratchpad-of-mine/notes" "a human keeps notes here"
  output="$loop_output"
  # The witness for the refutation below, and it is not decoration: a refutation
  # against an empty `$output` cannot fail, which is how two of them in this file
  # passed for months. This line proves the loop's output is what is being read.
  assert_output_contains "nothing in this gate judged"
  refute_output_contains "moved the ignore frontier"

  run git -C "$PROJECT_DIR" status --porcelain -- wip.txt CONTEXT.md
  assert_output_contains "?? wip.txt"
  assert_output_contains "CONTEXT.md"
}
