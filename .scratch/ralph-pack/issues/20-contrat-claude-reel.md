# 20 — Test de contrat contre le vrai `claude`

**What to build:** Le pont entre le fake `claude` et la réalité. Toute la suite pilote un shim écrit à la main : « vert » ne prouve aujourd'hui que la cohérence du pack avec nos propres hypothèses sur l'interface de Claude Code. Ce ticket ajoute un jeu d'assertions unique, appliqué à la fois à la sortie du fake et à celle du vrai binaire, exécuté à la demande (réseau + quota). Il attrape la dérive dans les deux sens : un shim qui ment, et une mise à jour de Claude Code qui change le contrat sous le pack.

**Blocked by:** None — can start immediately.

**Write-surface:** `test/contract-claude.bats`, `test/helpers/claude-contract.bash`, `test/run.sh`

**Status:** ready-for-agent

- [ ] Les assertions de contrat vivent dans un helper unique, appliqué sans duplication à la sortie du fake **et** à celle du vrai `claude`.
- [ ] Sur le fake, elles tournent dans la suite par défaut : un shim qui s'écarte du contrat casse les tests tout de suite.
- [ ] Sur le vrai binaire, elles ne tournent que si `RALPH_REAL_CLAUDE=1` (skip explicite sinon) : la suite par défaut reste hermétique, sans réseau ni quota.
- [ ] Le run réel utilise les flags exacts du pack (`-p`, `--output-format stream-json`, `--verbose`, `--dangerously-skip-permissions`, `--model`) sur un prompt trivial, dans un tmpdir jetable hors du dépôt.
- [ ] Les invariants vérifiés sont ceux dont la boucle dépend : sortie NDJSON une ligne par événement, dernière ligne `{"type":"result"…}`, champs `subtype` / `is_error` / `num_turns` / `total_cost_usd` présents et lisibles **par l'extracteur du pack lui-même**, exit code 0 sur succès.
- [ ] Le prompt passé sur stdin est bien reçu par la session : le contrat le prouve en demandant un marqueur précis dans la réponse.
- [ ] L'échec dit quoi corriger : soit le shim a divergé du réel, soit le pack s'appuie sur un champ qui n'existe plus.

## Comments

- **Le run réel du 25/07/2026 a déjà montré l'écart.** La boucle a broyé un ticket trivial de bout en bout contre le vrai `claude` (exit 0, fichier créé, ticket `resolved`, `turns=5 cost=0.0346` correctement extraits) : l'extracteur du pack lit bien le vrai format. Mais le flux, lui, ne ressemble pas à ce que le shim émet.

  | | shim actuel | `claude` réel (2.1.220, haiku) |
  |---|---|---|
  | événements | `system/init`, `assistant`, `result` | `system/init`, **`rate_limit_event`**, **`system/thinking_tokens` ×4**, `assistant` ×2, `result/success` |
  | clés du `result` | 8 | 21 — dont `stop_reason`, `terminal_reason`, `api_error_status`, `permission_denials`, `modelUsage` |

  Sans conséquence aujourd'hui (la boucle ne lit que la dernière ligne), mais [04] surveille le flux pour le seuil 150K et [08] veut y lire le budget : les deux seraient conçus contre une fiction. Le shim doit être réaligné sur une capture réelle, et c'est précisément ce que ce ticket doit rendre impossible à oublier.

- Une capture de référence du flux réel est facile à reproduire :
  `printf 'Reply with PONG and nothing else.\n' | claude -p --model haiku --output-format stream-json --verbose`
