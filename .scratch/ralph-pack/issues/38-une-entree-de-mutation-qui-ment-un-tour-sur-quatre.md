# 38 — Une entrée de mutation qui ment un tour sur quatre

**What to build:** Rendre déterministes les tests de délai de `test/smart-zone.bats` — « a session that ignores the deadline's TERM is killed after the grace » d'abord, et « a stream arriving in slow halves is not silence » qui l'a rejoint en livrant [36] — et avec le premier les **deux** entrées de `test/mutate.sh` qui le nomment — `23 a TERM nobody answers hangs the run for ever` et `23 the grace is hard-coded`. Aujourd'hui l'une ou l'autre rend `VACUOUS` environ **une fois sur trois**, sur `main` comme sur une branche : la garantie « un TERM que personne n'écoute est suivi d'un KILL » n'est prouvée que la plupart du temps, et un `bash test/mutate.sh` vert ne dit donc pas la même chose d'un run à l'autre.

**Blocked by:** None

**Write-surface:** `test/smart-zone.bats`, `test/mutate.sh`, `.claude/lib/monitor.sh`

**Status:** ready-for-agent

- [ ] **Les deux** entrées de mutation rendent le même verdict sur dix runs consécutifs chacune. Le compte est dans le ticket, pas dans un « ça a l'air stable ».
- [ ] La cause est **nommée** : pourquoi le faux `claude` meurt parfois à ~1 s alors qu'il porte `trap '' TERM` et que le reaper a été retiré. Un correctif qui stabilise le test sans expliquer ça déplace la flakiness, il ne la retire pas.
- [ ] Si la cause est dans `monitor.sh` — quelqu'un d'autre que le reaper tue l'arbre — c'est une trouvaille de production et pas de harnais : elle vaut sa propre ligne dans `docs/frontiere-de-confiance.md`.
- [ ] `a stream arriving in slow halves is not silence` rend le même verdict sur dix suites complètes — c'est dans la suite complète qu'il rougit, jamais seul, donc le critère de sortie doit être mesuré là. Et sans écarter ses marges : 2.5 s contre 4 s sont des constantes de couverture, les élargir rendrait le test vert et sa garantie invérifiable ([28]).
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

- **Un second test instable du même fichier, trouvé en livrant [36] le 04/08/2026 : `a stream arriving in slow halves is not silence`.** Il rougit **dans la suite complète** et jamais seul — mesuré : suite complète sur la branche `vert, ROUGE, vert` ; le test seul sur la branche `3/3 vert` ; le test seul dans un worktree propre de `main` `4/4 vert` ; suite complète sur `main` `vert`. Le message est `hung, terminated` là où le test attend le contraire, donc le délai de silence est tombé sur une session qui écrivait. La cause est dans les marges du faux : il émet une moitié de ligne, `sleep 2.5`, l'autre moitié, `sleep 2.5`, contre un `SESSION_STALL_TIMEOUT` de 4 — deux dépassements de 0,75 s sous charge suffisent. Ce n'est pas la même signature que `killed after the grace` (là un faux meurt sans qu'on sache qui le tue ; ici un délai tombe pour de bon, avec sa raison), mais c'est la même famille et le même coût pour la procédure : une suite complète peut rougir sans régression. **Ce que le correctif devra trancher, et c'est la leçon de [28] à l'envers :** ces 2.5 et ce 4 sont des constantes de couverture — les écarter rendrait le test vert et sa garantie invérifiable — donc la sortie n'est pas d'élargir la marge mais de retirer l'horloge du chemin critique, en faisant émettre le faux sur un signal plutôt que sur un `sleep`. Vérifié comme n'étant pas de [36] : `monitor_watch` n'est pas touché par ce ticket, qui ne modifie que les processus de délai et ajoute un `find` de 13 ms au démarrage d'un run.

- **Ce que ça coûte à la procédure, en attendant.** Un `bash test/mutate.sh` complet rend aujourd'hui `1 not ok` de façon attendue, et un agent qui suit `CLAUDE.md` à la lettre — « `bash test/mutate.sh` vert avant d'annoncer » — n'a aucun moyen de le savoir sans lire ce ticket. La manœuvre reste celle de la mémoire de harnais : sur un `not ok`, rejouer l'entrée seule 3-4 fois **et** dans un worktree de `main` avant de conclure à une régression. Tant que ce ticket n'est pas livré, c'est la seule chose qui distingue une entrée instable d'une garantie cassée.

- **Diagnostic offert par la livraison de [17], le 05/08/2026 — la cause de *cette* entrée-là est arithmétique, pas mystérieuse.** `23 the grace is hard-coded` remplace `${SESSION_KILL_GRACE:-30}` par **30**, et le faux `claude` du test tourne `while [ $i -lt 300 ]; do sleep 0.1; done`, c'est-à-dire **30 secondes lui aussi**. La passe mutée est donc une course entre deux minuteurs de trente secondes, par construction — et les deux ne s'étirent pas pareil : la grâce est **un** compte à rebours, la fin du fake est **300 `sleep` séquentiels** plus 300 forks. Sous charge, seul le second s'allonge, donc le KILL arrive avant le marqueur `session-ran-to-the-end`, l'assertion négative tient, et l'entrée rend `VACUOUS`. Ce n'est pas « un tour sur quatre » : c'est déterministe dans la charge, et « ok » est le cas où la machine était au repos.

  Sondé en A/B alterné le 05/08/2026, pour écarter une régression de [17] : branche → `VACUOUS`, `main` dans un worktree propre → `VACUOUS`, deux tours d'affilée en alternance. Et trois `main` d'affilée juste avant, sur une machine calmée, → `ok, ok, ok`. C'est l'état de la machine et rien d'autre.

  Ce que ça donne comme piste, sans la livrer : éloigner la fin du fake de la constante de la mutation (600 pas de `sleep 0.1` contre une grâce mutée de 30) ferait gagner le marqueur à coup sûr. **Ne pas le faire à l'aveugle** — c'est exactement le geste que [28] a payé : un délai porté par un fake est une constante de couverture pour la mutation d'un *autre* ticket, et la question à poser avant de toucher ce nombre est « quelle mutation ce nombre tient-il ». Ici il en tient deux (`a TERM nobody answers hangs the run for ever` et celle-ci) et les deux nomment le même test.

- **Deux entrées de plus pour ce ticket, mesurées en livrant [13] le 06/08/2026.** `23 a TERM nobody answers hangs the run for ever` et `23 the grace is hard-coded` rapportent **VACUOUS dans une passe complète et `ok` en isolé** — mesuré dans les deux sens, la version isolée met 14 s et rougit franchement. La cause est déjà écrite dans le commentaire du test qu'elles nomment (`a session that ignores the deadline's TERM is killed after the grace`) : `wait_for_file` compte des *essais* et pas des secondes, donc sous la charge d'une passe de mutation son échéance s'étire au-delà des trente secondes que le faux `claude` met à finir tout seul, et chaque assertion tient alors pour la mauvaise raison. Le garde-fou que ce test s'était donné — `refute_file_exists session-ran-to-the-end` — ne suffit pas non plus : sous charge la session n'atteint pas toujours sa fin.

  Ce que [13] ajoute au dossier, et c'est la forme du correctif : le test de stop de `test/concurrency.bats` avait exactement la même maladie, et il a été guéri en **remplaçant le délai par un protocole de relâche** — la session est tenue ouverte par un fichier que le test crée quand il a fini d'observer, donc « le pilote est encore vivant après son TERM » est un fait sur le pilote et sur rien d'autre. Les deux entrées ci-dessus demandent la même chose : quelque chose que le test contrôle à la place d'un délai qu'il espère.

- **Deux tests rouges de la passe transversale du 06/08/2026, disculpés et disséqués.** `bash test/run.sh` sur la branche de la passe : `386 tests, 2 failures, 6 skipped`. Les deux ont été rejoués en isolé sur la branche **et** sur un worktree détaché de `main` (la passe ne touche aucun fichier de `.claude/**` ni `test/**` — `git diff main --stat -- .claude test` est vide) :

  | test | branche, isolé ×3 | `main`, isolé ×3 |
  |---|---|---|
  | `a stop request lets the iterations in flight finish` (concurrency.bats:588) | ✗ ✗ ✗ | ✗ ✗ ✓ |
  | `a run killed mid-session leaves a claim, …` (claim.bats:386) | ✓ ✓ ✗ | ✓ ✗ ✗ |

  Aucune régression : les deux échouent des deux côtés. Mais les deux ne sont pas la même chose, et c'est ce que la disculpation seule aurait raté.

  **Le premier est bien de ce ticket, et c'est une variante non couverte.** `expected: 2, actual: 3` — une troisième session démarre. Le test synchronise son `kill -TERM` sur l'**apparition de `01-alpha` dans `run.log`**, c'est-à-dire sur un événement du pilote qui précède immédiatement sa décision de démarrer l'itération suivante. Sur une machine assez rapide le pilote gagne la course et claime `03-blocked` avant que le signal n'arrive. C'est exactement la maladie que ce ticket décrit, avec une ligne de journal à la place d'un `sleep` : *un test qui ordonne deux choses par un événement qu'il ne contrôle pas mesure la machine*. Le correctif est celui que [13] a déjà appliqué au même fichier — un protocole de relâche, quelque chose que le test tient plutôt qu'un instant qu'il espère : tenir le pilote entre le journal et la décision, envoyer le TERM, puis relâcher.

  **Le second n'est pas de ce ticket du tout, et il n'attend pas un correctif de synchronisation.** Deux symptômes alternés — `expected status 'resolved', got 'ready-for-human'`, et `The 01-alpha session edited the tracker itself (1 ticket file(s))` dans un test qui ne met en scène aucune édition de tracker. La cause est [44] : le test tue le pilote au `SIGKILL` et tue le pid de la session, mais depuis [13] il y a un troisième processus entre les deux — le sous-shell de `loop__iterate` — que personne ne tue et qui continue d'écrire le tracker pendant que le run suivant broie. Le test avait raison ; c'est le pack qui a changé sous lui. **Ne pas lui poser de garde-fou de timing** : ça masquerait [44].
