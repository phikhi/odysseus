# 68 — Le témoin du flux a une borne dont l'argument est mort depuis [16]

**What to build:** `playthrough_witness` protège `spec.md` contre une session **pendant** un run et laisse l'intervalle **entre deux runs** au motif que ce qui y écrit est un humain. [16] a mis une session non jugée dans cet intervalle. Décider qui possède cet intervalle et l'écrire.

**Blocked by:** 66

**Write-surface:** `.claude/lib/playthrough.sh`, `.claude/lib/router.sh`, `.claude/human-loop.sh`, `test/playthrough.bats`, `test/human-loop.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

**Tags:** playthrough, human-loop, trust-boundary

- [ ] Une session routée qui réécrit `spec.md` ne fait pas rejouer au gate de valeur du run suivant un flux que personne n'a promis — ou, si la décision est de le laisser, elle est **dite** : au drain qui l'a laissée faire, et dans le tableau de frontière.
- [ ] La borne de `playthrough_witness` cesse d'être écrite comme « pendant un run / entre deux runs » et devient « ce que le pack a vu écrire / ce qu'un humain a écrit ». Aujourd'hui la phrase est vraie de [11] et fausse du pack.
- [ ] Le témoin de [11] n'est pas affaibli : une session AFK qui réécrit `spec.md` pendant un run ne doit **toujours** rien changer au prompt du gate de valeur (Q5c est le témoin appairé à ne pas casser).
- [ ] Une entrée de mutation par garantie livrée, plus le témoin appairé.

## Comments

- **Trouvé par la passe transversale du 06/09/2026** (`../passe-transversale-06-09.md`, §4). Sondes : `../sondes/passe-06-09/q5-*.bats`.

- **Le commentaire de `playthrough_witness` est le meilleur du pack sur ce sujet, et c'est sa dernière phrase qui a vieilli :**

  > **This is a control and not a cache** […] a delivery session can rewrite the user flow this gate replays, and a value gate reading the file on disk would be asking "does the feature do what the last session said it promised". […] Across runs it is the file on disk that seeds it, and that limit is the lesson index's own: **a human who corrects the spec between two runs is heard, a session that rewrites it during one is not.**

  La borne est « pendant un run » contre « entre deux runs », et ce qui la rend sûre est que *ce qui écrit entre deux runs est un humain*. Depuis [16], ce n'est plus vrai : la session routée écrit dans l'arbre principal, sans worktree, sans scope-guard, sans gate, sans rollback, et entre deux runs par définition.

- **Mesuré** (`q5`) :

  | | |
  |---|---|
  | Q5a — une session routée réécrit `spec.md`, puis un run AFK tourne | le prompt du gate de valeur porte le flux **forgé** ; le drain a nommé **0** chemin, le run n'a dit **0** mot du flux |
  | Q5b — témoin appairé, le même run sans le drain | le prompt porte le vrai `spec.md` |
  | Q5c — la **même** réécriture, par une session AFK **pendant** le run | le prompt porte **0** ligne forgée |

  Q5c est la moitié qui empêche de lire ça comme un défaut de [11] : le contrôle fait exactement ce pour quoi il a été écrit. Ce qui a changé est la population de ce qui écrit dans l'intervalle qu'il ne couvre pas.

- **La direction, et elle n'est pas symétrique.** Le compte ne peut pas rendre le gate plus sévère : un flux réécrit rend le gate de valeur **plus indulgent** — `pass` sur une feature qui ne marche pas, une feature close sur un flux que personne n'a promis, et un `docs/playthroughs/<feature>.md` qui raconte ce flux-là à l'humain du matin. C'est le sens opposé à celui de [65] (dont l'effet était « un humain est demandé plus tôt »), donc c'est un **faux vert possible** et pas seulement une autonomie éteinte.

- **Trois sorties, et le ticket doit choisir plutôt qu'hériter.**
  1. **Le drain nomme.** `spec.md` est dans la zone que `router__tree_dirt` saute (`gate_is_bookkeeping`) ; [66] livre le mécanisme qui nomme ce qu'une session routée laisse hors de `issues/`. Une réécriture nommée devant l'humain qui vient de lancer la session est une réparation honnête, et c'est la posture de [11] (« la boucle nomme, l'humain décide »).
  2. **Le drain re-témoigne.** Le drain prend son propre témoin de `spec.md` au moment où il ouvre une session routée, et le compare en sortant. Plus étroit, ne couvre pas une réécriture faite hors du pack.
  3. **Rien, et c'est écrit.** L'arbre principal appartient à l'opérateur ; un humain qui laisse une session écrire sans regarder a la même exposition que sur `RALPH_CONFIG` (déjà au tableau depuis la passe du 31/08). Si c'est la réponse, elle va dans le tableau **et** dans le commentaire de `playthrough_witness`, dont la phrase actuelle dit le contraire.

- **Ne pas confondre avec [65].** [65] a retiré un **scan du tracker** parce que `issues/` a deux écrivains. Ici la source est `spec.md`, un fichier que le pack **doit** relire entre deux runs — c'est ainsi qu'un humain corrige la spec. Le registre d'écritures de [13]/[40] ne répond pas à cette question non plus (il dit ce que la boucle a écrit dans le *tracker*).

- **Contrainte pour [11]** : sa borne est écrite comme une borne de run et son argument nomme un humain. À relire avec ce ticket.

- **Piège de sonde.** Une session routée n'a pas `$FEATURE` dans son environnement : prendre le répertoire par `ls -d "$root"/.scratch/*/`. Et le prompt du gate de valeur se lit par `playthrough_call_stdin 1`, entre `--- spec begins ---` et `--- spec ends ---`.

- **[66] est livré le 07/09/2026 (merge `650f636`), et voici le mécanisme sur
  lequel choisir.** Ce ticket attendait de savoir « ce que [66] aura livré comme
  mécanisme pour nommer ce qu'une session routée laisse hors de `issues/` ». La
  réponse, en une phrase : **un épinglage pris par `router_pin` + une note dite au
  retour de session, qui compte et ne juge rien — rien n'est remis, rien n'est
  refusé.**

  Ce qu'il y a à copier, et c'est une forme entière plutôt qu'une fonction :
  - `router_pin` prend l'objet **au moment où le drain prend le ticket**, avant le
    dossier et avant toute session ; ici ce serait un `ROUTER__PINNED_SPEC` (le
    contenu de `spec.md`, ou son `cksum` — `router__ticket_digest` est déjà écrit
    sous cet argument-là).
  - la note est une fonction publique `router_*_note` appelée depuis
    `human_loop__session` **comme une instruction et jamais dans une substitution
    de commande**, parce qu'elle journalise et que `ROUTER__JOURNAL_WITNESS` est
    une variable du process du drain ([67], point que [66] a hérité tel quel).
    Elle imprime son propre préfixe `ralph: `, rend 0 quand elle a dit quelque
    chose et **1 en silence** quand rien n'a bougé ([37] : un contrôle n'annonce
    pas avoir agi sur ce qu'il a laissé intact).
  - un refus du producteur n'est **pas** une absence ([59]) : `router_branch_note`
    refuse et ne nomme rien quand `git` ne répond pas. Un `spec.md` illisible n'est
    pas un `spec.md` réécrit.

  **Ce qui rend la sortie 1 (« le drain nomme ») disponible telle quelle, et ce
  qui la borne.** `spec.md` est bien dans la zone que `router__tree_dirt` saute,
  et le commentaire de `router_desk` porte désormais la **carte de qui garde
  quelle zone** — l'arbre, `issues/`, les refs, `run.log`, et « le reste de
  `.scratch/<feature>/` : rien, et rien ne le peut ; la pièce qui *décide*
  quelque chose est `spec.md`, et elle est [68]'s ». **Cette ligne de la carte est
  la write-surface de ce ticket** : la remplir ou dire pourquoi elle reste ainsi.
  À relire au même endroit : `router__run_notes_caveat` et sa jumelle dans
  `router_journal_lines` affirment toutes deux que rien ne garde
  `.scratch/<feature>/`. [66] ne les a pas touchées **parce qu'il a mis son garde
  dans `.git/`** ; un garde de [68] est dans `.scratch/<feature>/`, donc les deux
  phrases **deviennent à moitié fausses le jour de la livraison**. C'est un AC de
  ce ticket, pas un détail de rédaction — la même clause que [67] avait posée à
  [66], cette fois réellement déclenchée.

  **Les deux résidus de [66], parce qu'ils se reproduiront ici à l'identique**
  (mesurés, `../sondes/ticket-66/verification.bats`) : l'écriture forgée
  **survit** au drainage, donc le drainage suivant l'épingle et travaille dessus
  (V1) ; et l'épinglage est **par ticket**, donc ce qu'une session écrit est
  nommé au retour de *sa* session puis devient la base du ticket suivant (V5).
  Pour `spec.md`, la seconde a une conséquence propre : nommer au retour de
  session ne protège **pas** le run suivant — c'est ce que la sortie 1 achète et
  n'achète pas, et l'AC 1 demande précisément que ce soit dit plutôt que supposé.

  **Ce qui n'a pas de précédent à copier**, et donc le vrai travail de ce ticket :
  [66] a pu ne rien remettre parce que ce drain n'est pas l'auteur des refs. Le
  pack **est** l'auteur de `spec.md` (`playthrough.sh` l'écrit), donc « rien n'est
  remis » n'est pas gratuit ici et l'argument de `router__put_back` — « ce drain
  ne réécrit que ce qu'un verbe public définit » — doit être posé à neuf. C'est
  aussi ce qui rend la sortie 2 (« le drain re-témoigne ») moins évidente qu'elle
  n'en a l'air : un témoin qui pourrait *refuser* casserait la posture que [69],
  [67] et [66] tiennent au même endroit.

- **Place dans la file, validée par Philippe le 06/09/2026 : quatrième**, derrière
  [66] et avant [18]. C'est le seul des quatre dont la réparation n'est pas
  décidée : il faut d'abord trancher *qui possède l'intervalle entre deux runs*,
  et les trois sorties écrites plus haut dépendent de ce que [66] aura livré comme
  mécanisme pour nommer ce qu'une session routée laisse hors de `issues/`. Livré
  avant [66], il inventerait ce mécanisme ; livré après, il choisit. `Blocked by:
  66`. Ordre complet retenu : [69] → [67] → [66] → [68] → [18] → [19].
