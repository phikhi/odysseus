# 57 — le drain ne redemande jamais s'il tient encore ses verrous

**What to build:** Donner au second point d'entrée la question que le premier
repose à chaque itération. `loop.sh` demande `run_lock_is_ours` puis
`tree_lock_is_ours` à chaque tour (l. 1468 et 1477) et s'arrête bruyamment si la
réponse est non — parce que le verrou de run vit sous `.scratch/<feature>/`, que
le scope-guard laisse comme bookkeeping, et que [12] a montré qu'une session peut
l'effacer. `human-loop.sh` prend les deux verrous et ne les redemande **jamais**,
alors que c'est le point d'entrée qui met un `claude` **non jugé** dans l'arbre
principal — donc celui où perdre le verrou coûte le plus cher.

**Blocked by:** None

**Write-surface:** `.claude/human-loop.sh`, `.claude/lib/state.sh`,
`test/human-loop.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

**Tags:** securite, frontiere-de-confiance

- [ ] **Le drain repose les deux questions**, séparément, à chaque ticket du
      puits — pour la raison que `loop.sh` écrit à côté des siennes : les deux
      réponses peuvent différer, `.git/` n'étant hors de portée que d'un
      `git add -A`, d'un `git clean` et d'un `rm -rf .scratch`, pas d'une session
      qui efface le répertoire.
- [ ] **Il s'arrête plutôt que de continuer**, et le code de sortie choisi est
      écrit dans l'en-tête de `human-loop.sh` avec les cinq autres. Continuer,
      c'est ouvrir un second `claude` non jugé dans un arbre qu'un run peut
      maintenant réclamer.
- [ ] **`run_lock_is_ours` et `tree_lock_is_ours` gagnent un second appelant** :
      vérifier qu'elles n'ont pas besoin d'être renommées (une `__` avec deux
      appelants est publique — `test/layering.bats`), et que le commentaire de
      `state.sh` cesse de dire une chose fausse pour la moitié du pack.
- [ ] **Une mutation par garantie livrée**, témoin appairé vérifié à la main.

## Ce que la passe du 31/08 a mesuré

Sondes conservées :
`.scratch/ralph-pack/sondes/passe-31-08/p4-le-verrou-que-le-drain-ne-revérifie-jamais.bats`.
Deux tickets dans le puits : la session routée du premier efface les deux verrous,
celle du second enregistre ce qu'il en reste **pendant que le drain tourne
encore**.

- **P4a** — la seconde session routée voit :

      run lock  : ABSENT
      tree lock : ABSENT

  Le drain continue, ouvre le second `claude` non jugé dans l'arbre principal,
  parcourt le puits jusqu'au bout et sort normalement. **Aucune ligne ne le
  nomme.** `state_locks_release` à la sortie est un no-op silencieux.
- **P4b, témoin appairé** — même paire de sessions, sans l'effacement :
  `run lock : présent`, `tree lock : présent`.
- **P4c — le même effacement sur le chemin AFK**, pour la comparaison :

      ralph: the run lock is gone or not ours any more after 1 iterations —
      stopping rather than grinding beside another run

Les deux points d'entrée donnent donc des réponses opposées au même événement, et
celui qui se tait est celui qui met une session non jugée dans l'arbre de
l'opérateur.

## Ce que ça rend faux ailleurs

`.claude/lib/state.sh` écrit, pour justifier de laisser une course ouverte dans
`state_guard_take` : « Two of the three callers are covered downstream — the run
and tree locks are **re-checked for ownership on every iteration**
(`*_is_ours`) ». Cette phrase est vraie de `loop.sh` et fausse de
`human-loop.sh` depuis [16]. C'est la question 4 de CLAUDE.md dans sa forme la
plus simple : une garantie écrite pour un appelant, et un second appelant arrivé
sans elle.

## Pièges connus, pour celui qui livre

- **Un verrou effacé n'est pas un verrou volé.** `state_guard_take` récupère le
  garde d'un propriétaire mort : la question à poser est bien « est-ce encore le
  nôtre » (`$$` contre `pid`), pas « existe-t-il ».
- **`$$` dans une itération du pilote est le pid du pilote** ([47]), et le drain
  n'a pas de sous-shell par ticket — mais `router_sink` et les substitutions de
  commande en ont : ne pas poser la question depuis l'un d'eux.
- **La sonde n'a pas besoin de concurrence** : deux tickets et deux sessions
  routées suffisent, la seconde observant pendant que le drain vit. Un `&` nu ne
  met rien en concurrence (piège de la passe du 27/08).
- **Ce ticket est le moins cher des trois ouverts par la passe** et il est délié
  ([55] et [56] le nomment en `Blocked by:`) : les trois écrivent
  `.claude/human-loop.sh`, et deux tickets dessinés sur un fichier sont un
  `decision` que le pack sait produire tout seul.
