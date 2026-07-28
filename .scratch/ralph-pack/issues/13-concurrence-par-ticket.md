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
- **Contrainte posée par [07], plus dure que la précédente : le rollback, le commit sur vert et `HEAD` sont globaux au dépôt.** Une itération qui échoue restaure chemin par chemin l'arbre de travail depuis son snapshot pré-session, `git reset --mixed` la branche si la session avait commité, et une itération verte **commite** sur la branche courante. Dans un arbre partagé, deux itérations concurrentes se détruiraient mutuellement de trois façons : le `reset --mixed` de l'une déplace la branche sous les pieds de l'autre ; le commit sur vert de l'une est calculé sur un arbre de travail que l'autre est en train de modifier ; et la restauration chemin par chemin de l'une écrase le contenu que l'autre a écrit dans un chemin commun. Le worktree par itération devient donc une **précondition de `MAX_PARALLEL > 1`**, pas une optimisation — et l'intégration sérialisée doit reprendre le commit-sur-vert de [07] au moment du repli, sans quoi la garantie « un gate vert est durable avant l'itération suivante » se perd en concurrence.
- Deuxième effet [07] : les branches `failed/<ticket>` sont des refs globales. Deux itérations qui échouent en parallèle sur le même ticket (ne devrait pas arriver, le claim l'interdit) écraseraient la même ref ; à garder en tête si le repli sérialisé les manipule.
- **Contrainte posée par [21] : la protection du tracker est un snapshot global, comme le rollback.** `failures_protect_tracker` compare deux tree objects de tout `.scratch/<feature>/issues` autour du spawn et restaure ce qui a bougé. En concurrence, la boucle écrit légitimement dans `issues/` **pendant** la fenêtre d'une autre itération : le claim de l'itération B, son `Failures:`, son marquage. L'itération A verrait donc ces écritures comme un delta et **restaurerait le ticket de B** — un claim effacé, un compteur remis à zéro, une résolution annulée — puis se déclarerait elle-même non verte pour une faute qu'elle n'a pas commise. Un worktree git par itération **ne suffit pas** ici, contrairement au rollback et au commit sur vert : le tracker est partagé par construction, il est l'autorité d'état commune. Il faut donc soit restreindre le snapshot au *seul ticket réclamé* (ce qui perd la variante « une session marque le ticket d'un autre resolved », la plus coûteuse des deux), soit sérialiser les écritures de la boucle dans `issues/` avec les fenêtres de surveillance. À trancher avant d'ouvrir `MAX_PARALLEL > 1` : en l'état, la protection et la concurrence sont incompatibles.
