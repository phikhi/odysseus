# Passe transversale du 14/09/2026

Treizième passe. Faite sur `main` à `4da86d0` (merge de [19]). Cinq livraisons
depuis celle du 13/09 : [83] `3f59f98`, [84] `ec60fdb`, [85] `07ba935`,
[73] `3429215`, [19] `4da86d0`.

La première passe qui n'a aucun ticket derrière elle : les 85 tickets du tracker
sont résolus. Ce qu'elle trouve **est** la file.

Sondes conservées : `sondes/passe-14-09/` (README avec le verdict de chacune).
**Ni `.claude/`, ni `test/`, ni `init.sh` touchés** → la baseline de [19] tient
telle quelle (`run.sh` 960/0/6 skips, `mutate.sh` 975/0) et les deux gates n'ont
pas été rejoués.

---

## La racine

> **Le pack dérive ce qu'il _exécute_ et retape ce qu'il _dit_ — et ce qu'il dit
> est la seule chose qu'une session lit.** Dix passes ont demandé *« qu'est-ce
> qu'une session peut écrire que rien ne vérifie ? »*. Celle-ci pose la question
> en miroir, et elle n'avait jamais été posée : *qu'est-ce que le pack dit à une
> session, que rien ne tient à jour ?*

La règle existe. C'est [17] qui l'a écrite, en tête de `loop_session_prompt` :

> *« The language rules come from `lib/lang.sh` rather than being typed here, and
> that is the shape [17] wanted: **the sentence a session is asked to follow and
> the check that keeps it live in one file**, so the prompt cannot go on
> promising a guarantee the day the check moves. It says "checked" only where it
> is. »*

Elle a exactement **deux** applications dans tout le pack : `$(lang_session_rules)`
dans le prompt de session, et `$(gate_sealed_paths)` dans le heredoc de prompt de
`playthrough.sh`. Partout ailleurs, la prose est une copie tapée à la main.

Et l'endroit où le pack parle le plus, au plus grand nombre de sessions, sur la
plus longue durée, est **le bloc que `init.sh` écrit dans le `CLAUDE.md` du projet
cible** — mesuré : `loop_session_prompt` ne nomme aucun chemin scellé, donc dans
un projet installé ce bloc est *tout* ce qu'une session de livraison apprend de ce
qu'aucune write-surface ne peut couvrir.

**Ce qui rend la racine nette plutôt qu'accusatrice** : [19] connaissait la règle
et l'a appliquée — ses commentaires la citent nommément (*« [28]'s fault is the one
this file would be most likely to repeat »*), et il demande au pack ses refus
(`init_refusals` lit les `_preflight ||` de `loop.sh`), ses noms de temporaires
(`gate_tmp_names`), ses clés de configuration (le `sed` sur le `.example`), et fait
comparer son payload au `files` de `package.json` par un test. Les quatre listes
qu'il **dérive** sont des listes de *code*. Les trois qu'il **retape** sont des
listes de *prose*. La règle a été lue comme une règle sur ce qu'on exécute.

---

## §1 — La prose déposée retape la liste scellée, et elle en a perdu la moitié

Sonde `q1` Q1a. Mesuré sur un install réel dans un dépôt git neuf.

`gate_sealed_paths` rend **douze** chemins. Le bloc que `init_claude_block` écrit
en nomme **cinq** tels quels :

| Scellé | Dans la prose déposée ? |
|---|---|
| `.claude/settings.json` | oui |
| `CLAUDE.md` | oui |
| `.mcp.json` | oui |
| `.claude/agents` | oui |
| `.claude/ralph.config.sh` | oui |
| `.claude/commands` | **basename nu** (`commands`) |
| `.claude/skills` | **basename nu** (`skills`) |
| `.claude/hooks` | **basename nu** (`hooks`) |
| `.claude/settings.local.json` | **non** |
| `CLAUDE.local.md` | **non** |
| `LEARNINGS.md` | **non** |
| `learning-records` | **non** |

Les quatre absents ne sont pas des oublis anodins : `LEARNINGS.md` et
`learning-records` sont scellés par [14] **précisément parce qu'ils sont inlinés
dans le prompt de chaque session suivante** — c'est la ligne du tableau qui dit
qu'une session qui écrirait l'index écrirait le prompt de toutes celles d'après.
Le seul texte qui prévient une session de l'existence de ce scellement ne le
nomme pas.

Et la liste **bouge** : elle est passée de trois entrées ([24]) à douze ([31]).
Le bloc est *managed* — `init__merge_block` le remplace à chaque réinstallation —
donc la réparation a un logement tout prêt : la liste se demande à
`gate_sealed_paths`, exactement comme `playthrough.sh` le fait trois fichiers plus
loin. Rien à inventer, un précédent à copier.

Ce que la sonde **ne** dit pas, et qu'il faut écrire : ce n'est pas une garantie
qui manque. Le scellement tient quoi qu'on dise à la session. Ce qui manque est
l'autre moitié de la doctrine de ce dépôt — *dire, puis tenir* — et son coût est
réel : une itération rouge sur un chemin dont la session avait lu la liste et où
ce chemin n'était pas.

---

## §2 — Le même bloc décrit un tracker que le projet n'a peut-être pas

Sonde `q1` Q1b. Mesuré.

`init_claude_block` prend `$feature` et rien d'autre. Sa première phrase est :

> *« Issues and specs are markdown under `.scratch/<feature>/`: one file per
> ticket in `issues/NN-slug.md`, the feature spec in `spec.md`. »*

C'est vrai du backend `local` et faux des deux autres. Installé avec
`TRACKER_BACKEND=github`, le projet reçoit **le même paragraphe**, plus un
`.scratch/demo/issues` provisionné qui ne recevra jamais rien.

Ce qui fait de ça un défaut et pas une approximation : **l'installeur sait**. Au
même run, `init_preflight` lit `TRACKER_BACKEND`, reconnaît le backend distant et
imprime à la console la phrase juste — celle qui nomme `TRACKER_REPO`,
`TRACKER_TOKEN_CMD`, `WAIT_CI`, et ce que le backend distant n'achète pas. Il le
dit **une fois, à l'humain qui regarde**, et écrit l'autre version **dans le
fichier que chaque session lira toutes les nuits**. C'est la forme exacte du
constat de [64] — huit fois sur une console, zéro fois là où ça compte — prise par
l'autre bout.

`TRACKER_BACKEND` n'est pas une confirmation forcée, donc un projet qui ne dit
rien reçoit `local` et la phrase est vraie. Le cas atteignable est celui qui
répond `github` ou `gitlab`, c'est-à-dire exactement celui pour lequel [18], [73],
[76], [77] et [82] ont été écrits.

---

## §3 — Aucune des quatre règles de source ne voit le troisième point d'entrée

Sonde `q2`. Mesuré dans les deux sens.

`test/layering.bats` porte les règles *« qu'aucun test fonctionnel ne peut
voir »*. Les quatre ont la même zone :

    for f in "$dir"/lib/*.sh "$dir"/*.sh   # $dir = "$RALPH_PACK_ROOT/.claude"

Le commentaire de `layering_privates` explique le glob :

> *« `"$dir"/*.sh` and not `"$dir"/loop.sh`: the pack has two entry points since
> [16], **and an entry point outside this glob is one where a lib's `__`
> internals are reachable with nothing to say so**. »*

[19] en a livré un troisième, et il vit à la racine du dépôt. Les quatre règles
ne le voient pas :

| Règle | Ce qu'elle refuse | `init.sh` aujourd'hui |
|---|---|---|
| `layering_privates` | appeler le `__` d'un voisin | propre (que des `init__`) |
| `layering_upward` | un lib qui appelle `loop_` | sans objet |
| `layering_masked_status` | `local x="$(f)"`, qui avale le refus de `f` | propre |
| `layering_heredoc_prose` | un backtick nu dans un heredoc non cité | propre, **à la main** |

Les quatre colonnes de droite sont des propriétés de l'auteur, pas du dépôt.

Et la quatrième est celle qui coûte le plus cher ici, parce que `init.sh` est le
fichier du pack qui a la plus forte densité de prose non citée : neuf heredocs,
dont `init_gitignore_block` et `init_claude_block`, qui écrivent tous deux dans le
projet cible — et le second dans un fichier **scellé** qu'un `claude` frais lit au
démarrage.

Mesuré : un seul backtick dé-échappé dans le paragraphe du tracker (une copie de
`init.sh`, jamais le fichier du dépôt), et

- la règle, **extraite de `test/layering.bats` sans être recopiée**, l'attrape dès
  qu'on l'y pointe : `init.sh:834: an unescaped backtick in the body of an
  unquoted heredoc` ;
- l'installeur **sort en 0**. Une ligne `docs/agents/: is a directory` passe dans
  un rapport de quarante lignes ;
- le projet garde, pour toute sa vie, un `CLAUDE.md` qui dit
  *« The conventions are in . »*.

C'est [61] à l'identique, un répertoire plus loin, et avec un lecteur de plus : là
où [61] cassait le prompt d'une session, celui-ci casse le fichier que **toutes**
les sessions d'un projet lisent. Témoin appairé : le pack livré et `init.sh` tel
quel rendent tous deux `rc=0`.

---

## §4 — Le prompt dit `.scratch/`, le contrôle fait `issues/`

Sonde `q3`. Lu et confirmé par le tableau.

`loop_session_prompt` porte quatre règles. La troisième :

> *« Never stage or commit the tracker (`.scratch/`). It is the loop's own state,
> and a commit taken mid-iteration freezes it in a state that was never true. »*

Ce qui la tient est `git -C "$root" reset -q -- "$(tracker_local__issues_relpath)"`
dans `tracker_local_snapshot_moved` : **`issues/` et rien d'autre**. Le tableau le
dit déjà à sa ligne « Ne jamais stager ni commiter le tracker » — *le désindexage
de `issues/`*. La phrase du prompt promet un cran de plus que la ligne du tableau,
et la différence est `spec.md`, que `gate_is_bookkeeping` (`.scratch/$FEATURE/*`)
retire **et** du rapport du scope-guard **et** du rollback.

C'est petit et c'est exactement la forme que [17] voulait fermer : la phrase et le
contrôle ne vivent pas dans le même fichier, donc la phrase a pu grandir sans que
le contrôle bouge. La réparation n'est probablement pas d'élargir le contrôle —
`spec.md` est une zone morte nommée, et le drain l'épingle depuis [68] — mais de
faire dire au prompt ce que le pack tient, en le lui demandant.

---

## §5 — La même forme, un autre namespace : `RALPH_*`

Sonde `q4`. Mesuré.

`harness__clear_env` **dérive** les soixante-quatre clés de configuration du
`.example` et les unset une par une ; puis il unset une liste tapée à la main de
**six** noms `RALPH_*`. Le namespace en fait **quarante-deux**.

La règle que cette liste tient est celle de [40], écrite dans le ticket [19] :

> *« `loop.sh` l'assigne aujourd'hui sans condition, ce qui est la seule raison
> pour laquelle une valeur héritée du shell d'un développeur est inoffensive — et
> c'est aussi pour ça que `harness__clear_env` peut se permettre de ne pas le
> connaître. »*

Cinq noms ne respectent pas la condition : leur lib les assigne **au `source`**,
en `${X:-}`, donc en préservant une valeur héritée.

| Nom | Lib | Ce qu'il porte |
|---|---|---|
| `RALPH_RETRO_STATE` | `retro.sh:102` | le répertoire d'état du rétro — celui que `retro_guards` compose, et où vivent `capability.seen` et `brief.<id>`, les deux objets de [83] |
| `RALPH_RECEIPT` | `receipt.sh:66` | le répertoire du reçu d'audit |
| `RALPH_TRACKER_SAID` | `tracker.sh:168` | ce qui **fait taire** le repli d'un constat de tracker ([64]) |
| `RALPH_PLAYTHROUGH_SPEC` | `playthrough.sh:198` | le témoin de spec pris avant la première session |
| `RALPH_PLAYTHROUGH_OPENED` | `playthrough.sh:513` | ce que le gate de valeur a ouvert |

Mesuré : les valeurs traversent le `source` des vingt-quatre libs intactes, et
`retro_guards` — le recensement de zones que [85] vient tout juste de dériver —
rend un `index.guard` sous un répertoire choisi par l'environnement.

**Ce que ça n'est pas** : un canal de session. Aucun de ces noms n'est exporté
(seul `RALPH_DIR` l'est), donc ni un `claude` jugé ni un successeur `at` ne les
place. L'injecteur est le shell d'un humain, ou un wrapper.

**Ce que c'est** : la moitié manquante de la garantie d'hermétisme de la suite.
`test/smoke.bats` porte un test entier — *« an exported config key does not leak
in »* — parce qu'un `STERILE_K` dans le shell d'un développeur ferait mesurer son
shell à la place du pack. Le namespace du pack lui-même n'a pas ce test, et il
fait sept fois la taille de ce que le harnais en connaît.

---

## Ce que la passe a regardé et disculpé

Écrit pour que ça ne soit pas re-sondé.

- **`init.sh` ne pose aucun temporaire au premier niveau de `$TMPDIR`.** [19]
  l'avait écrit et un test le vérifie sur la source (`grep mktemp`). Vérifié :
  les deux temporaires de l'installeur (`init_gitignore`, `init_claude_md`) vivent
  **dans l'arbre cible** sous `$$`, donc hors du critère de `gate_tmp_names` par
  construction et non par oubli.
- **La liste d'ignore que `init.sh` écrit n'est pas une copie de
  `gate_is_bookkeeping`.** Elle est plus **fine** que lui à dessein : le garde
  couvre `.scratch/$FEATURE/*` entier, l'ignore ne couvre que six noms pour laisser
  `issues/` et `spec.md` visibles. C'est une décision, pas une recopie, et le
  tableau la porte.
- **`init_main` respecte la règle de [72]** : son préambule lit, imprime sur la
  console et ne garde qu'en variables de shell jusqu'à `tree_lock_acquire`.
- **`bin/ralph-init.js` ne décide rien** et deux tests le tiennent.
- **Le payload et le `files` de `package.json` sont croisés** dans le bon sens
  (chaque source du dépôt est couverte par un motif publié).
- **`.claude/pack.version`** n'est lu par personne : un reçu pour un humain, pas
  une entrée de contrôle.
- **L'angle « `.agents/skills/` n'est ni scellé ni couvert par `.claude/skills` »**
  est réel mais déjà nommé : le commentaire de `gate_sealed_paths` porte la
  réserve en toutes lettres (*« a write **through** a link lands outside the sealed
  path »*). Ce que [19] change est la portée — ce répertoire est maintenant ce qui
  part dans le prochain projet — et ça vaut une phrase dans la ligne du tableau
  qu'ouvre [86], pas un ticket.
- **`package.json` porte `"private": true`** alors que sa description dit
  `npx ralph-pack`. Voulu tant que rien n'est publié ; à rouvrir le jour d'une
  publication, pas avant.

---

## Les tickets

| # | Ce qu'il ferme | Fichiers |
|---|---|---|
| **[86]** | le bloc `CLAUDE.md` déposé : la liste scellée demandée au pack, et le paragraphe du tracker qui dépend du backend | `init.sh`, `test/install.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md` |
| **[87]** | les quatre règles de source de `test/layering.bats` étendues au troisième point d'entrée | `test/layering.bats`, `test/mutate.sh` |
| **[88]** | ce que le prompt de session dit et ce que le pack tient : la phrase `.scratch/` demandée au module qui la tient | `.claude/loop.sh`, `.claude/lib/tracker*.sh`, `test/*.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md` |
| **[89]** | le namespace `RALPH_*` recensé, et l'hermétisme de la suite étendu à ce que le pack se fabrique | `test/helpers/harness.bash`, `test/smoke.bats`, `test/mutate.sh`, et les quatre libs qui préservent une valeur héritée si la décision est de ne plus la préserver |

### Ordre proposé

**[87] → [86] → [88] → [89]**, et le critère est celui d'habitude — minimiser la
reprise, jamais l'urgence :

1. **[87] devant** parce qu'il ne touche que `test/`, qu'il est le seul à pouvoir
   dire *« la prose de `init.sh` est propre »* autrement qu'à la main, et que [86]
   va réécrire un heredoc de prose de `init.sh` — le livrer derrière, c'est
   réécrire ce heredoc sans filet, et c'est exactement ce que le §3 mesure.
2. **[86] ensuite** : c'est le plus gros, il porte les deux moitiés du §1 et du §2,
   et il hérite du filet que [87] vient de poser.
3. **[88]** derrière, parce qu'il pose la *forme* générale (demander au module la
   phrase qu'on met dans un prompt) et que [86] en aura livré la première
   application dans le pack — un précédent vaut mieux qu'un principe.
4. **[89]** en dernier : indépendant des trois autres, purement dans `test/`, et
   le seul dont aucune des trois ne change la surface.

Arêtes : [87] → [86] (le filet avant la réécriture), [86] → [88] (le précédent
avant la forme). [89] n'en a aucune.
