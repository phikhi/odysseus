# 48 — Un nom de ticket qui porte un saut de ligne

**What to build:** Décider ce que le pack fait d'un fichier de ticket dont le nom
contient un **saut de ligne**, et le tenir. Depuis [37] toute liste d'ids voyage à
raison d'un id par ligne et se compare ligne entière ; c'est ce qui referme l'espace
et le métacaractère de glob, et c'est aussi ce qui laisse le saut de ligne ouvert —
la convention *est* le séparateur. Un `99-a<LF>b.md` déposé par une session est donc
encore vu comme **deux** ids qui ne résolvent rien.

**Blocked by:** None

**Write-surface:** `.claude/lib/tracker-local.sh`, `.claude/lib/failures.sh`,
`test/tracker-local.bats`, `test/failures.bats`, `test/mutate.sh`,
`docs/frontiere-de-confiance.md`

**Status:** resolved

- [x] Un ticket dont le nom de fichier porte un saut de ligne ne produit plus d'id
      fantôme sur la frontière : soit il est adressable, soit il est refusé — mais
      pas « annoncé mis en quarantaine » alors qu'il est resté `ready-for-agent`.
- [x] La ligne de journal ne ment plus. Aujourd'hui `failures_quarantine_strays`
      écrit `quarantined 99-a, b` sans avoir escaladé quoi que ce soit ; un contrôle
      qui annonce avoir agi est exactement ce que `docs/frontiere-de-confiance.md`
      existe pour attraper.
- [x] Le test porte le témoin appairé : le même scénario avec un nom d'une seule
      ligne doit rester vert, sinon il ne prouve rien sur le saut de ligne.
- [x] La ligne de `docs/frontiere-de-confiance.md` ouverte par [37] est mise à jour
      avec ce qui tient réellement, ou avec l'aveu que la décision est de refuser.

## Comments

- **Origine : livraison de [37], le 27/08/2026.** Sonde conservée :
  `.scratch/ralph-pack/sondes/37/s3-saut-de-ligne.bats`, tournée **après** correctif
  — ce qu'elle mesure est ce qui reste, pas ce que [37] a fermé. Sortie :
  `ids[01-alpha|99-a|b|]`, `strays[99-a|b|]`, deux `could not give … a number of its
  own`, `quarantined 99-a, b`, statut du fichier réel `ready-for-agent`, et
  `tracker_frontier` rend `01-alpha|99-a|b|`.

- **Ce que ça coûte réellement, et pourquoi ce n'est pas un faux vert.** Les deux
  fantômes entrent dans la frontière mais aucun n'est réclamable — `tracker_claim`
  échoue, l'itération compte stérile, et le run s'arrête sur `STERILE_K`. Donc :
  un run qui ne broie rien, une ligne de journal qui ment, et un ticket que la
  session s'est écrit avec la surface de son choix mais que personne ne peut broyer.
  À ordonner comme tel : ce n'est pas la gravité qui décide dans ce dépôt, c'est la
  reprise — et ce ticket ne bloque personne.

- **Les deux directions, à trancher explicitement.** *Refuser* est bon marché : le
  backend local peut ne pas rendre un nom qui contient un `\n` et le dire une fois,
  mais un ticket invisible est pire qu'un ticket inadressable si personne ne lit la
  ligne. *Porter* le nom demande un transport délimité par NUL — `read -d ''`,
  `find -print0` — qu'un heredoc ne peut pas véhiculer : c'est une réécriture du
  passage, pas une ligne, et elle toucherait les huit lecteurs que [37] vient
  d'unifier. Écrire la décision, pas seulement le correctif.

- **Ce que [39] laisse à ce ticket, livré le 27/08/2026.** Deux choses, et la
  première change le décor. (1) `failures_protect_tracker` lit `issues/` par un
  `diff-tree --name-status` qui passe désormais `core.quotePath=false`, donc un
  ticket dont le nom porte un **accent** est adressable et n'a jamais été le sujet
  ici ; ce qui reste sur ce chemin est exactement le résidu que git cite quoi que
  dise ce réglage — saut de ligne, tabulation, guillemet, contre-oblique. (2) La
  question « porter ou refuser » a déjà été tranchée pour les listes de **chemins**
  et la ligne du tableau de confiance porte l'argument complet : `-z` a été refusé
  parce que le quotage de git protège la convention — un nom à saut de ligne arrive
  comme **une** ligne citée, donc il ne coupe jamais une liste en silence, et
  chaque consommateur peut le refuser à voix haute. **Ce sondage vaut ici et il
  change la moitié « porter » de la décision** : le transport délimité par NUL
  n'est pas nécessaire pour *voir* le nom d'un seul tenant, il ne l'est que pour
  *l'adresser*. Vérifier avant de bâtir : la sonde `s3-saut-de-ligne.bats` a été
  écrite avant [39] et le producteur qui l'alimente a changé — un id fantôme
  produit par un `ls` n'est pas un id fantôme produit par `diff-tree`, et les deux
  lecteurs du tracker ne passent pas par le même.

- **Contrainte pour [18].** L'en-tête de `lib/tracker.sh` pose « un id par ligne »
  comme une clause de l'interface des backends depuis [37]. Ce ticket peut la
  changer ; s'il le fait, c'est cette phrase-là qu'il faut réécrire, pas seulement
  le backend local — un adaptateur distant lit ce contrat et rien d'autre.

- **Le sondage que le commentaire ci-dessus réclamait est fait, le 30/08/2026, et
  il tranche la moitié « porter » de la décision.** Sonde jetable (deux `pack_run`,
  reproduction en trois lignes ci-dessous), plus `s3-saut-de-ligne.bats` rejouée sur
  `82acfcf`. **Il n'y a qu'un producteur cassé, pas deux.**

  Le lecteur **git** de `issues/` est déjà correct depuis [39] + [49]. Le nom arrive
  sur **une seule ligne**, cité par git quoi que dise `core.quotePath` —
  `sed -n l` rend `A\t".scratch/demo/issues/99-a\nb.md"$` — et
  `failures_protect_tracker` le nomme puis refuse de vouer :

      ralph: 01-alpha: ".scratch/demo/issues/99-a\nb.md" moved in the tracker under
        a name this guard cannot address — nothing was put back for it
      ralph: 01-alpha: a path in the tracker moved under a name this guard cannot
        address — nothing here can vouch for the tracker, so the iteration cannot be green

  Le lecteur **glob** est le seul qui casse : `tracker_ids` et `tracker_frontier`
  rendent `01-alpha|99-a|b|`, et `failures_quarantine_strays` annonce
  `quarantined 99-a, b` en laissant le fichier intact.

  **Conséquence pour la décision.** « Porter » (transport NUL) n'achète plus que la
  capacité de **broyer** un ticket qu'un autre garde du même run refuse déjà de
  vouer — donc une itération qui ne peut pas être verte — et que [07]/[21] mettent
  de toute façon en quarantaine puisqu'une session l'a créé. La moitié « porter »
  est donc sans motif : **refuser au producteur glob**, à voix haute, et l'écrire.
  La clause d'interface « un id par ligne » de `lib/tracker.sh` **ne change pas** ;
  ce ticket lui en ajoute une, additive : *un backend ne rend jamais un id qui
  contient un saut de ligne*. `lib/tracker.sh` reste hors de la write-surface.

  **Et une chose que ni la sonde s3 ni ce ticket ne disaient** : dans un run réel
  les deux lecteurs parlent en même temps sur le même nom. L'itération est rouge
  (le garde git refuse de vouer) **et** la frontière est polluée par deux fantômes
  irréclamables. Le test du correctif doit couvrir les deux, sinon il prouve la
  moitié de la panne.

  **Conséquence pour l'ordre** : l'arête `[48] → [18]` passe de forte à moyenne (une
  clause additive, pas une réécriture de contrat), et les arêtes `[48] → [16]` et
  `[48] → [11]` tombent à zéro — aucun format ne change, et personne ne bâtit contre
  des ids fantômes.

  Reproduction :

      before="$(failures_tracker_tree)"
      printf '...' >"$(ralph_feature_dir)/issues/99-a"$'\n'"b.md"
      failures_protect_tracker 01-alpha "$before"

- **Contrainte posée par [11], livré le 04/09/2026 : un nouveau producteur d'ids,
  dont le slug vient d'un modèle.** Le gate de valeur ouvre des tickets
  (`playthrough-wiring-*`, `playthrough-gap-*`) dont le slug est dérivé d'un titre
  écrit par un subagent. `playthrough__oneline` retire les caractères de contrôle
  — sauts de ligne compris — avant `playthrough__slug`, qui ne garde ensuite que
  `[a-z0-9-]` : aucun saut de ligne n'entre dans un id par ce chemin. À vérifier si
  ce ticket change la façon dont un id est fabriqué ou lu, parce que ce chemin
  compte aussi ses propres tickets **en comparant des ids ligne à ligne** ([37]) et
  que la borne de réinjection repose sur ce compte.

- **Livré le 05/09/2026. La décision est *refuser au producteur*, et elle est
  écrite dans le tableau plutôt que déduite du code.** Un prédicat,
  `tracker_local__addressable`, et un refus à voix haute,
  `tracker_local__refuse_name`. Le sondage du 30/08 tenait : il n'y avait qu'un
  producteur cassé, et « porter » n'aurait acheté que la capacité de broyer un
  ticket que `failures_protect_tracker` refuse déjà de vouer.

- **La portée est plus large que « les deux scans », et c'est le seul endroit où
  ce ticket a débordé son énoncé — délibérément.** Le correctif tel que le corps
  le décrivait (filtrer `tracker_ids` et `tracker_frontier`) laissait un dégât
  que le défaut d'origine masquait : `tracker_local__path` compte les fichiers du
  glob `NN-*` pour décider qu'un **numéro nu** est ambigu. Un seul `99-a<LF>b.md`
  dans le répertoire faisait donc refuser `99`, et tout ticket portant
  `Blocked by: 99` sortait de la frontière pour de bon — c'est [27], rouvert par
  un fichier que plus aucun scan ne voit, qu'aucune quarantaine n'atteint et
  qu'aucun renumber ne peut déplacer. La règle appliquée est donc : *un nom que ce
  backend ne rend jamais ne décide de rien à la place d'un id qui en est un*,
  dans les six scans — `frontier`, `ids`, `__path`, `__number_taken`,
  `__slug_taken`, le compte de porteurs de `__renumber_held`. Chacun a son test et
  son témoin appairé, chacun a son entrée de mutation.

- **Le résidu, mesuré et laissé tel quel : `tracker_local__next_nn`.** Elle lit
  `ls` à travers un `sed` qui matche `NN-slug.md` sur une **ligne entière**, donc
  `12<LF>99-x.md` lui offre `99-x.md` comme s'il était un ticket et le numéro
  suivant saute au-delà de 99. Ça ne coûte que des numéros sautés : le numéro
  rendu est de toute façon vérifié contre le répertoire ([27]), et `__path` ne
  résout plus vers le fichier qui l'a suggéré. Écrit dans le code et dans le
  tableau plutôt que corrigé, parce que la corriger voudrait dire réécrire la
  seule fonction du fichier que quatre entrées de mutation ancrent.

- **Ce que la voix coûte, et pourquoi elle est répétée.** Le refus est écrit sur
  la sortie d'erreur à **chaque** scan qui croise le nom — une dizaine de fois par
  itération. Un drapeau « déjà dit » dans une variable de module ne marcherait
  pas : chaque consommateur lit `$(tracker_ids)` **dans un sous-shell**, donc le
  drapeau serait oublié entre deux appelants et la ligne ne sortirait jamais. Un
  témoin dans `$TMPDIR` aurait marché et n'a pas été construit : c'est un
  mécanisme neuf pour un cas rare, et le bruit est le prix d'une panne, pas du
  cas normal. Le nom est rendu avec son saut de ligne **échappé** (`99-a\nb.md`),
  sans quoi le message se couperait en deux comme la liste qu'il dénonce.

- **La frontière de confiance, question 5.** Rien de neuf n'est demandé à une
  session ici : le contrôle ajouté est un prédicat sur un nom de fichier que le
  backend lit lui-même, pas une règle de prompt. Ce qui *reste* non tenu est
  inchangé et maintenant écrit : le fichier reste où il est, sur aucune frontière
  et dans aucun scan, restauré par rien ([21]) et mis en quarantaine par rien
  ([07]) — ces deux-là ne le voient plus non plus. Si une session l'écrit,
  `failures_protect_tracker` le nomme et l'itération ne peut pas être verte ; s'il
  était déjà là au démarrage, **aucun garde ne bouge** et la ligne du producteur
  est le seul témoin qu'un humain aura.

- **Ce que [11] laissait à vérifier est vérifié, et rien ne bouge pour lui.** Ce
  ticket ne change pas la façon dont un id est *fabriqué* : `playthrough__oneline`
  retire les caractères de contrôle avant `playthrough__slug`, donc aucun saut de
  ligne n'entre dans un id par ce chemin, et la borne de réinjection continue de
  compter ses tickets en comparant des ids ligne à ligne ([37]). Ce qui change
  pour lui est favorable et involontaire : un fantôme ne peut plus entrer dans ce
  compte par un autre chemin.

- **Gates sur le code livré** : `bash test/run.sh` = 712 tests, 0 failures,
  6 skips opt-in ; `bash test/mutate.sh` = 708 mutations, 0 not ok.

- **Contrainte écrite dans [18].** La clause « un id par ligne » de l'en-tête de
  `lib/tracker.sh` ne change pas — le fichier est resté hors write-surface — et
  elle gagne un corollaire additif : *un backend ne rend jamais un id qui contient
  un saut de ligne, il le refuse à voix haute*. C'est une obligation d'adaptateur,
  pas un détail du backend local, et elle est écrite dans le ticket [18] et dans
  la ligne du tableau, faute de quoi personne ne la relirait au bon moment.

## Ce que la passe transversale du 05/09/2026 a mesuré du « à voix haute » — ticket [64]

Le **filtre** livré ici n'est pas en cause : les six scans passent bien par
`tracker_local__addressable`, et la règle « un septième scan ajouté sans le filtre
rouvre le trou » tient. Ce que la passe a mesuré est le **rapport**.

- La ligne est dite **huit fois** sur la console d'un run AFK, **zéro fois** dans
  `run.log`, **zéro** dans le reçu d'audit, **zéro** dans `docs/playthroughs/` —
  c'est-à-dire dans les trois seuls artefacts qu'un humain relit le matin. Sur le
  drain humain : six fois sans session, sept avec, console seulement.
- **Quatre consommateurs la jettent** : `playthrough__injected` ([11]),
  `router__tracker_state` ([61]) et `router_protect_tracker` ([55]) lisent
  `$(tracker_ids 2>/dev/null)`. Le commentaire de `tracker_local__refuse_name`
  raisonne soigneusement sur la substitution de commande (« the line has to survive
  being printed from a subshell ») et **jamais sur la redirection**. Ici ça ne
  coûte pas la ligne — les producteurs nus sont plus nombreux — mais ça démontre
  qu'un canal `>&2` posé dans un producteur n'est pas tenable : chaque nouveau
  consommateur décide s'il l'entend.
- Le pack a le canal qu'il faut et il a été écrit pour ce genre-là : [27] a
  construit `tracker_preflight` (« the state **no per-ticket read would ever
  surface** », « **not dispatched: the question is about the shape of ids, which
  the interface owns** ») lu par `loop__report_tracker_findings`, qui produit une
  ligne `loop_log` **et** une ligne de journal. Il ne porte qu'`ambiguous-id`.
- Conséquence pour la clause d'interface écrite ici pour [18] : elle n'a **aucun
  logement**. Sondes : `../sondes/passe-05-09/q3-*.bats`.
