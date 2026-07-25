# Analyse comparative — Workflow **Multiplyz** vs framework **Odysseus**

> Fichier temporaire d'analyse. Généré le 2026-07-24.
> Sources lues : `multiplyz/WORKFLOW.md`, `multiplyz/.claude/skills/orchestrate/SKILL.md`, `multiplyz/docs/adr/0011`, `multiplyz/.claude/agents/product-owner.md`, `multiplyz/.claude/skills/retro`, et côté Odysseus : `CONTEXT.md`, `.scratch/dev-framework/map.md` + issues, `prototype-form-factor/`, `research/limites-usage-claude.md`, `docs/agents/`.

---

## 0. Cadre : deux paris sur le même problème

Les deux objets répondent à **la même question** — *comment faire broyer une phase de delivery par des agents Claude Code, de façon autonome, sous contrainte de quota d'usage, sans dégrader la qualité de raisonnement ?* — et partagent le **même substrat** (les skills Matt Pocock : `grilling`, `domain-modeling`, `to-spec`, `to-tickets`, `implement`, `tdd`, `code-review`, `triage`, `research`, `wayfinder`), la **même langue**, et la **même séparation discovery (humain) / delivery (autonome)**.

Mais ce sont **deux incarnations opposées** :

| | **Multiplyz** | **Odysseus** |
|---|---|---|
| Nature | Workflow **incarné** dans un vrai produit (jeu de maths enfant, Next.js) | **Framework réutilisable** — un *blueprint gelé*, portable dans n'importe quel repo |
| Maturité | **Battle-tested** : forgé par des échecs réels (AUDIT, `LEARNINGS.md` de 477 Ko, 18 ADR) | **Conception uniquement** — « zéro code produit », un prototype jetable |
| Pari d'architecture | **Orchestrateur longue-durée** (conversation native) + délégation à des subagents + outils Agent/Workflow | **Ralph loop bash** qui relance une **session `claude -p` fraîche** par tâche |
| Passage d'état | Contexte gardé « plat » par **discipline de délégation**, jeté aux frontières de story | **Session fraîche jamais compactée** ; l'état durable vit dans les fichiers |
| Plateforme | **GitHub** (Issues + Project board + Actions + branch protection) | **Tracker local markdown** (`.scratch/<feature>/issues/NN-*.md`), pur bash/markdown |

**Le résumé le plus juste** : Multiplyz est *l'original organique* où le workflow a été inventé au contact du réel ; Odysseus est *la refonte propre et principielle*, extraite pour être portable — mais qui, en repartant d'une feuille blanche, **n'a pas encore réabsorbé les leçons douloureuses que Multiplyz a payées en production**. C'est le cœur de la section « ce qui devrait être implémenté ».

---

## 1. Différences de philosophie

### 1.1 Produit livré : un framework vs un jeu
Odysseus **est** le livrable (« Blueprint » : le design gelé du framework, prêt au handoff). Multiplyz livre un **jeu** ; son workflow est un moyen, pas une fin. Conséquence : Odysseus optimise la **généricité et la portabilité** ; Multiplyz optimise **ce jeu-là** (rôles `game-design`, `product-owner`, specs `ENGINE/ECONOMY/ART`…).

### 1.2 Anti-compaction dure vs contexte-plat-par-discipline
C'est **la** différence philosophique centrale.
- **Odysseus** érige en dogme : *la compaction mène en « dumb zone »*. La garantie « smart zone < 200K » est obtenue **par construction** — chaque tâche = un nouveau process `claude -p` au contexte neuf, avec `auto-compact OFF` et un filet runtime (SIGTERM à 150K mou / 200K dur). L'état ne survit **que** dans les fichiers, relus à neuf.
- **Multiplyz** garde **un orchestrateur qui vit longtemps** et reste « plat » par *discipline* : il délègue build/reviews/exploration à des subagents, ne garde que des « conclusions », et jette le contexte **aux frontières de story** (jamais au milieu). La garantie est *comportementale*, pas *structurelle*.

Odysseus a donc une garantie **plus forte** (mécanique) ; Multiplyz une garantie **plus souple** (mais qui dépend du respect du playbook).

### 1.3 Minimalisme mécanique vs richesse native
Odysseus : **pur bash + markdown**, zéro dépendance (fallback sans node), « décisions verrouillées → construction mécanique ». Multiplyz : exploite à fond le **natif Claude Code** (outils Agent/Workflow, hooks `settings.json`, subagents typés) **+ GitHub Actions + branch protection + CODEOWNERS**. Odysseus privilégie la **portabilité et l'auditabilité** ; Multiplyz la **puissance et l'intégration**.

### 1.4 Autonomie : delivery seule vs planning aussi délégué
Les deux gardent la **discovery en HITL**. Mais :
- Odysseus trace une **frontière nette** : 2 arrêts humains (seams + découpage), puis la boucle broie **uniquement** les tickets `ready-for-agent`. Le « contrat » (spec + tickets auto-suffisants) **est** la porte.
- Multiplyz **délègue aussi le planning** (ADR 0004) : l'orchestrateur trie le backlog, découpe l'épic, séquence/parallélise — le propriétaire n'intervient **que sur le drift**.

### 1.5 Fidélité produit comme préoccupation de premier ordre (Multiplyz uniquement)
Multiplyz a un **Product Owner** + un **game-design** qui valident que *la valeur atteint réellement l'enfant bout-en-bout* (règle #180), un **gate « parcours d'acceptation »** avec playthrough persisté, un **canari E2E full-loop**. Odysseus n'a que **deux axes** de revue (`Standards` | `Spec`) et « e2e si surface visible » — **aucun concept de fidélité produit assemblée**. (C'est précisément le trou que Multiplyz a découvert en production — voir §5 et §6.)

---

## 2. Différences de fonctionnement

| Dimension | **Multiplyz** | **Odysseus** |
|---|---|---|
| **Unité de travail** | Story GitHub (slice verticale) | Ticket markdown auto-suffisant (`NN-slug.md`), maille variable |
| **Sélection** | Orchestrateur trie + choisit la 1ʳᵉ story débloquée | Scan sans mémoire de la **frontière** (`open ∧ unblocked ∧ ready-for-agent`), **min NN** |
| **Passage d'état** | Délégation + jetable à la frontière de story | **Relance d'un process `claude -p` frais** (jamais `--continue`/`--resume`) |
| **Exécution** | Subagents en **worktrees** isolés, **parallèles** (WIP ~3-4) | **1 session fraîche = 1 tâche** ; **1 run par tracker** (verrou grossier) ; parallélisme par-ticket **hors-scope** |
| **Gate QA** | lint + typecheck + coverage + build + **E2E Playwright** en **CI GitHub Actions** (required checks) + reviewers scope + **PO** + captures | tests + typecheck (**bash local**) + **`code-review` 2 axes** (Standards\|Spec, subagents frais), **les 3 en //** |
| **Signal succès/échec** | Reviews ✅ + CI verte + branche à jour | `is_error` / exit non-zéro + `total_cost_usd` (JSON `stream-json`) |
| **Échec** | Fixes de consensus renvoyés au subagent de build ; escalade drift → `needs-owner` | **retry N fresh** (déf. 2) → `ready-for-human` ; **too-big → re-découpage autonome** |
| **Rollback** | Via git/PR (rien de mergé tant que rouge) | Snapshot `HEAD` pré-spawn → `git reset --hard` + `git clean` ; branche `failed/<ticket>` avant escalade |
| **Intégration** | **PR → merge par l'agent orchestrateur** (squash), branch protection sur `main` | **Pas de flux PR/merge** : marquage `resolved` local (temp + `mv`, atomique) sur le working tree |
| **Budget / quota** | **Mesure JSONL locale** + **réactif au message de limite** (ADR 0011) ; % serveur jugé *non lisible localement* | **Endpoint `GET /api/oauth/usage`** (`utilization` % + `resets_at`) ; seuils proactifs asymétriques (5h ~90 %, hebdo ~85 %) |
| **Reprise après mur** | **Auto-chaînage** d'un successeur one-shot via skill `schedule` | 5h → `sleep` in-process jusqu'à `resets_at` ; hebdo → **exit `pause-hebdo`** (humain/cron) |
| **Concurrence** | **`session-lock.mjs`** consultatif *fail-open* élaboré (pid liveness, TTL 90 min, MAX_AGE, heartbeat/acquire/release, énumération fermée des sorties) | **Verrou de run grossier** (1 run/tracker), simple |
| **Apprentissage** | **`LEARNINGS.md`** versionné + **promotion** en règles dures (CLAUDE.md / lint / hook) via skill `retro` | **Journal de run** append-only, **non-autoritaire**, observabilité seule — **aucun apprentissage** |
| **Décisions** | **ADR** systématiques (`docs/adr/`) + Technical Design pour `needs-design` | ADR = **contexte ambiant de discovery** ; la delivery n'en produit pas |
| **Form factor** | Baked-in dans le repo (CLAUDE.md 55 Ko, LEARNINGS 477 Ko) | **Pack déposé par `npx`/`init.sh`** dans n'importe quel repo ; 1 seul fichier à régler (`ralph.config.sh`) |

---

## 3. Avantages

### Odysseus
- **Garantie de qualité de raisonnement par construction** : la session fraîche non-compactée *ne peut pas* dériver en dumb-zone. Plus robuste que la discipline comportementale.
- **Portable et sans dépendance** : pur bash/markdown, se dépose dans tout repo (vierge ou existant) en une commande ; fallback sans node.
- **Simple, mécanique, auditable** : la `loop.sh` tient en ~55 lignes lisibles ; chaque décision est tracée à un ticket.
- **AFK-safe by design** : aucun humain dans la boucle de delivery ; re-découpage autonome des slices trop grosses.
- **Contrat discovery→delivery net** : une seule porte, tickets auto-suffisants, source de vérité unique (le tracker).
- **Signal quota potentiellement plus fort** : l'endpoint `/api/oauth/usage` donne le **% serveur réel** + `resets_at` (que Multiplyz croyait indisponible — voir §6.3).

### Multiplyz
- **Éprouvé en conditions réelles** : chaque garde-fou correspond à un échec vécu (le `LEARNINGS.md` et l'AUDIT sont l'historique de ces cicatrices).
- **Gates de qualité riches** : DoD niveau feature, playthrough narré persisté, canari E2E full-loop, vérification visuelle des pixels.
- **Le framework s'améliore lui-même** : boucle `retro` → `LEARNINGS` → **promotion** en règle dure. Il apprend.
- **Fidélité produit** : PO + game-design attrapent la classe de bug « tickets verts mais produit cassé » que l'ingénierie ne voit pas.
- **Parallélisme réel** (worktrees) + intégration GitHub (audit, CI required-checks, branch protection, collaboration humaine possible).
- **Quota honnête** : ADR 0011 a explicitement **banni l'hallucination de %** et modélise les deux fenêtres (5h + hebdo).
- **Survit aux murs de quota** : auto-chaînage d'un successeur programmé.

---

## 4. Inconvénients

### Odysseus
- **Non construit** : blueprint gelé, **jamais exécuté** → risques inconnus (le prototype est explicitement jetable/stub).
- **Aucun apprentissage** : le journal est non-autoritaire ; or *fresh-session-per-task* est le contexte qui en a **le plus besoin** — sans mémoire durable, chaque session peut **répéter la même erreur** que la précédente.
- **Pas de gate de valeur bout-en-bout** : le gate par-ticket peut valider des tickets verts qui **ne s'assemblent jamais** en produit vivant — exactement l'échec `AUDIT §4` de Multiplyz.
- **Gate purement local** : pas de CI required-checks ni de branch protection ; le filet est bash local (mitigé par la confirmation forcée de `TEST_CMD`/`TYPECHECK_CMD` anti-faux-vert, mais moins solide qu'une CI tierce).
- **Pas d'audit externe** : marquage `resolved` local, pas de PR/diff/captures qu'un humain puisse relire a posteriori.
- **Stratégie quota fragile** : l'endpoint `/api/oauth/usage` est **non documenté** (beta header susceptible de changer), et la recherche elle-même note libellés/exit-codes instables. Repose sur un signal qui peut casser sans préavis.
- **Coût potentiel** : relancer une session à contexte neuf par tâche **re-paie la lecture du contexte** à chaque itération (vs délégation qui amortit).

### Multiplyz
- **Non portable** : profondément couplé à ce projet (specs, docs, agents `game-design`…). Réutiliser ailleurs = tout réécrire.
- **Lourd et complexe** : CLAUDE.md 55 Ko, LEARNINGS 477 Ko, `session-lock.mjs` avec énumération fermée de 9 sorties… charge cognitive/contexte élevée, surface de bug du verrou non-triviale.
- **Garantie de contexte comportementale** : « plat par délégation » **dépend** du respect du playbook ; un orchestrateur indiscipliné peut saturer/compacter.
- **Verrou consultatif fail-open** : *ne garantit pas* l'absence de collision (documenté honnêtement) ; l'auto-chaînage peut **casser en silence** (« projet gelé en silence ») si un `release` est sauté.
- **Dépendance GitHub** (repo + Actions + `gh`) et scheduling cloud (gating plan).

---

## 5. Ce qui **DEVRAIT** être implémenté dans Odysseus

> Ces cinq points **corrigent un manque avéré** : chacun est une leçon que Multiplyz a **payée en production** et qu'Odysseus, parti d'une feuille blanche, n'a pas encore réabsorbée. À traiter **avant de geler définitivement le blueprint**.

1. **Une boucle d'auto-apprentissage durable (`LEARNINGS` + promotion).**
   Le journal de run actuel est *non-autoritaire* et n'apprend rien. Or le pari « session fraîche par tâche » est **précisément celui qui a le plus besoin d'une mémoire externe** : sans elle, l'itération N+1 ignore ce qui a cassé à l'itération N. Il faut un fichier de leçons **lu par chaque session fraîche** (via les pointeurs du ticket) + un mécanisme de **promotion** des leçons récurrentes en règles dures (CLAUDE.md / gate). Le skill `teach` du substrat fournit déjà le format ; il n'est juste pas câblé dans la ralph loop.

2. **Un gate de valeur produit *bout-en-bout* au niveau feature (playthrough).**
   Le gate par-ticket d'Odysseus (tests + typecheck + review 2 axes) **prouve qu'une slice est verte, pas que la feature est vécue**. C'est *littéralement* l'échec `AUDIT-2026-07-20` de Multiplyz : 8 épics « clos », tous les tickets verts, mais navigation cassée, art jamais affiché, économie absente. Ajouter à la **fermeture d'une feature** un gate « parcours d'acceptation » : un agent pilote le vrai flux sur les vrais assets et produit un **artefact persisté** (pas jetable en contexte). Sinon Odysseus reproduira ce bug de classe.

3. **Réconcilier la stratégie quota avec l'ADR 0011 de Multiplyz.**
   Les deux systèmes divergent, et **chacun détient une pièce que l'autre ignore** :
   - Odysseus **doit** adopter les garde-fous durs de l'ADR 0011 : *(a)* **le message de limite est la seule autorité « coupé »** — ne jamais halluciner un `%` (les faux arrêts/démarrages viennent de là) ; *(b)* **modéliser les DEUX fenêtres** (5h **et** hebdo), lire `resets_at`, **jamais `+7 j`** en dur ; *(c)* distinguer 429 transitoire ≠ épuisement de plan (déjà noté dans sa recherche, mais à graver dans la logique).
   - **Inversement** (bonus § réciproque) : Odysseus a trouvé l'endpoint `/api/oauth/usage` que l'ADR 0011 croyait inexistant (« aucun fichier local ne contient le % serveur »). Cet endpoint **est** le « signal d'autorité en local » dont l'ADR 0011 dit *« si Anthropic l'expose un jour, le brancher »*. Odysseus peut donc garder l'endpoint comme **signal proactif**, **mais** en le traitant comme un *proxy faillible* et en gardant **le message comme autorité de STOP** + un **fallback JSONL** si l'endpoint est indispo.

4. **Vérification visuelle des surfaces UI (vrai art + non-occlusion).**
   Odysseus dit « e2e si surface visible » — insuffisant. Multiplyz a durement appris (#170/#180) qu'un panel de tests verts sur un front **jamais rendu visible** (recouvert, fixture au lieu du vrai asset) = DoD **non** satisfait. Toute tâche à surface visible devrait exiger une **capture sur les vrais assets** + une **garde de non-occlusion** (`boundingClientRect`).

5. **Un axe de revue « fidélité » (au-delà de Standards/Spec).**
   L'axe `Spec` vérifie la conformité au ticket ; il ne vérifie pas que *la valeur atteint l'utilisateur*. Ajouter un 3ᵉ regard (l'équivalent léger et générique du `product-owner`) — « ce mécanisme est-il réellement consommé/câblé jusqu'à l'écran ? » — attrape la classe de bug que l'ingénierie approuve à tort.

---

## 6. Ce qui **POURRAIT** être implémenté dans Odysseus

> Améliorations **optionnelles** : elles enrichissent sans corriger un défaut critique. Certaines contredisent des choix volontaires d'Odysseus — à peser contre son minimalisme.

1. **Parallélisme par-ticket au sein d'une feature (worktrees).**
   Odysseus laisse la concurrence par-ticket **hors-scope volontairement** (le champ `claimed` est réservé « au cas où »). L'emprunter à Multiplyz (worktrees isolés, séquencement par surfaces partagées, cap de WIP) accélérerait la delivery — au prix de la simplicité et d'un verrou plus fin.

2. **Backend tracker GitHub/GitLab optionnel.**
   Déjà **anticipé** : `setup-matt-pocock-skills` embarque `issue-tracker-github.md` / `-gitlab.md` / `-local.md`. Offrir GitHub en option apporterait audit trail, CI required-checks et collaboration humaine — au prix de la portabilité « pur local ».

3. **Auto-chaînage d'un successeur one-shot pour le mur hebdo.**
   Alternative au `exit pause-hebdo` (relance humaine) : programmer un run one-shot au reset (à la Multiplyz, skill `schedule`), en gardant la garde anti-double-run.

4. **Artefact d'audit a posteriori par itération.**
   Committer un reçu (diff + captures + résultats de gate) pour permettre au propriétaire une **relecture asynchrone** — l'équivalent léger du playthrough persisté, sans imposer le flux PR.

5. **Scope-guard (l'agent ne touche que les fichiers de son ticket).**
   Multiplyz l'impose par hook. Chez Odysseus, la sandbox + la session fraîche + le snapshot/rollback réduisent déjà le risque — mais un scope-guard resserrerait l'anti-drift.

6. **Produire des ADR pendant la delivery.**
   Quand une session prend une décision d'archi non triviale, la capturer (le format ADR existe dans `domain-modeling`). Utile surtout couplé au point 5.1 (apprentissage) : une décision tracée nourrit les sessions suivantes.

7. **Verrou de session plus fin** — seulement **si** on adopte le point 6.1 (concurrence par-ticket). Le `session-lock.mjs` de Multiplyz est un modèle de référence (fail-open, heartbeat, énumération fermée des sorties), mais c'est de la complexité à n'ajouter que si le besoin de concurrence le justifie.

---

## 7. Bonus — ce que Multiplyz pourrait apprendre d'Odysseus (réciproque)

L'échange n'est pas à sens unique :
- **La garantie smart-zone par session fraîche** est structurellement plus sûre que le « contexte plat par délégation » de Multiplyz, qui repose sur la discipline. Multiplyz pourrait durcir : pour les tâches longues, spawn un process frais plutôt que de compter sur le fait de « rester plat ».
- **L'endpoint `/api/oauth/usage`** (§6.3) est le « signal serveur en local » que l'ADR 0011 croyait inexistant → il pourrait **superseder partiellement** la limitation « proxy » de 0011.
- **Le verrou de run grossier** (1 run/tracker) d'Odysseus est bien plus simple que le lock consultatif fail-open de Multiplyz — pertinent si Multiplyz pouvait réduire son besoin de concurrence.

---

## 8. Synthèse & recommandation

**Odysseus est la bonne cible** pour un framework portable et réutilisable : son pari anti-compaction et son minimalisme bash sont architecturalement plus propres et plus robustes que l'orchestrateur longue-durée de Multiplyz. **Mais il souffre de son point fort** : en repartant d'une feuille blanche, il a laissé de côté les leçons que Multiplyz a saignées en production.

**Avant de geler le blueprint**, absorber en priorité les points **§5.1 (apprentissage durable)**, **§5.2 (gate de valeur bout-en-bout)** et **§5.3 (réconciliation quota)** — ce sont exactement les trois échecs les plus coûteux de Multiplyz (répétition d'erreurs, produit non assemblé, faux arrêts/démarrages quota). Les points §5.4 et §5.5 (visuel + fidélité) suivent de près pour tout projet à surface visible.

Les points **§6** sont à trancher au cas par cas : chacun ajoute de la puissance au prix du minimalisme qui fait la valeur d'Odysseus. Ne les adopter que sur besoin avéré.
