# 15 — Revue de capacités au fil de l'eau

**What to build:** Le pas qui **repère sans créer** une capacité manquante (lentille / agent / skill) en delivery : le retro propose et escalade, jamais d'auto-création — une capacité change le contrat, donc toujours HITL.

**Blocked by:** 14

**Write-surface:** `.claude/lib/capability.sh`, `test/capability.bats`

**Status:** ready-for-agent

- [ ] Détecter ≠ créer : le retro qui repère une lentille/agent/skill manquant ouvre une proposition `ready-for-human`, sans jamais créer la capacité en AFK.
- [ ] La barre de déclenchement est respectée : récurrence **ou** classe non couverte.
- [ ] Réutiliser-avant-créer : la proposition privilégie étendre un brief > réutiliser un skill du substrat > créer neuf.
- [ ] Aucune capacité n'est créée automatiquement pendant un run AFK.
