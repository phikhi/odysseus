#!/usr/bin/env bats
#
# [46] part A: the witness of [15] on the iteration a run stops on.

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() { harness_setup; }
teardown() { harness_teardown; }

@test "Q1 the run that stops on a retried iteration now names the surface" {
  use_tickets 01-alpha
  set_config ITER_CAP 1
  set_config RETRY_N 2
  set_config STERILE_K 5
  stub_exit tests 1
  session_writes "src/alpha.txt" "$HOME/.claude/agents/backdoor.md"

  run_loop
  echo "=== rc=$status"
  echo "=== receipts"
  ls "$PROJECT_DIR/receipts/$RALPH_TEST_FEATURE" 2>/dev/null || echo "(none)"
  echo "=== run.log"
  cat "$FEATURE_DIR/run.log"
  echo "=== journal verify complaint?"
  printf '%s\n' "$output" | grep -i 'journal' || echo "(none)"
  false
}
