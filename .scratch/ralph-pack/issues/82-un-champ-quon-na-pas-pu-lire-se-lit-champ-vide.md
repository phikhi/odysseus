# 82 — Un champ qu'un tracker n'a pas pu lire se lit « ce ticket ne porte pas ce champ »

**What to build:** Que les lectures de l'interface d'adaptateur distinguent « ce ticket ne porte pas ça » de « je n'ai pas pu savoir », et que les consommateurs pour qui la différence décide quelque chose la lisent.

**Blocked by:** None

**Write-surface:** `.claude/lib/tracker.sh`, `.claude/lib/forge.sh`, `.claude/lib/gate.sh`, `.claude/lib/lenses.sh`, `.claude/lib/router.sh`, `.claude/lib/claim.sh`, `.claude/lib/concurrency.sh`, `.claude/lib/failures.sh`, `test/tracker-remote.bats`, `test/gate.bats`, `test/mutate.sh`

**Status:** resolved

- [x] `tracker_field` et `tracker_read_ticket` ont un code de retour pour « je n'ai pas pu savoir » distinct de celui pour « ce ticket n'a pas ce champ / n'existe pas », et l'interface l'écrit comme une clause, pas comme une habitude d'un adaptateur.
- [x] La write-surface qu'un scope-guard juge n'est jamais une surface **vide obtenue sur un refus** : le refus est un verdict, pas un périmètre nul.
- [x] Une lentille gatée par un tag ne devient pas « pas concernée » parce que le tracker n'a pas répondu.
- [x] Le pin du drain distingue « ce champ était vide » de « ce champ n'a pas pu être lu », et `router__say_drift` cesse de pouvoir accuser une session routée de ce que le tracker a simplement fini par répondre.
- [x] Le backend local garde exactement le comportement qu'il a : ses deux refus (ticket absent, id ambigu) sont des réponses et pas des « je n'ai pas pu savoir ».

## Comments

- **Trouvé à la passe transversale du 10/09/2026**
  (`../passe-transversale-10-09.md`, §4). Sondes :
  `../sondes/passe-10-09/q1-*.bats`, cas Q1a à Q1d.

- **La famille, et l'étage que personne n'a relu.** [59] a posé la règle (un refus
  n'est pas une réponse), [74] l'a fait lire au point d'entrée, [78] à
  l'ouverture, [79] la porte jusqu'aux appelants d'`open_unique`. Les quatre
  portent sur des **écritures** ou sur des **listes**. Les **lectures d'un champ**
  n'ont jamais été relues.

- **[71] a écrit *comment* une opération refuse — jamais ce qu'un refus veut
  dire.** L'en-tête de `lib/tracker.sh` porte « a refusal is a return code,
  non-zero, and the caller decides what it means », ce qui est exactement le
  problème : il y a **deux** choses à décider et un seul code.

      « ce ticket ne porte pas ce champ »   une réponse
      « je n'ai pas pu savoir »              un refus

  Mesuré sous la mise en scène de [78] (`FORGE_PAGE 2` + `FORGE_PAGES 1`, qui
  fait refuser tous les listings sans simuler de panne) :

  | | `tracker_field 1-alpha Status` (le ticket **existe**) | `tracker_field 999-nexistepas Status` |
  |---|---|---|
  | code | `1` | `1` |
  | valeur | vide | vide |

- **Vingt-huit sites, et tous écrasent les deux en la chaîne vide.**
  `|| status=''`, `2>/dev/null || true`, `[ "$(…)" = x ]`. Ce que le vide veut
  dire chez trois d'entre eux, mesuré :

  | Site | Ce que le vide veut dire | Verdict |
  |---|---|---|
  | `gate_write_surface` | « ce ticket ne déclare rien » | `src/alpha.txt`, que le ticket déclare, est **hors de sa propre surface** (Q1b) |
  | `lenses_has_tag` | « ce ticket ne porte pas ce tag » | la lentille gatée par `Tags: security` **ne voit pas** un ticket qui le porte (Q1c) |
  | `router_pin` | « ce champ était vide au moment du drain » | le pin est vide, et `router__say_drift` accusera la session routée d'avoir écrit ce que le tracker a fini par répondre |

  Témoin appairé Q1d, le même tracker sous un plafond qui tient : `rc=0
  ready-for-agent`, `surface=[src/alpha.txt]`, la lentille voit.

- **Le précédent est à deux lignes du défaut.** `gate__surface_owner` lit bien le
  refus depuis [18] — `ids="$(tracker_ids)" || return 2` — et rend `2` sous le
  même plafond (mesuré, Q1b), avec un appelant qui escalade au lieu de retenter.
  `gate_write_surface` est juste au-dessus dans le même fichier et ne le fait
  pas. La forme de la réparation existe donc déjà dans le dépôt ; ce qui manque
  est la **clause d'interface** qui dit qu'il y a trois réponses et pas deux.

- **Ce que ça ne coûte pas encore, écrit plutôt que laissé à découvrir.** Depuis
  [74], un tracker durablement au-dessus du plafond arrête le run en `4` avant la
  première itération : les trois lignes ci-dessus ne sont pas atteintes par
  *ce* chemin. Elles le sont par les trois que [78] a écrits — `MAX_PARALLEL > 1`
  avec des itérations en vol (`loop__reap 1; continue`), un tracker qui franchit
  le plafond pendant une session, un refus isolé après les réessais de
  `forge__api` — et par un quatrième que la passe ajoute : **le drain**, qui n'a
  pas de `loop__next_ticket` devant lui et qui lit cinq champs par ticket.

- **Le backend local n'a pas ce défaut et il ne faut pas lui en donner un.** Ses
  deux refus sont des réponses : le fichier n'existe pas, ou l'id est ambigu
  (`tracker_local__path`, [27], [48]). Une clause qui l'obligerait à distinguer
  un troisième cas lui ferait inventer un état qu'il n'a pas. Ce que la clause
  doit dire est l'inverse : *un backend qui ne peut pas savoir le dit ; un
  backend qui sait que le ticket n'a pas ce champ répond*.

- **`claim.sh` est le seul des vingt-huit qui distingue déjà les deux** —
  `status="$(tracker_field "$id" Status)" || continue`, donc un ticket dont le
  statut n'a pas pu être lu n'est pas repris. C'est le bon côté du fail-safe, et
  c'est un accident de forme plutôt qu'une décision : il n'y a pas de
  commentaire. Le lui écrire fait partie du ticket.

- **Contrainte que ce ticket crée pour [73]** : la remise du tracker distant lit
  cinq champs plus le corps par ticket et par fenêtre. Un champ qu'on n'a pas pu
  lire y devient « ce ticket ne portait rien », c'est-à-dire une remise qui
  **efface**. Écrit dans [73].

- **Piège de harnais, hérité de [74] et [78]** : `FORGE_PAGE` et `FORGE_PAGES`
  sont des clés déclarées, donc désarmées par `harness__clear_env` ;
  `set_config FORGE_PAGE 2` + `set_config FORGE_PAGES 1` sur un tracker qui porte
  au moins deux issues fait refuser **tous** les listings d'un run.

## Livré le 12/09/2026

- **La sonde du ticket a été rejouée avant d'écrire, et elle dit ce qu'elle
  annonçait.** Sous `FORGE_PAGE 2` + `FORGE_PAGES 1` sur deux issues,
  `tracker_field 1-alpha Status` sur un ticket qui **existe** et
  `tracker_field 999-rien Status` sur un ticket qui n'existe pas rendaient tous
  les deux `1` et une valeur vide. Le témoin appairé (`FORGE_PAGES 4`) rend
  `0 ready-for-agent` pour le premier.

- **Une mesure que le ticket n'avait pas faite, et qui change la clause.** Un
  ticket qui **existe** et ne porte pas le champ demandé rend `0` et une valeur
  vide — sur les deux backends. `tracker_local_field` finit sur un `awk` qui sort
  `0` sans imprimer, et `forge_field` finit sur `forge__field_of`, idem. Le `1`
  ne veut donc pas dire « ce ticket ne porte pas ce champ » mais « il n'y a pas
  de tel ticket », et la clause l'écrit comme ça. C'est aussi ce qui a décidé
  `gate_write_surface` : `rc=1` y est traité comme une **réponse** (surface vide),
  pas comme un refus — sinon un id que le tracker ne porte pas aurait fait
  escalader le scope-guard, ce qui n'est pas la garantie demandée et aurait
  changé le comportement du backend local.

- **Ce qui est livré, dans l'ordre où un lecteur le rencontre.**
  1. `lib/tracker.sh` — la clause : *what a refusal of a read means*. Trois
     réponses (`0` + valeur, `1` « pas de tel ticket », `2` « je n'ai pas pu
     savoir »), tout autre code non nul lu comme `2` (dont le `3` du dispatcher),
     et l'interdiction explicite faite au backend local d'inventer un troisième
     état. Pointeurs sur `tracker_read_ticket` et `tracker_field`.
  2. `lib/forge.sh` — `forge__record` est **la seule ligne** qui doit distinguer :
     `2` sur un listing refusé, `1` sur une issue absente. `forge_field`,
     `forge_read_ticket` et `forge__claimed` propagent par `|| return $?`.
  3. `lib/gate.sh` — `gate_write_surface` prend le champ dans une variable (le
     `| tr` rendait toujours `0` : un pipeline répond pour son dernier maillon) et
     rend `2`. `gate__scope_guard` imprime un constat et écrit `contract` sans
     regarder un seul fichier ; `gate__surface_owner` rend `2` par ticket comme il
     le faisait déjà par liste.
  4. `lib/lenses.sh` — `lenses_has_tag` rend `2` ; `lenses__triggered_by` lit le
     code et fait tourner la lentille. La deuxième moitié de sa question (la
     `Write-surface:`) passe par une variable pour la même raison.
  5. `lib/router.sh` — `router__now`, un lecteur pour les douze sites du fichier
     dont la réponse est **comparée au pin**. `router_pin` ne pinne pas quand un
     des trois champs ou `router__tracker_state` refuse ; `router__say_drift`,
     `router__ticket_digest`, `router__tracker_state`, `router__say_unrestored`,
     `router_protect_tracker` (sa relecture de `tracker_ids`) et la boucle de
     remise lisent le refus.
  6. `lib/claim.sh` — le commentaire que le ticket demandait, **et une seconde
     lecture qui ne distinguait pas** : voir ci-dessous.
  7. `lib/concurrency.sh` et `lib/failures.sh` — les deux autres appelants de
     `gate_write_surface` : voir « errexit » ci-dessous.

- **Ce que `claim.sh` faisait vraiment, et qui n'est pas ce que le ticket
  disait.** Le ticket le donnait comme « le seul des vingt-huit qui distingue
  déjà ». Mesuré : c'est vrai de sa **première** lecture (`Status`, `|| continue`)
  et faux de la seconde, deux lignes plus bas —
  `record="$(tracker_field "$id" Claimed)" || record=""`. Un `Claimed:` vide est
  « personne ne tient ce claim », donc un tracker qui refuse rendait **tous** les
  tickets `claimed` à la frontière pendant que les itérations qui les tiennent
  tournent encore. C'est le mauvais côté du fail-safe, dans la fonction que le
  ticket citait comme le bon exemple. Réparé (`|| continue`), et le commentaire
  dit maintenant la règle pour les deux lectures.

- **Décision : `router_pin` ne rend aucun statut à son appelant, et ce n'est pas
  l'erreur de [79].** [79] a tranché « le statut est le seul canal qui traverse un
  sous-shell » parce qu'il n'y en avait pas d'autre. Ici il y en a un, et c'est
  précisément l'objet du ticket : le pin est un jeu de variables du shell du
  drain, que `router__is_pinned`, `router_protect_tracker`, `router_branch_note`
  et `router_spec_note` lisent déjà, chacun avec sa propre phrase de refus. Un
  non-zéro rendu ici serait de plus **dangereux** : `human_loop__drain_one`
  appelle `router_pin "$id"` nu sous `set -euo pipefail`, donc il finirait le
  drain au milieu du puits au lieu de refuser un ticket. Conséquence :
  `human-loop.sh` n'est pas touché.

- **Ce que le refus coûte côté errexit, et pourquoi deux libs de plus sont dans
  la write-surface.** `gate_write_surface` a trois appelants hors du gate :
  `concurrency_clashes` (deux fois) et `failures_reslice`, tous en affectation
  nue. Sous le `set -e` de `loop.sh`, une affectation nue depuis une fonction qui
  rend `2` **tue le run**. Les deux lisent donc le refus, et c'est la moitié que
  ce ticket leur apporte : sur une surface *vraiment* vide leur fail-safe était
  déjà bon (`concurrency_clashes` répond « clash », donc le ticket tourne seul ;
  la phrase était même déjà écrite au-dessus de la fonction — « A surface this
  pack cannot read is a clash, not a pass » — et n'était pas dans le code).
  `failures_reslice` refuse : ses enfants héritent de cette liste, donc une
  re-slice prise sur un refus donnerait à chacun une write-surface vide, dans le
  seul endroit où l'auteur est la boucle et pas une session.

- **Écart de write-surface, assumé et écrit ici.** Déclarée : `tracker.sh`,
  `forge.sh`, `gate.sh`, `lenses.sh`, `router.sh`, `test/tracker-remote.bats`,
  `test/gate.bats`, `test/mutate.sh`. Livrée : + `claim.sh` (le ticket le demande
  explicitement, sans l'avoir mis dans la surface), + `concurrency.sh` et
  + `failures.sh` (errexit, ci-dessus). En moins : `test/gate.bats` n'est **pas**
  touché. La ligne de write-surface du ticket a été mise à jour.

- **Pourquoi tous les tests sont dans `test/tracker-remote.bats`.** Une garantie,
  une section, un fichier : le backend local n'a pas le troisième état, donc le
  seul tracker qui peut mettre en scène un refus de lecture est le distant, et
  `use_forge` n'existe nulle part ailleurs dans la suite (0 occurrence dans
  `gate.bats`, `lenses.bats`, `human-loop.bats`, `claim.bats`). Deux sections
  neuves : celle du refus **total** (le plafond de pages, sans stub ni panne) et
  celle du refus **partiel**.

- **Le refus partiel, et pourquoi il est mis en scène par un stub.** Six
  garanties ne sont atteignables que si le tracker répond à une lecture et refuse
  la suivante : `gate__surface_owner` (la liste passe, une surface refuse),
  `lenses__triggered_by` sur la surface (la question du tag refuse d'abord si tout
  refuse), `router__tracker_state` dans le pin, la relecture de `tracker_ids` de
  `router_protect_tracker`, sa boucle de remise, et `router__say_unrestored`.
  Aucune configuration d'un backend ne produit ça — un listing refusé refuse
  *tout*. Le stub est celui que le dépôt utilise déjà (`tracker_ids() { return 3; }`
  dans la section AC 5 de [18]) : `tracker_field() { case "$2" in X) return 2 ;;
  *) tracker_local_field "$@" ;; esac; }` refuse **un champ nommé** et rend tout
  le reste au backend. Ce qui est muté reste le lecteur, jamais le refus.

- **Ce que ce ticket n'a pas fermé, nommé plutôt que laissé à retrouver.** Trois
  sites de `router.sh` lisent encore un champ directement, et c'est écrit dans le
  commentaire de `router__now` : `router__field` (présentation — il **doit**
  retomber sur le tracker pour un ticket que rien n'a pinné, c'est [55]), et
  `router_unblocks` / `router_sink`, qui comptent et trient. Un refus y coûte un
  dossier plus pauvre ou un ordre de drainage faux — jamais une accusation, jamais
  une écriture. Non traité, non couvert, pas une garantie.

- **Pièges de mutation rencontrés — le réflexe de [79]/[80]/[81] a payé sept
  fois.** Sept entrées de `test/mutate.sh` s'ancraient sur des lignes que ce
  ticket touche et auraient rendu DRIFTED : `06 a tag on the ticket triggers
  nothing`, `13 a ticket with no write-surface runs beside anything`, `55` ×2
  (`ROUTER__PINNED_ESCALATION`, `ROUTER__PINNED_SURFACE`), `58 the pin records no
  tracker`, `61 the pin records no retry count`, `61 the snapshot records no
  body`. Toutes mises à jour dans le même commit.

- **Piège de perl, mesuré en le payant.** Dans la moitié **motif** d'une entrée,
  `\\\\n` (quatre barres dans la chaîne du shell) matche *deux* barres suivies de
  `n`, pas la séquence `\n` d'un `printf '%s\n'` du fichier. Trois entrées ont
  rendu DRIFTED pour ça. La bonne écriture est `\\\\n` → `\\n` des deux côtés
  (motif et remplacement), vérifié sur un fichier jetable avant de corriger.

- **Six entrées VACUOUS au premier passage du gate de mutation, et ce qu'elles
  disaient.** Toutes les six étaient à ce ticket, et aucune n'était un faux
  positif. Deux causes, les deux instructives :

  1. **Un pin gardé deux fois.** `router__tracker_state` lit `Status`,
     `Escalation`, `Failures` et `Blocked by` de **chaque** ticket. Neutraliser la
     lecture d'`Escalation` de `router_pin` laisse donc le pin vide quand même,
     par le second garde — le test reste vert et l'entrée ment. La réparation
     n'est pas d'assouplir l'entrée : c'est de viser le seul champ que le pin lit
     et que la baseline ne lit pas, **`Write-surface`**. Et de mettre en scène
     chaque lecture par un refus que les autres ne font pas : `Write-surface`
     pour la ligne du pin, `Status` pour la baseline, `tracker_read_ticket` pour
     le digest, `tracker_ids` pour la liste. Quatre bras, quatre refus disjoints,
     quatre garanties isolées — c'est le test « any one read of the pin ».
  2. **Un témoin dont la valeur épinglée était vide.** Le bras de
     `router__say_drift` lisait `Escalation` sur `1-alpha`, qui n'en porte pas :
     le pin valait la chaîne vide, donc un refus lu comme la chaîne vide
     **correspondait** au pin et la phrase n'était jamais imprimée, mutation ou
     pas. La phrase n'existe que sur un pin qui tient quelque chose ; le bras lit
     maintenant `Write-surface` (`src/alpha.txt`).
  3. **Un `set +e` qui désarmait la mutation.** L'entrée du re-slice mute
     l'affectation en affectation **nue** ; sous le `set +e` du test, errexit ne
     tire pas, la fonction continue, ouvre une session de planification et finit
     quand même non zéro — `reslice=1` des deux côtés. L'assertion utile n'est
     pas le statut mais **`claude_call_count` = 0** : ce que la garantie achète
     est qu'aucune session n'est ouverte sur une surface que personne n'a lue.

  Règle à retenir pour la prochaine famille de refus : **une mise en scène qui
  refuse tout ne prouve rien sur un lecteur gardé deux fois.** Il faut un refus
  par lecture, et il faut vérifier que la valeur de référence du témoin n'est pas
  vide — sinon « pas de dérive » est vrai pour la mauvaise raison.

- **Contrainte écrite dans [73]** : la remise d'un tracker distant lit cinq champs
  plus le corps par ticket et par fenêtre, et hérite de la clause — un champ qu'on
  n'a pas pu lire y serait « ce ticket ne portait rien », c'est-à-dire une remise
  qui efface. `router__now` est le précédent de la forme qu'il lui faut.

- **Baselines après ce ticket** : `bash test/run.sh` = 886 tests, 0 failures,
  6 skips opt-in (aucun dans le canari) ; `bash test/mutate.sh` = 915 mutations,
  0 not ok. Les seize tests neufs sont tous dans `test/tracker-remote.bats`
  (60 → 76).

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
