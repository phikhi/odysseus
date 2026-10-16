#!/usr/bin/env bats
#
# Passe transversale du 16/10/2026 — matière (3) de [106]/[107] : le stdin des
# programmes que git lance pour le pack. `proc_git` ([104]) ferme 3..255 mais GARDE
# le stdin de l'appelant (il le doit : des appelants pipent dans git — `hash-object
# --stdin`, `update-index --index-info`). Un programme que git LANCE hors de sa
# configuration (`core.fsmonitor`, un hook configuré) hérite de ce même stdin. Dans
# une boucle `while IFS= read -r x; do proc_git <op d'index> …; done <<LIST`, ce
# stdin est le RESTE de LIST : le programme lancé par git peut le vider, et la
# boucle saute le reste. C'est le trou stdin de [106], pour git.
#
# Mesuré hors du pack (scratchpad/fsmon/probe2.sh) : un core.fsmonitor dans une
# boucle `git add -- path <<CHANGED` avale SENTINEL-line-b/c. Ici, dans un vrai run.
#
#   bash test/run.sh .scratch/ralph-pack/sondes/passe-16-10/g1-le-stdin-que-git-passe.bats </dev/null
#
# Instrument, pas test : chaque cas finit sur un `false` volontaire.
load ../../../../test/helpers/harness
load ../../../../test/helpers/assert
setup() { harness_setup; }
teardown() { harness_teardown; }

# La session écrit core.fsmonitor dans le ~/.gitconfig de l'opérateur (valeur
# qu'aucun unset du dépôt n'atteint, [104]). Le spy : note qu'il a tourné, vide son
# stdin ligne par ligne dans un fichier, et répond un token fsmonitor minimal.
plant_fsmonitor() {
  cat >"$SHIM_STATE/fsmon-spy" <<SPY
#!/bin/sh
printf 'ran from %s\n' "\$(ps -o command= -p \$PPID 2>/dev/null | cut -c1-40)" >>"$SHIM_STATE/fsmon.ran"
while IFS= read -r l; do printf '%s\n' "\$l" >>"$SHIM_STATE/fsmon.stdin"; done
printf '/\0'
SPY
  chmod +x "$SHIM_STATE/fsmon-spy"
  cat >"$SHIM_STATE/claude.script" <<FAKE
#!/usr/bin/env bash
prompt="\$(cat)"
if [ ! -e "$SHIM_STATE/planted" ]; then
  : >"$SHIM_STATE/planted"
  git config --global core.fsmonitor "$SHIM_STATE/fsmon-spy"
fi
# the session also writes a few out-of-surface files, so a gate index-build loop
# (<<CHANGED) has several entries whose tail a drained stdin would drop
for n in 1 2 3 4; do printf 'planted %s\n' "\$n" > "extra-\$n.txt"; done
chmod -x "$SHIM_STATE/claude.script"
printf '%s' "\$prompt" | claude "\$@"
status=\$?
chmod +x "$SHIM_STATE/claude.script"
exit \$status
FAKE
  chmod +x "$SHIM_STATE/claude.script"
}

report() {
  printf '=== rc=%s\n' "$status"
  printf '=== fsmonitor ran: %s times\n' "$(wc -l <"$SHIM_STATE/fsmon.ran" 2>/dev/null | tr -d ' ' || printf 0)"
  printf '=== who launched it:\n'; sort -u "$SHIM_STATE/fsmon.ran" 2>/dev/null | sed 's/^/   /'
  printf '=== lines it drained from git stdin: %s\n' "$(wc -l <"$SHIM_STATE/fsmon.stdin" 2>/dev/null | tr -d ' ' || printf 0)"
  printf '=== a sample of what it drained (first 20):\n'; head -20 "$SHIM_STATE/fsmon.stdin" 2>/dev/null | sed 's/^/   /'
}

@test "G1 — a session's core.fsmonitor drains the stdin of the pack's git during a real night" {
  use_tickets 01-alpha
  : >"$SHIM_STATE/fsmon.ran"; : >"$SHIM_STATE/fsmon.stdin"
  plant_fsmonitor
  run_loop
  report
  set -e; false
}
