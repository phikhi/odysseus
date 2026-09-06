# Passe transversale du 06/09/2026

Huitième passe. Faite sur `main` à `61d88cb` (merge de [64]), avant [18].
Quatre livraisons depuis celle du 05/09 : [63] `064bd9a`, [62] `4b272ef`,
[65] `4e577c5`, [64] `61d88cb`.

Sondes conservées : `sondes/passe-06-09/` (README avec le verdict de chacune).
**Ni `.claude/` ni `test/` touchés** → la baseline de [64] tient telle quelle
(`run.sh` 737/0/6 skips, `mutate.sh` 737/0) et les deux gates n'ont pas été
rejoués.

---

## La racine

> **Tout ce que le pack épingle, il l'épingle autour de la session d'une
> itération AFK. La session routée du drain n'est entourée d'aucun épinglage —
> et elle écrit dans l'arbre principal, *entre deux runs*, c'est-à-dire à
> l'instant que chacun de ces raisonnements attribue à un humain.**

Le pack a une discipline, écrite depuis [21] et répétée à chaque ticket : *un
contrôle qui lit un fichier que la session peut écrire n'est pas un contrôle — il
doit lire l'état d'avant la session.* Elle est appliquée partout, et bien :
`failures_protect_tracker` prend un tree object d'`issues/` avant le spawn, [30]
épingle le contenu des règles d'ignore, [11] copie `spec.md` dans `$TMPDIR` sous
un nom que le pilote n'exporte pas, [55] puis [61] épinglent `Escalation:` et
`Failures:` avant que le drain ne montre le ticket.

Chacun de ces épinglages entoure **une session d'itération**. La session routée
de [16] n'en a qu'un — `router_pin`, cinq valeurs — et le drain décide et
raconte sur **trois preuves de plus** que rien n'épingle :

| ce que le drain lit | ce qui l'épingle | ce qu'une session routée en fait |
|---|---|---|
| `Escalation:`, `Write-surface:`, `Failures:` | `router_pin` ([55], [61]) | rien |
| l'arbre de travail | `ROUTER__PINNED_TREE` | nommé par `router_tree_note` |
| l'état du tracker | `ROUTER__PINNED_TRACKER` ([55]) | remis par `router_protect_tracker` |
| **la ref `refs/heads/failed/<id>`** | **rien** | choisit le desk, détruit la preuve (§1) |
| **`run.log`** | **rien** | fait taire une note, en fabrique une autre, efface la décision d'un humain (§2, §3) |
| **`spec.md`** | le témoin de [11], **borné au run** | réécrit le flux que le gate de valeur rejouera (§4) |

Et il y a **un seul** mécanisme qui prétend couvrir ce trio. Le commentaire de
`router_desk` le nomme en toutes lettres :

> The `failed/<id>` ref is still read as it stands, and that is the boundary:
> pinning a git ref is a different mechanism, a routed session that writes one has
> left a branch behind it in the repository, and **`router_tree_note` is what
> looks at what a session left outside `issues/`**.

`router_tree_note` lit `router__tree_dirt`, qui est `git diff --name-only HEAD`
plus `git ls-files --others`, **moins `gate_is_bookkeeping`**. C'est-à-dire :
les chemins non commités de l'arbre de travail, sauf `.scratch/<feature>/`. Une
ref n'est pas un chemin de l'arbre de travail. `run.log` et `spec.md` sont dans
la zone exclue. Le garde nommé est aveugle aux **trois** endroits pour lesquels
on le nomme, et il l'est par construction, pas par accident.

Mesuré à chaque fois : le drain a nommé **0 chemin** dans les quatre scénarios.

Le corollaire pour la file : **[18] ouvre `tracker.sh` et écrit deux adaptateurs
distants ; il n'a rien à voir avec ce trou, et il en hérite quand même** — la
ligne « `router_desk` distingue les trois arrivées de `decision` par les preuves »
est déjà écrite dans [18], avec la remarque qu'un backend distant peut ranger la
trace forensique ailleurs. Un [18] livré avant la réparation déplace une preuve
que rien n'épingle.

---

## 1. Le desk du puits est choisi par une ref git qu'une session routée écrit — ticket [66]

C'est [61] par l'autre bout, et [61] est cité dans le commentaire qui laisse la
ref dehors.

`router_desk` distingue les trois arrivées de `decision` par deux preuves :
l'existence de `refs/heads/failed/<id>` et la valeur de `Failures:`. [55] a
épinglé `Escalation:` ; [61] a épinglé `Failures:` après avoir **mesuré** qu'une
session routée qui s'ajoute `**Failures:** 1` envoyait la session suivante du
même ticket de `admit` à `triage-host` — « two desks on one ticket, the second
chosen by the first ». La ref est restée dehors sur l'argument cité plus haut.

**Mesuré** (sonde `q1`), session routée qui n'écrit **que** la ref :

| Sonde | Ce qu'elle demande | Verdict |
|---|---|---|
| Q1a | la session fait `git update-ref refs/heads/failed/20-decision HEAD` | desk **`admit` → `arbitrate`**. Le dossier du drain suivant dit « branch failed/20-decision — the tree of the attempt, as it was. `git log -p failed/20-decision` ». Le drain a nommé **0 chemin** |
| Q1b | témoin appairé : la même session, sans la ref | desk **`admit`**, « branch there is none. nothing ever ran on this ticket » |
| Q1c | l'autre sens : la session fait `git update-ref -d` sur la ref d'une tentative **réellement jugée** | desk **`arbitrate` → `admit`**, et le dossier dit à l'humain « **there is none. nothing ever ran on this ticket** ». Le drain a nommé **0 chemin** |

Q1c est la moitié qui décide de la gravité. Q1a est une fausse route — un humain
envoyé au guichet `arbitrate`, avec la question, le traitement et le prompt de la
session suivante qui vont avec. Q1c est une **destruction de preuve** : la
branche forensique est ce que le reçu envoie lire quand un ticket a vieilli dans
le puits (« `failed/<id>` is a ref: it survives, and it is what to lean on for a
ticket that has been in this sink for a while »), et une phrase du pack affirme
ensuite qu'aucun run n'a jamais jugé ce ticket. Nommer après coup ne la rend pas.

Ce que le tableau de frontière dit aujourd'hui de `.git/` : « le reste de `.git/`
— refs, objets, `config` au-delà des clés que ces deux mécanismes épinglent —
n'est vérifié par rien : le rempart est l'isolation de l'hôte ». Vrai, et c'était
suffisant tant que rien ne **lisait** une ref pour décider. Depuis [16], une ref
est l'entrée d'un contrôle.

---

## 2. Les quatre mots que le drain dit du run sont lus dans un fichier qu'une session écrit — ticket [67]

`router_run_notes` lit `run.log` et en tire **quatre conclusions**, dites une
fois, au démarrage du drain, **sans une réserve**. Son voisin
`router_journal_lines`, deux fonctions plus haut, lit le *même fichier* et
imprime la réserve avec les lignes :

> That file is under `.scratch/`, which nothing in this pack guards: the session
> these lines are about could have written them. **Read them, do not rely on
> them.**

Et l'une des quatre est une **négation** :

```sh
grep -q 'budget-wall' && ! grep -q 'successor-armed\|weekly-pause\|successor-blocked-'
```

dont le commentaire dit *« Nothing in this pack writes that end down as a
state »* — autrement dit cette phrase est le **seul** endroit où cet état est
jamais dit.

**Mesuré** (sonde `q2`) :

| Sonde | Ce qu'elle demande | Verdict |
|---|---|---|
| Q2a | un `run.log` portant `budget-wall` seul | la note est dite : « that run was killed while it was draining » |
| Q2b | une session routée ajoute une ligne portant `successor-armed` | `router_run_notes` **rc=1** : la note **disparaît**. Le drain suivant n'en dit rien, et le drain courant a nommé **0 chemin** |
| Q2c | témoin appairé : la même session, sans la ligne | la note est dite |
| Q2d | l'autre sens : une session routée fabrique `claim-refused` sur un `run.log` **vierge** | le drain suivant dit à l'humain « the frontier is short of a ticket nothing else would have mentioned » — sur un run qui n'a jamais refusé de claim |
| Q2e | un run AFK complet passe ensuite sur la ligne fabriquée | run **vert, rc=0**, `loop_journal_verify` se tait (**0**), la note est toujours dite après |

Q2b et Q2d sont les deux sens du même trou, et Q2e est ce qui le rend durable :
le témoin de [10] ne se prononce que sur **le bloc du run courant**, et une ligne
écrite *avant* le run entre dans `RALPH_JOURNAL_BASE`. Une contrefaçon posée par
un drain est invisible à tous les runs qui suivent.

Ce que le drain a nommé de l'écriture elle-même : **rien**, et c'est structurel —
`router__tree_dirt` saute `gate_is_bookkeeping`, c'est-à-dire `.scratch/<FEATURE>/`,
c'est-à-dire exactement le répertoire de `run.log`.

**Le tableau reste littéralement vrai et c'est ce qui l'a caché.** La ligne de
[10] dit « rien ne le relit pour **choisir ou marquer** ». `router_run_notes` ne
choisit rien et ne marque rien : il *raconte*, à l'humain qui va décider. La
catégorie n'existait pas quand la phrase a été écrite ; [16] l'a créée.

---

## 3. Le drain journalise sans témoin — ticket [67] (même mécanisme)

[10] a rendu `run.log` **détectable** plutôt qu'inviolable : le pilote garde en
mémoire chaque ligne qu'il a écrite (`RALPH_JOURNAL_WITNESS`, une variable de son
propre process, jamais un fichier) et `loop_journal_verify` compare en fin de run.

[16] a ajouté un **second écrivain** de ce fichier — `router_journal` — et aucun
témoin. Ce que le drain journalise est pourtant la seule trace de ce qu'un
**humain** a décidé : `drained/reinjected`, `drained/signed-off`,
`drained/closed`, `tracker-drift/skipped`, et depuis [64] les constats du
préflight.

**Mesuré** (sonde `q3`), deux tickets dans le puits :

| Sonde | Ce qu'elle demande | Verdict |
|---|---|---|
| Q3a | l'humain ferme `20-decision` (`c`), puis ouvre une session sur `21-second` qui écrase `run.log` | `20-decision` est **`wontfix`** et **sa ligne `drained` n'existe plus**. Le drain ne se plaint **0** fois et ne nomme **0** chemin |
| Q3b | témoin appairé : le même écrasement, par une session AFK | « the run journal does not hold exactly the 2 line(s) this run wrote, where it wrote them: something rewrote … » **plus la copie du run imprimée dessous** |
| Q3c | témoin appairé : le même drain, sans l'écrasement | les deux lignes sont là |

Les deux points d'entrée donnent des réponses opposées au même événement, et
celui qui se tait est celui dont les lignes disent ce qu'un **humain** a voulu.
C'est la forme de [57] à la lettre, sur un autre objet.

---

## 4. Le témoin du flux a une borne dont l'argument est mort depuis [16] — ticket [68]

`playthrough_witness` **est** un contrôle et le dit mieux que n'importe quel
autre commentaire du pack :

> **This is a control and not a cache** […] a delivery session can rewrite the
> user flow this gate replays […] Across runs it is the file on disk that seeds
> it, and that limit is the lesson index's own: **a human who corrects the spec
> between two runs is heard, a session that rewrites it during one is not.**

La borne est « pendant un run » contre « entre deux runs », et ce qui la rend
sûre est que *ce qui écrit entre deux runs est un humain*. [16] a livré un point
d'entrée qui met une session **non jugée** dans l'arbre principal, précisément
entre deux runs.

**Mesuré** (sonde `q5`) :

| Sonde | Ce qu'elle demande | Verdict |
|---|---|---|
| Q5a | une session routée réécrit `spec.md`, puis un run AFK tourne | le prompt du gate de valeur porte le flux **forgé** (`FORGED BY A ROUTED SESSION: the user opens the app and everything already works`). Le drain a nommé **0** chemin, le run n'a dit **0** mot du flux |
| Q5b | témoin appairé : le même run sans le drain | le prompt porte le vrai `spec.md` |
| Q5c | la **même** réécriture, par une session AFK **pendant** le run | le prompt porte **0** ligne forgée — le témoin de [11] tient exactement pour le cas qu'il vise |

Q5c est la moitié qui empêche de lire ça comme un défaut de [11] : le contrôle
fait ce pour quoi il a été écrit. Ce qui a changé est la population de ce qui
écrit dans l'intervalle qu'il ne couvre pas.

Direction : ce n'est pas un faux vert. Le gate de valeur peut être rendu **plus
indulgent** par un flux réécrit (`pass` sur une feature qui ne marche pas) — donc
une feature close sur un flux que personne n'a promis, et un
`docs/playthroughs/<feature>.md` qui raconte ce flux-là à l'humain du matin.

---

## 5. Un drainage démarré après un run tué ne nomme aucun résidu — ticket [69]

Le constat resté ouvert dans [16], qualifié. `loop_main` dit au démarrage ce que
les runs précédents ont laissé **dehors** (`gate_leftovers` : `$TMPDIR`, les
gardes morts de [49], le marqueur de successeur de [53]) et **dedans**
(`concurrency_leftovers` : un worktree encore enregistré). `human_loop_main`
n'appelle ni l'un ni l'autre.

**Mesuré** (sonde `q4`), run réel tué au `KILL` pendant le gate :

| Sonde | Ce qu'elle demande | Verdict |
|---|---|---|
| Q4a | un drainage démarré sur ce décor | le décor : **9** entrées dans `$TMPDIR`, un marqueur de successeur, **1** worktree encore enregistré. Le drain en nomme **0** |
| Q4b | témoin appairé : un run AFK sur le même décor | il en nomme **3** — les 9 entrées comptées **9** ([62] tient), le marqueur, le worktree |

Inerte — un silence, pas un faux vert — et c'est la situation même où un humain
vient voir ce qui s'est passé. Même racine que [55]/[56]/[57], et c'est le
morceau le moins cher des quatre : `human_loop_preflight` est explicitement *une
liste et pas une délégation*, donc la décision est d'ajouter deux lignes, pas
d'appeler `loop_preflight`.

---

## Angles sondés et disculpés — ne pas les resonder

- **Le témoin du journal côté AFK tient.** Q3b : la phrase entière, plus la copie
  du run. Ce que [10] a livré fait ce qu'il annonce.
- **Le témoin du flux côté AFK tient.** Q5c : une session d'itération qui réécrit
  `spec.md` ne change pas une ligne du prompt du gate de valeur.
- **`gate__tmp_leftovers` tient.** Q4b : neuf entrées laissées, neuf comptées, sur
  un run réel tué. La réparation de [62] est bonne.
- **`playthrough__opened` tient.** Rejeu de `sondes/ticket-65/verification.bats` :
  les trois tickets contrefaits ne comptent plus contre la borne, et la phrase de
  la borne les **nomme** (« the tracker carries wiring ticket(s) this run did not
  open, which no longer count against it: 60-…, 61-…, 62-… »).
- **Le constat de [64] tient.** Rejeu de `sondes/ticket-64/verification.bats` :
  deux noms inadressables → deux constats `unaddressable-name`, **une fois
  chacun**, dans `run.log` avec leur ligne de journal ; rien d'inadressable → 0
  phrase, 0 ligne, 0 résidu dans `$TMPDIR`.
- **`router_journal_lines` est honnête.** Il lit le même fichier que
  `router_run_notes` et imprime la réserve avec les lignes. Ce n'est pas lui qu'il
  faut réparer, c'est son voisin qui doit l'égaler.
- **`router_protect_tracker` couvre `issues/`.** La zone de bookkeeping est
  aveugle *sauf* `issues/`, remis par [55]. Le trou est le reste de la zone.
- **Une session routée qui écrit `receipts/`** est vue par `router_tree_note` : le
  chemin est dans l'arbre de travail et hors de `gate_is_bookkeeping`. Pas de
  ticket. (Un projet qui *ignore* `receipts/` retombe sous [50] ; c'est déjà écrit
  là-bas.)

---

## Ce qui est écrit ailleurs

Écrit maintenant, parce qu'une ligne fausse dans le tableau attend un faux vert :

- `docs/frontiere-de-confiance.md` — trois lignes élargies (`.git/`, le reste de
  `.scratch/<feature>/`, le flux du gate de valeur), chacune renvoyant à son
  ticket.
- **[16]** — le constat ouvert est qualifié en [69], et trois de plus lui sont
  ajoutés : la ref, le journal sans témoin, `spec.md`.
- **[10]** — « rien ne le relit pour choisir ou marquer » reste vrai et n'est plus
  suffisant : [16] a créé la catégorie *raconter à l'humain qui décide*.
- **[11]** — la borne du témoin de `spec.md` est écrite comme une borne de *run*
  et son argument nomme un humain ; l'intervalle a un second écrivain depuis [16].
- **[61]** — sa réparation a un frère non livré : la ref que le même
  commentaire laisse dehors.
- **[18]** — un backend distant qui déplace la trace forensique déplace une preuve
  que rien n'épingle ; à lire avec [66].

## L'ordre, validé par Philippe le 06/09/2026

**[69] → [67] → [66] → [68] → [18] → [19]**

Par le critère du dépôt — **minimiser la reprise**, jamais la gravité :

1. **[69]** — délié, deux lignes dans `human_loop_main`, aucune arête. Il livre
   aussi le décor de sonde (« un run tué, puis un drain ») que [67] et [66]
   réutilisent.
2. **[67]** — un seul fichier de plus (`router.sh` + `human-loop.sh`), un seul
   mécanisme (un témoin pour le drain, la réserve de son voisin sur les quatre
   mots), et il rouvre `human-loop.sh` juste après [69] : deux tickets dessinés
   sur un fichier sont un `decision` que le pack sait produire tout seul.
3. **[66]** — le point de convergence (`router_pin` + `router_tree_note`), la
   plus grosse surface, et l'arête **dure** vers [18].
4. **[68]** — le seul dont la réparation n'est pas dans `router.sh` : il faut
   d'abord décider *qui* possède l'intervalle entre deux runs, et [66] aura livré
   le mécanisme qui nomme ce qu'une session routée a laissé.

`Blocked by:` en conséquence : `[67] 69`, `[66] 67`, `[68] 66`, et `[18]` gagne
`66`.

Écrit dans les quatre tickets (« Place dans la file »).
