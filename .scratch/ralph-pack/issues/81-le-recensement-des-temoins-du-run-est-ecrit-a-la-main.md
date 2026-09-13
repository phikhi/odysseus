# 81 — Le recensement des témoins du run est écrit à la main et en couvre quatre sur neuf

**What to build:** Qu'un témoin du run manquant ou réécrit soit aussi fort qu'un pin cassé, et que la liste des témoins soit dérivée de son critère au lieu d'être recopiée à côté.

**Blocked by:** None

**Write-surface:** `.claude/lib/gate.sh`, `.claude/lib/forensic.sh`, `.claude/lib/playthrough.sh`, `.claude/lib/retro.sh`, `.claude/loop.sh`, `test/gate.bats`, `test/mutate.sh` — **plus, en livrant : `.claude/lib/concurrency.sh`, `test/playthrough.bats`, `test/retro.bats`, `docs/frontiere-de-confiance.md`** (écarts consignés en fin de ticket)

**Status:** resolved

- [x] Chaque objet que le run range en `$TMPDIR` pour s'en servir de **témoin** est recensé, et le recensement est dérivé de la source du pack — pas une seconde liste écrite à la main. `gate_witness_seal` **marche** le contenu des trois porteurs à l'instant où le run vient de les écrire ; aucun nom n'est tapé, ni dans le pack ni dans le test.
- [x] Un témoin **manquant** est traité comme le pin cassé de [41] : refusé, jamais replié en silence sur « lire la source vivante ». **Refusé par le contrôle qui le lit, et nommé par le run dans tous les cas** — le découpage est délibéré et expliqué plus bas.
- [x] Un témoin **réécrit** se comporte comme un témoin manquant : le contenu est vérifié, pas seulement l'existence. Trois exceptions, chacune avec sa borne et sa raison : les trois registres qui grandissent (longueur), et l'index des leçons (existence ici, contenu tenu par `retro_hold_index`).
- [x] `gate_guards` énumère les gardes des trois zones où le pack en pose, pas de deux — l'arbre (deux répertoires), le répertoire git commun (`ralph.frontier.lock`, `ralph.integrate.lock`) et `$TMPDIR` (`ralph-retro.*/index.guard`). Chaque module répond pour sa zone ; le recensement n'en compose aucun chemin.
- [x] Ce qui reste hors de portée est écrit dans `docs/frontiere-de-confiance.md` — trois lignes réécrites (le témoin, la leçon, le flux), et le cas du registre cité depuis la ligne que [80] avait écrite, pas réécrit.

## Comments

- **Trouvé à la passe transversale du 10/09/2026**
  (`../passe-transversale-10-09.md`, §2 et §3). Sondes :
  `../sondes/passe-10-09/q3-*.bats` (Q3a à Q3i) et `q4-*.bats` (Q4a, Q4b).

- **Le critère est déjà écrit, au bon endroit, et la liste ne le suit pas.**
  `gate__frontier_pin_broken` ([41]) porte ceci :

  > *« The run's witness of the shared sources and its register of movements are
  > held to the same standard, and they have to be: they live in the same
  > `$TMPDIR` under the same kind of unguessable name, so a session that can
  > reach one can reach the other — and the fallbacks around them are "read the
  > live sources", which is a quiet return to the behaviour this ticket
  > removed. »*

  Puis :

      [ -f "$common/manifest" ] && [ -f "$common/exclude" ] &&
        [ -f "$common/attributes" ] && [ -f "$common/ledger" ] || return 0

  Le répertoire porte **neuf** fichiers sur le backend local et **onze** sur un
  backend distant. C'est la forme de [31], [45] et [62] : un critère dans la
  phrase, une liste copiée à la main à côté.

- **Mesuré, un fichier par run, la session ne faisant rien d'autre qu'un `rm`
  après un glob :**

  | Fichier effacé | Qui l'y a mis | La nuit s'arrête ? | Un mot ? |
  |---|---|---|---|
  | `ledger` | [30], [41] | **oui**, `rc=4` | cinq phrases |
  | `manifest` | [30], [41] | **oui**, `rc=4` | cinq phrases |
  | `global` | [30] | non — `resolved`, `rc=0` | **aucun** |
  | `path` | [52] | non — `resolved`, `rc=0` | **aucun** |
  | `guards` | [77] | non — `resolved`, `rc=0` | **aucun** |
  | `forensic.witness` | [70] | non — `resolved`, `rc=0` | **aucun** |

  `global` est la ligne à lire en premier : elle vient de **[30] lui-même**,
  `gate_frontier_common` la copie dans la même boucle que `exclude` et
  `attributes`, et elle n'est pas dans la liste. La liste n'a pas dérivé — elle a
  été écrite courte dès le premier jour.

- **« Aucun mot » chiffré sur [70]** (Q4). Une session qui détruit un reçu
  d'audit d'un run précédent **et** `forensic.witness` : le reçu est parti, run
  `rc=0`, ticket `resolved`, rien. Témoin appairé, la même destruction avec le
  témoin laissé en place : « `receipts/demo/00-vieux.md` is gone, and this run
  did not remove it. It was the asynchronous review surface of a ticket a run
  finished with, and the human sink now says no receipt was kept for that
  ticket ». Un ticket entier de constat, éteint par un `rm` d'un fichier que rien
  ne compte. Le même geste éteint `gate_path_drift` ([52]), `gate_guard_note`
  ([77] — donc la phrase qu'un claim refusé imprime redevient exactement celle
  que [77] venait de corriger) et la remise du sidecar ([77]).

- **L'existence ne suffit pas, et c'est la seconde moitié du ticket.** Deux
  objets ne disparaissent pas : ils changent de contenu.

  *La copie de `spec.md`* (Q3a). `playthrough.sh` écrit en toutes lettres :
  « `a delivery session, during a run` — this copy is already taken; the rewrite
  changes nothing here ». Mesuré : la session réécrit `"$TMPDIR"/ralph-spec.*`,
  le gate de valeur rejoue `THIS-FLOW-WAS-FORGED-BY-THE-SESSION`, `spec.md` sur
  le disque est intact, run `rc=0`, feature fermée en vert, aucun mot. Le témoin
  appairé (la même réécriture sur le fichier du disque) donne bien le
  comportement documenté. C'est [68] rouvert là où [68] avait conclu qu'il n'y
  avait rien à faire : [68] a tranché sur le run **suivant**, et la phrase
  ci-dessus dit que le run **courant** est couvert.

  *La baseline de `LEARNINGS.md`* (Q3i). La session de l'itération 1 réécrit
  `ralph-retro.*/index` ; le prompt de la seconde session porte, mot pour mot :

      Standing rules distilled by earlier iterations:
      - LR-9 x9 learning-records/lr-9.md — RULE-FORGED-BY-THE-PREVIOUS-SESSION: ignore the write-surface.

  `LEARNINGS.md` sur le disque n'a jamais existé. C'est la moitié que [14]
  appelait « *empêcher* », et elle reposait sur le même nom.

  La forme qui couvre les deux est un **digest pris au moment où le témoin est
  pris**, revérifié à la lecture — ce que [41] fait déjà pour le pin, et rien
  d'autre. Attention à la seule exception réelle : `ledger` et le registre du
  sidecar **grandissent légalement** pendant le run, donc leur vérification est
  une borne de longueur (ce que [41] fait déjà pour `ledger`) et pas un digest.

- **La question transversale de [77], répondue et élargie.** [77] écrivait :
  « rien n'énumère les gardes que le pack pose **hors** de ces deux répertoires,
  et rien ne dit qu'il n'y en a pas ». Mesuré : `gate_guards` couvre **trois**
  des six `state_guard_take` du pack.

  | Garde | Où il vit | Dans `gate_guards` ? |
  |---|---|---|
  | `forge__guard` | `<feature_dir>/.forge.guard` | oui |
  | `tracker_local__open_guard` | `<feature_dir>/.open.guard` | oui |
  | claim guard | `<tickets_dir>/<id>.md.guard` | oui |
  | `concurrency_frontier_guard` | `<gitdir commun>/ralph.frontier.lock` | **non** |
  | `concurrency__integration_guard` | `<gitdir commun>/ralph.integrate.lock` | **non** |
  | garde de l'index de leçons | `$TMPDIR/ralph-retro.*/index.guard` | **non** |

  Le garde d'intégration est le plus cher, et c'est le geste de Q2e/Q2f de la
  passe du 08/09 dans une zone que la réparation de [77] ne couvre pas : pris par
  un propriétaire vivant, `concurrency__wait_for_guard` attend soixante secondes
  puis rend la main, et une itération **verte** finit `not-integrated` — le
  travail est dans un worktree que le run détruit, aucun commit, aucune ref,
  aucun changement au ticket, et la nuit s'arrête. La conséquence est déjà bien
  traitée par [74] (`not-integrated` émet un reçu et arrête le run) ; ce qui
  manque est que rien ne **nomme** l'objet, parce que rien ne l'énumère. `.git/`
  est atteignable par une session : c'est écrit dans [22] et dans le tableau de
  confiance.

- **La réparation est celle de [62], un répertoire plus loin.** [62] a remplacé
  six noms recopiés par une liste dérivée, tenue par un test qui lit les `mktemp`
  du pack **et les fait résoudre par le pack**. Le même geste ici lit les
  écritures que le pack fait dans le répertoire témoin. Deux pièges hérités de
  [62], à ne pas repayer : un motif trop large (`ralph-*`) a été refusé là-bas
  pour une bonne raison, et il y a **deux écrivains** de ce répertoire
  (`gate_frontier_common` et `forensic_witness`, plus l'adaptateur par
  `tracker_sidecar_witness`) — une liste dérivée d'un seul serait la même
  erreur d'un cran.

- **Ce qui n'appartient PAS à ce ticket** : le registre d'écritures de la boucle
  (`ralph-slot.writes.*`). Il est dans la même zone et il tombe au même glob,
  mais sa réparation est d'une autre nature — une ligne forgée y est
  indiscernable d'une ligne légitime, donc ni recensement ni digest ne
  l'attrapent. C'est [80], et c'est un faux vert livré.

- **Piège de harnais, mesuré** : effacer `ledger` ou `manifest` rougit **tout**
  le gate et pas seulement le contrôle d'ignore — le snapshot d'arbre est refusé,
  donc `scope` et `lang` rendent « could not read the working tree » et le
  rollback s'arrête. Une assertion sur `rc=4` seul ne distinguerait pas ce refus
  d'un autre : asserter les phrases.

- **Ce que [80] a tranché en livrant (10/09/2026), et qui est une contrainte
  d'entrée pour ce ticket.** Le registre `ralph-slot.writes.*` est **le seul** des
  douze objets de cette zone pour lequel « recenser et vérifier » ne peut rien :
  une ligne forgée y est un id appendu à un fichier append-only, indiscernable
  d'une ligne légitime, et le fichier bouge légalement entre deux lectures — donc
  ni digest ni recensement de contenu. La réparation livrée là-bas n'est pas un
  témoin : c'est une réduction de ce qu'une ligne achète (`failures_protect_tracker`
  n'exempte jamais le ticket de l'itération courante, et `failures__register_since`
  ne consulte rien quand `concurrency_may_overlap` est faux). **Conséquence pour
  ce ticket** : si le recensement inclut `ralph-slot.writes.*`, ce ne peut être
  que pour son **existence**, jamais pour son contenu — et la dernière AC
  ci-dessus (« y compris le cas du registre, qui appartient à [80] et pas ici »)
  est déjà satisfaite par la ligne que [80] a écrite dans
  `docs/frontiere-de-confiance.md`, qui nomme ce qui reste atteignable
  au-dessus de `MAX_PARALLEL=1`. Ne pas la réécrire, la citer.

  Deux sorties écartées là-bas et qui vaudraient pour d'autres objets d'ici, pour
  éviter de les re-sonder : le **descripteur délié** (`exec 9>f; rm -f f`) ne sert
  que pour un objet que personne ne relit depuis le début — bash ne rembobine pas
  un fd et `/dev/fd/N` est un `dup` sur darwin ; et un **MAC par ligne** est hors
  de portée de l'outillage du pack, dont le seul digest est `cksum`, un CRC donc
  affine et forgeable depuis quelques couples connus.

## Place dans la file

**Validée par Philippe le 10/09/2026, à la passe transversale du même jour.** La
file devient **[80] → [81] → [79] → [82] → [75] → [73] → [19]**. Le critère est
celui du dépôt — minimiser la reprise, jamais l'urgence — avec la seule exception
que ce dépôt s'autorise et qu'il a déjà payée : **un faux vert livré passe
devant**, comme [76] l'a fait à la passe du 08/09.

1. **[80]** — le faux vert livré du lot ([40] rouvert par un glob). Il tranche
   aussi ce qui reste à [81] : la seule chose que « recenser et vérifier » ne peut
   pas attraper.
2. **[81]** — même zone (`$TMPDIR`), et il consomme la décision de [80]. Livrés
   voisins, ils s'écrivent contre une seule relecture de `loop.sh` et de
   `gate.sh`.
3. **[79]** — petit, indépendant, position libre. Placé ici parce qu'il ferme le
   résidu de [78] avant que la file ne reparte sur un autre chantier.
4. **[82]** — la famille des refus de lecture, et il touche `forge.sh` comme [75].
5. **[75]** — le cache, qui donne son budget à la remise de [73].
6. **[73]** — la remise, qui hérite de la clause de [82] autant que du cache de
   [75].
7. **[19]** — l'installeur lit ce que les six autres décident.

**`Blocked by:` reste `None` pour [79], [80], [81] et [82], et c'est une
décision** — le précédent est celui que [78] a écrit : la position dans la file
est un choix d'ordonnancement, pas une dépendance, et écrire une fausse arête
ferait sortir un ticket de la frontière si son voisin était mis de côté. Les
arêtes réelles ne bougent pas : `[75] 77`, `[73] 74, 75, 77`,
`[19] 73, 74, 75, 76, 77`.

## Livré le 10/09/2026

Branche `ticket-81`. `bash test/run.sh` et `bash test/mutate.sh` verts, canari
compris. Baseline après ce ticket : **run.sh 867 tests, 0 failures, 6 skips
opt-in / mutate.sh 888 mutations, 0 not ok** (avant : 854 / 872).

### Ce que le code ne dit pas

- **La forme de la réparation est celle de [62], et le magasin est neuf.** Le
  recensement se dérive — `gate_witness_seal` marche le contenu de
  `$RALPH_FRONTIER_COMMON`, `$RALPH_PLAYTHROUGH_SPEC` et `$RALPH_RETRO_STATE` à
  l'instant où le pilote vient de les écrire, dernier des cinq gestes de
  démarrage. Ce que [62] n'avait pas et qui compte plus que la dérivation : la
  référence est **une variable de shell du pilote**, jamais un fichier et jamais
  exportée. `claude` est lancé avec un environnement, une itération est un `fork`
  du pilote — donc tout contrôle en aval hérite du sceau, et rien en aval du fork
  ne peut le replacer. C'est le seul magasin de ce pack qu'une session jugée ne
  peut prouvablement pas atteindre, et c'est la différence entre ce sceau et un
  treizième objet à côté des douze.

- **Le refus est découpé par témoin, et un refus global a été écrit puis jeté.**
  Le premier jet faisait consulter le sceau entier par `gate__frontier_pin_broken`.
  Mesuré : une copie de `spec.md` réécrite arrêtait le run en disant `scope=red`
  et *the scope-guard could not read the working tree*. C'est une accusation
  fausse sur un fichier qui n'a rien à voir avec l'arbre — exactement ce que ce
  dépôt refuse ailleurs (« une facture que personne ne peut contester »). Donc :
  **tous** les témoins sont **nommés** par `gate_witness_note` (`run.log` + reçu),
  et chacun est **refusé** par le contrôle qui le lit, parce que les replis ne
  sont pas le même repli :

  | Témoin | Qui refuse | Pourquoi celui-là |
  |---|---|---|
  | les 9/11 du témoin partagé | `gate__frontier_pin_broken` → le snapshot d'arbre | leur repli est « lire les sources vivantes » ([41]) |
  | `ralph-spec.*` | `playthrough_close`, avant de dépenser une session | son repli est le fichier du disque ([11]) |
  | `ralph-retro.*/index` | personne : **remis** et nommé | ce run le republie exprès ([14]) |
  | `capability.witness` | personne : **nommé** et rien de plus | son lecteur est un canal d'événements qui se tait, pas un contrôle qui se replie ([15]) |

- **`gate_witness_moved [ROOT]`** prend un porteur en argument pour ça, et
  `gate_witness_intact PATH` est la question qu'un lecteur pose sur son propre
  témoin. Un futur ticket qui ajoute un témoin doit choisir sa colonne : le mettre
  dans le répertoire partagé le fait refuser le snapshot d'arbre, ce qui n'est pas
  toujours ce qu'on veut.

- **L'index des leçons est le seul cas où « réécrit = manquant » ne tient pas, et
  c'est structurel.** Le run le republie (`retro__publish`), donc un digest pris à
  `retro_open` est périmé dès la première leçon ; et un pilote qui le reprendrait à
  chaque reap **rescellerait** ce qu'une session y aurait écrit — la contrefaçon
  est blanchie une itération plus tard, parce que `retro__promote` rend l'index
  suivant *à partir de* l'index courant. Trois sorties ont été écartées avant
  celle-ci et il vaut mieux ne pas les re-sonder : (1) resceller avant chaque fork
  — absorbe la réécriture de la session précédente ; (2) faire remonter au pilote
  un « j'ai publié » par un fichier — le fichier est dans la zone atteignable, donc
  ce n'est pas un contrôle ; (3) faire publier le pilote — `retro_run` est une
  session entière, elle vit dans l'enfant. La sortie retenue : **l'enfant garde la
  copie dans sa propre mémoire** (`retro_hold_index`, avant le spawn) et la remet
  au retour (`retro_index_note`). C'est le seul niveau où la republication du run
  se distingue d'une réécriture de session.

- **Ce que la remise ne fait pas, et qui est un choix** : au-dessus de
  `MAX_PARALLEL=1` elle **nomme et ne remet rien** — un frère qui distille une
  leçon a bougé le fichier légalement, et le remettre ferait tomber la leçon. Même
  aveu que [80] un glob plus loin, même ligne dans le tableau. Et une itération
  **tuée** entre sa session et la comparaison laisse l'index tel que la session
  l'a laissé : la remise est au plus tôt après le retour de session, juste après
  `gate_frontier_put_back`, mais elle n'est pas dans un trap.

- **Les trois registres qui grandissent** (`ledger`, `forensic.written`,
  `sidecar`) sont tenus à leur **longueur** et pas à un digest, ce que le ticket
  demandait. Deux choses à savoir avant de croire cette borne : (1) `ledger` et
  `forensic.written` sont scellés **vides**, donc la borne de longueur n'achète
  rien pour eux et ce qui tient le `ledger` reste la marque par itération de [41] ;
  seul `sidecar` est scellé non vide. (2) une ligne **forgée** y est hors de
  portée, ce que [80] avait déjà tranché — la contrainte d'entrée de ce ticket est
  respectée à la lettre : le registre `ralph-slot.writes.*` n'entre pas dans le
  sceau, et sa ligne du tableau est citée, pas réécrite.

- **`gate_witness_mutable` est une liste, et elle est tenue des deux côtés.** Le
  sens dangereux (un témoin que le pack bouge et que la liste ne nomme pas → une
  nuit ordinaire refusée) est tenu par un **run réel** : deux itérations, la
  session note le digest de chaque témoin à chaque spawn, et tout ce qui a bougé
  entre les deux doit être sur la liste. L'autre sens (un nom gardé après la
  disparition de l'objet) est tenu par un scan de source, et c'est le maillon
  faible du ticket : il vérifie qu'une redirection crée un fichier de ce nom, pas
  que le mécanisme est vivant. Un backend local ne fabrique jamais de `sidecar`.

- **`cksum` est un CRC.** Le seul digest du pack est affine, donc une session qui
  connaît le contenu d'un témoin peut fabriquer une réécriture qui conserve le
  digest. Le sceau fait passer le prix d'une réécriture de `cat >` à une
  contrefaçon délibérée contre un digest que personne ne lui a donné ; il ne la
  rend pas impossible, et le tableau le dit. Les deux sorties que [80] avait
  disqualifiées n'ont pas été re-sondées (fd délié, MAC par ligne).

- **Le sceau est un instantané.** Ce que le pack crée dans un porteur **après**
  l'avoir scellé n'est tenu par rien : le compteur de vues de [15]
  (`ralph-retro.*/capability.seen`, créé à la première revue de capacités) est le
  cas réel aujourd'hui. Nommé dans le tableau, pas réparé ici — le fermer demande
  de décider si un compteur est un témoin, ce que ce ticket n'a pas à trancher.
  **C'est la trouvaille à emporter à la passe suivante.**

- **Le drain ne prend aucun sceau.** `human-loop.sh` n'appelle ni
  `gate_witness_seal` ni les trois témoins ; `gate_witness_moved` est silencieux
  sans sceau **par construction**, pour que `gate_*` reste pilotable hors run
  (`pack_run`, un script de projet). Ce qui empêche ce silence d'être le
  comportement livré est la ligne du pilote et l'entrée de mutation
  « 81 the run throws its own seal away ».

- **`gate_guards`, trois zones.** Les deux répertoires de l'arbre sont *marchés*
  (un garde de claim porte le nom d'un ticket) ; les trois autres gardes sont
  *demandés* au module qui les possède — `concurrency_guards` (neuf, public) et
  `retro_guards` (neuf, public) — et `gate__guard_paths` n'en compose aucun. Deux
  conséquences à connaître : `gate_guard_note` peut désormais nommer le garde
  d'intégration d'un frère vivant, et `gate__stale_guards` nomme un
  `ralph.integrate.lock` laissé par un run tué. Ce dernier est **repris** pendant
  le run (`state_guard_take` déplace un propriétaire mort, et le repli d'une
  itération verte est le prochain appelant) — donc contrairement aux gardes de
  l'arbre, la règle « nommé, jamais balayé » ne s'applique pas à lui, et le test
  le dit.

### Écarts de write-surface

Quatre chemins hors de la surface déclarée, tous nécessaires :

- **`.claude/lib/concurrency.sh`** — `concurrency_guards`, neuf et public. La
  seule alternative était que `gate.sh` compose `<gitdir>/ralph.*.lock`, c'est-à-dire
  un second auteur pour un agencement que ce module seul connaît ; ou qu'il appelle
  `concurrency__integration_guard`, ce que `test/layering.bats` refuse — et la
  règle du dépôt est de renommer, pas d'appeler quand même.
- **`test/playthrough.bats`**, **`test/retro.bats`** — les deux garanties de §3
  vivent dans ces modules, donc leurs sondes de run réel aussi. Les mettre dans
  `test/gate.bats` aurait mis la preuve loin du code.
- **`docs/frontiere-de-confiance.md`** — c'est une AC du ticket ; la surface
  déclarée l'avait simplement oublié.

### Pièges rencontrés

- **Trois entrées de `test/mutate.sh` ont dérivé** et sont ré-ancrées, avec la
  raison écrite au-dessus de chacune : « 21 the write-surface is read after the
  session » (une ligne s'est insérée entre le snapshot et le spawn — l'édition est
  désormais un *delete* plus un *insert*, donc une quatrième ligne dans ce bloc ne
  la fera pas dériver à nouveau), « 41 a destroyed run witness reads as no witness
  at all » (les quatre noms ont disparu ; le porteur est le plancher hors-run),
  « 77 the sweep forgets where a ticket's own guard lives » (la marche est passée
  dans `gate__guard_paths`).
- **Une entrée neuve est sortie VACUOUS au premier jet** — « 81 the run stops
  without naming the witness ». Le test assertait `is gone` … `/guards`, et la
  **clause du gate** contient déjà ces mots : retirer la phrase de la boucle
  laissait le test vert. Le test assère maintenant les deux phrases séparément,
  parce que ce sont deux garanties.
- **Le prix d'un refus global**, mesuré et jeté : voir plus haut. C'est le genre
  d'erreur qu'un test vert n'aurait pas montrée — la nuit s'arrêtait bien, en
  accusant le mauvais objet.

### Ce qui est écrit ailleurs

- **[19]** — la liste que ce ticket dérive n'est **pas** celle que l'installeur
  balaye. `gate_tmp_names` ([62]) reste la spécification de balayage, au niveau des
  noms du premier étage de `$TMPDIR` ; `gate_witness_seal` descend d'un cran, dans
  le contenu de trois de ces répertoires, et ne sert qu'au run. [19] n'a rien à
  consommer d'ici.
- **[75]** — son cache loge dans le répertoire-témoin du run ([77]). Il **hérite
  du sceau** : un fichier de cache créé avant la prise du sceau est tenu à son
  digest — donc immuable pour le run, ce qui n'est probablement pas ce qu'un cache
  veut — et un fichier créé après n'est tenu par rien. Choisir explicitement, et
  si le cache doit bouger, l'inscrire dans `gate_witness_mutable` avec sa borne.
- **[15]** — `capability.seen` est créé après le sceau, donc hors de portée. Voir
  plus haut.
- **[77]** — sa question transversale de fin de ticket est répondue dans le code
  (`gate_guards`) et ici : trois zones, six `state_guard_take`, aucun chemin
  composé hors de son module.

## Ce que la passe transversale du 13/09/2026 en a fait

La trouvaille que ce ticket avait nommée pour la passe suivante — *« le sceau est
un instantané : ce que le pack crée dans un porteur **après** l'avoir scellé n'est
tenu par rien, et le compteur de vues de [15] est le cas réel aujourd'hui »* — a
été mesurée, et **il y en a deux** : `ralph-retro.*/capability.seen` ([15]) et
`ralph-retro.*/brief.<id>` ([14]). Les deux sont atteignables par un glob, les
deux changent ce qu'une session suivante est *dite* ou ce qu'un humain est
*demandé*, et le run ne dit rien dans les deux cas. Repris par **[83]**, avec la
contrainte structurelle que ce ticket-ci avait posée sans la nommer : le sceau
vit dans une variable du **pilote** et les deux objets sont créés dans un
`loop__iterate … &`, donc dans un fork qui ne peut rien y remettre.

L'autre moitié du ticket — `gate_guards`, porté de trois `state_guard_take`
recensés sur six à six sur six — est complète et **dérivée par aucun test**. C'est
la seconde moitié de la question de [77], reprise par **[85]**.

Sondes : `../sondes/passe-13-09/q1-*.bats`, `q2-*.bats`, `q3-*.bats`,
`q5-*.bats`.
