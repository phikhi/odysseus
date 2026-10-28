# Sondes de la livraison de [97], 28/10/2026

Des **instruments**, pas des tests. Chaque cas finit par un `set -e; false`
volontaire : il rougit toujours, et ce qu'on lit est ce qu'il imprime avant.
Hors de `test/`, jamais compté par les deux gates.

    bash test/run.sh .scratch/ralph-pack/sondes/ticket-97/q1-lentree-des-juges.bats </dev/null

## `q1-lentree-des-juges.bats` → ouvre [111]

[97] ferme le **flux** d'une session : ce qu'un juge écrit est ce que le pack lit.
Cette sonde mesure l'autre bout — ce que le juge **lit**. Le prompt d'une lentille
est sans nom depuis [94] ; ceux du rétro et du gate de valeur sont des fichiers
nommés (`ralph-retro.*/session.*/prompt`, `ralph-playthrough.*/prompt`), et le
gate de valeur cite dans le sien deux transcriptions nommées (`run.out`,
`visual.out`).

Le faux `claude` ne suit aucune instruction : ce qui se mesure est ce qu'il a
**reçu** sur stdin (`claude.calls/<n>/stdin`).

| | Mesuré sur la branche de [97] |
|---|---|
| Premier essai — le survivant ajoute une ligne marquée **une fois** par fichier | il atteint les quatre fichiers ; **aucun** juge ne reçoit la marque — le pack écrit ces fichiers par `>`, et l'ajout fait avant la fin de son écriture est écrasé |
| Second essai — il ajoute **tant que la marque manque** | le prompt du rétro (appel 3, `RALPH-RETRO-NOTHING`) et celui du gate de valeur (appel 4, `RALPH-PLAYTHROUGH-STEP`) **portent la ligne du survivant** ; `run.out` et `visual.out` vides dans ce montage (`stub-cmd`), donc pas atteints par `[ -s ]` — à mesurer avec une commande de projet qui écrit |

Le run sort `0` : la ligne n'a rien changé au verdict **du faux**. Ce qu'un vrai
modèle fait d'une question posée par un tiers est l'objet de [111], pas de cette
mesure.
