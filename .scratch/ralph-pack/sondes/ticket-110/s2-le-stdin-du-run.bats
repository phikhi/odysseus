#!/usr/bin/env bats
#
# [110] — ce que `proc_git` donne en fd 0 au programme que git lance, dans un vrai
# run, quand le run a un stdin (un terminal d'opérateur, le tuyau d'un lanceur).
# Ici un fichier fini de 40 lignes `RUN-STDIN-n` ; un `core.fsmonitor` global posé
# par la session les note. `S2` pour l'AFK (`loop.sh`), `S3` pour le drain
# (`human-loop.sh`) où le stdin est celui d'un humain qui répond.
#
#   bash test/run.sh .scratch/ralph-pack/sondes/ticket-110/s2-le-stdin-du-run.bats </dev/null
#
# Instrument, pas test : chaque cas finit sur un `false` volontaire.
load ../../../../test/helpers/harness
load ../../../../test/helpers/assert
setup() { harness_setup; }
teardown() { harness_teardown; }

plant() {
  cat >"$SHIM_STATE/fsmon-spy" <<SPY
#!/bin/sh
printf 'CALL %s\n' "\$(ps -o command= -p \$PPID | cut -c1-80)" >>"$SHIM_STATE/fsmon.log"
while IFS= read -r l; do printf 'READ %s\n' "\$l" >>"$SHIM_STATE/fsmon.log"; done
printf '/\0'
SPY
  chmod +x "$SHIM_STATE/fsmon-spy"
  cat >"$SHIM_STATE/claude.script" <<FAKE
#!/usr/bin/env bash
git config --global core.fsmonitor "$SHIM_STATE/fsmon-spy"
printf 'x\n' >written-by-session
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE
  chmod +x "$SHIM_STATE/claude.script"
  local i; for i in $(seq 1 40); do printf 'RUN-STDIN-%s\n' "$i"; done >"$SHIM_STATE/run.stdin"
}

report() {
  printf '=== rc=%s\n' "$status"
  printf '=== calls: %s\n' "$(grep -c '^CALL' "$SHIM_STATE/fsmon.log" 2>/dev/null || echo 0)"
  printf '=== RUN-STDIN lines read by the launched program: %s\n' "$(grep -c '^READ RUN-STDIN' "$SHIM_STATE/fsmon.log" 2>/dev/null || echo 0)"
  printf '=== other lines read: %s\n' "$(grep '^READ' "$SHIM_STATE/fsmon.log" 2>/dev/null | grep -vc 'RUN-STDIN' || true)"
  printf '=== git verbs that handed it RUN-STDIN:\n'
  awk '/^CALL/ { c = $0 } /^READ RUN-STDIN/ { print c }' "$SHIM_STATE/fsmon.log" 2>/dev/null | sort | uniq -c | sed 's/^/   /'
}

@test "S2 — AFK: a run with a stdin, a planted core.fsmonitor" {
  use_tickets 01-alpha
  plant
  run bash "$PACK_DIR/loop.sh" <"$SHIM_STATE/run.stdin"
  report
  set -e; false
}

@test "S3 — the drain: a human's answers on stdin, a core.fsmonitor already in ~/.gitconfig" {
  local id
  for id in 20-one 21-two; do
    {
      printf '# %s — sonde [110]\n\n**What to build:** A fixture for the human sink.\n\n' "$id"
      printf '**Status:** ready-for-human\n\n**Escalation:** failed-impl\n\n'
      printf '**Write-surface:** `src/%s.txt`\n\n**Blocked by:** None\n\n- [ ] Decide.\n' "$id"
    } >"$TRACKER_DIR/$id.md"
  done
  harness__commit "sonde: two tickets at the sink"
  plant
  git config --global core.fsmonitor "$SHIM_STATE/fsmon-spy"
  printf 'n\nn\nRUN-STDIN-after-the-answers\n' >"$SHIM_STATE/answers"
  run bash "$PACK_DIR/human-loop.sh" <"$SHIM_STATE/answers"
  printf '=== rc=%s\n' "$status"
  printf '=== calls: %s\n' "$(grep -c '^CALL' "$SHIM_STATE/fsmon.log" 2>/dev/null || echo 0)"
  printf '=== lines of the human read by the launched program: %s\n' "$(grep -c '^READ' "$SHIM_STATE/fsmon.log" 2>/dev/null || echo 0)"
  grep '^READ' "$SHIM_STATE/fsmon.log" 2>/dev/null | sed 's/^/   /'
  awk '/^CALL/ { c = $0 } /^READ/ { print c }' "$SHIM_STATE/fsmon.log" 2>/dev/null | sort | uniq -c | sed 's/^/   /'
  printf '=== drain output (tail):\n'
  printf '%s\n' "$output" | tail -8 | sed 's/^/   /'
  set -e; false
}
