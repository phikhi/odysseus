# 20 — Test de contrat contre le vrai `claude`

**What to build:** Le pont entre le fake `claude` et la réalité. Toute la suite pilote un shim écrit à la main : « vert » ne prouve aujourd'hui que la cohérence du pack avec nos propres hypothèses sur l'interface de Claude Code. Ce ticket ajoute un jeu d'assertions unique, appliqué à la fois à la sortie du fake et à celle du vrai binaire, exécuté à la demande (réseau + quota). Il attrape la dérive dans les deux sens : un shim qui ment, et une mise à jour de Claude Code qui change le contrat sous le pack.

**Blocked by:** None — can start immediately.

**Write-surface:** `test/contract-claude.bats`, `test/helpers/claude-contract.bash`, `test/run.sh`, `test/helpers/shims/claude`, `test/mutate.sh`, `.claude/lib/session.sh`, `.claude/loop.sh`, `test/smoke.bats`, `test/smart-zone.bats`, `test/helpers/harness.bash`, `README.md`, `docs/frontiere-de-confiance.md`

**Status:** resolved

- [x] Les assertions de contrat vivent dans un helper unique, appliqué sans duplication à la sortie du fake **et** à celle du vrai `claude`.
- [x] Sur le fake, elles tournent dans la suite par défaut : un shim qui s'écarte du contrat casse les tests tout de suite.
- [x] Sur le vrai binaire, elles ne tournent que si `RALPH_REAL_CLAUDE=1` (skip explicite sinon) : la suite par défaut reste hermétique, sans réseau ni quota.
- [x] Le run réel utilise les flags exacts du pack (`-p`, `--output-format stream-json`, `--verbose`, `--dangerously-skip-permissions`, `--model`) sur un prompt trivial, dans un tmpdir jetable hors du dépôt.
- [x] Les invariants vérifiés sont ceux dont la boucle dépend : sortie NDJSON une ligne par événement, dernière ligne `{"type":"result"…}`, champs `subtype` / `is_error` / `num_turns` / `total_cost_usd` présents et lisibles **par l'extracteur du pack lui-même**, exit code 0 sur succès.
- [x] Le prompt passé sur stdin est bien reçu par la session : le contrat le prouve en demandant un marqueur précis dans la réponse.
- [x] L'échec dit quoi corriger : soit le shim a divergé du réel, soit le pack s'appuie sur un champ qui n'existe plus.

## Comments

- **Le run réel du 25/07/2026 a déjà montré l'écart.** La boucle a broyé un ticket trivial de bout en bout contre le vrai `claude` (exit 0, fichier créé, ticket `resolved`, `turns=5 cost=0.0346` correctement extraits) : l'extracteur du pack lit bien le vrai format. Mais le flux, lui, ne ressemble pas à ce que le shim émet.

  | | shim actuel | `claude` réel (2.1.220, haiku) |
  |---|---|---|
  | événements | `system/init`, `assistant`, `result` | `system/init`, **`rate_limit_event`**, **`system/thinking_tokens` ×4**, `assistant` ×2, `result/success` |
  | clés du `result` | 8 | 21 — dont `stop_reason`, `terminal_reason`, `api_error_status`, `permission_denials`, `modelUsage` |

  Sans conséquence aujourd'hui (la boucle ne lit que la dernière ligne), mais [04] surveille le flux pour le seuil 150K et [08] veut y lire le budget : les deux seraient conçus contre une fiction. Le shim doit être réaligné sur une capture réelle, et c'est précisément ce que ce ticket doit rendre impossible à oublier.

- Une capture de référence du flux réel est facile à reproduire :
  `printf 'Reply with PONG and nothing else.\n' | claude -p --model haiku --output-format stream-json --verbose`

### Livraison, 29/07/2026

- **La moitié « réaligner le shim » que ce ticket attendait était déjà faite** — commit `f970e78`, 25/07 : séquence d'événements et 21 clés de `result`. Mais elle s'était arrêtée un cran trop tôt, et c'est la trouvaille du ticket : **les événements `assistant` du fake ne portaient aucun `message.usage`**. Or c'est exactement là que le filet smart-zone prend son signal sur le vrai binaire, *pendant* que la session tourne. Le `tokens=1200` que la suite journalisait venait de la dernière ligne `result` — un pic que le moniteur ne peut lire qu'une fois la session déjà terminée. Autrement dit le flux par défaut exerçait l'*analyse* du moniteur, jamais son *moment*.

  [04] n'était pas conçu contre une fiction pour autant, et c'était le point à vérifier : sondé contre la capture réelle, `monitor_context_tokens` somme correctement la forme réelle (`9 + 6495 + 17900 + 3 = 24407`, imbrication `cache_creation` non double-comptée), et `session_result_field` lit les 21 clés sans broncher. Ce qui manquait n'était pas la lecture, c'était le témoin.

- **Une faiblesse du moniteur que le contrat garde maintenant.** `monitor__int` ne distingue pas une clé *renommée* d'une clé *absente* : la somme sort simplement plus petite. Une release qui renommerait `cache_read_input_tokens` ferait sous-compter la fenêtre des ~18K du prompt système en cache — le filet tirerait tard, ou jamais — et **aucun test ne bougerait**, puisque tous utilisent des chiffres synthétiques à eux. Rien à corriger dans le moniteur (sans schéma, absent et renommé sont indistinguables) : le contrat vérifie désormais la présence des quatre clés, une par une, sur chaque événement `assistant`. Mutation `20 one of the four figures the monitor adds up` dans le tableau du test « teeth ».

- **`init.model` répond le modèle *résolu*, pas l'argument.** `--model haiku` revient en `claude-haiku-4-5-20251001`. Un commentaire de `smoke.bats` affirmait le contraire (« as the real one does ») ; le fake ne peut pas résoudre un alias, donc le contrat se contente d'exiger le champ non vide et le shim dit pourquoi. Rien dans le pack ne le lit.

- **`permissionMode` était codé en dur dans le shim.** Il est maintenant dérivé de l'argv. C'est ce qui donne des dents au contrôle : la mutation `20 the pack stops bypassing permissions` retire `--dangerously-skip-permissions` de `session_spawn` et fait rougir le contrat *sur le fake, dans la suite hermétique*. Avant, le pack aurait pu perdre le flag sans qu'un test bouge. Ligne ajoutée au tableau de `docs/frontiere-de-confiance.md`.

- **Écart de write-surface, et pourquoi.** L'AC exige que les champs soient lisibles « par l'extracteur du pack lui-même » : impossible tant que `loop_result_field` vit dans un script qui lance `loop_main` à la source. Il est devenu `session_result_field` dans `lib/session.sh` — le propriétaire de la forme du flux est celui qui spawne la session. `layering.bats` reste vert (la boucle appelle un lib, pas l'inverse). Le shim, `smoke.bats`, `smart-zone.bats` et `harness.bash` ont suivi : trois commentaires y affirmaient une fidélité que le flux n'avait pas.

- **Ce que le contrat ne vérifie pas, à dessein** :
  - **Pas de comptage exact de clés.** Une release qui *ajoute* un champ ne doit pas rougir. Seuls sont exigés les champs que le pack lit ou qu'un ticket s'est engagé à lire.
  - **Des ensembles, jamais des séquences.** L'ordre réel est `init`, `thinking_tokens`, `rate_limit_event`, `thinking_tokens` ×3, `assistant` ×2, `result` — pas celui que `harness.bash` décrivait (« right after init »). Le pack dépend du premier événement et du dernier ; rien entre les deux.
  - **`system/thinking_tokens` n'est pas dans le contrat.** Rien ne le lit, ni maintenant ni dans un ticket ouvert. Le test opt-in « same kinds of event » le compare quand même, en ensemble, parce qu'un *type* que le vrai émet et que le fake ignore est la prochaine fonctionnalité conçue contre une fiction.
  - **Aucune capture réelle commitée.** Un fixture de flux réel serait une deuxième chose à garder synchrone, et contient un id de session, un blob de signature et un coût réel. La commande de recapture est dans l'en-tête du shim.

- **Le test réel est model-dépendant par nature** : il demande un marqueur et le cherche dans la réponse (`contains`, pas égalité), sur un prompt trivial en haiku. C'est le prix de la seule assertion qui prouve que le prompt de stdin est arrivé.

- **Pièges rencontrés** :
  - **`test/mutate.sh` ne vérifiait pas la syntaxe des shims** — son `bash -n` filtre sur `*.sh|*.bash`, et les shims n'ont pas d'extension. Une mutation qui casse le shim rougit toute la suite et se lit `ok` : exactement la classe `BROKEN` que le fichier documente. Le filtre couvre maintenant `test/helpers/shims/*`.
  - **Un `skip` dans un helper appelé via `run` est un test qui passe en silence** : `run` évalue en substitution de commande, et `skip` y sort avec 0. Aucun contrôle du contrat ne skippe ; l'absence de `python3` dégrade en contrôle structurel et le dit (`note:`).
  - **Les douze cas du test « teeth » ont été relus un par un** avant de croire le vert, findings par findings : chacun sort exactement le finding annoncé, et seul « retirer l'événement `result` » en produit seize — tous cohérents. Deux cas envisagés ont été jetés parce qu'ils passaient pour la mauvaise raison : casser `input_tokens` en chaîne fait juste baisser la somme (d'où le contrôle par clé), et une édition trop large de `"usage":{…}` mangeait `modelUsage` au passage.
  - **La garde hermétique ne peut pas être mutée par le gate.** Retirer un garde `RALPH_REAL_CLAUDE` dans `mutate.sh` ferait dépenser du quota pendant le gate, ce que la garantie interdit précisément. Ce qui est muté, c'est le *scanner* (`contract_unguarded_real_spawns`), et le test plante lui-même une violation dans une copie — le token est écrit via un `printf '%s' real` pour que le scan ne se signale pas lui-même.

- **Pour les tickets voisins** (écrit aussi chez eux) : [08] a de quoi lire le budget in-band, avec deux détails ; [10] doit savoir que `usage` du `result` réel contient un tableau `iterations[]` dont la dernière entrée répète `input_tokens`/`output_tokens`, donc que sur cette ligne le moniteur lit la dernière itération et non les totaux ; [04] garde son trou de timeout de session, inchangé.

- **État à la livraison** : 183 tests verts (172 avant), 2 skips — les deux moitiés réelles, opt-in. 116 mutations rouges (106 avant), les 10 nouvelles relues une par une sur copie avant de croire le vert. Le fichier tourne aussi sous `bats-core` (11/11), l'interchangeabilité que le pack promet. Deux runs réels contre `claude 2.1.220` / haiku, ~1,6 ¢ notionnels chacun.
- **Piège rencontré en livrant, à connaître** : `test/mutate.sh` tué par un `KILL` laisse une mutation plantée dans l'arbre de travail — son `trap` ne s'exécute qu'entre deux commandes, et il passe l'essentiel de son temps bloqué dans `bash test/run.sh`. Un `gate.sh` amputé de son chien de garde est resté dans le dépôt, dans un fichier que personne n'avait édité. Deux règles écrites dans son en-tête : vérifier `git status` après une interruption, et ne jamais éditer un fichier pendant qu'il tourne.
