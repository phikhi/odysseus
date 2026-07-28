# 22 — Un run par arbre de travail, pas un par tracker

**What to build:** Le verrou de run est par **feature** ; le rollback, le commit sur vert, `HEAD` et le snapshot d'arbre sont par **dépôt**. Deux runs sur deux features d'un même dépôt — un usage que la spec autorise et qu'un test encourage — se détruisent donc mutuellement. Fermer l'écart : refuser au démarrage ce que le pack ne sait pas faire, jusqu'à ce que [13] livre l'isolation par worktree.

**Blocked by:** None

**Write-surface:** `.claude/lib/state.sh`, `.claude/loop.sh`, `test/state.bats`, `test/failures.bats`, `test/mutate.sh`

**Status:** ready-for-agent

- [ ] Un second run sur le même dépôt est refusé au démarrage, quelle que soit sa feature, avec un message qui dit qui tient l'arbre et pourquoi c'est refusé.
- [ ] Le verrou de dépôt vit hors de l'arbre de travail : ni `git add -A`, ni `git clean`, ni un `rm -rf .scratch` d'une session ne l'atteignent.
- [ ] Le verrou par feature reste (spec §135 : AFK et human-loop s'excluent sur un même tracker) — les deux verrous coexistent, avec des raisons distinctes et documentées.
- [ ] Le test `the lock is per feature: two features run side by side` est retourné : il dit désormais ce qui est vrai, à savoir que la primitive est par feature *et* que la boucle refuse quand même le second run.
- [ ] Une entrée dans `docs/frontiere-de-confiance.md` : ce qui tient « un seul run par arbre ».

## Comments

- **Trouvé par la passe transversale du 28/07/2026, après [21]. Faille vivante, reproduite, et elle n'a besoin d'aucune option de concurrence** — deux invocations de `loop.sh` sur deux features suffisent.

  La spec §135 dit : « **Verrou de run grossier**, un par feature, couvrant AFK **et** human-loop : 1 run à la fois par tracker. » Et `test/state.bats` porte `the lock is per feature: two features run side by side`. L'usage est donc autorisé et encouragé. Mais `gate_tree_snapshot` mesure **tout l'arbre**, `gate_is_bookkeeping` n'écarte que `.scratch/<FEATURE>/`, et `failures_rollback` / `failures_make_durable` agissent sur **tout le diff**.

  **Sonde 1 — deux sessions parfaitement honnêtes**, write-surfaces disjointes (`src/alpha.txt` pour f1, `src/beta.txt` pour f2), trackers disjoints, verrous disjoints. f1 lente, f2 rapide :

  ```
  f1: wrote .scratch/other/.session.16104.jsonl, outside the declared write-surface
      wrote .scratch/other/.session.16104.jsonl.tokens, outside the declared write-surface
      gate: 01-alpha: tests=green typecheck=green scope=red
      rolled back 3 path(s) the session touched
      01-alpha: gate-red -> fresh retry (1 of 2)
      sterile run: 1 iterations resolved nothing — stopping        exit 4

  f2: wrote .scratch/demo/.session.16103.jsonl, outside the declared write-surface
      wrote src/alpha.txt, outside the declared write-surface
      gate: 02-beta: tests=green typecheck=green scope=red
      rolled back 3 path(s) the session touched
  ```

  Chacune est déclarée en débordement sur le travail **et** le bookkeeping de l'autre, chacune récolte un `Failures:` qu'elle n'a pas mérité, et chacune rollbacke le travail de l'autre — f2 a supprimé `src/alpha.txt`, que f1 avait écrit *dans sa propre write-surface*. f1 rapporte un **run stérile** alors que sa session avait livré exactement ce qu'on lui demandait. f2 ne s'en sort que parce qu'un retry la sauve.

- **Sonde 2 — le rollback supprime aussi les répertoires, et casse l'autre run en vol.** `failures_rollback` fait `rmdir -p "$(dirname "$path")"` après avoir supprimé un ajout. f2 avait fait `mkdir -p src` puis travaillé ; le rollback de f1 a supprimé `src/` devenu vide, et quatre secondes plus tard la session de f2 a échoué :

  ```
  claude.script: line 13: src/beta.txt: No such file or directory
  ```

  Plus insidieux qu'un fichier effacé : la session **échoue à écrire** et rien ne lui dit pourquoi. Sur un vrai agent, cela produit une itération qui part en boucle sur une erreur d'I/O inexplicable.

- **Sonde 3 — le claim d'un autre run est annulable, selon le timing.** Le ticket d'une autre feature n'est pas du bookkeeping au sens de `gate_is_bookkeeping` (qui ne connaît que `$FEATURE`), donc il entre dans le diff du rollback. Vérifié dans les deux sens : si le run qui rollbacke a pris son snapshot **après** le claim de l'autre, le claim survit ; s'il l'a pris **avant** (le cas où il démarre le premier), le fichier du ticket est restauré à l'état pré-claim — **l'exclusion mutuelle est cassée**, et un troisième picker peut prendre un ticket déjà en cours.

- **Pourquoi ce n'est pas [13].** [13] traite la concurrence **intra-run** (`MAX_PARALLEL > 1`) et la contrainte de [07] y est déjà écrite : « le rollback, le commit sur vert et `HEAD` sont globaux au dépôt ». Mais personne n'avait posé la question pour **deux runs**, et là il n'y a aucune option à activer : le pack le permet, la spec l'annonce, un test l'encourage. C'est la forme exacte du pire bug du projet — faux dans aucun ticket pris isolément.

- **Correctif recommandé, et pourquoi celui-là.** Refuser plutôt que rattraper. Trois raisons :

  1. **Élargir `gate_is_bookkeeping` à tout `.scratch/` serait un recul.** Aujourd'hui, une session qui écrit `.scratch/une-autre-feature/` est vue comme un débordement et rollbackée — c'est correct et souhaitable, et [21] n'y touche pas (sa protection est bornée à `$FEATURE`). Exclure tout `.scratch/` ouvrirait le trou que [21] vient de fermer, dans le tracker voisin.
  2. **Restreindre le rollback à la write-surface est impossible** : son travail est précisément de défaire les écritures **hors** surface.
  3. Il reste donc l'isolation (un worktree par run) ou le refus. L'isolation est [13]. En attendant, refuser est cohérent avec la philosophie du pack — il refuse déjà de démarrer sur `TEST_CMD` vide plutôt que de broyer derrière un gate qui ne prouve rien. Ici : refuser de démarrer plutôt que détruire le travail d'un autre run.

  Un **verrou par dépôt** en plus du verrou par feature, dans `.git/` : hors de l'arbre de travail, donc hors d'atteinte d'un `git add -A`, d'un `git clean` ou d'un `rm -rf .scratch` — contrairement au verrou de run, dont [12] a montré qu'une session peut le supprimer. Quand [13] livrera les worktrees, il devient « un run par worktree » et plusieurs features redeviennent possibles sans rien changer d'autre.

- **Ce que ce ticket doit dire à [13] en le livrant** : le verrou de dépôt est ce qui devra être relâché — ou re-scopé au worktree — pour que la concurrence soit permise. C'est le point d'entrée du travail de [13], pas un obstacle.
