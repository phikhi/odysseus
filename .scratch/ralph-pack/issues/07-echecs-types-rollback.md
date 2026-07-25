# 07 — Échecs typés + rollback

**What to build:** La gestion des échecs de la boucle, par type : `too-big` → re-découpage autonome ; gate rouge / crash non-budget → retry-N en session fraîche puis `ready-for-human` ; contractuel → escalade directe. Avec rollback propre du dépôt et raison `Escalation:` posée sur toute escalade.

**Blocked by:** 05

**Write-surface:** `.claude/lib/failures.sh`, `test/failures.bats`

**Status:** ready-for-agent

- [ ] Un ticket « too-big » est re-découpé de façon autonome en préservant les AC (via `to-tickets`) et ré-injecté en frontière ; soupape humaine seulement si les AC ne peuvent être préservées.
- [ ] Un gate rouge / crash non-budget déclenche jusqu'à `RETRY_N` retries en session fraîche ; au-delà, le ticket passe `ready-for-human` avec le compteur `Failures:` incrémenté.
- [ ] Une décision contractuelle escalade directement, sans consommer les retries.
- [ ] Rollback : snapshot `HEAD` pré-spawn → `git reset --hard` + `git clean` ; le dépôt est propre après un échec.
- [ ] Avant l'escalade finale, une branche `failed/<ticket>` préserve la tentative ; toute escalade pose une ligne `Escalation:` (jeu fermé).
