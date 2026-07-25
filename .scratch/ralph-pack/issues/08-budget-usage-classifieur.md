# 08 — Budget d'usage + gate de spawn proactif + classifieur

**What to build:** La surveillance du budget d'usage et son intégration dans la boucle : gate de spawn proactif **avant** chaque session, classifieur budget (un exit non-zéro est testé « budget ? » avant « échec »), pause/reprise sur la fenêtre de session.

**Blocked by:** 07

**Write-surface:** `.claude/lib/budget.sh`, `test/budget.bats`

**Status:** ready-for-agent

- [ ] La boucle interroge `GET /api/oauth/usage` (`User-Agent` obligatoire, cache 180 s) et lit `five_hour`, `seven_day`, `seven_day_opus`.
- [ ] Seuils asymétriques : `THRESH_5H` (agressif) et `THRESH_WEEK` (conservateur) ; le spawn est gated **avant** de lancer la session.
- [ ] Un dépassement de la fenêtre de session déclenche un `sleep` in-process jusqu'à `resets_at`, puis la boucle reprend.
- [ ] Le classifieur teste tout exit non-zéro « budget ? » avant de le compter comme échec ; une pause budget n'incrémente jamais `Failures:`.
- [ ] Sous les seuils, aucun impact sur le happy-path.
