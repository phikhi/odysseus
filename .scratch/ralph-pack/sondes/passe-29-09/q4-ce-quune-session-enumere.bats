#!/usr/bin/env bats
#
# Passe transversale du 29/09 — Q4. Le recensement, mesuré et pas raisonné.
#
# [83] a posé la bonne question — « qu'est-ce que le pack crée APRÈS le sceau du
# pilote, donc à l'intérieur d'un fork, donc couvert par rien ? » — et il l'a
# posée **d'un seul répertoire**, choisi à la main :
#
#     « Measured on 13/09/2026, on a real run, by a session that received no name
#       and globbed "$TMPDIR"/ralph-retro.* : there are two of them »
#
# Cette sonde pose la même question de tout `$TMPDIR`, depuis la session d'une
# itération, pendant qu'elle tourne. Elle ne forge rien : elle liste.
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

@test "Q4 ce qu'une session d'itération voit dans \$TMPDIR, et ce qu'il y a dedans" {
  use_tickets 01-alpha 02-beta
  set_config RETRO on

  script_claude <<'SCRIPT'
#!/usr/bin/env bash
state="$RALPH_SHIM_STATE"
{
  printf '# TMPDIR=%s\n' "$TMPDIR"
  for d in "$TMPDIR"/ralph-*; do
    [ -e "$d" ] || continue
    if [ -d "$d" ]; then
      printf 'DIR  %s\n' "$(basename "$d")"
      for f in "$d"/* "$d"/.*; do
        [ -f "$f" ] || continue
        printf '     - %s (%s o)\n' "${f#$d/}" "$(wc -c <"$f" | tr -d ' ')"
      done
    else
      printf 'FILE %s (%s o)\n' "$(basename "$d")" "$(wc -c <"$d" | tr -d ' ')"
    fi
  done
  printf '# et ce que le pack publie lui-meme :\n'
  sed -n "s/^    '\(ralph-[^']*\)' .*/  glob \1/p" "$RALPH_DIR/lib/gate.sh"
} >"$state/tmpdir.listing" 2>&1
chmod -x "$state/claude.script"
exec claude "$@"
SCRIPT

  run_loop_own_tmp
  printf '=== statut du run : %s\n' "$status"
  printf '=== ce que la session a vu (premiere iteration, pendant sa fenetre) :\n'
  sed 's/^/    /' "$SHIM_STATE/tmpdir.listing" 2>/dev/null || printf '    rien\n'
  printf '=== une ligne du run nomme-t-elle la lecture ?\n'
  printf '%s\n' "$output" | grep -iE 'listed|enumerat|tmpdir|appeared' |
    sed 's/^/    /' || printf '    aucune\n'

  set -e
  false
}
