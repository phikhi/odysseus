# 71 — La remise d'un voisin sans `Escalation:` tue le drain, qui annonce un puits vidé

**What to build:** `router__put_back` remet un ticket voisin en appelant `tracker_mark_escalated <id> "$was_esc"` avec une **valeur de champ**. Quand le voisin n'a pas de `**Escalation:**` — la forme que `capability_propose` écrit, donc tous les tickets `request` du puits — l'opération est `${2:?tracker: an escalation needs a reason}`, c'est-à-dire une **sortie du shell**. Depuis [67] l'appel n'est plus dans une substitution de commande : le drain meurt, sort **`0`** (« the sink is empty: everything in it was drained »), laisse le voisin `resolved` sans gate, le ticket du puits dedans, et `run.log` vide.

**Blocked by:** None

**Write-surface:** `.claude/lib/router.sh`, `.claude/lib/tracker.sh`, `.claude/lib/tracker-local.sh`, `.claude/human-loop.sh`, `test/human-loop.bats`, `test/tracker-local.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** resolved

**Tags:** human-loop, tracker, false-green

- [x] Un drainage dont la session routée bouge un ticket voisin **sans `Escalation:`** ne meurt pas : le voisin est remis ou nommé, et le drain continue jusqu'au bout de son puits.
- [x] Le code de sortie d'un drainage qui s'est arrêté en cours n'est **jamais** `0`. `0` veut dire ce que l'en-tête de `human-loop.sh` dit qu'il veut dire, et rien d'autre.
- [x] Ce que l'interface du tracker a le droit de refuser, et **sous quelle forme**, est écrit dans l'en-tête de contrat de `lib/tracker.sh` : un refus est un code de retour, jamais une sortie de shell. Un backend qui refuse en tuant le shell tue ses deux appelants, dont l'un est le drain.
- [x] Le commentaire de `router_protect_tracker` cesse d'affirmer qu'un voisin sans `Escalation:` « comes back with an empty one » : ce qui est livré est ce qui est écrit.
- [x] Une entrée de mutation par garantie livrée, plus le témoin appairé (le même voisin **portant** une `Escalation:`).

## Comments

- **Trouvé par la passe transversale du 07/09/2026** (`../passe-transversale-07-09.md`, §2). Sondes : `../sondes/passe-07-09/q2-*.bats`.

- **Mesuré** (`q2`), un voisin dans le puits sans `**Escalation:**` :

  | | |
  |---|---|
  | Q2c — une session routée sur `20-decision` met `21-second` à `resolved` | le drain **meurt** dans la remise. `rc = 0`. `20-decision` toujours `ready-for-human`, **`21-second` `resolved`**, `run.log` **vide** (pas même la ligne `drain-session`), les deux verrous relâchés |
  | Q2d — témoin appairé, le même voisin portant `**Escalation:** decision` | remis, nommé, `tracker-drift restored` journalisé, rc=3 |
  | Q2b — témoin appairé, deux sessions, rien de touché | silence, 0 ligne de dérive, rc=3 |

- **C'est un faux vert livré et le cas est ordinaire.** `capability_propose` est le producteur unique du puits pour le palier capacité, le palier rétro et `playthrough__escalate` ; il écrit `**Status:** ready-for-human`, `**Blocked by:** None`, et **aucun `Escalation:`**. Ce sont exactement les tickets du guichet `request` — ceux que le puits existe pour recevoir. Il suffit qu'il y en ait un et qu'une session routée touche son `Status:`, c'est-à-dire l'écriture même que [58] existe pour attraper.

- **Le `0` est mesuré, pas déduit.** `${param:?word}` sort du shell avec le statut de la dernière commande exécutée et non avec `1` — vérifié hors pipeline (`bash human-loop.sh <fichier ; rc=$?`). Donc l'opérateur reçoit le code que `human-loop.sh` documente comme « the sink is empty: everything in it was drained », sur un puits qui ne l'est pas. **Une sonde qui mesure ce statut à travers un `|` mesure autre chose.**

- **Ce que [67] a hérité sans le savoir, et c'est la question 4 de `CLAUDE.md` dans sa forme la plus pure.** Avant [67] l'appel était `moved="$(router_protect_tracker "$id")"` — un sous-shell, où un `${:?}` ne tue que le sous-shell (mesuré : la substitution rend le vide, l'appelant survit, rc 0). Le rapport était perdu, le drain vivait. [67] a sorti l'appel de la substitution **pour la bonne raison** — le témoin de journal meurt dans un sous-shell — et a transformé un rapport perdu en drain mort qui annonce un puits vidé. Le défaut n'était faux dans aucun des deux tickets pris isolément.

- **La forme du correctif est à décider dans ce ticket, et il y a trois moitiés à trancher séparément.**

  1. *Le refus de l'opération.* Un `Escalation:` vide est-il une valeur légitime que le backend doit écrire, ou un refus ? Les deux sont défendables — `tracker_mark_escalated` définit `ready-for-human` **avec une raison**, et un ticket du puits sans raison est un état que le pack produit lui-même par `capability_propose`. Ce qui n'est pas défendable est la troisième réponse actuelle : refuser en tuant l'appelant.
  2. *Ce que `router__put_back` fait d'un refus.* Il a déjà un code pour ça (`2`, « it is, and writing it failed ») et une phrase (« putting it back to `%s` failed. It is where that session left it, and no gate has seen it »). Elle n'est jamais imprimée pour ce cas.
  3. *Le code de sortie.* Un drainage qui s'arrête en cours a déjà un code qui n'est ni `0` ni `3` : `4`, « stopped by a guard ». La question est de savoir si une mort d'appelant peut être ramenée sous un code du tout — voir la clause d'interface ci-dessous, qui est la seule réponse structurelle.

- **Clause d'interface, et c'est l'arête vers [18] :** *ce qu'une opération de l'adaptateur a le droit de refuser, et sous quelle forme.* Aujourd'hui l'en-tête de `lib/tracker.sh` documente les opérations et leurs valeurs de retour, jamais leurs refus. Le dispatcher, lui, rend `3` pour une opération non implémentée — donc la forme existe et n'est écrite nulle part comme un contrat. Un backend distant qui refuserait un argument par un `${:?}`, un `exit`, ou une erreur `set -e` non rattrapée tuerait **les deux points d'entrée**, et celui qui coûte le plus cher est le drain : il n'a ni sous-shell d'itération ni `proc_collect` entre lui et ses libs, exactement parce que [67] a retiré le dernier.

- **Inventaire fait, à ne pas refaire :** le pack porte vingt `${N:?}`. Dix-neuf prennent un argument d'appelant — un id, un nom de champ, un prompt. Un seul est piloté par une valeur lue sur un ticket, et c'est `tracker_local_mark_escalated`. Et `failures.sh` appelle `tracker_mark_escalated` sous `if [ -n "$reason" ]`, donc le chemin AFK ne peut pas atteindre cette sortie : la garantie est à livrer pour le drain, et la clause d'interface pour les deux.

- **Ce qu'une mutation doit retirer.** Pas seulement « le voisin est remis » — le test doit **survivre au drain**, donc asserter sur quelque chose qui n'existe que si le drainage a continué : le ticket suivant offert, la ligne de tally finale, ou le code de sortie. Un `assert_success` sur le drain est ici le pire des mensonges possibles, le drain mort rendant `0`.

- **Place dans la file, validée par Philippe le 07/09/2026 : premier.** `Blocked by: None`, la plus petite surface des trois, le seul **faux vert livré** — un ticket `resolved` qu'aucun gate n'a lu, plus un code de sortie qui ment. Le précédent est [59], ordonné premier de sa passe pour exactement cette raison. Et sa clause d'interface est ce que [18] écrira contre. Ordre retenu : [71] → [72] → [70] → [18] → [19].

## Ce qui a été livré, le 07/09/2026

- **Écart de write-surface, assumé et le seul :** `.claude/human-loop.sh` a été ajouté à la surface déclarée. Le deuxième AC — *le code de sortie d'un drainage qui s'est arrêté en cours n'est jamais `0`* — est une propriété des codes de sortie de ce fichier ; il n'y a pas d'endroit d'où le tenir sans y toucher, et la seule autre réponse était d'écrire dans le tableau que rien ne le tient. Le ticket demandait explicitement de trancher ce point, c'est ce qui a été tranché.

- **Les trois moitiés, tranchées.**

  1. *Un `Escalation:` vide est une **valeur**, pas un refus.* `tracker_local_mark_escalated <id> ""` écrit `ready-for-human` et **lâche le champ** — le geste exact de `mark_ready`. Raison décisive : `ready-for-human` sans `Escalation:` est la forme que le pack produit lui-même (`capability_propose`, guichet `request`), et aucun verbe public ne savait l'écrire ; le refus aurait laissé le voisin `resolved` — hors du puits **et** hors de la frontière, donc plus jamais revu par un drain — avec une phrase à l'écran pour toute réparation. Le critère anti-faux-vert tranche : on remet, on ne raconte pas. Un **argument manquant** reste un refus, par `return 2` : c'est un bug d'appelant, pas un état.
  2. *Ce que `router__put_back` fait d'un refus* : ce qu'il documentait déjà, `2`, et sa phrase s'imprime enfin (« putting it back to `%s` failed. It is where that session left it, and no gate has seen it »), avec `tracker-drift restore-failed` au journal. Le cas est atteignable dès qu'un backend refuse *en rendant un code* — c'est ce que teste `an adapter that refuses to put a neighbour back`, qui remplace l'opération par un `return 2` depuis un lib chargé après `tracker-local.sh`, c'est-à-dire depuis la position où répondra le backend de [18].
  3. *Le code de sortie* : ni `0` ni un `4` élargi, mais un **`6`** neuf — « ended in the middle, where nothing here decided to stop ». `4` était le presque-bon : c'est un **garde** qui arrête un drain par ailleurs sain, et dire « un verrou est parti » d'un shell qu'on a tué sous l'opérateur l'envoie regarder la seule chose qui n'a rien à voir. Le garde est un piège `EXIT` qui ne convertit **qu'un `0`** ; tout autre code passe intact.

- **Le piège du piège, et il a coûté un rouge :** `run_lock_acquire` et `tree_lock_acquire` posent chacun leur propre `trap 'state_locks_release' EXIT`. Un garde armé en tête de fichier est donc **désarmé par les verrous eux-mêmes** — mesuré : premier essai vert au préflight, `rc=0` dès que le drain prend ce qu'il vient prendre. D'où la forme livrée : `human_loop__on_exit` relâche les verrous lui-même, et `human_loop__arm_signals` le **réarme** — la fonction est déjà appelée juste après les deux acquisitions et après chaque session. Les deux placements ont chacun leur mutation et chacun son test, parce que retirer celui de tête seul serait invisible.

- **Ce que le garde couvre vraiment, mesuré aux deux bouts.** Le trap de tête n'est pas décoratif : `human_loop_preflight` passe les constats du tracker dans le shell du drain ([64]), donc une opération qui finit son appelant *là* finissait un drain qui n'avait ni lu le puits ni écrit une ligne — et sortait `0` quand même. Le test `ended before it took its locks` le mesure en remplaçant `tracker_finding_said`, la fonction d'interface qui tourne à ce moment-là dans ce shell, et en semant deux tickets portant le même `NN` pour que `tracker_preflight` produise le constat qui l'atteint.

- **Ce qu'il n'y avait pas moyen de tenir, écrit dans le tableau plutôt que supposé.** La clause d'interface (« un refus est un code de retour ») est une **règle**, et aucun test de ce dépôt ne peut lire le backend d'un projet ou celui de [18] : c'est écrit tel quel dans la ligne neuve de `docs/frontiere-de-confiance.md`. Ce qui la tient depuis ce dépôt est le seul bout qui est ici — la sortie du drain, qui ne peut plus mentir même quand la clause est violée.

- **Question 4 — ce que le ticket suivant hérite.** `loop.sh` porte le même `0` (« the frontier was drained ») et **aucun garde de ce genre**. Le chemin AFK n'atteint pas ce défaut-ci — `failures.sh` n'appelle `tracker_mark_escalated` que sous `[ -n "$reason" ]`, et les deux autres appelants passent `decision` en dur — mais la *forme* y est ouverte pour n'importe quel lib qui finirait le shell. Consigné dans **[72]**, qui travaille déjà sur les deux points d'entrée et porte `loop.sh` dans sa write-surface.

- **Ce que la remise ne distingue pas, dit plutôt que découvert :** un ticket portant `**Escalation:**` sans valeur et un ticket ne portant pas la ligne se lisent identiquement à travers `tracker_field`, donc une remise du premier écrit le second. Les deux sont `request` au guichet et aucun ne porte de raison : rien en aval ne les sépare.

- **Sondes rejouées sur le code livré** (`../sondes/passe-07-09/q2-*.bats`) : Q2c rend `rc=3`, remet `21-second` en `ready-for-human` **sans** `Escalation:`, journalise `action=restored` et **offre** le ticket (`── 21-second ── no escalation reason ── desk: request`) ; Q2a ouvre enfin ses **deux** sessions ; Q2b reste silencieuse ; Q2d inchangée. Le fichier remis est celui du départ, octet pour octet.

- **Neuf mutations**, toutes `ok`, dont trois témoins appairés : la raison qu'un voisin *portait* est toujours remise, un drain qui atteint sa propre fin sort toujours `0`, et un code de sortie que la boucle a décidé passe intact.

- **Piège de harnais rencontré :** ne jamais mesurer le code de sortie du drain à travers un `|`. Et pour semer le cas, il faut un voisin **sans** `Escalation:` — `two_in_the_sink` en met une à tout le monde, d'où `sink_without_an_escalation`.
