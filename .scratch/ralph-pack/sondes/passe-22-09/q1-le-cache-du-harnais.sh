#!/usr/bin/env bash
# Sonde Q1 — le gabarit de projet que la suite garde dans $TMPDIR est-il un
# canal de faux vert pour la session que cette même suite juge ?
#
# Pas un .bats : elle pilote `test/run.sh` de l'extérieur, dans une copie de
# l'arbre et avec un $TMPDIR à elle, parce que ce qu'elle mesure est le cache
# que le harnais résout AVANT que le premier test n'existe.
#
# Chaîne mise en scène, dans l'ordre où une session la joue :
#   A  run propre           → la suite bâtit le gabarit sous l'empreinte fp0
#   B  la session casse une garantie du pack (mutation existante de mutate.sh)
#   C  la session calcule fp1 AVEC LA FONCTION DU DÉPÔT et dépose sous cette
#      clé une copie du gabarit PROPRE, plus le drapeau .ready
#   D  le gate lance TEST_CMD → vert ou rouge ?
#   E  témoin appairé : même mutation, sans le dépôt → rouge attendu
set -uo pipefail

SRC="$(cd "$(dirname "$0")/../../../.." && pwd)"
W="$(mktemp -d "${TMPDIR:-/tmp}/sonde-q1.XXXXXX")"
trap 'rm -rf "$W"' EXIT

mkdir -p "$W/pack"
for p in .claude test init.sh package.json bin; do
  [ -e "$SRC/$p" ] && cp -R "$SRC/$p" "$W/pack/"
done
T="$W/tmp"
mkdir -p "$T"

TEST='not stolen'
FILE="$W/pack/.claude/lib/state.sh"
EDIT='s/  if \[ -n "\$owner" \] && kill -0 "\$owner" 2>\/dev\/null; then/  if false; then/'

fingerprint() {
  # La fonction du dépôt, appelée telle quelle : c'est le point.
  ( cd "$W/pack" && RALPH_PACK_ROOT="$W/pack" \
      bash -c '. test/helpers/harness.bash >/dev/null 2>&1; harness__pack_fingerprint' )
}

runsuite() {
  ( cd "$W/pack" && TMPDIR="$T" bash test/run.sh -f "$TEST" test/state.bats 2>&1 |
      LC_ALL=C tr '\r' '\n' | tail -3 )
}

say() { printf '\n=== %s\n' "$*"; }

say 'A — run propre'
runsuite
fp0="$(fingerprint)"
printf 'fp0 = %s\n' "$fp0"
ls -d "$T"/ralph-harness.* 2>/dev/null

say 'B — la session casse une garantie (state.sh : un verrou vivant est volé)'
cp "$FILE" "$W/state.sh.orig"
perl -0pi -e "$EDIT" "$FILE"
if cmp -s "$FILE" "$W/state.sh.orig"; then
  echo 'DRIFTED: la mutation ne mord plus, sonde invalide'; exit 1
fi
fp1="$(fingerprint)"
printf 'fp1 = %s  (différent de fp0 : %s)\n' "$fp1" \
  "$([ "$fp0" != "$fp1" ] && echo oui || echo NON)"

say 'C — la session dépose le gabarit PROPRE sous fp1'
cp -R "$T/ralph-harness.$fp0" "$T/ralph-harness.$fp1"
ls -d "$T"/ralph-harness.* 2>/dev/null

say 'D — le gate lance TEST_CMD sur un pack cassé, avec le gabarit forgé'
runsuite

say 'E — témoin appairé : on retire le dépôt, tout le reste identique'
rm -rf "$T/ralph-harness.$fp1"
runsuite

say 'F — contre-témoin : pack restauré, sans forge'
cp "$W/state.sh.orig" "$FILE"
runsuite
