# 38 — Une entrée de mutation qui ment un tour sur quatre

**What to build:** Rendre déterministes les tests de délai de `test/smart-zone.bats` — « a session that ignores the deadline's TERM is killed after the grace » d'abord, et « a stream arriving in slow halves is not silence » qui l'a rejoint en livrant [36] — et avec le premier les **deux** entrées de `test/mutate.sh` qui le nomment — `23 a TERM nobody answers hangs the run for ever` et `23 the grace is hard-coded`. Aujourd'hui l'une ou l'autre rend `VACUOUS` environ **une fois sur trois**, sur `main` comme sur une branche : la garantie « un TERM que personne n'écoute est suivi d'un KILL » n'est prouvée que la plupart du temps, et un `bash test/mutate.sh` vert ne dit donc pas la même chose d'un run à l'autre.

**Blocked by:** None

**Write-surface:** `test/smart-zone.bats`, `test/concurrency.bats`, `test/mutate.sh`, `.claude/lib/monitor.sh`

**Status:** resolved

- [x] **Les deux** entrées de mutation rendent le même verdict sur dix runs consécutifs chacune. Le compte est dans le ticket, pas dans un « ça a l'air stable ».
- [x] La cause est **nommée** : pourquoi le faux `claude` meurt parfois à ~1 s alors qu'il porte `trap '' TERM` et que le reaper a été retiré. Un correctif qui stabilise le test sans expliquer ça déplace la flakiness, il ne la retire pas.
- [x] Si la cause est dans `monitor.sh` — quelqu'un d'autre que le reaper tue l'arbre — c'est une trouvaille de production et pas de harnais : elle vaut sa propre ligne dans `docs/frontiere-de-confiance.md`.
- [x] `a stream arriving in slow halves is not silence` rend le même verdict sur dix suites complètes — c'est dans la suite complète qu'il rougit, jamais seul, donc le critère de sortie doit être mesuré là. Et sans écarter ses marges : 2.5 s contre 4 s sont des constantes de couverture, les élargir rendrait le test vert et sa garantie invérifiable ([28]).
- [x] Le canari (`test/canary.bats`) ne gagne pas un `skip` pour ça : une entrée de mutation instable est une garantie non couverte un tour sur quatre, pas une faille connue en attente.

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

  **Réglé le 07/08/2026 par la livraison de [44]**, sans une ligne touchée dans `claim.bats` — ce qui est la confirmation que le diagnostic était bon. L'orphelin s'arrête au lieu d'écrire `01-alpha.md`, donc l'écriture ne tombe plus dans la fenêtre que le run suivant surveille. Trois passes consécutives de `claim.bats` vertes après correctif. **Ce ticket ne garde donc plus que deux dossiers** : `a stop request lets the iterations in flight finish` (le protocole de relâche décrit au-dessus) et `23 a TERM nobody answers` (l'AC qui manquait, plus bas).

- **Mesure du 06/08/2026, en livrant [40] : le titre de ce ticket est devenu faux, et c'est une aggravation.** « Un tour sur quatre » décrivait une bascule ; sur cette machine à cette date, l'entrée `23 a TERM nobody answers hangs the run for ever` rend **`VACUOUS` 3/3 sur la branche et 3/3 sur un worktree détaché de `main`**, en alternant les six exécutions. Elle n'est plus intermittente, elle est *toujours* vacueuse — ce qui veut dire que la disculpation par alternance, seul outil dont ce dépôt dispose, ne peut plus distinguer cette entrée d'une régression réelle : les deux côtés répondent pareil parce que les deux sont faux, pas parce que les deux sont sains. La passe complète a rendu `356 mutations, 1 not ok`, ce seul `not ok`.

  Ça ne change pas le correctif, ça change son urgence et son critère d'acceptation. La cause écrite plus haut se lit maintenant à l'envers : la mutation fixe la grâce à 30 s et le faux `claude` du test finit lui aussi à 30 s (300 × `sleep 0.1`) — un compte à rebours unique contre 300 sleeps séquentiels. Tant que la machine était juste assez rapide, les deux arrivaient dans le désordre ; elle ne l'est plus assez, donc le second perd toujours. **L'AC qui manquait** : les deux durées ne doivent pas être le même nombre par coïncidence. Le test doit tenir la session ouverte par un protocole de relâche (le correctif déjà écrit ici pour l'autre moitié) *et* la mutation doit viser une grâce qui ne puisse pas coïncider avec la fin du faux — sinon le prochain qui accélère la machine remettra l'entrée à « un tour sur quatre » et croira l'avoir réparée.

  Corollaire pour quiconque livre un ticket avant celui-ci : `bash test/mutate.sh` rend **`1 not ok` attendu**, et le nom à vérifier est celui-là. Un `not ok` portant un autre nom est une régression.

- **Mesure du 07/08/2026, en livrant [44] : l'entrée a une sœur, et le corollaire ci-dessus était trop étroit.** La passe complète rend **`2 not ok`** : `23 a TERM nobody answers hangs the run for ever` et **`23 the grace is hard-coded`**, les deux `VACUOUS` et les deux nommant le *même* test, `test/smart-zone.bats -f "killed after the grace"`. C'est la même coïncidence lue par l'autre bout. La première mutation retire le reaper ; la seconde remplace `monitor__deadline "${SESSION_KILL_GRACE:-30}"` par `monitor__deadline 30`, c'est-à-dire qu'elle **rétablit exactement la durée que le faux met à finir** — 300 × `sleep 0.1` — au lieu des 2 s que le test configure. Sur une machine chargée le faux passe la barre des 30 s, le KILL tombe avant lui, `session-ran-to-the-end` n'est pas écrit et l'assertion incassable du test tient quand même. L'AC déjà écrite plus haut couvre les deux sans changer d'un mot : **les deux durées ne doivent pas être le même nombre par coïncidence**, et la seconde entrée montre que « les deux durées » veut dire *toutes* celles qu'une mutation peut installer, pas seulement la valeur par défaut.

  Disculpation, parce que ce nom n'était pas dans la baseline et qu'il touche le code que [44] refactorait (`proc_countdown`, sous `monitor__reaper`) : alternance branche/main, entrée par entrée. À vide, `23 a TERM nobody` rend `VACUOUS ok ok` des deux côtés ; `23 the grace` rend `VACUOUS ok ok` sur la branche et `ok ok ok` sur main — pas concluant, la bascule dépendant de la charge. Rejouée **sous charge de fond** (quatre boucles occupées), l'alternance rend `ok / VACUOUS / ok / ok` des deux côtés, la bascule tombant sur la **même passe**. Même maladie, même test, aucune régression. Le corollaire corrigé : `bash test/mutate.sh` rend **1 ou 2 `not ok`**, et les deux noms attendus sont ceux-là — un `not ok` portant un autre nom est une régression.

- **Mesure du 07/08/2026, en livrant [43] : le rouge de `run.sh` de cette famille n'est plus une affaire de charge, il se reproduit en isolé sur `main`.** La passe complète de la branche [43] a rendu **`1 failures`** sur `concurrency.bats -f "a stop request lets the iterations in flight finish"`, avec `expected: 2, actual: 3` sur `assert_equal "$(claude_call_count)" "2"` — le pilote a démarré `03-blocked` avant de voir le TERM.

  La procédure de disculpation a été suivie et elle a donné mieux qu'un verdict : la bascule est **reproductible sans charge, des deux côtés**. Six passes isolées sur un `git worktree add --detach … main` alternent proprement `✓ ✗ ✓ ✗ ✓ ✗`, et trois sur la branche donnent `✗ ✓ ✓`. Ce n'est donc pas une régression de [43] — et ce n'est plus « de la charge » non plus, ce qui était l'explication portée jusqu'ici.

  Ce que ça dit de la cause, pour le ticket qui prendra ce test : la fenêtre est entre la ligne `01-alpha` que le pilote écrit dans `run.log` et l'arrivée du `kill -TERM` que le test envoie *après* l'avoir vue. Le pilote a le droit de repartir dans une passe de planification dans cet intervalle — le test le lui reproche, alors que la promesse de [25] porte sur ce qui est démarré **après** le signal, pas avant. Le témoin que le test veut prendre est pris trop tard d'une passe. C'est le même genre de défaut que la sœur de `claim.bats` réglée par [44] : le test mesure une course qu'il crée lui-même.

  **Corollaire pour quiconque livre un ticket avant celui-ci** (mis à jour) : `bash test/run.sh` rend **0 ou 1 rouge**, et le seul nom acceptable est `a stop request lets the iterations in flight finish`. Un rouge portant un autre nom est une régression. `bash test/mutate.sh` rend **`2 not ok`**, tous deux `VACUOUS` sur `smart-zone.bats -f "killed after the grace"` : `23 a TERM nobody answers hangs the run for ever` et `23 the grace is hard-coded`.

- **Un troisième nom dans la liste, trouvé en livrant [15] le 26/08/2026 : `a stream arriving in slow halves is not silence` (`test/smart-zone.bats`).** Rouge une fois dans une passe complète de `run.sh` (2 h 16 sur une machine où `mutate.sh` a ensuite mis 12 h 20 au lieu de 3 h), sur `refute_output_contains "hung, terminated"`. Disculpé et il faut dire par quoi, parce que « il alterne » n'aurait rien prouvé : 6/6 vert sur la branche **et** 6/6 vert sur `main` dans la même fenêtre par `git worktree add --detach`, puis 3/3 vert des deux côtés sous 36 boucles occupées sur 12 cœurs. Et surtout un argument qui ne dépend d'aucun tirage : la marge est **structurelle**. Le faux écrit des demi-lignes espacées de 2,5 s contre `SESSION_STALL_TIMEOUT=4`, et un délai de ce pack est mesuré avec `SECONDS`, un entier — il tombe donc entre 3 et 5 s. Le pire cas laisse **0,5 s** de marge à un `sleep 2.5` sous pression disque. Ce test mesure la machine dès que la machine ralentit, exactement comme les entrées à deadline de [23].

  Ce que ça change pour le corollaire ci-dessus : la liste des noms acceptables en compte **deux** — `a stop request lets the iterations in flight finish` (`concurrency.bats`) et celui-ci. Tout autre nom reste une régression. Et la charge n'est pas un bruit à ignorer : c'est le régime dans lequel ces deux-là apparaissent, donc une passe complète sur une machine chargée en produira plus souvent qu'une passe à froid.

## Livraison, le 26/08/2026

**La cause, nommée, et ce n'est ni le reaper ni `proc_kill_tree`.** Le faux `claude` ne
mourait pas : **il n'avait jamais démarré**. La sonde A (`sondes/38/s38a.bats`) fait
tourner le scénario du test avec le reaper retiré à la main, en donnant au faux un
battement de cœur et un journal de tous les signaux qu'il peut attraper. Sur 8 passes au
repos, 3 rendent `heartbeats: 0` et un `fake.log` **vide** — pas une ligne, pas même le
`start` que le faux écrit juste après ses `trap`. La sonde B va un cran plus bas et
tranche : dans ce cas-là le répertoire de slot que le shim réserve **en premier**
(`claude.calls/1`, un `mkdir` en tête de fichier) n'existe pas non plus. Le processus est
mort avant d'avoir rien fait du tout.

Ce qui le tue est la composition de deux choses, dont aucune n'est un défaut du pack :

1. `SESSION_STALL_TIMEOUT 1`. **Un délai de 1 n'est pas un délai d'une seconde.** `idle`
   est `$SECONDS` échantillonné au spawn, `SECONDS` est un entier, donc le premier tick
   qui franchit une frontière de seconde satisfait déjà `SECONDS - idle >= 1` — après
   *zéro* seconde de silence réel. Mesuré hors du pack, sans rien de ce dépôt :

       $ bash -c 'hit=0; n=0; while [ $n -lt 120 ]; do idle=$SECONDS; sleep 0.3;
           [ $((SECONDS-idle)) -ge 1 ] && hit=$((hit+1)); n=$((n+1)); done; echo $hit/120'
       38/120

   32 %, à comparer aux 3/8 = 37 % de VACUOUS observés. C'est le même tirage.

2. Le `trap '' TERM` appartient au **scénario**, et le shim ne l'a pas encore `exec`é. Le
   shim réserve son slot, enregistre l'argv, vide `env`, lit `.mcp.json` et la config
   projet, puis lit le prompt sur stdin — une vingtaine de forks, 0,01 à 0,28 s au repos.
   C'est un script ordinaire : il n'ignore rien. Le TERM tombe dessus et le tue.

Donc quand (1) gagne la course, la session meurt de la **requête**, le KILL testé n'a
rien eu à faire, et les deux entrées de mutation rendent `VACUOUS` pour une raison qui
n'a aucun rapport avec la garantie qu'elles visent.

**Prédiction, posée puis vérifiée avant d'écrire le correctif** (c'est ce qui distingue
une cause d'une hypothèse) : monter le délai au-dessus de la fenêtre de spawn doit faire
disparaître le VACUOUS. Sonde C, identique à B au délai près (`SESSION_STALL_TIMEOUT 3`),
reaper toujours retiré : **8/8 scénario entré, 8/8 arrivé au bout**, donc 8/8 test rouge,
donc 8/8 mutation `ok`. Contre 3/8 VACUOUS à 1.

**AC 3 : ce n'est pas une trouvaille de production.** Personne d'autre que le reaper ne
tue l'arbre ; `monitor.sh` a fait exactement ce qui est écrit dans son en-tête, la bande
`limite-1 .. limite+1` étant documentée depuis [23]. Aucune ligne n'est due à
`docs/frontiere-de-confiance.md`. Ce que la bande **veut dire en bas de sa plage** n'y
était pas, en revanche, et c'est la seule édition de `.claude/**` de ce ticket : onze
lignes de commentaire dans `monitor.sh` qui disent que la borne basse à `limite=1` est
*zéro*, avec la mesure. Rien de livré n'en approche — le défaut est 1800 — mais un test
qui met 1 pour rester court ne mesure pas une session pendue.

### Ce que les tests achètent à la place de leurs délais

`a session that ignores the deadline's TERM is killed after the grace` — **les deux
nombres qui décidaient du verdict sans être sous son contrôle sont partis.**

- Le stall passe de 1 à **5** : aucune fenêtre de spawn ne l'atteint. Et le test
  **refuse au lieu de mesurer** si le scénario n'était pas en place — le faux écrit son
  pid juste après son `trap '' TERM`, le test l'attend, et son absence est un `fail`
  explicite. Une course qui reviendrait sera bruyante, pas silencieusement creuse.
- La **durée du faux n'existe plus**. C'était 300 × `sleep 0.1`, soit trente secondes,
  soit exactement le nombre que `SESSION_KILL_GRACE` vaut par défaut et que la seconde
  mutation code en dur : deux minuteurs de trente secondes en course par construction,
  dont un seul s'étire sous charge. Le faux tourne maintenant **jusqu'à ce que le test le
  relâche**. Aucune mutation ne peut installer une durée qui coïncide avec rien.
- Ce que le test regarde est le seul événement que seul le KILL peut produire : la
  disparition du pid. Borné à 15 s — un ordre de grandeur au-dessus des 2 s configurées,
  la moitié des 30 s que la mutation installe — et sur expiration il **relâche** la
  session pour que le run revienne et que l'échec soit *rapporté* au lieu de pendre le
  gate de mutation dedans.

`a stream arriving in slow halves is not silence` — **la bande est écrite, pas élargie.**
Deux inégalités doivent tenir ensemble, et [28] dit pourquoi on ne touche pas à ces
nombres au feeling :

    un écart entre deux morceaux ne doit jamais atteindre le délai   morceau < stall - 1
    un écart entre deux lignes entières doit toujours l'atteindre    ligne   > stall + 1

C'était 2,5 s de morceau, 5 s de ligne, stall 4 : la première inégalité avait **0,5 s** de
marge, donc le test mesurait la machine. C'est maintenant une ligne en **quatre** morceaux
espacés de 3 s contre un stall de **8** — `3 < 7` et `12 > 9` — donc un morceau devrait
mettre plus du **double** de ce qu'il demande avant que le verdict change. Le rapport
passe de 1,2× à 2,33×. Et le côté qui a besoin de la marge est nommé dans le commentaire :
un écart réel ne fait que *s'étirer*, donc la charge ne peut que rendre la seconde
inégalité plus vraie ; tout le risque est sur la première. Les coupures restent au milieu
d'un nom de clé (`"cache_read` / `_input_tokens"`), sans quoi le test ne prouverait plus
que le report de morceau réassemble une clé coupée.

`a stop request lets the iterations in flight finish` (`test/concurrency.bats`) — **le
témoin était pris une passe trop tôt.** Le signal partait à la vue de `01-alpha` dans
`run.log`, une ligne que le pilote écrit quand il **forke** une itération, pas quand il en
collecte une : sur une machine rapide 01 était collecté et 03 réclamé avant l'arrivée du
TERM, et le compte revenait à 3 — un pilote qui n'avait rien fait de mal, mis en échec par
un test qui avait posé sa question trop tôt. L'ordre est maintenant un **protocole** :
les deux sessions sont tenues, le signal part, le test attend **l'accusé de réception du
pilote lui-même** (la ligne que son trap écrit, `stop requested`), et seulement alors
relâche 01. Au moment où le pilote peut prendre la décision, l'arrêt est un fait qu'il a
déjà journalisé. L'asymétrie que le test exige — une itération qui revient pendant qu'une
autre est en vol — est préservée, mais séquencée par le test au lieu d'être tirée au sort.
L'attente de l'accusé a sa propre borne, parce qu'un pilote incapable d'accuser un arrêt
en tenant des itérations serait la trouvaille, pas une machine lente.

### Écart de write-surface

Le ticket déclarait `test/smart-zone.bats`, `test/mutate.sh`, `.claude/lib/monitor.sh`.
Il a fallu **`test/concurrency.bats`** en plus : le troisième dossier de ce ticket
(`a stop request lets the iterations in flight finish`) vit là, et ses commentaires le
disaient déjà sans que la write-surface suive. Ligne corrigée en tête.
`test/mutate.sh` n'a **pas** été touché : les cinq entrées concernées passent telles
quelles, et ce ticket ne livre aucune garantie de production neuve à muter — il répare
des instruments. Les cinq, vérifiées une par une après correctif :
`23 a TERM nobody answers hangs the run for ever` `ok`, `23 the grace is hard-coded` `ok`,
`23 half a line does not count as the session writing` `ok`,
`13 a stop schedules new work anyway` `ok`, `44 the orphan question always answers yes` `ok`.

### Piège de harnais trouvé en livrant celui-ci

**Tuer `test/mutate.sh` en vol laisse la mutation appliquée dans l'arbre.** Fait ici :
le job de fond a été arrêté entre l'édition et la restauration, et `.claude/lib/monitor.sh`
est resté sans son reaper — c'est-à-dire avec la garantie de [23] retirée, dans un arbre
qui avait l'air propre à tout sauf à un `git diff`. Un ticket livré sur cet arbre-là aurait
commité la mutation. À ajouter à la règle existante « ne pas éditer `.claude/` ni `test/`
pendant qu'un gate tourne » : **et ne pas tuer `mutate.sh` sans vérifier `git diff` après**.

### Sondes conservées

`.scratch/ralph-pack/sondes/38/` — trois `.bats` qui finissent par un `false` volontaire,
hors de `test/`, non ramassés par `test/run.sh` sans argument. Elles demandent que la
mutation du reaper soit appliquée à la main (la commande est dans leur en-tête).

### Un quatrième dossier, trouvé par les dix suites de l'AC 4

`a frontier moved on a path no gate judges is still charged to the siblings`
(`test/concurrency.bats`, livré par [41]) est rouge **1 fois sur 10** dans les suites
complètes de la phase 2. Le nom n'était dans aucune liste acceptée.

**Disculpé d'abord, et il faut dire par quoi.** Six rejeux isolés alternés dans la même
fenêtre, branche contre `git worktree add --detach … main` : branche `3✗ / 3✓`, `main`
`5✗ / 1✓`, signature identique au caractère près des deux côtés. Aucune régression de ce
ticket — et une inversion qui vaut d'être notée, parce qu'elle contredit le réflexe du
dépôt : celui-là rougit **plus souvent en isolé (5/8) qu'en suite complète (1/10)**.

**Corrigé ici quand même, et la raison n'est pas le confort.** Une entrée de mutation le
nomme — `41 a crashed iteration's movement never reaches its siblings`. Un test qui
rougit *tout seul* fait rapporter **`ok`** à l'entrée qui le nomme : la mutation croit
avoir été attrapée alors que le test n'a rien mesuré. C'est un **faux `ok`**, c'est-à-dire
pire qu'un `VACUOUS` — un VACUOUS se voit, un faux `ok` se fond dans les 476 autres. C'est
la thèse de ce ticket prise par son côté le plus dangereux, donc c'est de ce ticket.

**La cause, et c'est la même que celle du test d'arrêt d'un cran plus loin :** *le test
attend un état qui n'est pas encore établi, donc « pas encore » se lit « déjà fait ».* La
barrière du faux ne dit que « les deux sessions sont vivantes ». Après elle, 01 écrit
`rogue/` dans `.git/info/exclude` et meurt sans verdict ; 02 sondait l'**absence** de
`rogue/` pour savoir que la politique d'échec l'avait remis. Un 02 qui arrivait là le
premier trouvait `rogue/` absent — parce que rien n'avait encore bougé — et rendait la
main immédiatement. Il résolvait alors au vert, son `Failures:` n'était jamais écrit et le
run revenait à 0 : les deux assertions tombaient ensemble (`assert_failure 4` et
`ticket_field 02-beta Failures`), ce qui est exactement la sortie observée.

**Le correctif : les deux fronts, dans l'ordre.** 01 pose un marqueur `frontier-moved`
*après* avoir élargi, et 02 attend le front montant sur ce marqueur puis le front
descendant sur `rogue/`. Le marqueur plutôt que `rogue/` lui-même parce qu'il est
**monotone** : attendre l'apparition de l'élargissement se bloquerait sur le run où la
restauration a gagné la course.

**Mesuré après correctif, même fenêtre, même alternance** — et le témoin est que `main`
continue de basculer pendant que la branche ne bascule plus :

| | branche | `main` |
|---|---|---|
| avant | 3✗ / 3✓ | 5✗ / 1✓ |
| après | **0✗ / 6✓** | 4✗ / 2✓ |

`41 a crashed iteration's movement never reaches its siblings` : `ok` 3/3.

**Ce que ça a coûté à la procédure, et c'est une leçon à garder** : `test/concurrency.bats`
a rebougé *après* la passe de mutation complète, donc cette passe est devenue périmée pour
toutes les entrées qui nomment ce fichier. Les deux gates ont été relancés en entier. La
règle de `CLAUDE.md` est écrite pour `test/mutate.sh` (« si on réédite mutate.sh après une
passe, relancer la passe complète ») ; elle vaut pour **tout fichier qu'une entrée
nomme**, pas seulement pour le fichier d'entrées.
