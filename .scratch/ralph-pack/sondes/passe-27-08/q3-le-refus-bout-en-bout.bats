#!/usr/bin/env bats
#
# Passe transversale du 27/08 — angle 3 de [47].
#
# « Un appelant qui n'obtient pas le garde en 6 s REFUSE. Le chemin re-slice rend
# un split incomplet à un humain. Jamais sondé bout en bout. »
#
# Deux régimes : le garde tenu pour toute la nuit (aucun enfant créé) et le garde
# relâché en cours de split (un enfant sur deux). Le tenant est ici extérieur au
# run — ce que ça vaut quand c'est une session qui le pose est la sonde q2.
#
# Instrument, pas test : se termine par un `false` volontaire.

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() { harness_setup; }
teardown() {
  [ -n "${WEDGE_PID:-}" ] && kill "$WEDGE_PID" 2>/dev/null
  harness_teardown
}

# A session that crosses the soft limit on its first call and writes the split
# plan on its second — the shape test/failures.bats grinds, with a hook so a
# probe can run something at the moment the plan comes back.
script_reslice_world() {
  {
    cat <<'HEAD'
#!/usr/bin/env bash
prompt="$(cat)"
n="$(cat "$RALPH_SHIM_STATE/seq" 2>/dev/null || echo 0)"
n=$((n + 1)); printf '%s\n' "$n" >"$RALPH_SHIM_STATE/seq"
if [ "$n" = 1 ]; then
  echo '{"type":"system","subtype":"init","session_id":"s"}'
  echo '{"type":"assistant","message":{"role":"assistant","usage":{"input_tokens":10,"cache_read_input_tokens":9000,"output_tokens":5}}}'
  i=0
  while [ $i -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
  exit 0
fi
if [ "$n" = 2 ]; then
  plan="$(printf '%s' "$prompt" | sed -n 's/^Write the plan to \([^,]*\),.*/\1/p' | head -1)"
  cat >"$plan" <<'PLAN'
--- ticket: alpha-half | The alpha half ---
**What to build:** The first half of what was too big.

**Blocked by:** None

**Write-surface:** `src/alpha.txt`

**Status:** ready-for-agent

- [ ] the alpha half exists
--- ticket: eta-half | The eta half ---
**What to build:** The second half of what was too big.

**Blocked by:** None

**Write-surface:** `src/eta.txt`

**Status:** ready-for-agent

- [ ] the eta half exists
PLAN
  [ -x "$RALPH_SHIM_STATE/after-plan" ] && "$RALPH_SHIM_STATE/after-plan"
  echo '{"type":"result","subtype":"success","is_error":false,"num_turns":2,"total_cost_usd":0.01}'
  exit 0
fi
surface="$(printf '%s' "$prompt" |
  sed -n 's/^\*\*Write-surface:\*\* //p' | head -1 | tr -d '`\r' | tr ',' ' ')"
for target in $surface; do
  mkdir -p "$(dirname "$target")" && printf 'written\n' >"$target"
done
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":3,"total_cost_usd":0.02}'
HEAD
  } | script_claude
}

hold_guard() {
  local guard="$FEATURE_DIR/.open.guard"
  sleep 600 &
  WEDGE_PID=$!
  mkdir -p "$guard"
  printf '%s\n' "$WEDGE_PID" >"$guard/pid"
  printf '2026-08-27T00:00:00Z\n' >"$guard/since"
  printf 'someone else\n' >"$guard/note"
}

report() {
  echo "=== rc=$status"
  echo "=== 07-overlaps-alpha=$(ticket_status 07-overlaps-alpha) escalation=$(ticket_field 07-overlaps-alpha Escalation)"
  echo "=== tracker"
  ls "$TRACKER_DIR" | tr '\n' ' '
  echo
  echo "=== what a human reads on the parent"
  grep -A2 -i 're-slice\|incomplete' "$(ticket_file 07-overlaps-alpha)" || echo "(nothing on the ticket)"
  echo "=== run.log"
  cat "$FEATURE_DIR/run.log" 2>/dev/null || echo "(none)"
  echo "=== gaps and the guard, on stdout"
  printf '%s\n' "$output" | grep -i 'guard\|re-slice\|split\|could not create' || echo "(nothing)"
  echo "=== the receipt, whole"
  cat "$PROJECT_DIR/receipts/$RALPH_TEST_FEATURE"/*.md 2>/dev/null || echo "(no receipt)"
}

@test "Q3a the guard is held all night: the re-slice creates nothing" {
  use_tickets 07-overlaps-alpha
  set_config SOFT_LIMIT_TOKENS 5000
  set_config STERILE_K 5
  script_reslice_world
  hold_guard

  run_loop
  report
  false
}

@test "Q3b the guard frees mid-split: what an incomplete split hands over" {
  use_tickets 07-overlaps-alpha
  set_config SOFT_LIMIT_TOKENS 5000
  set_config STERILE_K 5
  script_reslice_world
  hold_guard

  # Released between the first child's refusal (~8s) and the second child's own
  # wait, so the split comes back with one piece of two.
  cat >"$SHIM_STATE/after-plan" <<EOF
#!/usr/bin/env bash
( sleep 11; rm -rf "$FEATURE_DIR/.open.guard" ) >/dev/null 2>&1 &
EOF
  chmod +x "$SHIM_STATE/after-plan"

  run_loop
  report
  false
}
