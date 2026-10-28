#!/usr/bin/env bash
# Replay the run-reel probes of [108], [110], [109] on main, serially.
cd /Users/philippekhill/Sites/odysseus || exit 1
out=/private/tmp/claude-501/-Users-philippekhill-Sites-odysseus/0dad1568-41d2-4f5a-8b30-f96952bbe82e/scratchpad/replay
S=.scratch/ralph-pack/sondes
for p in \
  ticket-108/s1-survivant-qui-reecrit-les-heredocs.bats \
  ticket-110/s1-dou-viennent-les-trois-lignes.bats \
  ticket-110/s2-le-stdin-du-run.bats \
  ticket-100/p2-le-temoin-detruit.bats \
  ticket-109/q1-sondes.bats \
  ticket-109/q4-cfg-et-concurrence.bats \
  passe-16-10/g1-le-stdin-que-git-passe.bats \
  passe-16-10/g4-trois-chemins-gardes.bats
do
  n=$(printf '%s' "$p" | tr '/' '_')
  start=$(date +%s)
  bash test/run.sh "$S/$p" </dev/null >"$out/$n.log" 2>&1
  rc=$?
  printf '%s rc=%s %ss\n' "$p" "$rc" "$(( $(date +%s) - start ))" >>"$out/summary"
done
for h in ticket-110/h1-les-verbes-qui-lancent-le-fsmonitor.sh ticket-110/h2-check-ignore-sans-index.sh; do
  n=$(printf '%s' "$h" | tr '/' '_')
  bash "$S/$h" </dev/null >"$out/$n.log" 2>&1
  printf '%s rc=%s\n' "$h" "$?" >>"$out/summary"
done
echo EXIT >>"$out/summary"
