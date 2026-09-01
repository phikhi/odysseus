#!/usr/bin/env bats
#
# Passe transversale du 01/09 — Q8, le résidu que [56] a nommé lui-même :
# « Ça couvre le chemin `r` et rien d'autre : un humain qui quitte le drain et
#   lance un run à la main lit toujours un vert que personne ne nomme. »
#
# La sonde `p3` du 31/08 est **périmée** depuis [56] : elle réinjectait, et le
# refus d'arbre sale tombe désormais dessus (mesuré au rejeu du 01/09 —
# `rc du drain : 3`, `rc du run AFK : 5`, la question ne se pose plus). Le seul
# ordre qui existe encore est celui-ci : la session routée réécrit la config,
# l'humain tape `q`, et le run suivant tourne sur un autre ticket.
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

@test "Q8a la session routée éteint le gate, l'humain quitte, le run suivant est vert" {
  mk_ticket 20-first Status ready-for-human Escalation failed-impl \
    'Write-surface' '`src/one.txt`' 'Blocked by' None
  mk_ticket 22-agent Status ready-for-agent \
    'Write-surface' '`src/two.txt`' 'Blocked by' None
  set_config TEST_CMD 'false'

  script_claude <<'SCRIPT'
#!/usr/bin/env bash
root="$(cat "$RALPH_SHIM_STATE/project-dir")"
printf "TEST_CMD='true'\n" >>"$root/.claude/ralph.config.sh"
exit 0
SCRIPT

  drain <<'ANSWERS'
o
q
ANSWERS
  printf '=== rc du drain                   : %s\n' "$status"
  printf '=== le drain nomme-t-il la config ?: %s\n' \
    "$(printf '%s\n' "$output" | grep -c 'ralph.config.sh')"
  printf '=== git status --porcelain        :\n%s\n' \
    "$(git -C "$PROJECT_DIR" status --porcelain)"

  rm -f "$SHIM_STATE/claude.script"
  run_loop
  printf '=== rc du run AFK                 : %s\n' "$status"
  printf '=== Status 22-agent               : %s\n' "$(ticket_status 22-agent)"
  printf '=== le run nomme-t-il la config ? : %s\n' \
    "$(printf '%s\n' "$output" | grep -c 'ralph.config.sh\|config')"
  printf '=== sortie du run ----------------------------------\n%s\n' "$output"

  set -e
  false
}

@test "Q8b témoin appairé : le même drain quitté, sans l'édition de la config" {
  mk_ticket 20-first Status ready-for-human Escalation failed-impl \
    'Write-surface' '`src/one.txt`' 'Blocked by' None
  mk_ticket 22-agent Status ready-for-agent \
    'Write-surface' '`src/two.txt`' 'Blocked by' None
  set_config TEST_CMD 'false'

  script_claude <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT

  drain <<'ANSWERS'
o
q
ANSWERS
  printf '=== rc du drain                   : %s\n' "$status"

  rm -f "$SHIM_STATE/claude.script"
  run_loop
  printf '=== rc du run AFK                 : %s\n' "$status"
  printf '=== Status 22-agent               : %s\n' "$(ticket_status 22-agent)"
  printf '=== sortie du run ----------------------------------\n%s\n' "$output"

  set -e
  false
}
