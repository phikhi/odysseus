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

@test "loop.sh boots in the injected environment and exits clean" {
  use_tickets
  run_loop
  assert_success
  assert_output_contains "skeleton ok"
  assert_output_contains "feature=demo"
  assert_output_contains "backend=local"
}

@test "loop.sh sources every lib, and an empty lib/ is not an error" {
  run_loop
  assert_success

  cat >"$PACK_DIR/lib/zz-probe.sh" <<'PROBE'
: >"$RALPH_DIR/../lib-was-sourced"
PROBE
  run_loop
  assert_success
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
THRESH_5H THRESH_WEEK USAGE_UA ITER_CAP STERILE_K RETRY_N \
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
  set_config TRACKER_BACKEND github
  run_loop
  assert_success
  assert_output_contains "backend=github"
}
