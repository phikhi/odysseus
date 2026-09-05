# Passe transversale du 05/09/2026

Septième passe. Faite sur `main` à `f9cac0c` (merge de [48]), avant [18].
Cinq livraisons depuis la passe du 01/09 : [59] `cbf7f1e`, [60] `772afc7`,
[61] `8bad00c`, [11] `0ff055e`, [48] `f9cac0c`.

Sondes conservées : `sondes/passe-05-09/` (README avec le verdict de chacune).
**Ni `.claude/` ni `test/` touchés** → la baseline de [48] tient telle quelle
(`run.sh` 712/0/6, `mutate.sh` 708/0) et les deux gates n'ont pas été rejoués.

---

## La racine

> **Ce que le pack sait, il le sait en trois exemplaires recopiés à la main.**

Les quatre trouvailles sont la même erreur vue par quatre bouts. À chaque fois le
**critère est juste et écrit**, souvent au-dessus de la fonction elle-même ; c'est
l'**exemplaire** qui a dérivé, parce que rien ne le dérive de son critère.

- Une **règle** ([43], « le verdict prime sur l'événement ») écrite en prose dans
  `lenses_refused_posture`, réécrite en prose dans `playthrough_close`, et
  **fausse** dans `retro_run` — le troisième palier. Aucun test ne la porte comme
  règle, chacun la porte comme cas.
- Une **liste** (`gate__tmp_leftovers`) tenue à la main à côté de ses **dix-huit**
  producteurs, dont six sont dedans.
- Un **genre de constat** (« ce qui ne va pas dans le tracker ») qui a un
  mécanisme (`tracker_preflight` + `loop__report_tracker_findings`, [27]) et un
  producteur neuf ([48]) qui ne l'emprunte pas.
- Une **borne** (`PLAYTHROUGH_REINJECT_MAX`) comptée sur un espace de noms qui a
  deux écrivains, le pack et une session.

Et le corollaire pour les deux tickets qui restent : **[18] et [19] héritent
chacun d'un de ces exemplaires comme spécification.** [19] est nommé par le
commentaire de `gate_leftovers` comme le composant qui balaiera `$TMPDIR` ; [48] a
écrit pour [18] la clause « un backend refuse **à voix haute** » et cette clause
n'a aujourd'hui aucun logement dans l'interface.

---

## 1. `gate__tmp_leftovers` compte six des dix-huit noms que le pack pose — ticket [62]

Forme exacte de [31] (un scellement plus étroit que son critère) et de [45] (un
reçu avec moins de producteurs que son critère).

Le **critère** est écrit dans la phrase même : « N temporary director(ies) **from
earlier runs** are still in `$TMPDIR`: **a run killed mid-iteration leaves one
behind**, and nothing here removes them ». La **liste** est cinq motifs :
`ralph-gate.*`, `ralph-ignore.*`, `ralph-worktree.*`, `ralph-slot.*`,
`ralph-frontier.*`.

`grep -rn mktemp .claude/` en donne **dix-huit** au premier niveau de `$TMPDIR`.
Mesuré (sonde `q1` Q1a, un nom par run, vieilli de 25 h) :

| vu | nom | producteur |
|---|---|---|
| ✅ | `ralph-slot.*` | `loop.sh:1087` |
| ✅ | `ralph-slot.writes.*` | `loop.sh:1396` (par le glob du précédent) |
| ✅ | `ralph-frontier.*` | `gate.sh:656` |
| ✅ | `ralph-ignore.*` | `gate.sh:764` |
| ✅ | `ralph-gate.*` | `gate.sh:3130` |
| ✅ | `ralph-worktree.*` | `concurrency.sh:298` |
| ❌ | `ralph-receipt.*` | `receipt.sh:100` — **un répertoire** |
| ❌ | `ralph-retro.*` | `retro.sh:164` — **un répertoire** |
| ❌ | `ralph-playthrough.*` | `playthrough.sh:699` — **un répertoire**, [11] |
| ❌ | `ralph-spec.*` | `playthrough.sh:229` — le témoin du flux, [11] |
| ❌ | `ralph-tracker.*` | `failures.sh:764` |
| ❌ | `ralph-failed.*` | `failures.sh:1029` |
| ❌ | `ralph-durable.*` | `failures.sh:1112` |
| ❌ | `ralph-reslice.*` | `failures.sh:1259` |
| ❌ | `ralph-index.*` | `gate.sh:2224` |
| ❌ | `ralph-restore.*` | `gate.sh:2441` |
| ❌ | `ralph-fold.*` | `concurrency.sh:533` |
| ❌ | `ralph-refresh.*` | `concurrency.sh:652` |

**Run réel** (sonde `q1` Q1b) : un run tué au `KILL` pendant le gate laisse **neuf**
entrées, `gate__tmp_leftovers` en compte **six**. Les trois muettes sont
`ralph-receipt.*`, `ralph-retro.*` et `ralph-spec.*` — deux répertoires et le
témoin de [11]. **Témoin appairé** (Q1c) : un run qui finit normalement laisse
**zéro**, donc ce qui reste est bien ce que le critère décrit et rien d'autre.

Trois d'entre eux sont des **répertoires**, ce qui retire l'échappatoire « la
phrase dit *director(ies)* » : elle en compte six et en laisse trois du même
genre. Et deux des trois muettes du run réel sont des livraisons de **[11]**, la
feature qui vient d'être posée — c'est la dérive en train de se faire, pas un
héritage ancien.

**Ce que [19] hérite.** Le commentaire de `gate_leftovers` désigne l'installeur
comme le composant entitled à balayer (« the obvious shape […] and the component
entitled to run it is the installer ([19]) »). Un [19] qui prend cette liste pour
spécification balaie six familles sur dix-huit et laisse les douze autres sur le
disque pour toujours. C'est la question 4 dans sa forme la plus directe : la
mesure du 03/09 (`1,0 Go → 49 Mo` sur cette machine, ~1 Go de résidus par ticket)
est faite **à la main** aujourd'hui.

**Sortie à trancher dans le ticket** — dériver la liste de ses producteurs plutôt
que la recopier. Le pack a déjà la forme (`gate_config_keys` a 53 entrées, la
règle de [31] est « dériver du critère »). Un motif unique `ralph-*` est le
candidat évident et il a un coût à mesurer : `$TMPDIR` est partagé avec les runs
d'autres dépôts, et `ralph-test.*` (le harnais) y vit aussi.

---

## 2. `retro_run` consulte le budget **avant** le verdict — ticket [63]

[43] a posé la règle, et [11] l'a réécrite en toutes lettres :

> **The verdict outranks the event, in that order and not the other way round** —
> le signal in-band peut annoncer `blocked` pour la fenêtre *suivante* pendant
> que la session en cours répond parfaitement. Une session qui a répondu a
> **regardé**, et ce qu'elle a dit tient.

Trois paliers spawnent une session subalterne et lisent son `rate_limit_event` :

| module | ordre |
|---|---|
| `lenses_refused_posture` | `[ verdict = none ] \|\| return 1` **puis** `budget_refused` |
| `playthrough_close` | `[ "$verdict" = none ] && budget_refused …` |
| `retro_run` | **`budget_refused "$posture"` d'abord**, les `retro__said` après |

Mesuré (sonde `q2`, run réel, faux `claude` qui répond en rétro **et** porte
l'événement demandé — la session de livraison, elle, dit `allowed`) :

**Q2a — le rétro répond `LESSON` + `WHY` + `ADR` + `DECISION` + `BECAUSE` +
`ESCALATE`, son flux dit `blocked` (`seven_day`) :**

```
rc du run                 : 6
LEARNINGS.md              : NON
docs/adr/                 : (vide)
tickets                   : 01-alpha.md 02-beta.md
Status 01-alpha / 02-beta : resolved / ready-for-agent
le reçu dit               : « no lesson was distilled from this iteration:
                              the API refused the retro session (seven_day) »
ralph: the weekly usage limit blocks this run (seven_day, said by the stream) — stopping
```

**Q2b — témoin appairé, le même rétro, l'événement dit `allowed` :**

```
rc du run                 : 4 (run stérile, au bout de la file)
LEARNINGS.md              : oui — LR-0001
docs/adr/                 : 0001-who-owns-the-flow-document.md
tickets                   : + 03-retro-add-a-lint-that-fails-when-the-flow-is-not-wired
Status 01-alpha / 02-beta : resolved / ready-for-human
iterations                : 4 (02-beta épuise son budget de retries)
```

Ce que l'ordre inversé coûte, mesuré, sur une session qui a répondu :

1. **La leçon** — `LEARNINGS.md` et `learning-records/`, le quatrième palier
   d'observabilité, celui qui est lu *dans le prompt de chaque session suivante*.
2. **La décision d'architecture** — `docs/adr/`, lue par toutes les sessions et
   par la lentille Standards.
3. **L'escalade** — le ticket sur le puits humain que le rétro demandait, la
   seule façon dont ce pack demande une règle qu'il ne construit pas lui-même.
4. **La capacité** ([15]) — `capability_review` n'est jamais atteint.
5. **La nuit** — `RALPH_RETRO_QUOTA` écrase `$slot/posture`, le pilote lit le mur
   et **arrête le run** : `02-beta` n'est jamais tenté.

Et le reçu **ment** : « the API refused the retro session ». L'API n'a rien
refusé — la session a répondu six lignes taggées, et elles sont dans le flux que
le pack vient de jeter.

**Le harnais porte l'asymétrie, et c'est pour ça que personne ne l'a vu.** [11] a
ajouté `playthrough_rate_limit` (un événement **avec** une réponse) pour son
propre palier, précisément parce qu'il se posait la question de [43]. Le rétro
n'a que `retro_refused` — événement **sans** réponse, `exit 1`. Le cas ne pouvait
pas s'écrire avec les helpers livrés ; la sonde a dû passer par `script_claude`.
Un `retro_rate_limit` fait partie des AC.

---

## 3. Le constat de [48] n'a ni ligne de journal ni logement d'interface — ticket [64]

[27] a construit **le** mécanisme du pack pour « ce qui ne va pas dans le tracker
lui-même » : `tracker_preflight`, lu par `loop__report_tracker_findings`, qui
émet une ligne `loop_log` **et** une ligne de journal `subject / outcome`. Son
en-tête dit ce qu'il couvre :

> One scan, at the preflight, of the state **no per-ticket read would ever
> surface** […] finding that ticket by ticket in the middle of a night is exactly
> what this avoids. […] **Not dispatched: the question is about the *shape* of
> ids, which the interface owns**, not about how a backend stores them.

[48] a ajouté un second constat de ce genre exact — un fichier de `issues/` que
personne ne peut adresser, qui n'est sur aucune frontière, qu'aucun scan ne voit
et qu'aucun garde ne bouge — et l'a rapporté par un `printf … >&2` nu à
l'intérieur de `tracker_ids`.

Mesuré (sonde `q3`, fichier `50-a<LF>b.md` posé **avant** le run) :

| | |
|---|---|
| run AFK, la ligne dite | **8 fois** sur la console |
| `run.log` la porte | **0 fois** (2 lignes de journal, aucune) |
| le reçu d'audit la porte | **0 fois** |
| `docs/playthroughs/demo.md` la porte | **0 fois** |
| drain humain, la ligne dite | **6 fois** sur la console |
| `playthrough__injected` au module (Q3d) | **0 fois** — `2>/dev/null` |

Trois choses, et la troisième est celle qui décide de l'ordre :

- **Huit fois sur une console que personne ne regarde.** Un run AFK est par
  définition sans humain ; le seul artefact qu'on relit le matin est `run.log`,
  le reçu et le playthrough, et aucun des trois ne la porte. C'est la forme de
  [53] (« la phrase qui nomme le marqueur est stdout-only »), avec en plus le fait
  que le pack a **déjà** le canal qu'il faut, écrit par [27] pour ce genre-là.
- **Quatre consommateurs jettent la voix.** `playthrough.sh:494` ([11]),
  `router.sh:539` ([61]), `router.sh:646` ([55]) lisent
  `$(tracker_ids 2>/dev/null)`. Le commentaire de `tracker_local__refuse_name`
  raisonne soigneusement sur la substitution de commande (« the line has to
  survive being printed from a subshell ») et jamais sur la redirection. Ici ça ne
  coûte qu'une ligne — les producteurs nus sont plus nombreux — mais c'est la
  démonstration que le canal `>&2` d'un producteur n'est pas tenable.
- **[18] hérite d'une clause sans logement.** La contrainte écrite pour [18] est
  « un backend ne rend jamais un id porteur d'un saut de ligne, **il refuse à voix
  haute** ». La voix vit aujourd'hui dans `tracker_local__refuse_name`, un `__`
  du backend local. `tracker_preflight` — le seul endroit que l'interface possède
  pour les constats de **forme d'id**, et explicitement *non dispatché* — n'en
  parle pas. Un [18] écrit tel quel réimplémente huit `printf >&2` dans son
  propre backend, ou ne les écrit pas du tout.

**Arête dure : [64] avant [18].**

---

## 4. La borne du gate de valeur est comptée sur un espace de noms qu'une session écrit — ticket [65]

`playthrough__injected` compte les tickets dont l'id contient
`PLAYTHROUGH_SLUG_PREFIX` (`playthrough-wiring`), et c'est ce compte que
`PLAYTHROUGH_REINJECT_MAX` (défaut 2) borne. Le commentaire dit pourquoi il est
lu du tracker : « **a variable resets, a tracker does not** ».

Il ne dit pas qui écrit le tracker. Mesuré (sonde `q3` Q3e) : une session de
livraison dépose trois fichiers `60/61/62-playthrough-wiring-forged.md` dans
`issues/`. La quarantaine de [07] les voit et les nomme —

```
ralph: 01-alpha: the session wrote the tracker itself — quarantined
       60-playthrough-wiring-forged, 61-…, 62-…
```

— **et leur laisse leur nom**. Après le run :

```
tickets présents          : 01-alpha.md 60-…-forged.md 61-…-forged.md 62-…-forged.md
playthrough__injected     : 3
```

Avec `PLAYTHROUGH_REINJECT_MAX=2`, cette feature ne rouvrira **plus jamais** un
ticket de câblage : chaque playthrough rouge part droit au puits humain avec la
phrase « past the 2 re-injection(s) `PLAYTHROUGH_REINJECT_MAX` allows this
feature ». La phrase nomme la borne, jamais la contrefaçon.

C'est la question 5 du CLAUDE.md dans sa forme canonique — *un contrôle qui lit
un fichier que la session peut écrire n'est pas un contrôle* — appliquée à une
borne plutôt qu'à un champ. Deux nuances à écrire dans le ticket :

- **La direction est sûre.** Le compte ne peut que monter (une session ne peut pas
  supprimer un ticket, [21] restaure), donc l'effet est « un humain est demandé
  plus tôt », jamais un faux vert. Ce qui est perdu est **l'autonomie de la
  nuit** : le palier que [11] a construit pour se réparer tout seul est éteint par
  une session, en silence.
- **Le second chemin est le même.** `tracker_open_unique` déduplique sur le slug :
  une session qui pose un ticket portant *exactement* le slug que le gate
  utiliserait fait ouvrir **rien** au gate, qui escalade (`rc=2`). Même direction,
  même silence.

**Ce que [18] hérite.** [11] avait déjà écrit dans [18] que `playthrough__injected`
lit le slug **dans l'id** et qu'un backend numérotant côté serveur casse la borne.
La trouvaille l'élargit : la borne ne lit pas seulement un id, elle lit un espace
de noms **à deux écrivains**. Ce qui la répare doit être un compte que le pack
tient lui-même (le registre d'écritures de [13]/[40] est la forme évidente) et
non un scan.

---

## Angles disculpés — ne pas les resonder

- **Le drain humain n'hérite pas des préflights du run.** `human_loop_preflight`
  **écrit** qu'il n'appelle ni `gate_preflight`, ni `budget_preflight`, ni
  `concurrency_preflight`, ni les quatre qui suivent — c'est une décision datée,
  pas un oubli, et le drain ne clôt aucune feature.
- **`failures_protect_tracker` face à un nom porteur d'un saut de ligne.** Git
  cite ces noms quoi que dise `core.quotePath`, et `gate_unaddressable` les
  attrape : le chemin est **nommé et compté comme un trou**, l'itération ne peut
  pas être verte. Le garde de [21] est correct sur ce cas.
- **Pas de faux vert par la borne du gate de valeur.** Voir §4 : les deux chemins
  vont au puits humain.

## Rejeu des sondes conservées

- **[59] `passe-01-09/q2` — la réparation tient.** Q2c : le run dit **3 fois**
  qu'un chemin est illisible (0 avant), `Failures: 1` au lieu du budget brûlé, et
  `HEAD` ne bouge pas. Q2e — le faux livré de [59] : `ready-for-agent` et `rc=4`
  au lieu de `resolved` sur un `HEAD` immobile.
- **[60] `passe-01-09/q1` — la réparation tient, et les deux moitiés.** Q1a : le
  commit humain arrivé pendant l'itération à `MAX_PARALLEL=1` ne déclenche **plus
  de rejeu** (`ligne rejeu ? : 0`, plus de « over a sibling's commit » sans
  frère). Q1b : le chemin livré rendu illisible après l'arbre jugé donne
  toujours `could not be staged` — **et `src/shared.txt` est sur `HEAD` avec le
  contenu de l'humain** (« written by the human, committed by hand »), là où il
  était absent de `HEAD` *et* de l'arbre avant [60]. Q1c témoin : sans le refus,
  la livraison de la session gagne.

---

## Ce qui est écrit ailleurs

À écrire en livrant, pas maintenant : notes dans [11], [18], [19], [27], [43],
[48], et les lignes du tableau de `docs/frontiere-de-confiance.md` que chaque
ticket touche.

---

## L'ordre, validé par Philippe le 05/09/2026

**[63] → [62] → [65] → [64] → *passe transversale* → [18] → [19]**

Par le critère du dépôt — **minimiser la reprise**, jamais la gravité en
exploitation :

1. **[63]** — zéro arête (`retro.sh` + `test/helpers/`), seul **faux livré** des
   quatre, et son `retro_rate_limit` profite aux trois suivants.
2. **[62]** — placé tôt **pas** pour son arête vers [19] mais parce qu'il livre le
   contrôle qui rougit quand un producteur de `$TMPDIR` est ajouté sans être
   couvert : installé ici, il travaille pour [65], [64], [18] et [19] ; installé
   juste avant [19], il arriverait après le producteur qu'il aurait dû attraper
   (un backend distant qui cache des réponses est un candidat évident).
3. **[65]** — isolé (`playthrough.sh`), et il retire le scan du tracker, ce qui
   fait **disparaître** la contrainte que [11] avait écrite dans [18] au lieu de
   la lui laisser.
4. **[64]** — plus grosse surface des quatre, arête **dure**, collé à [18] qui
   rouvre `tracker.sh` juste après : l'en-tête de contrat est écrit et rempli
   dans la foulée.
5. **La passe transversale** tombe exactement là : quatre livraisons depuis celle
   du 05/09, et [18] est le ticket qui porte le plus de contraintes héritées.
6. **[18]** puis **[19]**, inchangé depuis le 01/09.

`Blocked by:` mis à jour en conséquence : `[18] 02, 10, 64, 65` et
`[19] 01, 18, 62`. [62] et [63] restent `None`.
