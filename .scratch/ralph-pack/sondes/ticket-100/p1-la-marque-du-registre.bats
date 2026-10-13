#!/usr/bin/env bats
#
# Ticket [100] — P1. La marque `ledger-seen` est le seul fichier du pin que le pack
# réécrit pendant l'itération (`gate__frontier_share`). Une session qui la porte à
# exactement la longueur que le registre aura après la remise efface sa propre part
# du registre : le déplacement est remis, mais personne n'est facturé.
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

widen() {
  script_claude <<SCRIPT
#!/usr/bin/env bash
state="\$RALPH_SHIM_STATE"
main="\$(cat "\$state/project-dir")"
excl="\$main/.git/info/exclude"
mkdir -p "\$(dirname "\$excl")"
printf 'nothing-behind-this-rule.txt\n' >>"\$excl"
if [ "$1" = forge ]; then
  for common in "\$TMPDIR"/ralph-frontier.*; do
    [ -f "\$common/ledger" ] || continue
    n="\$(awk 'END { print NR + 0 }' "\$common/ledger")"
    for pin in "\$TMPDIR"/ralph-ignore.*; do
      [ -f "\$pin/ledger-seen" ] || continue
      printf '%s\n' "\$((n + 1))" >"\$pin/ledger-seen"
      printf '%s -> %s\n' "\$pin" "\$((n + 1))" >>"\$state/forged"
    done
  done
fi
chmod -x "\$state/claude.script"
exec claude "\$@"
SCRIPT
}

report() {
  printf '=== statut du run : %s\n' "$status"
  printf '=== marque forgée : %s\n' "$(cat "$SHIM_STATE/forged" 2>/dev/null || echo non)"
  printf '%s\n' "$output" |
    grep -iE 'frontier|put back|scope|iteration|pinned' | sed 's/^/    /' | head -14
  printf '=== ticket 01-alpha : Status=%s\n' "$(ticket_field 01-alpha Status || true)"
  printf '=== la règle survit-elle ? %s\n' \
    "$(grep -c 'nothing-behind' "$PROJECT_DIR/.git/info/exclude" 2>/dev/null || echo 0)"
}

@test "P1a témoin — la session élargit la frontière, rien d'autre" {
  use_tickets 01-alpha
  widen plain
  run_loop_own_tmp
  report
  set -e
  false
}

@test "P1b la même session porte sa marque à la longueur que le registre aura" {
  use_tickets 01-alpha
  widen forge
  run_loop_own_tmp
  report
  set -e
  false
}
