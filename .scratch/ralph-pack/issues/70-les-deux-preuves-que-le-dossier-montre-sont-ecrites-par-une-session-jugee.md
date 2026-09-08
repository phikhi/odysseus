# 70 — Les deux preuves que le dossier montre sont écrites par une session jugée

**What to build:** Le dossier du drain envoie un humain lire trois preuves. `run.log` porte sa réserve depuis [67]. Les deux autres — la ref `refs/heads/failed/<id>` et le reçu d'audit `receipts/<feature>/<id>.md` — sont écrites par un **run AFK**, dans deux zones qu'aucun contrôle du chemin AFK ne regarde : une ref n'est un chemin d'aucun arbre, et l'arbre principal n'est pas le worktree que le scope-guard juge. Une itération **verte** peut créer, déplacer ou détruire l'une et l'autre, et rien — ni le gate, ni le scope-guard, ni le rollback, ni le reçu, ni l'épinglage de [66] — ne dit un mot.

**Blocked by:** 72

**Write-surface:** `.claude/loop.sh`, `.claude/lib/failures.sh`, `.claude/lib/gate.sh`, `.claude/lib/receipt.sh`, `.claude/lib/router.sh`, `test/gate.bats`, `test/failures.bats`, `test/human-loop.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** resolved

**Tags:** human-loop, forensics, trust-boundary

- [x] Une itération dont la session a écrit, déplacé ou détruit un `refs/heads/failed/*` **le fait dire**, dans le run où ça s'est passé. Ce que ça coûte — le guichet du drain suivant, la preuve perdue — est nommé, pas seulement compté.
- [x] Même chose pour le reçu d'audit : un fichier apparu, réécrit ou effacé sous `receipts/<feature>/` que le pack n'a pas écrit est nommé par le run.
- [x] Le dossier du drain ne présente plus le reçu comme une preuve nue : il porte la même sorte de réserve que `router_journal_lines`, ou bien quelque chose atteste réellement sa provenance. Les deux sont acceptables ; ce qui ne l'est pas est de le montrer sans dire lequel des deux est vrai.
- [x] `docs/frontiere-de-confiance.md` cesse de dire que ce qu'une session écrit dans `.git/` « n'est vérifié par rien » sans dire **qui le lit** : la ligne nomme le lecteur (le guichet et le dossier du drain) et ce qui le tient.
- [x] Une entrée de mutation par garantie livrée, plus les témoins appairés (le même run vert sans contrefaçon, et un run qui écrit une **vraie** ref et un **vrai** reçu, qui ne doit rien faire dire).

## Comments

- **Trouvé par la passe transversale du 07/09/2026** (`../passe-transversale-07-09.md`, §1 et §3). Sondes : `../sondes/passe-07-09/q1-*.bats` et `q3-*.bats`.

- **Mesuré** (`q1`), la ref :

  | | |
  |---|---|
  | Q1a — une itération **verte** dont la session fait `git update-ref refs/heads/failed/20-decision <commit>` | `tests=green typecheck=green scope=green lang=green`, ticket `resolved`, run **rc=0**. **0** mot d'une ref au run, **0** au reçu. Le drain suivant : desk **`admit` → `arbitrate`**, dossier « `git log -p failed/20-decision` » |
  | Q1b — témoin appairé, le même run sans la ref | desk `admit`, « there is none. nothing ever ran on this ticket » |
  | Q1c — l'autre sens, la même itération verte **efface** une ref d'un run précédent | la ref est partie, **0** mot, et le drain affirme « nothing ever ran on this ticket » sur un ticket réellement jugé |

- **Mesuré** (`q3`), le reçu :

  | | |
  |---|---|
  | Q3a — une itération **verte** dont la session écrit `receipts/<feature>/20-decision.md` dans l'arbre principal | run **rc=0**, **0** mot. Le dossier le présente comme le reçu d'audit — « verdicts, findings, and the zones nothing judged » — avec **0** réserve, et ajoute la phrase qui envoie l'humain vers l'autre objet contrefaisable (« `failed/20-decision` is a ref and survives ») |
  | Q3b — témoin appairé, le même run sans le reçu forgé | « receipt none was kept for this ticket » |

- **Pourquoi les quatre contrôles du chemin AFK regardent ailleurs, ensemble.** Le scope-guard, le rollback, le scellement et le témoin d'ignore sont tous construits sur des **trees git du worktree de l'itération**. `refs/heads/*` vit dans le répertoire git **commun**, qu'un worktree partage : un `git update-ref` depuis le worktree écrit dans l'arbre principal, et aucun chemin ne le nomme. `receipts/` est un chemin, mais de l'**arbre principal**, que `git worktree list` nomme à qui le demande — le harnais de test le dit en toutes lettres depuis [13]. Ce que le gate compare est le worktree, deux fois.

- **L'épinglage de [66] ne mord pas, et c'est structurel.** Il compare la photo prise quand le drain prend le ticket à celle prise au retour de la session routée. Une contrefaçon posée par un run **avant** le drainage est dans la photo de base : `router_branch_note` se tait, correctement au sens de son propre contrat. C'est le résidu V1 de [66] atteint par l'autre bout — là-bas la contrefaçon survit **au** drainage et le drainage suivant l'épingle ; ici elle n'a besoin de survivre à rien, elle arrive déjà épinglée.

- **Le mécanisme qui manque existe déjà dans le pack, une fois, et c'est le modèle** : [14] copie `LEARNINGS.md` dans `$TMPDIR` sous un `mktemp` que le pilote n'exporte pas, **avant qu'aucune session n'existe**, sert le prompt depuis la copie et détecte une réécriture de l'arbre principal (« is not what this run last wrote »). Le pack sait donc témoigner d'un fichier de l'arbre principal à l'échelle d'un run. Il le fait pour le seul objet de cette famille que **la boucle** lit. Les deux que la boucle **montre à un humain** n'ont rien.

- **Trois formes possibles, à trancher dans ce ticket** — et le choix a un précédent immédiat, [68], qui a écrit trois sorties et en a retenu une :

  1. *Un témoin par run*, sur le modèle de [14] : `loop_main` épingle l'espace de noms `refs/heads/failed/*` et l'état de `receipts/<feature>/` à son démarrage, et compare à la fin. Nomme, ne remet rien. C'est le moins cher et c'est ce que [72] rend plaçable.
  2. *Un témoin par itération*, autour de chaque session : plus précis — il nomme **quelle** itération a écrit — et il coûte deux mesures de plus par itération, dont une sur `for-each-ref` que [66] a déjà écrite (`router__failed_refs`, à remonter d'un module si elle sert aux deux).
  3. *Une réserve côté drain seulement* : le dossier dit du reçu ce qu'il dit déjà du journal. Le moins cher de tous et le plus honnête sur ce qu'il n'achète pas — il ne détecte rien, il arrête juste de faire croire.

  Les trois sont défendables ; ce qui ne l'est pas est de livrer (1) ou (2) **sans** (3), parce qu'un témoin par run ne dit rien d'une contrefaçon posée par un run que personne n'a fait tourner depuis.

- **Ce qui est déjà tranché et qu'il ne faut pas rouvrir : rien n'est remis.** L'argument est celui de [66] mot pour mot et il vaut pour les deux objets — ce drain n'est l'auteur ni des refs ni des reçus, le commit qu'une ref nommait peut être inatteignable, et une remise qui invente est un second auteur pour un état que personne n'a mesuré. Et rien ne **refuse** : la posture de [69], [67], [66] et [68] tient ici aussi, un garde qui pourrait arrêter un run ou un drainage sur une ref donnerait à une session un `git update-ref` pour renvoyer chez lui l'humain venu vider le puits.

- **Le troisième objet de la même liste, nommé et non sondé :** `docs/playthroughs/<feature>.md`. Écrit par le pack dans l'arbre principal ([11]), lu par un humain le matin, atteignable par une session jugée exactement comme le reçu. Rien dans le pack ne le relit et le dossier ne le montre pas, donc il ne porte pas le défaut mesuré ici — mais il est dans la même zone, avec le même mécanisme absent, et un correctif qui l'oublierait laisserait la liste plus étroite que son critère ([31], [45]).

- **Contrainte héritée de [72]** : c'est [72] qui décide où le préambule de `loop_main` a le droit d'écrire et d'épingler avant les verrous. L'épinglage de la forme (1) va exactement là. `Blocked by: 72` pour cette raison et pour aucune autre.

- **Arête dure vers [18], et elle a deux moitiés.** [66] avait écrit la première dans [18] : *un backend distant qui déplace la trace forensique déplace une preuve, qui doit être lue à travers un épinglage pris avant la session routée.* Celle-ci ajoute la seconde : sur un backend distant, **le reçu est une PR** ([10] et l'en-tête de `lib/tracker.sh` le disent), c'est-à-dire un objet qu'une session peut atteindre par le réseau, et `tracker_receipt_path` rend un emplacement que ce ticket-ci apprend à ne plus présenter nu. [18] doit dire ce qui atteste la provenance d'un reçu distant, ou dire que rien ne l'atteste.

- **Contrainte pour [10]** : la provenance du reçu est une garantie sur ce que le pack **écrit**, pas sur ce qu'un lecteur **trouve** à cet emplacement. La phrase de `receipt.sh` (« it does not read `run.log`: that file lives under `.scratch/`, which no check in this pack guards ») reste vraie et n'est plus suffisante — depuis [68] elle est même à moitié fausse pour `spec.md`, une ligne à relire dans le même passage.

- **Piège de sonde.** Une session d'itération atteint l'arbre principal par `git worktree list --porcelain | awk '/^worktree /{print $2; exit}'`, et les refs sans rien faire du tout. Et il faut un ticket `ready-for-agent` en plus du ticket du puits, sinon le run sort sur une frontière vide et n'ouvre aucune session.

- **Place dans la file, validée par Philippe le 07/09/2026 : troisième, collé à [18].** La plus grosse surface des trois (`loop.sh`, `failures.sh`, `receipt.sh`, `router.sh`) et l'arête dure vers [18], qui rouvre les deux objets juste après. Même raison qui avait fait coller [64] puis [66] à [18]. Ordre retenu : [71] → [72] → [70] → [18] → [19].

- **[72] a répondu, le 07/09/2026, et voici la règle exacte qu'il laisse.** Le
  préambule de `loop_main` — tout ce qui va de sa première ligne à
  `run_lock_acquire` — porte maintenant une règle écrite en toutes lettres
  au-dessus de la fonction, et le même paragraphe est au-dessus de
  `human_loop_main` : *un préambule a le droit de **lire**, d'**imprimer** sur la
  console de qui l'a lancé, et de garder ce qu'il a trouvé dans une **variable de
  son propre shell** — il n'a pas le droit d'écrire un octet là où un second point
  d'entrée lit.* Ce qui a payé pour cette phrase : le préflight journalisait les
  constats du tracker trois lignes avant de demander les verrous, donc le point
  d'entrée refusé écrivait dans le `run.log` de celui qui tournait, qui finissait
  en l'accusant d'avoir réécrit son journal.

  **Conséquence directe pour la forme (1) :** l'épinglage se prend soit en pure
  lecture dans le préambule (une photo est une lecture — c'est exactement le
  statut que garde `RALPH_JOURNAL_BASE`), soit **après** les deux verrous s'il
  écrit quoi que ce soit — un `mktemp`, un fichier de `$TMPDIR`, une ligne de
  journal. `loop_main` a désormais une ligne dédiée juste après les verrous
  (`loop__journal_tracker_findings`) : c'est là que va tout ce que le préambule a
  trouvé et qui doit laisser une trace. Deuxième conséquence, plus petite : le
  préambule porte aussi un garde de sortie (`loop__on_exit`, code 7) armé en tête
  de fichier et **réarmé après les verrous**, parce que les deux `*_lock_acquire`
  écrasent tout trap EXIT ; un épinglage posé entre `tree_lock_acquire` et ce
  réarmement est dans une fenêtre de trois lignes que le garde ne couvre pas, et
  cette fenêtre est nommée dans le code.

## Livraison — 08/09/2026

**Forme retenue : (1) + (3), et (2) refusée pour une raison mesurée.** Un témoin
par **run** — pris après les verrous, avant la première session, dans le
répertoire que `gate_frontier_common` fabrique déjà — comparé **à chaque
itération**, plus la réserve du dossier. Ce que ça donne des trois formes : la
précision de (2) (l'itération qui compare est celle qui nomme, et la ligne va sur
le reçu *de cette itération*) sans son coût ni son défaut — un témoin par
itération pris au spawn accuse la voisine de la ref que sa propre politique
d'échec vient d'écrire, et c'est exactement la mésattribution de [41]. C'est la
forme de `gate_path_witness` / `gate_path_drift` de [52], reprise telle quelle.

**Nouveau module : `.claude/lib/forensic.sh`** (écart de write-surface, voir plus
bas). Il possède le préfixe `forensic_` et cinq fonctions publiques :
`forensic_failed_refs`, `forensic_witness DIR`, `forensic_uncovered`,
`forensic_expect DIR KIND [ID]`, `forensic_drift DIR`.

**Le critère, écrit dans l'en-tête du module et pas dérivé des deux objets
sondés** : *ce que ce pack écrit durablement, hors de tout arbre qu'il juge, pour
qu'un humain le lise après le run*. Trois membres — `refs/heads/failed/*`,
`receipts/<feature>/`, `docs/playthroughs/<feature>.md` — et deux membres de la
même famille explicitement **hors** de ce témoin parce qu'ils en ont déjà un :
`LEARNINGS.md` ([14], parce que la *boucle* le relit) et `run.log`
(`loop_journal_verify`, plus la réserve de [67]). Le troisième objet nommé par ce
ticket et non sondé est donc couvert, et il l'est **par le critère** : aucune
sonde ne l'aurait trouvé, rien dans le pack ne le relit et le dossier ne le
montre pas.

### Le registre, et pourquoi il est entré *avant* l'écriture

Un témoin seul rapporte les écritures de la boucle elle-même comme de la dérive :
`failures_preserve_attempt` écrit `failed/<ticket>`, `receipt_emit` écrit le reçu,
`playthrough_close` écrit le playthrough. Ce qui les sépare est un registre de ce
que le pack **s'apprête à** écrire, ajouté par `loop.sh` juste avant l'appel qui
écrit.

**L'ordre est la garantie, et il a été mesuré.** Un registre nourri *après* coup
laisse une fenêtre dans laquelle l'itération voisine trouve une ref ou un reçu qui
existe et n'est pas encore enregistré — et la phrase pour ça accuse une session
d'avoir contrefait ce que le run d'à côté venait d'écrire légalement. Sondé à
`MAX_PARALLEL=2`, deux tickets rouges en parallèle : **0** accusation
(`test/forensic.bats`, « two failing iterations side by side accuse each other of
nothing »).

**Écrit par `loop.sh` et pas par les modules qui écrivent**, ce qui évite un cycle
`receipt.sh` → `gate.sh`/`forensic.sh` alors que `gate.sh` appelle déjà
`receipt_gap`. Conséquence voulue : l'entrée est mise **sur les deux appels qui
écrivent**, pas en tête d'itération — `failures_handle` n'est appelé que sur le
chemin non vert, donc **une session verte qui contrefait la ref de son propre
ticket est nommée comme une autre**.

**Ce que le registre excuse, écrit plutôt que découvert plus tard** ([65] : un
registre dit ce que la boucle a *écrit*) : une session qui contrefait l'objet d'un
ticket que le pack réécrit dans la même itération. L'écriture du pack passe
par-dessus, et ce qu'un humain lit ensuite est celle du pack.

### Deux trous de la forme [59] trouvés dans ma propre lecture

Les deux sont dans le ticket parce qu'ils ont failli être livrés :

1. **`find` qui refuse n'est pas un répertoire vide.** `find` rend non-zéro pour
   un répertoire qu'il n'a pas pu parcourir *comme* pour un répertoire absent, et
   lu comme une liste vide ça transforme chaque reçu du témoin en reçu que
   quelqu'un a effacé — la phrase qui accuse une session d'avoir détruit toute la
   trace d'audit d'un ticket. Réparé par un `[ -d ]` **avant** la marche (un
   répertoire pas encore créé n'a pas de reçus, ce qui est une réponse) et le
   statut de `find` **après** (un refus fait refuser le manifeste entier).
2. **Un troisième état de digest.** `-` est la réponse de « pas là ». Un document
   dont le mode a changé, ou remplacé par un répertoire du même nom, prenait cette
   valeur sous l'orthographe évidente — donc la comparaison disait la preuve
   *détruite*, sur un fichier toujours assis là où le dossier pointe. `?` dit ce
   qui s'est passé, et diffère quand même de tout digest réel, donc l'événement
   est rapporté et seule la phrase change. La marche est un `-mindepth 1` et non
   un `-type f` pour la même raison : sous `-type f` un reçu remplacé par un
   répertoire quitte la liste et devient une preuve détruite.

### Écarts de write-surface

Déclarée : `loop.sh`, `failures.sh`, `gate.sh`, `receipt.sh`, `router.sh`,
`test/gate.bats`, `test/failures.bats`, `test/human-loop.bats`, `test/mutate.sh`,
`docs/frontiere-de-confiance.md`. Écrit en réalité :

- **`.claude/lib/forensic.sh` (nouveau)** au lieu de `gate.sh`. `gate.sh` était le
  logement naturel — il possède déjà le répertoire de témoin du run et le triplet
  témoin/dérive/résidu — mais le manifeste a besoin de `playthrough_path`, et
  `playthrough.sh` appelle `gate_*` : le loger dans `gate.sh` fabriquait un cycle.
  `failures.sh` et `receipt.sh` ne pouvaient pas non plus posséder les trois zones
  à eux deux. Ni `failures.sh` ni `receipt.sh` ni `gate.sh` n'ont finalement été
  touchés.
- **`.claude/lib/tracker.sh` + `.claude/lib/tracker-local.sh`** : une opération
  d'adaptateur de plus, `tracker_receipt_dir`. `tracker_receipt_path` ne pouvait
  pas servir — elle répond pour un reçu qui **existe déjà**, et le témoin est pris
  avant la première session, sur un répertoire entier. Composer le chemin dans
  `forensic.sh` aurait été un second auteur pour la disposition du backend, ce que
  le commentaire de `tracker_receipt_path` refuse en toutes lettres. Ajoutée à la
  liste des lectures de `tracker__dispatch` : **par le critère et sans effet
  observable**, l'opération ne prenant aucun argument et `tracker__note_write`
  n'écrivant aucune ligne pour un id vide — aucune mutation ne vise cette ligne,
  aucun test ne pourrait rougir pour elle, et c'est dit ici plutôt que laissé à
  découvrir.
- **`test/forensic.bats` (nouveau, 15 tests)** au lieu de `test/gate.bats` /
  `test/failures.bats`. `test/human-loop.bats` n'a été touché que pour le renommage
  ci-dessous.

### `router__failed_refs` remonté d'un module

Comme ce ticket le proposait. La mesure a deux appelants dans deux couches — le
drain, et le témoin qu'un run prend avant sa première session — et deux copies du
même `for-each-ref` auraient été deux endroits où oublier sa clause de refus
([59]). Devenue `forensic_failed_refs`, corps et prose inchangés. Mis à jour :
`router.sh` (3 emplacements), `test/mutate.sh` (2 entrées), `test/human-loop.bats`
(1 stub). Les tickets [66] et [18] nomment encore l'ancien nom dans leur prose
historique : c'est un compte rendu de ce qui a été fait à l'époque, laissé tel
quel, et la note est écrite dans [66].

### Ce que ça ne dit pas, nommé et non fermé

- Une contrefaçon posée par un run que **personne n'a fait tourner depuis** est
  dans la photo de base du témoin — et dans l'épinglage du drain aussi, qui compare
  le drain à lui-même ([66]). C'est exactement pourquoi la forme (3) est livrée
  avec : sans elle on échangeait un silence contre un plus étroit.
- Une itération **orpheline** ([44]) sort par `loop__orphaned` avant le bloc de
  dérive, donc ne compare rien — et un run **tué** non plus. Le témoin meurt dans
  `$TMPDIR` avec lui, comme le pin d'ignore et l'espace du retro.
- Rien n'est **remis** et rien ne **refuse**. Déjà tranché par le ticket, tenu :
  la posture de [66], [67], [68] et [69].
- Sur un backend dont les reçus ne sont pas des fichiers, **rien ici ne les
  témoigne**. Le run le dit une fois (`forensic_uncovered`) au lieu d'être plus
  étroit que sa propre phrase, et la question est celle de **[18]**.

### La question de la frontière de confiance, posée sur ce que ce ticket ajoute

Trois surfaces neuves, et aucune n'est une garantie nouvelle :

- **`forensic.witness` et `forensic.written`** vivent dans le répertoire
  `ralph-frontier.XXXXXX` que `gate_frontier_common` fabrique — un `mktemp` que le
  pilote **n'exporte pas**, même discipline et même exposition que le témoin
  d'ignore ([30]), le registre du tracker ([40]) et la copie de `spec.md` ([11]).
  Une session qui devinerait ce nom ajouterait une clé à `forensic.written` et
  ferait excuser sa contrefaçon. **Ce n'est pas une exposition nouvelle** : le même
  répertoire porte déjà le témoin de frontière partagée et la ligne de base du
  PATH, qu'une session trouvant ce nom réécrirait aussi. Ce qui la tient est « qui
  connaît le nom », et c'est écrit ici pour ne pas être redécouvert.
- **`tracker_receipt_dir` rend un chemin qu'un backend choisit.** Un backend qui
  répondrait `/` ferait parcourir la machine à chaque itération. Un backend est un
  fichier qu'un projet installe — du code de confiance dans le modèle de ce pack,
  au même titre que `TEST_CMD` — donc ce n'est pas une frontière franchie ; c'est
  un coût que [18] doit connaître quand il en écrit un.
- **Un nom de reçu portant une tabulation** casse la position des champs du
  manifeste : la clé est tronquée et l'objet est rapporté comme apparu au lieu
  d'être rapporté sous son nom. Même famille que le saut de ligne déjà écrite dans
  `forensic__manifest`, même direction d'erreur (bruyant plutôt que muet), et rien
  ne l'adresse — la ligne de `docs/frontiere-de-confiance.md` sur les noms que ce
  transport ne peut pas porter ([37], [39]) la couvre.

### Contrainte héritée de [72], respectée

Le témoin écrit dans `$TMPDIR` : il est donc pris **après les deux verrous**, à
côté de `RALPH_FRONTIER_COMMON` dont il réutilise le répertoire. Rien n'a été
ajouté à `gate_tmp_names` ([62]) et rien de neuf n'est à démonter : `rm -rf
"${RALPH_FRONTIER_COMMON:-}"` emporte les deux fichiers. Ni les verrous, ni la
base de journal, ni le préflight, ni les deux lignes de `loop__on_exit` n'ont
bougé.

### Ce que `test/mutate.sh` a trouvé et qu'une relecture n'avait pas vu

Deux fois, et les deux sont des entrées de mutation **à moi** qui mentaient :

1. **VACUOUS sur « the receipt this iteration is about to write is never
   registered ».** Le témoin appairé visé était un run à **un** ticket, qui écrit
   son reçu sur la **dernière** itération qu'il fera : aucune comparaison ne tourne
   après cette écriture, donc l'entrée de registre n'était jamais exercée. Réécrit
   à deux tickets, `MAX_PARALLEL=1`, tous les deux rouges — le reçu du premier est
   en place quand la première itération du second compare.
2. **VACUOUS sur « 44 nothing is asked between the gate and the failure policy »**,
   une entrée existante que ce ticket a dû réancrer parce que `forensic_expect`
   s'est posé entre le garde et `failures_handle`. C'est exactement l'avertissement
   de l'en-tête de `mutate.sh` : `loop.sh` porte **quatre** appels à
   `loop__orphaned`, dont ceux des lignes 766 et 948 sont **identiques au
   caractère près, indentation comprise**. Une ancre sans son voisin distinctif,
   sans `/g`, édite le **premier** — donc le garde du repli et non celui de la
   politique d'échec, et le test nommé restait vert avec sa garantie intacte.
   Réancré comme ses deux entrées sœurs, en enjambant vers le commentaire qui
   suit ; les trois sont `ok`.

Aucune des deux n'était visible en relecture, et la première ne l'était pas non
plus en sonde : le run réel se comporte correctement dans les deux cas. C'est le
gate de mutation qui a dit que les tests, eux, ne le remarquaient pas.

### Sondes et gates

Sondes de la passe rejouées avant d'écrire (`sondes/passe-07-09/q1-*`, `q3-*`) et
sondes de vérification conservées sous `sondes/ticket-70/`. Les cas de la passe
sont maintenant des tests de la suite : Q1a, Q1b, Q1c, Q3a, Q3b.

- `bash test/run.sh` : **785 tests, 0 failures**, 6 skips opt-in (aucun dans le canari)
- `bash test/mutate.sh` : **804 mutations, 0 not ok**
