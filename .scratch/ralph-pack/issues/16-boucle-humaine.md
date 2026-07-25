# 16 — Boucle humaine (`human-loop.sh`)

**What to build:** La 2ᵉ boucle bash HITL, sœur de la ralph loop, qui **draine le puits `ready-for-human`**, route chaque ticket par sa raison d'escalade vers le bon traitement, et **réinjecte** le résultat en `ready-for-agent`. Ferme le cycle escalade → drain → réinjection.

**Blocked by:** 07

**Write-surface:** `.claude/human-loop.sh`, `.claude/lib/router.sh`, `test/human-loop.bats`

**Status:** ready-for-agent

- [ ] `human-loop.sh` draine `ready-for-human` et route par `Escalation:` : `decision`→grilling, `too-big`→to-tickets, `failed-impl`→implement/pair (amorcé `failed/<ticket>` + reçu), `spec-gap`→to-spec, `sign-off`→approbation.
- [ ] Anti-faux-vert : tout code corrigé repasse le gate via réinjection `ready-for-agent` ; jamais de `resolved` direct sauf `sign-off`.
- [ ] Exclusion mutuelle avec l'AFK via le verrou de run (on broie **ou** on draine).
- [ ] L'ordre de traitement = impact de déblocage puis NN.
