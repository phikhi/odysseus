# Sondes de [50] — un chemin gardé qu'un projet ignore

Deux fichiers, trois questions, toutes posées **avant** d'écrire une ligne de
correctif — c'est ce que le ticket demandait, et le cas par défaut s'est révélé pire
que ce que le ticket décrivait.

Elles ne sont pas dans `test/` et `test/run.sh` sans argument ne les ramasse pas ; il
faut les nommer :

    bash test/run.sh .scratch/ralph-pack/sondes/ticket-50/p1-le-cas-par-defaut-du-pack-sur-lui-meme.bats
    bash test/run.sh -f "P2 " .scratch/ralph-pack/sondes/ticket-50/p2-le-rafraichissement-supprime-ce-quil-na-pas-commite.bats

Chaque fichier finit par un test qui fait `false` : une sonde qui rendrait « tout vert »
sans que ce sentinelle rougisse n'a pas tourné.

## P1 — le pack ne pouvait pas se livrer à lui-même

`p1-le-cas-par-defaut-du-pack-sur-lui-meme.bats`

- **P1a** — un projet qui ignore `.claude/` (la convention de tout projet Claude Code)
  avec le `GUARDED_PATHS` par défaut, un ticket dont la surface est
  `.claude/lib/thing.sh`. Avant [50] : `resolved`, **aucune** ligne `committed`,
  **aucun** fold, rien dans l'historique — le seul chemin changé étant refusé, l'arbre
  reconstruit égalait celui de `HEAD` et le retour anticipé tirait.
- **P1b** — la famille de [30] : la session écrit `build/out.txt` puis ajoute `build/`
  au `.gitignore`, les deux dans sa surface. Avant [50] : vert, règle commitée, fichier
  absent. Un faux livré en deux lignes, à la portée de n'importe quelle session.

Les deux passent depuis le `git add -A --force` de `failures_make_durable`.

## P2 — l'arbre principal perdait ce que le run venait de dire irrecevable

`p2-le-rafraichissement-supprime-ce-quil-na-pas-commite.bats`

`concurrency__refresh` ne posait qu'une question — ce chemin est-il dans `HEAD` — et
lisait « non » comme « l'itération l'a supprimé ». Avant [50] : le
`.claude/cache/keep.txt` de l'arbre principal est supprimé et `rmdir -p` emporte
`.claude/cache/` avec lui.

**Attention en la rejouant : cette sonde a cessé d'être une sonde.** Depuis le forçage,
`.claude/cache/keep.txt` est **commité**, donc `checkout-index` l'écrit et l'assertion
passe sans que le garde de `concurrency__refresh` y soit pour quoi que ce soit. Elle
reste ici parce qu'elle documente le défaut d'origine ; le test qui **tient** la
garantie est au module, `test/concurrency.bats`, « it does not delete a path the fold
never put on the branch », et il couvre les trois réponses de la partition.
