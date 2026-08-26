#!/usr/bin/env bats
#
# [38] probe C — the prediction: a stall above the spawn window ends the VACUOUS.
#
# Probe A showed the VACUOUS case is not a fake that dies: it is a fake that
# never runs. The shim records argv, then env, then the prompt on stdin, and
# only then `exec`s the scripted scenario — twenty-odd forks. This lists which
# of those artefacts exist after a run that came back in three seconds, so the
# death can be placed inside that preamble rather than guessed at.
#
# Run with the reaper mutation applied by hand:
#   perl -Mstrict -0pi -e 's/  monitor__reaper "\$pid" "\$grace" &\n  MONITOR_REAPER=\$!\n//' .claude/lib/monitor.sh

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() { harness_setup; use_tickets 01-alpha 02-beta; }
teardown() { harness_teardown; }

@test "C stall 3 instead of 1" {
  set_config SESSION_STALL_TIMEOUT 3
  set_config SESSION_KILL_GRACE 2
  set_config SESSION_TIMEOUT 0
  set_config STERILE_K 1

  script_claude <<'FAKE'
#!/usr/bin/env bash
trap '' TERM
: >"$RALPH_SHIM_STATE/scenario-entered"
echo '{"type":"system","subtype":"init","session_id":"s"}'
i=0
while [ $i -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
: >"$RALPH_SHIM_STATE/session-ran-to-the-end"
FAKE

  t0="$(date +%s)"
  bash "$PACK_DIR/loop.sh" >"$RALPH_TEST_DIR/loop.out" 2>&1 &
  PACK_BG_PID=$!
  wait_for_file "$FEATURE_DIR/run.log" 240 || echo "=== run.log never appeared"
  rc=0
  wait "$PACK_BG_PID" || rc=$?
  PACK_BG_PID=""

  echo "=== rc=$rc elapsed=$(($(date +%s) - t0))s"
  echo "=== scenario entered: $([ -e "$SHIM_STATE/scenario-entered" ] && echo YES || echo no)"
  echo "=== ran to the end: $([ -e "$SHIM_STATE/session-ran-to-the-end" ] && echo YES || echo no)"
  echo "=== the shim's slot, in the order the shim writes it (argv, env, stdin):"
  ls -1 "$SHIM_STATE/claude.calls/1" 2>/dev/null || echo "(no slot 1)"
  echo "=== the session stream:"
  wc -c "$FEATURE_DIR"/*.jsonl 2>/dev/null || echo "(none)"
  echo "=== loop.out:"
  head -12 "$RALPH_TEST_DIR/loop.out"
  false
}
