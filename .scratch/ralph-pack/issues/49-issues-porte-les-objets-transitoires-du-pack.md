# 49 — `issues/` porte les objets transitoires du pack, et la restauration les ressuscite

**What to build:** Décider ce que le pack fait de **ses propres** objets d'exécution
posés dans des répertoires dont les gardes sont écrits contre une autre forme, et le
tenir aux deux endroits où il en pose. `failures_protect_tracker` traite `issues/`
comme « un répertoire de fichiers de ticket » et restaure tout ce qui y a bougé
autour d'une session ; or le pack y écrit trois sortes de transitoires
(`<id>.md.guard/` du claim, `<id>.md.tmp.XXXXXX` de `state_atomic_write`,
`<id>.md.work.XXXXXX` et `.work.XXXXXX.p` de `set_fields`), dont l'exemption de
[13]/[42] ne peut structurellement pas s'occuper parce qu'elle est indexée par
**id**. Et `docs/frontiere-de-confiance.md` traite `.scratch/<feature>/` comme une
zone qui ne vaut qu'un verrou de run, alors que [47] y a mis un garde dont une
session peut se rendre propriétaire — ce qui n'achète pas « une collision » mais
l'espace des numéros entier, pour la nuit et pour les runs suivants.

**Blocked by:** None

**Write-surface:** `.claude/lib/failures.sh`, `.claude/lib/tracker-local.sh`,
`.claude/lib/state.sh`, `.claude/lib/gate.sh`, `.claude/loop.sh`,
`test/failures.bats`, `test/gate.bats`, `test/loop-happy-path.bats`,
`test/mutate.sh`, `docs/frontiere-de-confiance.md` — élargie en livrant, voir
« Écarts de write-surface » plus bas

**Status:** resolved

- [x] Un transitoire que le pack écrit dans `issues/` et qui disparaît dans la
      fenêtre d'une sœur n'est plus **ressuscité** par `failures_protect_tracker`.
      Deux directions possibles et il faut trancher, pas les cumuler par réflexe :
      filtrer la comparaison sur ce qui est un fichier de ticket, ou sortir les
      transitoires de `issues/` comme [47] a sorti le sien. Écrire la décision et
      son prix — filtrer laisse une session déposer un non-`.md` dans `issues/` que
      ni ce garde ni la quarantaine ne regardent ; déplacer touche `state.sh`, donc
      tout écrivain atomique du pack, et un temporaire doit rester sur le même
      système de fichiers que sa cible pour que le `mv` soit atomique.
- [x] Un contrôle cesse d'**accuser** une session de ce qu'elle n'a pas fait. La
      note écrite aujourd'hui sur le ticket dit « The 01-alpha session edited the
      tracker itself (N ticket file(s)) » quand la session n'a rien écrit et que les
      N ne sont pas des tickets. C'est la famille que
      `docs/frontiere-de-confiance.md` existe pour attraper ([30] sur
      `core.excludesFile`, [37] sur la quarantaine).
- [x] Un garde de claim ressuscité ne peut plus sortir un ticket de la frontière
      pour le reste du run. Le garde revient avec le pid du **pilote**, qui est
      vivant, et rien ne le relâche jamais — `state_guard_release` ne suit qu'une
      prise réussie. Le ticket reste `ready-for-agent` sur la frontière, le run
      s'arrête stérile, et la seule phrase émise est fausse : « could not claim
      02-beta — someone else has it » désigne un propriétaire qui n'existe pas.
- [x] `run.log` cesse d'être **muet** sur un ticket qu'aucune itération n'a pu
      réclamer. Aujourd'hui il n'a aucune ligne pour lui : seule la console dit
      quelque chose, et personne ne lit une console le matin ([45]).
- [x] Le tableau de `docs/frontiere-de-confiance.md` dit ce qu'une session achète en
      **posant** le garde d'ouverture, et pas seulement en le supprimant. La ligne
      actuelle ([47]) ne nomme que la suppression et en chiffre le prix à « une
      collision entre deux écrivains de la boucle ». Mesuré : une pose survit au
      run, éteint les trois producteurs de tickets **et** `tracker_renumber`,
      c'est-à-dire la réparation de [27] elle-même.
- [x] La cause d'un refus d'allocation atteint un document durable, ou il est écrit
      qu'elle ne le fait pas. Les deux lignes qui nomment le garde sont des
      `printf … >&2` de `tracker_local__open` ; le reçu porte les `gap`
      (« could not create the ticket for … ») sans la raison, et `run.log`
      enregistre `action=escalated:too-big`, qui est la mauvaise cause.
- [x] Un `.open.guard` laissé par un run tué est compté ou balayé par quelqu'un, ou
      il est écrit que personne ne le fait. Aujourd'hui il traverse un run vert
      entier en silence : `gate_leftovers` ne regarde que `$TMPDIR`, et le verrou de
      run — le voisin dont ce garde « hérite l'exposition » — est relâché par son
      trap `EXIT`, ce qui n'est pas le cas de celui-ci.
- [x] Le commentaire de `state.sh` cesse d'être faux par omission. Il énumère ce qui
      couvre en aval la course qu'il ne ferme pas — « les verrous revérifiés à
      chaque itération, le claim qui est un test-and-set sur le `Status:` » — et [47]
      a ajouté un consommateur dont la correction **est** l'exclusion mutuelle, sans
      rien en aval qui revérifie.

## Comments

- **Origine : passe transversale du 27/08/2026**, sur `main` à `fcf45e1` (merge de
  [47]), avant [39]. Document dans
  `.scratch/ralph-pack/passe-transversale-27-08.md`, sondes conservées dans
  `.scratch/ralph-pack/sondes/passe-27-08/` (`q5` Q5a–Q5e, `q6` Q6a/Q6b pour la
  trouvaille 1 ; `q1` Q1a/Q1b et `q2` Q2a pour la trouvaille 2). Ce sont des
  instruments : chacune finit par un `false` volontaire.

- **La racine, et c'est elle qui justifie un seul ticket pour deux sites.** Le pack
  range ses objets d'exécution dans des répertoires dont les gardes sont écrits
  contre une autre forme. [47] a **nommé** ce danger — « `issues/` est l'arbre que
  `failures_protect_tracker` compare autour de chaque session, donc un garde pris là
  arriverait comme un chemin `A`/`D` que la restauration tenterait de
  `checkout-index` » — et s'en est servi pour écarter *son* garde. Personne n'est
  retourné voir ce qui y était déjà, ni ce que la zone d'accueil vaut maintenant
  qu'un garde y vit. Les deux moitiés éditent le même paragraphe du tableau ; les
  séparer coûte deux passes de mutation sur les mêmes fichiers.

- **Pourquoi le registre ne peut pas aider, et il ne faut pas essayer.**
  `failures_protect_tracker` exempte par `failures__in_list "$(basename "$path" .md)"
  "$ours"`. Pour `.../02-beta.md.guard/pid` ce basename est `pid` ; pour
  `02-beta.md.work.IDdYXp` c'est le nom entier. Aucun n'est jamais un id. Sondé
  plutôt que déduit (`q5` Q5e) : registre correctement rempli avec `02-beta`,
  `restored 3 ticket file(s)` quand même. L'exemption est juste et [42] a coûté un
  ticket pour l'installer — la réparation est ailleurs.

- **Le cas miroir est sain, et il borne le ticket.** Un transitoire qui **apparaît**
  dans la fenêtre est un `A`, la branche `A` ne fait rien, `restored` reste à zéro,
  aucune note (`q5` Q5b). Et `tracker_ids` ne glob que `*.md`, donc aucun de ces
  chemins ne devient un intrus pour la quarantaine. Ce qui doit changer est le seul
  chemin `D`.

- **La largeur de la fenêtre, mesurée — à ne pas surestimer en la citant.**
  `failures_tracker_tree` est un `git add -A` de **35 ms** sur `issues/` ; un
  `set_fields` expose son `.work` pendant **15 ms** ; un claim + un unclaim coûtent
  64 ms (`q6` Q6b). Le `52 sur 60` de `q6` Q6a est mesuré avec une sœur qui écrit
  **en boucle**, ce qui est le pire cas et pas l'exploitation. L'énoncé honnête est
  « rare par itération, certain sur un run assez long » : à `MAX_PARALLEL>1`, sur
  des centaines d'itérations, c'est une loterie qu'on finit par gagner. Ne pas
  écrire un test qui *mesure* cette probabilité — le harnais a déjà payé cette
  leçon deux fois ([38]). Le test qui tient la garantie est au niveau du module,
  comme `q5` : on met l'état à la main et on assert ce que la restauration en fait.

- **Ce que la trouvaille 2 n'est pas.** Ce n'est pas un faux vert : le pack
  **refuse** d'allouer plutôt que d'allouer sans garde, et la décision de [47] tient.
  C'est un déni durable dont la cause n'atteint aucun document. Et la porte
  d'entrée n'est pas neuve — `.scratch/<feature>/` est déclaré non jugé depuis [12],
  le scope-guard juge le worktree et `ralph_feature_dir` résout dans l'arbre
  principal via `RALPH_DIR` (vérifié, `q1` Q1b : aucune ligne de zone, `scope=green`).
  Ce qui est neuf est **ce que cette zone achète**.

- **Angles déjà disculpés par la passe — ne pas les resonder.**
  `state_guard_release` avec deux sœurs en vol (une sœur refusée ne relâche rien,
  `q4` Q4c ; et un sous-shell n'hérite pas du trap `EXIT`) ; la double reprise d'un
  garde périmé (`q4` Q4a, barrière d'attente active, `both=0` sur 300 tours — la
  course est stagée, pas gagnée, et elle est déjà écrite comme une limite non
  réparée) ; le slug d'un plan de re-slice comme nom de fichier
  (`failures__plan_slug` fait `tr -c 'a-z0-9-' ' '` puis prend le premier mot) ; le
  refus bout en bout du re-slice, qui fonctionne et se dit sur le reçu (`q3`).

- **Deux observations mineures récoltées au passage, à traiter ici si c'est gratuit
  et à laisser sinon.** (a) Le chemin « le re-slice n'a créé aucun enfant » n'écrit
  **rien sur le ticket**, alors que le chemin « split incomplet » y écrit une note :
  un humain qui trie le matin ne distingue pas une allocation refusée d'un plan
  inutilisable sans ouvrir le reçu. (b) La borne annoncée du garde d'ouverture est
  de 6 s et la mesure donne **8 s** (120 × 0,05 s plus le coût de la boucle), et
  `tracker_renumber` la paie **par intrus** : dix fichiers déposés par une session
  coûtent 80 s d'itération immobile.

- **Ordre.** Avant [16] et [18] : [16] est la boucle humaine, donc exactement le
  lecteur d'une frontière dont un ticket a disparu sans qu'aucun journal le dise ; et
  [18] doit implémenter `claim`, `open_ticket` et `open_unique` sur un backend
  distant, donc hériter de la clause « le répertoire du tracker ne contient pas que
  des tickets, et un garde autour d'une session ne doit pas prendre le reste pour
  une édition » plutôt que la redécouvrir. Disjoint de [39], de [46] et de [09].

- **Pièges de harnais, récoltés en écrivant les sondes.** Deux `&` nus ne mettent
  rien en concurrence — le coût du fork est plus large que la fenêtre, et Q4a
  rendait `a_only=3 b_only=297` avant qu'une barrière d'attente active ne ramène
  145/155. Et `set -euo pipefail` plus une affectation depuis une substitution qui
  échoue tue le `pack_run` : la sonde ne rougit pas, elle **pend**, parce que
  l'écrivain lancé en fond garde le tuyau de stdout ouvert et que le `run` de bats
  attend pour toujours. Un `pack_run` dont la sortie est vide n'est pas « en cours ».

## Livraison, le 29/08/2026

### La décision : filtrer, et pas déplacer

Le ticket demandait de trancher entre « filtrer la comparaison sur ce qui est un
fichier de ticket » et « sortir les transitoires de `issues/` comme [47] a sorti le
sien ». **Filtrer**, et c'est le producteur le plus banal des trois qui tranche :
`state_atomic_write` doit écrire **à côté de sa cible** pour que le `mv` soit
atomique, et ses cibles ne sont pas toutes dans `issues/` — un répertoire de
temporaires fixe casserait l'atomicité ailleurs (rien ne garantit un même système
de fichiers), et un répertoire dérivé de `dirname` retomberait dans `issues/`.
Déplacer n'était donc disponible que pour un des trois, le garde de claim, ce qui
aurait laissé les deux autres exactement là où ils sont.

Et le garde de claim reste où il est **pour une raison qui n'est pas la
commodité** : un garde sur un ticket appartient au ticket — un backend distant le
prendrait là où ce ticket vit ([18]) — et ce qui rendait ce placement dangereux
était de l'autre côté, dans un garde qui comparait deux arbres de `issues/` comme
si le répertoire ne contenait que des tickets. C'est ce côté-là qui est corrigé,
une fois, pour les trois sortes de transitoire au lieu d'une seule. Le commentaire
de `tracker_local_claim` porte cet argument, parce que celui de [47] disait le
contraire (« sa fenêtre est de l'ordre de la milliseconde ») et qu'un lecteur qui
retombe dessus doit trouver la décision et pas son ancienne justification.

**Le prix du filtre est écrit, pas tu** : ce qu'une session dépose dans `issues/`
sous un nom qui n'est pas `<id>.md` n'est restauré par personne, et ne l'était déjà
pas mis en quarantaine. Ces chemins sont **nommés** à chaque fenêtre où ils bougent
(`failures__say`, donc journal *et* reçu), avec ce qui les produit normalement, de
sorte que la ligne ne se lise pas comme une accusation. Ligne au tableau de
confiance.

### Ce qui a été livré

- **`failures__is_ticket_path`** (`failures.sh`) : un chemin est un ticket s'il est
  **directement** dans `issues/` et finit par `.md` — la définition qu'utilisent
  déjà `tracker_frontier` et `tracker_ids` (`"$dir"/*.md`). Deux clauses, et elles
  ne répondent pas pour les mêmes producteurs (voir trouvaille 1).
- **`failures_protect_tracker` trie ce qui a bougé en trois** : un ticket (restauré
  comme avant), un chemin que git a dû citer (refus de vouer, itération non verte),
  et le reste (laissé tel quel et nommé). La note « the session edited the tracker
  itself (N ticket file(s)) » et le compte qui la porte ne comptent plus que des
  tickets, donc l'accusation ne peut plus viser une session qui n'a rien écrit.
- **`tracker_local__open_refused`** : la cause d'un refus d'allocation atteint le
  **reçu** — pid détenteur, depuis quand — au lieu des deux `printf … >&2` qui
  étaient tout ce qui la nommait. Les trois producteurs disent déjà qu'aucun ticket
  n'a été ouvert ; aucun ne pouvait dire pourquoi, la raison appartenant au backend.
- **`gate__stale_guards`** : `gate_leftovers` compte aussi les gardes d'exclusion
  laissés dans le répertoire de la feature, **sur la liveness du propriétaire** et
  non sur l'âge (contrairement à `$TMPDIR`, ce répertoire appartient à un seul
  arbre, dont ce run tient le verrou). Générique par nom (`*.guard`), donc un
  quatrième garde en héritera sans qu'on y pense.
- **`loop__claim_refused`** : un ticket qu'aucune itération n'a pu réclamer a
  maintenant une ligne `claim-refused` dans `run.log`, et la phrase dit ce qu'elle a
  observé — le statut a bougé (avec le propriétaire), ou il n'a pas bougé et c'est
  l'exclusion du tracker qui a refusé, auquel cas **personne** ne tient le ticket.
- **Le re-slice qui n'a rien pu créer écrit une note sur son ticket**, comme le
  chemin voisin « split incomplet » le fait déjà (observation mineure (a)).
- **Deux commentaires rendus vrais** : celui de `state_guard_take`, qui énumérait ce
  qui couvre sa course en aval sans le consommateur ajouté par [47] — dont la
  correction *est* l'exclusion mutuelle et qui n'a rien en aval ; et la borne du
  garde d'ouverture, **huit secondes** mesurées et non six, payée **par intrus** par
  `tracker_renumber` (observation mineure (b)).

### Les trouvailles

1. **Le prédicat a deux clauses, et une n'a aucun producteur dans le pack.** Les
   trois transitoires échouent tous sur le suffixe (`pid`, `…md.tmp.XXXXXX`,
   `…md.work.XXXXXX`) ; la clause « pas plus profond que `issues/` » ne sert que
   contre un chemin qu'une **session** peut produire — `issues/drafts/09-ghost.md`,
   créé dans une itération où il est un ajout que personne ne juge, supprimé dans la
   fenêtre de la suivante, où le restaurer remettrait le fichier d'une session sous
   un nom que le tracker n'a jamais porté. Écrit comme un cas testé et pas comme du
   code défensif : entrée de mutation dédiée, sur ce chemin-là.

2. **`gate_unaddressable` gagne un quatrième lecteur, et il fallait décider ce qu'il
   en fait** ([39] pose la question à tout nouveau consommateur d'une liste de
   chemins). Un nom que git cite quand même — tabulation, saut de ligne — ne peut
   être ni restauré ni rangé parmi les transitoires : ce garde est le seul des
   quatre qui ne peut même pas dire si ce qu'il regarde est un ticket. Il **refuse
   de vouer**, l'itération n'est pas verte, et il ne le compte pas comme un ticket
   remis. Avant, le `checkout-index` échouait, `restored` était incrémenté quand
   même et la note accusait la session d'avoir édité un ticket : un contrôle qui
   rend son intention pour son résultat, une fois de plus.

3. **`gate_leftovers` devait rendre deux constats et n'en rendait qu'un.** Sa sortie
   est passée à une ligne par constat, ce qui a obligé à changer son appelant dans
   `loop.sh` (un `loop_log` par ligne) : un `loop_log` d'une chaîne à deux lignes
   imprime la seconde sans le préfixe `ralph:`, dans le fichier qu'un humain grep le
   matin. Écart de write-surface assumé, ci-dessous ; l'entrée de mutation `36
   nothing names what earlier runs left in TMPDIR` a été recalée sur la nouvelle
   forme et reste verte.

### Écarts de write-surface

- **Ajouté `.claude/loop.sh` et `test/loop-happy-path.bats`.** Le critère « `run.log`
  cesse d'être muet » est tenu à l'endroit où la ligne manque, c'est-à-dire dans le
  pilote : `loop_journal_append` est à `loop.sh` et un lib n'a pas le droit
  d'appeler `loop_*` (`test/layering.bats`). Même raison pour l'appelant de
  `gate_leftovers` (trouvaille 3).
- **Non utilisé : `test/state.bats` et `test/tracker-local.bats`.** Ce que ce ticket
  change dans `state.sh` est un **commentaire** — la course qu'il décrit n'a pas
  changé et [47] avait déjà décidé de ne pas la fermer, donc il n'y a pas de
  garantie à muter : conformément à [47], on ne livre pas une réparation qu'aucune
  mutation ne peut rendre rouge. Et la cause d'un refus d'allocation est asservie
  **bout en bout** (`test/failures.bats`, un re-slice dont toutes les créations sont
  refusées par un garde tenu vivant) plutôt qu'au module : c'est le chemin réel, il
  passe par le reçu que le pilote assemble, et un test de module aurait asserté sur
  `receipt_render` piloté à la main.
- **Deux entrées de [47] recalées** (`47 the number is allocated with nothing
  serialising it`, `47 the renumber allocates beside an opening`) : leur ancre
  nommait le `printf` que `tracker_local__open_refused` remplace. Garantie vérifiée
  inchangée, ancre déplacée, les deux repassent `ok`.

### Ce qui reste, et qui le porte

- **Poser le garde d'ouverture n'est empêché par rien**, et ne peut pas l'être ici :
  `.scratch/<feature>/` est hors de l'arbre que le gate juge depuis [12]. Ce que ce
  ticket change est que la conséquence est **écrite** (tableau de confiance) et que
  ses deux effets observables ont désormais un canal durable — la cause sur le reçu,
  le garde orphelin compté au démarrage.
- **Les transitoires restent dans `issues/`**, ce qui est la décision. Un backend
  distant hérite de la clause, notée dans [18] : le répertoire du tracker ne
  contient pas que des tickets, et un garde autour d'une session ne doit pas prendre
  le reste pour une édition.
- **Le résidu de [39]** — un nom que git cite quand même — reste inadressable ici
  comme ailleurs ; ce ticket ajoute seulement le refus explicite. Propriétaire [48].
- **Rien ne balaye** un garde orphelin : il est compté, et repris silencieusement par
  la prochaine allocation, ce qui est le bon comportement. Le balayage appartient à
  l'installeur ([19]), comme pour `$TMPDIR`.

### Notes écrites ailleurs

[12] (le garde du claim reste dans `issues/`, et pourquoi c'est sûr maintenant),
[21] (la restauration ne restaure que des fichiers de ticket, et son prix), [27]
(`tracker_renumber` paie le garde par intrus), [47] (la pose du garde, la borne
mesurée, le garde orphelin compté, la cause sur le reçu), [16] (un ticket
inréclamable a maintenant une ligne de journal), [18] (la clause d'interface).

### Les deux gates

Verts sur `ticket-49`, canari compris, mesurés le 29/08/2026 :

- `bash test/run.sh` = **540 tests, 0 failures, 6 skips** opt-in (533 + les sept
  tests de ce ticket) ;
- `bash test/mutate.sh` = **517 mutations, 0 not ok** (506 + les onze entrées de ce
  ticket), aucun VACUOUS et aucun DRIFTED après recalage des trois entrées
  déplacées.

Nouvelle baseline. Aucun nom toléré : tout rouge est une régression.
