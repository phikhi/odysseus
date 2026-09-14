# 87 — Aucune des quatre règles de source ne voit le troisième point d'entrée

**What to build:** Que les quatre règles de `test/layering.bats` jugent `init.sh` comme elles jugent `loop.sh` et `human-loop.sh`, et que leur zone soit dérivée des points d'entrée du pack au lieu d'être un glob écrit à la main.

**Blocked by:** None

**Write-surface:** `test/layering.bats`, `test/mutate.sh`

**Status:** ready-for-agent

- [ ] Les quatre règles (`layering_privates`, `layering_upward`, `layering_masked_status`, `layering_heredoc_prose`) sont exécutées sur `init.sh` comme sur les deux autres points d'entrée, et chacune rougit sur une violation plantée dans une **copie** de `init.sh` (le pack planté de `layering__planted_pack` est le logement existant : il copie déjà `lib/`, `loop.sh` et `human-loop.sh`).
- [ ] La zone n'est plus « `.claude/lib/*.sh` plus `.claude/*.sh` » écrit à la main : elle est **dérivée**, de sorte qu'un quatrième point d'entrée livré demain soit jugé le jour où il arrive, ou refusé bruyamment s'il n'est pas dérivable. Un point d'entrée est un fichier exécutable du pack qui n'est pas un lib — le critère est à écrire dans le test, pas à deviner.
- [ ] `layering_privates` reçoit le bon `own` pour `init.sh` : le préfixe est `init_`, ce que `basename … .sh | tr '-' '_'` donne déjà, donc la règle marche telle quelle — le vérifier plutôt que le supposer, avec un `gate__quelque_chose` planté dans la copie.
- [ ] `layering_upward` sur `init.sh` : la règle actuelle ne boucle que sur `lib/`, et elle n'a pas de sens pour un point d'entrée. Décider et **écrire** lequel des deux : soit elle reste sur `lib/` et le test dit pourquoi, soit `init.sh` gagne sa propre règle (un installeur n'a pas le droit d'appeler `loop_`, il n'y a pas de boucle).
- [ ] Une entrée de mutation par garantie livrée, avec le témoin appairé qui distingue « le test ment » de « la ligne porteuse a bougé ».

## Comments

- **Ouvert par la passe transversale du 14/09/2026** (`../passe-transversale-14-09.md`,
  §3). Sonde : `../sondes/passe-14-09/q2-aucune-regle-de-source-ne-voit-linstalleur.bats`.

- **Ce qui est mesuré, et dans les deux sens.** Les quatre règles bouclent sur
  `"$dir"/lib/*.sh "$dir"/*.sh` avec `$dir="$RALPH_PACK_ROOT/.claude"` ; `init.sh`
  est à la racine du dépôt, donc hors des quatre. Un seul backtick dé-échappé
  planté dans le heredoc de `init_claude_block` (sur une **copie**) donne :
  - la règle `layering_heredoc_prose`, extraite de `test/layering.bats` sans être
    recopiée, l'attrape dès qu'on l'y pointe — `init.sh:834` ;
  - l'installeur sort en **0**, avec une ligne `docs/agents/: is a directory`
    perdue dans un rapport de quarante lignes ;
  - et le projet cible garde un `CLAUDE.md` qui dit « The conventions are in . ».

  Témoin appairé : le pack livré **et** `init.sh` tel quel rendent tous deux
  `rc=0`. Les backticks de `init.sh` sont échappés à la main aujourd'hui — c'est
  une propriété de l'auteur, pas du dépôt.

- **Pourquoi la règle du heredoc est celle qui coûte le plus cher ici.** `init.sh`
  est le fichier du pack qui a la plus forte densité de prose non citée : neuf
  heredocs, dont deux — `init_gitignore_block` et `init_claude_block` — écrivent
  dans le projet cible. Le second écrit dans `CLAUDE.md`, qui est **scellé** ([31])
  et que chaque `claude` frais lit au démarrage. [61] a payé un ticket pour la même
  faute dans le prompt d'**une** session ; ici elle atteint toutes les sessions
  d'un projet, pour toute sa vie, et l'installeur ne tourne qu'une fois.

- **Le commentaire de `layering_privates` dit déjà pourquoi ce ticket existe** :
  *« `"$dir"/*.sh` and not `"$dir"/loop.sh`: the pack has two entry points since
  [16], and an entry point outside this glob is one where a lib's `__` internals
  are reachable with nothing to say so. »* [19] en a livré un troisième. Le glob a
  été élargi une fois à la main quand [16] est arrivé ; le livrer dérivé est ce
  qui empêche de le refaire.

- **Contrainte de forme, héritée de [62] et [85].** La dérivation vit **dans le
  test**, jamais dans le pack : la source du pack est dans un arbre qu'une session
  écrit, donc un pack qui publierait la liste de ses propres points d'entrée
  publierait une liste qu'une session peut réduire. Et une dérivation qui ne sait
  pas ce qu'elle ne voit pas ne prouve rien : le test doit refuser un point
  d'entrée que son critère ne classe ni comme lib ni comme entrée, plutôt que de
  le laisser tomber en silence.

- **Piège de mise en scène.** `layering__planted_pack` construit une copie du pack
  et y plante une violation de chaque genre. `init.sh` n'est pas dans cette copie
  aujourd'hui ; l'y ajouter est la moitié facile. La moitié qui compte est que le
  fichier planté soit **une copie** — planter dans `init.sh` lui-même laisse le
  dépôt avec un installeur cassé si le run est interrompu, et c'est précisément ce
  que le commentaire de `layering__planted_pack` dit déjà (*« a run interrupted
  halfway must not leave the repository holding a bogus function »*).

- **Ce que le ticket suivant hérite.** [86] réécrit un heredoc de prose de
  `init.sh` (le bloc `CLAUDE.md`). Livré devant, ce ticket-ci est le filet sous
  cette réécriture ; livré derrière, il constate après coup. C'est la seule arête
  de la file proposée par la passe.

- **Ce que ce ticket ne fait pas, et qui reste écrit ailleurs.** `init.sh`,
  `bin/**` et `package.json` ne sont pas scellés et ne peuvent pas l'être — la
  ligne du tableau de [19] le dit et l'assume. Ce ticket ne change pas ça : il
  ajoute un contrôle de **source**, du même genre que les trois autres, pas une
  garde d'exécution.
