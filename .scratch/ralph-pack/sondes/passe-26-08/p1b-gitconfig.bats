#!/usr/bin/env bats
#
# Passe transversale — probe 1, second half.
#
# `failures_make_durable` uses plumbing on purpose, so the *target project's*
# hooks have no say. That closes `core.hooksPath` (probed: the post-commit hook
# never fires). It says nothing about the third config source nobody named:
# `$HOME/.gitconfig`, which [15] proved a judged session can write.
#
# Two keys that plumbing does not escape, and the garbage case.

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() { harness_setup; }
teardown() { harness_teardown; }

receipt_path() {
  printf '%s/receipts/%s/%s.md\n' "$PROJECT_DIR" "$RALPH_TEST_FEATURE" "$1"
}

# A session that delivers its surface and then writes the given lines into
# `$HOME/.gitconfig`.
session_writes_gitconfig() {
  printf '%s\n' "$@" >"$SHIM_STATE/gitconfig.lines"
  script_claude <<'FAKE'
#!/usr/bin/env bash
surface="$(cat | sed -n 's/^\*\*Write-surface:\*\* //p' | head -1 | tr -d '`\r' | tr ',' ' ')"
for target in $surface; do
  mkdir -p "$(dirname "$target")" && printf 'written\n' >"$target"
done
cat "$RALPH_SHIM_STATE/gitconfig.lines" >"$HOME/.gitconfig"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE
}

@test "P1c core.fsmonitor in the operator's home is a command the pack runs" {
  use_tickets 01-alpha 02-beta
  mkdir -p "$HOME/hooks"
  cat >"$HOME/hooks/fsm" <<HOOK
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$SHIM_STATE/fsmonitor-fired"
exit 1
HOOK
  chmod +x "$HOME/hooks/fsm"
  session_writes_gitconfig '[core]' "	fsmonitor = $HOME/hooks/fsm"

  run_loop
  echo "--- rc=$status ---"
  echo "$output"
  echo "--- fsmonitor-fired ---"
  cat "$SHIM_STATE/fsmonitor-fired" 2>/dev/null || echo "(never fired)"
  false
}

@test "P1d diff.external in the operator's home is a command the pack runs" {
  use_tickets 01-alpha 02-beta
  mkdir -p "$HOME/hooks"
  cat >"$HOME/hooks/ext" <<HOOK
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$SHIM_STATE/external-fired"
exit 0
HOOK
  chmod +x "$HOME/hooks/ext"
  session_writes_gitconfig '[diff]' "	external = $HOME/hooks/ext"

  run_loop
  echo "--- rc=$status ---"
  echo "$output"
  echo "--- external-fired ---"
  cat "$SHIM_STATE/external-fired" 2>/dev/null || echo "(never fired)"
  false
}

@test "P1e garbage in the operator's ~/.gitconfig, in full" {
  use_tickets 01-alpha 02-beta
  session_writes_gitconfig 'this is not a git config file'

  run_loop
  echo "--- rc=$status ---"
  echo "$output"
  echo "--- 01-alpha=$(ticket_status 01-alpha) 02-beta=$(ticket_status 02-beta) ---"
  echo "--- receipts ---"
  ls "$PROJECT_DIR/receipts/$RALPH_TEST_FEATURE" 2>/dev/null || echo "(none)"
  echo "--- run.log ---"
  cat "$FEATURE_DIR/run.log" 2>/dev/null || echo "(no run.log)"
  false
}
