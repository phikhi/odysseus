# Sondes de la livraison de [112], 29/10/2026

Des **instruments**, pas des tests : chaque cas finit par un `false` volontaire.
Hors de `test/`, jamais compté par les deux gates.

    bash test/run.sh .scratch/ralph-pack/sondes/ticket-112/<sonde>.bats </dev/null

Le survivant est celui du harnais, `script_index_survivor` (`test/helpers/harness.bash`) :
planté par la première livraison, ignore `TERM`, **ajoute tant que sa marque manque**,
une fois aux noms que l'index traversait (`index`, `index.next`, `work`, `prom`,
`promoting`, `read.*/`), une fois — **dérivé** — dans tout fichier de `$TMPDIR` qui
porte le gist de la leçon du run. Il exclut le prompt du rétro, que [111] rendra sans nom.

## s1 — le relevé dérivé, et l'exclusion

| Cas | Sur `main` (`c87726c`, worktree) | Sur la branche de [112] |
|---|---|---|
| **S1** la moitié dérivée seule (boucle des noms retirée du script) | le relevé trouve `ralph-retro.*/index` (60 ajouts) ; marques aux appels 4 et 5 (livraison 2, rétro 2) et dans `LEARNINGS.md` | relevé **vide** ; aucune marque nulle part ; le gist n'est que dans les stdin de la livraison 2 et du rétro 2 |
| **S2** le survivant entier **sans** l'exclusion des prompts de session | — | le relevé trouve `ralph-retro.*/session.*/prompt` (le prompt du rétro 2) ; marque à l'appel 5 (`You are the retro subagent…`) ; `LEARNINGS.md` propre (le faux répond ce qu'on lui a scripté) |

S2 est ce que [111] hérite : l'exclusion est porteuse, et la lever n'est verte qu'une
fois le prompt du rétro sans nom.

Mesuré aussi sur `main`, avec les deux tests livrés recopiés dans le worktree
(`test/probe112.bats`, non gardé) : le test du survivant rougit sur les appels 4 et 5 ;
le test `heredoc_spy` rougit sur un `LEARNINGS.md` dont la tête est en `x`.

## Ce que ces mesures ne disent pas

Ce qu'un vrai modèle fait d'une entrée forgée. Pour `LEARNINGS.md` et le run suivant,
il n'y avait pas de modèle dans la chaîne ; il n'y en a toujours pas, et il n'y a plus
de fichier.
