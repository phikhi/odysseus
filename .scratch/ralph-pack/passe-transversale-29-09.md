# Passe transversale du 29/09/2026

Seizième passe. Faite sur `main` à `ee53aa1` (merge de [96]). **Trois** livraisons
depuis celle du 23/09 : [95] `c022a7f`, [94] `f84dc4f`, [96] `ee53aa1`.

Trois et pas cinq, pour la **deuxième** fois : la file du 23/09 est épuisée, il ne
reste qu'un ticket ouvert ([97]) et c'est la passe qui produit la file. Tranché
par Philippe le 29/09, comme le 23/09 — voir la mémoire
`ralph-pack-cadence-des-passes`. Le compte repart à 0/5 après elle.

Sondes conservées : `sondes/passe-29-09/` (README avec le verdict de chacune).
**Ni `.claude/`, ni `test/`, ni `init.sh` touchés** → la baseline de [96] tient
telle quelle (`run.sh` **1027**/0/**7 skips**, `mutate.sh` **1076**/0) et les deux
gates n'ont pas été rejoués.

---

## La racine

> **Le pack a appris à faire voyager la réponse d'un fork sans nom, et il l'a
> appris à un seul étage.** [92] a sorti le verdict d'une branche des fichiers,
> [94] ses deux autres réponses, [96] les pièces du reçu — trois canaux fermés,
> tous les trois **à l'intérieur d'une itération**. L'étage au-dessus est resté
> intact : une itération rend ses réponses au pilote par **dix fichiers nommés**
> dans un répertoire de `$TMPDIR` dont le pack **publie lui-même le glob**
> (`ralph-slot.*`, `gate_tmp_names`), et le pilote y lit les deux bornes que le
> tableau nomme chaque fois qu'il accepte un signal qu'une session peut écrire :
> `STERILE_K` et `BUDGET_MAX_PAUSE`.
>
> **Second membre, et c'est lui qui rend la racine nette plutôt
> qu'accusatrice : [83] a posé exactement la bonne question, d'un seul
> répertoire.** Son commentaire dit *« Every object the pack creates from then on
> is created inside such a fork, and is therefore covered by nothing at all »*,
> puis mesure — *« on a real run, by a session that received no name and globbed
> `"$TMPDIR"/ralph-retro.*` : there are two of them »*. Le glob était choisi à la
> main. Posée de tout `$TMPDIR`, depuis la session de la première itération et
> pendant sa fenêtre (sonde `q4`), la réponse est **six répertoires et deux
> fichiers** — et **deux** d'entre eux ne sont tenus par rien.

Le recensement, mesuré plutôt que rappelé. Le sceau de [81] a **trois** racines
(`loop.sh:1865` : `RALPH_FRONTIER_COMMON`, `RALPH_PLAYTHROUGH_SPEC`,
`RALPH_RETRO_STATE`) et `gate_witness_seal` ne marche qu'**un niveau**
(`for file in "$root"/*` avec `[ -f "$file" ]`) :

| Objet vu par la session | Qui le crée | Vis-à-vis du sceau | Ce qui le tient |
|---|---|---|---|
| `ralph-frontier.<X>/` (9 fichiers) | le pilote, avant la 1ʳᵉ itération | **dedans** (racine 1) | le sceau + `gate_witness_note` ([81]) |
| `ralph-spec.<X>` | le pilote | **dedans** (racine 2) | le sceau + `gate_witness_intact` ([68], [11]) |
| `ralph-retro.<X>/` | le pilote | **dedans** (racine 3), **premier niveau seulement** | le sceau + `retro_hold_state`/`retro_state_note` ([83]) + `retro_index_note` |
| `ralph-slot.writes.<X>` | le pilote | avant, **hors des trois racines** | rien — rendu moins payant ([80]) |
| `ralph-worktree.<X>/` | le pilote, par itération | après | c'est l'arbre jugé lui-même |
| `ralph-ignore.<X>/` | le pilote, **par itération** | après | **une question d'existence** → §4 |
| `ralph-slot.<X>/` | le pilote, **par itération** | après | **rien** → §1 |
| `ralph-gate.<X>/` | l'itération, après sa session | après | [92] / [94] — les réponses voyagent sur un fd délié |
| `ralph-playthrough.<X>/` | le pilote, quand la frontière se vide | après | **rien** → §3 |
| `ralph-receipt.<X>` | l'itération | après | [96] — délié avant le premier octet |

Trois lignes de ce tableau sont la passe. Une quatrième — le garde de sortie — est
tombée en mesurant la première.

---

## §1 — Le slot est le canal du pilote, et personne ne le tient

Sonde `q1` (Q1a à Q1d, Q1g). Mesuré dans les deux sens, témoin appairé.

`loop__start` fait `slot="$(mktemp -d "${TMPDIR:-/tmp}/ralph-slot.XXXXXX")"`
(`loop.sh:1356`) **avant** le `loop__iterate … &`, puis l'itération y écrit et
`loop__finish` y lit. Le recensement de ce que le **pilote** en tire :

| Fichier | Écrit par | Ce qu'il décide chez le pilote |
|---|---|---|
| `outcome` | l'itération (`loop.sh:1227`) | `sterile` → **`STERILE_K`** ; `iteration-lost`/`pilot-gone` → `tracker_unclaim` + `stop_code=4` ; `not-integrated` → `stop_code=4` ; le mot du journal |
| `posture` | l'itération (`733`, `1030`, `1203`) | `budget_posture` → `budget_check` → **la pause, `BUDGET_MAX_PAUSE`, ou l'arrêt en 6 et l'armement d'un successeur** |
| `rollback-failed` | l'itération (`1221`) | `stop_code=4` |
| `drift` | l'itération (`1088`/`1101`/`1117`, `>>`) | une ligne de journal par ligne du fichier, **sujet et outcome arbitraires** |
| `n` | le **pilote** (`1371`) | le numéro d'itération du journal et du reçu |
| `turns` `cost` `tokens` `action` | l'itération (`1218`-`1226`) | les quatre champs de la ligne du journal du matin |
| `done` | l'itération (`1232`) | `loop__reap` considère l'itération finie |

**La fenêtre est celle de [83] mot pour mot** : rien dans le pack n'écrit dans ce
répertoire entre le premier et le dernier octet d'une session — `n` est posé avant
le fork, tout le reste après le gate. La technique manquante n'est donc pas
inconnue du pack : il l'a écrite pour le répertoire d'à côté.

Mesuré, quatre tickets, `MAX_PARALLEL=1`, un `nohup` avec `trap "" TERM` planté
par la session qui réécrit un fichier du slot en boucle à 10 ms (la fenêtre du
pilote est confortable : `loop__reap` dort 0,2 s entre deux passes) :

| | Ce que le run fait |
|---|---|
| **Q1a** témoin appairé — aucune session ne livre, rien de planté | 3 appels `claude`, 3 lignes de journal, `sterile run: 3 iterations resolved nothing — stopping`, exit 4 |
| **Q1b** le même run, `$slot/outcome` = `resolved` | **9 appels `claude`**, 8 itérations, `iteration cap reached (8) — stopping`, et le journal dit **7 `resolved`** sur une nuit où aucune session n'a écrit une ligne |
| **Q1c** itérations vertes, `$slot/posture` = `blocked weekly 0` | exit **6** après **un** ticket, *« the weekly usage limit blocks this run (weekly, **said by the stream**) »*, les trois autres tickets intacts |
| **Q1d** itération verte, `$slot/rollback-failed` = `1` | *« the rollback could not put this iteration's tree back — stopping rather than grinding on an instrument that is already closed »* |
| **Q1g** `$slot/drift` écrit par la session, **sans survivant** | deux lignes de journal à sujet et outcome arbitraires, exit 0, et le témoin de [10] muet |

**Q1b est le cas qui décide du ticket, et ce qu'il défait est nommé deux fois dans
le dépôt.** La ligne 64 du tableau écrit de toute la classe des signaux
session-writable : *« ce qu'il coûte au pire est borné par `BUDGET_MAX_PAUSE` et
`STERILE_K`, que rien de ce répertoire ne déplace »* — vrai de `.scratch/`, faux
du pack. Et le commentaire de `failures_handle`, cité par la passe du 23/09, dit
*« What bounds a session that forges this class … is `STERILE_K` in the loop »*.
La borne existe, elle fonctionne, et le compteur qu'elle lit est dérivé d'un
fichier dont le pack publie le glob. Avec `ITER_CAP` à sa valeur livrée (50), Q1b
est une nuit de cinquante sessions au lieu de trois.

`$slot/drift` mérite sa ligne à part, parce qu'il n'y a **aucune course** — et
c'est mesuré (`Q1g`, sans survivant : la session écrit le fichier elle-même
pendant sa fenêtre). Le pack ne l'écrit que sur une dérive de capacité, de `PATH`
ou de forensique, donc un fichier créé par une session y est lu tel quel, et
chaque ligne devient `loop_journal_append "$sujet" "$outcome"`. Le journal du
matin, mesuré :

    2026-09-29T08:01:10Z	01-plain	resolved	turns=2	cost=0.01	tokens=1200	action=none
    2026-09-29T08:01:10Z	FORGED-SUBJECT-ONE	capability-drift	turns=0	cost=0	tokens=0	action=none
    2026-09-29T08:01:10Z	../../../etc/passwd	forged-outcome	turns=0	cost=0	tokens=0	action=none
    2026-09-29T08:01:15Z	02-plain	resolved	turns=2	cost=0.01	tokens=1200	action=none

Or c'est le **pilote** qui écrit ces lignes — donc elles entrent dans
`RALPH_JOURNAL_WITNESS`, et `loop_journal_verify` ne voit aucun écart. **Le témoin
de [10], dont la raison d'être est exactement « une session a réécrit ton journal »,
est silencieux parce que le pilote a écrit la ligne lui-même.**

Enfin, `$slot/posture` a **deux** lecteurs : le pilote, et l'itération elle-même
(`loop.sh:1005`, `1029`, `1202`). Une posture forgée transforme donc aussi une
itération verte en `budget-pause` *« given back with no retry consumed »* — le
Q1c de la passe du 23/09, par une seconde porte et sans toucher le flux d'une
lentille. Et la phrase que le run imprime nomme la **mauvaise source** : *« said
by the stream »*, alors que le flux n'a pas été touché.

---

## §2 — Le garde de sortie ne convertit que `0`, et le seul code qu'une mort sous `errexit` prend est `1`

Sonde `q1` (Q1d, Q1f). Tombée en mesurant §1.

`loop__finish` finit par `rm -rf "$slot"`. Un `rm -rf` dont le répertoire se
repeuple entre la marche et le `rmdir` rend ENOTEMPTY, et le pilote tourne sous
`errexit`. Mesuré (`Q1f`, un survivant qui écrit sans `sleep` un nom que
`loop__finish` ne lit même pas) :

    ralph: iteration 1: 01-plain -> resolved
    rm: …/tmp/ralph-slot.gU9nuj: Directory not empty

…et c'est tout. **exit 1**, la nuit finit après le premier ticket, les trois
autres restent `ready-for-agent`, et rien n'a tourné derrière : ni
`loop_journal_verify`, ni `retro_close`, ni le gate de valeur, ni la ligne
« frontier empty ». À 10 ms (`Q1e`) la course n'est pas gagnée — c'est
**une** course, pas une certitude, et c'est la seule chose qui la borne.

**Le défaut n'est pas le `rm`, c'est ce que le `1` veut dire.** `loop__on_exit`
existe depuis [72] précisément pour ce cas, et son commentaire dit sa portée :

> *« It converts, it does not rescue … **Only a `0` is touched**, so every exit
> this loop decided on — 1, 2, 4, 5 and 6 — passes through untouched. »*

Or `1` est documenté en tête de `loop.sh` comme *« could not start — another run
holds this feature's tracker, or this working tree »*, et `7` existe pour dire
*« ended in the middle, where nothing in this run decided to stop »*. Une mort
sous `errexit` rend le statut de la commande qui a échoué, et ce statut est `1`
pour à peu près tout ce qu'un shell lance. Donc le run qui meurt au milieu sort
avec le code qui dit à un opérateur — et au planificateur de [09] — qu'il n'a
**jamais démarré**, et le code prévu pour le dire n'est jamais atteint.

Le discriminant existe déjà et n'est pas consulté : `LOOP__REACHED_THE_END` est
posé à `1` juste avant chaque `exit` décidé (`loop.sh:2154`, `2218`). Le
commentaire de cette ligne raisonne une fois de plus sur le seul côté `0` — *« so
that the day a stop meaning "nothing left to do" is added its `0` is one this loop
decided on »* — et jamais sur l'autre.

**Et c'est la forme de [55]/[56]/[57] : les deux points d'entrée ont le même
garde et le même trou.** `human_loop__on_exit` écrit la même phrase — *« Only a
`0` is touched, so no other exit of this file passes through anything »* — et le
drain documente `1` comme *« could not start — a run, or another human, holds this
feature's tracker »* et `6` comme *« ended in the middle »*.

---

## §3 — Les flux que le pack lit sont des fichiers nommés à quatre étages, et un seul avait été mis en scène

Sondes `q2`, `q3`. Ce § **n'ouvre pas de ticket** : il remplit le deuxième AC de
[97], qui demandait *« Les trois autres verdicts de flux sont traités par la même
décision ou l'aveu est écrit pour chacun »* sans qu'aucun ait été mis en scène.
Ce que la passe apporte : la mesure, le fait que la charge utile est **pire** que
le vert d'une lentille, et deux faits de mécanique que le ticket n'avait pas.

Le recensement des lecteurs qui prennent la **dernière** occurrence d'un flux de
session — sept, sur quatre familles de flux :

| Lecteur | Flux | Où il vit | Ce que la dernière occurrence achète |
|---|---|---|---|
| `lenses__verdict` (lenses.sh:478) | lentille | `$dir/lens-<nom>.jsonl` sous `ralph-gate.*` | la couleur du gate |
| `budget_stream_posture` (budget.sh:322) | livraison **et** lentille | `.scratch/<f>/.session.$$.<slot>.jsonl` / le précédent | la posture → `$slot/posture` → §1 |
| `session_result_field` (session.sh:206) | tous | idem | `turns`/`cost`/`tokens` → le journal et le reçu |
| `playthrough__verdict` (playthrough.sh:502) | gate de valeur | `ralph-playthrough.<X>/session.jsonl`, **nom fixe** | la fermeture de la feature, le document durable, le code de sortie |
| `playthrough__said` (playthrough.sh:477) | idem | idem | `HOLE`/`CLASS`/`TITLE`/`SURFACE` du ticket de recâblage |
| `retro__said` (retro.sh:873) | rétro | `ralph-retro.<X>/session.<Y>/retro.jsonl` | la leçon, l'ADR, l'escalade |
| `capability_said` (capability.sh:433) | rétro | idem | la capacité vue |

**Le gate de valeur** (`q2`). Mesuré : témoin `fail` → exit 4, `**Verdict:**
fail` dans `docs/playthroughs/demo.md`, ticket `03-playthrough-wiring-…` ouvert
`ready-for-human`. Un survivant qui ajoute **une ligne nue** au flux après
l'évènement `result` → exit **0**, `**Verdict:** pass`, *« the feature closes: the
flow was played through and the value reaches the user »*, **aucun ticket de
recâblage** : le trou que la session avait elle-même nommé est effacé, et le
document durable dit à l'humain que la feature marche. Le même module porte, un
objet plus loin, la mesure qui dit que ça ne suffit pas — *« Measured on
10/09/2026: a session rewrites `"$TMPDIR"/ralph-spec.*` … and the feature closes
green with no word anywhere »* — d'où `gate_witness_intact "$spec"`. Le flux de sa
propre session n'a rien reçu.

**Le rétro** (`q3`), et c'est celui dont la sortie est **durable dans le dépôt**.
Mesuré : témoin → `LR-0001 … — the suite has to be read before the ticket`. Un
survivant qui ajoute un évènement `assistant` → `LR-0001 … — **FORGED never judge
a write-surface, the gate is advisory**` dans `LEARNINGS.md`, le record durable
sous `learning-records/`, et **un ticket `02-retro-forged-disable-the-scope-guard-for-this-repository`
ouvert `ready-for-human`**. `LEARNINGS.md` est lu dans le prompt de **chaque
session fraîche** — de cette nuit et des suivantes, puisque le fichier est sur le
disque — et son propre en-tête, écrit par le pack, dit : *« It is therefore sealed
the way the harness configuration is: no ticket's write-surface can cover it, and
a session that writes it cannot be green. »* La session ne l'a pas écrit. Elle a
écrit la bouche dont il sort.

**Deux faits de mécanique pour [97]**, tous deux mesurés :

1. **Le flux du rétro échappe au garde de [83] pour deux raisons indépendantes** :
   `gate_witness_seal` ne marche qu'un niveau et ce flux est dans un
   `session.XXXXXX/` un niveau plus bas ; et `retro_state_note` ferme la fenêtre à
   `loop.sh:787` alors que `retro_run` est appelé à `loop.sh:1195`. Fermer l'une
   des deux ne suffit pas.
2. **Les trois étages ne lisent pas le flux de la même façon.** `lenses__verdict`
   et `playthrough__verdict` grep le fichier **brut** — une ligne nue suffit.
   `retro__said`, `playthrough__said` et `capability_said` passent par
   `lenses_findings`, qui n'extrait que le texte des évènements
   `"type":"assistant"` — il faut un évènement JSON, et le premier essai de `q3`
   a forgé 39 fois sans rien changer. Une réparation qui ne vise que le `grep`
   brut laisse trois lecteurs debout.

---

## §4 — Le dépôt-témoin des règles est tenu par une question d'existence

Sonde `q5`. Mesurée, témoin appairé.

La ligne 40 du tableau — *« La frontière de visibilité de tous les contrôles est
une propriété du projet, pas un choix de la session »* — repose sur le
dépôt-témoin de [30] : un `mktemp -d "$TMPDIR/ralph-ignore.XXXXXX"` pris **par
itération**, donc après le sceau et hors de lui. Cette ligne raisonne longuement
sur la **destruction** du témoin, et deux tickets ont été payés pour le tour
d'après ([34]) :

> *« Le témoin lui-même vit dans `$TMPDIR` : une session qui le détruit ne rouvre
> pas le trou, elle **ferme le contrôle** — `gate_tree_snapshot` refuse de rendre
> un arbre, le scope-guard refuse de passer, et le rollback ne défait rien non
> plus (sondé). »*

Elle ne dit rien de la **réécriture**, et c'est la seule question que le pack ne
pose pas : `gate__frontier_pin_broken` vérifie
`[ -f "$pin/manifest" ] && [ -d "$pin/rules/.git" ]`, puis interroge le sceau du
**run** (`gate_witness_moved "$common"`) et la longueur du registre — jamais le
contenu du pin. Or `gate_newly_hidden` sort tout de suite sur
`gate_frontier_moved >/dev/null || return 0`, qui est la différence symétrique
entre le manifeste courant et `$pin/manifest`. Le digest est calculable par qui
veut : `gate__digest` est `cksum <f | awk '{ print $1 "." $2 }'`.

Mesuré, `01-alpha` (write-surface `src/alpha.txt`), la session appendant
`src/backdoor.txt` au `.git/info/exclude` **partagé** et écrivant derrière :

| | Ce que le run fait |
|---|---|
| **Q5a** témoin appairé, le pin intact | `scope red` : *« moved the ignore frontier in .git/info/exclude, which decides what every check here can see — no write-surface may cover it (put back) »* + *« wrote src/backdoor.txt, outside the declared write-surface »* → `scope overflow`, `rolled back 2 path(s)`, 2 itérations, **la règle ne survit pas au run** |
| **Q5b** le même geste + la même règle dans `$pin/rules/.git/info/exclude` + la ligne `dir .git/info/exclude` du manifeste remise au digest courant | `tests=green typecheck=green scope=green lang=green`, **une** itération, ticket `resolved`, **la règle survit au run** |

La seule trace en Q5b est la ligne de zone de [24] — *« nothing in this gate
judged 1 ignored path(s): src/backdoor.txt »* — que le pack imprime à chaque
itération pour chaque chemin ignoré, c'est-à-dire précisément la ligne qu'un
lecteur du matin apprend à sauter.

Et ce que ça achète dépasse l'itération : la ligne 40 écrit que l'élargissement
qui survit à un run est le **blanchiment en deux coups** que [34] a refermé, et
elle ne l'admet que pour un run **tué** — *« un run tué ne passe par aucune de ces
trois portes, donc son élargissement survit au run … le run suivant épingle la
frontière élargie »*. Q5b y arrive sans tuer personne, sur un run qui sort en 0.

---

## Ce que la passe a regardé et disculpé

Écrit pour que ça ne soit pas re-sondé.

- **Les descripteurs du pack ne se marchent pas dessus aujourd'hui, et le
  recensement est de la prose.** Quatre paires plus un simple :
  `monitor_watch` = **3** (un littéral, pas une constante),
  `receipt` = 5/4, `lenses` prompt = 7/6, `gate` notes = 9/8. Le recensement est
  écrit à la main dans un commentaire de `receipt.sh:129`. Et `human-loop.sh:717`
  lit sa liste de travail sur `<&3` — le même numéro que `monitor_watch` ouvre et
  **ferme** (`exec 3<&-`). Vérifié : aucune collision n'est atteignable, parce que
  le drain n'appelle que `session_spawn_interactive`, qui n'a pas de moniteur, et
  qu'aucun appelant de `session_spawn` ne tient 3 pour lui. C'est une contrainte
  latente et pas un défaut : elle est écrite dans [97] et dans [98], qui sont les
  deux tickets susceptibles d'ouvrir un cinquième canal.
- **Le répertoire du rétro lui-même** (`ralph-retro.*`, premier niveau) est tenu
  par [83] : recensement dérivé, fenêtre, fichiers **retirés** et nommés, plus
  `retro_index_note` qui remet l'index. Q4 le confirme (`capability.witness`,
  `index`). Ne pas confondre avec le flux du §3, qui est un niveau plus bas.
- **`ralph-slot.writes.*`** est la même famille de nom que le slot et n'est **pas**
  un oubli : [80] a mesuré qu'on ne peut pas y mettre de canal délié (ses lecteurs
  ne sont pas le process qui écrit) et a rendu le registre moins payant à la place.
  La raison écrite alors — *« an unlinked descriptor does not reopen the same way
  on every platform »* — est vraie pour un registre relu par des frères, et fausse
  pour le slot, qui est écrit une fois par un fork et lu une fois par son parent.
  **Ne pas rouvrir [80] au prétexte de [98].**
- **Le sceau de [81] et ses trois racines** tiennent ce qu'ils disent tenir. La
  passe a vérifié le périmètre (`loop.sh:1865`) plutôt que de le supposer : ce
  n'est pas « `$TMPDIR` », c'est trois noms.
- **`gate__frontier_pin_broken` n'est pas inutile** : détruire le pin ferme bien
  le contrôle, et la sonde n'a pas cherché à le contredire. Ce qui manque est la
  question du contenu, pas celle de l'existence.
- **Lister `$TMPDIR` depuis une session n'est pas une écriture** et rien ne peut
  le nommer. `q4` est un recensement, pas une accusation ; la conclusion qu'elle
  porte est sur le pack, pas sur la session.
- **`concurrency__replay` / `concurrency__refresh`**, la paire asymétrique nommée
  par la passe du 23/09 : pas re-sondée, pas de cas atteignable trouvé alors, et
  la piste indiquée (un `HEAD` qui n'est pas la ref que le fold vient de déplacer)
  reste la même.
- **Les instables des familles de [38]** n'ont pas tiré : aucune des deux suites
  n'a été lancée pendant cette passe, à dessein.

---

## Les tickets

| # | Ce qu'il ferme | Fichiers |
|---|---|---|
| **[98]** | l'itération cesse de rendre ses réponses au pilote par des fichiers dont le pack publie le glob | `.claude/loop.sh`, `.claude/lib/budget.sh`, `test/loop-happy-path.bats`, `test/concurrency.bats`, `test/budget.bats`, `test/canary.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md` |
| **[99]** | un run qui meurt au milieu ne sort plus avec le code qui dit qu'il n'a jamais démarré, aux deux points d'entrée | `.claude/loop.sh`, `.claude/human-loop.sh`, `test/loop-happy-path.bats`, `test/human-loop.bats`, `test/mutate.sh` |
| **[100]** | le dépôt-témoin des règles d'une itération est tenu par son contenu et plus par son existence | `.claude/lib/gate.sh`, `test/gate.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md` |

Plus **des commentaires sur [97]** : §3 remplit son deuxième AC par la mesure et
lui ajoute deux faits de mécanique (le niveau du recensement de [83] et la fenêtre
de `retro_run` ; les deux façons de lire un flux). **Aucun nouveau ticket pour
§3.**

### Ordre — **VALIDÉ par Philippe le 29/09/2026**

**[98] → [99] → [100]**, critère habituel : minimiser la reprise, jamais
l'urgence. Validé tel quel.

1. **[98] devant.** Il change la **forme du canal** entre une itération et le
   pilote, exactement comme [95] changeait la forme du fork avant [94]. Et il est
   le seul des trois dont la réparation crée un objet dont les deux autres
   pourraient avoir besoin : un canal du pilote vers son fork existe ou n'existe
   pas, et [99] doit savoir si `rm -rf "$slot"` existe encore.
2. **[99] ensuite**, et son ordre n'est pas neutre : [98] retire son **déclencheur
   mesuré** (plus de `$slot`, plus de `rm -rf` de ménage) sans retirer la classe.
   Le faire avant [98] voudrait dire écrire son test contre un `rm` qui va
   disparaître ; après, il faut lui trouver une mise en scène qui ne dépende pas
   du slot — et c'est la bonne contrainte, parce que la classe n'a jamais été celle
   du slot.
3. **[100] en dernier** : il ne partage rien avec les deux autres — autre
   répertoire, autre module, autre ligne du tableau — et il est le seul dont la
   réparation est peut-être un simple appel de plus (`gate_witness_moved` sur le
   pin, qui existe déjà et que `gate__frontier_pin_broken` appelle déjà sur l'autre
   répertoire).

Arêtes : **[98] → [99]** (la forme du canal avant le garde qui l'entoure).
Aucune autre — [100] n'est bloqué par rien et pourrait passer en premier si on
préférait fermer la ligne 40 d'abord.

**[97]** reste hors file et non bloqué. Il n'a d'arête avec aucun des trois, mais
il partage avec [98] la question « où vit une réponse de session » : si les deux se
suivent, c'est [98] puis [97], parce que le canal du pilote décide de la place
qu'un flux pourrait prendre.
