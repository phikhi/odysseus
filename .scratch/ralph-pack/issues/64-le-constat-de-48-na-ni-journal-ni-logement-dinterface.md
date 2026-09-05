# 64 — Le constat de [48] n'a ni ligne de journal ni logement d'interface

**What to build:** Faire passer « un fichier de `issues/` que rien ne peut adresser » par le mécanisme que [27] a construit pour ce genre de constat (`tracker_preflight` → `loop__report_tracker_findings`), et donner à la clause « un backend refuse à voix haute » un logement dans l'interface, avant que [18] ait à l'inventer.

**Blocked by:** None

**Write-surface:** `.claude/lib/tracker.sh`, `.claude/lib/tracker-local.sh`, `.claude/loop.sh`, `test/tracker-local.bats`, `test/smoke.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

**Tags:** tracker, observability

- [ ] Un nom que le backend ne peut pas rendre comme id est un **constat de `tracker_preflight`** : une ligne `subject <TAB> outcome <TAB> phrase`, donc une ligne `loop_log` **et** une ligne de journal, dites **une fois** au démarrage — comme `ambiguous-id`.
- [ ] La question étant celle de la **forme d'un id**, elle reste **non dispatchée** : c'est l'interface qui la possède, exactement comme `tracker__ambiguous_numbers`. Un backend qui numérote côté serveur n'y trouve rien, et c'est la bonne réponse, pas une réponse manquante.
- [ ] La clause écrite pour [18] — « un backend ne rend jamais un id porteur d'un saut de ligne, il refuse à voix haute » — est écrite dans l'en-tête de contrat de `lib/tracker.sh`, avec **où** la voix passe. Aujourd'hui elle ne vit que dans le ticket [48] et dans `docs/frontiere-de-confiance.md`.
- [ ] Décider ce que devient le `printf >&2` de `tracker_local__refuse_name` : gardé (et alors dire pourquoi huit répétitions par run valent mieux qu'une), réduit, ou remplacé. Ne pas le laisser tel quel *par défaut*.
- [ ] Le drain humain le dit aussi une fois : `human_loop_preflight` n'appelle pas `loop_preflight`, et c'est écrit comme une décision — donc le chemin est à choisir explicitement, pas à hériter.
- [ ] Entrée de mutation par garantie livrée, plus le témoin appairé.

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

- **Huit fois sur une console que personne ne regarde.** Un run AFK est par définition sans humain. Ce qu'on relit le matin est `run.log`, le reçu et le playthrough, et aucun des trois ne la porte. Famille de [53] (« la phrase qui nomme le marqueur est stdout-only »), avec la circonstance aggravante que le canal existe et qu'il a été écrit pour ce constat-là.

- **Quatre consommateurs jettent la voix.** `playthrough.sh:494` ([11]), `router.sh:539` ([61]) et `router.sh:646` ([55]) lisent `$(tracker_ids 2>/dev/null)`. Le commentaire de `tracker_local__refuse_name` raisonne soigneusement sur la substitution de commande — « the line has to survive being printed from a subshell: every consumer reads these lists as `$(tracker_ids)`, so a "say it once" flag kept in a variable would be forgotten between two callers » — et jamais sur la **redirection**. Ici ça ne coûte pas la ligne (les producteurs nus sont plus nombreux), mais c'est la démonstration qu'un canal `>&2` posé dans un producteur n'est pas tenable : chaque nouveau consommateur décide s'il l'entend.

- **Arête dure : [64] avant [18].** La contrainte écrite pour [18] est « un backend ne rend jamais un id porteur d'un saut de ligne, **il refuse à voix haute** ». La voix vit dans `tracker_local__refuse_name`, un `__` du backend local. `tracker_preflight` — le seul endroit que l'interface possède pour les constats de forme d'id, et explicitement *non dispatché* — n'en parle pas, et l'en-tête de contrat de `lib/tracker.sh` non plus (il renvoie la limite du transport à `docs/frontiere-de-confiance.md`, ce qui est juste pour « une ligne ne peut pas porter un saut de ligne » et muet sur « qui le dit »). Un [18] écrit tel quel réimplémente huit `printf >&2` dans son propre backend, ou ne les écrit pas du tout.

- **Ce qui ne change pas.** Le **filtre** de [48] (`tracker_local__addressable` sur les six scans) est correct et n'est pas en cause : un nom que ce backend ne rend jamais ne décide de rien à la place d'un id qui en est un. Ce ticket ne touche pas au filtre, il touche au **rapport**. Et la règle de [48] reste : un septième scan ajouté sans le filtre rouvre le trou.

- **Ce qui reste écrit au tableau et que ce ticket ne répare pas.** Un fichier au nom porteur d'un saut de ligne présent **avant** le run n'est vu ni par [21] (restauration : il ne bouge pas, donc aucune entrée de `diff-tree`) ni par [07] (quarantaine : elle regarde ce que le registre d'écritures dit d'un nom `<id>.md`). Vérifié une fois de plus dans cette passe : c'est bien la ligne du producteur qui est le seul témoin, ce qui est précisément l'argument de ce ticket.
