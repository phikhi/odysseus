# 39 — Un nom de fichier non-ASCII est C-quoté, donc inadressable

**What to build:** Rendre les listes de chemins du pack utilisables quand un chemin sort de l'ASCII. `git diff-tree --name-only` et `--name-status` **C-quotent** tout nom qui n'est pas ASCII pur (`core.quotePath`, vrai par défaut) : `docs/spécification.md` sort de `gate_changed_files` sous la forme `"docs/sp\303\251cification.md"`, guillemets compris — et cette chaîne n'est un chemin pour aucun des quatre consommateurs de la liste.

**Blocked by:** None

**Write-surface:** `.claude/lib/gate.sh`, `.claude/lib/failures.sh`, `test/gate.bats`, `test/failures.bats`

**Status:** ready-for-agent

- [ ] Un fichier dont le nom porte un caractère non-ASCII est jugé par le scope-guard **sur son vrai nom** : déclaré dans la write-surface il passe, hors surface il est rouge en le nommant lisiblement.
- [ ] Une itération verte qui a écrit un tel fichier le **commite** — aujourd'hui `failures_make_durable` échoue en silence dessus.
- [ ] Un rollback qui prétend avoir retiré un tel fichier l'a réellement retiré, ou dit qu'il n'a pas pu. Pas d'intention rendue pour un résultat ([30]).
- [ ] Le cas du nom portant un **saut de ligne** est tranché explicitement : soit fermé (`-z`, et alors la convention « un chemin par ligne » de [33] est à revoir de bout en bout), soit nommé comme une limite dans `docs/frontiere-de-confiance.md`. Pas laissé implicite.
- [ ] Le compte que [17] a posé (`could not address N path(s)`) disparaît ou change de sens : il existe parce que ce ticket n'était pas livré.

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
