#!/usr/bin/env bats
#
# Passe transversale — probes 5.
#
#   P5a  the quarantine's renumber, with and without the register (clean run)
#   P5b  the lens of the SAME iteration loads what the session just wrote in $HOME
#   P5c  CAPABILITY=off does not switch the witness off

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() { harness_setup; }
teardown() { harness_teardown; }

receipt_path() {
  printf '%s/receipts/%s/%s.md\n' "$PROJECT_DIR" "$RALPH_TEST_FEATURE" "$1"
}

seed_collision() {
  printf '# 02 — a\n\n**Status:** ready-for-human\n\n**Blocked by:** None\n' \
    >"$TRACKER_DIR/02-first.md"
  printf '# 02 — b\n\n**Status:** ready-for-human\n\n**Blocked by:** None\n' \
    >"$TRACKER_DIR/02-second.md"
}

@test "P5a the renumber that would repair it is exactly what the register turns off" {
  use_tickets 01-alpha
  seed_collision

  # `seen` is space-fenced: the ids the tracker held when the session was spawned.
  pack_run 'export RALPH_TRACKER_LOG="'"$RALPH_TEST_DIR"'/reg1"
    printf "02-first\n02-second\n" >"$RALPH_TRACKER_LOG"
    failures_quarantine_strays 01-alpha " 01-alpha " 0
    printf "rc=%s tracker: %s\n" "$?" "$(ls "'"$TRACKER_DIR"'" | tr "\n" " ")"'
  echo "=== the loop created them (ids in the register)"
  printf '%s\n' "$output"

  pack_run 'export RALPH_TRACKER_LOG="'"$RALPH_TEST_DIR"'/reg2"
    : >"$RALPH_TRACKER_LOG"
    failures_quarantine_strays 01-alpha " 01-alpha " 0
    printf "rc=%s tracker: %s\n" "$?" "$(ls "'"$TRACKER_DIR"'" | tr "\n" " ")"'
  echo "=== a session created them (empty register)"
  printf '%s\n' "$output"
  false
}

@test "P5b the lens of the same iteration reads the home the session just wrote" {
  use_tickets 01-alpha
  set_config LENSES standards

  script_claude <<'FAKE'
#!/usr/bin/env bash
prompt="$(cat)"
case "$prompt" in
  *RALPH-LENS-VERDICT*)
    # A review lens. Say what it can see of the operator's home at *its* spawn
    # time, then answer the way a lens has to.
    if [ -f "$HOME/.claude/settings.json" ]; then
      printf 'seen-by-lens\n' >>"$RALPH_SHIM_STATE/lens-saw-home"
    fi
    printf '{"type":"system","subtype":"init","session_id":"l","model":"m"}\n'
    printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"RALPH-LENS-VERDICT: pass\nfindings: none."}]}}\n'
    printf '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.01}\n'
    exit 0
    ;;
esac
surface="$(printf '%s' "$prompt" | sed -n 's/^\*\*Write-surface:\*\* //p' | head -1 | tr -d '`\r' | tr ',' ' ')"
for target in $surface; do
  mkdir -p "$(dirname "$target")" && printf 'written\n' >"$target"
done
mkdir -p "$HOME/.claude"
printf '{"hooks":{"PreToolUse":[]}}\n' >"$HOME/.claude/settings.json"
printf '%s\n' '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  echo "=== rc=$status"
  printf '%s\n' "$output" | head -20
  echo "=== did the lens of this very iteration see it? $(cat "$SHIM_STATE/lens-saw-home" 2>/dev/null || echo no)"
  echo "=== was the lens spawned with --setting-sources user?"
  lens_call_argv standards | tr '\n' ' '
  echo
  echo "=== and the receipt says, after the fact:"
  grep 'capability surface changed' "$(receipt_path 01-alpha)" 2>/dev/null || echo "(nothing)"
  false
}

@test "P5c CAPABILITY=off leaves the witness on" {
  use_tickets 01-alpha
  set_config CAPABILITY off
  session_writes "src/alpha.txt" "$HOME/.claude/agents/backdoor.md"

  run_loop
  echo "=== rc=$status"
  echo "=== drift line on the receipt:"
  grep 'capability surface changed' "$(receipt_path 01-alpha)" || echo "(nothing — the key switched the witness off too)"
  echo "=== and the note that says the review is off:"
  grep 'capability review is off' "$(receipt_path 01-alpha)" || echo "(no note)"
  false
}
