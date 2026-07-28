# Frontière de confiance

Ce que la boucle **vérifie**, et ce qu'elle se contente de **demander**. Les deux ressemblent à des garanties quand on lit le prompt de session ; une seule en est une.

Ce document existe parce que quatre défauts livrés étaient la même erreur : une règle écrite dans le prompt, lue par tout le monde — moi compris — comme une contrainte, alors que rien ne la contrôlait. Un agent qui délivre un ticket de ce dépôt est censé le lire **avant** d'écrire, pas après.

Les `[NN]` renvoient aux tickets, sous [`.scratch/ralph-pack/issues/`](../.scratch/ralph-pack/issues/).

## L'état actuel

| Règle du prompt de session | Ce qui la tient réellement |
|---|---|
| Rester dans la write-surface déclarée | **Le scope-guard** (`gate__scope_guard`) — mais il lit la surface sur le disque *après* la session, donc une session qui réécrit son propre ticket l'élargit ([21]) |
| Ne pas changer le `Status:` du ticket | **Rien.** Un ticket *créé* par une session est mis en quarantaine ([07]) ; un ticket *modifié* ne l'est pas ([21]) |
| Ne jamais stager ni commiter le tracker | **Rien sur le chemin vert.** Sur un échec, le rollback remet `HEAD` ; sur un succès, le commit de la session reste, tracker à l'état `claimed` dans l'historique du projet cible ([21]) |
| Prose durable en `LANG_ARTIFACT` | **Rien** — le gate de langue arrive en [17] |
| Finir la tâche dans cette session | Invérifiable par nature ; borné par `ITER_CAP`, `STERILE_K` et le filet smart-zone |

Autres frontières, hors prompt :

| Attendu | Ce qui le tient |
|---|---|
| La suite de tests dit la vérité | **`TEST_CMD` non vide** (préflight). `TEST_CMD="true"` passe tous les contrôles du pack : seule la confirmation forcée de l'installeur [19] peut l'attraper |
| Une branche du gate finit | **`GATE_TIMEOUT`** ([07]) : l'arbre de processus est tué, « pas de verdict » compte rouge |
| Une session finit | **Le filet smart-zone** ([04]) borne le **contexte**, pas le **temps** : une session qui pend sans émettre de token n'est bornée par rien |
| Le travail d'une itération verte survit | **Le commit sur vert** ([07]), plus un rollback qui ne touche que le diff de la session |

## La règle, en une phrase

**Ajouter une règle au prompt de session sans ajouter une ligne à ce tableau, c'est livrer un faux vert en attente.** Si la ligne dit « Rien », le ticket doit dire pourquoi c'est acceptable pour l'instant, et lequel des tickets à venir la referme.

## Comment poser la question

À chaque ticket, avant d'écrire :

> Qu'est-ce qu'une session peut écrire que rien ne vérifie ?

Les quatre défauts trouvés à ce jour sont tous une réponse à cette question — trouvés trois fois par accident, dans trois déguisements différents. La poser une fois coûte une minute et les rend tous visibles d'un coup.

Deux corollaires utiles :

- **Un contrôle qui lit un fichier que la session peut écrire n'est pas un contrôle** — il faut lire l'état d'avant la session (snapshot), pas l'état d'après.
- **Un contrôle qui exclut une zone doit dire ce qui garde cette zone.** Le scope-guard et le rollback excluent tous deux `.scratch/<feature>/`, pour de bonnes raisons ; personne n'avait posé la question « alors qui garde le tracker ? ».
