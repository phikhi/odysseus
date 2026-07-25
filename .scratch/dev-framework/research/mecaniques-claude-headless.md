# Mécaniques Claude Code headless pour une boucle bash ("ralph loop")

> Recherche menée contre les sources primaires (doc officielle `code.claude.com/docs`, `claude --help` local en v2.1.x). Chaque affirmation cite sa source. Date : 2026-07-23.

## Résumé exécutif (actionnable)

- **Une session neuve par tâche = simplement `claude -p "<prompt>"` sans `--continue` ni `--resume`.** Chaque invocation `claude -p` démarre une session isolée ; le contexte conversationnel n'est PAS repris tant qu'on ne passe pas explicitement `--continue`/`--resume`. Pour une "ralph loop", ne jamais passer ces deux flags → contexte frais garanti à chaque tour. (Source : [headless](https://code.claude.com/docs/en/headless), [sessions](https://code.claude.com/docs/en/sessions))
- **Squelette de boucle** : `claude -p "$PROMPT" --output-format json --permission-mode dontAsk --allowedTools "..." --model opus`, puis parser la sortie avec `jq`. Injecter le contexte d'UNE tâche via l'argument prompt, un pipe stdin (`cat ticket.md | claude -p '...'`), des chemins de fichiers cités dans le prompt, et `--append-system-prompt` pour le rôle. (Source : [headless](https://code.claude.com/docs/en/headless))
- **Sortie structurée** : `--output-format json` renvoie un objet unique avec `result`, `session_id`, `is_error`, `num_turns`, `total_cost_usd`, `usage` et `modelUsage` (coût/tokens par modèle) → budget mesurable par run. `stream-json` = un événement JSON par ligne (NDJSON), dernière ligne = message `result`. (Source : [headless](https://code.claude.com/docs/en/headless), [agent-sdk/typescript](https://code.claude.com/docs/en/agent-sdk/typescript))
- **Succès/échec** : se fier au champ **`is_error`** de la sortie JSON (`false`=succès, `true`=échec) plutôt qu'au seul code retour. Le code de sortie standard (0/non-zéro) existe mais Anthropic ne publie PAS de table exhaustive des codes ; seuls quelques cas sont documentés (143 = SIGTERM, 137 = OOM, `--max-turns` sort en erreur). (Source : [headless](https://code.claude.com/docs/en/headless), [errors](https://code.claude.com/docs/en/errors))
- **Reproductibilité CI** : ajouter `--bare` pour ignorer l'auto-découverte (hooks, skills, plugins, MCP, mémoire, CLAUDE.md d'un collègue) et n'avoir que ce qu'on passe explicitement en flags — recommandé pour scripts/CI. Optionnel : `--max-budget-usd` pour plafonner la dépense, `--no-session-persistence` pour ne rien écrire sur disque. (Source : [headless](https://code.claude.com/docs/en/headless), [cli-reference](https://code.claude.com/docs/en/cli-reference))

---

## 1. Invocation headless

### Flag `-p` / `--print`
« Add the `-p` (or `--print`) flag to any `claude` command to run it non-interactively. » Toutes les options CLI fonctionnent avec `-p`. (Source : [headless](https://code.claude.com/docs/en/headless))

Le `claude --help` local le confirme : « starts an interactive session by default, use `-p`/`--print` for non-interactive output » ; `-p, --print : Print response and exit (useful for pipes) ». Note importante du help : en mode non-interactif (via `-p`, ou stdout non-TTY), le dialogue de confiance du workspace est ignoré et les fichiers de settings invalides sont silencieusement ignorés — à n'utiliser que dans des répertoires de confiance.

### Passer le prompt : argument, stdin, heredoc
- **Argument positionnel** : `claude -p "What does the auth module do?"`. (Source : [headless](https://code.claude.com/docs/en/headless))
- **stdin / pipe** : « Non-interactive mode reads stdin, so you can pipe data in and redirect the response out like any other command-line tool. » Exemple : `cat build-error.txt | claude -p 'concisely explain the root cause of this build error' > output.txt`. Le contenu piché est combiné au prompt fourni en argument. (Source : [headless](https://code.claude.com/docs/en/headless))
- **heredoc** : c'est une source stdin comme une autre, donc supporté par le même mécanisme (non nommé explicitement "heredoc" dans la doc, mais c'est du stdin standard).
- **Limite stdin** : depuis v2.1.128 le stdin piché est plafonné à **10 Mo** ; au-delà, `claude` sort avec un statut non-zéro et une erreur claire → écrire le contenu dans un fichier et référencer le chemin dans le prompt. (Source : [headless](https://code.claude.com/docs/en/headless))
- Si Claude ne peut pas lire stdin, il émet un avertissement sur stderr et continue avec le prompt de la ligne de commande. (Source : [headless](https://code.claude.com/docs/en/headless))

### `--output-format` (text / json / stream-json)
« Use `--output-format` to control how responses are returned : `text` (default) plain text ; `json` structured JSON with result, session ID, and metadata ; `stream-json` newline-delimited JSON for real-time streaming. » (Source : [headless](https://code.claude.com/docs/en/headless)) Détails de schéma en section 3.

### `--append-system-prompt` (et variantes)
« Use `--append-system-prompt` to add instructions while keeping Claude Code's default behavior. » Exemple : `gh pr diff "$1" | claude -p --append-system-prompt "You are a security engineer. Review for vulnerabilities." --output-format json`. Variantes documentées : `--append-system-prompt-file <file>` (append depuis fichier), `--system-prompt <text>` / `--system-prompt-file <file>` (remplacent entièrement le prompt système par défaut). (Source : [headless](https://code.claude.com/docs/en/headless), [cli-reference](https://code.claude.com/docs/en/cli-reference))

### `--allowedTools` / `--disallowedTools`
- `--allowedTools` (alias `--allowed-tools`) : « let Claude use certain tools without prompting ». Exemple : `claude -p "Run the test suite and fix any failures" --allowedTools "Bash,Read,Edit"`. Syntaxe de règles de permission ; ex. `Bash(git diff *)` (le ` *` final active le préfixe). (Source : [headless](https://code.claude.com/docs/en/headless))
- `--disallowedTools` (alias `--disallowed-tools`) : règles de refus. Un nom nu retire l'outil du contexte (`"Edit"`, `"*"`, `"mcp__*"`) ; une règle scopée (`Bash(rm *)`) laisse l'outil disponible et ne refuse que les appels correspondants. (Source : [cli-reference](https://code.claude.com/docs/en/cli-reference))
- À distinguer de `--tools` qui restreint l'ensemble d'outils *disponibles* (`--tools "Bash,Edit,Read"`, `""` pour tout désactiver, `"default"` pour tout). (Source : [cli-reference](https://code.claude.com/docs/en/cli-reference))

### `--permission-mode` et `--dangerously-skip-permissions`
- `--permission-mode` accepte : `default`, `acceptEdits`, `plan`, `auto`, `dontAsk`, `bypassPermissions` (et `manual` = alias de `default` depuis v2.1.200). (Source : [cli-reference](https://code.claude.com/docs/en/cli-reference))
- Pour un run CI verrouillé, la doc headless recommande **`dontAsk`** : refuse tout ce qui n'est pas dans `permissions.allow` ou l'ensemble read-only. `acceptEdits` laisse écrire les fichiers + auto-approuve `mkdir/touch/mv/cp` sans approuver les autres commandes shell/réseau. (Source : [headless](https://code.claude.com/docs/en/headless))
- `--dangerously-skip-permissions` : « Skip permission prompts. Equivalent to `--permission-mode bypassPermissions`. » (Source : [cli-reference](https://code.claude.com/docs/en/cli-reference)) Le `--help` local liste aussi `--allow-dangerously-skip-permissions` (rend l'option disponible sans l'activer par défaut) ; recommandé uniquement pour des sandboxes sans accès internet.

### `--model`
« Sets the model for the current session with an alias for the latest model (`sonnet`, `opus`, `haiku`, or `fable`) or a model's full name. Overrides the `model` setting and `ANTHROPIC_MODEL`. » Ex. `--model claude-sonnet-5`. (Source : [cli-reference](https://code.claude.com/docs/en/cli-reference))

### Activer / cibler des skills ou subagents en headless
- **Skills / commandes** : « User-invoked skills and custom commands work in `-p` mode : include `/skill-name` in the prompt string and Claude Code expands it before running. » Les commandes purement terminal (ex. `/login`) ne sont PAS dispo en `-p`. Depuis v2.1.205, `/model`, `/effort`, `/fast`, `/color`, `/rename` acceptent un argument (`/model sonnet`), et `/config key=value` change un réglage depuis un run `-p`. (Source : [headless](https://code.claude.com/docs/en/headless))
- **Subagents** :
  - `--agent <agent>` : impose un agent pour la session (override le réglage `agent`). (Source : [cli-reference](https://code.claude.com/docs/en/cli-reference))
  - `--agents '<json>'` : définit des subagents dynamiquement en JSON, mêmes champs que la frontmatter + un champ `prompt`. Ex. `--agents '{"reviewer":{"description":"Reviews code","prompt":"You are a code reviewer"}}'`. (Source : [cli-reference](https://code.claude.com/docs/en/cli-reference))
  - `--append-subagent-system-prompt "<txt>"` : ajoute du texte au prompt système de chaque subagent (headless `-p` uniquement, v2.1.205+). (Source : [cli-reference](https://code.claude.com/docs/en/cli-reference))
  - En `stream-json`, les messages de subagents apparaissent comme `assistant`/`user` avec `parent_tool_use_id` = l'ID du `tool_use` qui les a lancés (`null` pour la conversation principale). Par défaut seuls les blocs `tool_use`/`tool_result` des subagents sont émis ; `--forward-subagent-text` (v2.1.211+) ajoute leur texte et thinking. (Source : [headless](https://code.claude.com/docs/en/headless))

---

## 2. Contexte frais par tâche

### Chaque `claude -p` démarre-t-il une session neuve ?
Oui. « Sessions created with `claude -p` or the Agent SDK do not appear in the session picker, but you can still resume one by passing its session ID to `claude --resume <session-id>`. » Autrement dit chaque run crée sa propre session ; la reprise d'historique n'a lieu QUE si l'on passe explicitement `--continue`/`--resume`. Sans ces flags → aucune reprise d'historique conversationnel. (Source : [sessions](https://code.claude.com/docs/en/sessions))

Nuance importante : « sans `--bare`, `claude -p` loads the same context an interactive session would, including anything configured in the working directory or `~/.claude` » (CLAUDE.md, hooks, skills, MCP, mémoire auto). Donc "contexte frais" = **pas d'historique de conversation antérieure**, mais le contexte *projet/config* (CLAUDE.md etc.) est bien rechargé à chaque run — ce qui est en général souhaité. Pour un run 100% reproductible et indépendant de la config locale, ajouter `--bare` (ignore l'auto-découverte ; ne prend que les flags explicites). (Source : [headless](https://code.claude.com/docs/en/headless))

### Injecter proprement le contexte d'UNE tâche
Options documentées, combinables :
- **Prompt en argument** : le corps de la tâche (contenu du ticket, instructions). (Source : [headless](https://code.claude.com/docs/en/headless))
- **stdin/pipe** : `cat ticket-123.md | claude -p 'implémente ce ticket'` — le contenu piché est joint au prompt (≤10 Mo). (Source : [headless](https://code.claude.com/docs/en/headless))
- **Chemins de fichiers ciblés dans le prompt** : recommandé pour gros volumes (« write the content to a file and reference the file path in your prompt »). (Source : [headless](https://code.claude.com/docs/en/headless))
- **`--append-system-prompt`** pour le rôle/consignes persistantes de la tâche. (Source : [headless](https://code.claude.com/docs/en/headless))
- **`--add-dir <dirs...>`** pour donner accès à des répertoires supplémentaires. (Source : `claude --help` local)
- **`--bare` + flags explicites** (`--append-system-prompt-file`, `--settings`, `--mcp-config`, `--agents`, `--plugin-dir`) pour un contexte entièrement maîtrisé. (Source : [headless](https://code.claude.com/docs/en/headless))

---

## 3. Codes de sortie & sortie structurée

### Code retour succès/échec
La doc officielle **ne publie pas de table exhaustive** des codes de sortie du mode `-p`. Ce qui est documenté :
- Comportement standard implicite : **0 = succès, non-zéro = échec** (ex. dépassement stdin 10 Mo → « non-zero status » ; `claude auth status` → 0 si connecté, 1 sinon). (Source : [headless](https://code.claude.com/docs/en/headless), [cli-reference](https://code.claude.com/docs/en/cli-reference))
- **SIGTERM → code 143** : « If you stop a `claude -p` run with SIGTERM ... Claude Code aborts the in-progress turn ... and exits with code 143. » (Source : [headless](https://code.claude.com/docs/en/headless))
- **OOM (installation) → code 137** (SIGKILL par l'OOM killer). (Source : [errors](https://code.claude.com/docs/en/errors))
- `--max-turns` : « Exits with an error when the limit is reached. » (code précis non documenté). (Source : [cli-reference](https://code.claude.com/docs/en/cli-reference))
- Échec de reprise depuis le picker `--resume` → « exits with code 1 ». (Source : [sessions](https://code.claude.com/docs/en/sessions))

**Recommandation robuste pour un script** : ne pas dépendre uniquement de `$?` ; parser le champ **`is_error`** de la sortie JSON pour distinguer succès/échec de façon fiable.

### Format exact de `--output-format json` (message `result`)
Schéma du message `result` (source primaire : [agent-sdk/typescript](https://code.claude.com/docs/en/agent-sdk/typescript)) :

```
type: "result"
is_error: false | true          // false = succès, true = échec (result contient alors le message d'erreur)
result: string                   // texte final (ou message d'erreur si is_error)
session_id: string               // UUID de la session
duration_ms: number              // temps total (wall-clock)
duration_api_ms: number          // temps passé en appels API
num_turns: number                // nb de tours agentiques
total_cost_usd: number           // coût estimé côté client, en USD
usage: {
  input_tokens: number
  output_tokens: number
  cache_creation_input_tokens?: number
  cache_read_input_tokens?: number
}
modelUsage?: [{ model, input_tokens, output_tokens, cache_creation_input_tokens?, cache_read_input_tokens? }]  // ventilation par modèle
permission_denials?: [{ tool, reason }]
```

Avec `--json-schema`, la sortie ajoute le champ **`structured_output`** (objet conforme au schéma) à côté des métadonnées (session_id, usage, etc.). (Source : [headless](https://code.claude.com/docs/en/headless))

### Format `stream-json`
- NDJSON : « newline-delimited JSON, one object per line, arriving in real time ». Un événement par ligne. (Source : [headless](https://code.claude.com/docs/en/headless))
- Premier événement = `system` / `subtype: "init"` : métadonnées de session (model, tools, MCP servers, plugins chargés ; éventuel tableau `capabilities`). (Source : [headless](https://code.claude.com/docs/en/headless))
- Événements possibles avant l'init : `plugin_install`, `hook_started`/`hook_progress`/`hook_response`. Événement `system` / `subtype: "api_retry"` (champs `attempt`, `max_retries`, `retry_delay_ms`, `error_status`, `error`, `uuid`, `session_id`) lors des retries. (Source : [headless](https://code.claude.com/docs/en/headless))
- **Dernière ligne = message `result`** avec le texte final, le coût et les métadonnées de session. Nécessite `--verbose` (et `--include-partial-messages` pour le token-par-token). (Source : [headless](https://code.claude.com/docs/en/headless))

### Parsing bash avec `jq`
Exemples documentés (Source : [headless](https://code.claude.com/docs/en/headless)) :
```bash
# Texte du résultat
claude -p "Summarize this project" --output-format json | jq -r '.result'

# Sortie structurée (avec --json-schema)
claude -p "..." --output-format json --json-schema '{...}' | jq '.structured_output'

# Capturer le session_id
session_id=$(claude -p "Start a review" --output-format json | jq -r '.session_id')

# Streaming : filtrer les deltas de texte
claude -p "Write a poem" --output-format stream-json --verbose --include-partial-messages | \
  jq -rj 'select(.type == "stream_event" and .event.delta.type? == "text_delta") | .event.delta.text'
```
Pour une boucle, on lira aussi `.is_error`, `.total_cost_usd` et `.usage` sur le message `result`.

---

## 4. Continuité : `--continue` et `--resume` (à ÉVITER pour un contexte frais)

- **`--continue` (`-c`)** : « Load the most recent conversation in the current directory. » Fonctionne avec `-p`. Ex. `claude -p "Now focus on the database queries" --continue`. (Source : [sessions](https://code.claude.com/docs/en/sessions), [headless](https://code.claude.com/docs/en/headless))
- **`--resume` (`-r`) `<id|nom>`** : reprend une session précise par ID/nom (ou ouvre un picker). Fonctionne avec `-p` en passant l'ID : `claude -p "Continue that review" --resume "$session_id"`. Le lookup d'ID est scopé au répertoire projet courant et ses worktrees. (Source : [sessions](https://code.claude.com/docs/en/sessions), [headless](https://code.claude.com/docs/en/headless))
- **`--fork-session`** : à la reprise, crée un nouvel ID de session au lieu de réutiliser l'original (à combiner avec `--resume`/`--continue`). (Source : [cli-reference](https://code.claude.com/docs/en/cli-reference))
- Ce qu'une session reprise restaure : historique complet (y compris tool calls/results), modèle, agent, mode de permission, goal actif, tâches planifiées non expirées. (Source : [sessions](https://code.claude.com/docs/en/sessions))

**Confirmation pour la "ralph loop"** : pour garder un contexte frais à chaque itération, il faut **NE PAS** utiliser `--continue` ni `--resume` — ce sont précisément les mécanismes qui réinjectent l'historique de conversation. Un `claude -p "<tâche>"` nu part sans historique conversationnel antérieur. C'est le comportement voulu, une session neuve par tâche.

Options complémentaires utiles à la boucle :
- **`--session-id <uuid>`** : imposer un UUID de session (doit être valide). Utile pour tracer/logguer chaque itération. (Source : [cli-reference](https://code.claude.com/docs/en/cli-reference))
- **`--no-session-persistence`** : print-mode uniquement ; ne sauvegarde rien sur disque, session non-reprenable (équivalent à `CLAUDE_CODE_SKIP_PROMPT_HISTORY`). Idéal si l'on ne veut aucun état résiduel entre itérations. (Source : [sessions](https://code.claude.com/docs/en/sessions), [cli-reference](https://code.claude.com/docs/en/cli-reference))

> Caveat (source secondaire, non-officielle) : un rapport de bug GitHub (anthropics/claude-code #3976) signale des problèmes historiques de reprise en mode non-interactif. Non pertinent pour une ralph loop puisqu'on n'utilise justement pas la reprise.

---

## 5. Coût / tokens exposés dans la sortie headless

Oui, la sortie JSON headless expose le coût et l'usage, exploitable pour un budget :
- « With `--output-format json`, the response payload includes **`total_cost_usd`** and a per-model cost breakdown, so scripted callers can track spend per invocation without consulting the usage dashboard. » (Source : [headless](https://code.claude.com/docs/en/headless))
- Champs disponibles sur le message `result` : **`total_cost_usd`** (coût estimé USD), **`usage`** (`input_tokens`, `output_tokens`, `cache_creation_input_tokens?`, `cache_read_input_tokens?`), **`modelUsage`** (ventilation par modèle), `num_turns`, `duration_ms`, `duration_api_ms`. (Source : [agent-sdk/typescript](https://code.claude.com/docs/en/agent-sdk/typescript))
- **Plafond de dépense** : `--max-budget-usd <amount>` (print mode uniquement) « Maximum dollar amount to spend on API calls before stopping ». (Source : [cli-reference](https://code.claude.com/docs/en/cli-reference)) Le `--help` local le confirme.
- Exemple d'extraction budget dans une boucle : `cost=$(... --output-format json | jq -r '.total_cost_usd')`.

---

## Squelette de "ralph loop" (synthèse dérivée des sources ci-dessus)

```bash
#!/usr/bin/env bash
set -euo pipefail
BUDGET_TOTAL=0

for ticket in tickets/*.md; do
  # Session NEUVE : ni --continue ni --resume => contexte frais
  out=$(claude -p "$(cat "$ticket")

Implémente la tâche décrite ci-dessus. Fichiers ciblés : src/... " \
    --bare \
    --output-format json \
    --permission-mode dontAsk \
    --allowedTools "Read,Edit,Bash(git diff *),Bash(git status *)" \
    --append-system-prompt "Tu es un ingénieur. Reste dans le périmètre du ticket." \
    --model opus \
    --max-budget-usd 5.00 \
    --no-session-persistence)

  is_error=$(jq -r '.is_error' <<<"$out")
  result=$(jq -r '.result'   <<<"$out")
  cost=$(jq -r '.total_cost_usd' <<<"$out")
  BUDGET_TOTAL=$(echo "$BUDGET_TOTAL + $cost" | bc -l)

  if [[ "$is_error" == "true" ]]; then
    echo "ECHEC sur $ticket : $result" >&2
    # décider : continuer / stopper la boucle
  fi
done
echo "Coût total : \$$BUDGET_TOTAL"
```
(Flags et champs tous issus des sources primaires citées ; script assemblé à titre illustratif.)

---

## Sources (primaires)

- Run Claude Code programmatically / headless : https://code.claude.com/docs/en/headless
- Manage sessions (`--continue`, `--resume`, `--fork-session`, persistance) : https://code.claude.com/docs/en/sessions
- CLI reference (tous les flags) : https://code.claude.com/docs/en/cli-reference
- Agent SDK TypeScript (schéma `SDKResultMessage`, `usage`, `modelUsage`) : https://code.claude.com/docs/en/agent-sdk/typescript
- Errors (codes de sortie 137/143, gaps) : https://code.claude.com/docs/en/errors
- `claude --help` (binaire local, Claude Code v2.1.x)
