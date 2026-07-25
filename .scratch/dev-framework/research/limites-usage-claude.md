# Détecter l'épuisement des limites d'usage (plan Max) depuis un script bash pilotant Claude Code

> Recherche menée le 2026-07-23. Sources primaires = doc officielle Claude Code / centre d'aide Anthropic. Le reste est explicitement marqué comme observation communautaire.

## Résumé exécutif (actionnable)

- **Meilleur signal pour un pilote autonome : l'endpoint `GET https://api.anthropic.com/api/oauth/usage`** (celui qu'utilise la commande `/usage`). Il renvoie, en JSON structuré, `utilization` (%) et `resets_at` (ISO 8601 UTC) pour `five_hour`, `seven_day`, `seven_day_opus`, `seven_day_sonnet`. Un script bash lit ça, dort jusqu'à `resets_at`, reprend. C'est **semi-officiel / non documenté** mais stable et utilisé en interne. [jtbr gist](https://gist.github.com/jtbr/4f99671d1cee06b44106456958caba8b) · [issue #202](https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor/issues/202)
- **Il n'existe AUCUN code de sortie dédié à l'épuisement de quota.** En headless (`claude -p`), Claude Code fait un `exit` non‑zéro générique (typiquement `1`). Un code spécifique (`exit 75`) et un flag `--wait-on-limit` sont *demandés* mais **pas encore livrés**. Ne branchez donc pas sur un code précis : traitez tout non‑zéro comme "à réessayer". [issue #36320](https://github.com/anthropics/claude-code/issues/36320)
- **Fenêtre 5 h = rolling, démarre au premier prompt.** Elle ne se vide pas d'un coup : l'usage "vieillit" et se libère ~5 h après chaque appel. Le compteur ne repart réellement à zéro que quand vous renvoyez un message après expiration. Non documenté officiellement (mécanique confirmée par la communauté). [portkey](https://portkey.ai/blog/claude-code-limits/)
- **Limite HEBDOMADAIRE (introduite le 28 août 2025)** : un cap global tous modèles + des caps par modèle (`seven_day_opus`, `seven_day_sonnet`), **partagés entre Claude.ai et Claude Code**. Officiellement "reset tous les 7 jours à une heure fixe", **mais** une mesure communautaire (juin 2026) montre un reset réel toutes les ~72 h à un ancrage fixe (~04:50–05:00 UTC). À traiter comme incertain — se fier à `resets_at`, pas à un calcul "+7 jours". [support Max](https://support.claude.com/en/articles/11049741-what-is-the-max-plan) · [gist monperrus](https://gist.github.com/monperrus/3ac4b303a84946bbeaf2b1123ee99491)
- **Stratégie robuste** : boucle `while` autour de `claude -p --dangerously-skip-permissions`, contrôle *proactif* de `utilization` avant chaque itération (pause si > ~90 %), et *réactif* sur exit non‑zéro → `sleep` jusqu'à `resets_at` (+ marge). Ne pas dépendre du texte du message d'erreur seul (le libellé change entre versions).

---

## 1. Fenêtre de session "5 heures"

### Ce qui est officiel
- Le plan facturé a une **limite de session de 5 heures**, visible dans **Réglages > Usage** : *"Current session: How much of your plan's five-hour session limit you've used thus far, plus the amount of time remaining in the session."* — [support.claude.com/…/9797557 (usage limit best practices)](https://support.claude.com/en/articles/9797557-usage-limit-best-practices)
- Ces limites sont **partagées entre Claude.ai et Claude Code** : *"all activity in both tools counts against the same usage limits."* — [support.claude.com/…/11145838](https://support.claude.com/en/articles/11145838-use-claude-code-with-your-pro-or-max-plan)
- Les limites 5 h de Claude Code (Pro/Max/Team/Enterprise par siège) ont été **doublées** et la réduction "heures de pointe" retirée. — [anthropic.com/news/higher-limits-spacex](https://www.anthropic.com/news/higher-limits-spacex)

### Ce qui est observation communautaire (non documenté par Anthropic)
- **Démarrage** : la fenêtre démarre au **premier prompt** — *"The moment you run `claude` in your terminal, a 5‑hour rolling window begins."*
- **Rolling** : elle ne se réinitialise pas en bloc à heure fixe ; l'usage d'il y a ~5 h se libère progressivement. *"the clock resets only when you send the next message after the 5 hours lapse."* — [portkey.ai/blog/claude-code-limits](https://portkey.ai/blog/claude-code-limits/)
- **Périmètre** : compteur unique par compte, partagé chat + CLI + sous‑agents.

### Signal exploitable
Champ API `five_hour.utilization` (0–100) et `five_hour.resets_at` (voir §4).

---

## 2. Limite HEBDOMADAIRE (introduite en 2025)

### Officiel
- Le plan Max a **deux limites hebdomadaires** : *"Max plans also have two weekly usage limits: one that applies across all models and another for [model‑specific]."* — [support.claude.com/…/11049741 (what is the Max plan)](https://support.claude.com/en/articles/11049741-what-is-the-max-plan)
- Partagées Claude.ai + Claude Code (même pool). — [support.claude.com/…/11145838](https://support.claude.com/en/articles/11145838-use-claude-code-with-your-pro-or-max-plan)
- Le CLI expose un message distinct de type **"weekly limit"** et **"Opus limit"** (voir §3). — [code.claude.com/docs/en/errors](https://code.claude.com/docs/en/errors)

### Communautaire
- **Date d'introduction : 28 août 2025.** Deux niveaux totalement indépendants : fenêtre 5 h rolling + cap hebdo séparé, qui *"reset independently, which is why usage can feel fine one moment and locked the next."* — [portkey.ai/blog/claude-code-limits](https://portkey.ai/blog/claude-code-limits/)
- **Cadence de reset réelle contestée** : mesure sur 11 jours du champ `seven_day.utilization` (9–20 juin 2026) → resets tous les **~72 h** (71.9 h / 72.6 h / 72.5 h), à un **ancrage fixe ~04:50–05:00 UTC**, *pas* un jour de semaine fixe ni 7 jours pleins. Certains utilisateurs rapportent ensuite des doubles resets irréguliers → mécanique possiblement changée depuis. — [gist monperrus](https://gist.github.com/monperrus/3ac4b303a84946bbeaf2b1123ee99491)

### Différence clé avec la fenêtre 5 h
La 5 h est un tampon glissant court terme ; l'hebdo est un plafond long terme partagé tous modèles + par modèle. Les deux peuvent bloquer indépendamment. **Ne jamais calculer le reset hebdo par "dernier appel + 7 j"** : lire `seven_day.resets_at`.

---

## 3. Signal d'épuisement en mode headless (`claude -p`)

### Code de sortie — POINT CRITIQUE
- **Aucun code de sortie spécifique au quota.** L'issue #36320 (fermée comme duplicate) *demande* explicitement : un code dédié (proposé `exit 75`) pour distinguer "rate‑limité" d'un crash, un flag natif `--wait-on-limit`, et la persistance de session en pause. **Rien de tout ça n'existe aujourd'hui.** Comportement actuel : la tâche est *"silently killed mid-execution"* et le process sort en non‑zéro générique (`1`). — [issue #36320](https://github.com/anthropics/claude-code/issues/36320)
- Convention documentée : `0` = succès, tout non‑zéro = erreur, sans table exhaustive. `1` = erreur générique (prompt invalide, réseau) ; `2` = auth. La recommandation officielle est de **tester "non‑zéro", pas un code précis**. — [code.claude.com/docs/en/errors](https://code.claude.com/docs/en/errors)

### Messages texte (stdout)
Formats exacts affichés par le CLI (doc officielle "Error reference") :
```text
You've hit your session limit · resets 3:45pm
You've hit your weekly limit · resets Mon 12:00am
You've hit your Opus limit · resets 3:45pm
```
— [code.claude.com/docs/en/errors](https://code.claude.com/docs/en/errors)

⚠️ **Attention version** : d'anciennes versions émettaient plutôt `Claude AI usage limit reached|<timestamp epoch>` (format pipe que parsent les scripts type *claude-auto-resume*). D'autres variantes observées : `5-hour limit reached ∙ resets 3pm`, `Claude usage limit reached. Resets at 2pm`. **Le libellé n'est PAS stable** → le parsing texte est fragile. — [terryso/claude-auto-resume](https://github.com/terryso/claude-auto-resume) · [cheapestinference](https://cheapestinference.com/blog/claude-code-usage-limit-auto-retry/)

### Sortie JSON (`--output-format json` / `stream-json`)
- Les **429 transitoires** (capacité API) apparaissent comme événements `system` :
```json
{ "type":"system","subtype":"api_retry","attempt":1,"max_retries":5,
  "retry_delay_ms":2000,"error_status":429,"error":"rate_limit", ... }
```
Le champ `error` peut valoir `rate_limit`, `server_error`, `authentication_failed`, `billing_error`, `invalid_request`, `max_output_tokens`, `unknown`. — [backgroundclaude.com/blog/stream-json](https://backgroundclaude.com/blog/stream-json)
- L'événement final `result` porte `subtype` (`success` / `error_max_turns` / `error_during_execution`), `is_error`, et parfois `api_error_status`. — [backgroundclaude.com/blog/stream-json](https://backgroundclaude.com/blog/stream-json)

⚠️ **Distinction essentielle** : un `429 rate_limit` API (capacité serveur, retry auto en secondes) **n'est pas** l'épuisement du quota d'abonnement (session/hebdo, reset en heures). Le SDK gère les 429 transitoires tout seul. L'épuisement de *plan* se manifeste par le message texte ci‑dessus et/ou l'arrêt non‑zéro, **pas** par un champ JSON dédié documenté. Ne pas confondre les deux dans la logique de reprise.

---

## 4. Temps avant reset : comment un script sait QUAND reprendre

### (a) Source la plus fiable — endpoint usage OAuth (semi‑officiel, non documenté)
`GET https://api.anthropic.com/api/oauth/usage` — c'est ce que la commande `/usage` interroge.

**En‑têtes requis :**
```
Authorization: Bearer <oauth_access_token>
anthropic-beta: oauth-2025-04-20
User-Agent: claude-code/<version>        # OBLIGATOIRE, sinon 429 persistants
Content-Type: application/json
```
**Réponse (exemple) :**
```json
{
  "five_hour":        { "utilization": 37.0, "resets_at": "2026-02-08T04:59:59.000000+00:00" },
  "seven_day":        { "utilization": 26.0, "resets_at": "2026-02-12T14:59:59.771647+00:00" },
  "seven_day_opus":   null,
  "seven_day_sonnet": { "utilization": 1.0,  "resets_at": "2026-02-13T20:59:59.771655+00:00" },
  "extra_usage":      { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null }
}
```
**Récupérer le token OAuth :**
- macOS : Keychain, service `Claude Code-credentials` → `security find-generic-password -s "Claude Code-credentials" -w` puis `jq -r '.claudeAiOauth.accessToken'`.
- Linux/WSL : `~/.claude/.credentials.json` → même chemin JSON `.claudeAiOauth.accessToken`.
- Ou variable d'env `CLAUDE_CODE_OAUTH_TOKEN`.
- ⚠️ Le token expire ~toutes les 60 min ; Claude Code le rafraîchit automatiquement s'il tourne.

**Caveats de rate‑limit sur l'endpoint** : sans le bon `User-Agent` → 429 instantanés persistants ; avec, safe à intervalle ~180 s. Rate‑limit par token, pas par compte ; prévoir un cache TTL ~180 s + backoff. — [jtbr gist](https://gist.github.com/jtbr/4f99671d1cee06b44106456958caba8b) · [issue #202](https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor/issues/202) · [issue #31021 (429 sur l'endpoint)](https://github.com/anthropics/claude-code/issues/31021)

**Calcul du sleep (bash) :**
```bash
resets_at=$(curl -s https://api.anthropic.com/api/oauth/usage \
  -H "Authorization: Bearer $token" -H "anthropic-beta: oauth-2025-04-20" \
  -H "User-Agent: claude-code/2.1.79" | jq -r '.five_hour.resets_at')
reset_epoch=$(date -ud "$resets_at" +%s)          # GNU/Linux
now=$(date -u +%s)
sleep $(( reset_epoch - now + 30 ))               # + marge
```

### (b) Depuis le message texte (fragile)
Parser `resets 3:45pm` / `Resets at 2pm` avec parsing horaire timezone‑aware, ou l'ancien `...reached|<epoch>`. Fonctionne mais casse au moindre changement de libellé. — [code.claude.com/docs/en/errors](https://code.claude.com/docs/en/errors) · [cheapestinference](https://cheapestinference.com/blog/claude-code-usage-limit-auto-retry/)

### (c) En interactif seulement
`Réglages > Usage` (et `/usage`) affichent le temps restant de session. Pas exploitable directement en headless. — [support.claude.com/…/9797557](https://support.claude.com/en/articles/9797557-usage-limit-best-practices)

### Headers HTTP ?
Sur l'API *plateforme* classique (clé API, pas abonnement), les 429 renvoient `retry-after` et des headers `anthropic-ratelimit-*` ([platform.claude.com/docs/en/api/rate-limits](https://platform.claude.com/docs/en/api/rate-limits)). Mais en mode abonnement Max via Claude Code, **le script ne voit pas ces headers** : il faut passer par l'endpoint `/api/oauth/usage` (a) ou le texte (b).

---

## 5. Max 5x vs Max 20x — quota exploitable ?

### Officiel
- Max 5x = **5×** l'usage Pro par session 5 h ; Max 20x = **20×** l'usage Pro par session. Les deux ont les deux limites hebdo. — [support.claude.com/…/11049741](https://support.claude.com/en/articles/11049741-what-is-the-max-plan)

### Estimations communautaires (par semaine)
| Tier | Sonnet | Opus |
|------|--------|------|
| Max 5x (100 $/mo)  | ~140–280 h | ~15–35 h |
| Max 20x (200 $/mo) | ~240–480 h | ~24–40 h |
≈ ×1.7 en capacité Sonnet et ×1.6 en Opus pour le 20x vs 5x. — [portkey.ai/blog/claude-code-limits](https://portkey.ai/blog/claude-code-limits/)

### Exploitable pour un script ?
Oui, **de façon transparente** : les *mécaniques* (fenêtre 5 h rolling, hebdo, endpoint `/api/oauth/usage`) sont identiques sur 5x et 20x ; seule la taille des tampons change. Comme `utilization` est un **pourcentage normalisé** (0–100) et `resets_at` un timestamp absolu, **le même code de détection/pause fonctionne quel que soit le tier** — pas besoin de connaître les quotas absolus. Le 20x permet simplement des sessions plus longues avant la pause.

---

## 6. Bonnes pratiques pour une boucle autonome sous ces limites

**Modèle recommandé (proactif + réactif) :**
1. **Avant chaque itération** : GET `/api/oauth/usage`. Si `five_hour.utilization` ou `seven_day.utilization` > ~90 %, dormir jusqu'à `resets_at` correspondant (+ marge) au lieu de foncer dans le mur. (Cache 180 s, User‑Agent correct, backoff sur 429.)
2. **Lancer** `claude -p "<prompt>" --dangerously-skip-permissions --output-format json` (skip‑permissions requis pour l'unattended — **risque sécurité** : exécute tout sans confirmation). — [terryso/claude-auto-resume](https://github.com/terryso/claude-auto-resume)
3. **Après** : si `exit != 0`, considérer comme rate‑limité → re‑GET `/api/oauth/usage`, `sleep` jusqu'au `resets_at`, puis reprendre (relance ou `claude -c` pour continuer la conversation).
4. **Fallback** si l'endpoint est indispo : parser le message texte pour l'heure de reset ; à défaut, `sleep` d'un intervalle fixe (ex. `POLL_INTERVAL=300`) et boucler. — workaround officiel de l'issue :
```bash
while true; do
  claude "$@"; EXIT_CODE=$?
  [[ $EXIT_CODE -eq 0 ]] && break
  echo "Rate-limited. Retry in ${POLL_INTERVAL:-300}s..."
  sleep "${POLL_INTERVAL:-300}" || break
done
```
— [issue #36320](https://github.com/anthropics/claude-code/issues/36320)

**Outils communautaires prêts à l'emploi** (à auditer avant usage) :
- `terryso/claude-auto-resume` — wrapper shell qui parse le message et reprend. [lien](https://github.com/terryso/claude-auto-resume)
- `Maciek-roboblog/Claude-Code-Usage-Monitor`, `bozdemir/claude-usage-widget`, `ccusage` — monitors qui exploitent `/api/oauth/usage`. [issue #202](https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor/issues/202)

**Pièges à éviter :**
- Ne pas brancher sur un code de sortie précis (n'existe pas) → tester non‑zéro.
- Ne pas confondre 429 transitoire (retry auto, secondes) et épuisement de plan (reset en heures).
- Ne pas calculer le reset hebdo par "+7 jours" (cadence réelle incertaine, ~72 h observés) → lire `resets_at`.
- Le parsing texte casse quand Anthropic change le libellé → préférer l'endpoint JSON.

---

## Non documenté / incertain (à surveiller)

| Point | Statut |
|-------|--------|
| Démarrage "au premier prompt" + mécanique rolling de la fenêtre 5 h | **Non documenté** officiellement ; cohérent dans la communauté. |
| Cadence de reset hebdo : 7 jours (officiel) vs ~72 h (mesuré, juin 2026) | **Contradiction non résolue.** Ne pas coder de "+7 j" en dur. |
| Cap hebdo par modèle : Opus ou Sonnet ? | L'article Max dit "Sonnet only" ; l'API expose **les deux** (`seven_day_opus` ET `seven_day_sonnet`) et le CLI affiche "Opus limit". Ambigu. |
| Endpoint `/api/oauth/usage` (URL, headers, champs `resets_at`/`utilization`) | **Non documenté publiquement** (interne à `/usage`). Header beta `oauth-2025-04-20` → susceptible de changer. |
| Code de sortie dédié au quota + flag `--wait-on-limit` | **Demandés, non livrés** (issue #36320). |
| Format exact du message d'erreur en headless | **Instable entre versions** (`...reached\|<epoch>` ancien vs `resets 3:45pm` actuel). |
| Chiffres d'heures Sonnet/Opus par tier | **Estimations communautaires**, non chiffrés officiellement par Anthropic pour Pro/Max. |

---

### Sources
Officielles : [Error reference](https://code.claude.com/docs/en/errors) · [Usage limit best practices](https://support.claude.com/en/articles/9797557-usage-limit-best-practices) · [What is the Max plan](https://support.claude.com/en/articles/11049741-what-is-the-max-plan) · [Use Claude Code with Pro/Max](https://support.claude.com/en/articles/11145838-use-claude-code-with-your-pro-or-max-plan) · [Higher limits (SpaceX)](https://www.anthropic.com/news/higher-limits-spacex) · [API rate limits](https://platform.claude.com/docs/en/api/rate-limits)
Communautaires : [portkey limits](https://portkey.ai/blog/claude-code-limits/) · [issue #36320](https://github.com/anthropics/claude-code/issues/36320) · [claude-auto-resume](https://github.com/terryso/claude-auto-resume) · [cheapestinference auto-retry](https://cheapestinference.com/blog/claude-code-usage-limit-auto-retry/) · [stream-json](https://backgroundclaude.com/blog/stream-json) · [gist monperrus 72h](https://gist.github.com/monperrus/3ac4b303a84946bbeaf2b1123ee99491) · [jtbr status line gist](https://gist.github.com/jtbr/4f99671d1cee06b44106456958caba8b) · [issue #202 OAuth usage API](https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor/issues/202) · [issue #31021](https://github.com/anthropics/claude-code/issues/31021)
