# 34 — Un refus de snapshot lu comme « rien à faire »

**What to build:** Faire dire à chaque appelant de `gate_tree_snapshot` la différence entre « rien n'a changé » et « je n'ai pas pu regarder ». [30] a rendu le snapshot faillible à dessein — un témoin d'ignore illisible fait refuser l'arbre, parce qu'un garde qui ne voit pas ne doit pas passer. Deux appelants avalent ce refus : `gate_unjudged_changes` rend une liste vide, donc `gate__contain_lens_writes` conclut « aucune écriture de lentille à défaire » et **passe au vert sans avoir mesuré** — c'est-à-dire que la seule des trois moitiés de [06] qui soit une garantie échoue ouverte. Et `failures_handle`/`failures_rollback` disent honnêtement qu'ils n'ont rien pu défaire, sans que rien n'empêche l'itération **suivante** de prendre cet arbre comme `base` : le fail-closed est un blanchiment en deux coups.

**Blocked by:** None

**Write-surface:** `.claude/lib/gate.sh`, `.claude/lib/failures.sh`, `.claude/loop.sh`, `test/gate.bats`, `test/lenses.bats`, `test/failures.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

- [ ] Le confinement des écritures d'une lentille échoue **fermé** des deux côtés : il refuse déjà de passer quand l'arbre d'avant est illisible, il doit refuser aussi quand l'arbre d'après l'est. Aujourd'hui la première garde existe et la seconde manque, à une ligne près.
- [ ] Aucun appelant de `gate_tree_snapshot` ne traite plus un refus comme un vide sans le dire. Les appelants sont énumérés dans le ticket au moment de le livrer, et chacun reçoit son traitement explicite — le `|| return 0` de `gate_unjudged_changes` est le cas qui a produit un faux vert, pas le seul cas.
- [ ] Une itération dont le rollback n'a rien pu défaire ne laisse pas l'itération suivante prendre son arbre pour un état d'avant : soit la boucle refuse de continuer, soit ce qu'elle laisse est nommé au tour suivant. Le choix est tranché dans le ticket, avec son coût — refuser de continuer transforme une session hostile en arrêt du run, ce qui est aussi ce qu'un `exit 4` fait déjà pour un témoin manquant.
- [ ] Les deux tests portent leur témoin appairé (le même scénario sans destruction du témoin doit annoncer l'écriture et la remettre), et la mutation vise la garde neuve et non le message.
- [ ] La ligne « Ce qu'une lentille de revue écrit dans l'arbre qu'elle juge » de `docs/frontiere-de-confiance.md` dit ce qui arrive à la mesure quand elle ne peut pas être prise, et la ligne « La frontière de visibilité » cesse de laisser croire qu'un témoin détruit ne coûte qu'une itération.

## Comments

- **Origine : passe transversale du 03/08/2026** (fenêtre [06], [23], [28], [29], [30], [31]), questions 4 et 5 posées ensemble sur ce que [30] appelle son fail-closed.

  *Sonde A — une lentille qui ferme la mesure de ses propres écritures.* `LENSES=standards`, session de livraison honnête. La lentille écrit `lens-artifact.txt` dans l'arbre qu'elle juge, détruit le témoin d'ignore (`rm -rf $TMPDIR/ralph-ignore.*`), et répond `pass`.

  ```
  ralph: gate: the pinned ignore rules cannot be read — refusing to snapshot …
  ralph: gate: 01-alpha: tests=green typecheck=green scope=green standards=green
  ralph: gate: the pinned ignore rules cannot be read — refusing to snapshot …
  ralph: 01-alpha: committed 1 path(s)
  ralph: iteration 1: 01-alpha -> resolved

  lens-artifact.txt: survives    lignes de containment: 0    refus de passer: 0
  ```

  *Témoin — la même lentille qui écrit sans détruire le témoin :*

  ```
  ralph: gate: 01-alpha: a review lens changed 1 path(s) in the tree it was
    judging: lens-artifact.txt — putting them back
  lens-artifact.txt: gone
  ```

  Le mécanisme de [06] fonctionne, et il suffit de fermer sa mesure pour qu'il annonce zéro écriture au lieu d'annoncer qu'il n'a pas pu compter. Le diagnostic sort bien sur stderr — [30] l'y a mis exprès — mais personne en aval ne le lit : `gate_unjudged_changes` fait `now="$(gate_tree_snapshot)" || return 0`, et `gate__contain_lens_writes` teste `[ -n "$changed" ] || return 0`.

  *Sonde B — le blanchiment que le fail-closed n'empêche pas.* Session 1 : écrit sa surface **et** `lib/rogue.sh` hors surface, détruit le témoin, finit proprement. Session 2 (retry du même ticket) : n'écrit que sa surface.

  ```
  ralph: gate: the pinned ignore rules cannot be read — refusing to snapshot …
  ralph: gate: scope red (exit 1)
    the scope-guard could not read the working tree — refusing to pass it
  ralph: cannot read the working tree — nothing was rolled back
  ralph: 01-alpha: gate-red -> fresh retry (1 of 2)
  ralph: iteration 2: 01-alpha -> resolved

  lib/rogue.sh: survives     scope complaints: 0
  git status: ?? lib/  ?? src/
  ```

  Tout le fail-closed a fonctionné : le snapshot refuse, le scope-guard refuse, le rollback dit qu'il n'a rien défait. Et l'itération 2 prend cet arbre comme `base`, donc `lib/rogue.sh` n'est plus un changement de personne : `resolved`. Le prix pour la session est un retry. [30] a écrit le premier tour comme un prix assumé (« l'itération est rouge avec ses écritures encore en place ») ; ce que la question 4 ajoute est le second tour, où le prix devient un gain.

  *Témoin — la même sonde sans destruction du témoin :* `lib/rogue.sh` est nommé par le scope-guard, rollbacké, et l'itération 2 repart d'un arbre propre.

- **Un effet de bord constaté au passage, qui n'est pas dans le champ de ce ticket mais dont il est le premier chemin d'accès.** Dans la sonde B, l'itération 2 est `resolved` **sans commiter quoi que ce soit** : `failures_make_durable` commite le diff `base..arbre jugé`, et `src/alpha.txt` était déjà dans le `base` puisque rien ne l'avait défait. Un ticket livré, une ligne `resolved` dans `run.log`, zéro commit, et le travail qui traîne en `??` pour l'itération suivante. C'est le même angle mort que [35] attaque par l'autre bout (un diff vide n'a rien livré) : à citer là-bas, pas à réparer ici.

- **Ce que la sonde A dit du modèle de menace, et il faut le dire sans le surestimer.** Une lentille est spawnée avec la posture de [31] (`--tools Read,Grep,Glob`, `--strict-mcp-config`, `--setting-sources user`), donc elle n'a pas de `Bash` et ne peut pas, par le jeu d'outils, faire un `rm -rf`. La sonde met en scène ce que [31] a établi de plus dur : la posture est un **flag**, et [31] a sondé deux canaux qui ne sont pas des outils (la commande d'un serveur MCP, un hook des settings) et qui, eux, tournent. Le point du ticket n'est pas qu'une lentille soit malveillante : c'est qu'un contrôle dont le rôle est de mesurer ce qu'il ne contrôle pas doit refuser de conclure quand il n'a pas mesuré. Une release qui cesse d'honorer un flag, un hook d'un projet ordinaire, une machine qui nettoie `$TMPDIR` sous le run : trois causes, un seul chemin de code.

- **Piège pour qui livrera ça, et c'est le cœur du ticket.** La réparation évidente est d'ajouter une garde dans `gate__contain_lens_writes`. Elle est nécessaire et elle ne suffit pas : `gate_unjudged_changes` a **quatre** lecteurs (le confinement des lentilles, `gate__report_changed`, la ligne du rollback via `failures__report_unrolled`, et lui-même deux fois de suite dans le confinement), et chacun lit « liste vide » comme « rien à dire ». Une garantie réparée chez un appelant est le défaut de [25] à l'envers : *combien d'endroits appellent ça*. La forme qui tient est que la primitive distingue les deux cas dans son **statut** — elle le fait déjà pour l'arbre, pas pour le diff — et que chaque lecteur choisisse explicitement.

  Second piège : ne pas rendre le refus rouge partout par symétrie. `gate__report_changed` est une ligne d'annonce sur une itération qui peut être verte ; la rendre bloquante ferait refuser une itération honnête sur une machine dont `$TMPDIR` a été nettoyé. Ce qu'elle doit faire est dire qu'elle n'a pas pu compter — la leçon de [30] sur `core.excludesFile` (« un contrôle qui rend compte de son intention et non de son résultat »), un cran plus loin.

- **Contrainte pour [13].** Un worktree par itération referme la moitié B par construction : l'arbre de l'itération suivante ne porte pas ce que la précédente a laissé. Il ne referme rien de la moitié A. Et il ajoute un appelant de `gate_tree_snapshot` par worktree, donc la revue des appelants demandée par l'AC 2 doit être refaite là-bas — à écrire dans son ticket.

- **Contrainte pour [10].** Le reçu d'audit doit pouvoir dire « ce gate n'a pas pu mesurer » et pas seulement « ce gate n'a rien trouvé ». C'est une quatrième catégorie après les trois exemptions de [29], et c'est la première qui soit un aveu d'ignorance plutôt qu'une liste.
