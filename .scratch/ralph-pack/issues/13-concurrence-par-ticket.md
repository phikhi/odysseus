# 13 — Concurrence par-ticket (worktree, write-surfaces disjointes, MAX_PARALLEL, intégration sérialisée)

**What to build:** L'exécution de plusieurs itérations en parallèle **en sécurité** : worktree git par itération, séquencement par write-surfaces disjointes (unifié avec le scope-guard), cap throttlé par le budget agrégé, intégration sérialisée sur la branche principale.

**Blocked by:** 12, 05, 08

**Write-surface:** `.claude/lib/concurrency.sh`, `test/concurrency.bats`

**Status:** ready-for-agent

- [ ] Chaque itération construit / teste / roll-back dans un worktree git isolé.
- [ ] Deux tickets à write-surfaces **disjointes** s'exécutent en parallèle ; des write-surfaces qui se chevauchent (ou inconnues) sont **séquencées** (fail-safe) — mécanisme unifié avec le scope-guard d'[05].
- [ ] Le parallélisme est borné par `MAX_PARALLEL` et throttlé par le budget agrégé ; fallback `=1` si le test est partagé.
- [ ] L'intégration est **sérialisée** : les worktrees gatés sont repliés un-à-un sur la branche principale (couvre l'index LEARNINGS).
- [ ] Le verrou de run est conservé (1 run pilote, N itérations).

## Comments

- **Contrainte posée par [05] : le worktree par itération n'est pas une optimisation, c'est une condition de correction du scope-guard.** Le guard mesure la différence entre un snapshot de l'arbre de travail pris avant le spawn et un pris après la session. Deux itérations concurrentes dans **le même arbre** verraient chacune le travail en cours de l'autre apparaître dans son propre diff — donc un débordement hors write-surface, classé `contract` (drift) puisque l'autre ticket déclare bien ces fichiers. Le résultat serait des escalades croisées sur deux tickets pourtant corrects. Isoler l'arbre par itération est ce qui rend le snapshot pré-spawn honnête.
