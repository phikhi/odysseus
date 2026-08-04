# 38 — Une entrée de mutation qui ment un tour sur quatre

**What to build:** Rendre déterministe le test `test/smart-zone.bats` « a session that ignores the deadline's TERM is killed after the grace », et avec lui les **deux** entrées de `test/mutate.sh` qui le nomment — `23 a TERM nobody answers hangs the run for ever` et `23 the grace is hard-coded`. Aujourd'hui l'une ou l'autre rend `VACUOUS` environ **une fois sur trois**, sur `main` comme sur une branche : la garantie « un TERM que personne n'écoute est suivi d'un KILL » n'est prouvée que la plupart du temps, et un `bash test/mutate.sh` vert ne dit donc pas la même chose d'un run à l'autre.

**Blocked by:** None

**Write-surface:** `test/smart-zone.bats`, `test/mutate.sh`, `.claude/lib/monitor.sh`

**Status:** ready-for-agent

- [ ] **Les deux** entrées de mutation rendent le même verdict sur dix runs consécutifs chacune. Le compte est dans le ticket, pas dans un « ça a l'air stable ».
- [ ] La cause est **nommée** : pourquoi le faux `claude` meurt parfois à ~1 s alors qu'il porte `trap '' TERM` et que le reaper a été retiré. Un correctif qui stabilise le test sans expliquer ça déplace la flakiness, il ne la retire pas.
- [ ] Si la cause est dans `monitor.sh` — quelqu'un d'autre que le reaper tue l'arbre — c'est une trouvaille de production et pas de harnais : elle vaut sa propre ligne dans `docs/frontiere-de-confiance.md`.
- [ ] Le canari (`test/canary.bats`) ne gagne pas un `skip` pour ça : une entrée de mutation instable est une garantie non couverte un tour sur quatre, pas une faille connue en attente.

## Comments

- **Origine : livraison de [33], le 04/08/2026.** Le run complet de `mutate.sh` a rendu `VACUOUS` sur cette entrée. Sondé avant de conclure à une régression, et ce n'en est pas une : rejouée seule sur la branche → `VACUOUS, ok, ok` ; rejouée seule sur `main` dans un worktree propre → `ok, VACUOUS, ok, ok`. Pré-existant, indépendant du ticket qui l'a fait apparaître.

- **La sonde, reproductible.** Retirer le reaper à la main dans `monitor.sh` :

  ```bash
  perl -Mstrict -0pi -e 's/  monitor__reaper "\$pid" "\$grace" &\n  MONITOR_REAPER=\$!\n//' .claude/lib/monitor.sh
  ```

  puis rejouer le scénario du test dans un `.bats` jetable qui mesure le temps du run et regarde le marqueur. Deux issues, sur la même machine au repos, à quelques minutes d'intervalle :

  ```
  PROBE: rc=4 elapsed=1s    marker=absent     ← le test reste vert, la mutation est VACUOUS
  PROBE: rc=4 elapsed=34s   marker=PRESENT    ← le test rougit, la mutation est ok
  ```

  Dans le cas à 1 s, le marqueur est toujours absent quarante secondes plus tard : le faux `claude` est bien **mort**, il n'a pas seulement été lent. Sans reaper, personne n'est censé le tuer — il porte `trap '' TERM` et boucle 300 × `sleep 0.1`. C'est cette mort-là qu'il faut expliquer.

- **Pourquoi ça compte plus qu'une flakiness de test.** Le commentaire du test dit déjà avoir vu ce `VACUOUS` sous charge, l'a attribué à `wait_for_file` qui compte des essais et non des secondes, et a ajouté le marqueur `session-ran-to-the-end` pour ne plus dépendre du délai. Le marqueur fait son travail — mais il fait passer le test dans les deux cas, parce que dans le cas à 1 s le faux est mort et n'a rien écrit. La correction précédente a donc rendu le test robuste **et** la mutation instable : la seule chose qui aurait dû rester vraie, « sans le KILL cette session survit », ne l'est pas toujours. C'est la forme exacte du corollaire de `CLAUDE.md` : *le gate qui vérifie les tests peut mentir aussi*.

- **Piste à écarter en premier.** `proc_kill_tree` descend l'arbre de processus et TERM chaque pid. Le faux ignore TERM, ses `sleep` ne l'ignorent pas. Selon l'instant où le balayage tombe, il est possible qu'un pid soit lu, puis réutilisé, ou que le shell interposé par le shim reçoive le signal au lieu du faux. Regarder ce que `proc_kill_tree` vise réellement dans les deux cas — c'est une mesure, pas une hypothèse à trancher au raisonnement.

- **Contrainte pour [23].** Écrite dans son ticket : la ligne « le KILL borne le moment où la boucle récupère la main » est vraie, et sa preuve ne l'est qu'un tour sur quatre.

- **Confirmé et élargi en livrant [34], le 04/08/2026 : ce n'est pas une entrée, c'est le test.** Le run complet a rendu `VACUOUS` sur l'**autre** entrée, `23 the grace is hard-coded`, qui vise le même test. Rejouée seule sur la branche → `VACUOUS, ok, ok` ; dans un worktree propre de `main` → `ok, VACUOUS, ok, ok`. Même signature, même fréquence, même cible : ce qui est instable est `killed after the grace`, et chaque entrée qui le nomme hérite de son instabilité. Deux conséquences pour qui livrera ça : le correctif est à faire **dans le test ou dans `monitor.sh`**, pas dans une entrée de mutation ; et le critère de sortie porte sur les deux entrées, sinon la moitié du problème reste verte par chance.

- **Ce que ça coûte à la procédure, en attendant.** Un `bash test/mutate.sh` complet rend aujourd'hui `1 not ok` de façon attendue, et un agent qui suit `CLAUDE.md` à la lettre — « `bash test/mutate.sh` vert avant d'annoncer » — n'a aucun moyen de le savoir sans lire ce ticket. La manœuvre reste celle de la mémoire de harnais : sur un `not ok`, rejouer l'entrée seule 3-4 fois **et** dans un worktree de `main` avant de conclure à une régression. Tant que ce ticket n'est pas livré, c'est la seule chose qui distingue une entrée instable d'une garantie cassée.
