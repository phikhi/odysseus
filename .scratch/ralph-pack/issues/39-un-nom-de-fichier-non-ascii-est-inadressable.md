# 39 — Un nom de fichier non-ASCII est C-quoté, donc inadressable

**What to build:** Rendre les listes de chemins du pack utilisables quand un chemin sort de l'ASCII. `git diff-tree --name-only` et `--name-status` **C-quotent** tout nom qui n'est pas ASCII pur (`core.quotePath`, vrai par défaut) : `docs/spécification.md` sort de `gate_changed_files` sous la forme `"docs/sp\303\251cification.md"`, guillemets compris — et cette chaîne n'est un chemin pour aucun des quatre consommateurs de la liste.

**Blocked by:** None

**Write-surface:** `.claude/lib/gate.sh`, `.claude/lib/failures.sh`, `.claude/lib/lang.sh`, `.claude/lib/concurrency.sh`, `test/gate.bats`, `test/failures.bats`, `test/lang.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** resolved

- [x] Un fichier dont le nom porte un caractère non-ASCII est jugé par le scope-guard **sur son vrai nom** : déclaré dans la write-surface il passe, hors surface il est rouge en le nommant lisiblement.
- [x] Une itération verte qui a écrit un tel fichier le **commite** — aujourd'hui `failures_make_durable` échoue en silence dessus.
- [x] Un rollback qui prétend avoir retiré un tel fichier l'a réellement retiré, ou dit qu'il n'a pas pu. Pas d'intention rendue pour un résultat ([30]).
- [x] Le cas du nom portant un **saut de ligne** est tranché explicitement : soit fermé (`-z`, et alors la convention « un chemin par ligne » de [33] est à revoir de bout en bout), soit nommé comme une limite dans `docs/frontiere-de-confiance.md`. Pas laissé implicite.
- [x] Le compte que [17] a posé (`could not address N path(s)`) disparaît ou change de sens : il existe parce que ce ticket n'était pas livré.

## Comments

- **Origine : livraison de [17], le 05/08/2026**, en sondant le gate de langue sur des noms réels. C'est une trouvaille de production et pas de harnais, et elle touche quatre mécanismes d'un coup. Toutes les sondes ci-dessous ont été rejouées dans un dépôt jetable le 05/08/2026, avec `docs/spécification.md` :

  | Sonde | Résultat |
  |---|---|
  | `git diff-tree -r --name-only` | `"docs/sp\303\251cification.md"` — guillemets inclus |
  | `git -c core.quotePath=false diff-tree -r --name-only` | `docs/spécification.md` |
  | `git cat-file -e "$tree:<quoté>"` | `fatal: path … does not exist` |
  | `git add -A -- <quoté>` | `fatal: pathspec … did not match any files` |
  | `rm -f <quoté>` | ne retire rien, et ne dit rien |
  | `git checkout-index -f -- <quoté>` | `… is not in the cache` |

- **Ce que ça donne chez les quatre consommateurs.** Le **scope-guard** compare la chaîne quotée à la write-surface : `docs/*` ne matche pas `"docs/sp\303\...`, donc rouge — pour une raison qu'aucun humain ne peut corriger autrement qu'en renommant son fichier. Mais un ticket dont la surface est `*` matche la chaîne quotée comme n'importe quelle autre, donc **le vert est atteignable** et la suite compte. `failures_make_durable` fait `git add -A -- $changed` derrière un `|| true` : le fichier approuvé par le gate n'est **jamais commité**, en silence. `gate_restore_tree` fait `rm -f "$path"` pour un `A` puis **imprime le chemin comme restauré quoi qu'il arrive** : le rollback annonce avoir retiré un fichier qui est toujours là — c'est exactement « un contrôle qui rend compte de son intention et non de son résultat », la leçon que [30] a payée sur `core.excludesFile`, sur un autre mécanisme. Le `checkout-index` d'un `M` est le seul des trois qui soit bruyant : il journalise `could not restore`.

- **Le correctif candidat tient en deux `-c`, et c'est le piège.** `git -c core.quotePath=false` sur les deux lecteurs rend les vrais noms, et rien en aval n'a besoin de changer. Ce que ça **ne** ferme pas : un nom qui porte un saut de ligne casse toute liste lue ligne par ligne, et la vraie réponse à celui-là est `-z`, qui change la forme de chaque liste du pack — donc la convention tranchée par [33] (« un chemin par ligne, partout »). Le ticket doit choisir et l'écrire, pas livrer le `-c` en laissant croire que la famille est fermée.

- **Contrainte héritée de [33] : deux mécanismes qui se partagent une liste doivent la découper *et* l'interpréter pareil.** Ici la liste est la même et le format change sous les deux moitiés à la fois, donc le risque est le contraire du précédent : un correctif posé sur `gate_changed_files` seul laisserait `gate_restore_tree` sur les noms quotés, et le rollback continuerait de mentir pendant que le scope-guard dirait vrai.

- **Ce que [17] a fait en attendant, et qu'il faudra défaire.** `lang_check` reconnaît un chemin C-quoté à ses guillemets, ne le juge pas, et le **compte** dans sa ligne de couverture (`could not address N path(s)`). Fail-open assumé et visible : rougir un projet francophone parce qu'un de ses fichiers s'appelle `spécification.md` serait le rouge sur du travail honnête que ce gate existe pour éviter. Quand ce ticket-ci est livré, ce compte doit tomber à zéro par construction — c'est le critère de sortie le plus simple à vérifier.

---

## Livraison, le 27/08/2026

### La décision sur le saut de ligne : pas de `-z`, et pourquoi ce n'est pas de la paresse

Sondé avant d'écrire, dans un dépôt jetable, sur quatre noms à la fois (`spécification.md`, `a<TAB>tab.md`, `new<LF>line.md`, `my dir.md`) :

| | défaut | `core.quotePath=false` |
|---|---|---|
| accent | `"docs/sp\303\251cification.md"` | `docs/spécification.md` |
| tabulation | `"docs/a\ttab.md"` | `"docs/a\ttab.md"` |
| saut de ligne | `"docs/new\nline.md"` | `"docs/new\nline.md"` |
| espace | `docs/my dir.md` | `docs/my dir.md` |

**C'est le sondage qui a tranché le ticket.** `core.quotePath=false` ne débraye que l'échappement des octets hors ASCII ; git continue de citer un nom portant un caractère qu'il ne sait pas montrer tel quel. Donc :

- la famille non-ASCII est **fermée** — les noms arrivent tels quels chez tous les consommateurs ;
- le résidu (saut de ligne, tabulation, guillemet, contre-oblique) arrive **sur une seule ligne, entre guillemets**. Il ne coupe donc *jamais* une liste en silence : la convention « un chemin par ligne » de [33] tient telle quelle, et c'est le quotage de git lui-même qui la protège ;
- ce résidu arrive comme quelque chose que personne ne sait adresser, ce qui est une chose que chaque consommateur peut **refuser à voix haute**.

`-z` rendrait ce résidu adressable et rendrait NUL-séparée **chaque** liste du pack — la convention de [33], dans neuf lecteurs, pour un nom qu'aucun projet n'a. Refusé, écrit comme un choix dans `docs/frontiere-de-confiance.md` avec son prix, et le propriétaire si la décision doit changer est ce ticket.

### Ce qui a été livré

Un producteur, un prédicat, et six consommateurs remis d'aplomb.

- **`gate_unaddressable`** (`gate.sh`, public) : le prédicat « git a dû citer ce nom ». Public parce que trois modules le lisent — le scope-guard rougit dessus, la restauration refuse de prétendre l'avoir remis, le gate de langue le compte.
- **`core.quotePath=false`** sur **les trois** producteurs de liste de chemins, et pas seulement sur les deux que le ticket nommait : `gate_changed_files`, `gate_restore_tree` (`--name-status`), **et `gate_unjudged_changes`** — le cinquième lecteur, qui alimente la ligne de zone « ce que ce gate a écrit après l'arbre qu'il a jugé » et, à travers elle, la containment de ce qu'une lentille écrit ([06]). Plus `failures_protect_tracker`, pour un nom de ticket accentué.
- **Le scope-guard refuse un nom inadressable avant toute comparaison**, `class=internal`, retryable — renommer le fichier est un travail qu'une session sait faire. Placé **avant** le scellement et avant la surface : une chaîne citée ne se compare à aucun motif, et les deux réponses possibles étaient fausses dans le même sens (une surface `*` la matchait, puis le commit durable laissait le fichier de côté en silence).
- **La restauration rend compte de son résultat** : un nom inadressable est confessé au lieu d'être imprimé comme remis ; un `A` dont le `rm -f` n'a rien retiré est confessé aussi (`rm -f` rend 0 pour un chemin qu'il n'a pas retiré) ; un `checkout-index` en échec n'est plus imprimé comme restauré.
- **Le commit durable vérifie ce qui a atterri**, et pas le statut de `git add` — qui est sous un `|| true` par nécessité. Les chemins qui diffèrent encore entre l'arbre à commiter et l'arbre jugé, **nettés contre la liste approuvée**, sont nommés un par un.
- **Trois rejointures de liste supprimées** (voir ci-dessous), dans `failures_make_durable` (deux) , `failures_rollback` et `concurrency__refresh`, plus la clôture de mots de `failures__minus`.
- **`lang_check`** lit le prédicat partagé au lieu de sa propre copie ; son compte est zéro par construction pour la famille non-ASCII et désigne maintenant le résidu.

### Les trouvailles, c'est-à-dire ce que le ticket ne savait pas

1. **`gate__gap` écrivait dans le canal qui sert à rendre les résultats.** `gate_restore_tree` rend sa liste de chemins remis **sur stdout**, et ses deux appelants la lisent par substitution de commande ; `gate__gap` passe par `gate__log`, qui `printf` sur stdout. Un `could not restore x` atterrissait donc **dans la liste** comme s'il était un chemin remis : compté dans `rolled back N path(s)`, passé au désindexage comme pathspec, et netté hors de la ligne « ce que ce rollback n'a pas pu défaire ». Défaut **antérieur à ce ticket** (le `could not restore` du `checkout-index` existait depuis [07]) et que ce ticket aurait aggravé en ajoutant deux confessions de plus. Corrigé par `>&2` aux trois points, exactement comme `gate_tree_snapshot` deux fonctions plus haut. Entrée de mutation dédiée.

2. **[33] a converti les découpages, pas les rejointures.** Quatre lecteurs recollaient la liste :
   - `failures_make_durable` : `git add -A -- $changed`, une seule fois pour tout. Et **`git add` refuse l'appel entier** quand un pathspec ne matche rien (sondé, rc=128), donc un seul `src/my file.txt` faisait qu'une itération verte ne commitait **rien du tout** — arbre reconstruit identique à `HEAD`, retour anticipé « tout est déjà dans HEAD », ticket `resolved`, zéro fichier dans l'historique, zéro ligne à ce sujet. C'est le pire des trois.
   - `failures_make_durable`, deuxième moitié : le restage de l'index de l'appelant, même découpage.
   - `failures_rollback` : `git reset -q -- $paths`. Ici **`git reset` ne casse pas l'appel entier** (sondé) — il laisse le mauvais pathspec et fait le reste. Le défaut est donc local : le fichier à espace restait indexé, avec `rolled back 2 path(s)` imprimé par-dessus.
   - `concurrency__refresh` (module `concurrency.sh`, hors de la surface d'origine) : la marche lit la liste ligne par ligne, puis la dernière commande la recolle par `tr '\n' ' '`. Résultat exact : un chemin livré est bien réécrit dans l'arbre principal par la boucle **et laissé indexé comme une suppression** par cette ligne — précisément l'état que cette fonction existe pour empêcher, et un `git commit -a` d'un humain au matin défaisait la nuit sur ce fichier.

   Plus une **clôture de mots** dans `failures__minus`, dont le commentaire assumait par écrit l'hypothèse fausse (« un chemin avec une espace n'est pas un chemin que cette boucle peut porter ») : une clôture de mots ne rate pas un nom à espace, elle répond oui pour *chacun de ses mots* ([37]), donc un chemin sans rapport nommé comme l'un de ces mots sortait de la ligne « ce que ce rollback n'a pas pu défaire ».

3. **Un chemin approuvé que `git add` refuse est perdu en silence, et ça dépasse les noms bizarres.** Cas armé, testé : un projet qui `gitignore` un répertoire que son propre `GUARDED_PATHS` nomme. Le snapshot le force dans l'arbre jugé, le gate l'approuve, `git add` sans `-f` refuse un chemin ignoré — itération verte, ticket `resolved`, fichier absent de l'historique. **Ce ticket le nomme, il ne le commite pas** : forcer serait changer ce qu'une itération verte commite dans tout projet à `.gitignore` fourni, et c'est une décision à prendre pour elle-même. Ligne de gap par chemin, ligne au tableau de confiance. **Ouvert comme [50]**, validé par Philippe le 27/08/2026. Le cas armé du défaut n'est d'ailleurs pas `vendor/` : `GUARDED_PATHS` vaut `.claude` par défaut, et un projet qui ignore `.claude/` — ce que font des projets réels — ne reçoit jamais le code que la boucle lui livre.

4. **Un `VACUOUS` qui était un problème d'observabilité, pas un test qui ment.** L'entrée de mutation du restage d'index nommait le test bout en bout : vert sans la ligne. Diagnostic avant réécriture ([47]) : depuis [13] le commit durable tourne dans un **worktree jetable**, donc l'index qu'il remet part avec le worktree et aucune assertion de boucle complète ne peut voir cette ligne — le vert venait de `concurrency__refresh`, un module plus loin, qui portait la même faute. Réponse : descendre le test au module (`failures_make_durable` piloté directement dans `PROJECT_DIR`), et une entrée séparée pour `concurrency__refresh`.

### Écarts de write-surface

La surface déclarée par le ticket (`gate.sh`, `failures.sh`, `test/gate.bats`, `test/failures.bats`) ne permettait d'atteindre **aucun** des trois derniers AC. Élargie, et chaque ajout se justifie par un AC :

- `.claude/lib/lang.sh` + `test/lang.bats` — AC 5 : le compte de [17] vit là, et le test qui l'assertait **devient rouge** dès que le producteur ne cite plus (c'est le critère de sortie qui se voit) ;
- `docs/frontiere-de-confiance.md` — AC 4, qui nomme le fichier ;
- `test/mutate.sh` — étape 1 de la definition of done ;
- `.claude/lib/concurrency.sh` — trouvaille 2, quatrième rejointure, avec son test et son entrée de mutation.

### Ce qui reste, et pour qui

- **`lenses.sh:544`** : `git diff-tree -p --no-color "$base" "$tree" -- "$file"` prend le chemin comme **pathspec**, donc comme un motif. Un fichier réellement nommé `src/zone[1].ts` montrerait à une lentille le diff de `src/zone1.ts`. Le correctif est `:(literal)`, un caractère ; il n'est **pas** livré ici parce que ni `lenses.sh` ni `lenses.bats` ne sont dans la surface et qu'aucune mutation ne pourrait le rendre rouge — livrer une réparation que rien ne mesure est une phrase dans un tableau, pas du code. Famille [33]/[34], propriétaire [06]. **Ouvert comme [51]**, validé par Philippe le 27/08/2026.
- **Le résidu quoté reste un refus, pas une capacité.** Un projet qui a réellement besoin d'un nom à saut de ligne n'est pas servi par ce pack, et la ligne du tableau dit ce que ça coûterait.
- **[48]** (un nom de ticket qui porte un saut de ligne) hérite directement de la ligne du tableau : le tracker lit `issues/` par `diff-tree --name-status`, qui passe maintenant `core.quotePath=false`, donc un ticket **accentué** est adressable ; un ticket à saut de ligne reste cité et c'est [48] qui décide quoi en faire.

### Un détail trouvé en écrivant le tableau

La ligne « Rester dans la write-surface déclarée » de `docs/frontiere-de-confiance.md`
portait un `` `|| true` `` **non échappé** depuis [33] : dans un tableau markdown un
`|` coupe la cellule, code span compris, donc cette ligne — la première du document,
celle du scope-guard — se rendait en cinq colonnes depuis. Corrigé en `` `\|\| true` ``,
et les 60 lignes de tableau du fichier ont été vérifiées d'un coup (aucune autre).

### Sondes conservées

Aucune sonde jetable n'a survécu à ce ticket : les six sondes du 05/08 et les quatre du 27/08 (les quatre noms × deux réglages, `checkout-index` avec et sans magie de pathspec, `git add` sur un pathspec vide, `git reset` sur un pathspec vide) sont toutes devenues des tests ou des lignes de commentaire à l'endroit qu'elles expliquent.

### Huit entrées d'autres tickets recalées, et pourquoi c'est le résultat attendu

La passe complète a rendu **8 `not ok`, tous `DRIFTED`, aucun `VACUOUS`, aucun `BROKEN`** :
ce ticket a bougé huit lignes sous les ancres d'autres tickets. Chacune a été vérifiée
comme *encore portée* avant d'être recalée — c'est l'ordre que la definition of done
impose, et c'est ce qui distingue un recalage d'un silence :

| Entrée | Ce qui a bougé | Garantie revérifiée |
|---|---|---|
| `05 the loop's own writes trip the scope-guard` | le `\| gate__drop_bookkeeping` est passé en ligne de continuation | le filtre est toujours là |
| `05 the tree diff is not recursive` | `git diff-tree` est devenu `git -c core.quotePath=false diff-tree` | le `-r` est toujours là ; ancre raccourcie à `diff-tree -r --name-only "$base" "$now"`, vérifiée unique |
| `29 the diff of what the gate changed is not recursive` | idem sur `"$judged" "$now"` | idem |
| `29 the loop's own bookkeeping counts as a gate write` | idem, ligne de continuation | idem |
| `07 a file the session deleted is not restored` | le `checkout-index \|\| gap` est devenu un `if ! …; then gap >&2; continue; fi` | la restauration d'un `D` est toujours là |
| `07 what the session staged stays staged` | le `git reset` est entré dans la boucle avec `:(literal)` | le désindexage est toujours là |
| `07 the durable commit takes the whole tree` | le `git add` unique est devenu un `git add` par chemin | le commit est toujours **borné** à ce que le gate a approuvé |
| `29 a path the rollback put back is named as one it could not` | la clôture de mots de `failures__minus` a disparu | la garantie a changé de **porteur** : ce n'est plus une clôture qu'on vide, c'est la ligne qui consulte la liste. Entrée réécrite sur `! failures__in_list … \|\| continue` |

Le dernier est le cas que ce dépôt connaît sous un autre nom (« une garantie peut
gagner un second propriétaire ») dans sa forme inverse : la garantie a gardé son
propriétaire et **perdu la ligne** par laquelle on la retirait. Une entrée qu'on aurait
« réparée » en blanchissant une autre ligne aurait été verte pour une autre raison.

### Gates

- `bash test/run.sh` = **533 tests, 0 failures, 6 skips**. 533 = 522 + 11 : 3 dans
  `gate.bats`, 7 dans `failures.bats`, et **+1 net** dans `lang.bats` — le test « a name
  git prints quoted is counted, not judged » de [17] a été réécrit en deux, un par côté
  de la frontière que ce ticket déplace.
- `bash test/mutate.sh` = **506 mutations**. 506 = 494 + 12 entrées `39 …`. Première
  passe : 8 `DRIFTED` (ci-dessus), 0 `VACUOUS`, 0 `BROKEN`. Après recalage, passe
  complète rejouée : 0 `not ok`.
- Les 12 entrées `39 …` ont chacune été vues `ok` en passe ciblée, et deux d'entre
  elles ont d'abord rendu `VACUOUS` — voir les trouvailles 2 et 4 : ce sont ces deux
  `VACUOUS` qui ont trouvé le trou du chemin à espace et celui de
  `concurrency__refresh`.

## Relu par [50], le 30/08/2026 — la ligne de gap lit deux choses au lieu d'une

Ce ticket a eu raison de refuser d'asserter le **statut** du `git add` (un chemin que la
session a supprimé d'un arbre jamais commité ne matche rien des deux côtés), et il a
posé le contrôle sur le **résultat** seul. Le résultat seul accuse la suite de tests du
projet : `TEST_CMD` tourne après que l'arbre a été jugé, donc un fichier livré qu'elle
réécrit diffère de l'arbre jugé tout en étant dans le commit avec des octets plus
récents. C'est une trouvaille, mais celle de `gate_unjudged_changes`, qui la nomme déjà
à chaque itération et à qui le pack refuse explicitement d'en faire un verdict.

`failures_make_durable` retient donc maintenant les chemins dont le `git add` a échoué
(`refused`) et n'accuse que ceux qui **diffèrent aussi** de l'arbre jugé. Les deux
moitiés ont chacune leur test et leur entrée de mutation. Le cas le plus bruyant de
cette ligne a par ailleurs disparu plutôt que d'être adouci : depuis [50] le staging
force, donc un chemin gardé qu'un projet ignore est commité au lieu d'être nommé ici.

Et deux entrées de mutation de ce ticket ont dû être ré-ancrées (`--force` ajouté au
corps de boucle). Le premier jet les recalibrait en rejoignant la liste en un mot ;
l'une est sortie **VACUOUS sur un test sain**, parce que
`$(printf '%s' "$changed" | tr '\n' ' ')` est un **no-op sur une liste à un seul
élément** — `$changed` n'a pas de saut de ligne final — et le test module qui la nomme
ne change qu'un chemin. Les deux sont revenues au découpage en mots, et le commentaire
de `failures.sh` est passé au-dessus de la boucle pour que le corps reste ancrable.
