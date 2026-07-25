# Limites d'usage Claude Code (5h + hebdo)

Type: research
Status: resolved
Blocked by: —

## Question

Comment un script bash **détecte** l'épuisement des limites d'usage d'un abonnement (plan Max) et **quand reprendre** ? Établir les faits (sources primaires : doc officielle Anthropic/Claude Code sur les limites d'usage) :

- Fenêtre de session **5h** : comment démarre-t-elle, comment se réinitialise-t-elle ? Limite **hebdomadaire** : périmètre, reset.
- Signal d'épuisement en headless : message d'erreur exact, **code de sortie**, réponse JSON — de quoi le bash peut brancher dessus.
- Le CLI/API expose-t-il le **temps avant reset** (header, champ, message) pour qu'un `sleep`/cron dorme jusqu'à la réinitialisation ?
- Différence Max 5x / 20x sur les quotas, s'il y en a une exploitable.
- Bonnes pratiques connues pour piloter une boucle autonome sous ces limites (pause propre, reprise).

Livrable : `.scratch/dev-framework/research/limites-usage-claude.md`, chaque fait sourcé. Signaler explicitement tout point non documenté publiquement.

## Answer

Trouvailles complètes (sourcées, section « Non documenté / incertain » incluse) : [`research/limites-usage-claude.md`](../research/limites-usage-claude.md).

Faits actionnables :
- **Pas de code de sortie dédié au quota** en headless : `claude -p` sort `1` générique. `exit 75` + `--wait-on-limit` demandés mais **non livrés** (issue #36320). → traiter tout non-zéro comme « réessayer », ne pas brancher sur un code précis.
- **Meilleur signal = endpoint (non documenté) `GET /api/oauth/usage`** : renvoie `utilization` (%) + `resets_at` (ISO 8601 UTC) pour `five_hour`, `seven_day`, `seven_day_opus`, `seven_day_sonnet`. Token OAuth lu dans Keychain macOS / `~/.claude/.credentials.json` ; header `User-Agent: claude-code/<v>` **obligatoire** (sinon 429). → **c'est LE moyen** de savoir quand un `sleep`/cron doit reprendre (dormir jusqu'à `resets_at`).
- **Fenêtre 5 h** = rolling, démarre au 1er prompt, se libère ~5 h après chaque appel (mécanique communautaire, non officielle).
- **Hebdo** (depuis 28 août 2025) = cap global + caps par modèle, partagés Claude.ai + Claude Code. Officiel « reset 7 j » mais mesures communautaires divergent (~72 h) → **se fier à `resets_at`, pas à un calcul maison**.
- **Message texte instable** entre versions → parsing fragile ; distinguer 429 transitoire (retry auto) d'un épuisement de plan.
- **Max 5x vs 20x** : mêmes mécaniques, seuls les tampons changent ; `utilization` étant un % normalisé, le même code marche quel que soit le tier.

Impact carte : alimente fortement 07 (budget = polling `resets_at`/`utilization`, pause = `sleep` jusqu'à reset) ; contraint 06 (détection de limite = non-zéro + poll endpoint, pas de code dédié).
