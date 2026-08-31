#!/usr/bin/env bats
#
# [55] — la question de la frontière de confiance, posée une fois le pin livré.
#
# Le pin rend aux deux refus une entrée que la session routée ne peut pas
# fabriquer *sur le ticket que le drain tient*. Reste la question que le ticket
# ne pose pas : ce qu'une session routée peut écrire sur un **autre** ticket,
# c'est-à-dire hors de tout ce que ce drain a épinglé.
#
# Deux effets à mesurer, pas un :
#   - le drain relit `Status:` avant chaque ticket (`human_loop_main`), donc un
#     ticket qui ne dit plus `ready-for-human` est sauté en silence ;
#   - `resolved` est un état terminal du tracker : le ticket quitte aussi la
#     frontière AFK, sans qu'aucun gate n'ait rien vu.
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

drain() {
  run bash "$PACK_DIR/human-loop.sh"
}

mk_ticket() {
  local id="$1" file
  shift
  file="$TRACKER_DIR/$id.md"
  {
    printf '# %s — written by a sonde\n\n' "$id"
    printf '**What to build:** A fixture for the human sink.\n\n'
    while [ "$#" -ge 2 ]; do
      printf '**%s:** %s\n\n' "$1" "$2"
      shift 2
    done
    printf -- '- [ ] Something a human decides about.\n'
  } >"$file"
  harness__commit "sonde: $id"
}

mk_two() {
  mk_ticket 20-first Status ready-for-human Escalation failed-impl \
    'Write-surface' '`src/one.txt`' 'Blocked by' None
  mk_ticket 21-second Status ready-for-human Escalation failed-impl \
    'Write-surface' '`src/two.txt`' 'Blocked by' None
}

# ── S1 — la session routée résout le ticket d'à côté ──────────────────────────

@test "S1 une session routée écrit resolved sur le ticket suivant du puits" {
  mk_two

  script_claude <<'SCRIPT'
#!/usr/bin/env bash
tracker="$(cat "$RALPH_SHIM_STATE/tracker-dir")"
perl -pi -e 's/^\*\*Status:\*\* .*$/**Status:** resolved/' "$tracker/21-second.md"
exit 0
SCRIPT

  drain <<'ANSWERS'
o
n
n
ANSWERS

  printf '=== rc du drain          : %s\n' "$status"
  printf '=== Status 21-second     : %s\n' "$(ticket_status 21-second)"
  printf '=== 21-second offert ?   : %s\n' \
    "$(printf '%s\n' "$output" | grep -c -- '── 21-second ──')"
  printf '=== une ligne le nomme ? : %s\n' \
    "$(printf '%s\n' "$output" | grep -c '21-second')"
  printf '=== sortie du drain --------------------------------\n%s\n' "$output"

  set -e
  false
}

# ── S1b — le témoin appairé ───────────────────────────────────────────────────

@test "S1b le même drain, la même touche, sans l'édition de la session" {
  mk_two

  script_claude <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT

  drain <<'ANSWERS'
o
n
n
ANSWERS

  printf '=== rc du drain          : %s\n' "$status"
  printf '=== Status 21-second     : %s\n' "$(ticket_status 21-second)"
  printf '=== 21-second offert ?   : %s\n' \
    "$(printf '%s\n' "$output" | grep -c -- '── 21-second ──')"
  printf '=== sortie du drain --------------------------------\n%s\n' "$output"

  set -e
  false
}

# ── S1c — et ce que la frontière AFK en fait ──────────────────────────────────
#
# `resolved` n'est pas seulement « hors du puits » : c'est l'état d'un ticket
# livré. La question est de savoir si un run AFK lancé ensuite le reprend ou le
# considère comme fini.

@test "S1c un run AFK derrière ce drain reprend-il le ticket résolu par la session" {
  mk_two

  script_claude <<'SCRIPT'
#!/usr/bin/env bash
tracker="$(cat "$RALPH_SHIM_STATE/tracker-dir")"
perl -pi -e 's/^\*\*Status:\*\* .*$/**Status:** resolved/' "$tracker/21-second.md"
exit 0
SCRIPT

  drain <<'ANSWERS'
o
n
n
ANSWERS
  printf '=== Status 21-second après le drain : %s\n' "$(ticket_status 21-second)"

  script_claude <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
  run_loop
  printf '=== rc du run AFK                   : %s\n' "$status"
  printf '=== Status 21-second après le run   : %s\n' "$(ticket_status 21-second)"
  printf '=== sortie du run ----------------------------------\n%s\n' "$output"

  set -e
  false
}
