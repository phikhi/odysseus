#!/usr/bin/env bats
#
# Passe transversale du 10/09 — Q4.
#
# Q3 a montré que quatre des huit fichiers du répertoire témoin du run peuvent
# disparaître sans que la nuit s'arrête et sans un mot. « Sans un mot » n'est pas
# encore un coût : celle-ci le chiffre sur le témoin de [70], dont tout le ticket
# était « les deux preuves que le dossier montre sont écrites par une session
# jugée ».
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

sonde__session() {
  { printf '#!/usr/bin/env bash\nprompt="$(cat)"\n'
    printf '%s\n' "$1"
    cat <<'TAIL'
surface="$(printf '%s' "$prompt" | sed -n 's/^\*\*Write-surface:\*\* //p' |
  head -1 | tr -d '`\r' | tr ',' ' ')"
for t in $surface; do mkdir -p "$(dirname "$t")"; printf 'written\n' >"$t"; done
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
TAIL
  } | script_claude
}

# Un reçu d'audit d'un run précédent, dans l'arbre principal — la zone que [70]
# témoigne parce qu'aucun scope-guard ne la regarde.
sonde__seed_receipt() {
  mkdir -p "$PROJECT_DIR/receipts/demo"
  printf '# 00-vieux — resolved\n\nLe reçu d un run précédent.\n' \
    >"$PROJECT_DIR/receipts/demo/00-vieux.md"
}

@test "Q4a une session qui détruit un reçu ET le témoin de [70] : rien n est dit" {
  use_tickets 01-alpha
  sonde__seed_receipt
  sonde__session '
common="$(git rev-parse --git-common-dir 2>/dev/null)"
case "$common" in /*) ;; *) common="$PWD/$common" ;; esac
main="$(cd "$(dirname "$common")" && pwd)"
rm -f "$main"/receipts/demo/00-vieux.md
for d in "${TMPDIR:-/tmp}"/ralph-frontier.*; do
  [ -d "$d" ] || continue
  rm -f "$d/forensic.witness" "$d/forensic.written"
done'

  run_loop_own_tmp
  printf '=== rc du run : %s\n' "$status"
  printf '=== le reçu du run précédent est-il encore là ?\n'
  [ -f "$PROJECT_DIR/receipts/demo/00-vieux.md" ] &&
    printf '    oui\n' || printf '    NON, détruit\n'
  printf '=== ce que le run a dit du sujet :\n'
  printf '%s\n' "$output" | grep -iE "forensic|receipt|reçu|drift" | sed 's/^/    /' ||
    printf '    (aucun mot)\n'
  printf '=== le reçu de cette itération, section « ce que rien n a jugé » :\n'
  sed -n '/What nothing here judged/,/## Meta/p' \
    "$PROJECT_DIR/receipts/demo/01-alpha.md" 2>/dev/null | sed 's/^/    /'

  set -e
  false
}

@test "Q4b témoin appairé : la même destruction, le témoin de [70] laissé en place" {
  use_tickets 01-alpha
  sonde__seed_receipt
  sonde__session '
common="$(git rev-parse --git-common-dir 2>/dev/null)"
case "$common" in /*) ;; *) common="$PWD/$common" ;; esac
main="$(cd "$(dirname "$common")" && pwd)"
rm -f "$main"/receipts/demo/00-vieux.md'

  run_loop_own_tmp
  printf '=== rc du run : %s\n' "$status"
  printf '=== ce que le run a dit du sujet :\n'
  printf '%s\n' "$output" | grep -iE "forensic|receipt|reçu|drift" | sed 's/^/    /' ||
    printf '    (aucun mot)\n'
  printf '=== le reçu de cette itération, section « ce que rien n a jugé » :\n'
  sed -n '/What nothing here judged/,/## Meta/p' \
    "$PROJECT_DIR/receipts/demo/01-alpha.md" 2>/dev/null | sed 's/^/    /'

  set -e
  false
}
