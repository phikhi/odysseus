#!/usr/bin/env bats
#
# Passe transversale — probes 2.
#
#   P2a  the same fsmonitor, written to `.git/config` instead of `$HOME`
#   P2b  the [15] witness on an iteration that ends on a fresh retry
#   P2c  the same, when the run stops there

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() { harness_setup; }
teardown() { harness_teardown; }

receipt_path() {
  printf '%s/receipts/%s/%s.md\n' "$PROJECT_DIR" "$RALPH_TEST_FEATURE" "$1"
}

@test "P2a a session that writes .git/config gets the same command run for it" {
  use_tickets 01-alpha 02-beta
  mkdir -p "$HOME/hooks"
  cat >"$HOME/hooks/fsm" <<HOOK
#!/usr/bin/env bash
printf 'x\n' >>"$SHIM_STATE/fsmonitor-fired"
exit 1
HOOK
  chmod +x "$HOME/hooks/fsm"

  script_claude <<'FAKE'
#!/usr/bin/env bash
surface="$(cat | sed -n 's/^\*\*Write-surface:\*\* //p' | head -1 | tr -d '`\r' | tr ',' ' ')"
for target in $surface; do
  mkdir -p "$(dirname "$target")" && printf 'written\n' >"$target"
done
# The tree the run was started in, which a session finds through `git worktree
# list` and the harness hands over in one line.
root="$(cat "$RALPH_SHIM_STATE/project-dir")"
printf 'fsmonitor = %s/hooks/fsm\n' "$HOME" >>"$root/.git/config"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  echo "=== rc=$status"
  printf '%s\n' "$output" | head -25
  echo "=== fsmonitor invocations: $(awk 'END{print NR+0}' "$SHIM_STATE/fsmonitor-fired" 2>/dev/null)"
  echo "=== 01-alpha=$(ticket_status 01-alpha) 02-beta=$(ticket_status 02-beta)"
  echo "=== receipts that mention it"
  grep -l 'fsmonitor\|capability surface changed' "$PROJECT_DIR/receipts/$RALPH_TEST_FEATURE"/*.md 2>/dev/null || echo "(none)"
  false
}

@test "P2b a capability appearing on an iteration that is retried reaches no document" {
  use_tickets 01-alpha
  set_config RETRY_N 2
  set_config STERILE_K 5
  stub_exit tests 1
  session_writes "src/alpha.txt" "$HOME/.claude/agents/backdoor.md"

  run_loop
  echo "=== rc=$status"
  printf '%s\n' "$output" | head -40
  echo "=== receipts"
  ls "$PROJECT_DIR/receipts/$RALPH_TEST_FEATURE" 2>/dev/null || echo "(none)"
  echo "=== every receipt, grepped"
  grep -h 'capability surface changed' "$PROJECT_DIR/receipts/$RALPH_TEST_FEATURE"/*.md 2>/dev/null || echo "(no receipt names it)"
  echo "=== run.log"
  cat "$FEATURE_DIR/run.log"
  false
}

@test "P2c the run that stops on a retried iteration loses it altogether" {
  use_tickets 01-alpha
  set_config ITER_CAP 1
  set_config RETRY_N 2
  set_config STERILE_K 5
  stub_exit tests 1
  session_writes "src/alpha.txt" "$HOME/.claude/agents/backdoor.md"

  run_loop
  echo "=== rc=$status"
  printf '%s\n' "$output" | head -40
  echo "=== receipts"
  ls "$PROJECT_DIR/receipts/$RALPH_TEST_FEATURE" 2>/dev/null || echo "(none)"
  echo "=== run.log"
  cat "$FEATURE_DIR/run.log"
  echo "=== the backdoor is there:"
  ls -l "$HOME/.claude/agents/" 2>/dev/null
  false
}
