# 32 — La frontière d'ignore n'est remise que là où un gate a jugé

**What to build:** Donner à `gate_ignore_frontier` les appelants qui lui manquent. [30] remet `.git/info/exclude` et `core.excludesFile` depuis le témoin, et l'argument qui justifie la remise est écrit noir sur blanc dans son ticket : *sans elle, une itération rouge achète la nuit — la frontière élargie est ce que l'itération suivante épingle*. Or la remise n'existe que sur deux chemins : `gate_run`, et `failures_reslice`. Une itération dont la session **crashe** ou se fait **couper par un délai** n'est jugée par aucun gate et ne re-slice pas : rien ne remet les règles, et l'élargissement devient la configuration légitime du projet au tour suivant. Le prix pour une session est un code de sortie non nul, qu'elle contrôle.

**Blocked by:** None

**Write-surface:** `.claude/lib/failures.sh`, `.claude/lib/gate.sh`, `test/failures.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** resolved

- [x] Une itération qui n'est jugée par aucun gate remet les règles du répertoire git comme une itération gatée, et le dit — il n'y a pas de gate là pour porter un finding, donc la ligne de journal est la seule trace qu'un humain aura. Les quatre classes de `failures_classify` sont couvertes nommément, pas seulement celle qui a servi à écrire le correctif.
- [x] La remise tombe une seule fois par itération quel que soit le chemin : un `gate_run` qui a déjà remis, suivi d'un `failures_handle`, ne doit pas produire deux findings ni deux lignes pour un seul déplacement.
- [x] Le test rejoue la sonde de ce ticket dans les deux moitiés — l'itération qui élargit et crashe, *puis* l'itération suivante qui écrit hors surface derrière la nouvelle règle. Une assertion sur la seule première moitié laisserait passer le correctif qui remet le fichier sans que personne ne vérifie qu'il compte.
- [x] La mutation vise ce que le correctif tient réellement : retirer l'appel doit faire rougir le test par la **seconde** itération devenue verte, pas par le contenu de `.git/info/exclude`.
- [x] La ligne « La frontière de visibilité de tous les contrôles » de `docs/frontiere-de-confiance.md` cesse de dire que les sources du répertoire git sont remises sans dire *sur quels chemins*.

## Comments

- **Origine : passe transversale du 03/08/2026** (fenêtre [06], [23], [28], [29], [30], [31]), question 4 posée sur [30] : *qu'hérite l'itération suivante de ce que celle-ci laisse ?*

  *Sonde — la session élargit `.git/info/exclude`, puis crashe.* Ticket `01-alpha`, surface `src/alpha.txt`. Session 1 : `printf 'rogue/\n' >>.git/info/exclude`, écrit `rogue/backdoor` hors surface, écrit sa surface, `exit 1`. Session 2 (retry du même ticket) : écrit `rogue/second` hors surface et sa surface, `exit 0`.

  ```
  ralph: iteration 1: 01-alpha
  ralph: rolled back 2 path(s) the session touched
  ralph: 01-alpha: crash -> fresh retry (1 of 2)
  ralph: iteration 2: 01-alpha
  ralph: gate: 01-alpha: tests=green typecheck=green scope=green
  ralph: gate: 01-alpha: nothing in this gate judged 1 ignored path(s): rogue/
  ralph: 01-alpha: committed 1 path(s)
  ralph: iteration 2: 01-alpha -> resolved

  exclude:            # git ls-files … rogue/          rogue/second: survives
  scope complaints:   0                                frontier findings: 0
  ```

  La première moitié marche comme [30] l'a livrée : `rogue/backdoor` est forcé dans l'arbre jugé et le rollback le défait. Ce qui ne marche pas est ce qui vient après : zéro finding de frontière, `.git/info/exclude` toujours élargi, et l'itération 2 épingle `rogue/` comme une règle du projet. `rogue/second` est alors invisible pour tout le pack, l'itération est verte, le ticket est `resolved`, et la ligne de zone annonce `rogue/` exactement comme elle annoncerait un répertoire de build.

  *Même sonde sur le chemin des délais de [23]*, `SESSION_STALL_TIMEOUT=2` et une session 1 qui dort après avoir écrit :

  ```
  ralph: session wrote nothing for 2s — hung, terminated
  ralph: 01-alpha: timeout -> fresh retry (1 of 2)
  …
  ralph: iteration 2: 01-alpha -> resolved
  exclude: … rogue/     rogue/second: survives     frontier findings: 0
  ```

  *Témoin — le même scénario avec un gate qui tourne* (session 1 propre, `TEST_CMD` rouge) :

  ```
  ralph: gate: 01-alpha: this session moved the ignore frontier … (put back)
  exclude:            # git ls-files …            rogue/second: gone
  scope complaints:   3                            frontier findings: 1
  ```

  La frontière est remise, le fichier derrière la règle est vu et rollbacké aux trois tentatives. C'est donc bien le chemin qui décide, et non le contenu du scénario.

- **La cause, et elle est courte.** `grep -n gate_ignore_frontier .claude/` rend deux appelants : `gate.sh` (dans `gate_run`, avant le fan) et `failures.sh` (dans `failures_reslice`). `loop.sh` n'appelle `gate_run` que quand la session est revenue `rc=0` sans limite molle et sans délai ; `failures_handle` n'appelle `failures_reslice` que pour la classe `too-big`. Restent `crash` (tout `rc` non nul) et `timeout` (`session-stalled`, `session-timeout`) : deux classes, aucun appelant.

  Le commentaire du second appelant dit précisément pourquoi il existe — « a planning session is a session, it is never gated, so nothing else here would ever put the rules back and the *next* iteration would pin the widened ones ». Le raisonnement est juste et n'a pas été appliqué à la session d'itération, qui n'est pas gatée non plus sur deux de ses quatre issues. C'est la question 4 dans sa forme pure : faux dans aucun ticket pris isolément. [30] a fermé le chemin sans gate qu'il connaissait ; les deux chemins que [23] venait d'ajouter deux jours plus tôt n'étaient dans le champ de vision de personne.

- **Ce que ça coûte à une session, mesuré.** Un `exit 1`. C'est la partie inconfortable : le pack facture un retry (`Failures: 1`) et rend en échange un angle mort permanent sur un répertoire au choix. Deux itérations suffisent, et la seconde est verte, commitée, `resolved`.

- **Piège pour qui livrera ça.** La tentation est d'appeler `gate_ignore_frontier` en tête de `failures_handle`, qui est le point de passage de tous les échecs. Ça marche pour les deux classes manquantes et ça **double** la remise sur `gate-red` et `tracker-write`, où `gate_run` l'a déjà faite : deux findings pour un déplacement, et une ligne de rollback qui parle d'un fichier déjà remis — le demi-mensonge que [29] a refusé. La forme qui reste honnête est soit un appel conditionné à « aucun gate n'a tourné sur cette itération », soit une remise idempotente qui ne rapporte que ce qu'elle a *réellement* changé (`gate__ignore_restore` sait déjà répondre à ça, c'est ce que [30] a construit en deux passes). Trancher dans le ticket, et dire lequel des deux.

  Second piège, du même genre : `gate_ignore_frontier` **remet et rapporte** dans la même fonction. Sur un chemin sans gate il n'y a pas de scope-guard pour porter le finding, donc l'itération ne peut pas devenir rouge par ce moyen — elle est déjà rouge de toute façon. Ne pas inventer une classe d'échec pour ça : ce qui manque est la remise, pas un verdict.

- **Ce qui reste hors de ce ticket, et pourquoi.** Le `.gitignore` de l'arbre n'a rien à remettre (c'est du travail de projet, [30]) — mais sur un chemin sans gate, personne n'imprime la ligne de cause non plus (`gate__report_frontier` vit dans `gate_run`). Un humain qui lit le matin voit donc `nothing in this gate judged … lib/` sans jamais savoir qu'une session l'a décidé. À traiter ici : c'est la même ligne de journal, au même endroit.

- **Contrainte pour [13].** La remise est une écriture dans le répertoire git **commun**, partagé par tous les worktrees liés — [30] l'a déjà écrit dans son ticket. Ce ticket ajoute que la remise tombera désormais sur plus de chemins, donc plus souvent, donc la course entre deux itérations concurrentes qui remettent la même clé est plus large qu'elle ne l'était.

- **Contrainte pour [10].** Le reçu d'audit hérite d'une ligne de journal supplémentaire sur les chemins d'échec (« la frontière a été remise, hors gate »), et elle n'a pas d'équivalent dans les verdicts : c'est la seule trace de l'événement.

- **Contrainte posée par [35], livré le 04/08/2026 : `gate_run` a maintenant *deux* endroits où les findings de `gate_ignore_frontier` s'impriment.** Le chemin nominal les fait porter par la sortie du scope-guard ; le refus de livraison (`delivery=red`) rend son verdict **avant le fan**, donc sans scope-guard, et réimprime les findings ligne à ligne lui-même — sans quoi une session qui élargit `.git/info/exclude` et n'écrit rien derrière verrait sa règle remise en silence. Deux conséquences pour ce ticket : l'AC « la remise tombe une seule fois par itération » doit compter les **lignes** aussi, sur les trois chemins maintenant (gate nominal, refus de livraison, `failures_handle`) ; et le chemin qu'il faut sonder en priorité est celui d'une session qui élargit la frontière **puis crashe**, parce que c'est le seul où plus personne n'imprime quoi que ce soit.

## Livraison — 04/08/2026

- **Ce qui a été livré, en une phrase.** `failures_handle` remet la frontière d'ignore pour les deux classes que rien ne gate (`crash`, `timeout`), avant de snapshotter l'arbre qu'il va rollbacker, et le dit — plus une ligne de cause pour les `.gitignore` de l'arbre, que personne n'imprimait sur ces chemins.

- **Le choix tranché, et c'est celui que le piège demandait de nommer : un appel conditionné à la classe, pas une remise idempotente.** Les six sorties de `failures_classify` ont chacune un appelant et un seul :

  | classe | qui remet |
  |---|---|
  | `gate-red`, `contract`, `nothing-delivered` | `gate_run`, avant le fan |
  | `too-big` | `failures_reslice`, **après** la session de planification — qui est elle-même une session non gatée, donc la remise doit tomber après elle pour couvrir ce qu'*elle* a déplacé |
  | `crash`, `timeout` | `failures_handle` — ce ticket |

  La raison de préférer le conditionnement : **la remise est déjà idempotente pour ce qu'elle remet**. Un second appel sur `.git/info/exclude` trouve le fichier revenu, `gate_ignore_moved` ne rend rien, et il n'imprime rien. Ce qu'un appel en trop double, ce n'est donc pas ce qu'il remet, c'est ce qu'il **ne peut pas** remettre — le fichier d'exclusion global, hors du dépôt, qui est signalé à chaque appel et pour toujours. Une remise « idempotente qui ne rapporte que ce qu'elle a changé » ne rapporterait alors *jamais* le cas global, c'est-à-dire supprimerait un finding de [30]. Un appelant par chemin est la seule forme qui garde les deux propriétés.

- **La liste a été lue, pas devinée.** C'est la leçon que la passe du 03/08 avait tirée de [30] (« où est la liste des chemins, et est-ce que je l'ai lue ») : le `case` de `failures_classify` est la liste, elle est recopiée dans le commentaire au-dessus de l'appel avec le nom de qui couvre chaque classe. Un ticket qui ajoutera une classe verra la question posée à côté de sa ligne.

- **Placement, et il porte trois choses à la fois.** L'appel est en tête de `failures_handle`, après la classification et **avant** `gate_tree_snapshot` : (1) l'arbre que le rollback compare est alors mesuré à travers les règles que le run a distribuées et non celles que la session a laissées ; (2) la ligne de cause sur les `.gitignore` de l'arbre est imprimée pendant qu'ils sont encore déplacés — le rollback qui suit les emporte ; (3) rien de ce que la remise écrit ne peut être imputé à la session, `.git/` n'étant dans aucun arbre.

- **Deux phrasés pour une même liste, à dessein.** `gate__report_frontier` dit « this iteration was judged through the rules it was handed, the new ones apply from the next ». Sur un chemin sans gate c'est faux deux fois : rien n'a jugé, et le rollback reprend la règle. D'où `gate_moved_tree_rules`, public (second appelant ⇒ public, CLAUDE.md §6), qui rend la liste, et deux sites qui écrivent chacun la phrase dont ils peuvent répondre. Si le rollback refuse ensuite, il le crie lui-même et le run s'arrête ([34]) — une ligne contredite bruyamment deux lignes plus loin n'est pas le demi-mensonge de [29].

- **Le test de comptage était vide, et c'est la trouvaille de la livraison.** L'AC 2 (« une seule fois quel que soit le chemin ») se teste mal : comme la remise de `.git/info/exclude` est idempotente, un appel branché sur *toutes* les classes ne produit aucune ligne en double et le compteur reste à 1. Écrit comme ça, le test aurait été vert avec et sans le conditionnement — un compteur mesurant une constante. Il ne devient réfutable qu'en faisant déplacer **les deux** sources par la même session : les `.gitignore` de l'arbre ne sont jamais remis (travail de projet, [30]), donc ce sont eux que deux locuteurs répètent. La mutation « the restore is bolted onto every class » rougit par cette ligne-là, et par la phrase `no gate judged this iteration` apparaissant sur une itération gatée. Corollaire ajouté à `docs/frontiere-de-confiance.md`.

- **Sondes rejouées le 04/08/2026** (harnais jetable `test/probe-32.bats`, supprimé depuis) :

  1. *Crash, les deux moitiés* — session 1 élargit `.git/info/exclude`, écrit `rogue/backdoor` hors surface et `exit 1` ; session 2 écrit `rogue/second` hors surface. Avant : itération 2 verte, `resolved`, `rogue/second` survit, zéro finding. Après : `moved the ignore frontier in .git/info/exclude … (put back)`, exclude propre, `wrote rogue/second, outside the declared write-surface`, `rogue/second` effacé, ticket `ready-for-human`. C'est le test « a session that crashed cannot leave the ignore frontier widened », dont les assertions sur la *seconde* itération viennent en premier (AC 4).
  2. *Délai de [23], les deux moitiés* — `SESSION_STALL_TIMEOUT=2`, session 1 élargit puis dort. Même résultat : remise à l'itération 1, `scope=red` à l'itération 2, `rogue/second` effacé.
  3. *`core.excludesFile` sur un crash* — la seconde source `dir`, que les tests de [30] ne couvraient que sous un gate : `git config --unset` la remet, la clé est vide après le run, le fichier écrit derrière est rollbacké.
  4. *Crash **et** témoin détruit* — la session élargit, écrit hors surface, détruit le pin de `$TMPDIR` et sort 1. La remise ne dit rien (sans manifeste, `gate_ignore_moved` ne peut rien comparer) — et ce silence est couvert : `gate_tree_snapshot` refuse, le rollback refuse, `RALPH_ROLLBACK_FAILED` arrête le run avant l'itération suivante ([34]). Rien n'est blanchi, la frontière reste élargie, un humain repart d'un état connu. **Décision : ne pas ajouter de fail-closed ici** — le contrôle qui suit immédiatement en a un, en ajouter un second ne changerait que le mot imprimé.

- **Ce qui reste, et c'est la même frontière un cran plus haut.** Un run **tué** (`kill -9`, coupure, OOM) ne passe par aucune des trois portes : son témoin meurt dans `$TMPDIR`, son élargissement reste, et le run *suivant* l'épingle comme la configuration du projet. Rien dans le pack ne peut le refermer — il faudrait un état qui survive au run, et le seul qui existe est le tracker, que la session écrit. Écrit dans le tableau, pas laissé au lecteur.

- **Écarts de write-surface : aucun.** `CONTEXT.md` n'a pas bougé et n'avait pas à bouger : son entrée « règles épinglées » dit que les deux sources du répertoire git sont remises, sans jamais promettre sur quels chemins — elle était vraie avant et elle l'est encore. `loop.sh` non plus : `failures_handle` est déjà son point de passage pour tout ce qui n'est pas `resolved`.

- **Contraintes écrites ailleurs :** [13] (trois appelants au lieu de deux, donc une course sur le répertoire git *commun* aussi large que l'itération) et [10] (deux lignes de journal sur les chemins d'échec, et le fait que les deux phrasés ne doivent pas être fusionnés dans le reçu).

- **Passe transversale du 06/08/2026 : les trois appelants sont maintenant concurrents.** Ce ticket a donné à la remise les trois sorties d'une itération (`gate_run`, `failures_reslice`, `failures_handle`), ce qui reste juste. Depuis [13] les trois tombent en parallèle sur un fichier partagé, donc les trois facturent leur finding à l'itération qui **regarde** et non à celle qui a écrit ([41]). Le correctif de [41] doit couvrir les trois ou dire pourquoi il n'en couvre qu'un — la liste est celle que ce ticket a établie, il n'y a pas à la redeviner.

- **Contrainte écrite par [41], livré le 07/08/2026 — les trois appelants sont couverts, et l'un d'eux a une propriété nouvelle.** Les trois passent par `gate_ignore_frontier`, donc les trois enregistrent le mouvement dans le registre de run et le rendent à toutes les itérations en vol ; le chemin `crash` est sondé nommément (`test/concurrency.bats -f "no gate judges is still charged"`) parce que c'est celui qui n'a aucun scope-guard pour porter un finding. **Ce qui change pour la double lecture que ce ticket avait raisonnée** : la part d'une itération est lue avec une **marque qui avance à chaque lecture**, donc quand une même itération demande deux fois — `gate_run` avant le fan, puis `failures_reslice` après la session de planification — la seconde ne rapporte que ce qui a bougé depuis la première. Le raisonnement « conditionné à la classe plutôt que rendu idempotent, parce qu'un second appel rapporterait deux fois ce qu'on n'a pas pu remettre » reste vrai et reste la raison du `case`, mais il n'est plus la seule chose qui empêche un doublon : un appelant qu'on ajouterait par erreur rapporterait désormais le fichier global une fois de plus (il est redétecté, donc réenregistré), et rien d'autre.

- **Et ce que [41] a retiré à ce ticket sans le vouloir : le discriminant de son propre test.** Trouvé par `bash test/mutate.sh` complet, entrée `32 an iteration no gate judged keeps its widened frontier` passée **VACUOUS**. La raison n'est pas une faiblesse du test, c'est un changement sous lui. Avant [41], retirer la remise du chemin `crash` faisait épingler l'élargissement par l'itération **2** — donc plus aucun finding, plus de remise, et les quatre assertions rougissaient. Depuis [41], les trois sources partagées sont témoignées **une fois par run** : l'itération 2 ne pinne plus ce que la session crashée a laissé, donc elle détecte le mouvement, le remet et l'annonce — les assertions tiennent toutes, y compris le comptage à 1.

  **Ce que la mutation ouvre réellement, et c'est pire qu'avant.** Sans la remise sur le chemin `crash`, le mouvement est facturé à l'itération **suivante**, c'est-à-dire à un **autre ticket** dès qu'il y a autre chose à broyer — et sans la ligne « personne ne peut être départagé », puisque cette itération-là l'a détecté de ses propres yeux. C'est le défaut de [41] atteint par la porte de ce ticket-ci. La remise sur les chemins sans gate est donc **plus** porteuse qu'avant, pas moins.

  **Correctif : le discriminant devient l'ordre.** Le test asserte maintenant que la ligne `moved the ignore frontier` apparaît **avant** `iteration 2:`. C'est la seule chose que seule la remise du chemin sans gate peut produire. Les deux autres tests de la famille n'étaient pas touchés et c'est vérifié plutôt que supposé : `a session the loop cut short…` et le test `budget` de [08] tournent à `STERILE_K 1`, donc il n'y a pas de seconde itération pour masquer quoi que ce soit.

- **[43], le 07/08/2026 : la garantie « une seule remise par itération » a maintenant deux propriétaires, et la liste de classes n'était déjà plus suffisante.** La table écrite ici est indexée par **classe**, et `budget` est la seule entrée qui nomme une *raison* et pas un genre de session : depuis [08]/[35] elle arrive aussi d'un `nothing-delivered` reclassé, c'est-à-dire d'un gate qui a tourné et qui a déjà remis les règles. Sur ce chemin la remise était demandée deux fois — la seule source qu'aucune restauration ne défait (le fichier d'excludes global) redétectée, réannoncée et **réinscrite dans le registre de [41]**, donc une ouverture facturée deux fois à chaque itération en vol. Personne ne l'avait vu parce que le symptôme n'existe que sur cette source-là. Corrigé en demandant le fait — `RALPH_GATE_FRONTIER_READ`, posé par `gate_run` juste après la restauration — au lieu du nom de la classe.

  **Conséquence pour les entrées de mutation de ce ticket, et c'est le piège dans sa version immobile.** `32 the restore is bolted onto every class, gated or not` élargissait la liste à `*)` ; avec le drapeau en place, l'édition s'applique toujours proprement et ne retire **plus rien** — `ok` en `-n`, `VACUOUS` en vrai (vérifié en appliquant l'ancienne édition à la main : `test/failures.bats -f "once, not twice"` reste vert). Le test était sain, c'est l'arête qui avait bougé. L'entrée retire maintenant les deux propriétaires d'un coup. La règle générale, écrite dans `docs/frontiere-de-confiance.md` : **une garantie peut gagner un second propriétaire, et l'ancienne mutation cesse alors de la retirer** — diagnostiquer ce que l'édition ouvre réellement avant de réécrire un test.
