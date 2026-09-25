# Passe transversale du 23/09/2026

Quinzième passe. Faite sur `main` à `66ac813` (merge de [93]). **Trois**
livraisons depuis celle du 22/09 : [91] `0773c1e`, [92] `c591232`,
[93] `66ac813`.

Trois et pas cinq : la cadence est « tous les 5 tickets livrés », et le cas que
la règle ne couvrait pas s'est présenté — la file du 22/09 est épuisée, les 93
tickets du tracker sont résolus, et **rien ne peut fournir les deux tickets
manquants puisque c'est la passe qui produit la file**. Tranché par Philippe le
23/09 : la passe se fait à 3/5, le compte repart à 0/5 après elle. Troisième
passe d'affilée dont ce qu'elle trouve **est** la file.

Sondes conservées : `sondes/passe-23-09/` (README avec le verdict de chacune).
**Ni `.claude/`, ni `test/`, ni `init.sh` touchés** → la baseline de [93] tient
telle quelle (`run.sh` 997/0/6 skips, `mutate.sh` 1049/0) et les deux gates
n'ont pas été rejoués.

---

## La racine

> **[92] a sorti le verdict des fichiers ; il a laissé sur place tout ce dont le
> verdict se raconte — et dans ce pack, ce qui raconte décide.** Le répertoire
> de travail du gate est le seul endroit où se rencontrent ce qui décide de la
> facturation d'un ticket, ce qui décide de la suite du run, et ce que l'audit
> du matin dira. C'est un `mktemp -d` sous `$TMPDIR`, créé **après** le sceau de
> [81] et **dans** le fork d'une itération, donc hors de toute couverture par
> construction ([83] dit pourquoi ça ne peut pas venir du pilote). [92] y a vu
> deux objets et les a retirés — le `.rc` par branche, le marqueur `timed-out` —
> parce que ces deux-là **étaient** des verdicts. Les cinq autres sont restés, et
> chacun est **en amont** de ce que [92] a fermé : la source d'où la décision est
> tirée, au lieu de la décision.
>
> Et le second membre de la racine : **le porteur n'a pas besoin d'être une
> session.** [92] a fermé « ce qu'une session laisse tourner ». Les trois
> programmes que le pack lance lui-même — `TEST_CMD`, `TYPECHECK_CMD`,
> `RUN_CMD`/`VISUAL_CMD` — ne sont dans aucun groupe, ne sont marchés par
> personne quand ils finissent normalement, et ce qu'ils laissent court pendant
> le gate qui vient de les lancer.

Le répertoire du gate, recensé plutôt que rappelé — ce que le **parent** y lit
après la mort de la branche qui l'a écrit :

| Objet | Qui l'écrit | Ce qu'il décide |
|---|---|---|
| `$dir/<branche>.out` | la branche | `gate__report` (`run.log`) et `receipt_keep_branch` — les constats du reçu |
| `$dir/scope.class` | `gate__scope_guard` | `RALPH_GATE_SCOPE_CLASS` → la **classe d'échec** → le budget de reprise |
| `$dir/lang.zone` | `lang_check` | la ligne de couverture de langue |
| `$dir/lens-<nom>.jsonl` | `session_spawn`, dans la branche | `lenses_refused_posture` → `RALPH_GATE_QUOTA[_ONLY]` → `budget-pause` **et** `$slot/posture`, donc le pilote |
| `$dir/lens-<nom>.prompt` | le parent, lu dans la branche | la **consigne** donnée au juge |

**Ce qui rend la racine nette plutôt qu'accusatrice** : le pack connaît cette
classe et a raisonné dessus une ligne trop tôt. Le commentaire de
`gate__lens_phase` dit, mot pour mot, pourquoi le marqueur `timed-out` devait
sortir — *« a survivor of the session being judged that dropped a `timed-out`
into the gate's directory would silence the refusal check for the whole fan »* —
et la phrase suivante lit ce même contrôle dans un fichier du même répertoire.
Le commentaire de `lib/receipt.sh` explique sur trois paragraphes pourquoi un
reçu ne lit pas `run.log`, et range ses propres pièces à côté. Le dernier
commentaire de [92] nomme les trois objets restants et finit par *« Si ça vaut un
ticket, c'est à une passe de le dire »*. Cette passe le dit, et elle ajoute que
la liste était courte de deux.

---

## §1 — La source du refus est restée là où [92] a pris l'interrupteur

Sondes `q1`, `q5`. Mesuré dans les deux sens, témoin appairé pour chacun.

`lenses_refused_posture "$dir" "$name"` lit `$dir/lens-<nom>.jsonl` et répond
« cette lentille n'a rien jugé parce que l'API a refusé sa session ». Ce que
cette réponse achète est la classe la moins chère du pack :

- `RALPH_GATE_QUOTA_ONLY=1` → l'outcome de l'itération devient `budget-pause` ;
- `failures_classify` rend `budget`, la seule classe qui **ne compte pas** :
  ni `tracker_bump_failures`, ni `reason`, ni branche `failed/<ticket>` ;
- le pilote reçoit `$slot/posture` et décide de **pauser** — puis d'arrêter.

Mesuré, `LENSES=standards`, `MAX_PARALLEL=1`, un `nohup` avec `trap "" TERM`
planté par la session, qui attend `$TMPDIR/ralph-gate.*/lens-standards.jsonl` et
le remplace par un flux sans verdict portant un `rate_limit_event` bloqué :

| | Ce que le run fait |
|---|---|
| **Q1a** témoin appairé — lentille `fail`, rien de laissé | 3 tentatives, `Failures: 3`, `ready-for-human`, `escalated:failed-impl`, exit 4 |
| **Q1b** la même lentille `fail`, avec le survivant | `Failures:` **vide**, ticket `ready-for-agent`, *« given back with no retry consumed »* à chaque tour — le ticket n'est **jamais** escaladé |
| **Q1c** lentille **`pass`** — le gate serait **vert** | *« rolled back 1 path(s) the session touched »*, `budget-pause`, *« the session window is spent — pausing 0s »*, puis `sterile run: 3 iterations resolved nothing — stopping`, exit 4 |

Q1c est le cas qui décide du ticket. L'itération était verte ; son travail est
détruit par le rollback, le ticket n'est jamais facturé, le pilote croit
l'abonnement épuisé, et la nuit s'arrête au bout de trois tours. **Aucune ligne
du run ne nomme quoi que ce soit d'anormal** — les quatre phrases imprimées sont
exactement celles d'une vraie panne de quota.

Ce que ça ne peut pas faire, et il faut le lire avec : ça ne rend pas un rouge
vert. Ça fait l'inverse — et l'inverse est pire ici, parce que la classe `budget`
est précisément celle que le pack a conçue pour ne rien coûter. Le commentaire de
`failures_handle` écrit d'ailleurs ce qui la borne : *« What bounds a session that
forges this class — the in-band signal lives in a file it can write ([23]) — is
`STERILE_K` in the loop »*. La borne existe, elle fonctionne, et ce qu'elle achète
est l'arrêt du run. Elle a été écrite en pensant au flux de la **session de
livraison** ; le flux d'une **lentille** est la chose que le pack croit
non-forgeable, puisqu'elle est spawnée avec `--tools` sans outil d'écriture.

**Le troisième objet, mesuré aussi** (`q5`), et c'est celui que la ligne 35 du
tableau nomme depuis [92] sans que personne l'ait jamais mis en scène. Un
survivant qui écrit `contract` dans `$dir/scope.class`, sur la même suite rouge
que le témoin Q4a (3 tentatives, `Failures: 3`, `escalated:failed-impl`, exit 4) :

    ralph: gate: 01-alpha: tests=red typecheck=green scope=green lang=green
    ralph: scope overflow on 01-alpha: contract
    ralph: 01-alpha: escalated to the human sink (decision)

**Une seule itération**, `Failures:` vide, run **exit 0** — la nuit se termine
« bien » sur un ticket dont la suite est rouge, et l'humain reçoit « conflit de
périmètre, redessine les deux surfaces ». Les deux premières lignes se
contredisent (`scope=green` et « scope overflow ») et rien ne le remarque.

**Le cinquième poste n'a pas été mis en scène et il est nommé ici pour ne pas
être redécouvert** : `$dir/lens-<nom>.prompt` est écrit par le parent et lu dans
la branche, donc réécrire ce fichier est une course — mais ce qu'elle gagne est
la **consigne** donnée au juge, et la fenêtre est ouverte par le même `ls`.

---

## §2 — Le porteur est la commande de test du projet, et personne ne la range

Sonde `q2`. Mesurée, témoin appairé.

[92] a écrit la classe en toutes lettres : *« "la session a fini" et "les process
de la session ont fini" sont deux choses »*. Sa réparation est `set -m` autour
d'**un seul** fork, celui de `session_spawn`, plus `session__sweep`. Le
commentaire dit pourquoi elle s'arrête là : *« it is not needed to collect the
session and it is not wanted for the gate's branches »*.

Recensement dérivé plutôt que rappelé — le pack a **un** `set -m` (`session.sh:73`)
et **trois** sites qui lancent un programme du projet :

| Site | Ce qu'il lance | Dans un groupe ? | Marché au retour normal ? |
|---|---|---|---|
| `gate.sh:4041` | `bash -c "$TEST_CMD"` | non | non |
| `gate.sh:4048` | `bash -c "$TYPECHECK_CMD"` | non | non |
| `playthrough.sh:291` | `bash -c "$cmd"` — `RUN_CMD`, `VISUAL_CMD` | non | non, sauf échéance |

Mesuré, rien d'hostile — un `&` et un `nohup`, ce que fait tout script qui monte
un serveur avant ses tests :

| | Mesuré |
|---|---|
| **Q2a** `TEST_CMD` laisse un `sleep` | run **vert** (exit 0), ticket `resolved`, process **vivant** quand le run a fini, `ppid 1`, **aucune ligne** |
| **Q2b** le même, qui liste `$TMPDIR/ralph-gate.*` | il voit `tests.out scope.out typecheck.out lang.out` |
| **Q2c** témoin appairé — lentille `pass`, rien de laissé | vert, `resolved`, exit 0 |
| **Q2d** le même run, mais `TEST_CMD` laisse le survivant de §1 | ticket jamais résolu, travail roulé en arrière trois fois, `sterile run`, exit 4 |

Q2d est Q1c **sans session hostile**. Et le `pgid` mesuré en Q2a est celui du
pilote lui-même : `proc_group_members` refuse son propre groupe à dessein ([92]),
donc même si quelqu'un pensait à appeler `session__sweep` ici, il ne trouverait
rien — il faut que le fork ait un groupe à lui, comme `session_spawn` en a un.

Deux remarques qui appartiennent au ticket et pas à la passe. Le playthrough est
le membre le plus exposé des trois : `RUN_CMD` **est** un serveur par conception
(*« A server that boots correctly and waits is the normal case »*), il tourne
`cd "$(ralph_project_root)"` — c'est-à-dire dans l'arbre principal de l'humain,
et non dans un worktree jetable —, et son `proc_kill_tree` n'arrive que sur le
chemin d'échéance. Et le chien de garde du gate vise les branches **par pid** :
un groupe change ce que ce garde peut atteindre, donc le ticket touche la course
que [92] a payée d'un rouge.

---

## §3 — Le reçu d'audit est assemblé dans la zone dont il se protège

Sonde `q4`. Mesurée de bout en bout, témoin appairé.

`lib/receipt.sh` s'ouvre sur l'argument qui justifie son existence :

> *« nothing in this pack guards that directory … So a session can rewrite the
> journal — and a receipt assembled from a source the judged session can edit is
> not a receipt, it is a session's account of itself. »*

Et la garantie qu'il oppose, sur la même page :

> *« The receipt is therefore built from … the branch output the gate collected
> before it removed its temporary directory … **None of those is reachable from a
> session's write-surface**, and none of them is a file whose name a session is
> told — this workspace lives in `$TMPDIR` under a `mktemp` name that is never
> exported. »*

Les deux moitiés de cette phrase sont fausses au même endroit. La source citée
(`$dir/<branche>.out`) est dans le répertoire du gate — celui que Q2b énumère —
et le workspace est un `mktemp -d "$TMPDIR/ralph-receipt.XXXXXX"` : **un nom
n'est pas une garde**, c'est la racine de la passe du 10/09 et ce que [80] et
[81] ont payé un ticket chacun. Ses pièces sont quatre fichiers texte — `facts`,
`notes`, `gaps`, `branch.<nom>` — et `receipt__fact` lit la **dernière**
occurrence, donc un `>>` suffit.

Mesuré sur une suite rouge, le reçu déposé dans `receipts/<feature>/01-alpha.md` :

| | Ce que l'humain lit le matin |
|---|---|
| **Q4a** témoin appairé, aucun survivant | `tests=red`, findings `FAIL: 3 of 12 tests failed in src/alpha`, outcome `gate-red` |
| **Q4b** la même suite rouge, un survivant | `tests=green typecheck=green scope=green lang=green`, findings *« the suite passed cleanly on the first attempt »*, outcome **`resolved`** |

Et le document forgé porte toujours, en dernière section, sa propre phrase de
garantie : *« Assembled by the process that measured this iteration … It does
**not** read `run.log` … so the session this receipt is about can rewrite it. »*
Le seul résidu qui trahit en Q4b est `what the loop then did:
escalated:failed-impl`, un fait écrit après la dernière forge ; un survivant qui
couvrirait aussi ce fait ne laisserait rien.

Ce qui distingue ce § du §1 et qui en fait un ticket à part : ici rien n'est
décidé. C'est le seul document durable que la nuit produit sur elle-même, il
survit dans le dépôt, et il est ce qu'un humain lit **à la place** de ce qui
s'est passé.

---

## Ce que la passe a regardé et disculpé

Écrit pour que ça ne soit pas re-sondé.

- **L'environnement que reçoit la commande du projet** (sonde `q3`). `bash -c
  "$TEST_CMD"` hérite de 70 variables : deux `RALPH_*` (`RALPH_DIR`, plus le
  `RALPH_SHIM_STATE` du harnais), **aucune clé de configuration du pack**, et
  **pas `RALPH_WITNESS_SEAL`**. Le sceau de [81] tient face à la commande du
  projet exactement comme face à une session — et la raison est utile à [94] :
  une variable **non exportée** du shell qui forke est héritée par un sous-shell
  et jamais par un `exec`.
- **Le sceau des témoins du run** (`RALPH_FRONTIER_COMMON` : `exclude`, `global`,
  `attributes`, `manifest`, `path`, `ledger`, `guards`, `forensic.witness`). C'est
  un **autre** `$dir` que celui du gate, il est scellé par [81] et sa fenêtre est
  tranchée par [83]. Le manifeste du `PATH` que [91] vient de dériver y vit et est
  couvert. Ne pas confondre les deux répertoires.
- **Ce que `TEST_CMD` écrit dans le worktree après le snapshot.** Déjà nommé à
  chaque itération par `gate_unjudged_changes`, et le commit durable ne stage que
  les chemins de `$changed` — calculé entre deux arbres pris **avant** le fan. Un
  chemin que seule la commande de test a écrit n'entre dans aucun commit.
- **`concurrency__replay` et `concurrency__refresh`, la paire asymétrique.** Le
  premier pose ses deux `git ls-tree` par le **statut** ([59], [60]) et le
  commentaire l'explique longuement ; le second pose les mêmes questions par la
  **vacuité** (`line="$(…)" || line=""`, `[ -z "$(…)" ]`) quatre-vingts lignes
  plus bas, et c'est lui qui fait `rm -f` dans l'arbre de l'humain. L'asymétrie
  est réelle et vaut d'être écrite ici, mais **le cas atteignable n'a pas été
  trouvé** : les deux appels frappent le même dépôt au même instant, donc un refus
  qui atteint le premier atteint le second, et la branche destructrice exige que
  le premier refuse pendant que le second répond. Pas de ticket ouvert dessus.
  Si une passe future cherche, c'est là qu'il faut chercher : un `HEAD` qui n'est
  pas la ref que le fold vient de déplacer.
- **Le `set -m` de [92] et le stop gracieux.** Depuis [92] la session est dans son
  propre groupe, donc un Ctrl-C au terminal ne l'atteint plus et le pilote finit
  l'itération lui-même. C'est **meilleur** que l'état antérieur et c'est ce que
  [25] et [28] voulaient ; le commentaire de `loop__iterate` qui parle d'un signal
  « addressed to the process group » décrit maintenant un cas qui n'arrive plus
  à la session. Rien à ouvrir.
- **`gate_config_keys` (53 entrées) porte toujours la dette de liste écrite à la
  main** que [91] a payée sur `gate_path_programs`. Le tableau le dit déjà aux
  deux endroits. La passe ne l'ouvre pas : il n'y a pas de critère dérivable
  équivalent à « ce que ce pack lance par son nom nu ».
- **Le rouge instable de `test/budget.bats`** (*« a lens the gate's own deadline
  killed is not read as a refusal »*, famille de [38]) n'a pas tiré pendant cette
  passe. Disculpé par la voie structurelle de [57] ; ne pas le poursuivre.

---

## Les tickets

| # | Ce qu'il ferme | Fichiers |
|---|---|---|
| **[94]** | le répertoire de travail du gate cesse d'être le canal par lequel la facturation d'un ticket et la suite du run se décident | `.claude/lib/gate.sh`, `.claude/lib/lenses.sh`, `.claude/lib/lang.sh`, `test/gate.bats`, `test/lenses.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md` |
| **[95]** | ce que le pack lance lui-même est rangé et nommé comme ce qu'une session laisse, aux trois sites et pas au premier | `.claude/lib/gate.sh`, `.claude/lib/playthrough.sh`, `.claude/lib/proc.sh`, `.claude/lib/session.sh`, `test/gate.bats`, `test/playthrough.bats`, `test/proc.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md` |
| **[96]** | le reçu d'audit est assemblé hors de portée de ce dont il rend compte, ou dit ce qu'il ne tient pas | `.claude/lib/receipt.sh`, `.claude/lib/gate.sh`, `test/receipt.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md` |

### Ordre — **validé par Philippe le 23/09/2026**

**[95] → [94] → [96]**, critère habituel — minimiser la reprise, jamais
l'urgence :

1. **[95] devant**, et ce n'est pas le plus gros ni le plus grave. Il change la
   **forme du fork** : `set -m` autour de `gate__start`, un groupe par branche,
   un sweep, et la course du chien de garde que [92] a payée d'un rouge. [94]
   doit précisément trouver comment une branche rend une chaîne à son parent
   maintenant que le fichier ne vaut plus — c'est-à-dire concevoir un canal
   **autour de ce fork**. Le concevoir avant que [95] n'en change la forme, c'est
   le reprendre.
2. **[94] ensuite** : le plus grave des trois et celui dont la réparation est le
   moins évidente. Il hérite de [95] une population de porteurs réduite, ce qui
   ne le rend pas inutile — [95] n'est qu'un TERM, et son propre prix écrit est
   qu'un survivant qui l'ignore reste.
3. **[96] en dernier** : il cite `$dir/<branche>.out` comme source, donc il hérite
   de ce que [94] en aura fait, et ce qui lui reste en propre — son workspace et
   la phrase qu'il imprime sur lui-même — n'appartient qu'à lui.

Arêtes : **[95] → [94]** (la forme du fork avant ce qui le traverse),
**[94] → [96]** (la source avant le document qui la cite). Aucune autre.

### Suite — livraison de [94], 24/09/2026

**[95] ✅ `c022a7f` (+ `d7cf83e`) · [94] ✅ livré le 24/09 · [96] ouvert.**

Ce que [94] a fermé et ce qu'il a **rendu visible sans pouvoir le fermer**, parce
que la distinction décide de la suite de la file :

- **Fermé** : la lecture faite par le **shell qui forke**, dans le répertoire du
  gate, **après la mort de la branche**. Les trois réponses (classe d'échec, ligne
  de couverture, posture de refus d'une lentille) voyagent sur un descripteur d'un
  fichier **délié avant qu'un octet y soit écrit**, et les trois `exec` du pack qui
  lancent autre chose que le pack passent par `gate_notes_shut`. `$dir/scope.class`
  et `$dir/lang.zone` ne sont plus écrits du tout. Le **prompt** d'une lentille est
  sans nom lui aussi — c'était le seul objet de ce répertoire qu'une réécriture
  transformait en vert.
- **Pas fermé, et c'est une trouvaille de livraison → [97]** : le **flux** d'une
  session. Il doit avoir un nom pendant toute la session (`claude` le reçoit par
  une redirection, `monitor_watch` le suit par un descripteur ouvert **par le
  chemin**), et `session.sh` / `monitor.sh` étaient hors de la write-surface de
  [94]. Ce que la passe avait mesuré en `q1c` était donc **deux fenêtres en une** :
  celle du parent (fermée) et celle de la branche (ouverte). La seconde est
  gagnable par un process qui poll, et pour le **verdict** ce n'est même pas une
  course — `lenses__verdict` prend la dernière occurrence. Un `skip` du canari
  garde la faille ; le lever est un AC de [97].

La leçon transversale de cette livraison, pour la passe suivante : **la passe a
nommé le canal et pris le fichier au bout du canal pour la source.** La source
d'une réponse lue dans un flux de session n'est pas le répertoire où le flux est
rangé, c'est le fait qu'un flux de session soit un fichier nommé — et ça, aucun des
trois §  ne le disait. Quatre étages en tirent un verdict.
