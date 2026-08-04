#!/usr/bin/env bats
#
# The review lens registry: which lenses answer which ticket, and what the gate
# does with what they wrote.
#
# The rest of the suite runs with `LENSES=none` — the harness injects that the way
# it injects a stub behind TEST_CMD, because a lens is a `claude` session and
# leaving the tier on would turn every "how many sessions did the loop spawn"
# assertion into an assertion about the fan. This file is where the tier is on, and
# test/canary.bats is where it runs at the value a project actually installs.
#
# Two things here are not about triggering at all, and they are the reason [06] was
# more than a table of predicates. A lens is a model with a bypassed permission
# mode running in the working tree of the session it is judging: what it writes is
# judged by nothing and undone by nothing ([29]). So the gate prevents the write
# (`--tools`), measures it (a tree object either side of the phase) and undoes it —
# and the tests for the middle one are the tests that matter, because prevention
# rests on a flag a release could stop honouring.

load helpers/harness
load helpers/assert

setup() {
  harness_setup
  set_config LENSES "$(config_default LENSES)"
}

teardown() {
  harness_teardown
}

# A ticket with a write-surface and, optionally, tags. Written straight into the
# tracker rather than added to test/fixtures/tickets: half the suite calls
# `use_tickets` with no arguments, and a new fixture would silently move the
# frontier of every one of those tests.
#
# Not committed on purpose, and it costs nothing: the pre-session snapshot is a
# tree of the working directory, untracked files included, so an uncommitted
# ticket is in the baseline — and the tracker is bookkeeping, which every diff in
# this pack drops anyway.
lens_ticket() {
  local id="$1" surface="$2" tags="${3:-}"
  {
    printf '# %s\n\n' "$id"
    printf '**What to build:** A ticket written by test/lenses.bats.\n\n'
    printf '**Blocked by:** None\n\n'
    printf '**Write-surface:** %s\n\n' "$surface"
    [ -z "$tags" ] || printf '**Tags:** %s\n\n' "$tags"
    printf '**Status:** ready-for-agent\n\n'
    printf -- '- [ ] The marker file exists.\n'
  } >"$TRACKER_DIR/$id.md"
}

# ── which lenses answer which ticket ─────────────────────────────────────────

@test "standards and spec answer every ticket, and a plain ticket gets nothing else" {
  # The AC in both directions at once. The positive half alone would pass on a
  # registry that ran all five lenses on everything, which is the failure mode a
  # predicate exists to prevent — five sessions per iteration instead of two.
  lens_ticket 01-plain 'src/plain.txt'
  session_writes

  run_loop
  assert_success
  assert_ticket_status 01-plain resolved
  assert_equal "$(lenses_that_ran)" "spec standards"
}

@test "a ticket tagged visible gets the fidelity and accessibility lenses" {
  lens_ticket 01-visible 'src/visible.txt' '`visible`'
  session_writes

  run_loop
  assert_success
  assert_equal "$(lenses_that_ran)" "accessibility fidelity spec standards"
}

@test "a write-surface meeting VISIBLE_PATHS is a visible surface too" {
  # The other half of the predicate: no tag at all, and a surface the project
  # declared as rendering something.
  set_config VISIBLE_PATHS 'src/ui/*'
  lens_ticket 01-ui 'src/ui/button.txt'
  session_writes

  run_loop
  assert_success
  assert_equal "$(lenses_that_ran)" "accessibility fidelity spec standards"
}

@test "a surface that only looks like a sensitive one does not trigger security" {
  # The refutation VISIBLE_PATHS and SECURITY_PATHS both need: a configured glob
  # that matches nothing in this ticket must leave the gated lens alone. Without
  # it, a predicate that returned 0 unconditionally would pass every test above.
  set_config SECURITY_PATHS 'src/auth/*'
  set_config VISIBLE_PATHS 'src/ui/*'
  lens_ticket 01-plain 'src/plain.txt'
  session_writes

  run_loop
  assert_success
  assert_equal "$(lenses_that_ran)" "spec standards"
}

@test "a config key naming several globs still meets a surface on any of them" {
  # The key is whitespace-separated, which is how a human writes a list of globs,
  # and [33] made every list inside the pack travel one entry per line: the
  # conversion happens here, in the one place the key is read. Without it the key
  # arrives as a single pattern with a space in it, matches nothing, and the gated
  # lens quietly stops firing — a green with one reviewer fewer and no line saying
  # so. The matching glob is the *second* one on purpose: a reader that only ever
  # honoured the first word would pass this test.
  set_config SECURITY_PATHS 'src/keys/* src/auth/*'
  lens_ticket 01-sensitive 'src/auth/token.txt'
  session_writes

  run_loop
  assert_success
  assert_equal "$(lens_call_count security)" "1"
}

@test "the security lens answers a tagged ticket, and a sensitive surface" {
  set_config SECURITY_PATHS 'src/auth/*'
  lens_ticket 01-tagged 'src/plain.txt' 'security, needs-care'
  lens_ticket 02-sensitive 'src/auth/token.txt'
  session_writes

  run_loop
  assert_success
  assert_ticket_status 01-tagged resolved
  assert_ticket_status 02-sensitive resolved

  # Twice: once per ticket. A predicate that fired on the tag and never on the
  # path would still show one call.
  assert_equal "$(lens_call_count security)" "2"
}

@test "a surface declaring the directory a sensitive glob is under still triggers" {
  # Both sides of the intersection are globs and neither is a path on disk, so
  # `src` against `src/auth/*` only matches one way round. The predicate tries
  # both, and errs towards running the lens — the only safe direction.
  set_config SECURITY_PATHS 'src/auth/*'
  lens_ticket 01-wide 'src'
  session_writes

  run_loop
  assert_success
  assert_equal "$(lens_call_count security)" "1"
}

@test "a session cannot switch its own reviewers off by editing its tags" {
  # The predicates read the ticket, so they inherit [21]: the tickets are put back
  # from the pre-session snapshot before the gate reads a single field. Without
  # that ordering, a session would only have to delete one line to lose a lens.
  set_config STERILE_K 1
  set_config SECURITY_PATHS 'src/auth/*'
  lens_ticket 01-tagged 'src/auth/token.txt' 'security'
  script_claude <<'FAKE'
#!/usr/bin/env bash
prompt="$(cat)"
case "$prompt" in
  *RALPH-LENS-VERDICT*)
    lens="$(printf '%s' "$prompt" | sed -n 's/^## The lens you are: \(.*\)$/\1/p' | head -1)"
    mkdir -p "$RALPH_SHIM_STATE/claude.lenses"
    printf '1\n' >>"$RALPH_SHIM_STATE/claude.lenses/$lens"
    printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"RALPH-LENS-VERDICT: pass"}],"usage":{"input_tokens":1,"output_tokens":1}}}\n'
    ;;
  *)
    mkdir -p src/auth && printf 'written\n' >src/auth/token.txt
    perl -pi -e 's/^\*\*Tags:\*\*.*$//' .scratch/demo/issues/01-tagged.md
    ;;
esac
printf '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.01}\n'
FAKE

  run_loop
  # The tracker write takes the green away on its own ([21]); what is being
  # asserted here is that the lens ran anyway, on the contract as it stood.
  assert_failure 4
  assert_equal "$(lens_call_count security)" "1"
}

# ── the registry is a registry ───────────────────────────────────────────────

@test "a lens the pack does not ship runs without the gate knowing about it" {
  # The extensibility AC, and it is asserted by adding one rather than by reading
  # the code: a name in LENSES plus two functions, and the fan picks it up.
  lens_ticket 01-plain 'src/plain.txt'
  set_config LENSES "standards perf"

  pack_run '
    lenses_want_perf() { return 0; }
    lenses_rubric_perf() { printf "**Perf.** Is anything obviously quadratic?\n"; }
    base="$(gate_tree_snapshot)"
    mkdir -p src && printf "written\n" >src/plain.txt
    gate_run 01-plain "$base" >/dev/null
    printf "verdicts=%s\n" "$RALPH_GATE_VERDICTS"'
  assert_success
  assert_output_contains "standards=green perf=green"
  assert_equal "$(lens_call_count perf)" "1"

  # And it was given its own rubric, not the standards one.
  run lens_call_stdin perf
  assert_output_contains "obviously quadratic"
}

@test "the gate's control flow names no lens" {
  # The other half of "adding a lens does not modify the gate". A registry the
  # gate reached into by name would pass every test above and still have to be
  # edited for the sixth lens. Comments are stripped: gate.sh explains the phase,
  # and documentation is not a dependency.
  run bash -c "grep -v '^[[:space:]]*#' '$RALPH_PACK_ROOT/.claude/lib/gate.sh' |
    grep -n -E 'standards|fidelity|accessibility|security'"
  assert_failure

  # And the check has teeth: the same grep does find the two entry points the gate
  # is allowed to know, so a glob that matched nothing would be visible here.
  run bash -c "grep -v '^[[:space:]]*#' '$RALPH_PACK_ROOT/.claude/lib/gate.sh' |
    grep -c -E 'lenses_triggered|lenses_review'"
  assert_success
  assert_equal "$output" "2"
}

@test "a lens named in LENSES that nothing can perform stops the run at the door" {
  # Not skipped, and not red on every iteration of the night: refused before the
  # lock is taken. A typo that quietly removed a reviewer would leave a gate
  # indistinguishable from one whose reviewers all passed.
  lens_ticket 01-plain 'src/plain.txt'
  set_config LENSES "standards spce"

  run_loop
  assert_failure 2
  assert_output_contains "LENSES names a lens this pack cannot run: spce"
  assert_equal "$(claude_call_count)" "0"
}

@test "LENSES switched off is said out loud, on every iteration" {
  # A zone nothing guards gets named every time round ([24]). A project is free to
  # turn the judgement tier off — and then its gate is green on its own tests and
  # on nothing else, which a human has to be able to read in the morning without
  # remembering which key was set.
  set_config LENSES none
  lens_ticket 01-plain 'src/plain.txt'
  session_writes

  run_loop
  assert_success
  assert_output_contains "01-plain: no review lens ran (LENSES is empty)"
  assert_equal "$(lenses_that_ran)" ""
}

# ── what a lens is judged on ─────────────────────────────────────────────────

@test "a lens reviews the tree the scope-guard judged, not one of its own" {
  # What [29] left this ticket. A lens that snapshotted the working tree from
  # inside its own branch would hand the model files the session never wrote — the
  # suite's artefacts — and ask for a verdict on them.
  lens_ticket 01-plain 'src/plain.txt'
  session_writes
  set_config TEST_CMD 'mkdir -p build; printf report >build/coverage.xml; exit 0'

  run_loop
  assert_success

  local prompt
  prompt="$(lens_call_stdin standards)"
  case "$prompt" in
    *src/plain.txt*) ;;
    *) fail "the lens was not shown the file the session wrote" ;;
  esac
  case "$prompt" in
    *build/coverage.xml*) fail "the lens was shown an artefact of the test suite" ;;
  esac
}

@test "a lens is handed the diff, not just the names of the files" {
  # It has no Bash, so it cannot run git: a file list alone would let it review
  # the state of the tree and never what changed in it.
  lens_ticket 01-plain 'src/plain.txt'
  session_writes

  run_loop
  assert_success
  run lens_call_stdin standards
  assert_output_contains "+written by the session"
  assert_output_contains "b/src/plain.txt"
}

@test "an iteration that changed nothing is red, and costs no lens session" {
  # The default fake writes nothing at all, which is a session that reported
  # success having delivered no ticket. Deterministic, so it is decided before a
  # model is spawned — one `claude` for the session, none for the lenses.
  set_config STERILE_K 1
  lens_ticket 01-plain 'src/plain.txt'

  run_loop
  assert_failure 4
  assert_ticket_status 01-plain ready-for-agent
  assert_output_contains "nothing to review"
  assert_equal "$(claude_call_count)" "1"
  assert_equal "$(lenses_that_ran)" ""
}

# ── the verdict ──────────────────────────────────────────────────────────────

@test "a red lens makes the gate red and the work is rolled back" {
  set_config STERILE_K 1
  lens_ticket 01-plain 'src/plain.txt'
  session_writes
  lens_verdict standards fail

  run_loop
  assert_failure 4
  assert_ticket_status 01-plain ready-for-agent
  assert_output_contains "standards=red"
  refute_file_exists "$PROJECT_DIR/src/plain.txt"
}

@test "a lens that reviewed and never said what it decided counts red" {
  # Silence is the shape a false green would take here: a session that crashed,
  # was killed for context, or simply answered prose is a lens that judged
  # nothing, and a branch that judged nothing has always counted red in this gate.
  set_config STERILE_K 1
  lens_ticket 01-plain 'src/plain.txt'
  session_writes
  lens_verdict spec silent

  run_loop
  assert_failure 4
  assert_output_contains "spec=red"
  assert_output_contains "ended without a RALPH-LENS-VERDICT line"
}

@test "the verdict is the last one in the stream, not the first" {
  # A model on its way to an answer quotes the instruction it was given, and a
  # diff under review can contain the token too — this repository's own does. The
  # first match must not decide, and neither must a match anywhere but the end.
  local stream="$RALPH_TEST_DIR/stream.jsonl"
  printf '%s\n' '{"text":"I will answer RALPH-LENS-VERDICT: pass or fail"}' >"$stream"
  printf '%s\n' '{"text":"RALPH-LENS-VERDICT: fail"}' >>"$stream"

  pack_run "printf 'verdict=%s\\n' \"\$(lenses__verdict $stream)\""
  assert_success
  assert_output_contains "verdict=fail"
}

@test "a verdict that is neither pass nor fail is not a pass" {
  # The two shapes of silence a lens can return, and neither is a green: a word
  # nobody defined, and no line at all.
  local stream="$RALPH_TEST_DIR/stream.jsonl"
  printf '%s\n' '{"text":"RALPH-LENS-VERDICT: probably"}' >"$stream"
  pack_run "printf 'one=%s\\n' \"\$(lenses__verdict $stream)\""
  assert_success
  assert_output_contains "one=none"

  : >"$stream"
  pack_run "printf 'two=%s\\n' \"\$(lenses__verdict $stream)\""
  assert_success
  assert_output_contains "two=none"
}

# ── the lens cannot write, and it is measured rather than asked ──────────────

@test "a lens is spawned without the tools that write" {
  lens_ticket 01-plain 'src/plain.txt'
  session_writes

  run_loop
  assert_success

  local argv
  argv="$(lens_call_argv standards)"
  case "$argv" in
    *--tools*) ;;
    *) fail "the lens was spawned without --tools: nothing removed the write tools" ;;
  esac
  case "$argv" in
    *Read,Grep,Glob*) ;;
    *) fail "the lens was not given the read-only tool set" ;;
  esac
  case "$argv" in
    *Edit* | *Write* | *Bash*) fail "the lens was handed a tool that writes" ;;
  esac

  # And the delivery session is not restricted: a `--tools` that had leaked onto
  # every spawn would pass every assertion above and stop the loop delivering
  # anything at all.
  run claude_call_argv 1
  refute_output_contains "--tools"
}

@test "a lens starts sterile of the tree it is judging, not merely tool-less" {
  # [31], and the case is a normal project rather than an attack: a project may
  # perfectly well commit a `.mcp.json` and a `.claude/settings.json` of its own.
  # No session wrote either, so the scope-guard is green and the lens phase runs —
  # and before this, every lens spawn launched the project's MCP server command and
  # ran its hooks. `--tools` never covered those: a hook is not a tool, and an MCP
  # tool is not built in.
  mkdir -p "$PROJECT_DIR/.claude"
  cat >"$PROJECT_DIR/.mcp.json" <<'MCP'
{ "mcpServers": { "projectserver": { "command": "sh", "args": ["-c", "true"] } } }
MCP
  cat >"$PROJECT_DIR/.claude/settings.json" <<'SETTINGS'
{ "hooks": { "PreToolUse": [ { "matcher": "Read",
  "hooks": [ { "type": "command", "command": "true" } ] } ] } }
SETTINGS
  harness__commit "fixture: the project has its own MCP servers and hooks"

  lens_ticket 01-plain 'src/plain.txt'
  session_writes

  run_loop
  assert_success
  assert_ticket_status 01-plain resolved

  # What the judge got from the judged tree: nothing.
  run lens_call_mcp_loaded standards
  assert_equal "$output" ""
  run lens_call_project_config standards
  assert_equal "$output" ""

  # The witness, and without it the two assertions above would pass in a project
  # that simply has no such files. The delivery session is not sterile — it is the
  # session doing the project's work, and a project that declares an MCP server
  # declares it for that.
  run claude_call_mcp_loaded 1
  assert_output_contains ".mcp.json"
  run claude_call_project_config 1
  assert_output_contains ".claude/settings.json"
}

@test "the tool set is not a config key a project can widen" {
  # A guarantee a key can empty is not a guarantee ([24]). Asserted against the
  # shipped example rather than by reading lenses.sh, which is where the constant
  # would move to if somebody made it configurable.
  run grep -c 'Read,Grep,Glob' "$PACK_DIR/ralph.config.sh.example"
  assert_equal "$output" "0"

  run bash -c "grep -n 'lenses_tools' '$RALPH_PACK_ROOT/.claude/lib/lenses.sh' |
    grep -v '^[0-9]*:#'"
  assert_success
  refute_output_contains '${'

  # The rest of the posture is the same kind of promise and takes the same rule
  # ([31]): a key that could put the project's settings or its MCP servers back in
  # a lens session would switch off what the flags were added for.
  run bash -c "grep -n 'strict-mcp-config\|setting-sources' \
    '$RALPH_PACK_ROOT/.claude/lib/lenses.sh' | grep -v '^[0-9]*:#'"
  assert_success
  refute_output_contains '${'
  run grep -c 'strict-mcp-config' "$PACK_DIR/ralph.config.sh.example"
  assert_equal "$output" "0"
}

@test "what a lens wrote in the tree it was judging is put back" {
  # The decision [06] had to take, and the half of it that is a guarantee. The
  # prevention above is a flag the binary honours today; this is two tree objects
  # and a diff, and it holds whatever the flag does.
  lens_ticket 01-plain 'src/plain.txt'
  session_writes
  lens_writes standards 'rogue/lens-wrote-this.txt'

  run_loop
  assert_success

  # Undone, not merely noticed.
  refute_file_exists "$PROJECT_DIR/rogue/lens-wrote-this.txt"
  assert_output_contains "a review lens changed 1 path(s) in the tree it was judging"

  # And the iteration is still green: the session did nothing wrong, and charging
  # it a retry for what its judge did is the mistake [29] found one layer up.
  assert_ticket_status 01-plain resolved
  assert_file_contains "$PROJECT_DIR/src/plain.txt" "written by the session"

  # The work the session did is committed, and what the lens wrote is not in the
  # commit either — the durable commit takes the judged tree, which predates both.
  run git -C "$PROJECT_DIR" log --oneline -- rogue/lens-wrote-this.txt
  assert_equal "$output" ""
}

@test "a lens overwriting the session's own work is put back to the judged state" {
  # The harder half: a path that is *in* the diff under review. Deleting it would
  # take the session's delivery with it, so it has to come back to what the gate
  # judged rather than to nothing.
  lens_ticket 01-plain 'src/plain.txt'
  session_writes
  lens_writes spec 'src/plain.txt'

  run_loop
  assert_success
  assert_ticket_status 01-plain resolved
  assert_file_contains "$PROJECT_DIR/src/plain.txt" "written by the session"
  refute_file_contains "$PROJECT_DIR/src/plain.txt" "written by the spec lens"
}

@test "a lens write that cannot be undone refuses to pass the iteration" {
  # The one case where reddening is right: the pack can no longer say what is in
  # the tree. Staged by taking the restore away rather than by contriving an
  # unwritable path — what is being asserted is the decision, not git's behaviour.
  pack_run '
    gate_restore_tree() { return 0; }
    pre="$(gate_tree_snapshot)"
    mkdir -p rogue && printf "left behind\n" >rogue/artefact.txt
    if gate__contain_lens_writes 01-plain "$pre"; then
      printf "verdict=green\n"
    else
      printf "verdict=red\n"
    fi'
  assert_success
  assert_output_contains "verdict=red"
  assert_output_contains "could not undo 1 path(s) a review lens wrote"
}

@test "a gate whose tree cannot be read before the lenses does not pass either" {
  # A judge that cannot see must not pass — the same refusal gate__scope_guard
  # makes, in the one place the containment could have been tempted to shrug.
  pack_run '
    if gate__contain_lens_writes 01-plain ""; then
      printf "verdict=green\n"
    else
      printf "verdict=red\n"
    fi'
  assert_success
  assert_output_contains "verdict=red"
  assert_output_contains "cannot say what they wrote"
}

@test "a gate whose lenses wrote nothing says nothing about it" {
  # The refutation the two zone lines of [24] and [29] each needed: a line printed
  # on every iteration is a line a human learns to skip, which is the same as not
  # printing it.
  lens_ticket 01-plain 'src/plain.txt'
  session_writes

  run_loop
  assert_success
  refute_output_contains "a review lens changed"
}

# ── the phase, and what it costs ─────────────────────────────────────────────

@test "the lenses do not run when the objective checks are already red" {
  # No verdict a lens could return changes a gate that is red, and a lens costs a
  # real session against the subscription. Skipped is not passed: nothing is added
  # to the verdicts, the same way an unconfigured type check is absent.
  set_config STERILE_K 1
  lens_ticket 01-plain 'src/plain.txt'
  session_writes
  stub_exit tests 1

  run_loop
  assert_failure 4
  assert_output_contains "the review lenses did not run: the objective checks are already red"
  assert_equal "$(lenses_that_ran)" ""
  refute_output_contains "standards=green"
}

@test "the lens phase has a deadline of its own" {
  # GATE_TIMEOUT is per phase since [06]. A lens that never returns is bounded by
  # the watchdog and by nothing else — the graceful stop deliberately has no delay
  # ([25]) — so this carries its own deadline: without the watchdog the run hangs
  # instead of failing an assertion.
  set_config STERILE_K 1
  set_config GATE_TIMEOUT 1
  lens_ticket 01-plain 'src/plain.txt'
  script_claude <<'FAKE'
#!/usr/bin/env bash
prompt="$(cat)"
case "$prompt" in
  *RALPH-LENS-VERDICT*)
    # One file per pid, never one shared marker: a plain ticket draws two lenses
    # and they run in parallel, so a single `lens-pid` would record whichever
    # branch wrote last and the assertion below would only ever check one of them.
    mkdir -p "$RALPH_SHIM_STATE/lens-pids"
    : >"$RALPH_SHIM_STATE/lens-pids/$$"
    # 120 and not 30: this sleep is load-bearing twice over. It has to outlast the
    # 60s this test gives the run to come back, or the mutation "06 a lens that
    # never returns is left to hang" stops hanging — the lens finishes on its own,
    # answers no verdict, the gate is red anyway and the test stays green against a
    # gate with no deadline at all. Shortened to 30 while delivering [28] and caught
    # by exactly that VACUOUS.
    sleep 120
    ;;
  *)
    mkdir -p src && printf 'written\n' >src/plain.txt
    ;;
esac
printf '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.01}\n'
FAKE

  local waited=0
  run_loop &
  local loop_pid=$!
  while kill -0 "$loop_pid" 2>/dev/null && [ "$waited" -lt 60 ]; do
    sleep 1
    waited=$((waited + 1))
  done
  if kill -0 "$loop_pid" 2>/dev/null; then
    kill -9 "$loop_pid" 2>/dev/null || true
    fail "the lens phase never came back: nothing bounds a lens that hangs"
  fi
  wait "$loop_pid" || true

  assert_ticket_status 01-plain ready-for-agent

  # And no `claude` outlives the run. This is the lens half of that promise, and it
  # is a different mechanism from the session's: a branch runs in a subshell, which
  # does not inherit the parent's traps, so a lens is never exposed to the window
  # `proc_collect` closes ([28]). What has to hold here is that the watchdog walks
  # *down* — a lens is a grandchild of the loop, so killing the branch alone would
  # leave a live session spending subscription quota with the run already gone.
  local pidfile lens_pid alive waited=0
  run bash -c "ls '$SHIM_STATE/lens-pids' 2>/dev/null | wc -l | tr -d ' '"
  [ "$output" != "0" ] || fail "no lens ever recorded its pid"

  # A killed grandchild is briefly a zombie until it is reparented and reaped, so
  # "gone" is given a moment rather than asserted on the instant the run returns.
  while [ "$waited" -lt 30 ]; do
    alive=""
    for pidfile in "$SHIM_STATE/lens-pids"/*; do
      lens_pid="$(basename "$pidfile")"
      if kill -0 "$lens_pid" 2>/dev/null; then alive="$alive $lens_pid"; fi
    done
    [ -n "$alive" ] || break
    sleep 0.1
    waited=$((waited + 1))
  done

  if [ -n "$alive" ]; then
    for lens_pid in $alive; do
      kill -9 "$lens_pid" 2>/dev/null || true
    done
    fail "a lens session outlived the run the watchdog stopped:$alive"
  fi
}
