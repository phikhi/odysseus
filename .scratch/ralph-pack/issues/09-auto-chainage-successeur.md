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

## Comments

- **Contrainte posée par la revue de [01]–[04] : les codes de sortie de `loop.sh` ont changé.** `0` signifie désormais « ce run a drainé la frontière » et **`5` « la frontière était déjà vide au démarrage »** (mauvais `FEATURE`, tout en triage, tracker illisible). Un successeur one-shot qui se réveille doit traiter `5` comme « plus rien à faire », pas comme un échec — et surtout ne pas se re-programmer en boucle dessus. `2` couvre maintenant aussi une config qui viderait le gate de son sens (`TEST_CMD`/`TYPECHECK_CMD` vides), ce qui est un cas où re-programmer un successeur ne servirait à rien : il refusera pareil.
