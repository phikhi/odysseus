# 91 — Le shell qui porte le verdict n'est pas surveillé

**What to build:** Que ce que le run épingle du `PATH` couvre le nom par lequel passent les quatre commandes du projet — `bash` — et que le premier mot de ces quatre commandes soit tranché plutôt qu'omis par défaut.

**Blocked by:** None

**Write-surface:** `.claude/lib/gate.sh`, `.claude/lib/scheduler.sh`, `test/gate.bats`, `test/scheduler.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** resolved

- [x] `bash` entre dans ce que `gate_path_programs` publie, et un test **dérive** de la source livrée les noms que le pack lance par leur nom nu plutôt que de recopier la liste — la dette que le tableau nomme aux deux endroits (`gate_config_keys`, `gate_path_programs`) est payée sur celle-ci, et le critère de la dérivation est écrit dans le test ([62], [85]).
- [x] Le premier mot de `TEST_CMD`, `TYPECHECK_CMD`, `RUN_CMD` et `VISUAL_CMD` est **tranché** : soit il entre dans le manifeste (dérivé de la configuration, pas retapé), soit la ligne du tableau dit que le pack ne surveille pas le programme dont il croit le code de sortie, et pourquoi. Une réponse « c'est le programme du projet » n'en est pas une — c'est le programme dont le verdict décide de tout.
- [x] `scheduler_command` ne résout plus le shell du successeur avec `command -v` : le commentaire de `gate__path_where` interdit cette fonction en toutes lettres, et la ligne mise en file s'exécute des heures plus tard.
- [x] Un test met en scène un `bash` planté en tête de `PATH` sur une itération réelle et asserte **ce qui a changé** : le nom apparaît dans le témoin, une ligne le nomme, le successeur n'est pas armé. Jamais `assert_success` seul.
- [x] Une entrée de mutation par garantie livrée, avec le témoin appairé.

## Comments

- **Ordre validé par Philippe le 22/09/2026** : **[91] → [92] → [93]**.
  Le critère est celui d'habitude — minimiser la reprise, jamais l'urgence. [91]
  devant parce qu'un `bash` planté possède l'interpréteur des quatre commandes du
  projet et rendrait inutile toute réparation faite à l'intérieur du gate ; [92]
  ensuite, seul ticket qui touche le cycle de vie d'une session, et il réécrit la
  borne de la ligne 35 du tableau ; [93] en dernier, purement dans `test/`, sa
  ligne de tableau étant l'aveu générique dont les deux autres sont les cas
  adressables.

- **Ouvert par la passe transversale du 22/09/2026** (`../passe-transversale-22-09.md`,
  §1). Sonde : `../sondes/passe-22-09/q2-le-verdict-passe-par-un-nom-non-surveille.bats`.

- **Les quatre sites, mesurés sur le pack livré** : `gate.sh:3814`
  (`bash -c "$TEST_CMD"`), `gate.sh:3821` (`bash -c "$TYPECHECK_CMD"`),
  `playthrough.sh:291` (`bash -c "$cmd"` pour `RUN_CMD` et `VISUAL_CMD`),
  `scheduler.sh:510` (`command -v bash`, figé dans la ligne du successeur).

- **Le compte** : `gate_path_programs` rend **32** noms, `gate_path_witness`
  écrit **32** lignes, aucune ne dit `bash`. Un `bash` enregistreur en tête de
  `PATH` voit **13** passages sur une itération verte, dont les **4** qui portent
  un verdict (`-c stub-cmd tests`, `-c stub-cmd typecheck`, `-c stub-cmd run`,
  `-c stub-cmd visual`). Le run sort `0`, le ticket est `resolved`, rien n'est dit.

- **Ce n'est pas la dette nommée par le tableau.** Celle-ci dit *« un site d'appel
  ajouté au pack dans un programme absent de la liste rouvre le trou »* : elle
  parle d'une dérive. Les quatre sites sont **antérieurs** à [52] — la liste était
  incomplète le jour où elle a été écrite.

- **Ce que [52] a posé et qu'il ne faut pas défaire.** Ce qui est surveillé n'est
  pas les *répertoires* du `PATH` (bruit sur un canal dont la conséquence est de
  refuser un successeur) mais la **résolution et le contenu** des noms. Les
  builtins de bash sont absents par critère et non par oubli. La recherche est
  faite à la main sur `PATH` (`gate__path_where`) et jamais demandée à
  `command -v` — c'est le piège que [52] a trouvé en livrant. Le prix est écrit :
  un `bash` mis à jour en pleine nuit coûtera le successeur, comme un `git` mis à
  jour le coûte déjà.

- **Contrainte pour [92]** : un `bash` planté rend inutile toute réparation faite
  à l'intérieur du gate, puisqu'il possède l'interpréteur des quatre commandes.
  Ce ticket est le plancher de l'autre, et c'est pour ça qu'il passe devant.

- **Livré le 22/09/2026.** Ce que le code ne dit pas :

  **La liste n'était pas courte d'un nom, elle l'était de cinq — et large de
  deux.** Une fois la dérivation écrite, le pack lance par leur nom nu **35**
  noms, `gate_path_programs` en publiait **32**, et l'intersection n'était pas
  celle qu'on attendait : manquaient `bash`, **`sh`** (`proc_self` :
  `$(exec sh -c 'echo $PPID')`), **`chmod`** (`init.sh:632`), **`cmp`**
  (`retro.sh:637`), **`rmdir`** (`concurrency.sh:732`, `gate.sh:2995`) ; et
  `diff` et `touch` y étaient pour des sites d'appel que le pack **n'a pas** (les
  diffs passent tous par `git diff`). Les cinq manques sont antérieurs à [52]
  comme `bash` l'est : ce n'est toujours pas la dérive que le tableau nomme.

  **La dérivation est un lexeur, pas un `grep`, et c'est ce qui a coûté le
  temps.** Quatre versions successives ont rendu 71, 54, 51 puis 35 candidats, et
  les 36 de trop étaient tous de la prose — `who`, `yes`, `open`, `install`,
  `file`, `size`, `split` sont de vrais programmes de cette machine. Quatre
  décisions portent seules la propreté du résultat, et chacune a été mesurée :

  1. **un antislash en fin de ligne JOINT.** Sans ça, `printf '%s\n' \` suivi
     d'un nom par ligne fait lire chaque nom comme une commande : `router_reasons`
     donnait `failed-impl`, `too-big`, `spec-gap`… et surtout
     **`gate_path_programs` se certifiait elle-même**. C'est la seule réponse que
     ce test ne doit pas pouvoir donner, et c'est une ligne d'awk.
  2. **les chaînes se suivent d'une ligne à l'autre, et `$(` rouvre du code
     dedans.** Un `sed` qui retire `"[^"]*"` mange `"$(basename "` et perd
     `basename` ; un lexeur qui ne rouvre pas perd `uname` dans
     `case "$(uname -s)"`. Les deux cas sont assertés nommément dans le test.
  3. **`$((` doit être testé AVANT `$(`**, y compris à l'intérieur d'une chaîne
     double : sinon `"$((attempt + 1))"` livre `attempt` en position de commande.
  4. **un motif de `case` n'est pas une position de commande** (`auto | at |
     systemd-run)`), et **un préfixe d'affectation n'est pas la commande** —
     `DISABLE_AUTO_COMPACT=1 claude -p` est la façon dont ce pack ouvre *toutes*
     ses sessions, donc sans cette ligne le scan ne voit pas `claude`.

  Le backtick n'est **pas** un séparateur de position de commande : ce pack écrit
  des centaines de backticks markdown dans sa prose et n'utilise jamais la
  substitution par backticks ([61], [90]). L'exclusion des builtins est demandée
  à `compgen -b`/`compgen -k` et pas retapée.

  **Le second demi-cas est tranché dans le sens « il entre dans le manifeste ».**
  `gate_path_project_programs` dérive le premier mot des quatre clés de config.
  Ce qui a été décidé en écrivant, et qui n'était pas dans le ticket :
  - **un préfixe d'affectation est traversé, pas refusé** — `NODE_ENV=test npm
    test` est un `TEST_CMD` ordinaire, et le lire comme « rien à épingler »
    perdrait le runner exactement chez les projets assez soigneux pour poser une
    variable ;
  - **chemin, expansion, mot quoté ou échappé → silence**, jamais une ligne `-`
    (ce serait le défaut de [49] par une autre porte) ;
  - **déduplication dans `gate__path_manifest`** et pas dans les deux listes : un
    projet dont `TEST_CMD` commence par `git` aurait deux lignes pour un nom,
    donc `gate__path_moved` dirait deux fois le même mouvement sur un canal dont
    la conséquence est de refuser un successeur. Les noms du pack passent en
    premier pour que l'ordre de la liste de [52], que des tests lisent par
    position, ne bouge pas sous la configuration d'un projet.

  **`gate__path_where` est devenue `gate_path_where`.** Pas un goût : le second
  appelant est `scheduler_command`, et la règle du pack dit qu'un `__` à deux
  appelants est public (`layering.bats` refuse l'autre lecture). Le repli
  `/bin/bash` reste pour un `PATH` qui ne répond d'aucun `bash` — un job doit
  nommer un interpréteur, `-` n'en est pas un.

  **Écart de write-surface, assumé et consigné** : `test/scheduler.bats` a été
  ajouté. Les deux tests de run réel (`bash` planté, runner du projet planté)
  ont besoin de `sched_all_clear`/`sched_weekly_wall`/`sched_soon`, qui sont
  locaux à ce fichier, et les recopier dans `test/gate.bats` aurait été un second
  endroit où la mise en scène peut dériver de ce qu'elle met en scène — l'argument
  que `harness.bash` fait déjà pour `hold_open_guard` et `write_middle_shell`.

  **Ce qui a été corrigé chez le voisin** : la mutation `52 the binary that owns
  both halves of the judgement is not watched` s'ancrait sur
  `    git claude at systemd-run` et aurait DRIFTÉ en silence ; elle est
  ré-ancrée. Idem pour `52 the witness asks this shell's hash table` après le
  renommage.

  **Pièges de mise en scène, pour la suite** : un enregistreur nommé `bash` doit
  avoir un shebang **absolu** (`#!/bin/bash` + `exec /bin/bash "$@"`) — sinon il
  se re-résout par le `PATH` dont il est en tête et récurse. Une assertion sur la
  ligne du successeur ne doit pas exiger d'espace après le chemin du shell :
  `scheduler__quote` le rend entre apostrophes.

  **Ce que [92] hérite** : `bash` est maintenant épinglé, donc un survivant de
  session qui voudrait posséder l'interpréteur du gate coûte le successeur — mais
  **rien n'a changé pour un survivant qui écrit les `.rc`** : [91] ferme la porte
  du *nom*, [92] doit fermer celle du *canal*. Et la nouvelle liste de 35 noms
  rend la ligne 35 du tableau plus large à réécrire, pas moins.
