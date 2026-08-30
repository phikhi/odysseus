# Passe transversale du 30/08/2026

Faite sur `main` à `a4ecf90` (merge de [09]), avant [16]. Quatrième passe, après
celles du 07/08, du 26/08 et du 27/08. Déclenchée par le compteur : quatre
livraisons depuis la précédente ([39], [49], [46], [09]), et `CLAUDE.md` en veut
une tous les quatre ou cinq.

Seize sondes dans `sondes/passe-30-08/` (README avec le tableau sonde → question →
verdict). Rien édité dans `.claude/` ni `test/`, donc la baseline des deux gates
de [09] tient telle quelle : `run.sh` 577/0/6, `mutate.sh` 556/0.

Point de départ : les cinq angles que [09] avait écrits pour cette passe, plus les
questions 4 et 5 de `CLAUDE.md`. **Quatre trouvailles, deux disculpations, une
racine.**

## La racine

**Le pack juge ce qu'une session écrit. Rien ne juge ce qui décide de ce que le
pack lui-même exécutera ensuite.**

[46] a fermé un genre de cette famille et l'a nommé pour ce qu'il était : « la
configuration git décide aussi de ce que git exécute ». La ligne du tableau qui
parle de l'écriture hors du dépôt le dit déjà en toutes lettres — *« la ligne
« rien ne le fera ici » reste vraie de ce qui est écrit comme donnée ; elle ne
couvre pas ce que le pack exécute ensuite »* — et donne un propriétaire, [46],
pour le seul cas qu'elle connaissait alors (`~/.gitconfig`).

Il y en a un second, plus large, et personne n'était retourné le chercher : le
**`PATH`**. Il décide quel `git`, quel `claude`, quel `at` le pack exécute — donc
il est en amont de tout ce que [46] a épinglé, `gate_frontier_common` compris,
puisque ce témoin *demande à git* ce que la configuration dit.

Et [09] vient de poser l'objet où cette question se concentre : **la ligne mise en
file**. [09] a très soigneusement demandé ce qu'un successeur hérite comme **ligne
de base** (index de leçons, témoin de capacités, brief de reprise — refusés, sur
l'argument de [40]). Il n'a pas posé la même question sur ce qu'il hérite comme
**contexte d'exécution** : quel programme (`PATH`), quel travail (`FEATURE`), quel
canal (`successor.log`) — et si oui ou non (le marqueur). Les quatre sont pris sur
le run mourant, et trois d'entre eux sont à portée d'une session.

## 1. Le `PATH` du pilote décide de ce que le pack exécute — ticket [52]

`sondes/passe-30-08/r5-le-path-du-pilote.bats`.

Une session, **depuis une itération verte**, écrit un `git` dans un répertoire qui
se trouve sur le `PATH` du pilote — `~/.local/bin`, `/usr/local/bin` sur beaucoup
de macs, `node_modules/.bin` sous `npm run`. Le run courant ne le remarque pas, et
la raison est un détail de bash qu'il faut connaître : le pilote a **hashé** `git`
bien avant que la session existe. Ce qui compte est le run **suivant**, qui est un
bash frais :

    === second run rc=0 02-beta=resolved
    === git calls of the SECOND run through the planted binary:      204
    --- who was calling
    rev-parse --git-dir
    rev-parse HEAD
    worktree list --porcelain
    rev-parse --git-common-dir
    config --get core.excludesFile
    === did that second run say a word about it?
    (nothing)

204 appels, dont exactement ceux dont dépendent le verrou d'arbre ([22]), la
frontière de visibilité ([30], [41], [46]) et l'arbre que le scope-guard juge
([21], [29]). Un `git` interposé ne contourne pas ces contrôles : **il les
fabrique**. Aucune ligne de gate, aucune ligne de zone, aucun reçu, aucune dérive
de capacité — la sonde `R5a` cherche les quatre.

`claude` est la même porte, et pire : le pack le lance par son nom nu, et un
`claude` interposé possède toutes les sessions et toutes les lentilles du run
suivant.

**Et [09] fige ce `PATH` dans la file.** `scheduler_command` écrit
`PATH='<le PATH du pilote>'` en tête de la ligne mise en file, exprès et pour une
bonne raison (« so the successor finds the same `claude` and the same `git` this
run found »). La conséquence n'avait pas été tirée : ce que le run exécutait, le
successeur l'exécutera aussi, des jours plus tard, sans humain — et
`gate_frontier_residue`, la seule chose qui puisse refuser d'armer, ne parle que
de configuration git (`R5b`).

Ce n'est pas « une session peut exécuter du code », qui est assumé au niveau du
pack ([20]). C'est trois choses de plus, qui sont exactement celles que [46] a
jugées dignes d'un ticket : l'écriture **survit au rollback** (hors de tout arbre
jugé), elle **s'exécute dans l'arbre de process du pilote** (pas dans la session),
et elle **traverse le redémarrage** jusqu'à un run que personne ne regarde.

`R5c` mesure l'asymétrie : `gate_config_keys` a 53 entrées ; `PATH` n'est lu
qu'**une seule fois** dans tout le pack, à la ligne 322 de `scheduler.sh`, pour le
recopier dans la file.

## 2. La ligne mise en file porte trois choses qu'une session atteint — ticket [53]

### 2a. `successor.log` est un chemin qu'une session choisit

`sondes/passe-30-08/r3-successor-log-en-zone-ecrivable.bats`.

La ligne finit par `>>'<feature_dir>/successor.log' 2>&1`. Ce chemin est dans
`.scratch/<feature>/`, la zone que la ligne « Le reste de `.scratch/<feature>/` »
décrit comme écrivable par une session — et que `q2` du 27/08 avait déjà atteinte
depuis un worktree. La redirection est la **première chose que le shell du job
fait**, avant `loop.sh`, donc avant tout préflight et tout gate.

**Répertoire** (`R3a`) : `bash: … successor.log: Is a directory`, le job sort en 1,
**`loop.sh` ne démarre jamais** — 0 appel `claude`, 0 appel `curl`. La nuit est
perdue, et le message part dans le mail d'`at`, c'est-à-dire dans le silence que la
redirection existait précisément pour éviter.

**Lien symbolique** (`R3b`, puis `R3d` bout en bout depuis une session) : le lien
pointe sur `.claude/settings.json`, qui est **scellé** ([24], [31]). L'itération
qui pose le lien est verte —

    ralph: gate: 01-alpha: tests=green typecheck=green scope=green lang=green
    === settings.json before the successor wakes:      153 bytes

— et au réveil le successeur **écrit lui-même dans le fichier scellé** :

    === settings.json after:     1240 bytes
    ralph: it is a new run and inherits nothing from this one: …

Le scellement n'est pas contourné, il est **hors circuit** : ce n'est pas la
session qui écrit, c'est le pack, depuis un shell mis en file, à un moment où
aucun run n'existe. C'est le corollaire de [21] par l'autre bout — *un contrôle
qui lit un fichier que la session peut écrire n'est pas un contrôle* devient ici
*un pack qui **écrit** dans un chemin que la session peut choisir n'a plus de
scellement*.

### 2b. La ligne ne porte pas `FEATURE`

`R4a`. La forme livrée du config est `FEATURE="${FEATURE:-}"`, donc
`FEATURE=x bash .claude/loop.sh` est une invocation qui marche et c'est celle
qu'un humain utilise pour broyer une seconde feature. Le run annonce :

    ralph: armed a one-shot successor with at at 2026-09-01T15:58:34+0200 …

journalise `successor-armed`, écrit le marqueur — et la ligne mise en file porte
`PATH`, `RALPH_CONFIG`, `RALPH_PROJECT_ROOT`, jamais `FEATURE`. Au réveil :

    === the successor exited 2
    ralph: FEATURE is empty — the run has no tracker to grind (see …)

C'est le même raisonnement que [31] avait imposé pour `RALPH_CONFIG` — « sous le
nom qu'il a réellement, parce qu'un run lancé avec une autre valeur ne doit pas
recevoir le défaut en silence » — non appliqué au second sélecteur que
l'environnement fournit. Le seul témoin est `successor.log`, dans la zone du 2a.

### 2c. Le marqueur se forge, et pour toutes les nuits

`sondes/passe-30-08/r2-le-marqueur-que-personne-ne-balaie.bats`.

Le tableau écrit l'exposition dans la direction prudente : *« une session qui en
forge un empêche l'armement, ce qui finit la nuit avec un humain »*. **Une** nuit.
`R2b` mesure le pluriel — rien n'efface le marqueur, et `scheduler_armed_at` ne
compare que son premier champ à `now` :

    === night 1: rc=6 at_call_count=0
    ralph: not arming a successor: one is already armed for this working tree at 2026-09-05T03:15:24+0200 …
    --- run.log
    budget-wall weekly-pause
    === night 2: rc=6 at_call_count=0
    ralph: not arming a successor: one is already armed for this working tree at 2026-09-05T03:15:24+0200 …
    === does any receipt or journal name why nothing was armed?
    (nowhere durable)

Deux choses, et la seconde est la pire. D'abord la durée : une session choisit
l'instant, donc elle choisit combien de nuits. Ensuite le **mot** : `run.log`
enregistre `weekly-pause`, qui est exactement le mot d'un projet ayant choisi
`WEEKLY_RESUME=human`. Un lecteur du matin ne peut pas distinguer « ce projet
reprend à la main » de « quelque chose a forgé un marqueur » ; la phrase qui nomme
le marqueur est stdout-only.

`R2c` mesure que la pose est à portée : depuis une itération **verte**
(`scope=green`, `01-alpha resolved`), par `git rev-parse --git-common-dir`. `.git/`
est hors de portée d'un `git add -A`, d'un `git clean` et d'un `rm -rf .scratch` —
et par la même occasion hors de portée de tout gate et de tout compteur.

`R2a` complète : un marqueur laissé par un successeur qui ne s'est jamais réveillé
(le cas `atrun` désactivé, que le tableau assume) n'est nommé et balayé par
personne — `gate_leftovers` ne regarde que `$TMPDIR` et les `*.guard` de la
feature. Inerte, mais c'est un objet de plus dans la zone que personne ne balaie
avant [19].

## 3. Le troisième état du mur budget — pas un ticket, une ligne

`sondes/passe-30-08/r1-le-kill-entre-le-mur-et-la-queue.bats`.

L'angle (a) de [09] supposait que `run.log` serait muet. Il ne l'est pas, et il
faut le corriger dans les notes : un run tué entre le mur et la queue de
`loop_main` laisse `budget-wall` **seul**.

| Fin | `run.log` |
|---|---|
| armé | `budget-wall` `successor-armed` |
| non armé par choix | `budget-wall` `weekly-pause` |
| tué pendant le drainage | `budget-wall` |

Les trois se distinguent donc, ce qui sauve la promesse du tableau. Ce qui reste :
le troisième état n'est écrit nulle part comme un état, et la phrase qui promet
« a one-shot successor is armed at the reset once the iterations in flight are
drained » est stdout-only — donc perdue avec le process. `R1a` montre aussi que le
ticket en vol reste `claimed`, ce qui appartient au balayage de liveness de [12] et
n'est pas neuf.

Pas de ticket : c'est une ligne à ajouter au tableau et une note dans [09], pas un
mécanisme à construire. Le corollaire général mérite d'être écrit : **une garantie
portée par une ligne `loop_log` meurt avec le process** — c'est ce que [46] a dû
réparer pour la dérive de capacités, et deux autres constats sont dans le même cas
(`gate_leftovers`, le refus d'armement de 2c).

## Les angles disculpés — NE PAS LES RESONDER

- **Deux runs sur deux features d'un même arbre** (angle (d) de [09]). `R4b` :
  refusé par le **verrou d'arbre** avant que la question du marqueur se pose —
  `another run already holds this working tree (pid …, feature demo)`. La
  granularité du marqueur (par arbre) est donc cohérente avec le verrou. Reste un
  fait mineur et voulu, écrit ici plutôt que tu : séquentiellement (`R4c`), la
  première feature qui rencontre le mur prend l'unique créneau de l'arbre, et la
  seconde est refusée. C'est le bon comportement — un arbre, un run — mais le
  ticket de la seconde reste `ready-for-agent` sans qu'un document le dise.
- **La restauration de `issues/` et le garde d'ouverture, après [49].** Les deux
  sondes du 27/08 rejouées sur `a4ecf90` : `q5` Q5a rend `rc=0`, aucune
  résurrection, aucune fausse accusation, et la confession nomme les deux chemins
  transitoires ; `q1` Q1a rend `1 exclusion guard(s) left in … .open.guard — the
  owner is gone`. Les deux réparations de [49] tiennent au réel.
- **`gate_frontier_residue` comme garde d'armement.** Il fait ce qu'il promet
  (`R5b` le montre en creux : il ne rend rien quand le résidu est ailleurs que
  dans la configuration git). Sa limite n'est pas un défaut, c'est son périmètre —
  et c'est [52] qui décide si ce périmètre doit grandir.

## Ce qui a été écrit ailleurs

Notes ajoutées dans [09], [15], [16], [19], [46] et [49] — la règle 8 de
`CLAUDE.md`. Quatre lignes du tableau de `docs/frontiere-de-confiance.md` sont
touchées, avec renvoi aux tickets [52] et [53] :

- « Ce qu'une session écrit **hors du dépôt** » — le second cas de la phrase que
  [46] y avait écrite, le `PATH`, avec la mesure et le propriétaire [52] ;
- « Le reste de `.scratch/<feature>/` » — cinquième objet de la zone,
  `successor.log`, et le fait qu'il est le premier dans lequel le pack écrit
  depuis hors de tout run ;
- « Un successeur n'hérite **rien** » — « la nuit » corrigé en « autant de nuits
  que l'instant forgé », le mot `weekly-pause` qui ment, le marqueur périmé que
  rien ne compte, et l'absence de `FEATURE` sur la ligne mise en file ;
- « Un successeur one-shot **démarre** vraiment » — le troisième état du mur
  budget, et la quatrième façon dont « armé » ne veut pas dire « démarre ».

Voir [[ralph-pack-ordre-livraison]], [[ralph-pack-pieges-de-harnais]],
[[ralph-pack-passe-transversale-27-08]].
