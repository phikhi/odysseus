# 04 — Filet smart-zone (auto-compact OFF + SIGTERM 150K)

**What to build:** Le filet runtime dur qui garantit qu'une session finit en smart zone, indépendamment du découpage : auto-compact désactivé, et SIGTERM de la session au franchissement du seuil mou 150K, détecté sur le flux stream-json. Le dur 200K reste la frontière dumb-zone documentée.

**Blocked by:** 03

**Write-surface:** `.claude/lib/monitor.sh`, `test/smart-zone.bats`

**Status:** ready-for-agent

- [ ] L'auto-compact est forcé OFF pour toute session spawnée par la boucle.
- [ ] Un fake `claude` dont le flux franchit `SOFT_LIMIT_TOKENS` (150K) reçoit un SIGTERM ; l'itération est traitée comme non-succès (rollback + suite), pas comme `resolved`.
- [ ] Sous le seuil, aucune interruption : le monitor n'affecte pas le happy-path d'[03].
- [ ] Le seuil est piloté par `SOFT_LIMIT_TOKENS` (config) ; le dur 200K = frontière dumb-zone documentée.
