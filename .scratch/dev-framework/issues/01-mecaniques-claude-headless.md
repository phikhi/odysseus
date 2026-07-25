# Mécaniques de Claude Code headless

Type: research
Status: resolved
Blocked by: —

## Question

Comment une ralph loop bash relance-t-elle une session Claude Code **non-interactive à contexte frais** par tâche ? Établir les faits (sources primaires : doc officielle Claude Code) :

- Invocation headless : `claude -p`/`--print`, comment passer le prompt, quels flags (`--output-format`, `--append-system-prompt`, `--allowedTools`, `--dangerously-skip-permissions`, `--model`, sélection de skills/agents).
- Chaque invocation démarre-t-elle bien un contexte **neuf** ? Comment injecter le contexte optimal d'une tâche (fichiers, ticket) sans traîner l'historique.
- Codes de sortie et format de sortie : comment le bash sait qu'une itération a réussi/échoué, comment capturer le résultat structuré (JSON stream ?).
- Reprise/continuité : `--continue`/`--resume` existent-ils, et faut-il les ÉVITER pour rester en contexte frais ?
- Coût/tokens : l'invocation headless expose-t-elle le coût de la session (pour le budget) ?

Livrable : `.scratch/dev-framework/research/mecaniques-claude-headless.md`, chaque fait sourcé.

## Answer

Trouvailles complètes (sourcées, sources primaires `code.claude.com/docs` + `claude --help` v2.1.x) : [`research/mecaniques-claude-headless.md`](../research/mecaniques-claude-headless.md).

Faits actionnables :
- **Contexte frais = `claude -p "<prompt>"` SANS `--continue`/`--resume`.** Ces deux flags sont précisément ce qui réinjecte l'historique ; les omettre garantit une session neuve par tâche (elle n'apparaît même pas dans le picker).
- **Invocation** : prompt en argument ou via stdin/pipe/heredoc (`cat ticket.md | claude -p '...'`, ≤10 Mo). Flags clés : `--append-system-prompt` (rôle), `--allowedTools`/`--disallowedTools`, `--permission-mode dontAsk` (CI verrouillée), `--dangerously-skip-permissions`, `--model opus`. Skills en headless = mettre `/skill-name` dans le prompt ; subagents via `--agent`/`--agents '<json>'`.
- **Sortie structurée** : `--output-format json` → objet unique avec `result`, `session_id`, `is_error`, `num_turns`, `total_cost_usd`, `usage`, `modelUsage`. `stream-json` = NDJSON. Parsing bash : `jq -r '.result'`, `.is_error`, `.total_cost_usd`.
- **Succès/échec** : pas de table de codes de sortie officielle exhaustive (documentés : 143=SIGTERM, 137=OOM ; `--max-turns` sort en erreur). **Se fier au champ `is_error` du JSON, pas seulement à `$?`.**
- **Budget** : `total_cost_usd` + `usage`/`modelUsage` par run ; plafond via `--max-budget-usd`. Reproductibilité : `--bare` (ignore hooks/skills/MCP/CLAUDE.md locaux), `--no-session-persistence`.

Impact carte : débloque partiellement 06 (control-flow) ; alimente 03 (le contexte injecté au démarrage compte dans le budget 200K) et 07 (budget via `total_cost_usd`).
