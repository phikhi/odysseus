# Frontière de confiance

Ce que la boucle **vérifie**, et ce qu'elle se contente de **demander**. Les deux ressemblent à des garanties quand on lit le prompt de session ; une seule en est une.

Ce document existe parce que quatre défauts livrés étaient la même erreur : une règle écrite dans le prompt, lue par tout le monde — moi compris — comme une contrainte, alors que rien ne la contrôlait. Un agent qui délivre un ticket de ce dépôt est censé le lire **avant** d'écrire, pas après.

Les `[NN]` renvoient aux tickets, sous [`.scratch/ralph-pack/issues/`](../.scratch/ralph-pack/issues/).

## L'état actuel

| Règle du prompt de session | Ce qui la tient réellement |
|---|---|
| Rester dans la write-surface déclarée | **Le scope-guard** (`gate__scope_guard`), qui juge contre la surface du **spawn** : `failures_protect_tracker` restaure les tickets depuis un tree object de `issues/` pris avant la session, avant que le gate ne lise un seul champ ([21]). **Mais seulement sur ce que git voit** : `gate_tree_snapshot` sans pathspec fait `git add -A` sans `--force`, donc tout chemin couvert par `.gitignore` est hors du snapshot, hors du scope-guard et hors du rollback. Sondé le 29/07/2026 : une session écrit un fichier ignoré hors surface, verdict `scope=green`, ticket `resolved`, fichier toujours là — et il survit aussi à un rollback. Propriétaire : [24] |
| Ne pas changer le `Status:` du ticket | **La restauration de `issues/`** ([21]) — sur son propre ticket comme sur celui d'un autre. Un ticket *créé* reste mis en quarantaine ([07]) : une création ne se décrée pas, un humain tranche |
| Ne jamais stager ni commiter le tracker | **Le désindexage de `issues/`** ([21]) sur les deux chemins, plus le retour de `HEAD` à l'état pré-spawn : sur un échec par le rollback ([07]), sur un succès par `failures_make_durable`, qui rebâtit le commit à partir des seuls chemins que le scope-guard a approuvés ([21]) |
| Prose durable en `LANG_ARTIFACT` | **Rien** — le gate de langue arrive en [17] |
| Finir la tâche dans cette session | Invérifiable par nature ; borné par `ITER_CAP`, `STERILE_K` et le filet smart-zone |

Autres frontières, hors prompt :

| Attendu | Ce qui le tient |
|---|---|
| La suite de tests dit la vérité | **`TEST_CMD` non vide** (préflight). `TEST_CMD="true"` passe tous les contrôles du pack : seule la confirmation forcée de l'installeur [19] peut l'attraper |
| Une branche du gate finit | **`GATE_TIMEOUT`** ([07]) : l'arbre de processus est tué, « pas de verdict » compte rouge |
| Une session finit | **Le filet smart-zone** ([04]) borne le **contexte**, pas le **temps** : une session qui pend sans émettre de token n'est bornée par **rien**, `monitor_watch` ne tiquant que sur ce que le flux écrit. Le pendant temporel arrive en [23], ouvert le 29/07/2026 après être resté 22 tickets sans propriétaire dans un commentaire de [04] — c'est le mode de panne le plus cher du pack : un run AFK qui ne broie rien et ne rend jamais la main |
| Un seul run touche l'arbre de travail | **Le verrou d'arbre** ([22]), dans le répertoire git. Un second run est refusé au démarrage *quelle que soit sa feature*, parce que le snapshot, le rollback, le commit sur vert et `HEAD` sont par dépôt. Il vit hors de l'arbre qu'il garde : ni `git add -A`, ni `git clean`, ni un `rm -rf .scratch` ne l'atteignent — contrairement au verrou de run, que [12] a montré supprimable par une session. Le verrou par feature reste, pour l'autre question : un run par tracker (spec §135). Une session peut encore le supprimer *délibérément* ; la boucle le revérifie à chaque itération et s'arrête, et le CAS du commit durable ([07]) couvre la fenêtre entre deux contrôles. `git rev-parse --git-dir` répond le répertoire privé d'un worktree lié, donc le verrou est déjà par *arbre* et non par dépôt : c'est par là que [13] rendra la concurrence possible |
| Le format du flux qu'une session émet | **Le test de contrat** ([20]), à deux vitesses. Sur le fake, à chaque `test/run.sh` : un shim qui s'écarte du format rougit tout de suite. Sur le **vrai** binaire, seulement quand un humain lance `RALPH_REAL_CLAUDE=1` — réseau et quota. Entre deux runs réels, donc, plus rien ne le tient : une release de Claude Code peut renommer `cache_read_input_tokens` et toute la suite reste verte, le moniteur se contentant de sous-compter la fenêtre des ~18K du prompt système, en silence. Limite assumée — l'alternative serait de dépenser du quota à chaque run |
| Une session ne bloque jamais sur une demande de permission | **`--dangerously-skip-permissions`**, et le contrat le vérifie contre le vrai binaire : `system/init` répond `permissionMode: bypassPermissions`. Avant [20] le seul témoin était un shim qui codait la réponse en dur, donc le pack aurait pu perdre le flag sans qu'un test bouge. Le fake dérive maintenant sa réponse de son argv, ce qui fait rougir le contrat si le spawn cesse de passer le flag |
| Un ticket réclamé par un run mort revient | **Le balayage de liveness** ([12]), en tête de chaque itération, avant la lecture de la frontière : pid absent ou claim plus vieux que `CLAIM_TTL` → le ticket retourne à la frontière, et le retour est journalisé dans `run.log`. Fail-open strict — un claim que rien ne prouve vivant est réclamable — parce que le coût de l'erreur inverse est borné (le claim reste un test-and-set) et que celui du deadlock ne l'est pas. Ce que ça **ne** tient pas : la liveness est mono-machine (un pid ne veut rien dire sur un autre hôte), et ce que la session tuée avait écrit dans l'arbre y reste — le pack ne peut pas la distinguer du travail non commité d'un humain, donc il n'y touche pas |
| Le travail d'une itération verte survit | **Le commit sur vert** ([07]), plus un rollback qui ne touche que le diff de la session |
| Une itération en cours finit quand un humain arrête le run | **Le trap `loop_request_stop`** ([03]), et **une collecte qui survit au signal** (`gate__collect`, [25]). Bash court-circuite `wait` dès qu'un signal piégé arrive : le gate lisait alors des verdicts que ses branches n'avaient pas encore écrits, et « pas de verdict » compte rouge — `Failures:` non mérité, travail rollbacké pendant que sa propre suite de tests tournait, branche orpheline survivant au run. Le gate re-attend maintenant chaque branche tant qu'elle répond, et reste borné par `GATE_TIMEOUT` : le stop n'a pas de délai à lui, et n'est donc plus une sortie de secours hors d'une branche qui pend. **Une fenêtre reste ouverte, en dehors du gate** : `session_spawn` attend `claude` avec le même `wait` nu, et sur le chemin soft-limit `monitor_watch` rend la main dès son TERM envoyé, sans attendre l'extinction. Sondé le 29/07/2026, avec témoin dans les deux sens : un TERM reçu pendant cette extinction fait sortir le run en laissant un `claude` vivant, qui brûle du quota et écrit dans un flux que la boucle vient de supprimer. Propriétaire : [28] |
| `Failures:` est le budget de retries du ticket depuis sa dernière livraison | **Le zéro sur `resolved`** ([26]) : `tracker_mark_resolved` lâche le champ avec le claim, donc le compteur n'est plus cumulatif sur toute la vie du ticket — c'est `resolved` et rien d'autre, le remettre à zéro sur `unclaim` rouvrirait le re-broyage infini que `RETRY_N` existe pour borner. Contre une session qui le baisserait elle-même, c'est **la restauration de `issues/`** ([21]) qui tient : le bump lit la valeur d'après le snapshot pré-session, jamais celle que la session a laissée. Ce que ça ne dit pas : **deux causes pour un champ**, une tentative jugée rouge et un claim réclamé d'un run mort. Le distinguo est dans `run.log` (une ligne `reclaimed-*` contre un verdict de gate) et dans la raison d'escalade — `failed-impl` seulement là où une session a été jugée, `decision` quand le plafond tombe sur un reclaim, avec la note qui dit qu'il n'y a pas de branche `failed/<ticket>` à lire. **Ce qui reste** : `tracker_mark_ready` ne remet rien à zéro, donc un ticket réinjecté est escaladé à sa première tentative — [16] pour le puits humain, [11] pour le câblage, chacun devant le dire dans son ticket |
| Un claim qu'un run du pack n'a pas relâché coûte un retry, celui d'un humain non | **`claim_owner_kind`** ([26]), une seule fonction pour la forme `owner=pid:<n>` : un claim que le pack peut rattacher à un de ses propres runs est facturé (c'est un crash que personne n'était vivant pour classer), tout le reste — un assignee, un humain, un record illisible — est rendu à la frontière sans rien consommer. Le vol lui-même reste : le fail-open de [12] prend le ticket dès que `CLAIM_TTL` tombe, y compris celui d'un humain, et c'est assumé. Ce qui change, c'est le prix — et la note posée sur le ticket, seule copie restante du claim une fois le champ lâché |
| Un ticket est identifiable par son `NN` | **Le refus d'un id ambigu** (`tracker_local__path`) — qui protège contre le mauvais choix, pas contre l'état lui-même. Une session qui **renomme** un fichier de ticket produit un `D` + un `A` : [21] restaure le premier et laisse le second en quarantaine, deux décisions correctes dont la composition laisse deux fois le même `NN`. Tout ticket portant `Blocked by: NN` quitte alors la frontière définitivement, et rien ne sort le tracker de cet état. Propriétaire : [27] |
| Ce qu'une session écrit **hors du dépôt** — `$HOME`, `/tmp`, un autre dépôt de la machine | **Rien, et rien ne le fera ici.** Le scope-guard diffe des trees git ; ce qui est hors de l'arbre lui est structurellement invisible. `--dangerously-skip-permissions` est assumé au niveau du pack ([20]), donc le rempart est l'isolation de l'hôte, pas la boucle. Limite assumée, pas un trou à combler — et la raison pour laquelle un run AFK n'a rien à faire sur une machine qui porte autre chose de précieux |
| Le reste de `.scratch/<feature>/` — `run.log`, `.run.lock/`, les flux `.session.*.jsonl` | **Rien** — et c'est pour cela que le verrou d'arbre de [22] n'y vit pas. La protection de [21] s'arrête à `issues/`, et il le faut : le flux de session s'écrit *pendant* la fenêtre surveillée, donc tout `.scratch/` aurait un delta légitime à chaque itération. Une session peut donc réécrire le journal — que [10] va lire — et faire partir des Mo de flux dans l'index du projet cible. Propriétaires : [19] pour le `.gitignore` qui empêche le `git add -A`, [10] pour un journal qu'on peut croire, [12]/[13] pour le lock |

## La règle, en une phrase

**Ajouter une règle au prompt de session sans ajouter une ligne à ce tableau, c'est livrer un faux vert en attente.** Si la ligne dit « Rien », le ticket doit dire pourquoi c'est acceptable pour l'instant, et lequel des tickets à venir la referme.

## Comment poser la question

À chaque ticket, avant d'écrire :

> Qu'est-ce qu'une session peut écrire que rien ne vérifie ?

Les quatre défauts trouvés à ce jour sont tous une réponse à cette question — trouvés trois fois par accident, dans trois déguisements différents. La poser une fois coûte une minute et les rend tous visibles d'un coup.

Deux corollaires utiles :

- **Un contrôle qui lit un fichier que la session peut écrire n'est pas un contrôle** — il faut lire l'état d'avant la session (snapshot), pas l'état d'après.
- **Un contrôle qui exclut une zone doit dire ce qui garde cette zone.** Le scope-guard et le rollback excluent tous deux `.scratch/<feature>/`, pour de bonnes raisons ; personne n'avait posé la question « alors qui garde le tracker ? ».

Un troisième, trouvé en livrant [21] :

- **Un contrôle qui restaure doit dire ce qu'il ne restaure *pas*, et pourquoi.** La protection du tracker remet les tickets *modifiés* et laisse les tickets *créés* : les rendre tous au snapshot aurait effacé la seule copie de ce qu'un ticket créé demandait. Deux contrôles sur la même zone doivent s'accorder explicitement, sinon le second défait le premier en silence.

Deux de plus, trouvés par la passe transversale du 29/07/2026 :

- **Un contrôle qui lit un diff git ne voit pas ce que git ignore.** Le scope-guard et le rollback sont tous deux construits sur `gate_tree_snapshot`, donc tous deux aveugles au même ensemble de chemins — et cet ensemble est choisi par le **projet cible**, pas par le pack. Un contrôle qui délègue sa visibilité à un fichier que le projet écrit doit dire jusqu'où il voit.
- **Une promesse vérifiée sur un fake qui finit vite n'est vérifiée que là.** L'arrêt gracieux a un test, il n'est pas vacuous, une mutation le fait rougir — et il envoie son signal dans la seule fenêtre où le code est correct. La question à poser en écrivant le test n'est pas « est-ce que la garantie est couverte » mais « **dans quelle fenêtre** est-ce que je la couvre, et laquelle est la plus longue en vrai ».

Un de plus, trouvé en livrant [26] :

- **Un champ dont le nom porte une promesse doit dire qui la tient, et qui l'efface.** `Failures:` annonçait « des échecs d'implémentation » : il comptait aussi des claims réclamés que personne n'avait jugés, et aucun chemin ne le remettait à zéro. Le nom a été lu comme une garantie par l'escalade, par le routage prévu de la boucle humaine et par moi — exactement la même erreur qu'une règle du prompt lue comme une contrainte, un cran plus bas. Deux questions, pas une, en ajoutant un état durable au tracker : qui l'écrit, et **qui l'efface, quand**. Un compteur qu'aucun chemin ne remet à zéro n'est pas un budget, c'est un cumul — et ça ne se voit dans aucun test qui regarde une seule itération.

Un de plus, trouvé en livrant [25] :

- **Une primitive de la boucle est un défaut répété autant de fois qu'elle est appelée.** Le trou du gate était un `wait` nu ; la même ligne existait dans `session_spawn`, écrite séparément, avec la même faille et sur une fenêtre plus longue en run réel. `grep` sur la primitive après avoir réparé un appelant coûte dix secondes et a livré la cinquième trouvaille de la journée — la question à poser n'est pas « est-ce que je l'ai réparé ici » mais « **combien d'endroits appellent ça** ».
