#!/usr/bin/env bats
#
# [110] première mesure — `g4` de la passe du 16/10 rejouée après [108] : le
# programme lancé par git (un `core.fsmonitor` global posé par la session) a lu
# 3 lignes alors que plus aucune boucle ne donne sa liste en stdin. D'où ?
#
# L'espion note, à chaque appel : la commande git qui l'a lancé (`ps` sur $PPID),
# la nature de son fd 0 (`lsof -d 0`), et ce qu'il lit — ligne par ligne, préfixée
# du numéro d'appel.
#
#   bash test/run.sh .scratch/ralph-pack/sondes/ticket-110/s1-dou-viennent-les-trois-lignes.bats </dev/null
#
# Instrument, pas test : chaque cas finit sur un `false` volontaire.
load ../../../../test/helpers/harness
load ../../../../test/helpers/assert
setup() { harness_setup; }
teardown() { harness_teardown; }

prep() {
  use_tickets 01-alpha
  set_config STERILE_K 1
  set_config GUARDED_PATHS '.claude
assets
vendor'
  printf 'assets/\nvendor/\n' >>"$PROJECT_DIR/.gitignore"
  git -C "$PROJECT_DIR" add -A; git -C "$PROJECT_DIR" commit -q -m "test: ignore assets and vendor"
}

write_session() {
  cat >"$SHIM_STATE/fsmon-spy" <<SPY
#!/bin/sh
n=\$(( \$(cat "$SHIM_STATE/fsmon.calls" 2>/dev/null || echo 0) + 1 ))
printf '%s' "\$n" >"$SHIM_STATE/fsmon.calls"
{
  printf 'CALL %s parent=[%s]\n' "\$n" "\$(ps -o command= -p \$PPID | cut -c1-160)"
  printf 'CALL %s fd0=[%s]\n' "\$n" "\$(lsof -a -p \$\$ -d 0 -F tn 2>/dev/null | tr '\n' ' ')"
} >>"$SHIM_STATE/fsmon.log"
while IFS= read -r l; do printf 'CALL %s READ %s\n' "\$n" "\$l" >>"$SHIM_STATE/fsmon.log"; done
printf '/\0'
SPY
  chmod +x "$SHIM_STATE/fsmon-spy"
  cat >"$SHIM_STATE/claude.script" <<FAKE
#!/usr/bin/env bash
if [ ! -e "$SHIM_STATE/planted" ]; then
  : >"$SHIM_STATE/planted"
  git config --global core.fsmonitor "$SHIM_STATE/fsmon-spy"
fi
mkdir -p vendor
printf 'written by the session\n' >vendor/rogue
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE
  chmod +x "$SHIM_STATE/claude.script"
}

@test "S1 — where do the lines the launched program reads come from?" {
  prep
  write_session
  run_loop
  printf '=== rc=%s\n' "$status"
  printf '=== calls: %s\n' "$(cat "$SHIM_STATE/fsmon.calls" 2>/dev/null || echo 0)"
  printf '=== READ lines: %s\n' "$(grep -c ' READ ' "$SHIM_STATE/fsmon.log" 2>/dev/null || echo 0)"
  local named=NO
  case "$output" in *vendor/rogue*) named=YES ;; esac
  printf '=== vendor/rogue named? %s\n' "$named"
  printf '=== vendor/rogue survives? %s\n' "$([ -e "$PROJECT_DIR/vendor/rogue" ] && echo YES || echo no)"
  printf '=== calls that read something, with their parent and fd 0:\n'
  for c in $(grep ' READ ' "$SHIM_STATE/fsmon.log" | awk '{print $2}' | sort -u); do
    grep "^CALL $c " "$SHIM_STATE/fsmon.log" | sed 's/^/   /'
  done
  printf '=== fd0 kinds over all calls:\n'
  grep ' fd0=' "$SHIM_STATE/fsmon.log" | sed 's/.*fd0=\[//; s/n\/.*//; s/n[^ ]*//' | sort | uniq -c | sed 's/^/   /'
  cp "$SHIM_STATE/fsmon.log" "$BATS_RUN_TMPDIR/../s1-fsmon.log" 2>/dev/null || true
  set -e; false
}
