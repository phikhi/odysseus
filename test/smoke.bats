#!/usr/bin/env bats
#
# Smoke test of the foundation: the pack boots inside the fully injected
# environment, and every injection point the rest of the delivery relies on is
# actually wired. If this file is red, no other test can be trusted.

load helpers/harness
load helpers/assert

setup() {
  harness_setup
}

teardown() {
  harness_teardown
}

@test "loop.sh boots in the injected environment and says what it found" {
  run_loop
  # Exit 5: booted fine, but this tracker holds nothing to grind.
  assert_failure 5
  assert_output_contains "run start (feature=demo backend=local"
  assert_output_contains "nothing to grind"
}

@test "loop.sh sources every lib, and an empty lib/ is not an error" {
  run_loop
  assert_failure 5

  cat >"$PACK_DIR/lib/zz-probe.sh" <<'PROBE'
: >"$RALPH_DIR/../lib-was-sourced"
PROBE
  run_loop
  assert_failure 5
  assert_file_exists "$PROJECT_DIR/lib-was-sourced"
}

@test "loop.sh refuses to run without a config, with a usable message" {
  rm "$RALPH_CONFIG_FILE"
  run_loop
  assert_failure 2
  assert_output_contains "no config at"
  assert_output_contains "ralph.config.sh.example"
}

@test "the example config declares the whole configuration surface" {
  keys="FEATURE MODEL TEST_CMD TYPECHECK_CMD SOFT_LIMIT_TOKENS \
THRESH_5H THRESH_WEEK USAGE_UA ITER_CAP STERILE_K RETRY_N GATE_TIMEOUT \
HUMAN_CHECKPOINT_EVERY SCHEDULER WEEKLY_RESUME MAX_PARALLEL CLAIM_TTL \
TRACKER_BACKEND WAIT_CI VISUAL_CMD VISUAL_REAL_ASSETS RUN_CMD \
PLAYTHROUGH_REINJECT_MAX SECURITY_PATHS SECURITY_REFS FIDELITY_REFS \
LANG_INTERACT LANG_ARTIFACT LANG_CHECK LANG_CHECK_THRESHOLD \
LEARNINGS_INDEX_MAX RECEIPTS_RETENTION_DAYS"

  # env -i: the example must stand on its own, with nothing inherited.
  run env -i "$(command -v bash)" -c '
    set -u
    . "$1"
    for key in $2; do
      eval "seen=\${$key+set}"
      if [ "$seen" != set ]; then
        echo "undeclared key: $key"
        exit 1
      fi
    done
    echo "surface complete"
  ' _ "$PACK_DIR/ralph.config.sh.example" "$keys"
  assert_success
  assert_output_contains "surface complete"
}

@test "the headless posture turns auto-compact off" {
  assert_file_exists "$PACK_DIR/settings.json"
  assert_file_contains "$PACK_DIR/settings.json" '"autoCompactEnabled": false'
  assert_file_contains "$PACK_DIR/settings.json" '"DISABLE_AUTO_COMPACT"'
}

@test "the environment is hermetic: an exported config key does not leak in" {
  # Every key is written KEY="${KEY:-default}", so an exported value wins over
  # the file — and a developer with STERILE_K or SOFT_LIMIT_TOKENS in their
  # shell would silently be testing their shell instead of the pack.
  #
  # The keys probed here are the ones no test overwrites afterwards. MODEL and
  # DISABLE_AUTO_COMPACT cannot leak whatever the harness does — the config
  # assigns one unconditionally and the loop sets the other on the spawn — so
  # asserting on those two alone proved nothing.
  harness_teardown
  export MODEL=leaked-model
  export DISABLE_AUTO_COMPACT=leaked-value
  export ITER_CAP=1
  export SOFT_LIMIT_TOKENS=1
  harness_setup
  use_tickets 01-alpha 02-beta

  run_loop
  assert_success

  # A leaked ITER_CAP=1 would stop the run after one iteration; a leaked
  # SOFT_LIMIT_TOKENS=1 would terminate every session on its first event.
  assert_output_contains "frontier empty after 2 iterations"
  refute_output_contains "soft limit"
  assert_ticket_status 02-beta resolved

  run claude_call_argv 1
  refute_output_contains "leaked-model"

  run claude_call_env 1
  refute_output_contains "leaked-value"
  assert_output_contains "DISABLE_AUTO_COMPACT=1"
}

@test "node, npm and npx are shadowed: the pack stays bash-only" {
  # 99, not 127: a plain "command not found" would be indistinguishable from
  # the tool simply being absent, and it makes bats warn.
  run node --version
  assert_failure 99
  assert_output_contains "must not be required"

  run npm install
  assert_failure 99

  run npx create-anything
  assert_failure 99
}

@test "the tracker is a disposable tmpdir seeded with fixture tickets" {
  use_tickets

  case "$TRACKER_DIR" in
    "$RALPH_PACK_ROOT"/*) fail "tracker must not live in the repo: $TRACKER_DIR" ;;
  esac

  assert_ticket_status 01-alpha ready-for-agent
  assert_ticket_status 04-claimed claimed
  assert_ticket_status 06-resolved resolved
  assert_ticket_status 09-escalated ready-for-human
  assert_file_contains "$(ticket_file 03-blocked)" "**Blocked by:** 01"
  assert_file_exists "$FEATURE_DIR/spec.md"
  assert_file_exists "$PROJECT_DIR/CONTEXT.md"
}

@test "use_tickets can seed a single ticket" {
  use_tickets 01-alpha
  assert_ticket_status 01-alpha ready-for-agent
  refute_file_exists "$(ticket_file 02-beta)"
}

@test "the project is a git repo whose tree stays clean" {
  use_tickets
  set_config MAX_PARALLEL 2

  # A dirty tree would make the pre-spawn HEAD snapshot and the scope-guard
  # diff meaningless, so the harness must never leave one behind.
  run git -C "$PROJECT_DIR" status --porcelain
  assert_success
  assert_equal "$output" ""

  run git -C "$PROJECT_DIR" rev-parse HEAD
  assert_success

  run git -C "$PROJECT_DIR" ls-files
  assert_output_contains ".scratch/demo/issues/01-alpha.md"
  assert_output_contains ".claude/loop.sh"
}

@test "the claude shim records argv and prompt" {
  run bash -c 'printf "the ticket body\n" | claude -p --output-format stream-json --model test-model'
  assert_success
  assert_output_contains '"type":"result"'
  assert_output_contains '"subtype":"success"'

  assert_equal "$(claude_call_count)" "1"

  run claude_call_argv 1
  assert_output_contains "--output-format"
  assert_output_contains "stream-json"

  run claude_call_stdin 1
  assert_output_contains "the ticket body"
}

@test "the fake stream mirrors the real one, event for event" {
  run bash -c 'printf "x\n" | claude -p --model probe-model --output-format stream-json --verbose'
  assert_success

  # Sequence captured from claude 2.1.220. The smart-zone net watches this
  # stream and the budget gate reads rate_limit_event out of it, so an
  # invented stream would let both be designed against a fiction.
  assert_output_contains '"type":"system","subtype":"init"'
  assert_output_contains '"type":"rate_limit_event"'
  assert_output_contains '"rateLimitType":"five_hour"'
  assert_output_contains '"subtype":"thinking_tokens"'
  assert_output_contains '"type":"assistant"'
  assert_output_contains '"type":"result"'

  # init echoes back the model argument. The real one reports the model it
  # resolved instead — `--model haiku` comes back as claude-haiku-4-5-20251001 —
  # so this is one place the fake is deliberately not faithful. Nothing in the
  # pack reads the field; the contract only asks that it be there.
  assert_output_contains '"model":"probe-model"'

  # Keys on the final result that the loop reads today, or will.
  assert_output_contains '"num_turns"'
  assert_output_contains '"total_cost_usd"'
  assert_output_contains '"stop_reason"'
  assert_output_contains '"terminal_reason"'
  assert_output_contains '"api_error_status"'
  assert_output_contains '"permission_denials"'
}

@test "every line of the fake stream is valid JSON" {
  if ! command -v python3 >/dev/null 2>&1; then
    skip "no python3 to parse with"
  fi

  bash -c 'printf "x\n" | claude -p --output-format stream-json --verbose' \
    >"$RALPH_TEST_DIR/stream.jsonl"

  run python3 -c '
import json, sys
for i, line in enumerate(open(sys.argv[1]), 1):
    if line.strip():
        json.loads(line)
print("ndjson ok")
' "$RALPH_TEST_DIR/stream.jsonl"
  assert_success
  assert_output_contains "ndjson ok"
}

@test "the in-band rate limit signal is scriptable" {
  claude_rate_limit '{"status":"blocked","resetsAt":1784979600,"rateLimitType":"seven_day","isUsingOverage":false}'

  run bash -c 'printf "x\n" | claude -p'
  assert_success
  assert_output_contains '"status":"blocked"'
  assert_output_contains '"rateLimitType":"seven_day"'
}

@test "the claude shim is scriptable per scenario" {
  script_claude <<'FAKE'
#!/usr/bin/env bash
echo '{"type":"result","subtype":"error_during_execution","is_error":true,"session_id":"s"}'
exit 1
FAKE

  run bash -c 'echo prompt | claude -p'
  assert_failure 1
  assert_output_contains "error_during_execution"
  assert_equal "$(claude_call_count)" "1"
}

@test "TEST_CMD and TYPECHECK_CMD stubs have controllable exit codes" {
  run stub-cmd tests
  assert_success

  stub_exit tests 1
  run stub-cmd tests --watch
  assert_failure 1

  stub_exit typecheck 2
  run stub-cmd typecheck
  assert_failure 2

  assert_equal "$(stub_call_count tests)" "2"
  assert_equal "$(stub_call_count typecheck)" "1"
  assert_equal "$(stub_call_count lint)" "0"

  # And the config points the gate at them.
  assert_file_contains "$RALPH_CONFIG_FILE" "TEST_CMD='stub-cmd tests'"
  assert_file_contains "$RALPH_CONFIG_FILE" "TYPECHECK_CMD='stub-cmd typecheck'"
}

@test "the usage endpoint is injectable and records its User-Agent" {
  usage_respond '{"five_hour":{"utilization":0.42,"resets_at":"2026-07-25T12:00:00Z"},"seven_day":{"utilization":0.11,"resets_at":"2026-07-31T00:00:00Z"}}'

  run curl -s -H "User-Agent: claude-code/2.1.220" https://api.anthropic.com/api/oauth/usage
  assert_success
  assert_output_contains '"utilization":0.42'

  run curl_calls
  assert_output_contains "User-Agent: claude-code"
  assert_output_contains "/api/oauth/usage"

  usage_exit 7
  run curl -s https://api.anthropic.com/api/oauth/usage
  assert_failure 7
}

@test "the scheduler shim records the successor instead of arming one" {
  run bash -c 'echo "bash .claude/loop.sh" | at 04:00 2026-07-26'
  assert_success

  run at_calls
  assert_output_contains "argv: 04:00 2026-07-26"
  assert_output_contains "command: bash .claude/loop.sh"

  at_exit 1
  run bash -c 'echo noop | at now'
  assert_failure 1
}

@test "set_config overrides a key the pack then reads" {
  use_tickets 01-alpha
  set_config MODEL zzz-probe

  run_loop
  assert_success

  run claude_call_argv 1
  assert_output_contains "zzz-probe"
}

@test "the project template is keyed by names as well as contents" {
  # Hashing only the bytes made the key blind to a rename: moving a lib reused
  # the cached template and quietly tested the previous layout.
  # The new name has to keep its place in the sort, or the contents would be
  # concatenated in a different order and the key would change for the wrong
  # reason — which is exactly how this test first passed against the bug.
  before="$(harness__pack_fingerprint)"
  mv "$RALPH_PACK_ROOT/.claude/lib/select.sh" "$RALPH_PACK_ROOT/.claude/lib/selection.sh"
  after="$(harness__pack_fingerprint)"
  mv "$RALPH_PACK_ROOT/.claude/lib/selection.sh" "$RALPH_PACK_ROOT/.claude/lib/select.sh"

  [ "$before" != "$after" ] || fail "the fingerprint did not change: $before"
}
