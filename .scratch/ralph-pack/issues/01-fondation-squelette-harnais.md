# 01 — Fondation : squelette de pack + harnais de test (seam process)

**What to build:** Le layout canonique du pack et le harnais qui rend tout le reste vérifiable via le **seam process** validé. Après ce ticket, un test peut lancer les scripts du pack dans un environnement entièrement injecté — tracker `local` en tmpdir, shims `claude`/`at`/`curl` sur le `PATH`, stubs `TEST_CMD`/`TYPECHECK_CMD`, tickets fixtures — et un `loop.sh` minimal source sa config et ses libs sans erreur. C'est le prefactor qui débloque toute la delivery.

**Blocked by:** None — can start immediately.

**Write-surface:** `.claude/settings.json`, `.claude/ralph.config.sh.example`, `.claude/loop.sh`, `.claude/lib/.gitkeep`, `test/helpers/**`, `test/fixtures/**`, `test/run.sh`, `test/smoke.bats`

**Status:** resolved

- [x] Le layout du pack est posé : `.claude/{settings.json, ralph.config.sh.example, loop.sh (stub), lib/}` ; la posture headless de `settings.json` désactive l'auto-compact.
- [x] `ralph.config.sh.example` déclare toutes les clés de la surface de config (blueprint §17) avec des valeurs de départ documentées.
- [x] Le harnais expose : un tracker `local` jetable en tmpdir, des shims `claude`/`at`/`curl` sur le `PATH` scriptables par test, des stubs `TEST_CMD`/`TYPECHECK_CMD` à exit-code contrôlable, et un jeu de tickets fixtures.
- [x] Un test « fumée » lance le pack dans cet environnement : le sourcing de la config et des libs se fait sans erreur, sortie propre.
- [x] Aucune dépendance node n'est requise pour exécuter les tests (fallback bash).

## Comments

- **Write-surface élargie en cours de route.** Trois fichiers exigés par les AC n'y figuraient pas : `.claude/loop.sh` (AC 1 le nomme explicitement), `test/run.sh` et `test/smoke.bats` (AC 4 exige un test de fumée, mais seuls `test/helpers/**` et `test/fixtures/**` étaient déclarés). La ligne ci-dessus a été corrigée pour refléter ce qui a réellement été écrit ; le scope-guard [19] doit voir la vraie surface.

- **Auto-compact désactivé deux fois** dans `settings.json` : la clé `autoCompactEnabled: false` et la variable `DISABLE_AUTO_COMPACT=1` via `env`. Les deux sont lues indépendamment par Claude Code (2.1.220), donc la posture headless survit à un changement de l'une. À noter : `.claude/settings.json` s'applique aussi aux sessions interactives de ce dépôt, pas seulement à la delivery AFK.

- **Runner de test maison (`microbats`)** plutôt que bats-core en dépendance. Le pack promet un fallback 100 % bash ; exiger une install pour tester le contredirait. `test/helpers/microbats.bash` interprète le sous-ensemble de la syntaxe bats que la suite utilise (`@test`, `setup`/`teardown`, `load`, `run`/`$status`/`$output`/`$lines`, `skip`), chaque test dans son propre process. Les fichiers `.bats` restent donc lisibles par bats-core : `test/run.sh` par défaut, `test/run.sh --bats` si l'outil est installé. Vérifié vert sous les deux.

- **Anti-node actif, pas déclaratif** : le harnais masque `node`/`npm`/`npx` sur le `PATH` par des échecs (exit 99). Si un module du pack finit par en dépendre, toute la suite casse au lieu de s'appuyer silencieusement sur la machine du dev.

- **Compatibilité bash 3.2** (le shell par défaut de macOS) pour le pack comme pour le harnais : pas de `mapfile`, pas de `declare -A`. Vérifié sur `/bin/bash 3.2.57`.

- **L'arbre git du projet-fixture reste propre en permanence** — `use_tickets` et `set_config` committent. Sinon le snapshot `HEAD` pré-spawn et le diff du scope-guard [08]/[19] partiraient d'un état sale, et un `git reset --hard` annulerait les overrides du test.

- **Langue** : le contenu du pack (code, commentaires, fixtures, messages) est en anglais, conformément au blueprint §13 qui exclut « le pack » du périmètre `LANG_ARTIFACT` — le pack se dépose dans des projets de n'importe quelle langue. Les artefacts de ce dépôt (spec, tickets, ADR) restent en français.

- **Formats provisoires à confirmer en [02]** : la ligne `**Claimed:** owner=… at=…` des fixtures et la sortie stream-json par défaut du shim `claude` sont des paris raisonnables, pas des contrats. Le ticket 02 fixe le format d'état, le 03 le parsing de la session.
