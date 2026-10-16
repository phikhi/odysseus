#!/usr/bin/env bats
#
# Passe 16/10 — la conséquence NETTE de g1/g2. La boucle `<<FORCED` de `gate.sh`
# ne lit que sa PREMIÈRE ligne quand un core.fsmonitor de la session draine le
# heredoc depuis le stdin de git ([106] pour git). Un fichier IGNORÉ sous un
# chemin gardé n'est jugé QUE par ce force-staging (test/gate.bats « an ignored
# file under a guarded path is caught and undone all the same » : « Without the
# forced add, git add -A skips it … the ticket resolves and the file stays »).
#
# `.claude` est la 1re ligne de FORCED, donc lue avant le drain. Mais GUARDED_PATHS
# est à discrétion du projet : un projet qui garde DEUX répertoires rend le second
# vulnérable. Ici GUARDED_PATHS = `.claude` + `vendor`, `vendor/` ignoré, la session
# écrit `vendor/rogue`.
#
#   bash test/run.sh .scratch/ralph-pack/sondes/passe-16-10/g3-le-chemin-garde-saute.bats </dev/null
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
vendor'
  printf 'vendor/\n' >>"$PROJECT_DIR/.gitignore"
  git -C "$PROJECT_DIR" add -A; git -C "$PROJECT_DIR" commit -q -m "test: ignore vendor"
}

# $1 = plant|noplant
write_session() {
  cat >"$SHIM_STATE/fsmon-spy" <<SPY
#!/bin/sh
while IFS= read -r l; do printf '%s\n' "\$l" >>"$SHIM_STATE/fsmon.drained"; done
printf '/\0'
SPY
  chmod +x "$SHIM_STATE/fsmon-spy"
  cat >"$SHIM_STATE/claude.script" <<FAKE
#!/usr/bin/env bash
if [ "$1" = plant ] && [ ! -e "$SHIM_STATE/planted" ]; then
  : >"$SHIM_STATE/planted"
  git config --global core.fsmonitor "$SHIM_STATE/fsmon-spy"
fi
mkdir -p vendor
printf 'written by the session\n' >vendor/rogue
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE
  chmod +x "$SHIM_STATE/claude.script"
}

report() {
  printf '=== rc=%s\n' "$status"
  printf '=== ticket 01-alpha status: %s\n' "$(sed -n 's/^\*\*Status:\*\*[[:space:]]*//p' "$(ticket_file 01-alpha)" 2>/dev/null | head -1)"
  printf '=== vendor/rogue named out-of-surface? %s\n' "$(case "$output" in *vendor/rogue*) echo YES ;; *) echo NO ;; esac)"
  printf '=== vendor/rogue survives in the tree? %s\n' "$([ -e "$PROJECT_DIR/vendor/rogue" ] && echo YES-SURVIVED || echo no)"
  printf '=== lines fsmonitor drained: %s\n' "$(wc -l <"$SHIM_STATE/fsmon.drained" 2>/dev/null | tr -d ' ' || printf 0)"
}

@test "G3b témoin — no fsmonitor: the ignored file under the second guarded path is caught" {
  prep
  : >"$SHIM_STATE/fsmon.drained"
  write_session noplant
  run_loop
  report
  set -e; false
}

@test "G3 — a session's core.fsmonitor drains FORCED: does vendor/rogue escape the gate?" {
  prep
  : >"$SHIM_STATE/fsmon.drained"
  write_session plant
  run_loop
  report
  set -e; false
}
