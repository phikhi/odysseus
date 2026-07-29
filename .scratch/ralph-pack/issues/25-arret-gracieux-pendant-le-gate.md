# 25 — L'arrêt gracieux ne finit pas l'itération quand il tombe pendant le gate

**What to build:** Faire tenir la promesse que `loop.sh` écrit en tête de sa section *graceful stop* : « un kill demande au run de s'arrêter, il ne le démantèle pas : l'itération en cours finit ». Elle est vraie quand le TERM arrive pendant la session, fausse quand il arrive pendant le gate. `gate_run` collecte ses branches avec `wait`, et bash interrompt `wait` immédiatement quand un signal piégé arrive — le trap `loop_request_stop` s'exécute, `wait` rend un code > 128, et le gate lit des verdicts qui n'existent pas encore.

**Blocked by:** None

**Write-surface:** `.claude/lib/gate.sh`, `test/gate.bats`, `test/loop-happy-path.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

- [ ] Un TERM reçu pendant que les branches tournent ne raccourcit pas leur collecte : chaque branche est attendue jusqu'à son code de retour, et le verdict rendu est celui qu'elles ont réellement produit.
- [ ] Un ticket dont la seule anomalie est un arrêt gracieux ne gagne pas de `Failures:` et ne quitte pas la frontière.
- [ ] Aucune branche ne survit au run : ce qui n'est pas attendu est tué avec son arbre de processus, par le chemin de `gate__kill_tree` déjà écrit pour le chien de garde.
- [ ] `rm -rf "$dir"` ne s'exécute pas tant qu'un process peut encore y écrire.
- [ ] Le test le prouve avec un `TEST_CMD` **lent** — un stub qui rend la main tout de suite ne peut pas distinguer le comportement correct du comportement actuel.

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

- **Constaté au passage, à ne pas mélanger : `GATE_TIMEOUT` n'est pas un budget partagé.** La lecture inverse est tentante — un seul `gate__watchdog` reçoit tous les pids et démarre en même temps que les branches — mais comme les branches sont parallèles, le mur global équivaut à un mur par branche. Une lentille lente ne mange donc pas le délai de la suite de tests. Ce qui reste vrai et mérite d'être su en livrant [06] : le marqueur `timed-out` est **global**, donc une branche qui n'a laissé aucun `.rc` pour une autre raison (subshell tué, OOM) sera journalisée « timed out » si le chien de garde a tiré. Cosmétique aujourd'hui, trompeur le jour où on lira le journal pour comprendre pourquoi une lentille est rouge.
