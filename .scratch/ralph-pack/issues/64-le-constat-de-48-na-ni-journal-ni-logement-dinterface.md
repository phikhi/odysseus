# 64 — Le constat de [48] n'a ni ligne de journal ni logement d'interface

**What to build:** Faire passer « un fichier de `issues/` que rien ne peut adresser » par le mécanisme que [27] a construit pour ce genre de constat (`tracker_preflight` → `loop__report_tracker_findings`), et donner à la clause « un backend refuse à voix haute » un logement dans l'interface, avant que [18] ait à l'inventer.

**Blocked by:** None

**Write-surface:** `.claude/lib/tracker.sh`, `.claude/lib/tracker-local.sh`, `.claude/loop.sh`, `.claude/human-loop.sh`, `test/tracker-local.bats`, `test/loop-happy-path.bats`, `test/human-loop.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** resolved

**Tags:** tracker, observability

- [x] Un nom que le backend ne peut pas rendre comme id est un **constat de `tracker_preflight`** : une ligne `subject <TAB> outcome <TAB> phrase`, donc une ligne `loop_log` **et** une ligne de journal, dites **une fois** au démarrage — comme `ambiguous-id`.
- [x] La question étant celle de la **forme d'un id**, elle reste **non dispatchée** : c'est l'interface qui la possède, exactement comme `tracker__ambiguous_numbers`. Un backend qui numérote côté serveur n'y trouve rien, et c'est la bonne réponse, pas une réponse manquante.
- [x] La clause écrite pour [18] — « un backend ne rend jamais un id porteur d'un saut de ligne, il refuse à voix haute » — est écrite dans l'en-tête de contrat de `lib/tracker.sh`, avec **où** la voix passe. Aujourd'hui elle ne vit que dans le ticket [48] et dans `docs/frontiere-de-confiance.md`.
- [x] Décider ce que devient le `printf >&2` de `tracker_local__refuse_name` : gardé (et alors dire pourquoi huit répétitions par run valent mieux qu'une), réduit, ou remplacé. Ne pas le laisser tel quel *par défaut*.
- [x] Le drain humain le dit aussi une fois : `human_loop_preflight` n'appelle pas `loop_preflight`, et c'est écrit comme une décision — donc le chemin est à choisir explicitement, pas à hériter.
- [x] Entrée de mutation par garantie livrée, plus le témoin appairé.

## Comments

- **Trouvé par la passe transversale du 05/09/2026** (`../passe-transversale-05-09.md`, §3). Sondes : `../sondes/passe-05-09/q3-*.bats`.

- **Le pack a déjà le mécanisme, et il a été écrit pour exactement ce genre-là.** [27] a construit `tracker_preflight` + `loop__report_tracker_findings`. Son en-tête :

  > One scan, at the preflight, of the state **no per-ticket read would ever surface** […] finding that ticket by ticket in the middle of a night is exactly what this avoids. […] **Not dispatched: the question is about the *shape* of ids, which the interface owns**, not about how a backend stores them.

  Il ne porte qu'un constat : deux tickets qui portent un numéro. [48] en a ajouté un second du même genre exact — un fichier qui n'est sur aucune frontière, qu'aucun scan ne voit, qu'aucun garde ne bouge et qu'aucune quarantaine ne renumérote — et l'a rapporté par un `printf … >&2` nu à l'intérieur de `tracker_ids`.

- **Mesuré** (`q3`, fichier `50-a<LF>b.md` posé **avant** le run) :

  | | |
  |---|---|
  | run AFK, la ligne dite | **8 fois** sur la console |
  | `run.log` la porte | **0 fois** (2 lignes de journal, aucune) |
  | le reçu d'audit la porte | **0 fois** |
  | `docs/playthroughs/<feature>.md` la porte | **0 fois** |
  | drain humain sans session, la ligne dite | **6 fois**, console seulement |
  | drain humain avec session routée, la ligne dite | **7 fois**, console seulement |
  | `playthrough__injected` au module | **0 fois** — `$(tracker_ids 2>/dev/null)` |

  **Depuis [65], livré le 05/09/2026, cette ligne a changé de nom et de rôle sans
  changer de forme.** `playthrough__injected` n'existe plus : la borne de
  réinjection est comptée sur la liste que le run tient lui-même, et plus du tout
  sur les ids du tracker. Le `$(tracker_ids 2>/dev/null)` est maintenant dans
  `playthrough__strangers` — les tickets de câblage que ce run n'a **pas** ouverts,
  qui alimentent la phrase qu'un humain lit quand la borne mord. Le constat est
  inchangé et il s'est aggravé de place : ce n'est plus un compte interne qui perd
  la ligne, c'est la **phrase adressée à un humain**.

- **Huit fois sur une console que personne ne regarde.** Un run AFK est par définition sans humain. Ce qu'on relit le matin est `run.log`, le reçu et le playthrough, et aucun des trois ne la porte. Famille de [53] (« la phrase qui nomme le marqueur est stdout-only »), avec la circonstance aggravante que le canal existe et qu'il a été écrit pour ce constat-là.

- **Quatre consommateurs jettent la voix.** `playthrough.sh:494` ([11] — depuis [65], c'est `playthrough__strangers`), `router.sh:539` ([61]) et `router.sh:646` ([55]) lisent `$(tracker_ids 2>/dev/null)`. Le commentaire de `tracker_local__refuse_name` raisonne soigneusement sur la substitution de commande — « the line has to survive being printed from a subshell: every consumer reads these lists as `$(tracker_ids)`, so a "say it once" flag kept in a variable would be forgotten between two callers » — et jamais sur la **redirection**. Ici ça ne coûte pas la ligne (les producteurs nus sont plus nombreux), mais c'est la démonstration qu'un canal `>&2` posé dans un producteur n'est pas tenable : chaque nouveau consommateur décide s'il l'entend.

- **Arête dure : [64] avant [18].** La contrainte écrite pour [18] est « un backend ne rend jamais un id porteur d'un saut de ligne, **il refuse à voix haute** ». La voix vit dans `tracker_local__refuse_name`, un `__` du backend local. `tracker_preflight` — le seul endroit que l'interface possède pour les constats de forme d'id, et explicitement *non dispatché* — n'en parle pas, et l'en-tête de contrat de `lib/tracker.sh` non plus (il renvoie la limite du transport à `docs/frontiere-de-confiance.md`, ce qui est juste pour « une ligne ne peut pas porter un saut de ligne » et muet sur « qui le dit »). Un [18] écrit tel quel réimplémente huit `printf >&2` dans son propre backend, ou ne les écrit pas du tout.

- **Ce qui ne change pas.** Le **filtre** de [48] (`tracker_local__addressable` sur les six scans) est correct et n'est pas en cause : un nom que ce backend ne rend jamais ne décide de rien à la place d'un id qui en est un. Ce ticket ne touche pas au filtre, il touche au **rapport**. Et la règle de [48] reste : un septième scan ajouté sans le filtre rouvre le trou.

- **Ce qui reste écrit au tableau et que ce ticket ne répare pas.** Un fichier au nom porteur d'un saut de ligne présent **avant** le run n'est vu ni par [21] (restauration : il ne bouge pas, donc aucune entrée de `diff-tree`) ni par [07] (quarantaine : elle regarde ce que le registre d'écritures dit d'un nom `<id>.md`). Vérifié une fois de plus dans cette passe : c'est bien la ligne du producteur qui est le seul témoin, ce qui est précisément l'argument de ce ticket.

- **Place dans la file, validée par Philippe le 05/09/2026 : quatrième**,
  **immédiatement avant [18]**. C'est la plus grosse surface des quatre tickets de
  la passe (`tracker.sh` + `tracker-local.sh` + `loop.sh`) et l'arête **dure** vers
  [18], qui rouvre `tracker.sh` juste après : collés, l'en-tête de contrat est
  écrit et rempli dans la foulée ; séparés, `tracker.sh` est relu deux fois.
  `[18] Blocked by:` porte maintenant `64`. Ordre complet retenu : [63] → [62] →
  [65] → [64] → passe transversale → [18] → [19].

- **Livré le 06/09/2026.** Branche `ticket-64`. Les deux gates verts (chiffres au
  bas de ce ticket). Sondes conservées :
  `../sondes/ticket-64/q3-rejeu.bats` (le rejeu de q3, avec
  `playthrough__injected` renommé `playthrough__strangers` pour [65]) et
  `../sondes/ticket-64/verification.bats` (la sonde « run réel » de ce ticket).

- **La sonde a été rejouée avant d'écrire, et elle a rendu les chiffres du
  ticket à l'unité près** : run AFK 8 fois sur la console, 0 dans `run.log`, 0
  dans le reçu, 0 dans le playthrough ; drain humain 6 fois sans session, 7 avec ;
  `playthrough__strangers` muet au module (`2>/dev/null`). Après livraison, sur la
  même sonde : **1 fois** partout, plus la ligne de journal.

## Ce qui a été livré

- **La voix a changé de propriétaire.** `tracker_local__refuse_name` **n'existe
  plus**. Les deux scans du backend appellent `tracker_refuse_name`, une fonction
  **publique de l'interface** (`lib/tracker.sh`) — le backend ne rend plus aucune
  phrase à lui. C'est ce qui ferme l'arête vers [18] : un nouveau backend appelle
  une fonction et hérite du canal, au lieu de réimplémenter huit `printf >&2`.
  Couche : `tracker-local.sh` appelle un `tracker_` **public** et jamais un
  `tracker__`, donc `test/layering.bats` est satisfait (il ne refuse que les `__`
  d'un voisin et les `loop_*` depuis un lib).

- **Le constat.** `tracker_preflight` émet
  `<nom échappé> <TAB> unaddressable-name <TAB> <phrase>`, exactement la forme
  d'`ambiguous-id`, donc une ligne `loop_log` **et** une ligne de journal, sans
  qu'un mot ait changé dans `loop__report_tracker_findings` : c'est l'intérêt
  d'avoir un canal plutôt qu'un message. Non dispatché, pour la raison écrite par
  [27] : la forme d'un id appartient à l'interface.

- **Comment l'interface apprend les noms, et pourquoi c'est un fichier.**
  `tracker_preflight` crée un temporaire, nomme son chemin aux backends par
  `RALPH_TRACKER_REFUSED` (**jamais exportée**, héritée par les sous-shells — la
  leçon de [40]), prend la liste d'ids, lit le temporaire, l'émet et le
  **supprime**, le tout avant qu'une session existe. Une variable ne peut pas
  porter la collecte : chaque appelant lit la liste dans une substitution de
  commande, donc ce qui est écrit dans ce sous-shell disparaît en revenant — ce
  que [48] avait dit du drapeau « déjà dit » et qui vaut identiquement d'un
  collecteur. Le nom du temporaire est `ralph-tracker.refused.XXXXXX`, couvert par
  le glob `ralph-tracker.*` déjà présent dans `gate_tmp_names` ([62]) : aucune
  ligne à ajouter, et `test/gate.bats` (« every name the pack puts at the top of
  TMPDIR ») reste vert — vérifié isolément avant les gates. Le plancher de ce test
  passe de 18 producteurs à 19, il demande `>= 18`.

- **Décision sur le `printf >&2` (AC4) : remplacé, et réduit.** Remplacé, parce
  qu'il n'est plus dans le backend : la phrase est rendue par
  `tracker__refuse_sentence`, un seul endroit, lu par le constat **et** par le
  repli. Réduit, parce qu'un point d'entrée qui vient de mettre un constat devant
  un humain le dit à l'interface (`tracker_finding_said`), qui fait taire le repli
  pour ce nom-là : **8 → 1** sur un run AFK, **6 → 1** et **7 → 1** sur les deux
  drains. La mémoire est une variable du shell du point d'entrée, non exportée,
  héritée par les sous-shells ; les deux lecteurs bouclent sur un **heredoc** et
  pas sur un pipe, donc ce qu'ils enregistrent l'est bien dans le processus qui
  broie la nuit ensuite.

- **Ce que le repli coûte encore, mesuré et laissé tel quel.** Un fichier
  inadressable déposé **pendant** le run (sonde S2) fait répéter la phrase
  **treize fois** sur trois itérations : aucun préflight de ce run ne pouvait le
  voir, et un `>&2` de producteur n'a pas de mémoire qu'un sous-shell garde. Laissé
  parce que ce cas-là n'est pas muet ailleurs : `failures_protect_tracker` voit le
  fichier arriver sous un nom qu'il ne sait pas adresser, le nomme, refuse de
  vouer pour le tracker ([39], [49]), l'itération est **rouge** et `run.log` porte
  son issue (`tracker-write`). Le cas sans second témoin est celui du fichier
  **déjà là** au démarrage — celui que le constat nomme désormais une fois, dans
  le fichier qu'un humain ouvre. Écrit aussi dans le commentaire de
  `tracker_refuse_name`.

- **Le drain (AC5) : choisi, pas hérité.** `human_loop_preflight` n'appelle pas
  `loop_preflight` — décision datée, écrite dans son préambule — donc rien ne
  descend ici tout seul. Il appelle `tracker_preflight` lui-même et prend le
  second constat **délibérément** : la réparation est un renommage, un renommage
  est d'un humain, et c'est le point d'entrée où un humain est déjà assis. Écrit
  dans `human-loop.sh` à côté de l'appel, et testé
  (`test/human-loop.bats`, « names the file no scan can reach, once » + témoin
  appairé).

- **Une tabulation aussi est échappée, et c'est un défaut trouvé en écrivant.**
  Un nom de fichier peut porter une tabulation ; un constat est
  `subject <TAB> outcome <TAB> phrase`, relu par
  `read -r subject outcome message`. Sans l'échappement, `50-a<LF>b<TAB>c.md`
  décalait tous les champs d'un cran : le journal aurait nommé un `outcome` que
  personne n'a jamais vu et l'humain aurait reçu un tiers de phrase. Test dédié +
  entrée de mutation.

## Ce que ce ticket laisse au dépôt

- **`tracker_refuse_name` est publique et fait partie de l'interface** : tout
  backend qui rencontre un nom qu'il ne peut pas rendre comme id l'appelle, et
  n'imprime rien. La clause est dans l'en-tête de contrat de `lib/tracker.sh`
  avec l'endroit où passe la voix. **Écrit dans [18].**
- **`tracker_finding_said SUBJECT OUTCOME` est appelée par les deux points
  d'entrée** après avoir journalisé un constat. Un troisième point d'entrée qui
  lirait `tracker_preflight` sans l'appeler ne casse rien — il retrouve seulement
  la répétition. C'est la famille [55]/[56]/[57] : la contrainte est écrite ici et
  dans [16].
- **`tracker_preflight` peut désormais rendre non-zéro sur un tracker dont
  `tracker_ids` ne rend rien.** Son ancien `|| return 0` avalait le cas « le
  répertoire ne contient que des fichiers que personne ne peut atteindre », qui
  est exactement celui où un run n'a pas de travail et personne ne sait pourquoi.
- **Le filtre de [48] n'a pas bougé** (`tracker_local__addressable`, six scans) :
  ce ticket ne touche qu'au rapport. La règle de [48] tient toujours — un
  septième scan ajouté sans le filtre rouvre le trou.

- **Contrainte posée par la passe transversale du 07/09/2026.** Le constat que ce
  ticket a fait journaliser par les deux points d'entrée est écrit **avant les
  deux verrous** : `*_report_tracker_findings` tourne dans le préflight, et le
  préflight tourne avant `tree_lock_acquire`. Celui des deux points d'entrée qui va
  perdre le verrou a donc déjà écrit une ligne dans le `run.log` de l'autre, et
  fait tirer son témoin ([10] ou [67]). Mesuré : `../sondes/passe-07-09/q4`.
  La garantie livrée ici — « une fois par run **et** par drain, dans `run.log` et à
  l'écran » — doit rester vraie pour un point d'entrée qui tourne vraiment, et
  devenir « à l'écran seulement » pour celui qui refuse. Propriétaire : **[72]**.
