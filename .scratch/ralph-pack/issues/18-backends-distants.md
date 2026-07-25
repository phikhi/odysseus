# 18 — Backends distants github + gitlab

**What to build:** Les implémentations distantes de l'adaptateur de tracker, satisfaisant **la même interface** que `local`, avec la forme d'intégration façonnée par le backend (claim = assignee, reçu = PR, `wait_ci`). La boucle reste agnostique.

**Blocked by:** 02, 10

**Write-surface:** `.claude/lib/tracker-github.sh`, `.claude/lib/tracker-gitlab.sh`, `test/tracker-remote.bats`

**Status:** ready-for-agent

- [ ] Les adaptateurs `github` et `gitlab` satisfont l'interface fixe ; la boucle reste agnostique (aucun changement de control-flow).
- [ ] En distant : claim = assignee ; reçu = la PR ; liveness du claim en **sidecar local** (concurrence mono-machine).
- [ ] `wait_ci` est ON par défaut si une CI est détectée (opt-out `WAIT_CI=off`) → intégration PR-par-itération.
- [ ] Le même scénario e2e que `local` (piloté par une API mockée) produit les mêmes transitions d'état observables.
