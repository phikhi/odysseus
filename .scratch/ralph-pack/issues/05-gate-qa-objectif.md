# 05 — Gate QA objectif (tests + typecheck + scope-guard, checks //)

**What to build:** Le gate déterministe par itération : `TEST_CMD`, `TYPECHECK_CMD` et le scope-guard exécutés **en parallèle par la boucle bash** (autorité déterministe, complaisance LLM impossible). *resolved* = toutes les branches déclenchées vertes. C'est ce qui remplace le gate stub d'[03].

**Blocked by:** 03

**Write-surface:** `.claude/lib/gate.sh`, `test/gate.bats`

**Status:** ready-for-agent

- [ ] Le gate lance `TEST_CMD`, `TYPECHECK_CMD` et le scope-guard en parallèle ; un exit non-zéro de n'importe lequel rend le gate rouge.
- [ ] Le scope-guard échoue si `git diff --name-only` sort de la **write-surface déclarée** du ticket ; un débordement dans un fichier neutre est distingué d'un débordement dans un autre ticket.
- [ ] *resolved* n'est prononcé que si **toutes** les branches déclenchées sont vertes ; un fake `claude` qui casse les tests ne produit jamais `resolved`.
- [ ] Anti-faux-vert : une commande objective absente ou silencieuse ne compte pas comme verte (confirmation forcée).
