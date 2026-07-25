# 11 — Gate de valeur feature (playthrough terminal + réinjection hybride)

**What to build:** Le **gate terminal** de niveau feature : à frontière vide, un subagent frais rejoue le flux du `spec.md` sur les **vrais assets** et produit un **playthrough persisté** (condition matérielle de clôture). Un playthrough rouge est traité en hybride borné. Attrape les **trous de câblage** que les tests unitaires ratent.

**Blocked by:** 07

**Write-surface:** `.claude/lib/playthrough.sh`, `test/playthrough.bats`

**Status:** ready-for-agent

- [ ] À frontière vide, **avant** l'exit succès, un subagent frais rejoue le flux utilisateur du `spec.md` sur les vrais assets et écrit `docs/playthroughs/<feature>.md`.
- [ ] La clôture de feature (exit succès) n'a lieu que si le playthrough est vert et persisté.
- [ ] Un trou de câblage **interne** réinjecte un ticket de câblage autonome en `ready-for-agent` ; un trou **contractuel** escalade en `ready-for-human`.
- [ ] La réinjection est bornée par `PLAYTHROUGH_REINJECT_MAX` (pas de boucle infinie).
- [ ] Un canari full-loop e2e est maintenu dans le gate comme régression du pack.
