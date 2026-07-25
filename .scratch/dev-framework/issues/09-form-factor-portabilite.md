# Form factor & portabilité du framework

Type: prototype
Status: resolved
Blocked by: 06, 07, 08

## Question

Comment le framework se **dépose dans n'importe quel futur projet** ? (Objectif de réutilisabilité de la destination.)

À trancher (s'appuie sur le control-flow [06], le budget [07], le gate QA [08] — il faut savoir quels fichiers/loop existent) :
- Forme : **template repo** à cloner, **script d'install** (`init.sh`), ou **pack de skills + `loop.sh` + settings** déposé dans `.claude/` ?
- Quels fichiers atterrissent dans un projet neuf : le script de boucle, les skills réutilisés (symlink vs copie), les conventions de tracker (`.scratch/`), le `CLAUDE.md` de base ?
- Configuration par projet : qu'est-ce qui varie d'un projet à l'autre (modèle, tools autorisés, budget) et où se règle-t-il ?
- Bootstrap : une commande unique passe-t-elle un dépôt vierge de « rien » à « prêt à discovery » ?
- Prototype léger attendu : arborescence + `init` factice pour réagir dessus.

## Answer

Décision verrouillée (prototype HITL). Prototype jetable capturé sous [`../prototype-form-factor/`](../prototype-form-factor/) (README + `init.sh` + `ralph.config.sh` + `loop.sh` assemblant les décisions 04/06/07/08 ; ce repo n'étant pas git, pas de branche jetable → capture dans le tracker). S'appuie sur control-flow [06], budget [07], gate QA [08].

**Forme du dépôt — pack + installeur double front-end.** Le framework EST un **pack** (`loop.sh` + `lib/` + skills + conventions + `CLAUDE.md` base + `settings.json`) **déposé dans le projet cible**. *Pas* un template repo (greenfield only ; cloner n'aide pas un projet existant).
- **npx wizard** comme front-end d'installation : interactif, **auto-détecte** le projet, valide, collecte la config — puis **appelle un moteur de dépôt en bash**.
- **Moteur de dépôt bash** : pose le pack, `git init` si besoin, crée `.scratch/`, merge `CLAUDE.md`, écrit `ralph.config.sh`. Lançable **seul** (non-interactif via flags/env) → **fallback sans node** (CI, container minimal, bootstrap automatisé). Une seule logique de dépôt, deux front-ends (pas de dual-maintenance).
- Insight : l'installeur tourne pendant la **discovery, sur la machine humaine** (node quasi toujours présent) → sa dépendance node **ne fuit pas** dans la sandbox ; le pack *déposé* reste **100 % bash/markdown**.

**Skills — upstream pinné, set complet.** Sourcés depuis **`mattpocock/skills` à un tag pinné** (le wizard **délègue à `setup-matt-pocock-skills`**), **copiés en dur** dans `.claude/skills/` (self-contained/sandbox-safe). Décision *pin vs float* tranchée en faveur du **pin** (le framework vend du déterminisme : des skills qui bougent sous une session AFK = non-déterminisme invisible + breaking change amont non maîtrisé). Réf enregistrée (`SKILLS_REF="vX.Y.Z"`) ; **`--update` re-pin** au dernier tag (latest = acte délibéré, jamais silencieux). **Set complet installé par défaut** (sur-provisionner > sous-provisionner : une session AFK ne peut pas ajouter un skill manquant en cours de run ; le coût d'un skill inutilisé est négligeable) ; le wizard **propose de trimmer** les hors-sujet (teach, ask-matt…) pour un footprint lean.

**Fichiers déposés dans le projet cible.** `init.sh` (bootstrap, auto-suppressible) · `CLAUDE.md` base (**mergé** si présent, jamais écrasé) · `.claude/settings.json` (posture headless) · `.claude/ralph.config.sh` (config par projet) · `.claude/loop.sh` (control-flow [06]) · `.claude/lib/{select,budget,gate,state}.sh` ([04][07][08][04]) · `.claude/skills/` (set complet pinné) · `docs/agents/{issue-tracker,triage-labels}.md` · `.scratch/` (racine tracker).

**Config par projet — un seul fichier.** `.claude/ralph.config.sh`, sourcé par `loop.sh`. Champs : `FEATURE`, `MODEL`, `TEST_CMD`, `TYPECHECK_CMD`, `THRESH_5H`, `THRESH_WEEK`, `USAGE_UA`, `SOFT_LIMIT_TOKENS`, `ITER_CAP`, `STERILE_K`, `RETRY_N`, `HUMAN_CHECKPOINT_EVERY`, `WEEKLY_RESUME`, `SKILLS_REF`.

**Défauts de config.** Défauts **universels pré-remplis** (aux valeurs des tickets : `MODEL=opus`, `THRESH_5H=90`, `THRESH_WEEK=85`, `SOFT_LIMIT_TOKENS=150000`, `ITER_CAP=200`, `STERILE_K=5`, `RETRY_N=2`, `HUMAN_CHECKPOINT_EVERY=0`, `WEEKLY_RESUME=human`) + **auto-détection** (`TEST_CMD`/`TYPECHECK_CMD` selon le type de projet, `USAGE_UA` via `claude --version`, `SKILLS_REF` = dernier tag). **Confirmation FORCÉE des critiques** : `TEST_CMD`/`TYPECHECK_CMD` (une commande fausse = **faux-vert silencieux** au gate [08] : des tickets marqués `resolved` sans tests réels — pire échec en AFK) + `FEATURE` (sans défaut sûr).

**Bootstrap une commande.** `npx <org>/ralph-init` (ou `bash init.sh` en fallback) passe un dépôt de « rien » à **« prêt à discovery »** : dépose le pack, fetch skills@ref, `.scratch/`, merge `CLAUDE.md`, écrit `ralph.config.sh` (défauts + confirmations). Ensuite : discovery HITL (grilling/domain-modeling → to-spec → to-tickets, porte [05]) → éditer la config → `bash .claude/loop.sh` (delivery autonome, **en sandbox** [D1/06]).

### Contraintes / notes pour l'assemblage du blueprint

- L'**exécution sandboxée** de la delivery (D1/[06]) est une **précondition d'environnement**, pas fournie par le pack lui-même : à documenter dans le blueprint (le pack suppose un env de confiance/sandboxé).
- Le pack suppose un **projet git** dans l'env cible (rollback + branches `failed/<ticket>` [08]) et des **commandes test/typecheck** configurables ([08]).
- Le **cron/launchd optionnel** de reprise post-`pause-hebdo` ([07]) et le **surfacing du `run.log`** ([06]/[07]) sont des extensions du form-factor, à décrire dans le blueprint.
