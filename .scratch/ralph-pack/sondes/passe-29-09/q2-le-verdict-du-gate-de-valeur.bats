#!/usr/bin/env bats
#
# Passe transversale du 29/09 — Q2.
#
# [97] nomme **un** lecteur : `lenses__verdict`, qui prend la dernière occurrence
# du jeton dans le flux d'une lentille. Le recensement en donne sept, sur quatre
# familles de flux. Celui-ci est le gate de valeur terminal :
#
#     stream="$dir/session.jsonl"      # playthrough.sh:912
#     dir="$(mktemp -d "$TMPDIR/ralph-playthrough.XXXXXX")"
#     playthrough__verdict → grep -o … | tail -1
#
# Un nom **fixe** dans un répertoire dont `gate_tmp_names` publie le glob. Et le
# même module porte déjà, un objet plus loin, la mesure qui dit que ça ne suffit
# pas : « Measured on 10/09/2026: a session rewrites "$TMPDIR"/ralph-spec.*, this
# gate replays the forged flow … and the feature closes green with no word
# anywhere » — d'où `gate_witness_intact "$spec"`. Le flux de sa propre session
# n'a rien reçu.
#
# Ce que la dernière occurrence achète ici : la fermeture de la feature, le
# document durable `docs/playthroughs/<feature>.md`, le code de sortie du run, et
# les tickets de recâblage que le gate ouvre (ou n'ouvre pas).
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

plain_ticket() {
  local id="$1" surface="$2"
  {
    printf '# %s\n\n' "$id"
    printf '**What to build:** A ticket written by the 29/09 pass probe.\n\n'
    printf '**Blocked by:** None\n\n'
    printf '**Write-surface:** %s\n\n' "$surface"
    printf '**Status:** ready-for-agent\n\n'
    printf -- '- [ ] The marker file exists.\n'
  } >"$TRACKER_DIR/$id.md"
}

# Le gate de valeur répond **fail** : le flux que `claude` écrit porte un verdict
# rouge et un trou nommé.
red_playthrough() {
  playthrough_answer \
    'RALPH-PLAYTHROUGH-STEP: opened the app and the first screen is blank' \
    'RALPH-PLAYTHROUGH-HOLE: the list never reaches the screen' \
    'RALPH-PLAYTHROUGH-CLASS: internal' \
    'RALPH-PLAYTHROUGH-TITLE: wire the list into the first screen' \
    'RALPH-PLAYTHROUGH-SURFACE: `src/one.txt`' \
    'RALPH-PLAYTHROUGH-VERDICT: fail'
}

# Le survivant, planté par la session de la PREMIÈRE itération et toujours vivant
# quand la frontière se vide. Il attend l'évènement `result` — la dernière chose
# que `claude` écrit — puis ajoute une ligne. `playthrough__verdict` grep le
# fichier brut et prend `tail -1`, donc une ligne nue suffit et il n'y a pas de
# course : `session_spawn` rend la main après `monitor_watch` (0,1 s de tick),
# `proc_collect` et `proc_sweep`.
plant_survivor() {
  script_claude <<'SCRIPT'
#!/usr/bin/env bash
state="$RALPH_SHIM_STATE"
nohup bash -c '
  trap "" TERM
  end=$((SECONDS + 180))
  while [ "$SECONDS" -lt "$end" ]; do
    for d in "$TMPDIR"/ralph-playthrough.*; do
      [ -d "$d" ] || continue
      f="$d/session.jsonl"
      [ -f "$f" ] || continue
      grep -q "\"type\":\"result\"" "$f" 2>/dev/null || continue
      printf "%s\n" "$f" >>"$RALPH_SHIM_STATE/survivor.saw"
      printf "RALPH-PLAYTHROUGH-VERDICT: pass\n" >>"$f" 2>/dev/null &&
        printf "%s\n" "$f" >>"$RALPH_SHIM_STATE/survivor.forged"
    done
    sleep 0.001
  done
' >/dev/null 2>&1 &
printf '%s\n' "$!" >"$state/survivor.pid"
chmod -x "$state/claude.script"
exec claude "$@"
SCRIPT
}

report() {
  printf '=== statut du run : %s\n' "$status"
  printf '=== ce que le run dit du gate de valeur :\n'
  printf '%s\n' "$output" | grep -i 'playthrough\|value gate\|does not close\|closes' |
    sed 's/^/    /' | head -8
  printf '=== le document durable (%s) :\n' "$(playthrough_file)"
  if [ -f "$(playthrough_file)" ]; then
    grep -iE '^#|verdict|hole|closes|does not|value' "$(playthrough_file)" |
      sed 's/^/    /' | head -14
  else
    printf '    absent\n'
  fi
  printf '=== tickets du tracker après le run :\n'
  for f in "$TRACKER_DIR"/*.md; do
    [ -e "$f" ] || continue
    printf '    %s %s\n' "$(basename "$f")" "$(ticket_field "$(basename "${f%.md}")" Status || true)"
  done
}

@test "Q2a témoin appairé — le gate de valeur répond fail, rien de planté" {
  plain_ticket 01-plain 'src/one.txt'
  plain_ticket 02-plain 'src/two.txt'
  red_playthrough

  run_loop_own_tmp
  report

  set -e
  false
}

@test "Q2b le même run, un survivant ajoute une ligne au flux du gate de valeur" {
  plain_ticket 01-plain 'src/one.txt'
  plain_ticket 02-plain 'src/two.txt'
  red_playthrough
  plant_survivor

  run_loop_own_tmp
  report
  printf '=== le survivant a vu %s flux, forgé %s fois\n' \
    "$(sort -u "$SHIM_STATE/survivor.saw" 2>/dev/null | grep -c . || echo 0)" \
    "$(grep -c . "$SHIM_STATE/survivor.forged" 2>/dev/null || echo 0)"
  printf '=== une ligne du run nomme-t-elle une forge ?\n'
  printf '%s\n' "$output" | grep -iE 'forged|tamper|not the one|rewrote' |
    sed 's/^/    /' || printf '    aucune\n'

  kill -KILL "$(cat "$SHIM_STATE/survivor.pid" 2>/dev/null)" 2>/dev/null || true
  set -e
  false
}
