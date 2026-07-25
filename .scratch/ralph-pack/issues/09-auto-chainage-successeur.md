# 09 — Auto-chaînage : successeur one-shot + scheduler

**What to build:** Le franchissement d'un mur hebdomadaire sans faire dormir un process des jours : un **successeur one-shot** programmé au reset de la fenêtre bloquante, via une chaîne de scheduler auto-détectée et ordonnée par survie au reboot, avec repli humain si aucun scheduler.

**Blocked by:** 08

**Write-surface:** `.claude/lib/scheduler.sh`, `test/scheduler.bats`

**Status:** ready-for-agent

- [ ] Un mur hebdo programme un successeur one-shot au `resets_at` de la fenêtre bloquante — **jamais `+7j`**.
- [ ] La chaîne de scheduler est auto-détectée et ordonnée par survie au reboot (`at` avant `systemd-run` transient ; variantes par plateforme Linux/macOS) ; le skill cloud `schedule` n'est **pas** dans la chaîne locale.
- [ ] Sans scheduler disponible, la boucle sort proprement en `pause-hebdo` (repli humain).
- [ ] Anti-double-run : le successeur est singleton et protégé par le verrou de run ; deux successeurs ne se chevauchent jamais.
- [ ] Un fake `at` reçoit exactement une programmation, avec la bonne échéance (vérifié via le seam).
