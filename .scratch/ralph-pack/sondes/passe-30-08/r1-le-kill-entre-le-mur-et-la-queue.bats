#!/usr/bin/env bats
#
# Passe transversale du 30/08 — angle (a) ouvert par [09].
#
# L'armement est en **queue de `loop_main`**, après le drainage. Entre la ligne
# qui annonce le mur et la ligne qui met en file, il y a un drainage qui dure
# aussi longtemps que la session la plus lente en vol. Qu'est-ce qu'un run tué
# dans cette fenêtre laisse à lire au matin ?
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

# A session that hangs around, so the drain is a window a test can aim at.
slow_session() {
  script_claude <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$$" >"$RALPH_SHIM_STATE/session.pid"
: >"$RALPH_SHIM_STATE/session.started"
exec sleep 90
FAKE
}

@test "R1a a run killed between the wall and the queue — what is left to read" {
  set +e
  use_tickets 01-alpha 02-beta
  set_config MAX_PARALLEL 2
  set_config USAGE_CACHE_TTL 0
  # All clear for the first ticket, then the weekly wall on the next question.
  usage_respond "$(sched_all_clear)" "$(sched_weekly_wall "$(sched_soon 200000)")"
  slow_session

  bash "$PACK_DIR/loop.sh" >"$RALPH_TEST_DIR/killed.out" 2>&1 &
  local pilot=$!
  wait_for_file "$SHIM_STATE/session.started" || { echo "no session ever started"; false; }

  # Wait for the wall to be *seen* — that is the line whose promise this probe is
  # about. Without this barrier the kill lands before the wall and the probe
  # measures nothing.
  local tries=200 saw=0
  while [ "$tries" -gt 0 ]; do
    if grep -q 'budget-wall' "$FEATURE_DIR/run.log" 2>/dev/null; then saw=1; break; fi
    tries=$((tries - 1)); sleep 0.05
  done
  echo "=== the wall was seen before the kill: $saw"

  kill -KILL "$pilot" 2>/dev/null || true
  wait "$pilot" 2>/dev/null || true
  kill -KILL "$(cat "$SHIM_STATE/session.pid" 2>/dev/null)" 2>/dev/null || true

  echo "=== at_call_count = $(at_call_count)"
  echo "=== marker present: $([ -f "$(sched_marker)" ] && echo yes || echo no)"
  echo "=== run.log"
  cat "$FEATURE_DIR/run.log" 2>/dev/null || echo "(none)"
  echo "=== the promise this run made on stdout, and never kept"
  grep -c 'a one-shot successor is armed at the reset' "$RALPH_TEST_DIR/killed.out" 2>/dev/null || echo 0
  echo "=== does anything in run.log say successor-armed or weekly-pause?"
  grep -c 'successor-armed\|weekly-pause' "$FEATURE_DIR/run.log" 2>/dev/null || echo 0
  echo "=== 01-alpha=$(ticket_status 01-alpha) 02-beta=$(ticket_status 02-beta)"
  set -e
  false
}

@test "R1b the paired witness: the same run, not killed" {
  set +e
  use_tickets 01-alpha 02-beta
  set_config MAX_PARALLEL 2
  set_config USAGE_CACHE_TTL 0
  usage_respond "$(sched_all_clear)" "$(sched_weekly_wall "$(sched_soon 200000)")"

  run_loop
  echo "=== rc=$status at_call_count=$(at_call_count)"
  echo "=== run.log"
  cat "$FEATURE_DIR/run.log" 2>/dev/null || echo "(none)"
  echo "=== marker: $(cat "$(sched_marker)" 2>/dev/null || echo '(none)')"
  set -e
  false
}

@test "R1c what a morning reader can tell apart, from run.log alone" {
  set +e
  # Three endings a human has to distinguish at 8am with the console long gone:
  # armed, deliberately not armed, and killed before either. The third is the
  # question — is there a line that says the wall was reached and nothing decided?
  use_tickets 01-alpha
  set_config USAGE_CACHE_TTL 0
  usage_respond "$(sched_weekly_wall "$(sched_soon 200000)")"
  run_loop
  echo "=== ARMED: journal lines"
  grep -o 'budget-wall\|successor-armed\|weekly-pause' "$FEATURE_DIR/run.log" | tr '\n' ' '
  echo

  harness_teardown; harness_setup
  use_tickets 01-alpha
  set_config USAGE_CACHE_TTL 0
  set_config WEEKLY_RESUME human
  usage_respond "$(sched_weekly_wall "$(sched_soon 200000)")"
  run_loop
  echo "=== NOT ARMED BY CHOICE: journal lines"
  grep -o 'budget-wall\|successor-armed\|weekly-pause' "$FEATURE_DIR/run.log" | tr '\n' ' '
  echo
  echo "(the killed case is R1a: read its run.log beside these two)"
  set -e
  false
}
