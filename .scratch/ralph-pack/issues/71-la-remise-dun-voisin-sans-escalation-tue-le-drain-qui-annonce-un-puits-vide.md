# 71 — La remise d'un voisin sans `Escalation:` tue le drain, qui annonce un puits vidé

**What to build:** `router__put_back` remet un ticket voisin en appelant `tracker_mark_escalated <id> "$was_esc"` avec une **valeur de champ**. Quand le voisin n'a pas de `**Escalation:**` — la forme que `capability_propose` écrit, donc tous les tickets `request` du puits — l'opération est `${2:?tracker: an escalation needs a reason}`, c'est-à-dire une **sortie du shell**. Depuis [67] l'appel n'est plus dans une substitution de commande : le drain meurt, sort **`0`** (« the sink is empty: everything in it was drained »), laisse le voisin `resolved` sans gate, le ticket du puits dedans, et `run.log` vide.

**Blocked by:** None

**Write-surface:** `.claude/lib/router.sh`, `.claude/lib/tracker.sh`, `.claude/lib/tracker-local.sh`, `test/human-loop.bats`, `test/tracker-local.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

**Tags:** human-loop, tracker, false-green

- [ ] Un drainage dont la session routée bouge un ticket voisin **sans `Escalation:`** ne meurt pas : le voisin est remis ou nommé, et le drain continue jusqu'au bout de son puits.
- [ ] Le code de sortie d'un drainage qui s'est arrêté en cours n'est **jamais** `0`. `0` veut dire ce que l'en-tête de `human-loop.sh` dit qu'il veut dire, et rien d'autre.
- [ ] Ce que l'interface du tracker a le droit de refuser, et **sous quelle forme**, est écrit dans l'en-tête de contrat de `lib/tracker.sh` : un refus est un code de retour, jamais une sortie de shell. Un backend qui refuse en tuant le shell tue ses deux appelants, dont l'un est le drain.
- [ ] Le commentaire de `router_protect_tracker` cesse d'affirmer qu'un voisin sans `Escalation:` « comes back with an empty one » : ce qui est livré est ce qui est écrit.
- [ ] Une entrée de mutation par garantie livrée, plus le témoin appairé (le même voisin **portant** une `Escalation:`).

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

- **Place dans la file (proposée par la passe du 07/09) : premier.** `Blocked by: None`, la plus petite surface des trois, le seul **faux vert livré** — un ticket `resolved` qu'aucun gate n'a lu, plus un code de sortie qui ment. Le précédent est [59], ordonné premier de sa passe pour exactement cette raison. Et sa clause d'interface est ce que [18] écrira contre. Ordre proposé : [71] → [72] → [70] → [18] → [19].
