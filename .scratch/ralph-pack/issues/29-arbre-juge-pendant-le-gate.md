# 29 — Le scope-guard juge un arbre qu'il prend pendant que le gate écrit déjà

**What to build:** Faire juger l'itération sur un arbre pris **avant** que le gate ne lance quoi que ce soit. Aujourd'hui `gate__scope_guard` prend son propre snapshot *depuis sa branche*, c'est-à-dire en parallèle de la suite de tests et du type-check que `gate_run` vient de démarrer. Le verdict de scope dépend donc de qui a écrit le premier : un artefact que la suite dépose avant le snapshot est imputé à la session, un artefact déposé après n'est ni jugé ni défait par le rollback. Même ticket, même session, deux verdicts.

**Blocked by:** None

**Write-surface:** `.claude/lib/gate.sh`, `.claude/lib/failures.sh`, `test/gate.bats`, `test/failures.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`, `README.md`

**Status:** resolved

- [x] Le tree jugé est pris une seule fois, dans `gate_run`, **avant** le premier `gate__start`, et passé au scope-guard au lieu de lui faire calculer le sien. Un test prouve qu'un fichier écrit par `TEST_CMD` — quel que soit son délai — ne change plus le verdict de scope. *`RALPH_GATE_TREE="$(gate_tree_snapshot)"` avant le fan ; `gate__scope_guard` prend l'arbre en troisième argument et **refuse** de passer si on ne lui en donne pas, au lieu de retomber sur `gate_changed_files` qui en recalculerait un.*
- [x] Le verdict ne dépend plus d'un délai : la sonde 7b et la sonde 7 ci-dessous rendent le **même** verdict, et un test le montre avec les deux `TEST_CMD` (immédiat / retardé). *Deux tests appariés dans `test/gate.bats`, `printf` immédiat et `sleep 2; printf` — vert des deux côtés.*
- [x] `RALPH_GATE_TREE` est renseignée avant le fan, donc lisible par une branche. C'est la correction que [06] porte déjà dans ses commentaires : elle est déplacée ici, et [06] l'hérite au lieu de la refaire. *Testé au seam par lequel passe toute branche : un wrapper autour de `gate__start` enregistre ce que chaque branche hérite — trois branches, même arbre non vide, celui que le gate rapporte ensuite.*
- [x] Ce que le gate lui-même a écrit pendant qu'il jugeait est **nommé**, sur le modèle de la zone ignorée de [24] : le rollback ne le défait pas, et « l'arbre est remis où la session l'a trouvé » ne doit pas rester vrai à l'exception d'un ensemble de chemins que personne n'énumère. Deuxième exemption non énumérée du rollback, la première étant la zone ignorée. *Troisième, en comptant le tracker. `gate_unjudged_changes` énumère, `gate_zone_line` (public, quatre lecteurs) formate, deux lignes le disent — dont celle du rollback, nette de ce qu'il a remis.*
- [x] Le cas armé est couvert : un artefact de la suite qui tombe dans la write-surface d'un **autre** ticket ne peut plus escalader le ticket en cours en `decision`. *La surface de l'autre ticket est celle de `04-claimed`, tenue hors frontière par un claim réellement vivant : le ticket existe pour l'attribution sans jamais être broyé.*

## Comments

- **Origine : passe transversale 24→26, le 30/07/2026.** Trouvé en posant la question 4 sur `gate_run` — que le gate lui-même laisse-t-il derrière lui ? Trois sondes, trois faces d'une même cause.

  *Sonde 7 — ce que la suite écrit après le snapshot n'est ni jugé ni défait.* `TEST_CMD='sleep 2; printf late >late-artifact.txt; exit 1'`, une session qui n'écrit que dans sa surface :

  ```
  ralph: gate: 01-alpha: tests=red typecheck=green scope=green
  ralph: rolled back 1 path(s) the session touched
  late-artifact.txt survives: yes        src/alpha.txt undone: yes
  ```

  Le fichier n'est pas ignoré par git : la ligne de zone de [24] ne le nomme donc pas, et rien d'autre ne le nomme. Il est là pour l'itération suivante, dont il fera partie du snapshot `base` — laundering complet.

  *Sonde 7b — le même fichier, écrit tout de suite, retourne le verdict.* `TEST_CMD='printf early >late-artifact.txt; exit 0'`, tout le reste identique :

  ```
  ralph: gate: 01-alpha: tests=green typecheck=green scope=red
    wrote late-artifact.txt, outside the declared write-surface
  ```

  Le scope-guard est la **troisième** branche démarrée ; son snapshot tombe donc après le début de la suite. Une suite qui écrit un rapport de couverture, un snapshot de test mis à jour, un `.log` — c'est-à-dire beaucoup de suites — rend le verdict de scope non déterministe. Un contrôle qui prend son entrée pendant que d'autres processus écrivent l'arbre ne rend pas un verdict, il rend un tirage.

  *Sonde 10 — et le tirage peut être définitif.* Le même artefact, mais dans la surface d'un autre ticket : `TEST_CMD='mkdir -p src; printf artefact >src/beta.txt; exit 0'` pendant que `01-alpha` est jugé, `02-beta` déclarant `src/beta.txt` :

  ```
  wrote src/beta.txt, inside the write-surface of 02-beta (drift)
  ralph: scope overflow on 01-alpha: contract
  01-alpha -> ready-for-human   Failures: []   Escalation: decision
  ```

  La classe `contract` est **délibérément non retryable** ([07]) : « deux tickets ont été dessinés sur un fichier, un retry n'y changera rien ». Ici les deux tickets sont disjoints et la session n'a rien fait de mal — c'est la suite de tests du projet qui a écrit. Le ticket part au puits humain sans consommer de retry, avec une raison fausse, et rien ne l'en fera revenir.

- **Le correctif est déjà écrit ailleurs, et c'est ce qui rend ce ticket petit.** La passe précédente avait noté dans [06] que `gate_changed_files "$base" "$RALPH_GATE_TREE"` est inapplicable depuis une branche, parce que `gate_run` vide les `RALPH_GATE_*` avant le fan et ne les remplit qu'après la collecte — et que le correctif est de **hisser le snapshot avant le fan**. Ce qui n'avait pas été vu : ce hissage n'est pas un confort pour les lentilles, c'est la correction d'un verdict non déterministe et d'une exemption silencieuse du rollback. Il change donc de propriétaire : ici, avant [06], parce que le défaut existe aujourd'hui sans lentille.

- **Ce que le hissage ne referme pas, et qu'il faut nommer plutôt que taire.** Après le hissage, un artefact que le gate écrit pendant qu'il juge est toujours dans l'arbre à la fin de l'itération, et le rollback ne le défait toujours pas — il n'est dans aucun des deux trees qu'il diffe. La différence est qu'il devient **déterministe** et **attribuable** : ce n'est plus « peut-être la session, peut-être la suite », c'est « ce que le gate a écrit ». C'est exactement le traitement que [24] a inventé pour la zone ignorée, et c'est la seconde moitié de ce ticket : une ligne qui dit ce que le rollback n'a pas pu défaire *parce que ça n'existait pas encore quand l'arbre a été pris*.

  Piège à ne pas répéter : la ligne ne doit pas devenir un verdict. Un projet dont la suite écrit un artefact à chaque run n'a rien fait de mal ; le rendre rouge, c'est refuser tout projet qui a un build — la même impasse que [24] a rencontrée sur la zone ignorée.

- **Piège de mesure, hérité de [24] et de [25].** La suite du dépôt utilise `stub-cmd` derrière `TEST_CMD`, qui rend la main immédiatement et n'écrit rien. Aucun test existant ne peut donc voir ce défaut : le seul moment où la fenêtre existe est celui où une branche écrit pendant que le scope-guard prend son arbre. Un test de ce ticket doit porter son `TEST_CMD` écrivant, dans les **deux** ordres, et le délai est porteur — sans lui, le test est un tirage au sort comme le code qu'il juge.

- **Contrainte pour [06].** Le registre de lentilles hérite du hissage et n'a plus à le faire. Deux conséquences à ne pas perdre : une lentille lit `RALPH_GATE_TREE` renseignée, donc juge le même arbre que le scope-guard ; et une lentille est elle-même une branche qui écrit (au minimum le flux de session `claude`), donc elle alimente précisément la ligne « ce que le gate a écrit » que ce ticket pose. Un flux de lentille qui atterrit dans l'arbre du projet est un cas de [19] (`.gitignore`), pas une exception à écrire ici.

- **Contrainte pour [10].** Le reçu d'audit héritera d'une troisième catégorie à porter, après « ce que le gate n'a pas jugé » (zone ignorée) et les verdicts : « ce que le gate a écrit et que le rollback n'a pas défait ». Trois exemptions, une seule promesse à ne pas laisser sonner complète.

## Livraison (30/07/2026)

- **Ce que le hissage change, en une phrase.** L'arbre jugé est pris dans `gate_run` avant le premier `gate__start` et posé dans `RALPH_GATE_TREE` **avant** le fan, puis passé au scope-guard. Toutes les branches parlent donc du même état du dépôt, et `failures_make_durable`, `failures_preserve_attempt` et `failures_rollback` — qui recevaient déjà `RALPH_GATE_TREE` — agissent maintenant sur un arbre qui est vraiment celui d'avant le gate, et non sur ce que la suite avait eu le temps d'écrire.

- **Le piège que le correctif ouvre, et qui a failli passer.** `gate_changed_files "$base" "$now"` recalcule son propre snapshot quand `$now` est vide. Un scope-guard à qui l'on ne donne pas d'arbre y retombe donc **en silence**, et le tirage revient par la porte de service : même code, même défaut, une indirection plus loin. Le guard refuse explicitement un arbre vide (`[ -z "$now" ] ||`), et la mutation `29 a scope-guard handed no tree recomputes one instead of refusing` la tient. C'est la leçon de [25] sous une autre forme : la primitive qu'on répare ailleurs a un appelant qui la rappelle.

- **Ce qu'il ne faut pas croire sur la ligne du rollback : elle doit être nette.** Une première version listait tout ce qui différait de l'arbre jugé. Or une suite qui réécrit un fichier que la session avait aussi touché — snapshot de test mis à jour, formateur, générateur — produit exactement ce diff-là, et ce chemin **est** restauré depuis le snapshot pré-session, comme n'importe quel autre chemin du diff du rollback. L'annoncer comme « non défait » envoie un humain chercher un artefact qui n'existe pas : le même demi-mensonge que [24] a refusé, dans l'autre sens. `failures__minus` retire donc ce que le rollback a effectivement remis, et le test qui le tient est une **réfutation** (aucune ligne du tout), avec sa mutation par vidage de la fence.

  Conséquence agréable et contre-intuitive : cette soustraction rend l'**instant** du calcul indifférent. Remettre un chemin en place le fait différer de l'arbre jugé, mais ce chemin est dans la liste de ce qui a été défait par construction — donc lire la liste avant ou après les restaurations donne le même résultat. La première version prenait la liste en tête de fonction avec un commentaire expliquant pourquoi c'était nécessaire ; ça ne l'était pas, et une garantie qu'aucune mutation ne peut isoler n'a pas à être revendiquée. Le calcul vit dans le rapporteur, un seul endroit, comme `gate_ignored_zone`.

- **Le verbe des deux lignes est `changed`, pas `wrote`, et ce n'est pas un détail de style.** `git diff-tree --name-only` liste aussi les **suppressions**, et un `rm -rf dist/ && build` est un `TEST_CMD` ordinaire. Une ligne qui annonce « the gate wrote `dist/old.js` » envoie un humain constater que le fichier n'est pas là et conclure que la ligne n'est pas fiable — la panne exacte que ce dépôt traque. La fonction s'appelle donc `gate_unjudged_changes`. Corollaire pour la ligne verte : sur un gate vert, `failures_make_durable` commite le contenu de l'**arbre jugé**, donc un fichier que la suite a supprimé après le snapshot est commité tel que le gate l'a approuvé, et l'arbre garde une suppression non commitée. C'est le comportement voulu depuis [07] (« ce que la suite a déposé après ce snapshot n'est pas le travail de l'itération »), il est simplement devenu déterministe.

- **Coût mesurable, assumé : deux `gate_tree_snapshot` de plus par itération échouée.** `gate_unjudged_changes` prend un snapshot pour se comparer à l'arbre jugé, une fois dans le gate et une fois dans le rollback. Sur un gros dépôt c'est un `git add -A` de plus dans un index jetable à chaque appel, à côté des deux que la boucle et le gate faisaient déjà, et des deux `git ls-files --others --ignored` que [24] a ajoutés. Aucune mesure ne le rendait nécessaire de l'optimiser ici ; si ça devient un problème, le partage naturel est de calculer l'arbre post-gate une fois et de le passer, comme ce ticket vient de le faire pour l'arbre jugé.

- **Deux entrées de `mutate.sh` avaient dérivé, et c'est la bonne nouvelle.** `05 the tree is not re-read after the session` visait la ligne du snapshot *dans* le scope-guard : elle a bougé d'une couche, pas disparu, et l'entrée plante maintenant `RALPH_GATE_TREE="$base"` dans `gate_run`. `24 the rollback only reports when it undid something` visait l'appel à `failures__report_unrolled`, qui a gagné deux arguments. Les deux redeviennent `ok`. Une garantie dont la ligne porteuse bouge est exactement ce que `DRIFTED` existe pour signaler.

- **La trouvaille de ce ticket n'est pas dans `gate.sh`, elle est dans `mutate.sh` : une substitution sans `/g` a un ordre.** Le premier passage complet a rendu **deux `VACUOUS`** — `05 the loop's own writes trip the scope-guard` et `05 the tree diff is not recursive` — sur deux tests qui n'avaient rien perdu. Cause : `gate_unjudged_changes` est un second appelant de `gate__drop_bookkeeping` et un second `git diff-tree -r`, et il est défini **plus haut dans le fichier** que `gate_changed_files`. Les deux entrées visaient le token sans contexte suffisant, donc perl a édité proprement… l'autre fonction. La mutation s'appliquait, `bash -n` passait, et le test nommé restait vert en gardant sa garantie intacte.

  Trois choses à en retenir, dans l'ordre de danger :

  1. **Le symptôme dit le contraire de la cause.** `VACUOUS` veut dire « le test est un mensonge, le réécrire » — ici les deux tests étaient sains et la réponse correcte était de réparer l'ancre. Un agent pressé aurait « réparé » deux bons tests, ce qui aurait ajouté deux faux verts au lieu d'en retirer. `DRIFTED` n'a pas pu se déclencher : le diff n'était pas vide, il était simplement ailleurs.
  2. **Une ancre non unique est un faux vert en attente**, exactement comme une règle du prompt sans ligne dans le tableau. Elle est correcte le jour où on l'écrit et devient fausse quand quelqu'un ajoute un appelant — sans que rien ne le signale. Les deux entrées sont maintenant ancrées sur les arbres qu'elles prennent (`"$base" "$now"` contre `"$judged" "$now"`), donc sur une ligne et non sur un token.
  3. **La question de [25] s'applique à ce fichier aussi** : « combien d'endroits appellent ça ». Ajouter un appelant à une primitive oblige à relire les mutations qui visaient l'appelant existant. La leçon est écrite dans l'en-tête de `test/mutate.sh`, à côté des deux autres façons dont ce fichier a déjà menti.

  Corollaire livré avec : la couverture est devenue symétrique. Le nouveau diff a ses deux entrées à lui (`-r` et le bookkeeping), et pour que celle sur `-r` puisse rougir, la suite écrit désormais `build/coverage.xml` et non un fichier à la racine — un diff non récursif rapporterait `build` et se lirait comme couvert. C'est ce qu'un vrai projet fait de toute façon.

- **Piège de mesure, confirmé.** Aucun test existant ne pouvait voir ce défaut : `stub-cmd` rend la main tout de suite et n'écrit rien dans l'arbre, donc la fenêtre où deux processus écrivent ne s'ouvrait jamais. Les tests de ce ticket portent leur propre `TEST_CMD` écrivant, dans les deux ordres, et la mutation qui replante le défaut porte un `sleep 1` — sans lui, l'entrée de `mutate.sh` serait un tirage au sort, exactement le reproche fait au code qu'elle plante.

- **La question de la frontière de confiance, pour ce que ce ticket laisse ouvert.** Ce que les branches du gate écrivent n'est jugé par rien et défait par rien : c'est nommé, ce n'est pas empêché. Pourquoi c'est acceptable aujourd'hui : `TEST_CMD` et `TYPECHECK_CMD` viennent de `ralph.config.sh`, qui est **scellé** ([24]) — leurs écritures sont donc aussi dignes de confiance que la configuration du harnais elle-même. La chaîne casse à deux endroits déjà ouverts, et il faut les lire ensemble : [31] (un `RALPH_CONFIG` sous un autre nom n'est pas scellé, donc une session peut poser le `TEST_CMD` du run suivant) et [06] (une branche qui est un `claude` n'est pas la commande du projet). Écrit dans les deux tickets, et dans le tableau de `docs/frontiere-de-confiance.md`.

- **Ce que le ticket suivant hérite.** [06] hérite du hissage, plus une contrainte qui n'était pas dans ce ticket au départ : une lentille est une branche, donc ce qu'elle écrit tombe dans la zone que ce ticket vient de nommer — non jugée, non défaite, et blanchie dans le `base` de l'itération suivante. [10] hérite d'une troisième catégorie à porter. [13] hérite d'un argument de plus pour l'isolation : un worktree par itération ferait mourir l'artefact avec lui, ce qui referme le blanchiment par construction là où ce ticket ne peut que le nommer.
