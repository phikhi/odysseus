#!/usr/bin/env bats
#
# The bridge between the fake `claude` and the real one.
#
# Every other file in this suite drives a shim. This one asks the question the
# shim cannot answer: is the interface the pack was built against the interface
# Claude Code actually offers? One set of assertions (helpers/claude-contract),
# two subjects — the fake on every run, the real binary when a human asks for it
# with RALPH_REAL_CLAUDE=1, because that one costs network and quota.
#
# The real run went red once already, before this file existed: the fake was
# emitting three event types where the real binary emits five, and eight keys on
# the result where the real one carries twenty-one. Nothing in the loop read the
# difference yet — the smart-zone net and the budget gate were about to.

load helpers/harness
load helpers/assert
load helpers/claude-contract

setup() {
  harness_setup
}

teardown() {
  harness_teardown
}

# ── the fake ─────────────────────────────────────────────────────────────────

@test "the fake stream honours the contract the loop depends on" {
  contract_prompt "$RALPH_TEST_DIR/prompt.txt" PONG-FAKE
  contract_spawn_fake "$RALPH_TEST_DIR/fake.jsonl" "$RALPH_TEST_DIR/prompt.txt"

  run contract_check "$RALPH_TEST_DIR/fake.jsonl" "$(contract_exit_code)" PONG-FAKE fake
  assert_success
}

@test "the stream under contract was produced by the pack, with the pack's flags" {
  # The contract is applied to a stream session_spawn produced, so the flags it
  # was produced with are the pack's own and cannot drift from them. Asserted
  # from the shim's record rather than from a list retyped here, which would go
  # on matching itself long after the pack changed.
  contract_prompt "$RALPH_TEST_DIR/prompt.txt" PONG-FLAGS
  contract_spawn_fake "$RALPH_TEST_DIR/fake.jsonl" "$RALPH_TEST_DIR/prompt.txt"

  run claude_call_argv 1
  assert_output_contains "-p"
  assert_output_contains "--output-format"
  assert_output_contains "stream-json"
  assert_output_contains "--verbose"
  assert_output_contains "--dangerously-skip-permissions"
  assert_output_contains "--model"
  refute_output_contains "--continue"
  refute_output_contains "--resume"

  run claude_call_env 1
  assert_output_contains "DISABLE_AUTO_COMPACT=1"
}

# ── the contract itself ──────────────────────────────────────────────────────

@test "the contract has teeth: each invariant, removed, is reported" {
  # Without this, a contract that quietly matched nothing — a renamed key, a grep
  # that stopped finding anything, a check that returned early — would read
  # exactly like a contract that holds. The specimen is the fake's own stream,
  # which the test above has just proved contract-clean, so every case differs
  # from a passing run by one edit and nothing else.
  #
  # Columns: what is broken, the exit code to report, the perl edit, the words
  # the finding has to contain. An edit that changes nothing is a finding of its
  # own: it means the case stopped testing anything.
  contract_prompt "$RALPH_TEST_DIR/prompt.txt" PONG-TEETH
  contract_spawn_fake "$RALPH_TEST_DIR/good.jsonl" "$RALPH_TEST_DIR/prompt.txt"

  local failures=0 label code edit expect stream
  while IFS='	' read -r label code edit expect; do
    [ -n "$label" ] || continue
    stream="$RALPH_TEST_DIR/broken.jsonl"
    cp "$RALPH_TEST_DIR/good.jsonl" "$stream"
    if [ "$edit" != "-" ]; then
      perl -0pi -e "$edit" "$stream"
      if diff -q "$RALPH_TEST_DIR/good.jsonl" "$stream" >/dev/null; then
        printf 'the edit for "%s" changed nothing: the case tests nothing\n' "$label"
        failures=$((failures + 1))
        continue
      fi
    fi

    run contract_check "$stream" "$code" PONG-TEETH
    if [ "$status" -eq 0 ]; then
      printf 'contract_check stayed green with "%s" broken\n' "$label"
      failures=$((failures + 1))
      continue
    fi
    case "$output" in
      *"$expect"*) ;;
      *)
        printf 'breaking "%s" was caught, but not said: expected "%s", got\n%s\n' \
          "$label" "$expect" "$output"
        failures=$((failures + 1))
        ;;
    esac
  done <<'CASES'
usage on the assistant events	0	s/"usage":\{"input_tokens":1000,"cache_creation_input_tokens"/"no_usage":{"input_tokens":1000,"cache_creation_input_tokens"/g	no assistant event carries usage
one of the four figures the monitor adds up	0	s/"cache_read_input_tokens":0,"cache_creation"/"cache_read_tokens":0,"cache_creation"/g	has no 'cache_read_input_tokens'
the assistant events themselves	0	s/^.*"type":"assistant".*\n//mg	no assistant event
the final result event	0	s/^.*"type":"result".*\n//m	the last event is not a result
num_turns on the result	0	s/"num_turns":\d+,//	nothing for 'num_turns'
modelUsage on the result	0	s/,"modelUsage":\{.*\}\}$/}/	no 'modelUsage'
the answer the prompt asked for	0	s/"result":"PONG-TEETH"/"result":"answering something else"/	did not reach the session
the rate_limit_event	0	s/^.*"type":"rate_limit_event".*\n//m	no rate_limit_event
a key of rate_limit_info	0	s/"rateLimitType"/"limitType"/	no 'rateLimitType'
the permission bypass	0	s/"permissionMode":"bypassPermissions"/"permissionMode":"default"/	no longer has the effect
the init event	0	s/^.*"subtype":"init".*\n//m	the first event is not system/init
a session that exited non-zero	3	-	the loop would count this iteration as failed
CASES

  [ "$failures" -eq 0 ] ||
    fail "$failures of the contract's invariants are not actually checked"
}

@test "two events sharing one line is caught" {
  # Kept apart from the table above because it needs a real JSON parser: a joined
  # pair still begins with { and ends with }, so no amount of shell can tell it
  # from one event. It matters all the same — the monitor reads this stream while
  # it is being written and counts one event per line.
  if ! command -v python3 >/dev/null 2>&1; then
    skip "no python3 to parse with"
  fi
  contract_prompt "$RALPH_TEST_DIR/prompt.txt" PONG-JOINED
  contract_spawn_fake "$RALPH_TEST_DIR/good.jsonl" "$RALPH_TEST_DIR/prompt.txt"

  before="$(awk 'END { print NR }' "$RALPH_TEST_DIR/good.jsonl")"
  perl -0pi -e 's/\}\n\{"type":"system","subtype":"thinking_tokens"/} {"type":"system","subtype":"thinking_tokens"/' \
    "$RALPH_TEST_DIR/good.jsonl"
  # The edit has to have joined a pair, or the case proves nothing.
  run bash -c "awk 'END { print NR }' '$RALPH_TEST_DIR/good.jsonl'"
  assert_equal "$output" "$((before - 1))"

  run contract_check "$RALPH_TEST_DIR/good.jsonl" 0 PONG-JOINED
  assert_failure
  assert_output_contains "does not parse"
}

@test "a broken contract says which side to repair" {
  # The same finding means opposite work depending on who produced the stream:
  # a field missing from the fake is a shim to re-capture, the same field missing
  # from the real binary is a pack reading something that no longer exists.
  # Without this line a reader gets a true statement and no next step.
  contract_prompt "$RALPH_TEST_DIR/prompt.txt" PONG-SIDE
  contract_spawn_fake "$RALPH_TEST_DIR/stream.jsonl" "$RALPH_TEST_DIR/prompt.txt"
  perl -0pi -e 's/"num_turns":\d+,//' "$RALPH_TEST_DIR/stream.jsonl"

  run contract_check "$RALPH_TEST_DIR/stream.jsonl" 0 PONG-SIDE fake
  assert_failure
  assert_output_contains "nothing for 'num_turns'"
  assert_output_contains "fix test/helpers/shims/claude"

  run contract_check "$RALPH_TEST_DIR/stream.jsonl" 0 PONG-SIDE real
  assert_failure
  assert_output_contains "fix the pack first"
}

@test "the fake earns its bypass: called without the flag it says default" {
  # The contract asserts that a session runs with permissions bypassed. On the
  # real binary that assertion is earned; on the fake it is only worth something
  # if the fake reports what it was actually called with. A shim that answered
  # bypassPermissions whatever it was given would make the check vacuous — and it
  # is the check that would notice the pack dropping the flag.
  run bash -c 'printf "x\n" | claude -p --output-format stream-json --verbose'
  assert_success
  assert_output_contains '"permissionMode":"default"'
  refute_output_contains '"permissionMode":"bypassPermissions"'
}

@test "the fake earns its tool set too: it reports what --tools asked for" {
  # The other half of [06]'s read-only promise. `--tools` removes the write tools
  # from the session rather than refusing them permission, which is the distinction
  # that matters when permissions are bypassed anyway — and init is where the
  # session says what it ended up with.
  contract_prompt "$RALPH_TEST_DIR/prompt.txt" PONG-TOOLS
  contract_spawn_fake "$RALPH_TEST_DIR/lens.jsonl" "$RALPH_TEST_DIR/prompt.txt" \
    --tools Read,Grep,Glob
  assert_equal "$(contract_init_tools "$RALPH_TEST_DIR/lens.jsonl")" "Read,Grep,Glob"

  # The refutation, and it is the whole value of the assertion above: a session
  # spawned without the flag really does have the tools that write. A fake that
  # answered an empty list whatever it was called with would make "the lens cannot
  # write" true of nothing.
  contract_spawn_fake "$RALPH_TEST_DIR/plain.jsonl" "$RALPH_TEST_DIR/prompt.txt"
  run contract_init_tools "$RALPH_TEST_DIR/plain.jsonl"
  assert_output_contains "Edit"
  assert_output_contains "Write"
  assert_output_contains "Bash"
}

# ── the hermetic promise ─────────────────────────────────────────────────────

@test "no test in this file reaches the real binary without asking" {
  # Read off the shipped file, not off a fixture: what must stay hermetic is
  # `test/run.sh` as anyone runs it.
  run contract_unguarded_real_spawns "$RALPH_PACK_ROOT/test/contract-claude.bats"
  assert_success
}

@test "the rule has teeth: an unguarded real spawn is caught" {
  # Spelled through a printf format so the token never appears whole in this
  # file: written out, the scan above would flag this very block. A copy, too —
  # the check must never need the repository edited to prove itself.
  planted="$RALPH_TEST_DIR/planted.bats"
  printf '@test "in a hurry" {\n  contract_spawn_%s "$out" "$prompt"\n}\n' real \
    >"$planted"

  run contract_unguarded_real_spawns "$planted"
  assert_failure
  assert_output_contains "without asking RALPH_REAL_CLAUDE first"
}

@test "an empty stream is a finding, not a pass" {
  # The one case that would make every other check unreachable: a session that
  # died before emitting anything. A contract that returned early on it would
  # report green for the worst possible outcome.
  : >"$RALPH_TEST_DIR/empty.jsonl"

  run contract_check "$RALPH_TEST_DIR/empty.jsonl" 0 PONG-NOBODY
  assert_failure
  assert_output_contains "the session wrote nothing"
}

# ── the real binary ──────────────────────────────────────────────────────────

@test "the real claude honours the same contract" {
  if [ "${RALPH_REAL_CLAUDE:-0}" != 1 ]; then
    skip "set RALPH_REAL_CLAUDE=1 to run this against the real binary (network + quota)"
  fi
  if ! contract_real_available; then
    skip "no claude binary on the developer's PATH"
  fi

  # A marker the model cannot have picked up anywhere else, so finding it in the
  # answer proves the prompt on stdin was received.
  contract_prompt "$RALPH_TEST_DIR/prompt.txt" PONG-8271
  contract_spawn_real "$RALPH_TEST_DIR/real.jsonl" "$RALPH_TEST_DIR/prompt.txt"

  run contract_check "$RALPH_TEST_DIR/real.jsonl" "$(contract_exit_code)" PONG-8271 real
  assert_success
}

@test "the real claude honours the read-only tool set a lens is given" {
  if [ "${RALPH_REAL_CLAUDE:-0}" != 1 ]; then
    skip "set RALPH_REAL_CLAUDE=1 to run this against the real binary (network + quota)"
  fi
  if ! contract_real_available; then
    skip "no claude binary on the developer's PATH"
  fi

  # The one assertion in this file that [06] cannot do without, and the only place
  # it can be made. Everything else about the read-only posture is argv — what the
  # pack *asked* for. This is what it got.
  #
  # If this goes red, the prevention half of [06] is gone and only the containment
  # half is left: the gate would still measure what a lens wrote and put it back,
  # but a lens would be free to write in the first place, and the trust-boundary
  # table needs its line changed the same day.
  contract_prompt "$RALPH_TEST_DIR/prompt.txt" PONG-4417
  contract_spawn_real "$RALPH_TEST_DIR/real-lens.jsonl" "$RALPH_TEST_DIR/prompt.txt" \
    --tools Read,Grep,Glob

  run contract_check "$RALPH_TEST_DIR/real-lens.jsonl" "$(contract_exit_code)" \
    PONG-4417 real
  assert_success

  local tools
  tools="$(contract_init_tools "$RALPH_TEST_DIR/real-lens.jsonl")"
  [ -n "$tools" ] || fail "the real binary reported no tool set at all"
  case ",$tools," in
    *,Edit,* | *,Write,* | *,Bash,* | *,NotebookEdit,* | *,Task,*)
      fail "the real binary kept a tool that writes despite --tools: $tools"
      ;;
  esac
}

@test "the fake and the real binary emit the same kinds of event" {
  if [ "${RALPH_REAL_CLAUDE:-0}" != 1 ]; then
    skip "set RALPH_REAL_CLAUDE=1 to run this against the real binary (network + quota)"
  fi
  if ! contract_real_available; then
    skip "no claude binary on the developer's PATH"
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    skip "no python3 to read the event kinds with"
  fi

  # The contract above covers the fields the pack reads. This covers the shape
  # around them: an event kind the real binary emits and the fake does not is a
  # feature waiting to be designed against a fiction, which is how [04] and [08]
  # nearly were. Sets, not sequences — the pack depends on the first event and on
  # the last, never on the order of what comes between.
  contract_prompt "$RALPH_TEST_DIR/prompt.txt" PONG-KINDS
  contract_spawn_real "$RALPH_TEST_DIR/real.jsonl" "$RALPH_TEST_DIR/prompt.txt"
  contract_spawn_fake "$RALPH_TEST_DIR/fake.jsonl" "$RALPH_TEST_DIR/prompt.txt"

  run python3 -c '
import json, sys

def kinds(path):
    found = set()
    for line in open(path):
        if not line.strip():
            continue
        event = json.loads(line)
        kind = event.get("type", "?")
        if event.get("subtype"):
            kind += "/" + event["subtype"]
        found.add(kind)
    return found

real, fake = kinds(sys.argv[1]), kinds(sys.argv[2])
for kind in sorted(real - fake):
    print("only the real binary emits %s: the fake has drifted" % kind)
for kind in sorted(fake - real):
    print("only the fake emits %s: it is inventing events" % kind)
sys.exit(1 if real != fake else 0)
' "$RALPH_TEST_DIR/real.jsonl" "$RALPH_TEST_DIR/fake.jsonl"
  assert_success
}
