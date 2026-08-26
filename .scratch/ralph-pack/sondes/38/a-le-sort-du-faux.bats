#!/usr/bin/env bats
#
# [38] probe A — who kills the fake at ~1s when the reaper is gone.
#
# Runs the exact scenario of `a session that ignores the deadline's TERM is
# killed after the grace`, with monitor.sh mutated by hand to remove the reaper
# (the `23 a TERM nobody answers` mutation). The fake keeps a heartbeat and logs
# every catchable signal it receives, so a death shows up as a last heartbeat
# plus either a signal name or silence (KILL, or an exit nobody asked for).

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() { harness_setup; use_tickets 01-alpha 02-beta; }
teardown() { harness_teardown; }

@test "A the fake's fate with no reaper" {
  set_config SESSION_STALL_TIMEOUT 1
  set_config SESSION_KILL_GRACE 2
  set_config SESSION_TIMEOUT 0
  set_config STERILE_K 1

  script_claude <<'FAKE'
#!/usr/bin/env bash
log="$RALPH_SHIM_STATE/fake.log"
hb="$RALPH_SHIM_STATE/fake.hb"
for s in HUP INT QUIT ABRT PIPE ALRM USR1 USR2 XCPU; do
  trap "echo caught-$s >>'$log'" "$s"
done
trap '' TERM
trap 'echo "EXIT rc=$? i=$i $(date +%s)" >>"$log"' EXIT
echo "start pid=$$ ppid=$PPID $(date +%s)" >>"$log"
echo '{"type":"system","subtype":"init","session_id":"s"}'
i=0
while [ $i -lt 300 ]; do
  sleep 0.1
  i=$((i + 1))
  printf '%s %s\n' "$i" "$(date +%s)" >>"$hb"
done
echo "end $(date +%s)" >>"$log"
: >"$RALPH_SHIM_STATE/session-ran-to-the-end"
FAKE

  t0="$(date +%s)"
  bash "$PACK_DIR/loop.sh" >"$RALPH_TEST_DIR/loop.out" 2>&1 &
  PACK_BG_PID=$!

  wait_for_file "$FEATURE_DIR/run.log" 240 || echo "=== run.log never appeared"
  rc=0
  wait "$PACK_BG_PID" || rc=$?
  PACK_BG_PID=""
  t1="$(date +%s)"

  echo "=== rc=$rc elapsed=$((t1 - t0))s"
  echo "=== fake.log:"
  cat "$SHIM_STATE/fake.log" 2>/dev/null || echo "(none)"
  echo "=== heartbeats: $(wc -l <"$SHIM_STATE/fake.hb" 2>/dev/null || echo 0) last=$(tail -1 "$SHIM_STATE/fake.hb" 2>/dev/null || echo none)"
  echo "=== marker: $([ -e "$SHIM_STATE/session-ran-to-the-end" ] && echo PRESENT || echo absent)"
  echo "=== loop.out:"
  head -20 "$RALPH_TEST_DIR/loop.out"

  # Ten seconds after the run came back, is the fake still going?
  sleep 8
  echo "=== +10s last heartbeat: $(tail -1 "$SHIM_STATE/fake.hb" 2>/dev/null || echo none)"
  echo "=== +10s marker: $([ -e "$SHIM_STATE/session-ran-to-the-end" ] && echo PRESENT || echo absent)"
  echo "=== +10s fake.log:"
  cat "$SHIM_STATE/fake.log" 2>/dev/null || echo "(none)"
  false
}
