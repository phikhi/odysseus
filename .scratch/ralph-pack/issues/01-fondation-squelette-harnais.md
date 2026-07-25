# 01 — Fondation : squelette de pack + harnais de test (seam process)

**What to build:** Le layout canonique du pack et le harnais qui rend tout le reste vérifiable via le **seam process** validé. Après ce ticket, un test peut lancer les scripts du pack dans un environnement entièrement injecté — tracker `local` en tmpdir, shims `claude`/`at`/`curl` sur le `PATH`, stubs `TEST_CMD`/`TYPECHECK_CMD`, tickets fixtures — et un `loop.sh` minimal source sa config et ses libs sans erreur. C'est le prefactor qui débloque toute la delivery.

**Blocked by:** None — can start immediately.

**Write-surface:** `.claude/settings.json`, `.claude/ralph.config.sh.example`, `.claude/lib/.gitkeep`, `test/helpers/**`, `test/fixtures/**`

**Status:** ready-for-agent

- [ ] Le layout du pack est posé : `.claude/{settings.json, ralph.config.sh.example, loop.sh (stub), lib/}` ; la posture headless de `settings.json` désactive l'auto-compact.
- [ ] `ralph.config.sh.example` déclare toutes les clés de la surface de config (blueprint §17) avec des valeurs de départ documentées.
- [ ] Le harnais expose : un tracker `local` jetable en tmpdir, des shims `claude`/`at`/`curl` sur le `PATH` scriptables par test, des stubs `TEST_CMD`/`TYPECHECK_CMD` à exit-code contrôlable, et un jeu de tickets fixtures.
- [ ] Un test « fumée » lance le pack dans cet environnement : le sourcing de la config et des libs se fait sans erreur, sortie propre.
- [ ] Aucune dépendance node n'est requise pour exécuter les tests (fallback bash).
