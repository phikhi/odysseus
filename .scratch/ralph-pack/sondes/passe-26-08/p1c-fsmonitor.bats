#!/usr/bin/env bats
#
# Passe transversale — probe 1c, tightened.
#
# `core.fsmonitor` in `$HOME/.gitconfig` is a *command*. The pack's own git
# invocations run it. Nothing in `capability_surfaces` watches that file.

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() { harness_setup; }
teardown() { harness_teardown; }

receipt_path() {
  printf '%s/receipts/%s/%s.md\n' "$PROJECT_DIR" "$RALPH_TEST_FEATURE" "$1"
}

@test "P1c fsmonitor fires, the run stays green, and nothing says a word" {
  use_tickets 01-alpha 02-beta
  mkdir -p "$HOME/hooks"
  cat >"$HOME/hooks/fsm" <<HOOK
#!/usr/bin/env bash
printf 'x\n' >>"$SHIM_STATE/fsmonitor-fired"
printf '%s\n' "\$PPID \$(ps -o comm= -p \$PPID 2>/dev/null)" >>"$SHIM_STATE/fsmonitor-parents"
exit 1
HOOK
  chmod +x "$HOME/hooks/fsm"

  script_claude <<'FAKE'
#!/usr/bin/env bash
surface="$(cat | sed -n 's/^\*\*Write-surface:\*\* //p' | head -1 | tr -d '`\r' | tr ',' ' ')"
for target in $surface; do
  mkdir -p "$(dirname "$target")" && printf 'written\n' >"$target"
done
printf '[core]\n\tfsmonitor = %s/hooks/fsm\n' "$HOME" >"$HOME/.gitconfig"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  echo "=== rc=$status"
  printf '%s\n' "$output" | grep -v '^ *[0-9]* [0-9]*$' | head -30
  echo "=== fsmonitor invocations: $(awk 'END{print NR+0}' "$SHIM_STATE/fsmonitor-fired" 2>/dev/null)"
  echo "=== distinct parents"
  sort -u "$SHIM_STATE/fsmonitor-parents" 2>/dev/null | head -10
  echo "=== 01-alpha=$(ticket_status 01-alpha) 02-beta=$(ticket_status 02-beta)"
  echo "=== does any receipt name .gitconfig or a drift?"
  grep -l 'gitconfig\|capability surface changed' "$PROJECT_DIR/receipts/$RALPH_TEST_FEATURE"/*.md 2>/dev/null || echo "(no receipt mentions it)"
  echo "=== run.log"
  cat "$FEATURE_DIR/run.log"
  echo "=== capability_surfaces, as the witness sees them"
  pack_run 'capability_surfaces'
  printf '%s\n' "$output"
  false
}
