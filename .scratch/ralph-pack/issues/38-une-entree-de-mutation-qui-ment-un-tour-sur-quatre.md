# 38 — Une entrée de mutation qui ment un tour sur quatre

**What to build:** Rendre déterministe l'entrée `23 a TERM nobody answers hangs the run for ever` de `test/mutate.sh`, ou le test qu'elle nomme (`test/smart-zone.bats`, « a session that ignores the deadline's TERM is killed after the grace »). Aujourd'hui elle rend `VACUOUS` environ **une fois sur quatre**, sur `main` comme sur une branche : la garantie « un TERM que personne n'écoute est suivi d'un KILL » n'est prouvée que la plupart du temps, et un `bash test/mutate.sh` vert ne dit donc pas la même chose d'un run à l'autre.

**Blocked by:** None

**Write-surface:** `test/smart-zone.bats`, `test/mutate.sh`, `.claude/lib/monitor.sh`

**Status:** ready-for-agent

- [ ] L'entrée de mutation rend le même verdict sur dix runs consécutifs. Le compte est dans le ticket, pas dans un « ça a l'air stable ».
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
