# 43 — Une lentille refusée pour quota est comptée comme un échec d'implémentation

**What to build:** Faire que l'abonnement qui s'épuise pendant la phase de lentilles coûte la même chose que quand il s'épuise pendant la session de livraison : rien. [08] a écrit un classifieur qui reconnaît un refus de quota et rend le ticket à la frontière *sans consommer de retry*, parce qu'« une session refusée n'est pas une tentative ». Il lit `rate_limit_event` dans le flux de la **session de livraison**, et il n'est posé que devant `failed` et `nothing-delivered`. Une lentille refusée ne produit ni l'un ni l'autre : elle produit un verdict manquant, donc une branche rouge, donc `gate-red` — la classe que [08] refuse délibérément de pardonner. Le ticket est facturé, retenté, et à `RETRY_N` escaladé `failed-impl`, c'est-à-dire avec l'affirmation qu'une implémentation a été jugée et trouvée fausse. Une itération vaut `1 + n` sessions ([06]) et `MAX_PARALLEL` multiplie encore ([13]) : la majorité des sessions d'un run sont du côté où un refus de quota se lit comme une faute du ticket.

**Blocked by:** None

**Write-surface:** `.claude/lib/lenses.sh`, `.claude/lib/gate.sh`, `.claude/lib/budget.sh`, `.claude/lib/failures.sh`, `test/budget.bats`, `test/lenses.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** resolved

- [x] Une lentille dont le flux porte un `rate_limit_event` non `allowed` et qui ne rend pas de verdict ne fait pas escalader le ticket en `failed-impl`. Le ticket revient à la frontière sans retry consommé, et le run dit que c'était le quota — pas « la lentille a refusé ».
- [x] Ça reste vrai **sans** rendre un gate rouge gratuit : la distinction à tenir est « aucun verdict parce que l'API a refusé la session » contre « aucun verdict parce que la lentille est morte, a été tuée pour contexte ou a répondu de la prose ». Les trois derniers restent rouges ([06] : le silence n'achète pas de vert). Écrire pourquoi ce n'est pas la porte que [08] a fermée devant `gate-red`.
- [x] Le signal remonte au pilote : un run dont les lentilles se font refuser doit finir par pauser ou s'arrêter sur le budget, au lieu de brûler `RETRY_N` × `1 + n` sessions par ticket contre un mur. Aujourd'hui `budget_stream_posture` n'est appelé que sur le flux de livraison, et `budget_` n'apparaît nulle part dans `gate.sh` ni `lenses.sh`.
- [x] La frontière de confiance est respectée telle que [08] l'a posée : le flux d'une lentille est écrit par une session, donc le signal ne peut rendre le run que **plus** prudent, jamais moins. Un `rate_limit_event` forgé dans un flux de lentille ne doit pas pouvoir acheter un vert ni annuler un rouge mérité — au mieux rendre le ticket sans le facturer, ce qui est déjà borné par `STERILE_K` et `ITER_CAP`.
- [x] Le témoin appairé : le même événement dans le flux de la session de livraison doit rester traité comme il l'est aujourd'hui (`budget-pause`, rendu sans retry), sinon le test ne mesure pas la différence entre les deux moitiés.
- [x] La ligne « Une panne de quota ne coûte pas un retry au ticket » de `docs/frontiere-de-confiance.md` cesse de dire « les issues où rien n'a été jugé » sans dire que la phase de lentilles n'en fait pas partie.

## Comments

- **Origine : passe transversale du 06/08/2026** (fenêtre [13]), sonde demandée sur [06] : *`MAX_PARALLEL` × `(1 + n)` sessions vivantes*. En comptant les sessions on tombe sur la question qui compte : ce n'est pas combien il y en a, c'est que **les deux tiers d'entre elles ne sont pas traitées comme des sessions** par le classifieur de budget.

  *Sonde F — la même API, le même événement, deux traitements.* `LENSES=standards`, ticket `01-alpha`. La session de livraison écrit sa surface et son flux dit `allowed` ; la session de lentille émet `{"type":"rate_limit_event","rate_limit_info":{"status":"blocked",…}}` et sort `1` sans verdict :

  ```
  ralph: gate: standards red (exit 1)
    the standards lens ended without a RALPH-LENS-VERDICT line (session exit 1): counted red
  ralph: gate: 01-alpha: tests=green typecheck=green scope=green lang=green standards=red
  ralph: 01-alpha: gate-red -> fresh retry (1 of 2)
  … trois itérations, trois fois le même …
  ralph: 01-alpha: the attempt is kept on branch failed/01-alpha
  ralph: 01-alpha: escalated to the human sink (failed-impl)
  ralph: sterile run: 3 iterations resolved nothing — stopping

  exit 4     01-alpha -> ready-for-human (escalation: failed-impl, Failures: 3)
  ```

  Trois sessions de livraison dépensées, trois gates objectifs verts à chaque tour, et un ticket rendu à un humain avec le motif « l'implémentation a échoué ». Aucune ligne du journal ne contient le mot quota.

  *Témoin — exactement le même événement, dans le flux de la session de livraison :*

  ```
  ralph: 01-alpha: the session was refused for quota (five_hour) — not an attempt at this ticket
  ralph: 01-alpha: given back with no retry consumed — the subscription ran out under this session,
    which is not an attempt at this ticket
  ralph: iteration 1: 01-alpha -> budget-pause
  ralph: budget: the usage endpoint said nothing this run could read, and the last session was told
    it is blocked (five_hour)

  exit 6     01-alpha -> ready-for-agent (aucune escalade, aucun Failures:)
  ```

  Même refus, même charge utile, deux moitiés du même mécanisme, résultats opposés.

- **Pourquoi ce n'est pas « un gate rouge doit rester rouge ».** [08] a raison de refuser de pardonner un gate rouge : c'est la preuve que quelque chose a été regardé et trouvé faux, et le pardonner rendrait le rouge gratuit pour toute session prête à écrire une ligne dans son propre flux. Mais une lentille refusée par l'API n'a **rien regardé** — c'est très exactement le critère que [08] écrit pour poser la question (« uniquement les issues où rien n'a été jugé »), et la phase de lentilles y répond oui. Le classifieur n'a pas été relu contre son critère, il a été relu contre les deux outcomes qui existaient quand il a été écrit : [31], appliqué au budget.

- **Ce que [13] change à l'exposition.** Rien dans la mécanique, tout dans la fréquence. `concurrency_cap` étrangle un *débit* et pas un prix, et il compte des itérations quand la dépense est en sessions ; à `MAX_PARALLEL=3` avec les cinq lentilles livrées, un run peut avoir douze `claude` vivants dont neuf sont des juges. Le mur arrive donc plus tôt, et il arrive statistiquement dans la moitié du mécanisme qui facture le ticket.

- **Piège attendu.** Le flux d'une lentille vit dans le répertoire temporaire du gate et disparaît avec lui ; la posture doit être lue avant, comme `loop__iterate` lit celle de la livraison avant de supprimer le flux. Et elle traverse une frontière de processus (une branche de gate est un sous-shell, [04]/[06]) : c'est le même problème que `RALPH_SESSION_TIMEOUT`, et la réponse de [23] a été de refuser un fichier à côté du flux. Ici le fichier de verdict de la branche existe déjà et il est dans `$TMPDIR` — donc à portée d'une session concurrente au-dessus de `MAX_PARALLEL=1` ([13]). D'où l'exigence d'AC : le signal ne peut que rendre le run plus prudent.

- **Contrainte pour [08].** Le classifieur est posé sur `failed` et `nothing-delivered`. Ce ticket ajoute une troisième issue à sa liste ; la liste doit être relue contre son critère (« rien n'a été jugé ») et non allongée d'un cas.

- **Contrainte pour [06].** La ligne « Le verdict d'une lentille dit la vérité » du tableau dit que l'absence de verdict compte rouge, et c'est juste. Elle doit maintenant distinguer les raisons d'une absence : une lentille qui n'a jamais démarré n'est pas une lentille qui n'a rien dit.

- **Contrainte pour [10].** Le reçu d'audit doit pouvoir dire pourquoi une branche est rouge sans verdict — quota, mort, silence — sinon un humain lit `standards=red` trois fois et en conclut ce que le journal lui laisse conclure aujourd'hui.

## Livraison — 07/08/2026

- **Ce qui a été construit, couche par couche.** Rien de nouveau sur le disque : le flux de la lentille existait déjà, dans le répertoire temporaire du gate, et c'est lui qu'on lit.

  - `lenses.sh` — `lenses__stream` (une seule définition du chemin du flux, parce qu'il a un deuxième lecteur maintenant) et `lenses_refused_posture <dir> <name>`, publique. Elle ne répond que si la lentille n'a **aucun** verdict *et* que la posture de son flux dit refusé. L'ordre compte et il est écrit dans la fonction : **le verdict prime sur l'événement** — une session peut être prévenue qu'elle est bloquée pour la fenêtre d'*après* celle qu'elle dépense et rendre `pass`/`fail` quand même ; cette lentille a regardé. `gate.sh` atteint maintenant ce module par trois fonctions au lieu de deux ; l'en-tête du registre le dit.
  - `gate.sh` — `gate__lens_phase` lit les postures **après** le fan (la branche est un sous-shell, donc ce ne peut pas être la réponse de la branche) et pose `RALPH_GATE_QUOTA` + `RALPH_GATE_QUOTA_ONLY`. `_ONLY` est à 1 sous **trois** conditions : il y a un rouge, la remise en état de l'arbre confié aux lentilles a réussi, et **toutes** les branches rouges sont des lentilles refusées (`gate__all_in`). Le verdict, lui, ne bouge pas : `standards=red` reste `standards=red`.
  - `loop.sh` — le classifieur de [08] gagne un bras `gate-red)` gardé par `RALPH_GATE_QUOTA_ONLY`, et le commentaire au-dessus est réécrit autour du **critère** (« rien n'a été jugé ») plutôt qu'autour des deux outcomes qui existaient à sa naissance. Puis la posture de la lentille est recopiée dans `$slot/posture` — jamais par-dessus une posture déjà refusée, qui est la mesure que le run a prise en premier — pour que le **pilote** l'ait à l'itération suivante.
  - `failures.sh` — cf. le défaut préexistant plus bas.
  - `budget.sh` — commentaires seulement. La section « ce que ce module ne garde pas » disait « les lentilles ne sont pas gatées ici » ; c'est toujours vrai (rien ne dort dans une itération) et il fallait ajouter que *pas gaté* n'est pas *pas lu*.

- **Écarts de write-surface** (déclarée : `lenses.sh`, `gate.sh`, `budget.sh`, `failures.sh`, `test/budget.bats`, `test/lenses.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`). Trois fichiers en plus, tous forcés :

  - `.claude/loop.sh` — le classifieur y vit, et surtout le chemin du slot n'est connu que du pilote. L'AC « le signal remonte au pilote » n'est atteignable d'aucune autre couche : une itération tourne dans un worktree qu'on va détruire, et décider de ne pas spawner appartient au pilote seul.
  - `test/helpers/shims/claude` et `test/helpers/harness.bash` — il fallait pouvoir mettre en scène une lentille refusée (`lens_refused NAME [status] [window] [reset]`). Écrit dans le fake plutôt qu'en `script_claude` pour la raison que `lens-*.writes` porte déjà : un script remplace tout le fake, donc un test qui scripterait une lentille refusée perdrait les verdicts des lentilles d'à côté et mesurerait ça.

- **Le point de doctrine, écrit là où il se lit.** Ce n'est pas « un gate rouge doit rester rouge » qui a bougé. Le commentaire de `loop.sh` et la ligne 48 du tableau disent tous les deux la même chose : [08] a écrit un **critère** (« uniquement les issues où rien n'a été jugé ») et une **liste** (`failed`, `nothing-delivered`) qui était sa transcription exacte au jour où elle a été écrite. Une lentille refusée répond `oui` au critère et n'est dans aucune des deux issues. La liste a été relue contre le critère, pas allongée d'un cas — [31] appliqué au budget.

- **Les trois pièges du ticket, et ce qu'ils sont devenus.**

  1. *Le flux meurt avec le répertoire du gate.* Lu dans `gate__lens_phase`, entre le fan et le `rm -rf "$dir"` de `gate_run`, c'est-à-dire pendant que le répertoire appartient encore à celui qui le lit.
  2. *La frontière de processus.* [23] avait refusé un fichier à côté du flux ; ici on n'en écrit aucun — le flux **est** le fichier, il est déjà là, et le parent le lit. C'est la seule raison pour laquelle ce ticket n'a pas eu à rouvrir la question de [23].
  3. *Le fichier est dans `$TMPDIR`, donc à portée d'une session concurrente au-dessus de `MAX_PARALLEL=1`.* D'où les trois conditions de `_ONLY`, et le tarif écrit dans le tableau : un événement forgé achète, au pire, un ticket rendu sans retry et un run **plus** prudent. Jamais un vert (le verdict manque toujours), jamais l'annulation d'un rouge qu'une autre lentille a mérité (`gate__all_in`), jamais l'effacement d'une mesure du pack (la remise en état de l'arbre). Et c'est déjà borné par `STERILE_K` et `ITER_CAP`.

- **Un quatrième, que le ticket n'avait pas nommé et que la question 5 a sorti.** `GATE_TIMEOUT` tue une branche de lentille, et c'est une mesure que le pack prend lui-même — exactement ce que [23] dit qui doit primer sur une affirmation lue dans le flux du mesuré. Sans garde, tout ce qui sait faire traîner une lentille au-delà de la deadline en ayant émis une ligne `blocked` achetait le même rendu gratuit qu'un vrai refus. La phase ne pose donc aucune question de quota quand `$dir/timed-out` existe. Le marqueur est bien celui de **ce** fan : un fan objectif qui a expiré est rouge, et un fan objectif rouge saute la phase avant même le snapshot. Un fan vert qui a couru la deadline de justesse est lu comme expiré — ça coûte au ticket un rendu qu'il aurait eu, c'est-à-dire le côté prudent. Test : `a lens the gate's own deadline killed is not read as a refusal`.

  Ce qui reste **non tenu** et est écrit comme tel : une lentille tuée *pour contexte* (limite molle, `SESSION_STALL_TIMEOUT`, `SESSION_TIMEOUT`) est mesurée par `monitor_watch` **dans la branche**, donc dans un sous-shell dont rien ne remonte ([23] à nouveau, et `session.sh` l'écrit déjà). Si son flux porte une ligne `blocked`, elle est lue comme refusée. Ce que ça coûte est le même plafond que tout le reste ici — un rendu sans retry, un pilote plus prudent — et pas un vert.

- **Un défaut préexistant, trouvé par la question 4 et corrigé ici.** La table de `failures_handle` qui dit *qui a déjà remis les règles d'ignore* est indexée par **classe** ([32]). Or `budget` est la seule entrée de cette liste qui nomme une *raison* et pas un genre de session : elle arrive d'un gate qui n'a jamais tourné (session de livraison refusée) **et** d'un gate allé au bout — `nothing-delivered` reclassé `budget-pause` depuis [08]/[35], et une lentille refusée depuis ce ticket. Sur le second cas la remise était demandée deux fois : la seule source qu'aucune restauration ne défait (le fichier d'excludes global) était redétectée, réannoncée, **et réinscrite dans le registre de [41]** — donc une seule ouverture facturée deux fois à chaque itération en vol. `gate_run` pose `RALPH_GATE_FRONTIER_READ=1` juste après la restauration, et `failures_handle` demande le fait au lieu du nom de la classe. Sondé : sans le correctif, le test `a widening the gate already read is not charged to the run twice` compte 2 occurrences là où il en attend 1.

- **Ce que ça a fait aux mutations d'autres tickets, et ce qu'il ne fallait *pas* faire.** Sept entrées ont dérivé ou sont devenues creuses. Six sont des ancres déplacées (`06` × 2, `08` × 1, `32` × 2, `41` × 1). La septième est le piège de [41] dans sa version immobile : `32 the restore is bolted onto every class, gated or not` s'appliquait toujours proprement — élargir la liste de classes à `*)` — et ne retirait **plus rien**, parce que le drapeau tient désormais la même garantie. `ok` en `-n`, `VACUOUS` en vrai (vérifié en appliquant l'ancienne édition à la main : `test/failures.bats -f "once, not twice"` reste vert). Le test était sain : c'est l'arête qui avait bougé. L'édition retire maintenant les deux propriétaires. Diagnostiquer avant de réécrire, comme le dit CLAUDE.md.

- **Résidus, nommés.**
  - Une lentille tuée pour contexte avec un `blocked` dans son flux est lue comme refusée (ci-dessus). Rien ne le tient ; le coût est borné.
  - `RALPH_GATE_QUOTA` ne porte que la **dernière** posture refusée quand plusieurs lentilles le sont. Le pilote n'a besoin que d'une fenêtre et d'un reset, et le journal nomme chaque lentille séparément — mais un consommateur qui voudrait la liste ne l'a pas. C'est pour [10].
  - Le journal dit `budget-pause` des deux côtés, ce qui est voulu (même prix, même nom) : la ligne qui distingue les deux moitiés est la ligne du gate, pas l'outcome. Un reçu d'audit qui ne lirait que l'outcome ne saurait pas laquelle des deux moitiés a été refusée — contrainte écrite dans [10].
  - `RALPH_GATE_QUOTA_ONLY` n'est jamais posé quand `MAX_PARALLEL > 1` a fait qu'une *autre* itération a vidé l'abonnement : chaque itération lit ses propres lentilles. C'est correct — on facture qui a été refusé — mais ça veut dire que le pilote apprend le mur autant de fois qu'il y a d'itérations en vol, et pas une seule.

### Vert au merge

`bash test/run.sh` : **421 tests, 1 failures, 6 skipped** (412 → 421 : 2 dans `lenses.bats`, 7 dans `budget.bats`). Le rouge est `concurrency.bats -f "a stop request lets the iterations in flight finish"`, famille [38]. Disculpé, et mieux que d'habitude : rejoué en isolé, il **alterne des deux côtés sans charge** — `✗ ✓ ✓` sur la branche, `✓ ✗ ✓ ✗ ✓ ✗` sur un `git worktree add --detach … main`. Ce n'est ni une régression ni « de la charge » ; la mesure et ce qu'elle dit de la cause sont écrites dans [38].

`bash test/mutate.sh` : **393 mutations, 2 not ok** (385 → 393 : 8 entrées `43`), les deux `VACUOUS` attendus et sur le même test — `23 a TERM nobody answers hangs the run for ever` et `23 the grace is hard-coded`, tous deux `smart-zone.bats -f "killed after the grace"`. Aucun autre nom.

Les 8 entrées `43` rendent `ok` lancées seules, et les 7 entrées d'autres tickets réancrées aussi (`06` × 2, `08` × 1, `32` × 3, `41` × 1).

- **Contrainte posée par [63], livré le 05/09/2026 : la règle de ce ticket n'est
  plus une phrase, c'est une fonction.** « Le verdict prime sur l'événement » était
  écrite en prose ici, réécrite en prose dans `playthrough_close` par [11], et
  **inversée** dans `retro_run` — qui consultait `budget_refused` avant de lire un
  seul mot de ce que la session avait répondu. C'est le seul faux livré des quatre
  trouvailles de la passe du 05/09. Elle vit maintenant dans
  `budget_refused_silence` (`.claude/lib/budget.sh`), qui prend `VERDICT POSTURE` et
  n'est vraie que si la session n'a rien dit (`none` ou vide) **et** que la raison
  est un refus. Trois conséquences : un quatrième palier qui lit une réponse dans un
  flux **appelle cette fonction** au lieu de recopier l'ordre ; `lenses_refused_posture`
  ne pose plus la question du posture elle-même, donc l'entrée de mutation
  « 43 a stream that says nothing about quota is read as a refusal » a déménagé de
  `$LENSES_LIB` vers `$BUDGET` (elle nomme toujours `test/budget.bats`) ; et
  « 43 a lens that answered is read as refused all the same » est ré-ancrée sur
  l'argument passé (`budget_refused_silence none`) plutôt que sur la ligne
  `[ "$(lenses__verdict …)" = none ]`, qui n'existe plus. Les deux rejouées `ok`.
