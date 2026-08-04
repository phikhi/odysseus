# 08 — Budget d'usage + gate de spawn proactif + classifieur

**What to build:** La surveillance du budget d'usage et son intégration dans la boucle : gate de spawn proactif **avant** chaque session, classifieur budget (un exit non-zéro est testé « budget ? » avant « échec »), pause/reprise sur la fenêtre de session.

**Blocked by:** 07

**Write-surface:** `.claude/lib/budget.sh`, `test/budget.bats`

**Status:** ready-for-agent

- [ ] La boucle interroge `GET /api/oauth/usage` (`User-Agent` obligatoire, cache 180 s) et lit `five_hour`, `seven_day`, `seven_day_opus`.
- [ ] Seuils asymétriques : `THRESH_5H` (agressif) et `THRESH_WEEK` (conservateur) ; le spawn est gated **avant** de lancer la session.
- [ ] Un dépassement de la fenêtre de session déclenche un `sleep` in-process jusqu'à `resets_at`, puis la boucle reprend.
- [ ] Le classifieur teste tout exit non-zéro « budget ? » avant de le compter comme échec ; une pause budget n'incrémente jamais `Failures:`.
- [ ] Sous les seuils, aucun impact sur le happy-path.

## Comments

- **Découverte du run réel (25/07/2026) : le flux stream-json porte lui-même un signal de budget.** Une session réelle émet, juste après `system/init`, un événement in-band :

  ```json
  {"type":"rate_limit_event","rate_limit_info":{"status":"allowed","resetsAt":1784979600,
   "rateLimitType":"five_hour","overageStatus":"rejected","isUsingOverage":false}}
  ```

  C'est la même information que `GET /api/oauth/usage` (type de fenêtre, statut, reset en epoch), mais **fournie par le binaire lui-même** — pas d'endpoint non documenté, pas de `User-Agent` bricolé, pas de 429 à gérer, pas de cache 180 s. À exploiter comme source primaire là où c'est possible.

  La limite reste : ce signal est *réactif* (on l'apprend pendant une session), alors que le gate de spawn est *proactif* (il faut décider avant de lancer). Les deux se complètent donc plutôt qu'ils ne se remplacent — l'endpoint pour décider de spawner, `rate_limit_event` pour corriger l'estimation à coût nul et pour classifier un exit non-zéro sans requête supplémentaire. À trancher au moment de l'implémentation ; les AC ci-dessus restent le contrat.

- **Autres champs utiles observés sur la ligne `result`** (pour [07] et [19], non exhaustif) : `stop_reason`, `terminal_reason`, `api_error_status`, `permission_denials`, `modelUsage`, `usage`.

- **Ordre de grandeur du coût**, mesuré avec `haiku` : 0,035 $ pour un ticket trivial en 5 tours, 0,016 $ pour un aller-retour d'un tour. Le plancher par itération n'est donc pas négligeable — utile pour calibrer les seuils.

- **Contrainte posée par [07] : où le classifieur s'insère, et ce qu'il ne doit pas déclencher.** La politique d'échec est dans `.claude/lib/failures.sh`. `failures_classify OUTCOME [SCOPE_CLASS]` rend aujourd'hui `too-big` (limite molle franchie), `contract`, `gate-red` ou `crash` — le cas par défaut (`crash`) est exactement celui que le classifieur budget doit intercepter en premier, avec une classe `budget`. Ce qu'une pause budget ne doit **pas** faire, et que fait tout le reste de `failures_handle` : incrémenter `Failures:`, rollbacker l'arbre, escalader. Un exit non-zéro dû au quota n'est pas une tentative ratée du ticket.
- Le signal in-band est déjà lisible sans requête : la boucle capture le flux complet dans `.scratch/<feature>/.session.$$.jsonl`, que `loop_result_field` lit déjà par `grep`+`sed`. Le `rate_limit_event` y est.
- Attention : `loop_spawn` (extrait de `loop_spawn_session` par [07]) est aussi utilisé par les sessions de **re-slice**. Un gate de spawn proactif posé dans la boucle ne les couvre pas ; à décider si une session de planification doit être gatée par le budget elle aussi.
- Renommage à connaître : le spawn a quitté `loop.sh` pour `.claude/lib/session.sh` (`session_spawn`), parce qu'un lib qui remonte dans la boucle inverse les couches — refusé désormais par `test/layering.bats`. Un gate de spawn proactif se pose donc soit dans `loop.sh` avant `loop_spawn_session`, soit dans `session_spawn` si les sessions de planification doivent être gatées elles aussi.
- **Vérifié contre le vrai binaire par [20] (29/07/2026), avec deux détails.** Le contrat exige désormais `rate_limit_event` avec `status`, `resetsAt` et `rateLimitType` — sur le fake à chaque run, sur le vrai binaire sous `RALPH_REAL_CLAUDE=1`. Le signal est donc gardé, pas supposé. Deux choses que la capture du 29/07 ajoute à celle du 25/07 : l'événement arrive **troisième**, après `init` *et* un premier `system/thinking_tokens` (pas « juste après init » — ne rien faire dépendre de la position), et `rate_limit_info` peut porter une clé de plus, `overageDisabledReason` (ici `group_zero_credit_limit`). `resetsAt` est bien un epoch. Le shim est scriptable par `claude_rate_limit`.
- Renommage à connaître, corollaire du précédent : l'extracteur de la ligne `result` s'appelle `session_result_field` et vit dans `.claude/lib/session.sh` — il a quitté `loop.sh` en [20] pour que le test de contrat puisse le pointer sur la sortie du vrai binaire.

- **Contrainte posée par [06], livré le 30/07/2026 : une itération ne coûte plus une session.** Le palier de jugement du gate spawne un `claude` par lentille déclenchée, dans une phase à part, après les branches objectives. Le compte par itération verte est donc `1 + n` : deux lentilles au minimum (Standards, Spec, toujours actives), jusqu'à cinq si le ticket est tagué ou si sa write-surface rencontre `SECURITY_PATHS` / `VISIBLE_PATHS` — et une surface `*` les déclenche toutes. Trois conséquences pour ce ticket :

  - **Le seuil de budget doit être franchissable avant le gate, pas seulement avant la session.** Un run qui décide « il reste de quoi faire une itération » en comptant une session sous-estime d'un facteur trois à six. Le pire cas est le plus cher : itération verte, donc phase de jugement jouée en entier.
  - **Une phase de jugement sautée est du quota économisé, et c'est déjà implémenté.** Sur un gate objectif rouge, aucune lentille ne tourne (le run le dit : `the review lenses did not run: the objective checks are already red`). Le classifieur peut compter là-dessus : le coût d'une itération rouge n'a pas bougé.
  - **`LENSES` est le levier, et il est dans la config scellée.** Si le budget doit être réduit sans arrêter le run, narrower `LENSES` est le seul réglage prévu pour ça — mais une session ne peut pas le faire, et un humain qui le fait éteint un palier du gate, ce que la boucle annonce à chaque itération.

- **Contrainte posée par [23], livré le 31/07/2026 : deux issues qui coûtent du quota sans rien livrer, et que le classifieur ne doit pas confondre avec une panne de budget.** Une session coupée par `SESSION_STALL_TIMEOUT` ou `SESSION_TIMEOUT` a brûlé tout ce qu'elle avait consommé jusque-là — jusqu'à trois heures de mur, au défaut livré — pour un ticket qui repart à zéro en session fraîche. Deux choses pour ce ticket. D'abord le compte : une itération vaut `1 + n` sessions (note ci-dessus), et il faut ajouter que chacune de ces sessions peut être **retryée jusqu'à `RETRY_N` fois** sur un timeout sans qu'aucun gate ne tourne, donc le pire cas d'un ticket toxique est plus cher que le pire cas d'un ticket rouge. Ensuite la classification : le classifieur budget se branche *devant* `failures_classify` et teste « budget ? » sur un exit non-zéro — or une session terminée par un délai répond 143, ou 0 si elle a piégé le TERM, et sa vraie raison est dans `RALPH_SESSION_TIMEOUT` et pas dans son statut. Un classifieur qui lirait le code de sortie seul rangerait un timeout sous « budget épuisé » (ou l'inverse) ; la question à poser en premier est « le moniteur a-t-il coupé cette session ? », avant toute lecture d'exit code.

- **Contrainte posée par la passe transversale du 03/08/2026 : une issue de plus, et elle va dans le bon sens pour le budget.** [35] refuse une itération dont le gate ne voit changer aucun fichier, et le refus est **déterministe et avant le fan** : les lentilles de cette itération ne sont donc pas dépensées. Pour ce ticket ça vaut deux choses. Le compte d'abord — une itération qui n'a rien livré coûte `1` session et non `1 + n`, ce qui n'est vrai qu'après [35] : aujourd'hui elle coûte `1 + n` **et** est marquée `resolved`, donc elle disparaît du compte des retries en plus de dépenser les lentilles. Et la classification ensuite : « rien à juger » n'est ni une panne de budget ni un échec d'implémentation, donc elle passe devant le classifieur budget sans le concerner — à condition qu'elle ne soit pas déduite d'un code de sortie, la session ayant répondu normalement.

- **[35] livré le 04/08/2026 : le vocabulaire final, et ce qu'il économise.** Le refus est `gate__nothing_delivered`, appelé dans `gate_run` **avant le fan** : ni `TEST_CMD`, ni `TYPECHECK_CMD`, ni le scope-guard, ni une seule lentille ne tournent. Une itération qui n'a rien livré coûte donc exactement **une** session, pas `1 + n`. Elle porte l'outcome `nothing-delivered` dans `run.log`, la classe `nothing-delivered` dans `failures_classify` (retryable, jamais re-slicée) et la raison d'escalade du même nom au plafond. Pour le classifieur budget : la classe est déduite d'une variable posée par le gate (`RALPH_GATE_NOTHING_DELIVERED`) et jamais d'un code de sortie — la session a répondu 0 — donc elle passe devant « budget ? » sans le concerner, exactement comme le timeout de [23].
