# Frontière de confiance

Ce que la boucle **vérifie**, et ce qu'elle se contente de **demander**. Les deux ressemblent à des garanties quand on lit le prompt de session ; une seule en est une.

Ce document existe parce que quatre défauts livrés étaient la même erreur : une règle écrite dans le prompt, lue par tout le monde — moi compris — comme une contrainte, alors que rien ne la contrôlait. Un agent qui délivre un ticket de ce dépôt est censé le lire **avant** d'écrire, pas après.

Les `[NN]` renvoient aux tickets, sous [`.scratch/ralph-pack/issues/`](../.scratch/ralph-pack/issues/).

## L'état actuel

| Règle du prompt de session | Ce qui la tient réellement |
|---|---|
| Rester dans la write-surface déclarée | **Le scope-guard** (`gate__scope_guard`), qui juge contre la surface du **spawn** : `failures_protect_tracker` restaure les tickets depuis un tree object de `issues/` pris avant la session, avant que le gate ne lise un seul champ ([21]) |
| Ne pas changer le `Status:` du ticket | **La restauration de `issues/`** ([21]) — sur son propre ticket comme sur celui d'un autre. Un ticket *créé* reste mis en quarantaine ([07]) : une création ne se décrée pas, un humain tranche |
| Ne jamais stager ni commiter le tracker | **Le désindexage de `issues/`** ([21]) sur les deux chemins, plus le retour de `HEAD` à l'état pré-spawn : sur un échec par le rollback ([07]), sur un succès par `failures_make_durable`, qui rebâtit le commit à partir des seuls chemins que le scope-guard a approuvés ([21]) |
| Prose durable en `LANG_ARTIFACT` | **Rien** — le gate de langue arrive en [17] |
| Finir la tâche dans cette session | Invérifiable par nature ; borné par `ITER_CAP`, `STERILE_K` et le filet smart-zone |

Autres frontières, hors prompt :

| Attendu | Ce qui le tient |
|---|---|
| La suite de tests dit la vérité | **`TEST_CMD` non vide** (préflight). `TEST_CMD="true"` passe tous les contrôles du pack : seule la confirmation forcée de l'installeur [19] peut l'attraper |
| Une branche du gate finit | **`GATE_TIMEOUT`** ([07]) : l'arbre de processus est tué, « pas de verdict » compte rouge |
| Une session finit | **Le filet smart-zone** ([04]) borne le **contexte**, pas le **temps** : une session qui pend sans émettre de token n'est bornée par rien |
| Un seul run touche l'arbre de travail | **Le verrou d'arbre** ([22]), dans le répertoire git. Un second run est refusé au démarrage *quelle que soit sa feature*, parce que le snapshot, le rollback, le commit sur vert et `HEAD` sont par dépôt. Il vit hors de l'arbre qu'il garde : ni `git add -A`, ni `git clean`, ni un `rm -rf .scratch` ne l'atteignent — contrairement au verrou de run, que [12] a montré supprimable par une session. Le verrou par feature reste, pour l'autre question : un run par tracker (spec §135). Une session peut encore le supprimer *délibérément* ; la boucle le revérifie à chaque itération et s'arrête, et le CAS du commit durable ([07]) couvre la fenêtre entre deux contrôles. `git rev-parse --git-dir` répond le répertoire privé d'un worktree lié, donc le verrou est déjà par *arbre* et non par dépôt : c'est par là que [13] rendra la concurrence possible |
| Un ticket réclamé par un run mort revient | **Rien.** Le *verrou* périmé est repris, le *claim* ne l'est pas, avec la même primitive — le ticket sort de la frontière et le run suivant sort en `exit 0` « frontière vide » ([12]) |
| Le travail d'une itération verte survit | **Le commit sur vert** ([07]), plus un rollback qui ne touche que le diff de la session |
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
