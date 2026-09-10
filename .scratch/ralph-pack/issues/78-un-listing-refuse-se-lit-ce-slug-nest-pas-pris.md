# 78 — Un listing refusé se lit « ce slug n'est pas pris »

**What to build:** Que `forge__slug_taken` cesse de lire un refus de listing comme une réponse, pour que `forge_open_unique` n'ouvre pas un doublon à chaque run d'un dépôt que le plafond de pages refuse.

**Blocked by:** None

**Write-surface:** `.claude/lib/forge.sh`, `test/tracker-remote.bats`, `test/mutate.sh`

**Status:** resolved

- [x] Un listing que l'adaptateur a refusé ne fait pas répondre « ce slug est libre » : `forge_open_unique` refuse plutôt que d'ouvrir.
- [x] Le refus se voit — un appelant qui ouvre un ticket unique sait que rien n'a été ouvert et pourquoi, sans lire un compteur.
- [x] `open_unique` garde exactement son comportement quand le listing répond : ouvre si le slug est libre, n'ouvre rien s'il est pris, et n'écrit rien de plus au registre de [13].

## Comments

- **Trouvé en livrant [76] (08/09/2026), laissé de côté par [74] (09/09/2026),
  et c'est la même règle que les deux** : un refus n'est pas une réponse ([59]).
  `forge__slug_taken` lit `forge__records` dans un heredoc avec `|| printf ''`,
  donc la liste vide qu'un refus produit se lit « aucun ticket ne porte ce slug »
  et `forge_open_unique` ouvre. Le garde de [47] — la question et l'écriture du
  même côté d'un verrou — tient toujours ; ce qui ne tient pas est la question.

- **Pourquoi ça compte plus depuis [76]** : le refus n'a plus besoin d'une panne.
  `forge__listing` refuse quand il atteint son plafond (`FORGE_PAGES`, 20, sur des
  pages de `FORGE_PAGE`, 100), donc un dépôt de plus de 2 000 issues refuse
  **tous** les listings, à tous les coups. Chaque `retro-*` et chaque
  `capability-*` censé être ouvert une seule fois est alors rouvert à chaque run,
  sur le tracker d'un humain, sans qu'aucune ligne ne le dise.

- **Ce que [74] a livré et qui sert de précédent** : deux codes de retour de
  l'interface, lus, sans que rien n'apprenne ce qu'est un backend — le statut du
  listing sort du heredoc (`x="$(…)" || return 1`), et l'appelant décide. Ici
  l'appelant est dans l'adaptateur, donc la décision est locale : `open_unique`
  n'a pas de canal pour dire « je n'ai pas pu savoir », et sa signature dit
  qu'un id vide veut dire « déjà pris ». Ne pas confondre les deux est la
  question de conception du ticket, pas un détail d'implémentation.

- **Le piège du harnais**, mesuré par [74] : le faux forge sert de vraies pages, et
  `FORGE_PAGE`/`FORGE_PAGES` sont des clés déclarées, donc désarmées par
  `harness__clear_env`. `set_config FORGE_PAGE 2` + `set_config FORGE_PAGES 1` avec
  deux issues suffit à faire refuser **tous** les listings d'un run, ce qui est la
  façon la moins chère de mettre en scène ce défaut sans simuler de panne.

## Place dans la file

**Placé par Philippe le 09/09/2026, juste après [77]** : la file devient
**[77] → [78] → [75] → [73] → [19]**. Le critère est celui du dépôt — minimiser la
reprise, jamais l'urgence : [77] et [78] touchent tous deux `forge.sh` et
`test/tracker-remote.bats`, donc les livrer voisins économise une relecture du même
fichier, et [78] est la plus petite des deux surfaces.

**`Blocked by:` reste `None`, et c'est une décision.** Rien de [78] ne dépend de
[77] : la position dans la file est un choix d'ordonnancement, pas une dépendance,
et écrire une fausse arête ferait sortir ce ticket de la frontière si [77] était
mis de côté. Ce qui suit [78] ne change pas non plus — `[75] 77`, `[73] 74, 75,
77`, `[19] 73, 74, 75, 76, 77`.

## Livraison (10/09/2026)

- **Ce qui a changé, en deux lignes.** `forge__open` lit le listing **sur une
  ligne à lui** — `records="$(forge__records "$flavour")" || { … return 1; }` —
  et `forge__slug_taken` prend désormais `RECORDS SLUG` au lieu de
  `FLAVOUR SLUG` : elle scanne des lignes et ne va plus rien chercher. Un refus
  n'a donc plus de chemin pour arriver dans le scan sous la forme d'une liste
  vide. C'est le précédent de [74] appliqué un étage plus bas — le statut sort du
  heredoc, l'appelant tranche — et l'appelant est ici dans l'adaptateur.

- **Pourquoi la réparation n'est pas un troisième code de retour de
  `forge__slug_taken`.** Les deux formes marchent ; celle-ci retire la
  *possibilité* du défaut au lieu de l'encoder. Une fonction qui lit un tracker
  dans le heredoc qui l'alimente n'a que deux réponses à sa disposition — « une
  ligne a matché » et « aucune ligne n'a matché » — et un refus n'est ni l'une ni
  l'autre : il sera toujours la seconde. En lui passant les enregistrements, la
  question qu'elle tranche redevient exactement celle qu'elle sait trancher.

- **Le canal du refus, et pourquoi il n'y en avait pas.** La signature
  d'`open_unique` dit qu'un stdout **vide** veut dire « une est déjà là », ce qui
  est un succès ; il n'y a pas de troisième chose à imprimer sans changer
  d'opération. Le refus part donc en **statut non nul** — porté intact par
  `tracker__dispatch`, qui fait `out="$("$fn" "$@")" || rc=$?` puis
  `return "$rc"` — plus une phrase nommant le slug et la cause. Et il n'écrit
  **rien** au registre de [13] : `tracker__note_write` n'écrit pas de ligne pour
  un id vide, ce qui est correct, une création qui n'a pas eu lieu n'étant pas
  une écriture à exempter. Asserté.

- **Le run réel, lu dans `loop.sh` avant d'annoncer — et la phrase du ticket
  était devenue fausse entre son ouverture et sa livraison.** Le ticket dit
  « à chaque run, pour chaque `retro-*` et `capability-*`, dès que le plafond
  refuse ». C'était vrai avant [74] (livré la veille) : un listing refusé
  arrivait au pilote comme une frontière **vide**, ce qui démarre le gate de
  valeur terminal, qui ouvre des tickets par `open_unique`. Depuis [74],
  `loop__next_ticket` lit le statut, journalise `frontier-refused` et **s'arrête
  en 4** — donc un dépôt durablement au-dessus du plafond ne broie rien et
  n'ouvre rien : le gate de valeur n'est pas atteint. Ce qui reste atteignable,
  et qui est ce que ce ticket ferme :

      MAX_PARALLEL > 1   un refus de frontière avec des itérations en vol fait
                         `loop__reap 1; continue` — le run continue, et les
                         itérations en vol escaladent par `capability_propose`
                         (retro, revue de capacités) sur un tracker qui refuse
      en cours de run    la frontière a répondu au début de l'itération et le
                         tracker franchit le plafond pendant la session — c'est
                         la mise en scène de [74], la session faisant grossir le
                         tracker pendant qu'elle travaille
      un refus isolé     `forge__api` a réessayé une lecture et abandonné : le
                         listing de l'escalade refuse là où celui de la frontière
                         avait répondu

  Les trois ouvrent un doublon sur le tracker d'un humain. Aucun n'est un cas de
  panne exotique — le premier est la configuration que [13] existe pour servir.
  `playthrough__inject`, lui, n'est **pas** sur ce chemin : le gate de valeur ne
  tourne qu'à frontière vide *et lue*.

- **Écart de write-surface : aucun sur `.claude/` ni `test/`.**
  `.claude/lib/forge.sh`, `test/tracker-remote.bats` et `test/mutate.sh`, comme
  déclaré. `docs/frontiere-de-confiance.md` est mis à jour (ligne « Ce que
  `tracker_ids` et `tracker_frontier` rendent est **tout** le tracker »), ce que
  la DoD impose et qu'aucune write-surface de ce dépôt n'a jamais eu à déclarer.

- **Ce qui est mesuré et non tenu, et c'est le ticket [79].** Le statut arrive à
  `tracker_open_unique` et meurt chez ses deux appelants : `capability_propose`
  et `playthrough__inject` finissent tous deux par `return 0`. Le premier par
  contrat écrit (« l'appelant lit le vide, jamais un code de sortie »), le second
  sans l'avoir décidé — et son `return 0` rend **inatteignable** la branche
  `openrc != 0` que `playthrough_close` porte depuis [65] pour dire « le tracker
  a refusé d'ouvrir un ticket », commentaire compris. Sondé plutôt que déduit :
  sous `id="$(f)" || rc=$?`, errexit est suspendu pour toute l'extension
  dynamique, substitution de commande incluse, donc rien ne remonte même si
  l'appelée échoue avant son `return 0`. Le refus est donc lu par un humain qui
  regarde la sortie du run, et par personne d'autre. Les deux fichiers sont hors
  de la write-surface de ce ticket : ouvert comme **[79]**, non placé dans la
  file, à arbitrer à la passe transversale du 10/09.

- **Mutations ajoutées** (`test/mutate.sh`) : `78 a refused listing is read as a
  free slug` (remet le `|| records=""`, c'est-à-dire le défaut livré) et `78 the
  refusal to open a unique ticket is silent` (retire la phrase, garde le statut).
  L'entrée `18 open_unique opens a second ticket under one slug` a été
  **réancrée** sur la nouvelle ligne — sans quoi elle rendait DRIFTED, ce qui est
  la moitié de la question 4 : le ticket qui bouge une ligne porteuse doit
  rebouger l'ancre.

- **Tests ajoutés** (`test/tracker-remote.bats`), et le second est le témoin
  appairé du premier : « a listing the forge refused is not a free slug, and
  open_unique refuses » (`FORGE_PAGE 2` + `FORGE_PAGES 1` sur les deux issues
  déjà semées : `rc=1`, la phrase, rien sur le forge — lu sur l'état du faux et
  non à travers le pack — et registre vide) et « the same slug under a ceiling
  that fits still opens once and answers nothing twice » (même tracker, même
  slug, un seul nombre changé). Sans le second, « ça a refusé » pourrait être un
  `open_unique` qui refuse quel que soit le plafond.
