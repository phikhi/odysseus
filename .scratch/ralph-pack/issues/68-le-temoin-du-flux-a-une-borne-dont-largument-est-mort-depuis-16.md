# 68 — Le témoin du flux a une borne dont l'argument est mort depuis [16]

**What to build:** `playthrough_witness` protège `spec.md` contre une session **pendant** un run et laisse l'intervalle **entre deux runs** au motif que ce qui y écrit est un humain. [16] a mis une session non jugée dans cet intervalle. Décider qui possède cet intervalle et l'écrire.

**Blocked by:** 66

**Write-surface:** `.claude/lib/playthrough.sh`, `.claude/lib/router.sh`, `.claude/human-loop.sh`, `test/playthrough.bats`, `test/human-loop.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** resolved

**Tags:** playthrough, human-loop, trust-boundary

- [x] Une session routée qui réécrit `spec.md` ne fait pas rejouer au gate de valeur du run suivant un flux que personne n'a promis — ou, si la décision est de le laisser, elle est **dite** : au drain qui l'a laissée faire, et dans le tableau de frontière.
- [x] La borne de `playthrough_witness` cesse d'être écrite comme « pendant un run / entre deux runs » et devient « ce que le pack a vu écrire / ce qu'un humain a écrit ». Aujourd'hui la phrase est vraie de [11] et fausse du pack.
- [x] Le témoin de [11] n'est pas affaibli : une session AFK qui réécrit `spec.md` pendant un run ne doit **toujours** rien changer au prompt du gate de valeur (Q5c est le témoin appairé à ne pas casser).
- [x] Une entrée de mutation par garantie livrée, plus le témoin appairé.

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

- **Livré le 07/09/2026. La sortie choisie est la 1 — le drain nomme — et elle
  est livrée dans la forme de [66] :** `router_pin` prend un `cksum` de `spec.md`
  au moment où il prend le ticket (`ROUTER__PINNED_SPEC`, cinquième objet du même
  appel), et `router_spec_note`, publique, appelée depuis `human_loop__session`
  **comme une instruction** et jamais dans une substitution de commande ([67]),
  nomme au retour de session ce qui a bougé. Trois bras — réécrit, effacé, apparu
  là où il n'y avait rien — une ligne `spec-drift` par bras dans `run.log`, le
  silence et un `1` quand rien n'a bougé ([37]), et un refus qui ne s'exprime pas
  en absence ([59]) : un `spec.md` présent et illisible n'est pas un `spec.md`
  effacé, aux **deux** bouts de l'épinglage (au moment du pin, et au retour).

- **Pourquoi rien n'est remis, et l'argument est neuf.** [66] pouvait s'appuyer
  sur « ce drain n'est pas l'auteur de ces refs ». Le ticket demandait de reposer
  la question ici, sur la foi que « le pack est l'auteur de `spec.md` » —
  **vérifié, et c'est faux** : rien dans `.claude/` n'écrit ce fichier,
  `playthrough.sh` le lit (`playthrough__spec_path`, `playthrough_witness`) et
  signale son absence (`PLAYTHROUGH_UNCONFIGURED`). L'argument tient donc, et il
  s'en ajoute un plus fort : **un humain qui corrige la spec entre deux runs est
  l'écriture pour laquelle ce fichier existe** — c'est la phrase même de [11] — et
  le guichet `admit` sert à avoir cette conversation dans la session routée. Un
  drain qui restaurerait déferait la seule édition que ce point d'entrée sert, sur
  une preuve incapable de la distinguer de celle d'une session. Le témoin ne peut
  donc pas refuser, ce qui exclut aussi la sortie 2.

- **Ce que la sortie 1 achète, et ce qu'elle n'achète pas — dit dans la phrase
  imprimée, pas seulement ici** (AC 1). Les deux résidus de [66] se reproduisent à
  l'identique : l'écriture **survit** au drainage, et l'épinglage est par ticket.
  La ligne met un humain devant la réécriture pendant qu'il est encore assis au
  puits ; elle ne protège **aucun run**. La phrase du bras « réécrit » se termine
  donc par : *the write survives this drain, the next drain takes it as its own
  baseline and says nothing, and the run after that replays it* — et une entrée de
  mutation garde cette phrase (`68 what the naming does not buy is left to be
  discovered`).

- **La borne de `playthrough_witness` (AC 2)** n'est plus « pendant un run / entre
  deux runs » : le commentaire porte une table des **trois écrivains** — une
  session de livraison pendant un run (la copie est déjà prise), une session
  routée au puits (épinglée et nommée depuis ce ticket), un humain dans son
  éditeur (entendu, et c'est le point). La borne est devenue « ce que le pack a vu
  écrire / ce qu'un humain a écrit », et la dernière ligne dit pourquoi la
  deuxième est **nommée** et non refusée : rien ne la distingue de la troisième.

- **La clause de [67] est déclenchée et purgée (AC de rédaction).**
  `router__run_notes_caveat`, sa jumelle en commentaire dans `router_journal_lines`
  et la ligne du dossier affirmaient toutes que `.scratch/<feature>/` n'est gardé
  par rien et ne peut pas l'être. Les trois sont recadrées sur **`run.log`**, avec
  la raison qui fait la différence : personne n'écrit `spec.md` pendant la fenêtre
  surveillée, alors que le flux de session, le journal et le verrou y sont écrits
  par construction. La carte de `router_desk` (livrée par [66], AC 4) gagne sa
  ligne `spec.md` — la write-surface que ce ticket devait remplir — et garde
  l'aveu pour le reste de la zone.

- **Mesuré après correctif** (`../sondes/ticket-68/verification.bats`), sur des
  drains et des runs AFK réels :

  | | |
  |---|---|
  | V1 — la session réécrit `spec.md`, écrit du code et **commite** | réécriture **nommée** (1 ligne, digest de la base citée), `spec-drift` dans `run.log` (1), aucune plainte du témoin de journal. **Résidus mesurés** : le fichier forgé survit, le drainage suivant n'en dit **rien** (0), et le gate de valeur du run d'après rejoue le flux forgé (1) |
  | V2 — la session **efface** `spec.md` | nommé, et la phrase dit ce que ça coûte : la **clôture**. Mesuré derrière : le run suivant sort en **4**, `playthrough` refuse (« spec.md is missing »), **0** appel du gate de valeur. Le sens indulgent ne vaut que pour une réécriture |
  | V3 — témoin appairé : une session qui écrit, commite et déplace un ticket **voisin** | **0** mot du flux, **0** `spec-drift`, **0** plainte du témoin — et la dérive du tracker journalisée (4). Le drain ne s'accuse pas de son propre journal |
  | V4 — un run AFK **réel** avant le drain | **0** mot du flux, **0** `spec-drift` : ni le témoin de [11], ni le journal, ni le reçu ne ressemblent à une dérive |

- **Onze entrées de mutation** (`test/mutate.sh -f "68 "`), toutes `ok` : les deux
  moitiés de l'épinglage (pris / lu vide), les trois bras de la note, la phrase de
  ce que le nommage n'achète pas, le témoin appairé (une note qui parlerait sur un
  fichier intact), l'appel remis dans une substitution de commande (le piège de
  [67], sur la fonction ajoutée après lui), et [59] aux deux bouts du producteur —
  le refus après la session, et le `[ -n "$digest" ]` sans lequel un fichier
  présent et illisible est lu comme un fichier absent. Les sept tests vivent dans
  `test/human-loop.bats`, et les deux refus sont **mis en scène pour de vrai** (un
  répertoire nommé `spec.md`) plutôt que par une fonction masquée : une mutation du
  producteur serait invisible à un test qui le remplace.

- **Ce qui reste ouvert ailleurs, écrit ici parce que personne ne relit un ticket
  clos.**
  1. `receipt.sh` porte encore, en commentaire, « `run.log` lives under
     `.scratch/<feature>/`, and nothing in this pack guards that directory » —
     à moitié faux depuis ce ticket, et hors de la write-surface de celui-ci.
     Contrainte écrite dans [10]. Le raisonnement du reçu, lui, reste juste : ce
     qu'il refuse de lire est `run.log`, que rien ne garde toujours.
  2. Nommer au retour de session ne protège pas le run suivant, et le fermer
     demanderait une base de comparaison à l'échelle du drainage entier — la même
     structure que [66] a laissée ouverte pour les refs (résidu V5). Un ticket qui
     voudrait fermer les deux commence par relire `router_pin` en entier ; deux
     durées de vie dans une seule structure est le prix.
  3. Rien ne nomme une réécriture faite **hors du pack** — un éditeur, un autre
     terminal — et c'est voulu : c'est l'écriture pour laquelle `spec.md` existe.
