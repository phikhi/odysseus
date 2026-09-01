# 58 — une session routée résout le ticket d'en face, et le drain le saute en silence

**What to build:** Fermer le second chemin de la ligne « rien ne sort du puits
humain en `resolved` sans être repassé par le gate ». [55] a rendu aux deux
refus une entrée que la session routée ne peut pas fabriquer — mais les deux
refus gardent des **transitions**, et écrire `**Status:** resolved` dans un
fichier de `issues/` n'en est pas une. Une session routée sur `20-first` écrit
sur `21-second` : le ticket quitte le puits **et** la frontière, aucun gate n'a
rien lu, et le drain le saute sans qu'une seule ligne le nomme.

**Blocked by:** 56

**Write-surface:** `.claude/human-loop.sh`, `.claude/lib/router.sh`,
`test/human-loop.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** resolved

**Tags:** securite, frontiere-de-confiance

- [x] **Un `Status:` terminal écrit par une session routée ne vaut pas une
      livraison.** Trancher explicitement entre restaurer (le mécanisme de [21],
      qui est ce que le pack fait partout ailleurs) et refuser/annoncer, et
      écrire le prix : restaurer un ticket qu'un humain a *voulu* corriger
      pendant la conversation est la suppression que la quarantaine refuse de
      faire — mais l'argument de [55] pour ne pas restaurer portait sur **le
      ticket que le drain tient**, pas sur ses voisins, et la différence est
      exactement ce que ce ticket a à décider.
- [x] **Le saut cesse d'être muet.** `human_loop_main` relit `Status:` avant
      chaque ticket et `continue` en silence — décision de [16], pour ne pas
      perdre bruyamment contre un humain à deux terminaux. Un ticket qui a changé
      d'état *pendant ce drain* n'est pas ce cas-là : il est sauté sans qu'aucune
      ligne, ni à l'écran ni au journal, ne le nomme.
- [x] **Ce qui reste hors de portée est dit.** Le pin de [55] couvre deux champs
      d'un ticket ; ce ticket-ci couvre `Status:` ; `Failures:`, `Blocked by:` et
      le corps restent écrits par une session que rien ne juge. Dire qui garde
      quoi, ou avouer que personne.
- [x] **Une mutation par garantie livrée**, témoin appairé vérifié à la main.

## Ce que [55] a mesuré, à sa livraison (31/08/2026)

Sonde conservée : `.scratch/ralph-pack/sondes/ticket-55/s1-le-ticket-voisin-que-la-session-resout.bats`,
rejouée sur le code livré de [55].

- **S1** — deux tickets dans le puits. La session routée sur `20-first` fait
  `perl -pi -e 's/^\*\*Status:\*\* .*$/**Status:** resolved/'` sur
  `21-second.md`. L'humain tape `o`, `n`, `n`. Résultat : `21-second` sort
  **`resolved`**, et `grep -c '21-second'` sur **toute** la sortie du drain rend
  **0** — pas de dossier, pas de ligne de journal, rien.
- **S1b, témoin appairé** — même drain, mêmes touches, session qui n'écrit rien :
  `21-second` est offert, `ready-for-human`.
- **S1c** — le run AFK lancé derrière sort **`exit 5`**, « rien à moudre ». Le
  ticket a quitté la frontière comme un ticket livré.

## Pourquoi ce n'est pas [55]

[55] ferme le chemin des **transitions** : `router_may_sign_off` et
`router_may_reinject` décident maintenant sur le pin — les champs du ticket tels
que le drain les a pris — et un ticket que rien n'a épinglé ne peut plus être
transitionné du tout. Le chemin d'ici ne passe par aucune des deux : la session
écrit l'état terminal elle-même, et le drain n'est même pas dans la boucle.

## Point de convergence

**L'instantané autour de `human_loop__session`**, que [56] posera pour l'arbre et
que [55] a délibérément choisi de ne pas poser pour le tracker (son pin est deux
variables du process, pas un instantané — les trois raisons sont écrites dans son
ticket). Les trois tickets veulent la même fenêtre ; la
poser une fois est la consigne de [46]. Et [57] a mesuré où elle est : en tête de
la boucle `while :;` de `human_loop__drain_one`, pas à la frontière de ticket —
le menu est ré-offert après une session, donc c'est le seul endroit qui voit *le
retour* d'une session.

## Ce que [56] laisse à ce ticket (écrit le 01/09/2026, à sa livraison)

- **La fenêtre est posée, et c'est un troisième objet et pas l'instantané
  partagé.** `router_pin ID` prend maintenant, au même appel que les deux champs
  de [55], un **témoin de l'arbre de travail** (`ROUTER__PINNED_TREE`), et
  `router_tree_note ID` le relit au retour de chaque session routée, dans
  `human_loop__session`. Ce que les trois tickets partagent est donc bien le
  **moment et l'endroit** — un appel à `router_pin` par ticket, une lecture au
  retour de session — et **jamais l'objet** : un pin de champs ne dit rien d'un
  arbre, et un témoin d'arbre ne dit rien d'un champ.
- **Et ce témoin ne t'aidera pas, ce qui est le point à ne pas se tromper.**
  `router__tree_dirt` **exclut le répertoire de la feature** par
  `gate_is_bookkeeping`, et il le fait parce qu'il le doit : le drain y écrit son
  journal, son verrou de run et le ticket que la transition va marquer, donc un
  témoin qui compterait cette zone ferait refuser le drain sur son propre
  deuxième ticket (mutation `56 the tree witness counts the drain's own
  writing`, vérifiée à la main : huit tests rouges). Un `Status: resolved` écrit
  sur `21-second.md` tombe exactement dans cette zone : il est dans l'écart entre
  l'arbre et `HEAD`, et il est **retiré** avant que quoi que ce soit le regarde.
  Ne pas lire la ligne « le drain sait ce que la session routée a laissé dans
  l'arbre » comme couvrant le tracker — elle ne le couvre pas, par construction.
- **Ce que ça te laisse comme choix** : soit un second lecteur au même appel qui
  regarde *uniquement* `issues/` (l'inverse exact du filtre ci-dessus, et alors
  il faut décider quoi faire du journal et du verrou que le drain y écrit
  lui-même), soit le mécanisme de [21] que ton premier critère met déjà en
  balance. Le premier a l'avantage de coûter une seule fenêtre de plus, prise là
  où les deux autres sont déjà.

## Pièges connus, pour celui qui livre

- **`failures_protect_tracker` ne se rappelle pas tel quel.** Il restaure depuis
  un tree git, exclut ce que la boucle a écrit via le registre de [13] — que ce
  drain n'alimente pas, écrivant `issues/` hors de toute itération — et rend son
  verdict à un appelant qui en fait un échec d'itération. Lire [49] avant : tout
  ce qui bouge sous `issues/` n'est pas un ticket.
- **Le ticket que le drain tient est un cas à part**, et c'est la décision de
  [55] : l'humain a le droit de le corriger pendant la conversation, le pin fait
  seulement que la correction ne décide pas *dans cette passe*. Restaurer celui-là
  serait un changement de politique, pas une réparation.
- **Ne pas confondre avec le durcissement du prompt** — même avertissement que
  [55] : une phrase de plus au prompt de la session routée est un faux vert en
  attente, pas une garantie.

## Ce qui a été livré (01/09/2026)

**Direction tranchée : RESTAURER, et sur les deux seuls états que ce drain sait
écrire sans rien inventer.** Le troisième objet du même appel `router_pin` est
`ROUTER__PINNED_TRACKER` — le `Status:` et l'`Escalation:` de *chaque* ticket,
une ligne `status<TAB>escalation<TAB>id` par ticket — relu au retour de chaque
session routée par `router_protect_tracker`, appelé dans `human_loop__session`
juste après `router_tree_note`.

Ce que la fonction fait, par classe, et pourquoi la ligne est là :

| ce qui a bougé | ce qui lui arrive |
|---|---|
| le ticket que le drain tient | **nommé, jamais restauré** — décision de [55], la correction peut être celle de l'humain et la prochaine touche est la sienne |
| un ticket qui était `ready-for-human` | **remis** par `tracker_mark_escalated` avec la raison épinglée, et nommé |
| un ticket qui était `ready-for-agent` | **remis** par `tracker_mark_ready`, et nommé |
| tout autre état d'origine | **nommé, pas restauré** (voir plus bas) |
| un ticket apparu | nommé, laissé où il est ([21], [27] : une création ne se décrée pas) |
| un ticket disparu | nommé ; aucun instantané de contenu n'est pris, il ne revient pas |

**Pourquoi seulement deux états, et c'est le cœur de la décision.**
`tracker_mark_escalated` et `tracker_mark_ready` écrivent *exactement* ce qui
définit leurs deux états — un statut, la raison que l'appel fournit ou retire, et
un `Claimed:` qu'aucun des deux ne porte. `tracker_mark_resolved` et
`tracker_mark_wontfix` effacent **aussi `Failures:`**, et un claim porte un
propriétaire dont ce drain n'a jamais pris copie : restaurer là, c'est écrire des
champs que rien n'a observés — un second auteur pour un état que personne n'a
mesuré, c'est-à-dire pire que le silence qu'on remplace. Et ce sont les deux
états qui comptent : un faux vert doit quitter le puits ou la frontière, et les
deux sont couverts. La frontière du choix vit dans `router__put_back`, qui rend
`0` remis / `1` état non écrivable / `2` écriture ratée.

**Le prix, assumé.** Une correction demandée à la session routée sur le `Status:`
ou l'`Escalation:` d'un ticket *voisin* est annulée — nommée, donc à refaire en
une touche par le menu qui l'enregistre, jamais perdue en silence. Et un ticket
qui était dans le puits **sans** `Escalation:` en récupère une vide,
`tracker_mark_escalated` étant le seul verbe public qui écrit cet état.

**Le saut muet, second critère.** `human_loop_main` nomme désormais chaque saut
(écran + journal `tracker-drift/skipped`) et les compte à part du décompte
« drained / left ». La liste de travail est lue au début du drain, donc *tout*
saut est un ticket qui a changé d'état pendant ce drain — le cas que [16] avait
choisi de perdre en silence (l'humain à deux terminaux) est toujours perdu, mais
plus en silence. Et `n` ne dit plus « left in the sink » par-dessus un ticket qui
lit `resolved` : c'est la seule sortie par laquelle le ticket tenu — celui qu'on
ne restaure pas — pouvait partir sans un mot.

## Ce qui reste ouvert, et qui le garde

- `Failures:`, `Blocked by:` et le corps de n'importe quel ticket : **personne**.
  Écrit au tableau et dit à l'écran à chaque fois que la fonction parle.
- **Un ticket tiré d'un état non restaurable *vers* le puits** (`resolved` →
  `ready-for-human` + `Escalation: sign-off`) est nommé au moment où ça arrive,
  mais un **drain suivant épinglera cette raison depuis le fichier** et un `s` la
  prendra pour vraie. La ligne de journal est alors la seule trace. Le dégât net
  est borné — le ticket était déjà hors du puits et hors de la frontière, donc
  « re-résolu » le ramène où il était — mais c'est la porte de [55] rouverte d'un
  cran, et elle est écrite ici plutôt que découverte. Test :
  `a state this drain cannot write faithfully is named instead of invented`.
- **Un ticket `claimed` par un run mort qu'une session résout** n'est pas remis :
  le balayage de [12] ne relit pas un ticket résolu. Personne ne le garde.
- **`tracker-drift` n'est pas expliqué par `router_run_notes`**, à dessein : ce
  guichet ne sert que les mots dont la lecture évidente est fausse ([52], [53]),
  et celui-ci est dit en toutes lettres à l'écran au moment où il tombe. La
  conséquence est écrite quand même : un drain **suivant** ne relit pas ces
  lignes, donc ce qu'un drain a remis en place n'est visible que dans `run.log`,
  qu'un humain doit ouvrir. Si un ticket ultérieur veut ce rappel, c'est
  `router_run_notes` qu'il faut élargir, pas un second journal.
- **Coût ajouté à `router_pin`** : deux `tracker_field` par ticket du tracker, à
  chaque ticket drainé. C'est le même ordre de grandeur que `router_sink`, qui
  fait déjà du O(n²) par `router_unblocks` — mais un appelant qui épinglerait en
  boucle serrée doit le savoir ([11]).

## Pièges rencontrés en livrant

- **Un second producteur d'une phrase rend creuse la mutation de l'ancien.** Le
  message du ticket tenu reprenait mot pour mot « which is not what it said when
  this drain took it » de `router__say_drift` : la mutation
  `55 a refused sign-off does not say the ticket moved under it` est sortie
  **VACUOUS** sur un test parfaitement sain — la session du test écrit *son
  propre* ticket, donc `router_protect_tracker` imprimait la phrase à la place du
  refus. Reformulé (« where this drain took it as ») ; [55] repasse 10/10.
  Diagnostiquer avant de réécrire, comme l'avait consigné [50].
- **Les transitoires de [49] ne se voient pas ici** : `tracker_ids` ne globe que
  `*.md`, et `<id>.md.guard/`, `<id>.md.work.XXXXXX`, `<id>.md.tmp.XXXXXX` ne se
  terminent aucun par `.md`. Vérifié dans le code, pas déduit.
- **Le format de ligne met l'id en dernier** (`status<TAB>escalation<TAB>id`) et
  se relit par `cut -f3-`, pour la raison exacte pour laquelle `router_sink` met
  l'id après le champ de tri ([37]) : un id est un nom de fichier, il peut porter
  une tabulation, et seuls les deux champs que le pack écrit lui-même sont lus
  par position.
- **La fonction écrit dans le tracker depuis une substitution de commande.**
  C'est sain là où [55] avait montré qu'un pin ne pouvait pas l'être : un
  sous-shell ne peut pas rendre une variable à son appelant, il peut très bien
  rendre un fichier. Ce qu'elle ne doit **pas** faire est rafraîchir le pin — la
  base reste ce que le drain a pris, donc une seconde session dans le même ticket
  redit ce qui est encore vrai.
- **Fail-closed comme [55]** : `router_protect_tracker` sur un ticket que rien
  n'a épinglé **refuse bruyamment** au lieu de retomber sur le tracker. Sans ça,
  un pin vide fait lire *chaque* ticket comme apparu pendant la session, et un
  second point d'entrée ([11]) qui oublierait l'appel recevrait un rapport de
  n'importe quoi au lieu d'un garde manquant.
