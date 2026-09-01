# Sondes de [56]

Des **instruments**, pas des tests : chacune se termine par un `set -e; false`
volontaire, elle rougit toujours, et ce qu'on lit est ce qu'elle imprime avant.
Elles ne sont pas sous `test/` et `test/run.sh` sans argument ne les ramasse pas —
elles ne comptent dans le verdict d'aucun des deux gates.

    bash test/run.sh .scratch/ralph-pack/sondes/ticket-56/s1-le-correctif-que-le-drain-refuse-de-promettre.bats

Les sondes qui ont **motivé** [56] sont ailleurs : `../passe-31-08/p2-*.bats`.
Celles-ci rejouent la même chaîne de bout en bout **sur le code livré**, plus la
question 5 de CLAUDE.md posée après la réparation.

| Sonde | Ce qu'elle demande | Verdict, mesuré le 01/09/2026 sur le code livré de [56] |
|---|---|---|
| `S1` | l'état par défaut : la session routée écrit le correctif, personne ne commite, l'humain tape `r` | **refusé**, le ticket reste `ready-for-human` avec `Failures: 2` ; le run AFK qui suit sort `exit 5` (« rien à moudre »), **zéro session dépensée**. Avant [56] : 3 itérations `tests=red`, budget brûlé, retour en `Failures: 3` / `failed-impl` |
| `S2` | témoin appairé, dans le bon ordre : le correctif commité entre deux drainages | réinjecté sous la phrase « on this branch as it is committed », puis `tests=green` et **`resolved`** à la première itération |
| `S3` | question 5 : la session routée écrit le correctif **puis le reprend** | l'arbre est propre, donc `r` passe et le drain ne dit rien — le run AFK rend 3 rouges et `failed-impl`. **Trou résiduel, écrit au tableau** |

## Ce que `S3` dit, et ce qu'elle ne dit pas

Le refus compare l'arbre à `HEAD` **par git**, et la session routée peut écrire
les deux : elle peut donc rendre l'arbre propre sans que le correctif soit sur la
branche. Ce que ça coûte est le **rapport**, pas la **promesse** — ce qu'un
worktree neuf porte est `HEAD`, et personne n'a besoin de le dire au drain. Une
session qui commite son correctif satisfait le refus *en le rendant vrai* ; une
session qui l'efface laisse un drain qui ne promet rien de faux, seulement un
humain qui a vu une conversation produire un fichier et le reprendre.

Ce n'est donc pas un contrôle contre un adversaire, et le tableau le dit ainsi :
c'est un contrôle contre l'**état par défaut** — un correctif que personne n'a
commité.

## La sonde périmée d'à côté

`../passe-31-08/p2-*.bats` **P2b** posait « le même correctif, commité à la main
entre le drain et le run » — mais elle commitait *après* le `r`, ce que le refus
de [56] rend impossible : elle rend maintenant `exit 5` des deux côtés. La
question qu'elle posait est reprise ici par `S2`, dans le seul ordre qui
existe encore (commiter, puis drainer). Le piège de mémoire est exactement
celui-là : une sonde conservée peut poser une question périmée et répondre
« rien ».
