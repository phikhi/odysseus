# Backend tracker GitHub/GitLab optionnel

Type: grilling
Status: resolved
Blocked by: —

> Durcissement v2 (emprunt Multiplyz : GitHub-natif). **Étend [09]** (form-factor). Voir `ANALYSE-multiplyz-vs-odysseus.md` §6.2.

## Question

Le framework doit-il **abstraire le backend de tracker** pour offrir **GitHub/GitLab** en plus du markdown local — et à quel prix pour la portabilité « pur local » ?

Contexte : déjà **anticipé** — `setup-matt-pocock-skills` embarque `issue-tracker-github.md` / `-gitlab.md` / `-local.md`, et `docs/agents/issue-tracker.md` décrit les ops locales. Multiplyz est **entièrement GitHub** (Issues + Project + Actions + branch-protection + CODEOWNERS) → audit trail, CI required-checks, collaboration humaine. Odysseus est **pur local markdown** (portable, zéro dépendance, mais aucun audit externe).

À trancher :
- **Surface à abstraire** : les ops de la boucle bash — **scan frontière** (`open ∧ unblocked ∧ ready-for-agent`, min NN) et **marquage** (`resolved`/`ready-for-human`, atomique) — doivent marcher sur les 3 backends (fichiers vs `gh`/`glab`). Quelle interface minimale (fonctions `frontier`/`mark`/`claim` déportées dans `lib/tracker-*.sh`) ?
- **Qui fournit les conventions** : réutiliser les docs `issue-tracker-{github,gitlab,local}.md` du substrat.
- **Défaut** : local (portabilité), GitHub/GitLab en **opt-in** via `ralph.config.sh` (`TRACKER_BACKEND=local|github|gitlab`).
- **Ce qu'on gagne / perd** : gain (audit, CI required-checks comme gate additionnel [08], collab) vs perte (dépendance `gh`/`glab` + réseau + repo distant → casse le « fallback sans node/offline » [09]).
- **Rapport avec le gate [08]** : un backend GitHub ouvre la porte aux **required checks CI** comme gate objectif complémentaire (mais optionnel).

## Answer

Décision verrouillée (grilling HITL). **Étend [09]**. Backend de tracker abstrait, `local` par défaut, `github`/`gitlab` en opt-in.

**D1 — Seam : interface d'adaptateur de tracker.** Contrat fixe de fonctions shell que la boucle appelle (jamais le backend en direct) : `frontier` (open ∧ unblocked ∧ ready-for-agent ∧ non-claimed, min NN) · `read_ticket` (corps + write-surface [15] + blocked-by) · `claim` (atomique, owner+horodatage [15]) · `mark_resolved`/`mark_ready_for_human` [04] · `open_ticket` (re-slice/re-injection/escalade [08]/[12]) · `append_note` (pointeur, run.log, reçu [18]). **3 impls** `lib/tracker-<backend>.sh` (`local`/`github`/`gitlab`), sélectionnées par `TRACKER_BACKEND`. La boucle [06] ne dépend **que** de l'interface (module profond, backend interchangeable, zéro `if github` dans le control-flow).

**D2 — Mapping via le substrat + liveness locale.** L'adaptateur implémente l'interface avec les conventions de `issue-tracker-{github,gitlab,local}.md` (substrat, ne pas réinventer) : Status → état + labels ; `ready-for-*` → labels ; `resolved` → fermé ; Blocked by → dépendance native ; notes → commentaires ; claim → **assignee**. **Accroc résolu** : la **liveness du claim [21] est LOCALE** (pid+mtime ; la concurrence est mono-machine [04]) → le claim *visible* vit sur le backend (collab), la **liveness runtime vit dans un sidecar local**, quel que soit le backend. L'interface scinde ops **durables** (remote-ables) vs **liveness** (locale).

**D3 — Défaut local, distant opt-in, compromis honnête (PAS « offline »).** Défaut `local` : dépendance minimale (pas de `gh`/`glab`/repo distant), **bookkeeping filesystem local** (pas de 2ᵉ service online dans le chemin critique de la boucle : ni rate-limit, ni latence, ni auth). `github`/`gitlab` opt-in (`TRACKER_BACKEND`, fixé au bootstrap [09]) pour **audit trail + collab humaine + gate CI**. **Correction explicite** : il n'y a **pas** de delivery « offline » — le LLM exige le réseau à **chaque** itération ; **`AFK = pas d'humain`, pas `offline`**. Le vrai axe local-vs-distant = **dépendance + robustesse du bookkeeping**, pas réseau. `fallback sans node` [09] = moteur bash (axe runtime), distinct aussi.

**D4 — CI = tier de gate additionnel, ON par défaut en distant (si CI détecté), opt-out explicite.** Le **gate local [08] fait toujours autorité** (primaire, rapide). En `TRACKER_BACKEND=github/gitlab`, l'adaptateur expose `wait_ci` et — **si un CI est détecté** — **`wait_ci` est ON par défaut** : la boucle **attend le vert CI avant `mark_resolved`** (défense en profondeur : local **ET** CI ; évite « resolved local contredit par un CI rouge / une branch-protection »). **Auto no-op** si aucun CI configuré. **Opt-out explicite `WAIT_CI=off`** pour l'usage « backend distant pour tracking/collab seulement ». Un seul toggle primaire (le backend). Coût assumé : latence CI (wall-clock, **ne brûle pas le quota Claude** — attente idle).

### Contraintes créées ailleurs
- **[06] control-flow** : la boucle appelle l'interface d'adaptateur, jamais un backend en dur ; si `wait_ci` actif, l'attente CI s'insère **avant** `mark_resolved`.
- **[08] gate** : le gate local reste autorité ; CI = tier confirmatif optionnel qui **s'ajoute** (jamais ne remplace).
- **[09] form-factor** : `TRACKER_BACKEND` (défaut `local`) + `WAIT_CI` (défaut auto : ON si distant+CI détecté) dans `ralph.config.sh` ; le pack embarque `lib/tracker-{local,github,gitlab}.sh` ; **retirer toute mention « offline »** — documenter le compromis en termes de dépendance/robustesse ; `fallback sans node` = axe runtime.
- **[15]/[21]** : claim visible sur le backend, **liveness (pid+mtime) en sidecar local** ; interface scindée durable/liveness.
- **[18] reçu** : avec un backend distant, le reçu peut *être* une PR (CI dessus) — à trancher en [18].
