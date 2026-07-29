# 25 — L'arrêt gracieux ne finit pas l'itération quand il tombe pendant le gate

**What to build:** Faire tenir la promesse que `loop.sh` écrit en tête de sa section *graceful stop* : « un kill demande au run de s'arrêter, il ne le démantèle pas : l'itération en cours finit ». Elle est vraie quand le TERM arrive pendant la session, fausse quand il arrive pendant le gate. `gate_run` collecte ses branches avec `wait`, et bash interrompt `wait` immédiatement quand un signal piégé arrive — le trap `loop_request_stop` s'exécute, `wait` rend un code > 128, et le gate lit des verdicts qui n'existent pas encore.

**Blocked by:** None

**Write-surface:** `.claude/lib/gate.sh`, `test/gate.bats`, `test/loop-happy-path.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** resolved

- [x] Un TERM reçu pendant que les branches tournent ne raccourcit pas leur collecte : chaque branche est attendue jusqu'à son code de retour, et le verdict rendu est celui qu'elles ont réellement produit. `gate__collect` re-attend tant que `wait` répond > 128 **et** que la branche répond encore à `kill -0`.
- [x] Un ticket dont la seule anomalie est un arrêt gracieux ne gagne pas de `Failures:` et ne quitte pas la frontière. Asserté nommément, champ `Failures:` absent compris.
- [x] Aucune branche ne survit au run — mais **pas** par le chemin que cette AC anticipait : puisque toutes les branches sont attendues, aucune ne reste à tuer, et `gate__kill_tree` demeure le chemin du seul chien de garde. Voir le commentaire « ce que le correctif ne fait pas ».
- [x] `rm -rf "$dir"` ne s'exécute pas tant qu'un process peut encore y écrire : il est derrière la collecte complète, et le test le prouve par le marqueur que la branche écrit *après* le stop.
- [x] Le test le prouve avec un `TEST_CMD` **lent**, et le premier `sleep` de ce `TEST_CMD` est porteur lui aussi — voir le piège de synchronisation.

## Comments

- **Origine : passe transversale 01→22, le 29/07/2026.** Sondé avec un `TEST_CMD` qui dort 8 s et un TERM envoyé dès que la branche a démarré. Journal du run, tel quel :

  ```
  ralph: iteration 1: 01-alpha
  ralph: stop requested — finishing the current iteration
  ralph: gate: tests red (no verdict)
  ralph: gate: 01-alpha: tests=red scope=green
  ralph: rolled back 1 path(s) the session touched
  ralph: 01-alpha: gate-red -> fresh retry (1 of 2)
  ```

  La suite de tests aurait été **verte** : elle a fini 8 s plus tard, après la sortie du run. Ce que l'itération a coûté : un `Failures: 1` non mérité, le travail de la session rollbacké **pendant que sa propre suite de tests tournait encore**, une branche de tests devenue orpheline qui a survécu au run, et le répertoire de travail du gate supprimé sous ses pieds. Trois arrêts gracieux sur le même ticket l'envoient en `ready-for-human` avec la raison `failed-impl`, sur un ticket qui n'a jamais été jugé.

- **La cause est un comportement documenté de bash, pas une race.** Pour une commande externe, un trap est différé jusqu'à la fin de la commande ; pour le builtin `wait`, le manuel dit l'inverse — « the reception of a signal for which a trap has been set will cause the wait builtin to return immediately with an exit status greater than 128, immediately after which the trap is executed ». `gate_run` fait `wait "$brc" 2>/dev/null || true` : le `|| true` avale précisément le code > 128 qui aurait pu distinguer les deux cas. Le correctif est de reboucler tant que la branche n'a pas déposé son `.rc`, ou de re-`wait` sur un retour > 128 — pas de désarmer le trap, qui est ce qui rend l'arrêt gracieux gracieux.

- **Pourquoi la suite ne l'a pas vu, et ce que ça dit du test qui existe.** `test/loop-happy-path.bats` a bien un test « a graceful kill finishes the iteration, then stops and frees the lock », et il n'est pas vacuous — `test/mutate.sh` porte la mutation « 03 a stop request tears the iteration down » qui le fait rougir. Mais il envoie le TERM pendant la **session** (le fake pose un marqueur puis dort 1 s) et son `TEST_CMD` est un `stub-cmd` qui rend la main immédiatement : la fenêtre du gate est trop courte pour être touchée. Le test prouve la promesse dans le seul cas où elle tient. C'est le point 3 de la definition of done en pleine forme — « les fakes de la suite finissent vite ; presque tous les défauts livrés vivaient dans cet écart » — et l'asymétrie a été vérifiée dans les deux sens : le même TERM pendant la session donne bien `resolved`, sans `Failures:`.

- **Contrainte pour [06] : ce défaut empire avec une lentille.** Une branche de lentille LLM tient la fenêtre du gate pendant des minutes au lieu de quelques secondes, ce qui multiplie la probabilité qu'un TERM tombe pendant le gate ; et une lentille tuée sans être attendue laisse un `claude` orphelin qui continue à consommer du quota. Livrer [06] avant celui-ci, c'est agrandir la fenêtre avant de réparer la fuite.

- **Livré le 29/07/2026. La sonde du ticket a d'abord été rejouée sous forme de test**, avant une ligne de correctif — `test/loop-happy-path.bats`, « a graceful kill during the gate waits for the branches it started ». Le journal du test rouge est celui du ticket, mot pour mot :

  ```
  ralph: stop requested — finishing the current iteration
  ralph: gate: tests red (no verdict)
  ralph: gate: 01-alpha: tests=red typecheck=green scope=green
  ralph: rolled back 1 path(s) the session touched
  ralph: 01-alpha: gate-red -> fresh retry (1 of 2)
  ```

  Correctif : `gate__collect`, appelé à la place du `wait "$brc" 2>/dev/null || true` du fan, et pour le chien de garde aussi. Une seule branche du fan est concernée par un signal donné — le trap est consommé au premier `wait` interrompu, les suivants bloquent normalement — mais laquelle dépend de l'ordre d'achèvement, donc la boucle de collecte les traite toutes pareil.

- **Ce que la sonde du ticket n'avait pas vu, et qui a failli faire livrer un run qui pend pour toujours.** Le raisonnement naturel est que la boucle de re-`wait` se termine d'elle-même : un pid déjà moissonné rend 127, « not a child of this shell ». **Faux en bash 3.2, et sondé** :

  ```
  (a) wait interrompu par un signal piégé -> 143, le fils est vivant, kill -0 répond
  (b) re-wait sur ce fils vivant          -> bloque, puis rend son vrai code (0)
  (c) re-wait sur un fils sorti normalement, déjà moissonné -> 0
  (e) fils tué par un signal              -> 143
      re-wait dessus                      -> 143, encore, et sans bloquer
  ```

  Le cas (e) est celui du chien de garde. Sans le `kill -0`, la collecte d'une branche tuée par le délai est une **boucle chaude infinie** : le run ne rend jamais la main, ce qui est précisément le mode de panne le plus cher du pack. Le `kill -0` n'est donc pas de la lisibilité, c'est la seule condition de terminaison — et c'est écrit dans le commentaire de la fonction, parce que la prochaine personne à « simplifier » ces deux lignes fera le même raisonnement que moi.

- **Conséquence pour le gate de mutation, qui vaut au-delà de ce ticket.** Une garantie de *terminaison* ne se mute pas comme les autres : retirer la condition qui borne une boucle fait **pendre** le run mutué au lieu de le faire rougir, et `test/mutate.sh` reste alors bloqué avec un défaut planté dans l'arbre de travail. La sortie est de faire porter le délai par le **test**, pas par le code de production : `test/gate.bats`, « collecting a branch the deadline killed ends instead of spinning », lance `gate__collect` détaché et donne 5 s au marqueur pour apparaître. C'est ce qui rend la mutation `25 a branch the deadline killed is waited for for ever` exécutable. Noté aussi dans l'en-tête de `test/mutate.sh`.

- **Ce que le correctif ne fait pas, délibérément : le stop n'a pas de délai à lui.** Avant, un TERM était une sortie de secours involontaire hors d'une branche qui pend — au prix d'un faux rouge et d'un orphelin. Maintenant la collecte attend, donc un `TEST_CMD` qui pend avec `GATE_TIMEOUT` vide fait pendre le run, stop demandé ou non. C'est le statu quo documenté du chien de garde, et un second délai qui ne s'appliquerait que quand un humain a tapé Ctrl-C serait un deuxième gate avec sa propre notion de « trop long ». Combien de temps une itération peut durer est la question de `GATE_TIMEOUT`, et d'elle seule. Test : « a graceful kill during the gate is still bounded by the deadline ». Pour un démantèlement immédiat il reste `KILL`, qui n'est pas gracieux et ne prétend pas l'être.

- **Piège de synchronisation dans le test, qui l'aurait rendu vacuous.** Le marqueur que le test attend avant d'envoyer son TERM est écrit après un `sleep 0.3`, et ce sleep est porteur : si le signal arrive **avant** que la boucle ne soit entrée dans `wait`, le trap s'exécute entre deux commandes, la collecte n'est jamais interrompue, et le test passe au vert contre le code cassé. Vérifié dans l'autre sens sur le code d'origine : sans ce délai, le test est un tirage au sort.

- **Trouvaille de la question 4 (« combien d'endroits appellent cette primitive ? »), livrée en [28].** `grep -n '\bwait\b' .claude/` rend deux lignes, pas une : `session.sh:39` attend `claude` avec le même `wait` nu. Hors du gate, donc hors de ce ticket, mais **la même faille sur une fenêtre plus longue en run réel** : sur le chemin soft-limit, `monitor_watch` rend la main dès son TERM envoyé sans attendre l'extinction, et `wait` bloque pendant que `claude` se ferme. Sondé, avec témoin dans les deux sens : un TERM du run reçu là fait sortir la boucle en laissant un `claude` vivant, qui brûle du quota et écrit dans un flux que la boucle vient de `rm -f`. Sans le TERM, le même run attend bien la fin. Ce n'est pas réparable en appelant `gate__collect` depuis `session.sh` — un lib qui appelle le `__` d'un voisin est refusé par `test/layering.bats` (règle 6) — donc [28] doit d'abord décider où vit la primitive.

- **Écart de write-surface, assumé : `README.md` en plus des cinq chemins déclarés.** Sa ligne « Failles connues » nommait ce ticket comme une faille ouverte ; la laisser aurait fait mentir le dépôt sur exactement ce qui vient d'être réparé. La ligne perd [25], gagne [28], et [25] rejoint les livrés.

- **Constaté au passage, à ne pas mélanger : `GATE_TIMEOUT` n'est pas un budget partagé.** La lecture inverse est tentante — un seul `gate__watchdog` reçoit tous les pids et démarre en même temps que les branches — mais comme les branches sont parallèles, le mur global équivaut à un mur par branche. Une lentille lente ne mange donc pas le délai de la suite de tests. Ce qui reste vrai et mérite d'être su en livrant [06] : le marqueur `timed-out` est **global**, donc une branche qui n'a laissé aucun `.rc` pour une autre raison (subshell tué, OOM) sera journalisée « timed out » si le chien de garde a tiré. Cosmétique aujourd'hui, trompeur le jour où on lira le journal pour comprendre pourquoi une lentille est rouge.
