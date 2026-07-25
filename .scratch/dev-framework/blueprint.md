# Blueprint — Framework de développement autonome (odysseus)

> **Document gelé.** Consolidation des décisions verrouillées ([03]→[09] v1 + [11]→[26] v2, sources [01]/[02]/[22]). **Zéro code, zéro nouvelle décision** — la synthèse prête au handoff `/to-spec` → `/to-tickets`. Le vocabulaire est fixé dans [`CONTEXT.md`](CONTEXT.md) ; chaque section renvoie au ticket qui détient le détail et le pourquoi.

---

## 0. Nature & destination

Un **pack déposable dans n'importe quel projet** qui ajoute, par-dessus les skills Matt Pocock déjà installés (le **substrat**), une **delivery autonome AFK** : une boucle bash relance une **session Claude Code headless à contexte frais par tâche** — jamais compactée, garantie « smart zone » <200K — pour broyer des tickets sous contrainte de budget d'usage, avec une **boucle humaine** compagne pour tout ce qui remonte au jugement. Discovery reste HITL ; delivery est AFK. **Le pack est 100 % bash + markdown** (fallback sans node).

## 1. Architecture d'ensemble — **deux boucles sur un tracker**

```
        discovery (HITL)                          delivery
   grilling/domain-modeling → to-spec → to-tickets
                     │  (contrat [05] : spec + tickets ready-for-agent)
                     ▼
   ┌─────────────────────────────────────────────────────────────┐
   │  loop.sh (AFK)  — broie ready-for-agent                       │
   │   scan frontière → session fraîche → gate → marque            │
   │        │ resolved                        │ escalade            │
   │        ▼                                  ▼ (Escalation:)       │
   │   [intégration]                    puits ready-for-human       │
   └───────────────────────────────────────────┬───────────────────┘
                                                 │
   ┌─────────────────────────────────────────────▼──────────────────┐
   │  human-loop.sh (HITL)  — draine ready-for-human [25]             │
   │   route par raison → grilling / to-tickets / implement / sign   │
   │        └── réinjecte ready-for-agent ──────────────────────────►┘ (retour AFK)
   └──────────────────────────────────────────────────────────────────┘
```

Les deux boucles partagent le **tracker** (seule autorité d'état [04]) et sont **mutuellement exclusives** via le **verrou de run grossier** [04]/[25] (on broie **ou** on draine). Le cycle **escalade → drain → réinjection** est le moteur de progression global.

## 2. Substrat & préconditions d'environnement

- **Substrat réutilisé** (jamais réinventé) : `grilling`, `domain-modeling`, `research`, `to-spec`, `to-tickets`, `implement`, `tdd`, `code-review`, `triage`, `wayfinder` (+ `teach` pour le **format** de leçon [11]).
- **Préconditions de l'env cible** (non fournies par le pack, à documenter à l'install [09]) :
  - **projet git** (snapshot/rollback [08], branches `failed/<ticket>`, worktrees [15]) ;
  - **exécution sandboxée** de la delivery AFK (D1/[06]) ;
  - **commandes de test/typecheck configurables** [08] ;
  - Claude Code (headless `claude -p`, hooks, endpoint `/api/oauth/usage`). *Multi-provider = hors périmètre (version ultérieure).*

## 3. Unité de travail & garantie smart-zone — [03]

- **Tâche** = une slice verticale « tracer-bullet » du découpage `to-tickets`, **maille variable**, dimensionnée pour finir **sous 200K**.
- **Garantie = filet runtime dur** : `auto-compact OFF`, SIGTERM au **franchissement du seuil mou (150K)** ; **dur 200K** = frontière dumb-zone.
- Slice trop grosse → **re-découpage autonome** préservant les AC (via `to-tickets`), ré-injecté en frontière ; soupape humaine seulement si les AC ne peuvent être préservées (cf. [08]).

## 4. Modèle d'état & sources de vérité — [04] (+ couches [11]/[18])

- **Tracker = unique autorité** de l'état des tâches (Status, `Blocked by`, triage, `Failures:`, write-surface [15], `Escalation:` [25]). Une session fraîche **reconstruit tout** en relisant le tracker seul.
- **Sélection** = **scan sans mémoire** ; frontière AFK = `open ∧ unblocked ∧ ready-for-agent ∧ non-claimed` [15], **min NN**.
- **Marquage** = par **la boucle**, **après le gate** (jamais la session), atomique **temp+`mv`**.
- **Quatre couches d'observabilité/mémoire** (distinctes) :
  1. **Journal de run** [04] — ligne machine/itération, non-autoritaire, jamais relue.
  2. **Reçu d'audit** [18] — document humain/itération (résumé + 4 verdicts + preuves + méta + **diff par référence**), surface de relecture async ; **local** = `.scratch/<feature>/receipts/`, **distant** = la PR.
  3. **Playthrough** [12] — narré/feature, acceptation durable (`docs/playthroughs/`).
  4. **LEARNINGS** [11] — leçons distillées (index + records), relu comme contexte.
- **Verrou de run grossier** : 1 run/tracker ; couvre AFK **et** human-loop.

## 5. Contrat discovery → delivery — [05]

- **Contrat** = sortie standard du substrat **validée** : `spec.md` (+ **flux utilisateur bout-en-bout explicite**, exigé par [12]) + tickets `to-tickets` (AC **machine-vérifiables**, e2e si surface, **non-occlusion** si superposé [13], **write-surface** déclarée [15], blocage, `ready-for-agent`) + `CONTEXT.md`/ADRs ambiants.
- **Ligne interne / contractuel** (structurante, réutilisée partout) : une décision **interne** (n'engage ni AC, ni spec, ni décision verrouillée, ni dépendance) → **autonome** ; **contractuelle** → **escalade `ready-for-human`**.
- **Une seule porte** d'approbation (`to-tickets`) ; 2 arrêts humains en discovery (seams + découpage) ; un **pas de revue de capacités** en sortie de charting [24].

## 6. La ralph loop — control-flow AFK — [06]

Squelette `while` : verrou de run → gardes (kill / cap itérations / détecteur de run stérile) → **scan frontière** (N tickets à write-surfaces disjointes [15]) → **budget proactif** (gate le spawn [07]) → `cat ticket | claude -p` **stream-json**, `--dangerously-skip-permissions` (**sandbox**), monitor SIGTERM 150K → **gate** [08] → **marquage** [04] → **reçu** [18] → **retro** [11] (leçon/ADR/gap de capacité) → append `run.log`. Frontière vide → **playthrough terminal** [12] avant l'exit « tout résolu ». Injecte dans le prompt : ticket + pointeurs (CONTEXT/ADRs/**index LEARNINGS** [11]) + consignes de **langue** [26].

## 7. Budget d'usage & auto-chaînage — [07]/[17]

- Surveille `five_hour` + `seven_day` + `seven_day_opus` via `GET /api/oauth/usage` (`User-Agent` obligatoire, cache 180 s) ; **seuils asymétriques** (5h agressif, hebdo conservateur) ; **classifieur budget** (un exit non-zéro est testé « budget ? » avant « échec »).
- **5h** → `sleep` in-process jusqu'à `resets_at`. **Hebdo** → **successeur one-shot auto-programmé** [17] au `resets_at` de la fenêtre bloquante (**jamais +7j**) ; **repli humain** (`exit pause-hebdo`) si pas de scheduler. **Anti-double-run** : successeur singleton + verrou de run [04].
- **Scheduler** [17] : chaîne de fallback auto-détectée, **ordonnée par survie au reboot** (le hebdo dure des jours) — `at` (spool disque) avant transient `systemd-run` ; par plateforme (cf. [22]) : Linux systemd / non-systemd / macOS ; skill `schedule` = cloud, **hors chaîne locale**.

## 8. Gate QA, registre de lentilles & échecs — [08] (+ [13]/[14]/[23]/[26]/[19])

- **Gate en checks parallèles**, autorité déterministe > LLM :
  - **Objectifs** (par la boucle bash, complaisance impossible) : **tests** + **typecheck** + **scope-guard** [19] (`git diff --name-only` vs write-surface) + **gate de langue** [26] (langue de la prose = attendue du fichier, tolérant).
  - **Registre de lentilles de revue au risque** [23] : **Standards** | **Spec** toujours (substrat `/code-review`) ; **Fidélité** [14], **Sécurité**, **Accessibilité** gatées par prédicat (surface visible ; tag `security` ou write-surface ∩ `SECURITY_PATHS`). Extensible ([24] propose de nouvelles lentilles).
- ***resolved*** = **toutes** les branches déclenchées vertes.
- **Échecs** : budget → pause ; too-big → re-slice autonome ; **gate rouge / crash non-budget** → **retry-N fresh** puis `ready-for-human` (compteur `Failures:` sur le ticket) ; **contractuel** → escalade directe. **Rollback** : snapshot `HEAD` pré-spawn → `git reset --hard`+`clean` ; branche `failed/<ticket>` avant l'escalade finale. Toute escalade pose une raison **`Escalation:`** [25].

## 9. Gate de valeur au niveau feature — [12]

- **Gate terminal** sur frontière-vide (avant l'exit succès [06]). Un **subagent frais** rejoue le **flux du `spec.md`** sur les **vrais assets**, produit un **playthrough persisté** (`docs/playthroughs/<feature>.md`, condition matérielle de clôture).
- Rouge → **hybride** : trou **interne** = ticket de câblage autonome ré-injecté / **contractuel** = `ready-for-human` ; borné (`PLAYTHROUGH_REINJECT_MAX`).
- **Échelle de défense** : ticket-level ([05] e2e / [13] visuel / [14] fidélité) + feature-level ([12] playthrough) + **canari** full-loop e2e maintenu dans le gate [08].

## 10. Concurrence par-ticket — [15] (+ [19]/[21])

- **Worktree git par itération** (rollback localisé). **Séquencement AFK** par **write-surfaces disjointes déclarées** (chevauchement → séquence ; fail-safe si inconnue) — **unifié avec le scope-guard** [19].
- **`claimed`** activé (claim atomique temp+mv, owner+horodatage). **Liveness du claim** [21] = **pid** (propriétaire = itération courte-durée → pas de heartbeat) + **TTL** backstop + **fail-open strict** ; bash-pur (`kill -0` + `mtime`) ; libération = les sorties de marquage [04]/[08].
- **Cap `MAX_PARALLEL`** + **throttle par le budget agrégé** [07] (spawn-gated). **Intégration sérialisée** (build //, repli un-à-un sur la branche principale ; couvre l'index LEARNINGS). Verrou de run [04] **conservé** (1 run pilote, N itérations).

## 11. Auto-apprentissage & ADR en delivery — [11]/[20]

- **Subagent retro frais** post-gate (Haiku, **auto-suppressif**) : écrit un **record de leçon** (`learning-records/NNNN`, index `LEARNINGS.md` injecté inline) **et/ou** un **ADR** (`docs/adr/`, décision d'archi **interne non-triviale** — le **contractuel escalade**), **et/ou** flagge un **gap de capacité** [24].
- **Anti-bruit** : 3 drains (dedup / supersession / **drain-par-promotion**). **Promotion** d'une leçon récurrente : **autonome** (guidance `CLAUDE.md`) ou **escaladée** (gate/lint/hook = contractuel → `ready-for-human`, jamais en silence).

## 12. Revue de capacités au fil de l'eau — [24]

- **Détecter ≠ créer** : une capacité (lentille/agent/skill) change le contrat → **toujours HITL** (discovery : décidée en sortie de charting ; delivery : le retro **propose → `ready-for-human`**, jamais auto-créé).
- **Barre** : récurrence **ou** classe non couverte ; **réutiliser-avant-créer** (étendre un brief > réutiliser un skill > créer neuf). « Étage escaladé de [11] appliqué aux capacités. »

## 13. Langues — [26]

- **`LANG_INTERACT`** (parole à l'humain, HITL only) ⟂ **`LANG_ARTIFACT`** (prose durable rédigée : docs + commentaires + commits + PR ; **pas** le code = Standards, **pas** le pack). AFK = artefact-only. Édition → matche la langue du fichier.
- **Gate de langue** objectif [26]/[08] (détection post-hoc, par-fichier, tolérant) — la consigne `CLAUDE.md` est **doublée d'un check**, pas seule.

## 14. Backend de tracker — [16]

- **Interface d'adaptateur** (`frontier` / `read_ticket` / `claim` / `mark_*` / `open_ticket` / `append_note` / `emit_receipt`), 3 impls `lib/tracker-<backend>.sh` : **`local`** (fichiers, défaut, dépendance minimale) · **`github`** · **`gitlab`** (audit/collab/CI). La boucle est agnostique.
- Distant : claim = assignee ; **liveness du claim en sidecar local** (concurrence mono-machine) ; **reçu = la PR** ; **`wait_ci` ON par défaut si CI détecté** (opt-out `WAIT_CI=off`) → le backend façonne la forme d'intégration (PR-par-itération distant / directe local). *Pas d'« offline » : le LLM exige le réseau ; `AFK ≠ offline`.*

## 15. La boucle humaine — [25]

- `human-loop.sh` (HITL, interactif) draine `ready-for-human`. **Routeur** par `Escalation:` : `decision`→grilling · `too-big`→to-tickets · `failed-impl`→implement/pair (amorcé `failed/<ticket>`+reçu) · `spec-gap`→to-spec · `sign-off`→approbation.
- **Anti-faux-vert** : tout code repasse le gate via réinjection `ready-for-agent` (jamais de `resolved` direct sauf `sign-off`). **HITL = jugement humain présent** (permissions = défaut de session). Ordre = impact de déblocage puis NN.

## 16. Form-factor, pack & installeur — [09]

- Déposé par **`npx` wizard** (auto-détecte, valide) → **moteur bash** (fallback sans node). Arborescence : `loop.sh` + `human-loop.sh` + `lib/*` (`select`, `budget`, `gate`, `state`, `claim`, `tracker-*`) + **substrat copié** (pinné) + `docs/agents/` (conventions tracker/triage) + `.scratch/` + `docs/adr` `docs/playthroughs` `docs/receipts` provisionnés + `settings.json` (posture headless, hook scope-guard optionnel [19]) + `CLAUDE.md` de base (mergé) + **`ralph.config.sh`** (le seul fichier réglé). Bootstrap une-commande → « prêt à discovery ».

## 17. Surface de configuration — `ralph.config.sh`

| Clé | Rôle | Ticket |
|---|---|---|
| `FEATURE` · `MODEL` | cible du run · modèle delivery | [09] |
| `TEST_CMD` · `TYPECHECK_CMD` | checks objectifs (**confirmation forcée**, anti-faux-vert) | [08]/[09] |
| `SOFT_LIMIT_TOKENS` (150K) | SIGTERM filet contexte | [03] |
| `THRESH_5H` · `THRESH_WEEK` · `USAGE_UA` | seuils budget + User-Agent endpoint | [07] |
| `ITER_CAP` · `STERILE_K` · `RETRY_N` · `HUMAN_CHECKPOINT_EVERY` | gardes anti-emballement + retries | [06]/[08] |
| `SCHEDULER` · `WEEKLY_RESUME` | chaîne one-shot + repli hebdo | [17] |
| `MAX_PARALLEL` | cap de parallélisme (fallback `=1` si test partagé) | [15] |
| `CLAIM_TTL` | backstop liveness du claim | [21] |
| `TRACKER_BACKEND` (local/github/gitlab) · `WAIT_CI` | backend + gate CI | [16] |
| `VISUAL_CMD` (+ flag vrais-assets) · `RUN_CMD` | vérif visuelle + lancement feature (**confirmation forcée**) | [13]/[12] |
| `SECURITY_PATHS` · `SECURITY_REFS` · `FIDELITY_REFS` | déclencheurs & refs des lentilles | [23]/[14] |
| `LANG_INTERACT` · `LANG_ARTIFACT` · `LANG_CHECK` (+ seuil) | langues + gate de langue (**confirmation forcée**) | [26] |
| cap index LEARNINGS · rétention reçus · `PLAYTHROUGH_REINJECT_MAX` | anti-bruit / bornes | [11]/[18]/[12] |

## 18. Prêt au handoff

Ce blueprint est **gelé** et **auto-suffisant** pour `/to-spec` → `/to-tickets` : il fixe le **quoi** (les décisions verrouillées, leur cohérence, la surface de config) sans produire de code. Le prototype jetable [`prototype-form-factor/`](prototype-form-factor/) incarne la forme cible (arborescence + `init.sh` + `ralph.config.sh` + `loop.sh`) comme matière première.

**Hors périmètre** (efforts distincts si la destination est redessinée) : **déploiement** · **réconciliation de la stratégie quota** (§5.3 de l'analyse) · **multi-provider** (codex/gemini/cursor/opencode/junie…).
