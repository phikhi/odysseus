# 43 — Une lentille refusée pour quota est comptée comme un échec d'implémentation

**What to build:** Faire que l'abonnement qui s'épuise pendant la phase de lentilles coûte la même chose que quand il s'épuise pendant la session de livraison : rien. [08] a écrit un classifieur qui reconnaît un refus de quota et rend le ticket à la frontière *sans consommer de retry*, parce qu'« une session refusée n'est pas une tentative ». Il lit `rate_limit_event` dans le flux de la **session de livraison**, et il n'est posé que devant `failed` et `nothing-delivered`. Une lentille refusée ne produit ni l'un ni l'autre : elle produit un verdict manquant, donc une branche rouge, donc `gate-red` — la classe que [08] refuse délibérément de pardonner. Le ticket est facturé, retenté, et à `RETRY_N` escaladé `failed-impl`, c'est-à-dire avec l'affirmation qu'une implémentation a été jugée et trouvée fausse. Une itération vaut `1 + n` sessions ([06]) et `MAX_PARALLEL` multiplie encore ([13]) : la majorité des sessions d'un run sont du côté où un refus de quota se lit comme une faute du ticket.

**Blocked by:** None

**Write-surface:** `.claude/lib/lenses.sh`, `.claude/lib/gate.sh`, `.claude/lib/budget.sh`, `.claude/lib/failures.sh`, `test/budget.bats`, `test/lenses.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

- [ ] Une lentille dont le flux porte un `rate_limit_event` non `allowed` et qui ne rend pas de verdict ne fait pas escalader le ticket en `failed-impl`. Le ticket revient à la frontière sans retry consommé, et le run dit que c'était le quota — pas « la lentille a refusé ».
- [ ] Ça reste vrai **sans** rendre un gate rouge gratuit : la distinction à tenir est « aucun verdict parce que l'API a refusé la session » contre « aucun verdict parce que la lentille est morte, a été tuée pour contexte ou a répondu de la prose ». Les trois derniers restent rouges ([06] : le silence n'achète pas de vert). Écrire pourquoi ce n'est pas la porte que [08] a fermée devant `gate-red`.
- [ ] Le signal remonte au pilote : un run dont les lentilles se font refuser doit finir par pauser ou s'arrêter sur le budget, au lieu de brûler `RETRY_N` × `1 + n` sessions par ticket contre un mur. Aujourd'hui `budget_stream_posture` n'est appelé que sur le flux de livraison, et `budget_` n'apparaît nulle part dans `gate.sh` ni `lenses.sh`.
- [ ] La frontière de confiance est respectée telle que [08] l'a posée : le flux d'une lentille est écrit par une session, donc le signal ne peut rendre le run que **plus** prudent, jamais moins. Un `rate_limit_event` forgé dans un flux de lentille ne doit pas pouvoir acheter un vert ni annuler un rouge mérité — au mieux rendre le ticket sans le facturer, ce qui est déjà borné par `STERILE_K` et `ITER_CAP`.
- [ ] Le témoin appairé : le même événement dans le flux de la session de livraison doit rester traité comme il l'est aujourd'hui (`budget-pause`, rendu sans retry), sinon le test ne mesure pas la différence entre les deux moitiés.
- [ ] La ligne « Une panne de quota ne coûte pas un retry au ticket » de `docs/frontiere-de-confiance.md` cesse de dire « les issues où rien n'a été jugé » sans dire que la phase de lentilles n'en fait pas partie.

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
