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

- **Contrainte posée par [26], livré le 29/07/2026 : la réinjection du ticket de câblage doit décider du compteur.** `Failures:` n'est remis à zéro que par `tracker_mark_resolved` (une livraison verte). `tracker_mark_ready` — le chemin qu'utilisera la réinjection de câblage de ce ticket — le laisse en place. Un ticket déjà réinjecté une fois, ou qui avait consommé des retries avant d'être livré puis rouvert par le playthrough, arrivera donc avec un budget entamé et pourra être escaladé à sa première tentative. À trancher ici, explicitement, et à écrire : soit la réinjection remet le compteur à zéro (et alors `PLAYTHROUGH_REINJECT_MAX` est le seul garde-fou contre la boucle infinie — c'est déjà son rôle), soit elle ne le remet pas et le ticket de câblage hérite d'un budget qu'il n'a pas dépensé. Le piège à ne pas rouvrir est écrit dans [26] : remettre le compteur à zéro entre deux retries est exactement ce que `RETRY_N` existe pour empêcher.
