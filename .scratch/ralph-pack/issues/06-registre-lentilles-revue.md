# 06 — Registre de lentilles de revue (Standards|Spec + gated)

**What to build:** Le registre extensible de lentilles ajouté au fan du gate : **Standards** et **Spec** toujours actives (via `/code-review`), **Fidélité**, **Sécurité**, **Accessibilité** déclenchées par prédicat au risque. Un projet ajoute une lentille sans refondre le gate.

**Blocked by:** 05

**Write-surface:** `.claude/lib/lenses.sh`, `test/lenses.bats`

**Status:** ready-for-agent

- [ ] Standards et Spec s'exécutent pour tout ticket.
- [ ] La lentille Fidélité/Accessibilité se déclenche ssi le ticket a une surface visible ; Sécurité ssi tag `security` **ou** write-surface ∩ `SECURITY_PATHS`.
- [ ] Un ticket sans surface ni chemin sensible ne déclenche que Standards|Spec.
- [ ] Le registre est extensible : ajouter une lentille avec son prédicat ne modifie pas le control-flow du gate.
- [ ] Une lentille rouge rend le gate rouge (intégrée au *resolved* d'[05]).
