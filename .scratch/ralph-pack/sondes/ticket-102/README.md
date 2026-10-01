# Sondes de [102] (01/10/2026)

Des **instruments**, pas des tests : `h2` et `h4` finissent chaque cas par un
`set -e; false` volontaire, `h1` et `h3` sont des scripts bash nus, hors du harnais.
Aucun ne compte dans le verdict des deux gates.

    bash .scratch/ralph-pack/sondes/ticket-102/h1-les-verbes-du-pack.sh [none|params|count]
    bash test/run.sh .scratch/ralph-pack/sondes/ticket-102/h2-les-hooks-dun-vrai-run.bats
    bash .scratch/ralph-pack/sondes/ticket-102/h3-la-forme-du-jeton.sh
    bash test/run.sh .scratch/ralph-pack/sondes/ticket-102/h4-le-hook-configure.bats
    bash test/run.sh -f L3 .scratch/ralph-pack/sondes/ticket-98/f2-le-canal-herite.bats

## h1 — le recensement, verbe par verbe

Tous les noms de githooks(5) posés dans le répertoire commun **et** un hook
*configuré* par évènement (`hook.cfg-<ev>.command` / `.event`, git ≥ 2.5x). Chaque
verbe du pack (liste dérivée par le lexeur de [91] : 23 verbes sur 94 appels) lancé
dans la forme que le pack écrit, depuis un worktree lié ou depuis l'arbre principal.
Sur git 2.54 (Apple Git-157), sans rien :

    worktree add (pilote)            post-checkout, post-index-change, reference-transaction
    read-tree / update-index /
    write-tree / rm --cached /
    add (GIT_INDEX_FILE ou non)      post-index-change
    reset -- chemin                  post-index-change
    reset --mixed                    post-index-change, reference-transaction
    update-ref (même refusé)         reference-transaction
    push --force (forge)             pre-push, reference-transaction
    rev-parse, config, worktree list|remove|prune, ls-tree, ls-files, check-ignore,
    diff-tree, diff, cat-file, show-ref, for-each-ref, symbolic-ref, commit-tree,
    checkout-index, init --template=    rien

Avec `GIT_CONFIG_PARAMETERS` (`params`) ou `GIT_CONFIG_COUNT` (`count`) portant
`core.hooksPath=/dev/null` : **aucun hook du répertoire**, et **chaque hook
configuré tire toujours**, sur les mêmes évènements. Le binaire n'a aucune clé qui
éteigne tous les hooks configurés (lu dans `hook.c` de v2.54.0 : seulement
`hook.<nom>.enabled`, nom par nom).

## h2 — un vrai run, hooks posés avant

A1 (deux tickets) sur `main` : 2 `post-checkout`, 42 `post-index-change`, 46
`reference-transaction` pour le répertoire **et** autant pour les hooks configurés.
Sur la branche : **zéro** pour le répertoire ; les configurés (posés avant le run :
ceux de l'opérateur) tirent toujours, du même ordre (38 `post-index-change` au lieu
de 42 — un run n'est pas l'autre) — c'est la décision, pas un oubli. A2 (le drain, une
réinjection) : aucun hook, ni avant ni après — aucun verbe du drain qui lance n'a
été exercé, d'où l'enregistreur du test de `human-loop.bats` plutôt qu'un hook.

## h3 — la forme du jeton

`'core.hooksPath=/dev/null'` (forme ancienne, lue par tout git ; la forme
`'k'='v'` demande 2.31) éteint le répertoire ; gagne sur un `core.hooksPath` local
qu'une session écrit et sur un `include.path` qui en porte un ; compose avec une
valeur que l'opérateur avait exportée (ancienne ou nouvelle forme), qui reste lue ;
n'écrit rien sur stderr ; et passe au git que git lance (`worktree add`). Piège payé
en l'écrivant : `update-index --refresh` n'écrit l'index — donc ne lance
`post-index-change` — que si une date a bougé ; la première version mesurait une
fenêtre fermée. Chaque cas touche maintenant un fichier suivi d'abord.

## h4 — le hook configuré, que le jeton ne touche pas

    C1  .git/config, MAX_PARALLEL=1, deux tickets      aucune exécution pour le pack,
                                                       remis, nommé, itération rouge
    C2  .git/config, MAX_PARALLEL=2, au hasard          rien vu : la sœur avait déjà fini
    C2b .git/config, MAX_PARALLEL=2, la sœur tenue      14 lignes forgées dans le reçu
        dans son gate pendant la pose                  de la sœur, fd 5 et 9 ouverts
    C3  ~/.gitconfig, hook configuré, MAX_PARALLEL=1   ~170 exécutions, 24 lignes
                                                       forgées, run arrêté en 4
    C4  ~/.gitconfig, core.fsmonitor, MAX_PARALLEL=1   978 exécutions, 204 lignes
                                                       forgées, fds 3, 5, 6, 9

C1 est ce que [102] livre pour un hook configuré (la clé `hook.*` sur la liste de
[46], remise avant le premier git de l'itération qui écrive). C2b, C3 et C4 sont
**[104]**. C4 n'est pas un trou neuf : c'est le résidu de [46] (« une valeur qui
répond encore après l'unset »), mesuré pour la première fois avec ses descripteurs.

## Rejouées sur la branche de [102]

`f2` L3 (`../ticket-98/`) : **aucun hook lancé**, aucune ligne forgée — c'était sa
mesure. `h2` A1 : zéro exécution du répertoire. `h4` : inchangée, c'est [104].
