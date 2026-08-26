# 41 — La frontière d'ignore est facturée à qui regarde en premier, pas à qui l'a déplacée

**What to build:** Rendre le déplacement de `.git/info/exclude` et de `core.excludesFile` imputable quand plusieurs itérations sont en vol. Ces deux sources vivent dans le répertoire git **commun**, partagé par tous les worktrees liés ; chaque itération les épingle à son propre instant et les remet à son propre gate, sans verrou. [13] a écrit que « le verdict de chacune reste juste — chacune juge à travers son propre témoin — mais l'état est en course ». **C'est faux, et c'est le verdict qui est en course** : le finding tombe sur l'itération qui *regarde* pendant que l'élargissement est vivant, laquelle n'est pas celle qui l'a écrit. Le frère innocent est rougi, rollbacké et facturé d'un retry ; la session qui a écrit trouve la frontière déjà remise par lui et passe au vert.

**Blocked by:** None

**Write-surface:** `.claude/lib/gate.sh`, `.claude/lib/concurrency.sh`, `.claude/loop.sh`, `test/concurrency.bats`, `test/gate.bats`, `test/failures.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`, `CONTEXT.md`

**Status:** resolved

- [x] Deux itérations en vol, l'une dont la session élargit `.git/info/exclude` et l'autre non : l'itération rougie est celle dont la session a écrit, quel que soit l'ordre dans lequel les deux gates tombent. Asserté sur le **ticket facturé** (`Failures:`, outcome au journal), pas seulement sur le contenu du fichier. — *l'auteur est facturé dans les deux ordres ; le frère aussi, et c'est la sortie retenue, cf. le commentaire de livraison*
- [x] La remise a lieu **une fois** et le fichier revient à ce que la session a reçu, sans qu'une itération remette par-dessus le témoin d'une autre. Décider et écrire ce qui ordonne : un garde dans le répertoire commun comme celui du repli ([13]), ou une remise qui compare à l'empreinte de son propre témoin avant d'écrire — et dire ce que le choix retenu ne tient pas. — *les deux, et pas l'un ou l'autre : un témoin de **run** rend la cible fixe, un garde ordonne*
- [x] Ce qui reste imputable à personne est **nommé** : si deux sessions élargissent dans la même fenêtre, le pack ne peut pas départager, et une ligne doit le dire plutôt que de facturer au hasard.
- [x] Le témoin appairé : la même paire de sessions à `MAX_PARALLEL=1` doit facturer la session qui a écrit, trois fois, jusqu'à l'escalade. Sans ce témoin le test ne prouve rien sur la concurrence.
- [x] La mutation vise l'imputation, pas la remise : un correctif qui remettrait le fichier sans rendre le finding à son auteur doit faire rougir.
- [x] La ligne « La frontière de visibilité de tous les contrôles » de `docs/frontiere-de-confiance.md` cesse de dire que le verdict de chacune reste juste.

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

## Livraison — 07/08/2026

- **La sortie retenue, et pourquoi celle-là.** Des deux sorties honnêtes que le ticket avait nommées, c'est la première : **toute itération en vol au moment du déplacement est facturée**. La raison n'est pas un goût, c'est le sens de l'erreur. Un faux vert laisse une session **acheter une livraison** — c'est exactement ce que [30] existe pour empêcher, un cran plus loin — pendant qu'un faux rouge coûte un retry. Quand on ne peut pas départager, on se trompe du côté qui ne s'achète pas.

  **La sortie non prise, et son coût chiffré.** Sérialiser les itérations dès qu'une frontière bouge est refusé sur deux points, et le second est décisif : (a) un mouvement n'est jamais *détecté* qu'à un gate, donc au moment où on le sait les deux sessions ont déjà tourné — la sérialisation achète l'itération d'après, pas celle-là ; (b) elle donnerait à toute session un `printf` d'une ligne pour retirer au run sa concurrence jusqu'au matin. Une porte de déni de service ouverte par la consigne qu'on essayait de faire respecter.

- **Ce que ça ne tient pas, écrit ici et dans le tableau.** Le frère qui n'a rien écrit paie un retry, et à sa dernière tentative une escalade `failed-impl` — l'affirmation qu'une implémentation a été jugée et trouvée fausse — pour un fichier que sa session n'a pas ouvert. Ce ticket ne crée **pas** une classe d'échec pour ça, et c'est délibéré : le finding porte sa propre ligne (« nothing here can tell which session wrote them and every iteration in flight is charged »), donc l'humain qui lit la facture au matin sait ce qu'il lit. Une classe de plus serait une décision de [26]/[16], pas une conséquence de celle-ci — la contrainte est écrite dans [16].

- **La moitié qui n'était pas dans le titre, et c'est la plus grave des deux.** L'imputation n'est que le symptôme visible ; la cause est que **le témoin de [30] est pris au mauvais niveau**. Il est per-itération, ce qui est juste pour les `.gitignore` d'un worktree — ils sont vraiment privés — et faux pour les trois autres sources, qui vivent dans le répertoire git commun ou hors du dépôt. Conséquence mesurée : une itération qui *spawne* pendant qu'un frère a la frontière élargie épingle l'élargissement comme sa propre base. Elle devient donc aveugle derrière une règle qu'elle n'a jamais écrite, **et sa propre remise réécrit l'élargissement par-dessus le témoin du frère qui l'avait juste**. C'est l'AC 2 dans les deux sens, et une correction qui n'aurait touché que l'imputation l'aurait laissée entière.

  D'où la forme livrée : `gate_ignore_common` prend **un témoin par run** des trois sources partagées, avant la première session de la nuit, et chaque pin d'itération copie sa moitié non-`tree` depuis lui plutôt que depuis le disque. Deux effets, tous deux voulus : la cible de la remise est une valeur fixe qu'aucune session ne déplace (donc deux remises concurrentes écrivent les mêmes octets), et un frère qui spawne en pleine fenêtre juge à travers la frontière que le **run** a reçue.

- **Ce qui ordonne, et pourquoi l'attente est courte.** Un garde `ralph.frontier.lock` dans le répertoire git commun, sur le modèle de `concurrency__integration_guard` comme le demandait le ticket — mais son attente est de 3 s là où celle du repli est de 60 s, et la différence est écrite comme une décision : le repli **doit** être exclusif pour être correct (c'est un compare-and-swap sur une ref), celui-ci ne l'est pas. Il achète une remise et un enregistrement là où il y en aurait deux ; une itération qui ne peut pas l'avoir remet quand même, parce que sauter la remise coûterait la nuit et que la cible est fixe de toute façon. Trois publics nouveaux dans `concurrency.sh` (`concurrency_frontier_guard`, `_take`, `_release`) : le garde appartient au module qui possède le répertoire commun, la décision de le prendre appartient au contrôle qui remet.

  **Piège du garde, et il a failli passer.** `state_guard_release` compare le `pid` stampé à `$$`, et **toutes les itérations d'un run partagent `$$`** — un sous-shell bash n'a pas de `$$` à lui. Une itération qui aurait attendu son tour en vain puis relâché quand même aurait retiré le garde au frère qui le tient. D'où le drapeau `took` et son entrée de mutation, avec la mise en scène qui va avec : le test fait tenir le garde par le shell de `pack_run` lui-même, ce qui est exactement ce à quoi ressemble un frère du même pilote vu du côté du garde.

- **Les trois appelants de [32], couverts par construction et sondés une fois.** `gate_run`, `failures_reslice` et `failures_handle` passent tous par `gate_ignore_frontier`, donc tous les trois enregistrent — mais « par construction » est une déduction tant que rien ne l'a mesuré, et c'est précisément le genre de déduction que ce ticket existe pour corriger. Le chemin `crash` est sondé et gardé par un test à lui (`a frontier moved on a path no gate judges is still charged to the siblings`) : c'est celui qui n'a **aucun** scope-guard pour porter un finding, donc le pire des trois. `core.excludesFile` n'a pas de mise en scène séparée sous concurrence : c'est la même boucle `dir` que `.git/info/exclude`, ligne pour ligne, et [30]/[32] la couvrent chacun de leur côté.

- **La frontière de confiance des deux artefacts nouveaux, posée avant d'écrire.** Le témoin de run et le registre vivent dans `$TMPDIR` sous un nom que le pilote tient dans une variable **jamais exportée** — même posture que le pin ([30]) et que le registre d'écritures ([40]). Mais la question à poser n'est pas « où vit-il », c'est « que se passe-t-il si une session le trouve au glob et le touche ». Réponse livrée :

  | Ce qu'une session peut faire | Ce qui la tient |
  |---|---|
  | détruire le témoin de run ou le registre | **fail-closed** : `gate__ignore_pin_broken` les vérifie comme il vérifie le pin, donc `gate_tree_snapshot` refuse, le scope-guard refuse, le rollback refuse et le run s'arrête ([34]). Sans ça, le repli « lire les sources vivantes » aurait racheté silencieusement le pack d'avant ce ticket |
  | tronquer le registre sous la marque d'une itération | **fail-closed** : un registre plus court que sa propre marque n'est pas un état que ce pack produit |
  | tronquer le registre **exactement** à la marque d'une itération | **rien** — le mouvement qu'un frère avait enregistré disparaît et son auteur repart vert. C'est le résidu, il est nommé dans le code et dans le tableau. La portée requise est la même que celle qui permet de détruire le pin ; la différence est que détruire est bruyant et que tronquer est silencieux |
  | appendre au registre | possible, et sans intérêt pour la session : ça rougit tout le monde en vol, elle comprise |

- **Le run tué, résidu inchangé et cohérent avec le voisin.** Le registre meurt avec le run dans `$TMPDIR`, donc un run tué pendant qu'une frontière est élargie ne facture personne. C'est le même résidu, une ligne plus haut, que celui que [32] a écrit pour la remise que ce run-là ne fait pas : il faudrait un état qui survive au run, et le seul qui existe est le tracker, que la session écrit.

- **Ce que le test a failli acheter, et c'est la trouvaille de méthode.** La première rédaction des tests de concurrence faisait écrire `rogue/backdoor` hors surface aux **deux** sessions — copié des cas de `gate.bats`, où ce fichier sert à vérifier que la règle n'a pas acheté d'invisibilité. Ici il achetait le rouge : les deux itérations auraient été `Failures: 1` avec ou sans ce ticket, et l'assertion centrale (« l'auteur est facturé ») aurait été vide. Les sessions de ces trois tests n'écrivent donc **rien** hors surface : la seule chose qui peut les rougir est la frontière elle-même. Les mutations le confirment côté imputation, mais elles n'auraient pas attrapé ça — une mutation ne teste que ce que l'assertion regarde.

- **Une entrée de mutation qui a menti, exactement de la façon que l'en-tête de `test/mutate.sh` décrit.** `41 the register is read from the beginning of the run` visait la ligne qui lit la marque ; cette ligne existait en **deux** exemplaires (la part de l'itération, et le contrôle fail-closed du registre raccourci), et une substitution sans `/g` édite la première — donc elle éditait `gate__ignore_pin_broken` et rapportait `VACUOUS` sur un test qui allait bien. Corrigé à la racine plutôt qu'au symptôme : les deux lecteurs partagent maintenant une définition (`gate__ignore_mark`), l'ancre est unique par construction, et l'entrée vise la définition. Une entrée de [30] a dérivé pour une raison saine (`30 the pin records nothing of .git/info/exclude` : la copie passe par le témoin de run maintenant) et son ancre est mise à jour.

- **Écart de write-surface, assumé.** Le ticket ne déclarait pas `.claude/loop.sh` ; la livraison le touche pour trois lignes de fond — créer le témoin de run avant la première itération, refuser le run s'il n'y arrive pas, le nettoyer aux trois sorties. Il n'y avait pas d'autre endroit : le témoin doit être pris **avant toute session** et vivre dans une variable du pilote, et `gate_ignore_pin` est appelé en substitution de commande, donc rien de ce qu'il pose ne survit. `.claude/lib/failures.sh` n'a **pas** été touché et n'avait pas à l'être : ses deux appels passent déjà par `gate_ignore_frontier`.

- **Reproduction des sondes.** La sonde d'origine du ticket est maintenant `test/concurrency.bats -f "charged to every iteration in flight"`, son témoin appairé `-f "sequenced bills the session that wrote"`. **Ce qui a changé dans la mise en scène et ce que ça coûterait de le remettre comme avant** : l'ordre des deux gates n'est pas obtenu par un `sleep` mais par une observation — la session qui doit être gatée en second attend que la frontière soit *effectivement remise*, ce que rien d'autre dans le pack n'écrit. Un `sleep 4` mesurerait la machine ([38]), et ces deux tests seraient les premiers à devenir intermittents sous charge.

- **Ce que ce ticket a retiré à [32] sans le vouloir, et c'est la question 4 répondue par une mesure.** `bash test/mutate.sh` complet a rendu un `VACUOUS` sur `32 an iteration no gate judged keeps its widened frontier`, et le diagnostic n'est pas « le test ment » : c'est le pack qui a bougé sous lui. Le discriminant de ce test-là était que, sans la remise du chemin `crash`, l'itération **suivante** épinglait l'élargissement et n'y voyait plus rien. Le témoin de run supprime exactement ça — l'itération suivante juge à travers la frontière que le run a reçue, donc elle détecte, remet et annonce, et les quatre assertions du test tiennent alors que la garantie de [32] a disparu.

  **Et ce que la mutation ouvre est pire qu'avant ce ticket** : sans la remise sur le chemin sans gate, le mouvement est facturé à l'itération suivante, c'est-à-dire à un **autre ticket** dès qu'il y a autre chose à broyer — et sans la ligne d'inimputabilité, puisque cette itération-là l'a vu de ses propres yeux. Le défaut que ce ticket referme, réatteint par la porte de [32]. Correctif : le test de [32] asserte désormais l'**ordre** (`moved the ignore frontier` avant `iteration 2:`), la seule chose que seule la remise du chemin sans gate produit. Vérifié que les deux autres tests de la famille ne sont pas dans le même cas plutôt que supposé — ils tournent à `STERILE_K 1`, il n'y a pas de seconde itération pour masquer.

  **Écart de write-surface, second et assumé** : `test/failures.bats`, pour ce seul test. Il appartient à [32], la contrainte y est écrite.

- **Contraintes écrites ailleurs :** [13] (la phrase du tableau qu'il avait écrite, et le fait que sa question « qu'est-ce qui est per-worktree » a une seconde réponse), [32] (la marque de registre avance à chaque lecture, donc un second appel dans une même itération ne rapporte que le nouveau), [16] (le frère facturé peut arriver au puits humain en `failed-impl` sans qu'aucune implémentation ait été jugée), [19] (deux nouvelles familles de répertoires temporaires à balayer, `ralph-frontier.*`, déjà comptée par `gate_leftovers`).

### État final mesuré

`bash test/run.sh` : **412 tests, 0 échec**, 6 skips opt-in — 401 avant ce ticket, et le rouge de la famille [38] (`a stop request lets the iterations in flight finish`) est vert sur les deux passes complètes de cette branche. `bash test/mutate.sh` : **385 entrées, 2 `not ok`**, et ce sont exactement les deux attendues, toutes deux sur `test/smart-zone.bats -f "killed after the grace"` (`23 a TERM nobody answers hangs the run for ever` et `23 the grace is hard-coded`). Rejouées **`ok` en isolé toutes les deux**, et vertes lors de la *première* passe complète de cette même branche — les deux états observés sur la même branche, c'est la signature de charge de [38] et pas une régression. Aucune entrée portant un autre nom.

- **Le faux du test « a frontier moved on a path no gate judges is still charged to the siblings » avait une course, corrigée par [38] le 26/08/2026.** La barrière du faux ne dit que « les deux sessions sont vivantes » ; 02-beta sondait ensuite l'**absence** de `rogue/` dans `.git/info/exclude` pour savoir que la politique d'échec l'avait remis, et un 02 qui arrivait là avant que 01 n'ait écrit trouvait `rogue/` absent — parce que rien n'avait bougé — et rendait la main aussitôt. Il résolvait au vert, son `Failures:` n'était jamais écrit, le run revenait à 0. Mesuré : rouge 1 fois sur 10 en suite complète, **5 fois sur 8 en isolé**, sur `main` comme sur une branche. La garantie de ce ticket n'est pas en cause — le test ne l'atteignait simplement pas ces fois-là. Ce qui rend la chose coûteuse est ailleurs : l'entrée `41 a crashed iteration's movement never reaches its siblings` nomme ce test, et un test qui rougit tout seul fait rapporter **`ok`** à sa mutation. Un faux `ok`, donc, et un faux `ok` ne se voit pas là où un `VACUOUS` se voit. Le correctif est dans le faux et non dans le pack : 01 pose un marqueur monotone après avoir élargi, 02 attend le front montant puis le front descendant. Après correctif, même fenêtre : branche 6/6 verte, `main` 4/6 rouge.
