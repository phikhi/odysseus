# 85 — Le recensement des gardes est complet et n'est dérivé par aucun test

**What to build:** Qu'un `state_guard_take` ajouté au pack rougisse le gate tant qu'il n'est pas recensé, comme un `mktemp` ajouté rougit déjà `test/gate.bats`.

**Blocked by:** None

**Write-surface:** `test/gate.bats`, `test/mutate.sh`, `.claude/lib/gate.sh`

**Status:** ready-for-agent

- [ ] Un test lit les `state_guard_take` de la source du pack et refuse celui qu'aucune zone de `gate__guard_paths` ne couvre — la dérivation vit dans le test, jamais dans le pack, pour la raison que [62] écrit en toutes lettres (la source du pack est dans un arbre qu'une session écrit).
- [ ] Le test refuse aussi un garde composé **hors** d'un `state_guard_take`, comme `test/gate.bats` refuse déjà un nom de `$TMPDIR` composé hors d'un `mktemp` : une dérivation qui ne sait pas ce qu'elle ne voit pas ne prouve rien.
- [ ] La couverture est demandée **au pack** et non recopiée : le test fait résoudre les chemins par `gate__guard_paths` sur un run mis en scène, comme le test des `mktemp` fait résoudre ses expressions par le pack.
- [ ] Une entrée de mutation par garantie livrée, et le témoin appairé qui distingue « le test ment » de « la ligne porteuse a bougé ».

## Comments

- **Trouvé à la passe transversale du 13/09/2026**
  (`../passe-transversale-13-09.md`, §3). Sonde :
  `../sondes/passe-13-09/q5-le-recensement-des-gardes-nest-derive-par-aucun-test.bats`.
  **C'est la seconde moitié de la question que [77] a laissée ouverte**, et la
  première a déjà été fermée deux fois : la passe du 10/09 a mesuré trois
  `state_guard_take` recensés sur six, [81] a écrit les trois manquants. La liste
  est juste aujourd'hui ; rien ne la tient demain.

- **Ce que [77] écrivait, mot pour mot** :

  > *« rien n'énumère les gardes que le pack pose **hors** de ces deux
  > répertoires, et rien ne dit qu'il n'y en a pas — la liste est `gate_guards`,
  > et son critère est écrit dans son commentaire, pas vérifié par un test qui
  > lirait les `state_guard_take` du pack comme `test/gate.bats` lit ses
  > `mktemp`. C'est la forme exacte de ce que [62] a réparé pour `$TMPDIR`, un
  > répertoire plus loin. »*

- **Mesuré** (Q5). Six `state_guard_take` dans la source livrée :

  | Garde | Où il vit | Couvert par |
  |---|---|---|
  | `forge__guard` (`forge.sh:1441`) | `<feature_dir>/.forge.guard` | la marche du répertoire de feature |
  | `tracker_local__open_guard` (`tracker-local.sh:472`) | `<feature_dir>/.open.guard` | idem |
  | claim guard (`tracker-local.sh:287`) | `<tickets_dir>/<id>.md.guard` | la marche du répertoire de tickets |
  | `concurrency_frontier_guard` (`concurrency.sh:432`) | `<gitdir commun>/ralph.frontier.lock` | `concurrency_guards` |
  | `concurrency__integration_guard` (`concurrency.sh:552`) | `<gitdir commun>/ralph.integrate.lock` | `concurrency_guards` |
  | garde de l'index de leçons (`retro.sh:479`) | `$TMPDIR/ralph-retro.*/index.guard` | `retro_guards` |

  Six sur six. Et six fichiers de `test/` nomment `state_guard_take` : cinq le
  citent en commentaire, un le met en scène (`gate.bats:1404`). **Aucun ne le lit
  comme une source.**

- **Le témoin appairé est dans le même fichier**, et c'est le modèle à reprendre :
  `test/gate.bats:2979` fait `grep -rn 'mktemp' "$PACK_DIR"`, fait résoudre
  chaque expression **par le pack**, refuse un motif de `gate_tmp_names` qu'aucun
  `mktemp` ne produit (`:3113`) — et refuse en plus un nom de premier niveau
  composé hors d'un `mktemp` (`:3119`), parce que la dérivation ne pourrait pas
  le voir. Les deux moitiés sont nécessaires ici aussi.

- **Ce que ça coûte si on ne le fait pas, chiffré par [77] et [81].** Le garde
  d'intégration est le plus cher : pris par un propriétaire vivant,
  `concurrency__wait_for_guard` attend soixante secondes puis rend la main, et une
  itération **verte** finit `not-integrated` — travail dans un worktree que le run
  détruit, aucun commit, aucune ref, aucun changement au ticket, la nuit s'arrête.
  Un septième garde ajouté demain et non recensé, c'est cette scène sans le nom de
  l'objet dans le journal du matin.

- **Un piège à ne pas recréer.** `gate__guard_paths` ne **compose** aucun des
  trois chemins hors de l'arbre : il les demande au module qui les possède
  (`concurrency_guards`, `retro_guards`), pour la raison que `tracker_tickets_dir`
  donne. Un test qui vérifierait la couverture en recomposant les chemins
  lui-même serait la seconde liste que ce ticket existe pour supprimer — d'où
  l'AC « la couverture est demandée au pack ».

- **Et un module qui ne répond rien n'est pas un trou** : un drain sans espace de
  leçons, une machine sans répertoire git commun ne contribuent rien, ce que
  `gate_guards` documente déjà comme la réponse honnête. Le test doit distinguer
  « cette zone est vide ici » de « ce preneur n'est couvert nulle part ».

## Place dans la file

Ouvert par la passe du 13/09/2026. **Ordre proposé, à valider par Philippe :**
**[83] → [84] → [85] → [73] → [19]**. Dernier des trois : il ne ferme aucune
faille atteignable aujourd'hui, il empêche celle de demain — et il est plus court
écrit après [83], qui ouvre `test/gate.bats` de toute façon.

Arêtes réelles : [77], [81], [62], [49].
