#!/usr/bin/env bats
#
# Passe transversale du 22/09 — Q3.
#
# La ligne « Ce qu'une session peut atteindre pendant qu'une autre itération est
# jugée » du tableau repose sur une prémisse, écrite en toutes lettres :
#
#     « Jusqu'ici aucune session n'était vivante pendant qu'un gate écrivait :
#       le gate tourne *après* la session qu'il juge, donc ses fichiers de
#       verdict dans `$TMPDIR` — un `.rc` par branche … — n'étaient à portée de
#       personne. Avec deux itérations en vol c'est faux. »
#
# Question : la prémisse est-elle vraie à `MAX_PARALLEL=1`, la valeur livrée ?
# `proc_kill_tree` existe et ne marche l'arbre de process que sur les deux
# chemins d'échéance (`monitor__reaper`, le chien de garde du gate). Une session
# qui **finit normalement** en laissant un process derrière elle n'est marchée
# par personne.
#
# Instrument, pas test : chaque cas finit par un `false` volontaire.

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() {
  harness_setup
}

teardown() {
  harness_teardown
}

plant_survivor() {
  script_claude <<'SCRIPT'
#!/usr/bin/env bash
# Une session qui laisse un process derrière elle, puis répond normalement.
state="$RALPH_SHIM_STATE"
nohup bash -c '
  end=$((SECONDS + 40))
  while [ "$SECONDS" -lt "$end" ]; do
    for d in "$TMPDIR"/ralph-gate.*; do
      [ -d "$d" ] || continue
      for f in "$d"/tests.rc "$d"/typecheck.rc "$d"/scope.rc "$d"/lang.rc; do
        [ -e "$f" ] && printf 0 >"$f"
      done
      printf "%s\n" "$d" >>"$RALPH_SHIM_STATE/survivor.saw"
    done
    sleep 0.01
  done
' >/dev/null 2>&1 &
printf '%s\n' "$!" >"$state/survivor.pid"
# Le reste de la session est la session par défaut du harnais.
chmod -x "$state/claude.script"
exec claude "$@"
SCRIPT
}

@test "Q3a témoin appairé — suite rouge, aucun survivant" {
  use_tickets 01-alpha
  stub_exit tests 1

  run_loop_own_tmp
  printf '=== statut : %s\n' "$status"
  printf '=== verdicts :\n'
  printf '%s\n' "$output" | grep -E 'tests=|scope=|escalat|red' | sed 's/^/    /' | head -10
  printf '=== statut du ticket : %s\n' "$(ticket_field 01-alpha Status || true)"

  set -e
  false
}

@test "Q3b la même suite rouge, avec un process laissé par la session" {
  use_tickets 01-alpha
  stub_exit tests 1
  plant_survivor

  run_loop_own_tmp
  printf '=== statut : %s\n' "$status"
  printf '=== verdicts :\n'
  printf '%s\n' "$output" | grep -E 'tests=|scope=|escalat|red|resolved' | sed 's/^/    /' | head -10
  printf '=== statut du ticket : %s\n' "$(ticket_field 01-alpha Status || true)"
  printf '=== le survivant a vu %s répertoire(s) de gate\n' \
    "$(sort -u "$SHIM_STATE/survivor.saw" 2>/dev/null | grep -c . || echo 0)"
  printf '=== une ligne du run nomme-t-elle le survivant ?\n'
  printf '%s\n' "$output" | grep -iE 'survivor|process|left behind' | sed 's/^/    /' || printf '    aucune\n'

  kill -KILL "$(cat "$SHIM_STATE/survivor.pid" 2>/dev/null)" 2>/dev/null || true

  set -e
  false
}

@test "Q3c le survivant est-il encore là quand le run a fini ?" {
  script_claude <<'SCRIPT'
#!/usr/bin/env bash
state="$RALPH_SHIM_STATE"
nohup sleep 120 >/dev/null 2>&1 &
printf '%s\n' "$!" >"$state/survivor.pid"
chmod -x "$state/claude.script"
exec claude "$@"
SCRIPT

  use_tickets 01-alpha
  run_loop_own_tmp
  printf '=== statut du run : %s\n' "$status"
  assert_ticket_status 01-alpha resolved

  local pid
  pid="$(cat "$SHIM_STATE/survivor.pid")"
  printf '=== le process laissé par la session (pid %s) est-il vivant ? %s\n' \
    "$pid" "$(kill -0 "$pid" 2>/dev/null && echo OUI || echo non)"
  printf '=== sa parenté maintenant :\n'
  ps -o pid=,ppid=,comm= -p "$pid" 2>/dev/null | sed 's/^/    /'
  printf '=== une ligne du run le nomme-t-elle ?\n'
  printf '%s\n' "$output" | grep -iE 'left|orphan|process' | sed 's/^/    /' || printf '    aucune\n'

  kill -KILL "$pid" 2>/dev/null || true
  set -e
  false
}
