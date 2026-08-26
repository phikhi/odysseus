#!/usr/bin/env bats
#
# Passe transversale — probe 1.
#
# Question 5: what can a session write that nothing checks?
#
# [15] proved the operator's home is writable by the session being judged, and
# put a witness on the surfaces a fresh `claude` loads. This probe asks the same
# question with a different criterion: what does a session write in that home
# that changes what the *pack itself* does, not what a later session is.

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() { harness_setup; }
teardown() { harness_teardown; }

receipt_path() {
  printf '%s/receipts/%s/%s.md\n' "$PROJECT_DIR" "$RALPH_TEST_FEATURE" "$1"
}

@test "P1a a session that writes ~/.gitconfig runs its own code inside the run" {
  use_tickets 01-alpha

  script_claude <<'FAKE'
#!/usr/bin/env bash
surface="$(cat | sed -n 's/^\*\*Write-surface:\*\* //p' | head -1 | tr -d '`\r' | tr ',' ' ')"
for target in $surface; do
  mkdir -p "$(dirname "$target")" && printf 'written\n' >"$target"
done
mkdir -p "$HOME/hooks"
cat >"$HOME/hooks/post-commit" <<'HOOK'
#!/usr/bin/env bash
printf '%s\n' "$PWD" >>"$RALPH_SHIM_STATE/hook-fired"
HOOK
chmod +x "$HOME/hooks/post-commit"
printf '[core]\n\thooksPath = %s/hooks\n' "$HOME" >"$HOME/.gitconfig"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  echo "--- rc=$status ---"
  echo "$output"
  echo "--- hook-fired ---"
  cat "$SHIM_STATE/hook-fired" 2>/dev/null || echo "(never fired)"
  echo "--- receipt ---"
  cat "$(receipt_path 01-alpha)" 2>/dev/null || echo "(no receipt)"
  echo "--- run.log ---"
  cat "$FEATURE_DIR/run.log" 2>/dev/null || echo "(no run.log)"

  [ -f "$SHIM_STATE/hook-fired" ] || fail "the hook never ran — the probe did not reproduce"
}

@test "P1b garbage in ~/.gitconfig is enough to take the run down" {
  use_tickets 01-alpha

  script_claude <<'FAKE'
#!/usr/bin/env bash
surface="$(cat | sed -n 's/^\*\*Write-surface:\*\* //p' | head -1 | tr -d '`\r' | tr ',' ' ')"
for target in $surface; do
  mkdir -p "$(dirname "$target")" && printf 'written\n' >"$target"
done
printf 'this is not a git config file\n' >"$HOME/.gitconfig"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  echo "--- rc=$status ---"
  echo "$output"
  echo "--- ticket ---"
  ticket_status 01-alpha
  echo "--- receipt ---"
  cat "$(receipt_path 01-alpha)" 2>/dev/null || echo "(no receipt)"
}
