#!/usr/bin/env bats
#
# [61] — le prompt de la session routée, rendu tel quel.
#
# Deux choses à voir d'un coup d'œil :
#   1. le paragraphe de [58] arrive entier, backticks comprises, et l'humain ne
#      voit plus « Status:: command not found » ;
#   2. la découpe en heredocs cités n'a pas décalé une ligne blanche : le prompt
#      rendu ici se compare à celui du commit précédent avec `diff`.
#
# Instrument, pas test : le cas finit par un `false` volontaire.

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

@test "Q1 le prompt réellement passé à la session routée" {
  mk_ticket 20-first Status ready-for-human Escalation failed-impl \
    'Write-surface' '`src/one.txt`' 'Blocked by' None

  script_claude <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT

  drain <<'ANSWERS'
o
n
ANSWERS
  printf '=== rc du drain : %s\n' "$status"
  printf '=== erreurs à l'\''écran de l'\''humain : %s\n' \
    "$(printf '%s\n' "$output" | grep -c 'command not found')"
  printf '=== le prompt, en entier ----------------------------\n'
  claude_call_argv 1 | cat -v
  printf '=== fin du prompt -----------------------------------\n'

  set -e
  false
}
