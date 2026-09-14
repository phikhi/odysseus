# 85 — Le recensement des gardes est complet et n'est dérivé par aucun test

**What to build:** Qu'un `state_guard_take` ajouté au pack rougisse le gate tant qu'il n'est pas recensé, comme un `mktemp` ajouté rougit déjà `test/gate.bats`.

**Blocked by:** None

**Write-surface:** `test/gate.bats`, `test/mutate.sh`, `.claude/lib/gate.sh`

**Status:** resolved

- [x] Un test lit les `state_guard_take` de la source du pack et refuse celui qu'aucune zone de `gate__guard_paths` ne couvre — la dérivation vit dans le test, jamais dans le pack, pour la raison que [62] écrit en toutes lettres (la source du pack est dans un arbre qu'une session écrit).
- [x] Le test refuse aussi un garde composé **hors** d'un `state_guard_take`, comme `test/gate.bats` refuse déjà un nom de `$TMPDIR` composé hors d'un `mktemp` : une dérivation qui ne sait pas ce qu'elle ne voit pas ne prouve rien.
- [x] La couverture est demandée **au pack** et non recopiée : le test fait résoudre les chemins par `gate__guard_paths` sur un run mis en scène, comme le test des `mktemp` fait résoudre ses expressions par le pack.
- [x] Une entrée de mutation par garantie livrée, et le témoin appairé qui distingue « le test ment » de « la ligne porteuse a bougé ».

## Comments

- **Précédent écrit par [84], livré le 13/09/2026.** La même forme de recensement
  existe maintenant dans `test/tracker-remote.bats` — « *an entry point that opens
  this reading and never takes one is refused* » — et ses trois traits sont ceux
  que ce ticket-ci demande : la liste est **dérivée** du pack
  (`"$PACK_DIR"/*.sh`, le même glob que `test/layering.bats`), les commentaires
  sont retirés d'abord (un paragraphe qui nomme l'appel n'est pas un appel), et un
  recensement **vide** est un échec et non un vert. Ce qu'il ne fait pas et que
  [85] doit faire en plus : il ne demande rien au pack lui-même — il compte des
  appels, là où la couverture d'un garde doit être **résolue par**
  `gate__guard_paths`.


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

Ouvert par la passe du 13/09/2026. **Ordre validé par Philippe le 13/09/2026,
après la passe transversale du même jour :**
**[83] → [84] → [85] → [73] → [19]**. Dernier des trois : il ne ferme aucune
faille atteignable aujourd'hui, il empêche celle de demain — et il est plus court
écrit après [83], qui ouvre `test/gate.bats` de toute façon.

Arêtes réelles : [77], [81], [62], [49].

## Livré

Livré le 13/09/2026. `test/gate.bats` gagne trois tests et trois helpers, à côté
du modèle des `mktemp` ; `test/mutate.sh` gagne six entrées ; `.claude/lib/gate.sh`
ne change que son commentaire, et seulement parce qu'il portait un nombre faux.

### La trouvaille : ils sont huit, pas six

Ce ticket, le tableau de la passe, la sonde `q5` **et** le commentaire de
`gate__guard_paths` disent tous « six `state_guard_take` ». La dérivation en
trouve **huit**. Les trois comptages excluaient `.claude/lib/state.sh` — la sonde
littéralement (`grep -v '^.*state.sh:'`), pour ne pas ramasser la définition — et
c'est dans `state.sh` que vivent les deux preneurs qu'aucun des trois n'a vus :

| Preneur | Où il vit | Couvert par |
|---|---|---|
| `run_lock_acquire` (`state.sh:175`) | `<feature_dir>/.run.lock` | **aucune zone** |
| `tree_lock_acquire` (`state.sh:278`) | `<gitdir>/ralph.tree.lock` | **aucune zone** |

Ce n'est pas un trou, et c'est la seule décision du ticket : les deux sont hors
du recensement **à dessein**, et la raison n'était écrite qu'en prose. Les trois
lecteurs de `gate_guards` (`gate__stale_guards`, `gate_guard_note`,
`gate_guard_witness`) disent tous la même phrase — *« ce point d'entrée vient de
prendre ses verrous et n'a rien démarré, donc un garde vivant ici n'est pas le
sien »*. Mettre le verrou de run dans le recensement, c'est faire accuser le run
de tenir son propre verrou, à l'instant précis où il le tient. Les deux verrous
répondent d'eux-mêmes là où ils sont pris : un mort est déplacé et annoncé par
`state_guard_take`, un vivant refuse le point d'entrée en le nommant.

Le test autorise donc **deux** réponses et pas une — une zone de
`gate__guard_paths`, ou l'un des deux verrous du point d'entrée — et les deux
sont **demandées au pack** (`ralph_run_lock_path`, `ralph_tree_lock_path`,
résolus dans le même run mis en scène). La seconde réponse n'est pas un
laissez-passer : le test assène juste après que `gate_guards` **ne** rapporte
**pas** ces deux chemins, alors qu'ils sont posés en répertoires au même instant.
Sans cette assertion, « c'est un verrou du point d'entrée » serait l'échappatoire
qui avale n'importe quel preneur futur. Elle a son entrée de mutation à elle
(« les verrous que ce point d'entrée tient lui-même sont comptés comme
étrangers »).

### Pourquoi la résolution passe par l'exécution et non par la ligne

Le modèle des `mktemp` lit l'**expression** sur la ligne (`mktemp -d "<expr>"`)
et la fait évaluer par le pack. Ici c'est impossible : **sept des huit sites**
passent une variable locale (`"$guard"`, `"$lock"`), composée une à quatre lignes
plus haut, parfois à travers trois fonctions de trois modules. Une dérivation qui
lirait la ligne ne verrait rien.

La sortie prise : `state_guard_take` est **remplacé par un enregistreur** dans le
shell du pack, et la fonction **englobante** de chaque site — dérivée de la source
par un `awk` qui remonte au dernier `^nom() {` — est appelée. Le chemin sort donc
exactement comme le pack le compose. Deux appels par site, sans argument puis avec
le ticket que le test a posé (`01-alpha`) : un preneur garde un ticket et a besoin
de son id, et une sonde qui atteindrait sept sites sur huit ne prouverait rien du
huitième.

### Le site qui ne compose rien

`concurrency__wait_for_guard` (`concurrency.sh:552`) prend son `$1` : il garde ce
que son appelant lui passe et ne compose aucun chemin. L'enregistreur récupère
l'argument qu'on lui a tendu, donc le site est classé « pass-through » (sa valeur
n'est pas un chemin absolu) et sort du contrôle de couverture. Ce n'est pas un
angle mort : `ralph.integrate.lock` est composé par
`concurrency__integration_guard`, et c'est le **second** test qui le tient — celui
qui lit les compositions et non les appels. Les deux moitiés sont nécessaires
exactement pour ce cas.

### Le second test, et ce qu'il refuse

« *only a state_guard_take composes an exclusion guard name* » lit chaque ligne de
la source qui compose un nom en `.guard` ou `.lock` (commentaires retirés, et les
**globs** retirés avec eux : `"$dir"/*.guard` est le recensement qui lit une zone,
pas un nom qu'on fabrique). Deux réponses suffisent, et rien d'autre :

- la fonction englobante **prend** un garde — le premier test l'a déjà mise au
  recensement ;
- ou la fonction est résolue **par le pack** et son chemin est une zone de
  `gate__guard_paths`, ou l'un des deux verrous.

Huit compositions aujourd'hui, huit réponses. Un `mkdir` sur un nom fabriqué
ailleurs, ou un nom tendu à un preneur d'un autre module, tombe en `MISSED`.

### Ce que le test ne voit pas, écrit ici et pas gardé

- Un chemin composé **en deux temps** — le répertoire dans une variable sur une
  ligne, le nom sur la suivante — n'est vu par aucune des deux moitiés. C'est la
  même limite que le test des `mktemp` écrit noir sur blanc pour `$TMPDIR`, et
  c'est pourquoi la liste est une liste des noms *de ce pack* et pas une promesse
  qu'aucun autre nom ne peut exister.
- La couverture de `forge__guard` dans le second test dépend du fait que le
  premier a posé le répertoire : une zone **marchée** ne nomme que ce qui s'y
  tient. C'est voulu (le recensement marche deux répertoires, il ne les invente
  pas), mais ça veut dire qu'un preneur retiré fait rougir les deux tests, pas un.
- « Cette zone est vide ici » ≠ « ce preneur n'est couvert nulle part » : le
  troisième test pose le cas — `RALPH_RETRO_STATE` vide, comme un drain sans
  espace de leçons — et vérifie que `retro_guards` refuse sans faire tomber le
  recensement des autres modules. Son entrée de mutation est celle qui fait
  répondre `retro_guards` inconditionnellement.

### Ce que [73] et [19] en héritent

- **[73].** Le run mis en scène est sur le backend **local**. Sur un backend
  distant, `tracker_tickets_dir` ne répond rien et la zone des tickets est vide —
  ce qui est « vide ici » et non « non couvert » (le preneur
  `tracker_local_claim` est appelé directement par la sonde, pas à travers
  l'adaptateur, donc il reste couvert). Si [73] ajoute un garde côté distant, il
  ajoute un neuvième `state_guard_take` : le plancher de huit rougira, et c'est
  exactement le but.
- **[19].** Rien. L'installeur ne prend aucun garde.

### Le commentaire du pack corrigé

`gate__guard_paths` disait « this covered three of the pack's **six**
`state_guard_take` sites ». C'est trois sur les six qu'un run peut **rencontrer** :
la phrase est devenue ça, et un paragraphe dit maintenant pourquoi les deux
verrous du point d'entrée sont dehors, plus la phrase de [85] — la liste n'est
plus tenue par son propre commentaire. La dérivation reste dans le test et jamais
dans le pack, pour la raison de [62] : la source du pack est dans un arbre qu'une
session écrit.

### Gates

- `bash test/run.sh` : 911 tests, 0 failures, 6 skips opt-in (aucun dans le canari)
- `bash test/mutate.sh` : 944 mutations, 0 not ok
