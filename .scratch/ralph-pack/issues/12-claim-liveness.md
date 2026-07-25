# 12 — Claim atomique + liveness

**What to build:** La prise atomique d'un ticket avant spawn (le retirant de la frontière pour les pickers concurrents) et la politique de **liveness** qui réclame un claim mort sans jamais provoquer de deadlock. Bash pur, sans heartbeat ni verrou séparé.

**Blocked by:** 02

**Write-surface:** `.claude/lib/claim.sh`, `test/claim.bats`

**Status:** ready-for-agent

- [ ] `claim` est atomique (temp + `mv`) et pose owner + horodatage ; un ticket claimé disparaît de la frontière pour les autres pickers.
- [ ] Liveness : pid vivant en primaire, `CLAIM_TTL` en backstop (anti pid-recycling), fail-open strict (incertain → réclamable, jamais de deadlock).
- [ ] Un claim dont le propriétaire est mort est réclamé au balayage ; implémenté en bash pur (`kill -0` + mtime).
- [ ] Le claim est libéré par les sorties de marquage (`resolved` / escalade).
