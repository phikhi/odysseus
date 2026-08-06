# 08 — Budget d'usage + gate de spawn proactif + classifieur

**What to build:** La surveillance du budget d'usage et son intégration dans la boucle : gate de spawn proactif **avant** chaque session, classifieur budget (un exit non-zéro est testé « budget ? » avant « échec »), pause/reprise sur la fenêtre de session.

**Blocked by:** 07

**Write-surface:** `.claude/lib/budget.sh`, `test/budget.bats`

**Status:** resolved

- [x] La boucle interroge `GET /api/oauth/usage` (`User-Agent` obligatoire, cache 180 s) et lit `five_hour`, `seven_day`, `seven_day_opus`.
- [x] Seuils asymétriques : `THRESH_5H` (agressif) et `THRESH_WEEK` (conservateur) ; le spawn est gated **avant** de lancer la session.
- [x] Un dépassement de la fenêtre de session déclenche un `sleep` in-process jusqu'à `resets_at`, puis la boucle reprend.
- [x] Le classifieur teste tout exit non-zéro « budget ? » avant de le compter comme échec ; une pause budget n'incrémente jamais `Failures:`.
- [x] Sous les seuils, aucun impact sur le happy-path.

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

## Livré le 05/08/2026

`.claude/lib/budget.sh` : le lecteur d'endpoint, le lecteur in-band, la décision, la pause et le préflight. `test/budget.bats` : 25 tests dont un opt-in (`RALPH_REAL_USAGE=1`). 36 entrées dans `test/mutate.sh`. Wiring dans `loop.sh` (gate de spawn avant le claim, classifieur après la session, code de sortie 6) et dans `failures.sh` (classe `budget`).

### La question de la frontière de confiance, posée avant d'écrire

*Qu'est-ce qu'une session peut écrire que rien ne vérifie ?* Le `rate_limit_event` du flux — et c'est la découverte du 25/07 qui rendait ce ticket facile qui l'a rendu délicat. Le flux vit dans `.scratch/<feature>/.session.$$.jsonl`, que le tableau de frontière liste explicitement comme écrivable par la session jugée (c'est pourquoi [23] a payé un second délai).

Les deux directions n'ont pas le même prix, et c'est ce calcul qui a écrit le design :

- forger « il reste du quota » n'achète rien : l'API refuse quand même, et le classifieur réactif ramasse ;
- forger « je suis bloqué » achète **une nuit entière** — un `resetsAt` dans dix ans et le run dort jusqu'au matin sans une ligne à lire.

D'où : l'endpoint décide dès qu'il répond (il est hors de portée de la session), le signal in-band ne peut que rendre le run *plus* prudent, et ce qu'un signal forgé coûte est borné trois fois par des choses qu'aucune session n'écrit — `BUDGET_MAX_PAUSE` sur une pause, la règle « deux pauses consécutives sans session entre elles arrêtent le run », et `STERILE_K` que la boucle compte elle-même sur le chemin réactif.

### Décisions, et ce qu'elles coûtent

**Le gate de spawn est dans `loop.sh`, avant le claim.** Le ticket laissait la question ouverte (`loop.sh` ou `session_spawn`, et faut-il gater les sessions de planification). Réponse : `loop.sh`, et **ni le re-slice ni les lentilles ne sont gatés**. Deux raisons, et aucune n'est esthétique. Gater dans `session_spawn` ferait dormir cinq heures *à l'intérieur d'une branche de gate* sous `GATE_TIMEOUT`, ou au milieu du chemin d'échec avec un ticket claimé et un arbre en attente de rollback. Et avant le claim plutôt qu'après : une pause de cinq heures avec un claim en main le ferait dépasser `CLAIM_TTL` (5400 s) et voler par le balayage de [12] — le run se ferait prendre son propre ticket.

**Le cache de 180 s est en mémoire du run, pas sur le disque.** Un fichier de cache serait un fichier que la session écrit : sous `.scratch/` directement, dans `$TMPDIR` aussi sûrement que le témoin d'ignore que [30] doit refuser quand une session le détruit. Un run est un process, la boucle appelle depuis son propre shell, et 180 s de fraîcheur *dans un run* est exactement ce que le cache devait donner. Le prix, assumé : deux runs sur deux dépôts demandent deux fois.

**Le rollback a lieu sur une pause budget, contre le commentaire de [07].** Ce ticket portait « ce qu'une pause budget ne doit pas faire : incrémenter `Failures:`, rollbacker l'arbre, escalader ». Deux des trois tiennent toujours ; le rollback non, parce que [34] et [35] sont passés entre-temps : ce qu'une itération laisse dans l'arbre devient la **base** de la suivante, donc ne pas défaire une session refusée en vol blanchit ses écritures au tour d'après. Le ticket revient à une frontière, pas à un arbre sale.

**« Budget ? » est posé devant ce que personne n'a jugé, et derrière ce que le pack a mesuré.** Devant : `crash` et `nothing-delivered`. Un **gate rouge reste rouge** — c'est la preuve que quelque chose a été regardé et trouvé faux, et le pardonner rendrait un gate rouge gratuit pour toute session prête à écrire une ligne dans son propre flux. Derrière : la limite molle et les deux délais de [23], parce qu'une mesure ne se fait pas écraser par une affirmation lue dans le flux du mesuré. Poser la question devant `nothing-delivered` est **plus large que l'AC** (« tout exit non-zéro »), et délibéré : une session refusée n'écrit rien, donc [35] lui facturerait un retry et enverrait un humain chercher « pourquoi ce ticket fait qu'une session ne fait rien ».

**Un chiffre illisible n'est jamais zéro.** Une fenêtre que le parseur ne sait pas lire n'est pas surveillée et le run le dit ; un `utilization` absent pris pour 0 % serait le faux vert habituel, avec une facture au bout. Le parseur est tolérant sur deux choses seulement, parce que le schéma n'est pas documenté : la clé de reset (`resets_at` ou `resetsAt`, epoch ou ISO) et l'unité (`[0,1]` ou `(1,100]`, `1` lu comme le ratio — le côté prudent de la seule valeur ambiguë).

**Le mur hebdo arrête le run avec un code à lui (6).** Pas de `sleep` de plusieurs jours dans un process : c'est ce que le successeur one-shot de [09] existe pour remplacer. 6 et pas 4, parce que c'est le seul arrêt qui se lève tout seul à un instant connu — voir la contrainte écrite dans [09].

**La limite opus n'est surveillée que par un run qui la dépense.** `MODEL` contient `opus` ou non ; gater une nuit haiku sur une limite qu'elle ne touche pas serait un refus sur lequel personne ne peut agir.

**`BUDGET_CHECK=on` par défaut, et pas de sonde réseau au préflight.** La suite est hermétique et un préflight qui appelle le réseau ne l'est plus. Un endpoint illisible ne refuse donc pas le run : il le dit une fois (`flying on the in-band signal alone`) et la nuit tourne sur le signal réactif seul. C'est un cran plus faible que `TEST_CMD` vide — un budget non mesuré ne produit pas de faux vert, il produit une facture — et le prix est écrit dans le tableau de frontière.

### Ce qui n'est vérifié par rien, et qui doit le savoir

**La moitié endpoint n'a jamais parlé à l'endpoint.** La suite est hermétique, l'endpoint n'est pas documenté, le token appartient à l'utilisateur (`USAGE_TOKEN_CMD`, vide par défaut) : la charge utile que les tests lisent a été **inventée dans ce dépôt**. `RALPH_REAL_USAGE=1 USAGE_TOKEN_CMD='…' test/run.sh test/budget.bats` lance la seule sonde qui pointe `budget__request` + `budget__window` sur la vraie chose et refuse `UNREADABLE` — même posture que `RALPH_REAL_CLAUDE=1` pour le flux de session ([20]). Tant qu'un humain ne l'a pas lancée, « ce pack sait lire cette charge utile » est une hypothèse. Propriétaire de la suite : [19], dont l'AC de préconditions nomme déjà l'endpoint d'usage.

**Une session refusée est payée une fois** quand l'endpoint est illisible : le signal réactif n'arrive qu'après le démarrage. C'est le cas nominal d'une installation sans token.

### Sondes de run réel, 05/08/2026

- **Une session refusée en vol laisse la moitié d'un fichier** : le rollback le retire, l'itération suivante ne l'adopte pas (test dédié, et l'entrée de mutation qui débranche le rollback pour la classe `budget` fait rougir).
- **Une session refusée qui élargit `.git/info/exclude`** : la remise de [32] tombe aussi sur cette classe — la liste a été relue dans le `case` de `failures_classify` au lieu d'être devinée.
- **Une pause interrompue par un `kill -TERM`** rend la main en moins d'une seconde : la pause est en pas d'une seconde, parce que `sleep 3600` retiendrait le trap une heure ([25]).
- **Le cache et la pause** : le run se réveille, relit l'endpoint (et pas le corps mesuré avant le reset), trouve la fenêtre refaite et broie.

### Écarts de write-surface

Le ticket déclarait `.claude/lib/budget.sh` et `test/budget.bats`. Sept fichiers de plus :

- `.claude/loop.sh` : le gate de spawn, le classifieur, le code de sortie 6, la lecture de la posture avant que le flux soit supprimé.
- `.claude/lib/failures.sh` : la classe `budget` dans `failures_classify`, son arm dans `failures_handle`, sa ligne de disposition, et son entrée dans la liste de remise des règles d'ignore.
- `.claude/ralph.config.sh.example` : cinq clés de plus (`BUDGET_CHECK`, `USAGE_URL`, `USAGE_TOKEN_CMD`, `USAGE_CACHE_TTL`, `BUDGET_MAX_PAUSE`) et la réécriture de la section.
- `test/helpers/shims/curl` : une réponse par appel quand plusieurs sont installées — sans ça, aucun test ne peut faire *traverser* un mur à un run, seulement l'y faire buter.
- `test/helpers/harness.bash` : `usage_respond` variadique, `curl_call_count`.
- `test/smoke.bats` : les cinq clés dans la liste de surface, **plus la seconde direction de l'assertion** (voir ci-dessous).
- `test/mutate.sh`, `docs/frontiere-de-confiance.md`.

### Trouvé en passant : `test/smoke.bats` ne voyait qu'un sens

La liste de clés de « the example config declares the whole configuration surface » est écrite à la main, et son propre commentaire raconte que quatre clés de [24] et [06] y avaient manqué. **[17] en a ajouté trois de plus** — `LANG_CHECK_MIN_HITS`, `LANG_PROSE_PATHS`, `LANG_EXEMPT_PATHS` — et le test a continué d'annoncer une surface complète : il ne vérifiait que « chaque clé de ma liste est déclarée », jamais l'inverse. Les trois sont ajoutées et la seconde assertion existe maintenant, avec son entrée de mutation. Leçon dans `docs/frontiere-de-confiance.md`.

### Ce que la passe de mutation complète a trouvé, et qu'aucune passe filtrée n'aurait vu

Les entrées de ce ticket sont revenues `ok` lancées seules. La passe **entière** a rendu 4 `not ok`, tous causés par ce ticket et aucun dans ses propres entrées :

- **1 `VACUOUS` sur une entrée de [03]**, `03 the ticket is not given back after a failure`, dont l'expression est `s/    tracker_unclaim "$ticket"\n//` — sans `/g`, donc **la première occurrence**. La classe `budget` rend elle aussi son ticket, trois lignes plus haut : depuis ce ticket, l'entrée retirait cet `unclaim`-là et laissait intact celui qu'elle nommait. Le symptôme est un `VACUOUS` sur un test parfaitement sain, c'est-à-dire l'accusation exactement inversée — et la tentation est de réécrire le test. C'est la **troisième** fois que ce piège se referme dans ce dépôt (deux entrées de [29], celle-ci), et l'en-tête de `test/mutate.sh` le décrit déjà mot pour mot. Corrigé en ancrant sur le `else` qui la précède, et la jumelle manquante a été ajoutée : `08 a refused ticket is left claimed`.
- **3 `DRIFTED` sur les entrées de [32]**, qui ancraient toutes sur `crash | timeout) failures__ignore_frontier` — devenu `crash | timeout | budget)`. C'est le bon comportement de `DRIFTED` : la ligne qui portait la garantie a bougé, et il fallait revérifier qu'elle la porte encore. Elle la porte, et une classe de plus.

La règle qui en sort, pour le prochain ticket qui ajoute une classe ou une branche à `failures_handle` : **ajouter une ligne qui ressemble à une ligne déjà ancrée par une entrée de mutation, c'est détourner cette entrée en silence.** `rtk grep` sur la ligne qu'on ajoute, dans `test/mutate.sh`, coûte dix secondes.

### Vert au merge

`bash test/run.sh` : **363 tests, 0 failures, 6 skipped** (338 → 363 ; le sixième `skip` est la sonde `RALPH_REAL_USAGE=1`). `bash test/mutate.sh` : **327 mutations, 0 not ok**, la passe rejouée en entier après correction des quatre entrées que ce ticket avait détournées. La bascule instable de [38] n'est pas apparue sur ces deux passes ; elle reste ouverte.
