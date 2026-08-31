# Sondes de [55]

Des **instruments**, pas des tests : chacune se termine par un `set -e; false`
volontaire, elle rougit toujours, et ce qu'on lit est ce qu'elle imprime avant.
Elles ne sont pas sous `test/` et `test/run.sh` sans argument ne les ramasse pas —
elles ne comptent dans le verdict d'aucun des deux gates.

    bash test/run.sh .scratch/ralph-pack/sondes/ticket-55/s1-le-ticket-voisin-que-la-session-resout.bats

Les sondes qui ont **motivé** [55] sont ailleurs : `../passe-31-08/p1-*.bats`
(P1a à P1d). Celle-ci est la question que [55] a posée *après* sa réparation,
c'est-à-dire la question 5 de CLAUDE.md rejouée sur le code livré : *qu'est-ce
qu'une session routée peut encore écrire que rien ne vérifie ?*

Le pin de [55] rend aux deux refus une entrée que la session ne peut pas
fabriquer **sur le ticket que le drain tient**. Il ne dit rien de ce qu'elle
écrit sur un autre ticket, ni de ce qu'elle écrit dans un champ qu'aucune
transition ne lit.

| Sonde | Ce qu'elle demande | Verdict, mesuré le 31/08/2026 sur le code livré de [55] |
|---|---|---|
| `S1` | une session routée sur `20-first` écrit `Status: resolved` sur `21-second`, le ticket suivant du puits | `21-second` sort **`resolved`**, le drain le **saute en silence** — `grep -c '21-second'` sur toute la sortie du drain rend **0**, aucun dossier, aucune ligne de journal |
| `S1b` | témoin appairé : même drain, mêmes touches, session qui n'écrit rien | `21-second` est offert, `ready-for-human` — la fenêtre est bien celle qu'on croit |
| `S1c` | et ce qu'un run AFK en fait ensuite | `exit 5` : « rien à moudre ». Le ticket a quitté le puits **et** la frontière, sans qu'aucun gate n'ait rien lu |

Ce que ça dit, et qui n'est pas un défaut de [55] : le chemin fermé par le pin
est celui des **transitions**. `Status: resolved` écrit à la main sur un fichier
de `issues/` n'en est pas une, et la ligne « rien ne sort du puits humain en
`resolved` sans être repassé par le gate » a donc un second chemin, indépendant
des deux refus. Propriétaire : **[58]**. Le point de convergence est
l'instantané autour de `human_loop__session`, que [56] posera.
