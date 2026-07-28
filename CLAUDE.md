Only respond to user in french.

## Langues

Le **pack** (`.claude/**`, `test/**` : code, commentaires, noms de tests, messages CLI) s'écrit **en anglais** — il est déposé dans des projets de n'importe quelle langue. Les **artefacts du dépôt** (`CONTEXT.md`, `.scratch/**`, `docs/adr/`, messages de commit) restent **en français**. En éditant un fichier existant, matcher sa langue.

## Definition of done d'un ticket

Un ticket n'est pas livré parce que la suite est verte. Treize tests de ce dépôt sont passés au vert alors que la propriété qu'ils prétendaient couvrir avait été supprimée — les deux derniers dans le canari lui-même, deux `refute_output_contains` qui visaient la sortie du `run` précédent. Avant d'annoncer vert :

1. **Muter chaque garantie livrée.** Ajouter une entrée dans `test/mutate.sh` (garantie → édition qui la supprime → test qui doit rougir) et lancer `bash test/mutate.sh`. `VACUOUS` = le test est un mensonge, le réécrire. `DRIFTED` = la ligne porteuse a bougé, revérifier que la garantie est encore portée. Une garantie qu'aucun test ne remarque n'est pas couverte — c'est la trouvaille, pas un détail.
2. **Ne jamais asserter un succès seul.** `assert_success` sur un run ne prouve rien : asserter ce qui a changé (tickets résolus, fichiers écrits, lignes de journal). Deux bugs ont vécu derrière un `exit 0`.
3. **Sonder le run réel avant de dire vert.** Les fakes de la suite écrivent peu, ne commitent pas et finissent vite ; presque tous les défauts livrés vivaient dans cet écart. Demander : que se passe-t-il si la session écrit vraiment, commit, émet 20 Mo, arrive en deux morceaux ? Si la réponse n'est pas testée, la tester.
4. **Poser la question transversale.** *Qu'hérite le ticket suivant de ce que celui-ci laisse dans le dépôt ?* Le pire bug du projet n'était faux dans aucun ticket pris isolément.
5. **Poser la question de la frontière de confiance, _avant_ d'écrire.** *Qu'est-ce qu'une session peut écrire que rien ne vérifie ?* Les quatre pires défauts du projet sont la même erreur : une règle du prompt de session lue comme une contrainte alors que rien ne la contrôlait. Une garantie qui repose sur une consigne au modèle n'est pas une garantie — elle va dans le tableau de `docs/frontiere-de-confiance.md`, avec ce qui la tient vraiment ou l'aveu que rien ne la tient. Deux corollaires : un contrôle qui lit un fichier que la session peut écrire n'est pas un contrôle, et un contrôle qui exclut une zone doit dire qui garde cette zone.
6. **Respecter les couches.** `loop.sh` au-dessus, `lib/*.sh` en dessous, chaque module propriétaire de son préfixe `<module>_` et de ses internes `<module>__`. Un lib qui appelle un `__` voisin ou qui remonte dans `loop.sh` transforme la pile en maillage ; `test/layering.bats` le refuse. Un second appelant sur une fonction `__` veut dire qu'elle est publique : la renommer, pas l'appeler quand même.
7. **`bash test/run.sh` et `bash test/mutate.sh` verts**, canari (`test/canary.bats`) compris. Un `skip` dans le canari est une faille connue qui attend son ticket : la lever fait partie des AC de ce ticket-là.
8. **Consigner dans le ticket** ce que le code ne dit pas : écarts de write-surface, décisions, pièges, ce qui reste à faire ailleurs. Et **écrire les contraintes créées dans les tickets concernés**, pas seulement dans le sien — personne ne relit les commentaires d'un ticket clos au bon moment.
9. **Une branche par ticket**, commit en français, `merge --no-ff` sur `main`, push.

Tous les 4 ou 5 tickets, faire une **passe transversale** : rejouer les sondes « run réel » sur les tickets déjà livrés, avec les questions 4 et 5 en tête. C'est ce qui attrape ce qu'une review par ticket ne peut pas voir.

### Ce qui est vérifié et ce qui est seulement demandé

`docs/frontiere-de-confiance.md` tient le tableau : pour chaque règle posée à une session, ce qui la tient réellement. **Ajouter une règle au prompt sans ajouter sa ligne au tableau, c'est livrer un faux vert en attente.**

## Agent skills

### Issue tracker

Issues et specs suivis en markdown local sous `.scratch/<feature>/` (ex. `.scratch/dev-framework/`). See `docs/agents/issue-tracker.md`.

### Triage labels

Libellés canoniques par défaut : needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix. See `docs/agents/triage-labels.md`.

### Domain docs

Contexte unique — `CONTEXT.md` + `docs/adr/` à la racine. See `docs/agents/domain.md`.
