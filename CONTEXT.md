# Framework de développement autonome (odysseus)

Ce contexte couvre la conception d'un framework de dev réutilisable : une boucle bash qui relance des sessions Claude Code headless à contexte frais, tâche par tâche, pour broyer la phase de delivery sans intervention humaine, sous contrainte de budget d'usage. Ce glossaire fixe le vocabulaire du domaine ; il ne contient aucun détail d'implémentation.

## Language

### La boucle

**Ralph loop**:
La boucle bash qui, à chaque tour, choisit la prochaine tâche puis relance une session Claude Code neuve pour l'exécuter. C'est le cœur du framework.
_À éviter_ : script, orchestrateur, runner.

**Itération**:
Un tour de la ralph loop portant sur une seule tâche : choisir → spawn session fraîche → exécuter → vérifier → marquer.
_À éviter_ : boucle (réservé à la ralph loop), cycle, passe.

**Run**:
Une exécution continue de la ralph loop, c'est-à-dire une suite d'itérations entre un démarrage et un arrêt (ou une pause budget).
_À éviter_ : session (réservé à la session fraîche), exécution, job.

**Session fraîche**:
Une invocation Claude Code non-interactive (headless) démarrée avec un contexte neuf et optimal pour une seule tâche, jamais compactée. Une itération en spawn exactement une.
_À éviter_ : session headless, instance, contexte hérité.

**Smart zone**:
L'état d'une session dont le contexte reste sous le seuil de ~200K tokens, où le modèle raisonne à pleine capacité. La garantie centrale : chaque tâche doit finir en smart zone.
_À éviter_ : contexte sain, zone verte.

**Dumb zone**:
L'état dégradé d'une session dont le contexte a dépassé le seuil ou a été compacté, où la qualité de raisonnement chute. À proscrire.
_À éviter_ : contexte saturé, zone rouge.

**Compaction**:
La réduction/résumé automatique du contexte d'une session (le *handoff* de contexte). Interdite dans ce framework car elle mène en dumb zone ; le passage d'état se fait par relance d'une session fraîche, pas par compaction.
_À éviter_ : handoff, résumé de contexte, summarization.

**Journal de run**:
Le fichier append-only, un par feature, qui capte l'observabilité d'un run — par itération : la tâche, son issue (succès/échec), son coût, son nombre de tours, son horodatage. *Non autoritaire* : il n'est jamais lu pour choisir ni marquer une tâche ; le tracker reste la seule source de vérité. Une ligne manquante après un crash est sans conséquence.
_À éviter_ : log, trace, historique, état.

**Verrou de run**:
Le mécanisme grossier, un par feature, qui garantit qu'une seule ralph loop est active à la fois sur un même **tracker**. Il empêche le double-run accidentel sur une frontière ; ce n'est pas de la concurrence par-ticket (plusieurs itérations sur un même tracker), laissée hors sujet. Il ne garde que le tracker : ce qui garde l'arbre est le **verrou d'arbre**.
_À éviter_ : lock, mutex, sémaphore, claim, verrou de dépôt (le verrou d'arbre n'est pas par dépôt).

**Verrou d'arbre**:
Le second verrou, un par **arbre de travail**, qui garantit qu'une seule ralph loop touche un arbre à la fois — quelles que soient les features visées. Il existe parce que le snapshot du scope-guard, le rollback, le commit sur vert et `HEAD` sont tous à l'échelle du dépôt : deux runs sur deux features d'un même arbre s'imputent mutuellement leurs écritures et se rollbackent l'un l'autre. Il vit dans le répertoire git, hors d'atteinte d'un `git add -A`, d'un `git clean` ou d'un `rm -rf .scratch`. Un worktree lié ayant son propre répertoire git, il est déjà par arbre et non par dépôt : c'est ce qui rendra la concurrence possible quand chaque itération aura son **worktree d'itération**.
_À éviter_ : verrou de dépôt, verrou global, verrou de run (c'est l'autre, et il garde autre chose).

### L'unité de travail

**Tâche**:
L'unité qu'une session fraîche broie en une itération : une slice verticale « tracer bullet » issue du découpage en tickets, dimensionnée pour finir sous le seuil 200K.
_À éviter_ : story, item, unité de travail.

**Ticket**:
Le fichier markdown durable décrivant une tâche dans le tracker (`.scratch/<feature>/issues/NN-<slug>.md`), auto-suffisant car aucun contexte n'est hérité entre itérations.
_À éviter_ : issue (en français), carte, note.

**Frontière**:
L'ensemble des tickets éligibles à la prochaine itération : ouverts, débloqués et marqués prêts pour l'agent. La ralph loop y puise sa prochaine tâche.
_À éviter_ : file d'attente, backlog, queue.

**Contrat**:
L'ensemble des artefacts que la discovery doit produire (spec validée + tickets débloquables et auto-suffisants) pour que la delivery soit broyable sans humain. Le franchissement du contrat est la porte de validation humaine.
_À éviter_ : handoff, cahier des charges, interface.

### Les phases

**Discovery**:
La phase amont, pilotée par l'humain (HITL), qui produit le contrat : cadrage, spec et tickets validés.
_À éviter_ : conception, cadrage, exploration.

**Delivery**:
La phase aval, autonome, où la ralph loop broie les tickets de la frontière sans humain.
_À éviter_ : implémentation, exécution, build.

**Gate QA**:
La porte de vérification, par itération, qui décide qu'une tâche est *resolved* (p. ex. tests verts, revue deux axes, typecheck) ou *failed*.
_À éviter_ : validation, contrôle qualité, check.

### Le budget d'usage

**Fenêtre de session**:
La fenêtre glissante de 5 h de l'abonnement Claude, à l'intérieur de laquelle un run consomme son quota avant réinitialisation.
_À éviter_ : quota horaire, fenêtre 5h (dans le texte courant, écrire « fenêtre de session »).

**Limite hebdomadaire**:
Le plafond d'usage sur la semaine, indépendant de la fenêtre de session ; un run doit s'arrêter avant de le cramer.
_À éviter_ : quota semaine, cap hebdo.

**Fenêtre de budget**:
La contrainte de budget active à un instant donné (fenêtre de session ou limite hebdomadaire) sur laquelle la boucle décide de pauser puis reprendre.
_À éviter_ : budget, allocation.

### Le produit

**Blueprint**:
Le livrable de cet effort : le design gelé du framework réutilisable, prêt au handoff vers l'implémentation. Aucun code n'est produit pendant sa conception.
_À éviter_ : plan, spec (réservé au contrat), architecture.

**Substrat**:
L'ensemble des skills d'ingénierie déjà installés (grilling, research, domain-modeling, to-spec, to-tickets, implement, tdd, code-review, triage, wayfinder) que le framework réutilise sans les réinventer.
_À éviter_ : dépendances, librairie, base.

### L'auto-apprentissage

_(Ajouté par le durcissement v2, ticket [11]. Le journal de run capte l'observabilité brute ; l'auto-apprentissage capte la connaissance apprise, decision-grade.)_

**Record de leçon**:
Un fichier `learning-records/NNNN-slug.md` (format `teach`) captant une seule leçon *decision-grade* tirée de la delivery : ce qui a été appris et pourquoi ça oriente les sessions futures. Écriture atomique (temp+`mv`).
_À éviter_ : log, note, entrée de journal (réservé au journal de run).

**Index de leçons**:
Le fichier `LEARNINGS.md` à la racine du projet cible : une ligne par record **actif** (gist + pointeur), assez petit pour être injecté inline dans chaque session fraîche. C'est un **working set** de leçons non-promues, jamais un log qui gonfle.
_À éviter_ : learnings (en vrac), base de connaissances, historique.

**Subagent retro**:
La session fraîche isolée, spawnée par la boucle **après le gate**, sur tier bon marché, qui inspecte le résultat de l'itération et n'écrit un record **que** s'il y a une leçon. Auto-suppressif (défaut : rien).
_À éviter_ : rétro (l'action de fin de story ailleurs), reviewer, session de vérif.

**Promotion**:
L'élévation d'une leçon **récurrente** en règle dure : soit une guidance ajoutée au `CLAUDE.md` du projet cible (**autonome**, interne), soit un gate/lint/hook (**escaladé** en `ready-for-human`, contractuel). Jamais silencieuse.
_À éviter_ : règle, escalade (réservé à la sortie humaine du gate).

**Drain**:
Un mécanisme qui **retire** une leçon de l'index actif — par supersession ou par promotion — gardant l'index borné en working set. Le drain-par-promotion est le principal.
_À éviter_ : purge, GC, nettoyage.

### La valeur bout-en-bout

_(Ajouté par le durcissement v2, ticket [12].)_

**Playthrough**:
La vérification narrée du **flux utilisateur bout-en-bout** d'une feature, rejouée par un subagent frais sur les vrais assets à la clôture (frontière vide), produisant un artefact persisté (`docs/playthroughs/<feature>.md`) + verdict. Condition matérielle de clôture de feature.
_À éviter_ : e2e (réservé au test), démo, recette.

**Gate terminal**:
Le gate de **niveau feature** exécuté une seule fois, dans la branche « tout résolu » de la boucle, avant l'exit succès — par opposition au gate QA par-itération [08].
_À éviter_ : gate final, gate de sortie.

**Trou de câblage**:
Le défaut qu'attrape le playthrough : un mécanisme livré et testé unitairement mais **jamais relié au flux utilisateur** (la valeur n'atteint pas l'utilisateur). Interne (re-câblage autonome) ou contractuel (escalade).
_À éviter_ : bug d'intégration, régression, gap.

**Garde de non-occlusion**:
L'assertion géométrique qu'un élément visuel superposé est réellement rendu, dans le viewport et **non recouvert** (au point attendu) — spécialisation de l'e2e [05] pour toute surface superposée. Règle portée par Odysseus, outil fourni par le stack.
_À éviter_ : test visuel, snapshot, régression pixel.

**Fidélité de l'environnement de vérif**:
La garantie que la vérif visuelle tourne dans des conditions proches de la prod : **outil de pilotage réel** (navigateur) **et vrais assets** (jamais un fixture). Confirmée en discovery [09] ; jamais un faux-vert.
_À éviter_ : environnement de test, staging, mock.

**Axe fidélité**:
Le regard *jugement* (LLM), par-ticket, qui vérifie que la valeur d'un ticket est **câblée/consommée jusqu'à l'utilisateur** — 4ᵉ branche du gate [08], gatée au risque. Complément du « c'est là » objectif de la garde de non-occlusion et du playthrough feature.
_À éviter_ : review produit, PO, axe Spec.

### Le parallélisme par-ticket

_(Ajouté par le durcissement v2, ticket [15] — révise la concurrence « hors-sujet » d'[04].)_

**Write-surface**:
L'ensemble déclaré des fichiers qu'un ticket va créer ou modifier (globs), produit par `to-tickets` et porté par le ticket. Deux tickets à write-surfaces disjointes sont parallélisables ; sinon ils sont séquencés. Mécanisme unifié avec le scope-guard.
_À éviter_ : périmètre, scope (ambigu), fichiers touchés.

**Scope-guard**:
Le verrou d'intégrité de la write-surface : un check post-hoc au gate (`git diff --name-only` vs globs déclarés) qui échoue si l'itération a écrit hors de sa surface ; hook `PreToolUse` optionnel pour bloquer tôt. Débordement dans un autre ticket = drift (escalade) ; dans un fichier neutre = retry. Juge contre la surface du **spawn**, restaurée par la protection du tracker avant qu'il ne lise le ticket — sinon il lirait un contrat que la session vient d'écrire. Juge l'**arbre jugé**, qu'il reçoit et ne calcule pas. Voit ce que git voit **à travers les règles épinglées** du spawn, plus les **chemins gardés** ; la **configuration scellée** est refusée avant même qu'il consulte la surface, et un déplacement de la frontière de visibilité hors de l'arbre l'est au même titre.
_À éviter_ : lint, garde-fou, sandbox (réservé à l'exécution).

**Arbre jugé**:
L'objet tree que le gate prend **une fois, avant de lancer sa première branche**, et sur lequel tout parle ensuite : le scope-guard, le rollback, le commit durable et les lentilles à venir. Deux branches du gate sont les commandes du projet cible, donc écrivent dans l'arbre qu'elles jugent : un contrôle qui figerait son entrée pendant ce temps ne rendrait pas un verdict mais un tirage — le même ticket avec la même session obtenait `scope=green` ou `scope=red` selon qui écrivait le premier.
_À éviter_ : snapshot du gate (ambigu avec les autres objets tree), état final.

**Chemins gardés**:
Les chemins que le snapshot d'arbre prend **par force**, règles d'ignore du projet cible incluses (`GUARDED_PATHS`, défaut `.claude`). Sans eux, ce que `.gitignore` couvre est hors du scope-guard *et* hors du rollback : une session écrit hors surface, garde son écriture après un gate rouge, et laisse un fichier qui change le verdict des tickets suivants. La liste est nommée et pas universelle : forcer l'arbre entier ferait entrer le build output du projet dans le tree jugé, donc déborder à chaque itération. Ce sont des **chemins**, pas des globs : lus littéralement des deux côtés du mécanisme (pathspecs `:(literal)` au forçage, comparaison littérale à l'énumération), donc un répertoire appelé `Design Assets` ou `zone[1]` se garde comme un autre — et un `GUARDED_PATHS` rédigé comme un glob ne garde rien et se fait nommer par la zone ignorée non gardée, au lieu de garder quelque chose en silence.
_À éviter_ : whitelist, chemins protégés (réservé au tracker), exceptions.

**Liste de chemins**:
La convention d'échange du pack : **une entrée par ligne**, lue ligne par ligne, jamais un `for x in $liste`. Un chemin peut porter une espace ou un métacaractère, donc une ligne de mots n'est pas une liste de chemins mais ce que le découpage en mots et l'expansion de glob en font — et deux mécanismes qui lisent la même liste avec deux découpages ne se contredisent pas bruyamment, ils se contredisent en silence : le forçage n'a rien pris, l'énumération croit qu'il a pris, le chemin n'est ni jugé ni nommé. Les formats **rédigés par un humain** — le champ `Write-surface:` d'un ticket, les clés de config qui nomment des globs — restent séparés par des espaces et sont convertis *à la lecture*, là où ils sont lus ; ils ne peuvent donc pas exprimer un chemin à espace, et c'est une propriété de ce qu'un humain tape. `GUARDED_PATHS` est l'exception qui se rédige une ligne par chemin, parce qu'elle nomme des chemins et non des globs.
_À éviter_ : tableau (bash 3.2), liste séparée par des espaces, chaîne de chemins.

**Zone ignorée non gardée**:
Ce que le `.gitignore` du projet couvre en dehors des chemins gardés : jugé par rien, défait par rien, **nommé à chaque itération et à chaque rollback** (combien de chemins, et les dix premiers). Le seul mode de panne qui y vit est une suite de tests qui lit un fichier ignoré : un ticket peut passer au vert grâce à ce qu'une session antérieure y a laissé. La liste ne nomme jamais un chemin que le pack juge : ni un chemin gardé, ni ce que les **règles épinglées** ne cachaient pas, et un répertoire replié qui *contient* un chemin jugé est parcouru d'un niveau plutôt qu'annoncé en bloc — sans quoi un projet qui ignore `.scratch/` sans avoir commité son tracker s'entend dire que personne n'a jugé le tracker.
_À éviter_ : zone morte (c'était le nom du défaut, pas de l'état déclaré), angle mort.

**Règles épinglées**:
Les règles d'ignore telles qu'elles étaient **au spawn** de l'itération, relevées dans un **dépôt-témoin** (un `git init` en répertoire temporaire, portant une copie de chaque source de règles et aucun fichier du projet) et interrogées avec `git check-ignore`. Quatre sources : les `.gitignore` de l'arbre, `.git/info/exclude`, `core.excludesFile`, le fichier d'exclusion global. Tout ce qui est caché *maintenant* et que ces règles ne cachaient pas est forcé dans l'arbre jugé : une session ne peut donc pas élargir l'angle mort dans lequel elle est jugée. Un ticket garde le droit d'ajouter une règle — elle compte à partir de l'itération suivante, comme sa write-surface compte depuis le spawn. Les deux sources du répertoire git sont en plus **remises** et rendent l'itération rouge, faute de quoi la frontière élargie deviendrait celle que l'itération suivante épingle.
_À éviter_ : rules cache, gitignore gelé, snapshot des règles (réservé aux objets tree).

**Mesure refusée**:
Ce que rend un contrôle du pack qui **n'a pas pu regarder**, par opposition à un contrôle qui a regardé et n'a rien trouvé. Les deux se ressemblent — une liste vide — et disent le contraire : le snapshot d'arbre refuse quand les règles épinglées sont illisibles, et tout ce qui est bâti dessus hérite du refus. La convention du pack est que la différence vit dans le **statut** de la fonction qui mesure, jamais dans la mémoire de ses lecteurs, et que chaque lecteur choisit : les deux qui jugent rougissent, les deux qui annoncent disent qu'ils n'ont pas pu compter au lieu d'annoncer zéro. Un rollback qui n'a pas pu agir va plus loin et **arrête le run** — sans quoi l'itération suivante prend l'arbre non défait pour son état d'avant, et ce qu'une session y a laissé n'est plus le changement de personne.
_À éviter_ : liste vide, échec silencieux, aucun changement.

**Écritures du gate**:
Ce que les branches du gate changent dans l'arbre **après** l'arbre jugé : un rapport de couverture, un snapshot de test mis à jour, un `rm -rf dist/` de build, et demain le flux d'une lentille. Dans aucun des deux trees que le rollback diffe, et pas ignoré par git non plus — donc jugé par rien, défait par rien, et **nommé** à chaque itération comme la zone ignorée, la ligne du rollback étant nette de ce qu'il a effectivement remis. Les lignes disent *changed* et non *wrote* parce qu'une suppression en fait partie. Tenable parce que ces commandes viennent d'un fichier scellé. Ce qu'écrit une **lentille** n'en fait pas partie et n'a jamais eu le droit d'en faire partie : c'est un modèle, donc ça relève du confinement des écritures de lentille, pas de l'énumération.
_À éviter_ : artefacts (trop large), pollution, résidus.

**Configuration scellée**:
Les fichiers qu'**aucune write-surface ne peut couvrir**, la liste étant dérivée de son critère et non des cas qui l'ont fait écrire : tout ce qu'un `claude` frais lit au démarrage — `.claude/settings.json`, `.claude/settings.local.json`, `CLAUDE.md`, `CLAUDE.local.md`, `.mcp.json`, `.claude/agents`, `commands`, `skills`, `hooks` — plus le fichier que le run suivant source, sous le nom que `RALPH_CONFIG` lui donne réellement. Hooks, permissions, env et serveurs MCP prennent effet dès le spawn suivant ; la configuration porte `TEST_CMD`. Toujours dans le snapshot, quoi que dise `GUARDED_PATHS`. Le *code* du pack n'en fait pas partie : un run a sourcé ses libs avant sa première session, et un ticket qui réécrit le gate est un ticket légitime.
_À éviter_ : fichiers interdits, read-only, verrou.

**Protection du tracker**:
La restauration des tickets qu'une session a édités, depuis un objet tree de `issues/` pris au spawn, faite **avant** que le gate ne lise quoi que ce soit du tracker. Une itération qui a édité un ticket ne peut pas être verte (outcome `tracker-write`). Un ticket qu'une session a *créé* n'est pas restauré : il part en quarantaine, parce qu'une création ne se décrée pas et qu'un humain doit trancher.
_À éviter_ : rollback du tracker (le rollback l'exclut, à dessein), verrou.

**Rollback d'itération**:
La remise du dépôt dans l'état où la session l'a trouvé, après tout échec. Aussi large que le diff de la session et pas plus : ses ajouts sont supprimés, ses modifications et suppressions restaurées depuis le snapshot pré-session, son commit éventuel défait (`HEAD` remis au commit pré-spawn). **N'est pas** un `git reset --hard` + `git clean` : le travail non commité que le run n'a pas produit ne lui appartient pas. Le tracker en est exclu — c'est la seule autorité d'état. Trois exceptions énumérées et non déduites : le tracker, la **zone ignorée non gardée**, et les **écritures du gate** — les deux dernières, le rollback les nomme au lieu de les taire. Un rollback qui n'a **rien pu défaire** (pas de snapshot pré-session, arbre illisible) est une **mesure refusée** et pas un rollback vide : il le dit, et le run s'arrête là.
_À éviter_ : reset, nettoyage, revert (réservé à un commit inverse).

**Travail durable**:
Ce qu'une itération verte a produit, **commité** par la boucle avant l'itération suivante, en ne contenant que les chemins approuvés par le scope-guard. C'est ce qui rend le commit pré-spawn utilisable comme point de rollback : sans lui, un échec ultérieur emporterait tout ce que le run a déjà gaté vert.
_À éviter_ : sauvegarde, snapshot (réservé aux objets tree du scope-guard).

**Rien livré (`delivery=red`)**:
Le verdict d'une itération dont le gate ne voit **changer aucun fichier** : rendu avant le fan, donc sans démarrer une seule branche, et rouge quoi qu'auraient dit les commandes du projet. Posé sur la liste même que le travail durable commite — « la session a-t-elle écrit » et « ce que ce gate approuve est-il non vide » sont le même calcul — donc il attrape aussi l'itération dont le travail était déjà dans son propre `base`. C'est le seul défaut du pack qui produisait un faux **livré** : le ticket quittait la frontière pour de bon, sans commit et sans que rien s'en souvienne. Une **mesure refusée** n'en est pas un : sur un arbre illisible ce contrôle ne conclut pas, il laisse le scope-guard refuser. Ce n'est pas un échec d'implémentation — rien n'a été jugé, donc pas de branche `failed/<ticket>` et une raison d'escalade à soi.
_À éviter_ : diff vide (c'est la cause, pas le verdict), itération stérile (réservé au filet `STERILE_K`), gate rouge.

**Claim**:
La prise atomique d'un ticket (`Status: claimed` + propriétaire + horodatage) avant spawn, qui le retire de la frontière pour les pickers concurrents. Un claim dont le propriétaire est mort est **réclamé au balayage**, en tête de chaque itération, avant la lecture de la frontière — sans quoi un run tué emporte son ticket hors de la frontière pour toujours.
_À éviter_ : lock (réservé aux verrous), réservation, assignation.

**Worktree d'itération**:
Le git worktree isolé dans lequel une itération construit, teste et roll-back, sans conflit avec les itérations parallèles. Ses commits sont repliés sur la branche principale par l'**intégration sérialisée**.
_À éviter_ : branche, sandbox (réservé à l'exécution).

**Intégration sérialisée**:
Le repli, **un à la fois**, des worktrees gatés sur la branche principale par la boucle (le build est parallèle, l'intégration est sérielle) ; couvre aussi la mise à jour de l'index de leçons.
_À éviter_ : merge, rebase, fusion.

**Liveness du claim**:
La politique qui décide qu'un claim est mort (donc balayable) : **pid vivant** en primaire (le propriétaire est une itération courte-durée), **TTL** en backstop (anti pid-recycling), **fail-open** (incertain → balayable, jamais de deadlock). Pas de verrou séparé ni de heartbeat : la politique se lit sur le champ `Claimed:` du ticket, seul état durable du claim. Le claim réclamé d'**un run du pack** (`owner=pid:<n>`) est **compté comme un crash** — c'en est un, que personne n'était vivant pour classer — donc il consomme un retry et finit dans la boucle humaine au plafond, avec la raison `decision` : rien n'a été jugé, il n'y a pas de branche `failed/<ticket>` à lire ([26]). Le claim d'un **owner que le pack ne pingue pas** est volé au même titre quand le backstop tombe, mais **ne consomme rien** : un claim qu'on a seulement attendu n'est pas une tentative ratée.
_À éviter_ : verrou de session (pas d'artefact séparé), mutex, flock, zombie.

### Le backend de tracker

_(Ajouté par le durcissement v2, ticket [16] — étend [09].)_

**Adaptateur de tracker**:
L'interface fixe de fonctions shell (`frontier`, `read_ticket`, `claim`, `mark_*`, `open_ticket`, `append_note`) que la boucle appelle sans connaître le backend. Trois implémentations pluggables : `local` (fichiers, défaut), `github`, `gitlab`. Ops durables remote-ables, liveness du claim toujours locale.
_À éviter_ : driver, connecteur, plugin.

### L'auto-chaînage

_(Ajouté par le durcissement v2, ticket [17] — révise [07].)_

**Successeur one-shot**:
Le run programmé **une seule fois** au reset de la fenêtre de budget bloquante, qui reprend la delivery après un mur hebdo — préservant l'AFK sans dormir un process des jours. Singleton (un seul à la fois), protégé par le verrou de run.
_À éviter_ : cron (récurrent), relance, reprise.

**Chaîne de fallback (scheduler)**:
L'ordre auto-détecté des mécanismes de programmation one-shot que la boucle essaie (`at` → systemd/launchd → cron auto-effaçant → skill `schedule` → repli humain), figé dans `SCHEDULER`.
_À éviter_ : ordonnanceur, planificateur.

### L'audit a posteriori

_(Ajouté par le durcissement v2, ticket [18].)_

**Reçu d'audit**:
Le document par-itération (résumé + 4 verdicts de gate + preuves + méta + **diff par référence**) qui sert de **surface de relecture asynchrone** au propriétaire, sans flux PR obligatoire. Rendu par l'adaptateur de tracker : fichier `receipts/` en local, **la PR elle-même** en distant.
_À éviter_ : PR (c'en est une seulement en distant), log, journal (réservé au journal de run).

**ADR en delivery**:
Une décision d'architecture **interne non-triviale** prise par une session de delivery, gravée en ADR (`docs/adr/`) par le subagent retro et relue par les sessions futures via le contexte ambiant. Une décision **contractuelle** (touche une AC/dep) n'est pas un ADR autonome : elle **escalade**. Distinct d'un record de leçon (archi vs process).
_À éviter_ : décision (trop vague), record de leçon (autre canal).

### Les lentilles de revue

_(Ajouté par le durcissement v2, ticket [23] — généralise [08]/[14].)_

**Lentille de revue**:
Un regard de revue dans la **phase de jugement** du gate — un `claude` frais, sans conversation héritée, qui relit le diff d'une session avec un **jeu d'outils en lecture seule** — avec un **prédicat de déclenchement** (toujours-active ou gatée au risque). Standards & Spec sont toujours-actives ; Fidélité, Sécurité, Accessibilité sont gatées par les caractéristiques du ticket (tag, ou write-surface rencontrant `VISIBLE_PATHS` / `SECURITY_PATHS`). Le prédicat lit le ticket **restauré** du snapshot pré-session, sinon une session éteindrait ses propres reviewers en supprimant une ligne.
_À éviter_ : reviewer, axe (réservé à Standards/Spec), check (réservé aux branches objectives — une lentille juge, elle ne mesure pas).

**Registre de lentilles**:
Le jeu extensible des lentilles que le gate évalue par prédicat pour chaque ticket. Une lentille = un nom dans `LENSES` plus `lenses_want_<nom>` et `lenses_rubric_<nom>` ; le control-flow du gate n'en nomme aucune, il ne connaît que le registre. Un nom que rien ne sait exécuter est refusé au **préflight** et non silencieusement sauté : une faute de frappe ne doit pas ressembler à un reviewer qui a passé. Le détecteur [24] propose quand en ajouter.
_À éviter_ : liste de reviewers, config de gate.

**Phase de jugement**:
La seconde phase du gate : les lentilles déclenchées, en éventail, **après** que les branches objectives ont rendu leur verdict et jamais à côté d'elles. Deux raisons, toutes deux structurelles. Une lentille écrit dans l'arbre qu'elle juge, et ce n'est attribuable — donc défaisable — que si rien d'autre n'écrit dans la fenêtre ; et un gate déjà rouge ne changera pas d'avis, donc y dépenser une session serait dépenser du quota pour rien. Sautée n'est pas passée : rien n'entre dans les verdicts, et le run dit pourquoi. `GATE_TIMEOUT` est **par phase**.
_À éviter_ : second fan (le fan est le mécanisme, la phase est l'ordonnancement), post-gate.

**Verdict de lentille**:
La dernière ligne `RALPH-LENS-VERDICT: pass|fail` du flux d'une lentille, lue en **dernière occurrence** — un modèle cite l'instruction en route vers sa réponse, et le diff relu peut porter le jeton lui aussi. Tout le reste compte rouge : session morte, tuée pour contexte, dépassée par le chien de garde, ou qui répond de la prose. Le silence n'achète pas de vert ; un `pass` complaisant, en revanche, n'est distinguable de rien — c'est le prix du palier de jugement, écrit comme tel dans `docs/frontiere-de-confiance.md`.
_À éviter_ : note, score, approbation (une lentille ne signe rien).

**Confinement des écritures de lentille**:
Les trois mécanismes qui font qu'un `claude` tournant dans l'arbre du jugé n'y laisse rien : **empêcher** (la posture de spawn, voir ci-dessous), **mesurer** (l'arbre relevé avant et après la phase de jugement), **défaire** (`gate_restore_tree`, la primitive du rollback). Une seule des trois est une garantie que le pack vérifie lui-même : la mesure. Une écriture qui survit à la restauration rend l'itération rouge ; une écriture défaite ne lui coûte rien, parce que facturer un retry à une session pour ce que son juge a fait est l'erreur que [29] a trouvée un cran plus haut.
_À éviter_ : sandbox (réservé à l'exécution), read-only (nomme un seul des trois), nettoyage.

**Posture de lentille**:
Les flags avec lesquels une lentille est spawnée, et le pluriel est le fond de l'affaire : `--tools Read,Grep,Glob` ne porte que sur le **jeu built-in**, donc trois fichiers de l'arbre jugé passaient à côté — un `.mcp.json`, dont la commande du serveur est lancée et dont les outils atteignent le modèle ; les `settings*.json` du projet, dont un **hook est une commande** exécutée dans le process du juge au premier appel d'outil ; le `CLAUDE.md`, lu au démarrage. `--strict-mcp-config` et `--setting-sources user` referment les trois, et sont sondés contre le vrai binaire ([31], 30/07/2026). Ce qui décide de la forme du correctif : un flag tombe **avant** ce qu'il protège, là où le scellement ne rougit qu'à l'agrégation, c'est-à-dire après que la lentille a tourné. Ce qui reste ouvert et qu'aucun flag ne ferme : les rubriques envoient la lentille lire `CONTEXT.md`, `docs/adr/` et le code autour du diff avec ses propres `Read`/`Grep` — le texte que la session vient d'écrire atteint toujours son juge.
_À éviter_ : sandbox, isolation (la lentille tourne bien dans l'arbre du jugé), permissions (le mode est bypass, c'est le jeu d'outils et les sources qui sont restreints).

**Revue de capacités**:
Le pas — en sortie de charting (discovery, HITL) et au retro [11] (delivery, propose→escalade) — qui repère si une nouvelle lentille/agent/skill est nécessaire. **Détecter ≠ créer** : une capacité est contractuelle → toujours HITL. Barre : récurrence ou classe non couverte, **réutiliser-avant-créer**.
_À éviter_ : auto-extension (trompeur — ce n'est pas automatique), méta-agent.

### La boucle humaine

_(Ajouté par le durcissement v2, ticket [25].)_

**Boucle humaine (human-loop)**:
La 2ᵉ boucle bash, **HITL**, sœur de la ralph loop, qui **draine le puits `ready-for-human`** : pour chaque ticket bloqué, elle route vers le skill assistant (grilling / to-tickets / implement / to-spec / approbation, selon la raison d'escalade) et réinjecte le résultat en `ready-for-agent`. HITL = **jugement humain présent**, pas approbation de chaque écriture (permissions = défaut de session).
_À éviter_ : ralph loop (réservé à l'AFK), boucle de review.

**Raison d'escalade (`Escalation:`)**:
La ligne posée sur un ticket au moment de l'escalader (`decision` / `too-big` / `failed-impl` / `spec-gap` / `sign-off` / `session-timeout` / `nothing-delivered`), jeu fermé, qui permet à la boucle humaine de router le ticket vers le bon traitement. Les deux dernières sont arrivées avec le pack et disent la même chose sous deux formes : **rien n'a été jugé**, donc `failed-impl` enverrait lire un verdict qui n'existe pas — la session a été coupée par un délai ([23]), ou elle a répondu sans rien changer dans l'arbre ([35]).
_À éviter_ : cause, motif, label (réservé au triage).

### Les langues

_(Ajouté par le durcissement v2, ticket [26].)_

**Langue d'interaction (`LANG_INTERACT`)**:
La langue dont l'agent parle à l'humain (grilling, rapports, boucle humaine). Ne s'applique qu'aux échanges HITL ; une session AFK ne l'utilise pas.
_À éviter_ : langue par défaut, locale.

**Langue des artefacts (`LANG_ARTIFACT`)**:
La langue de toute prose durable que l'agent rédige dans le projet (docs, commentaires, PR). Découplée de `LANG_INTERACT`. Ne couvre ni le code/identifiants (Standards) ni les fichiers du pack. **Vérifiée par le gate de langue** ([17]) — pas seulement par consigne, et la consigne du prompt ne dit « c'est vérifié » que là où elle l'est.
_À éviter_ : langue du projet (ambigu), langue de doc.

**Gate de langue**:
La quatrième branche de la phase objective ([17]) : elle relit, dans l'arbre que le gate juge, les **fichiers de prose** que l'itération a écrits et vérifie qu'ils sont dans la langue attendue — `LANG_ARTIFACT` pour un fichier neuf, **la langue du fichier avant la session** pour une édition. Tolérant : ce qui est comparé au seuil est la *part* des mots reconnus qui appartiennent à la langue attendue, donc un terme étranger cité ou une ligne de commande ne coûte rien, et un fichier trop court pour trancher n'est pas jugé mais **compté** dans le journal. Échec → retry. Ce qu'il ne juge pas est dit à chaque itération plutôt qu'une fois ici : ce que l'exemption a retiré, et le fait qu'il soit éteint.
_À éviter_ : lint de langue (il ne parse rien), consigne (elle, est molle), lentille (un modèle n'est pas un check).
