# 41 — La frontière d'ignore est facturée à qui regarde en premier, pas à qui l'a déplacée

**What to build:** Rendre le déplacement de `.git/info/exclude` et de `core.excludesFile` imputable quand plusieurs itérations sont en vol. Ces deux sources vivent dans le répertoire git **commun**, partagé par tous les worktrees liés ; chaque itération les épingle à son propre instant et les remet à son propre gate, sans verrou. [13] a écrit que « le verdict de chacune reste juste — chacune juge à travers son propre témoin — mais l'état est en course ». **C'est faux, et c'est le verdict qui est en course** : le finding tombe sur l'itération qui *regarde* pendant que l'élargissement est vivant, laquelle n'est pas celle qui l'a écrit. Le frère innocent est rougi, rollbacké et facturé d'un retry ; la session qui a écrit trouve la frontière déjà remise par lui et passe au vert.

**Blocked by:** None

**Write-surface:** `.claude/lib/gate.sh`, `.claude/lib/concurrency.sh`, `test/concurrency.bats`, `test/gate.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

- [ ] Deux itérations en vol, l'une dont la session élargit `.git/info/exclude` et l'autre non : l'itération rougie est celle dont la session a écrit, quel que soit l'ordre dans lequel les deux gates tombent. Asserté sur le **ticket facturé** (`Failures:`, outcome au journal), pas seulement sur le contenu du fichier.
- [ ] La remise a lieu **une fois** et le fichier revient à ce que la session a reçu, sans qu'une itération remette par-dessus le témoin d'une autre. Décider et écrire ce qui ordonne : un garde dans le répertoire commun comme celui du repli ([13]), ou une remise qui compare à l'empreinte de son propre témoin avant d'écrire — et dire ce que le choix retenu ne tient pas.
- [ ] Ce qui reste imputable à personne est **nommé** : si deux sessions élargissent dans la même fenêtre, le pack ne peut pas départager, et une ligne doit le dire plutôt que de facturer au hasard.
- [ ] Le témoin appairé : la même paire de sessions à `MAX_PARALLEL=1` doit facturer la session qui a écrit, trois fois, jusqu'à l'escalade. Sans ce témoin le test ne prouve rien sur la concurrence.
- [ ] La mutation vise l'imputation, pas la remise : un correctif qui remettrait le fichier sans rendre le finding à son auteur doit faire rougir.
- [ ] La ligne « La frontière de visibilité de tous les contrôles » de `docs/frontiere-de-confiance.md` cesse de dire que le verdict de chacune reste juste.

## Comments

- **Origine : passe transversale du 06/08/2026** (fenêtre [13]), question 4 posée sur [30] et [32] : *qu'hérite l'itération voisine de ce que celle-ci laisse ?* La réponse que [13] avait écrite — « l'état est en course, le verdict non » — était une déduction, pas une mesure.

  *Sonde.* `MAX_PARALLEL=2`, tickets `01-alpha` (surface `src/alpha.txt`) et `02-beta` (`src/beta.txt`), disjoints donc concurrents. Session `01-alpha` : `printf 'rogue/\n' >>"$root/.git/info/exclude"` dans l'arbre où le run a été lancé, écrit sa surface, puis `sleep 4`. Session `02-beta` : écrit sa surface, rend la main tout de suite.

  ```
  ralph: iteration 1: 01-alpha
  ralph: iteration 2: 02-beta
  ralph: gate: scope red (exit 1)
    moved the ignore frontier in .git/info/exclude, which decides what every check
    here can see — no write-surface may cover it (put back)
  ralph: gate: 02-beta: tests=green typecheck=green scope=red lang=green
  ralph: rolled back 1 path(s) the session touched
  ralph: 02-beta: gate-red -> fresh retry (1 of 2)
  ralph: iteration 2: 02-beta -> gate-red
  ralph: iteration 3: 02-beta
  ralph: gate: 02-beta: tests=green typecheck=green scope=green lang=green
  ralph: iteration 3: 02-beta -> resolved
  ralph: gate: 01-alpha: tests=green typecheck=green scope=green lang=green
  ralph: 01-alpha: committed 1 path(s)
  ralph: 01-alpha: folded onto the branch over a sibling's commit
  ralph: iteration 1: 01-alpha -> resolved

  exit 0        01-alpha -> resolved (0 finding)      02-beta -> resolved, 1 retry brûlé
  ```

  `02-beta` paie : son travail est rollbacké, un retry est consommé, une session entière est redépensée — pour un fichier que sa session n'a jamais ouvert. `01-alpha`, qui l'a écrit, trouve la frontière remise par son frère au moment où son gate tombe : **aucun finding**, vert, commité, replié, `resolved`.

  *Témoin — les deux mêmes sessions à `MAX_PARALLEL=1` :*

  ```
  ralph: iteration 1: 01-alpha
  ralph: gate: scope red (exit 1)
    moved the ignore frontier in .git/info/exclude … (put back)
  … trois tentatives, toutes sur 01-alpha …
  ralph: 01-alpha: escalated to the human sink (failed-impl)

  exit 4     01-alpha -> ready-for-human (Failures: 3)     02-beta -> ready-for-agent
  ```

  C'est bien la concurrence qui déplace la facture, et non le contenu du scénario.

- **Ce que ça coûte au pire, et ce n'est pas seulement un retry.** Le frère facturé peut être à sa dernière tentative : il part alors au puits humain en `failed-impl`, c'est-à-dire avec l'affirmation qu'une implémentation a été jugée et trouvée fausse. Et dans l'autre sens, la session qui a élargi encaisse un vert : le mécanisme dont [30] écrit qu'il existe pour empêcher qu'« une itération rouge achète la nuit » laisse ici acheter une **livraison**.

- **La cause, en une phrase.** `gate_ignore_frontier` répond à la question « la frontière a-t-elle bougé depuis *mon* témoin ? » et non « **qui** l'a bougée ». Tant qu'une seule itération vivait à la fois, les deux questions avaient la même réponse. C'est exactement le corollaire de [29] — *un contrôle qui prend son entrée pendant que d'autres processus écrivent rend un tirage et non un verdict* — sur la seule source que [29] ne pouvait pas atteindre : à l'époque, aucune session n'était vivante pendant qu'un gate lisait.

- **Piège attendu, et il choisit la forme du correctif.** Un verrou autour de la remise ordonne les écritures et ne rend l'imputation à personne : deux itérations verront toujours « ça a bougé depuis mon témoin ». Ce qui distingue l'auteur du témoin passif est *dans quel worktree* la modification a été faite — et la réponse est qu'on ne peut pas le savoir, `info/exclude` étant commun. Les deux sorties honnêtes sont donc : rendre le finding à **toutes** les itérations en vol au moment du déplacement (personne n'est innocenté, personne n'est seul facturé, et la ligne le dit), ou sérialiser les *itérations* dès qu'une frontière bouge. Écrire laquelle et pourquoi, pas seulement le code.

- **Contrainte pour [13].** La ligne du tableau que ce ticket corrige est celle que [13] a écrite lui-même en livrant. Elle est le cas d'école du corollaire de [08] : *une consigne héritée d'un ticket antérieur est une affirmation sur un dépôt qui a bougé* — sauf qu'ici l'affirmation était fausse le jour où elle a été écrite, faute d'avoir été sondée.

- **Contrainte pour [32].** [32] a donné à la remise ses trois appelants (`gate_run`, `failures_reslice`, `failures_handle`). Les trois sont maintenant des chemins **concurrents**, donc les trois facturent au premier regard. Le correctif de ce ticket doit couvrir les trois ou dire pourquoi il n'en couvre qu'un.
