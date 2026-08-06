# 22 — Un run par arbre de travail, pas un par tracker

**What to build:** Le verrou de run est par **feature** ; le rollback, le commit sur vert, `HEAD` et le snapshot d'arbre sont par **dépôt**. Deux runs sur deux features d'un même dépôt — un usage que la spec autorise et qu'un test encourage — se détruisent donc mutuellement. Fermer l'écart : refuser au démarrage ce que le pack ne sait pas faire, jusqu'à ce que [13] livre l'isolation par worktree.

**Blocked by:** None

**Write-surface:** `.claude/lib/state.sh`, `.claude/loop.sh`, `test/state.bats`, `test/failures.bats`, `test/mutate.sh`, `test/helpers/harness.bash`, `docs/frontiere-de-confiance.md`, `CONTEXT.md`, `README.md`

**Status:** resolved

- [x] Un second run sur le même dépôt est refusé au démarrage, quelle que soit sa feature, avec un message qui dit qui tient l'arbre et pourquoi c'est refusé.
- [x] Le verrou de dépôt vit hors de l'arbre de travail : ni `git add -A`, ni `git clean`, ni un `rm -rf .scratch` d'une session ne l'atteignent.
- [x] Le verrou par feature reste (spec §135 : AFK et human-loop s'excluent sur un même tracker) — les deux verrous coexistent, avec des raisons distinctes et documentées.
- [x] Le test `the lock is per feature: two features run side by side` est retourné : il dit désormais ce qui est vrai, à savoir que la primitive est par feature *et* que la boucle refuse quand même le second run.
- [x] Une entrée dans `docs/frontiere-de-confiance.md` : ce qui tient « un seul run par arbre ».

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

## Livraison

- **Deux verrous, deux questions distinctes, un seul handler de libération.** `run_lock_*` garde le **tracker** (un run par frontière, spec §135) et reste inchangé, dans `.scratch/<feature>/.run.lock`. `tree_lock_*` garde l'**arbre** (`<git-dir>/ralph.tree.lock`) et refuse tout second run *quelle que soit sa feature*. `loop.sh` prend le verrou d'arbre **en premier** — le refus le plus grossier doit tomber avant qu'on ait pris quoi que ce soit d'autre — puis le verrou de feature. Message en deux lignes : qui tient l'arbre (pid + feature du détenteur, lue dans son propre garde), puis pourquoi c'est refusé.

- **Piège trouvé en écrivant, invisible à la lecture : les traps bash ne s'empilent pas.** Deux `*_acquire` posant chacun `trap … EXIT` laissent le **second** seul détenteur du handler, et le premier verrou fuit à la sortie. D'où `state_locks_release`, un handler unique appelé par les deux acquires, chaque libération étant un no-op pour un verrou que ce processus n'a pas pris. Deux tests le tiennent (sortie ordinaire, `SIGTERM`) et la mutation `only the last lock taken is released` le prouve.

- **Frontière de confiance : `.git/` est hors d'atteinte d'un *accident*, pas hors d'atteinte.** Un `git add -A`, un `git clean -xdff` et un `rm -rf .scratch` ne l'atteignent pas — sondé, et le test `the working-tree lock is out of reach of the tree it guards` rejoue les trois puis vérifie que le verrou **refuse encore**, pas seulement qu'il est encore là. Mais une session peut faire `rm -rf .git/ralph.tree.lock`. La boucle revérifie donc **les deux** verrous à chaque itération, symétriquement à ce que [12] avait posé pour le verrou de run, et sort en `exit 4` sur l'un comme sur l'autre. Sans ce contrôle, la ligne ajoutée au tableau de `docs/frontiere-de-confiance.md` aurait été un faux vert de plus.

- **Refuser ne doit pas devenir la panne.** Un run tué sans libérer laisserait le dépôt bloqué pour de bon. La reprise d'un garde périmé de `state_guard_take` s'applique donc au verrou d'arbre aussi, et un test le tient (`a working-tree lock whose holder died is taken over`). La liveness est pid-based, donc mono-machine — même limite que le verrou de run, et même backstop TTL attendu en [12].

- **`state_guard_take` prend un troisième argument optionnel : une note.** Un pid seul dit *quel processus*, jamais *quel run* — et « refusé par le pid 94485 » n'aide personne à 3 h du matin. La note est écrite **après** le `mkdir`, parce que `mkdir` est le seul test-and-set atomique d'un pack en bash pur : un rival qui lit le garde dans cette fenêtre voit le pid et pas la note, donc tout lecteur traite une note absente comme `unknown`. Assumé, documenté dans le code, et sans conséquence — la fenêtre ne peut que dégrader le message, jamais l'exclusion.

- **Sonde du run réel : la reproduction du ticket est morte.** Deux vrais `loop.sh`, deux configs, deux features, write-surfaces disjointes, f2 démarrée pendant la session de f1. Avant : `scope=red` des deux côtés, `rolled back 3 path(s)`, f1 en run stérile `exit 4` alors que sa session avait livré exactement ce qu'on lui demandait. Après :

  ```
  f1: gate: 01-alpha: tests=green typecheck=green scope=green
      01-alpha: committed 1 path(s)
      iteration 1: 01-alpha -> resolved
      frontier empty after 1 iterations                                    exit 0
  f2: another run already holds this working tree (pid 94485, feature demo)
      refusing to start — the tree snapshot, the rollback, the commit on
      green and HEAD are repository-wide, …                                exit 1
  ```

  Sondé aussi : aucun `outside the declared write-surface`, aucun `rolled back`, aucun `sterile` chez f1, `src/alpha.txt` toujours sur le disque, `02-beta` toujours `ready-for-agent`, aucune session spawnée par f2, et les deux verrous partis. Les sondes 2 (le `rmdir -p` qui casse l'autre session en vol) et 3 (le claim d'un autre run annulé) tombent par construction : il n'y a plus de second run.

- **Trouvaille en vérifiant une affirmation que j'allais écrire sans la sonder.** Le ticket annonçait « quand [13] livrera les worktrees, ça devient un run par worktree ». C'est vrai — mais seulement parce que le chemin vient de `git rev-parse --git-dir`, à qui un worktree lié répond `.git/worktrees/<nom>/`, et pas de `--git-common-dir` ni de la racine du dépôt. Sondé : git y garde aussi l'`index` et le `HEAD` de ce worktree, ce qui est précisément ce qui rend deux runs en deux worktrees **non destructeurs**. Le verrou est donc déjà par *arbre*, pas par dépôt. Figé par un test (`the lock is per working tree, not per repository`) et par une mutation, plutôt que laissé en commentaire : c'est [13] qui va s'appuyer dessus, et une promesse qu'aucun test ne tient n'est pas une promesse.

- **Risque créé par ce ticket, et il est du genre qui ne rougit nulle part.** Un verrou plus grossier pris *avant* le verrou de feature peut **tenir sa place** dans presque tous les tests : supprimer `run_lock_acquire || exit 1` de `loop.sh` laisserait la suite verte à un test près. La mutation `22 the tree lock stands in for the feature lock` existe pour ça, pointée sur `loop-happy-path.bats "refuses to start while another run holds the lock"` — le seul test qui distingue encore les deux. Toute réécriture future de cette zone doit garder **deux** affirmations vivantes, pas une.

- **Écart de write-surface, assumé.** Trois ajouts hors du périmètre déclaré, tous parce que le dépôt disait désormais quelque chose de faux. `README.md` annonçait cette faille en **Failles connues** au présent ; `CONTEXT.md` n'avait qu'un terme *Verrou de run* défini comme « le mécanisme grossier », alors qu'il y en a maintenant deux qui gardent des choses différentes — il a gagné une entrée **Verrou d'arbre** et la ligne « ce qui garde l'arbre est le verrou d'arbre » sur l'ancienne, parce que le vocabulaire réservé du modèle de domaine était devenu ambigu. Et `test/helpers/harness.bash` : un helper `tree_lock_dir` (qui épelle `.git/ralph.tree.lock` **sans passer par le pack** — un test qui demanderait `ralph_tree_lock_path` ne pourrait pas attraper le pack rangeant son verrou là où une session l'atteint) et `RALPH_TREE_LOCK` ajouté au nettoyage d'environnement, par symétrie avec `RALPH_RUN_LOCK`. Le test retourné de l'AC 4 a été gardé dans `test/state.bats` plutôt que déplacé dans `loop-happy-path.bats` : il porte les **deux** affirmations, dont une qui n'est pas du ressort de la boucle.

- **Ce que le ticket suivant hérite.** `state_guard_take` a un troisième paramètre (note) et `state_guard_note` le relit — le claim de [12] ne les utilise pas mais y a droit. `state_locks_release` est le point de libération unique : tout futur verrou de run doit y passer, pas poser son propre trap. Et l'invariant nouveau, sur lequel [06], [10] et [19] peuvent compter : **pendant qu'un run tourne, aucun autre run ne touche cet arbre de travail** — ce qui rend enfin honnêtes les hypothèses « le diff que je mesure est le mien » de [05] et « le commit sur vert est le mien » de [07].

- **Question transversale.** Ce ticket a **réduit** la dette de concurrence, il n'en a pas créé — sauf le risque de substitution ci-dessus. Il ne touche ni [13] (isolation intra-run : le verrou d'arbre y devient le point d'entrée, contrainte écrite là-bas), ni [21] (dont la protection reste bornée à `issues/` — l'élargir à tout `.scratch/` était justement l'alternative écartée), ni [18] (backend distant : le verrou d'arbre est du git, donc intrinsèquement backend `local` — même angle mort que la protection du tracker, déjà consigné dans [18]). Contraintes écrites dans [13] et [12].

- **Coût sur la suite** : 163 → 172 tests, 95 → 106 mutations, 0 `skip` au canari. Le surcoût par run est d'un `git rev-parse --git-dir` et d'un `mkdir`, une fois au démarrage, plus un `cat` par itération pour le contrôle du verrou. Verte sous le bash 3.2 de macOS.

- **11 mutations vérifiées rouges pour ce ticket** : verrou d'arbre non pris par la boucle, chemin rendu par feature, chemin rendu par dépôt (`--git-common-dir`) au lieu de par arbre, verrou déplacé dans l'arbre qu'il garde, refus qui ne dit pas qui tient, refus qui ne dit pas pourquoi, un seul des deux verrous libéré, reprise d'un garde périmé désactivée, contrôle par itération retiré, `tree_lock_is_ours` toujours vrai, et le verrou de feature devenu superflu derrière le verrou d'arbre. Les quatre plus délicates ont été **inspectées en diff avant d'être crues** : le piège documenté en tête de `mutate.sh` est qu'un `ok` obtenu sur un fichier cassé ne prouve rien, et deux de ces éditions interpolent des `$` dans les deux moitiés de l'expression perl.

- **Passe transversale du 06/08/2026 : le verrou n'est revérifié que par le pilote.** `tree_lock_is_ours` et `run_lock_is_ours` sont posés dans la boucle du pilote, à chaque tour. Depuis [13] ce n'est plus le processus qui écrit : le gate, le commit durable, le repli et le marquage vivent dans le sous-shell de l'itération, qui ne revérifie rien. Un run tué au `SIGKILL` ne déclenche aucun trap, donc les verrous restent posés — mais `state_guard_take` reprend le garde d'un propriétaire mort, donc un run suivant démarre légitimement pendant que l'orphelin commite encore. C'est [44], et c'est la destruction que ce ticket refuse, atteignable en tuant un run.
