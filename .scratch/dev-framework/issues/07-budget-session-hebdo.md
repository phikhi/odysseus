# Gestion du budget 5h / hebdo dans la boucle

Type: grilling
Status: resolved
Blocked by: 02, 06

> **⚠️ En révision — durcissement v2.** La décision v1 ci-dessous est conservée comme record, mais la **reprise après mur hebdo** (`exit pause-hebdo` → relance humaine/cron) est rouverte par [17] (successeur one-shot auto-programmé + anti-double-run). Voir `map.md`.

## Question

Comment la boucle **respecte** la fenêtre de session 5h et les limites hebdo — pause et reprise propres ?

À trancher (s'appuie sur les faits de limites [02] et le control-flow [06]) :
- **Détection** : sur quel signal (code sortie, message, header de reset) la boucle conclut « limite atteinte » ?
- **Pause propre** : finit-elle la tâche en cours, ou l'avorte-t-elle proprement et la re-file ? Aucun ticket ne doit rester à demi.
- **Reprise** : `sleep` jusqu'au reset, cron, ou attente d'un feu vert humain ? Comment redémarrer sans perdre l'état ni traîner de contexte.
- **Politique de fenêtre** : consommer chaque fenêtre 5h à fond, ou garder une marge ? Interaction avec le plafond hebdo (arrêter avant de cramer la semaine).
- Journalisation du budget consommé pour piloter (lié à l'observabilité, encore en brume).

## Answer

Décision verrouillée (grilling HITL). S'appuie sur les faits de limites [02] et les deux hooks (proactif/réactif) déjà posés par le control-flow [06].

**Décision A — Seuils & fenêtres surveillées.** La boucle surveille **trois** fenêtres via `GET /api/oauth/usage` : `five_hour`, `seven_day` (global), `seven_day_opus` (cap du modèle utilisé). Seuils **asymétriques** car l'asymétrie de reset commande : la 5h se réinitialise en **heures**, l'hebdo en **jours** (~72 h observés, incertain [02]), donc un kill mid-task près de la borne hebdo coûte beaucoup plus.
- **5h : seuil ~90 %** (agressif) — on consomme la ressource bon marché à fond.
- **hebdo (`seven_day` et `seven_day_opus`) : seuil ~85 %** (conservateur) — pause/handback plus tôt pour éviter un kill coûteux.
- Seuils **configurables**. **Proactif** : check `utilization` avant chaque spawn. **Réactif** : sur exit non-zéro, re-GET pour identifier la fenêtre saturée et son `resets_at`.

**Décision B — Mécanisme de reprise (asymétrique).**
- **Fenêtre 5h saturée → `sleep` in-process** jusqu'à `resets_at` (+marge) dans le même run, puis re-check et continue. L'état durable vit au tracker [04] → rien à perdre pendant le sommeil ; un sleep de quelques heures est bénin.
- **Limite hebdo saturée → exit-et-handback** : le run **sort** avec le statut **`pause-hebdo` jusqu'à `<resets_at>`** (+ log). Dormir ~72 h en process est fragile (reboot, machine bloquée, process idle qui gaspille) ; comme l'état vit au tracker, la relance (humaine, ou cron/launchd optionnel → [09]) est une reprise propre. Ceci **étend la taxonomie de sortie** de [06] : `tout-résolu` / `bloqué-humain` / **`pause-hebdo`** / `cap` / `stérile`.

**Confirmations (déterminé par [04]+[06], pas re-tranché) :**
- **Pause propre** : le check proactif tombe **avant** le spawn → aucune tâche en vol lors d'une pause proactive. Le réactif tombe après que la plateforme a déjà tué la tâche mid-exec — mais [04] ne marque qu'**après le gate**, donc le ticket reste `open+ready` et sera re-fait à neuf à la reprise. **Aucun ticket ne reste à demi**, par construction.
- **Journalisation** : `total_cost_usd`/`num_turns` par itération sont déjà au `run.log` [06] ; on y **ajoute un snapshot `utilization`** (les trois fenêtres + leur `resets_at`) à chaque pause.

**Détails opérationnels [02] (à implémenter) :**
- Endpoint `GET https://api.anthropic.com/api/oauth/usage` avec header **`User-Agent: claude-code/<version>` obligatoire** (sinon 429 persistants instantanés).
- **Cache ~180 s + backoff** sur 429 (rate-limit par token de l'endpoint lui-même).
- Marge de `sleep` **+~60 s** après `resets_at` (dérive d'horloge).
- **Ne jamais calculer le reset hebdo par « +7 j »** (cadence réelle incertaine) → lire `resets_at`.
- **Même code tous tiers** (5x/20x) : `utilization` est un % normalisé (0–100), `resets_at` un timestamp absolu → pas besoin de connaître les quotas absolus.
- **Fallback** si l'endpoint est indisponible : parser l'heure de reset dans le message texte ; à défaut, `sleep` d'un `POLL_INTERVAL` fixe (ex. 300 s) et re-boucler.

**Frontière [07]/[08] — le classifieur budget.** Un exit non-zéro n'est **pas** d'emblée un échec de tâche. [07] fournit le **classifieur** en amont de la branche d'échec : sur non-zéro → re-GET usage → si une fenêtre est saturée → **pause budget** (D-B) ; sinon → échec réel → passé à [08]. Le **429 transitoire** (capacité API, retry auto par le SDK en secondes) et l'**épuisement de plan** (reset en heures/jours) ne sont **jamais** comptés comme échec de tâche.

**Contraintes créées ailleurs :**
- **[08] Gate QA** : consommer le classifieur budget de [07] **avant** `Failures++`/retry/escalade — ne traiter comme échec réel qu'un non-zéro non imputable au budget.
- **[09] Form-factor** : fournir la config du **cron/launchd optionnel** de relance post-`pause-hebdo` ; embarquer le bon **`User-Agent`** ; **surfacer** les snapshots budget du `run.log`.
