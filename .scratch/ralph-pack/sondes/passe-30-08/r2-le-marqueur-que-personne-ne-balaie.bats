#!/usr/bin/env bats
#
# Passe transversale du 30/08 — angle (b) ouvert par [09].
#
# `<gitdir>/ralph.successor` n'est compté par aucun `*_leftovers`, et rien ne
# l'efface : « un successeur qui se réveille trouve son propre marqueur dans le
# passé et écrit par-dessus ». Trois questions que personne n'a posées : qui le
# voit quand le successeur ne se réveille jamais, ce qu'une session peut en
# faire, et **pour combien de temps**.
#
# Le tableau de confiance écrit l'exposition dans la direction prudente : « une
# session qui en forge un empêche l'armement, ce qui finit la nuit avec un
# humain ». Une nuit — au singulier. C'est ce singulier que ce fichier interroge.
#
# Instrument, pas test : chaque cas se termine par un `false` volontaire.

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() { harness_setup; }
teardown() { harness_teardown; }

sched_soon() { printf '%s\n' "$(($(date +%s) + ${1:-2}))"; }

sched_weekly_wall() {
  local reset="$1"
  printf '{"five_hour":{"utilization":0.10,"resets_at":%s},' "$(sched_soon 3600)"
  printf '"seven_day":{"utilization":0.85,"resets_at":%s},' "$reset"
  printf '"seven_day_opus":{"utilization":0.01,"resets_at":%s}}\n' "$reset"
}

sched_all_clear() {
  local reset
  reset="$(sched_soon 3600)"
  printf '{"five_hour":{"utilization":0.10,"resets_at":%s},' "$reset"
  printf '"seven_day":{"utilization":0.05,"resets_at":%s},' "$reset"
  printf '"seven_day_opus":{"utilization":0.01,"resets_at":%s}}\n' "$reset"
}

sched_marker() { printf '%s/.git/ralph.successor' "$PROJECT_DIR"; }

deliver_normally() {
  script_claude <<'FAKE'
#!/usr/bin/env bash
prompt="$(cat)"
surface="$(printf '%s' "$prompt" |
  sed -n 's/^\*\*Write-surface:\*\* //p' | head -1 | tr -d '`\r' | tr ',' ' ')"
for target in $surface; do
  mkdir -p "$(dirname "$target")" && printf 'written\n' >"$target"
done
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE
}

@test "R2a a marker left by a successor that never woke — who counts it" {
  set +e
  # Exactly what an `at` submission on a macOS box with `atrun` disabled leaves:
  # a marker in the past, and a queue entry that never ran.
  use_tickets 01-alpha
  printf '%s\tat\t2026-08-01T00:00:00Z\n' "$(($(date +%s) - 400000))" >"$(sched_marker)"
  deliver_normally

  run_loop
  echo "=== rc=$status 01-alpha=$(ticket_status 01-alpha)"
  echo "=== anything on stdout about the marker or a leftover?"
  printf '%s\n' "$output" | grep -i 'successor\|leftover\|still in\|earlier run' || echo "(nothing)"
  echo "=== run.log"
  cat "$FEATURE_DIR/run.log" 2>/dev/null || echo "(none)"
  echo "=== still there after a green run: $([ -f "$(sched_marker)" ] && echo yes || echo no)"
  echo "=== and what gate_leftovers actually says on this tree"
  pack_run 'gate_leftovers || echo "(nothing)"'
  printf '%s\n' "$output"
  set -e
  false
}

@test "R2b a session forges a marker — for how many nights" {
  set +e
  # The direction the trust table calls cautious. It calls it *a* night. This
  # asks how many: nothing removes the marker, and `scheduler_armed_at` only
  # ever compares its first field to `now`.
  use_tickets 01-alpha 02-beta
  set_config USAGE_CACHE_TTL 0
  printf '%s\tat\t2026-08-30T00:00:00Z\n' "$(($(date +%s) + 500000))" >"$(sched_marker)"
  usage_respond "$(sched_weekly_wall "$(sched_soon 200000)")"

  run_loop
  echo "=== night 1: rc=$status at_call_count=$(at_call_count)"
  printf '%s\n' "$output" | grep -i 'already armed' || echo "(no refusal line)"
  echo "--- run.log"
  grep -o 'budget-wall\|successor-armed\|weekly-pause' "$FEATURE_DIR/run.log" | tr '\n' ' '; echo

  # Second night, same tree, same forged marker. Nothing swept it.
  rm -rf "$SHIM_STATE/curl.slots" "$SHIM_STATE/claude.calls"
  usage_respond "$(sched_weekly_wall "$(sched_soon 200000)")"
  run_loop
  echo "=== night 2: rc=$status at_call_count=$(at_call_count)"
  printf '%s\n' "$output" | grep -i 'already armed' || echo "(no refusal line)"

  echo "=== the marker, unchanged, and how far out it says"
  cat "$(sched_marker)"
  echo "=== does any receipt or journal name why nothing was armed?"
  grep -rh 'already armed' "$PROJECT_DIR/receipts" "$FEATURE_DIR/run.log" 2>/dev/null || echo "(nowhere durable)"
  set -e
  false
}

@test "R2c can a session reach the marker from inside its worktree" {
  set +e
  # `.git/` is out of reach of a `git add -A`, an `rm -rf .scratch` and a
  # `git clean`. It is not out of reach of a session that asks git where the
  # common directory is — the same route q2 of the 27/08 pass used for the
  # ticket-open guard.
  use_tickets 01-alpha
  script_claude <<'FAKE'
#!/usr/bin/env bash
prompt="$(cat)"
common="$(git rev-parse --git-common-dir 2>/dev/null)"
case "$common" in /*) ;; *) common="$PWD/$common" ;; esac
printf '%s\tat\tforged\n' "$(( $(date +%s) + 500000 ))" >"$common/ralph.successor" 2>/dev/null
printf 'marker=%s\n' "$common/ralph.successor" >"$RALPH_SHIM_STATE/forged.where"
surface="$(printf '%s' "$prompt" |
  sed -n 's/^\*\*Write-surface:\*\* //p' | head -1 | tr -d '`\r' | tr ',' ' ')"
for target in $surface; do
  mkdir -p "$(dirname "$target")" && printf 'written\n' >"$target"
done
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  echo "=== rc=$status 01-alpha=$(ticket_status 01-alpha)"
  echo "=== where the session aimed: $(cat "$SHIM_STATE/forged.where" 2>/dev/null || echo '(it did not run)')"
  echo "=== did the scope-guard see anything?"
  printf '%s\n' "$output" | grep -i 'scope=\|overflow\|ignored path' || echo "(no scope line)"
  echo "=== marker in the main tree now:"
  cat "$(sched_marker)" 2>/dev/null || echo "(none)"
  echo "=== git status of the main tree"
  git -C "$PROJECT_DIR" status --porcelain --ignored=matching | head
  set -e
  false
}
