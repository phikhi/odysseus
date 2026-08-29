# Sondes de [46] — la configuration git décide aussi de ce que git exécute

Des **instruments**, pas des tests, comme ceux de `../passe-26-08/` : chacun finit
par un `false` volontaire, il rougit toujours, et ce qu'on lit est ce qu'il imprime
avant. Ils ne sont pas dans `test/` et `test/run.sh` sans argument ne les ramasse
pas — ils ne doivent jamais compter dans le verdict des deux gates.

Les faire tourner, une par une :

    bash test/run.sh .scratch/ralph-pack/sondes/ticket-46/q2.bats -f Q3

Ils pilotent le pack tel qu'il est livré ; aucun n'édite `.claude/` ni `test/`.

| Sonde | Ce qu'elle demande | Verdict après [46] |
|---|---|---|
| `q1` | le témoin de [15] sur l'itération où le run s'arrête | une ligne `capability-drift` dans `run.log`, la surface en sujet, et toujours aucun reçu (c'est [10]) |
| `q2` Q2 | `core.fsmonitor` dans `<arbre principal>/.git/config` | `scope=red`, nommé, clé retirée ; **12 exécutions au lieu de 252** — la fenêtre qui reste est celle de la session elle-même |
| `q2` Q3 | le même dans `~/.gitconfig` | `scope=red`, nommé « could not put it back », et le fichier de l'opérateur n'est pas touché |
| `q2` Q4 | un `filter.<n>.smudge` armé par `.git/info/attributes` | rouge sur l'itération qui l'installe, et la session suivante reçoit le `CONTEXT.md` d'origine |
| `q2` Q5 | le même filtre et le garde du tracker, qui lit et écrit `issues/` à travers git avant les trois sites de [32] | les tickets sur le disque ne portent pas le marqueur : la remise est avancée avant ce garde |

Ce que Q3 a trouvé **avant** correction, et qui a déplacé une invariante de [41] :
le constat apparaissait **deux fois**, parce qu'un mouvement qu'aucune remise ne
peut défaire est redétecté à chaque regard et que [46] ajoute un quatrième
appelant. La règle « une seule fois par itération » vit maintenant dans le
registre (`gate__frontier_record`) et non plus dans la discipline des sites
d'appel.

Les sondes de la passe qui a ouvert ce ticket sont dans `../passe-26-08/` ; elles
ont toutes été rejouées le 29/08/2026 avant que la première ligne de code ne soit
écrite. Une seule ne reproduit pas et c'est un défaut de la sonde : **`p2` P2a
écrit `fsmonitor = …` sans en-tête de section**, donc la clé n'est pas
`core.fsmonitor` — c'est `p3` P3a qui porte cette trouvaille.
