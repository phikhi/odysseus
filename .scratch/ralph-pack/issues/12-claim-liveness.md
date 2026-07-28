# 12 — Claim atomique + liveness

**What to build:** La prise atomique d'un ticket avant spawn (le retirant de la frontière pour les pickers concurrents) et la politique de **liveness** qui réclame un claim mort sans jamais provoquer de deadlock. Bash pur, sans heartbeat ni verrou séparé.

**Blocked by:** 02

**Write-surface:** `.claude/lib/claim.sh`, `test/claim.bats`

**Status:** ready-for-agent

- [ ] `claim` est atomique (temp + `mv`) et pose owner + horodatage ; un ticket claimé disparaît de la frontière pour les autres pickers.
- [ ] Liveness : pid vivant en primaire, `CLAIM_TTL` en backstop (anti pid-recycling), fail-open strict (incertain → réclamable, jamais de deadlock).
- [ ] Un claim dont le propriétaire est mort est réclamé au balayage ; implémenté en bash pur (`kill -0` + mtime).
- [ ] Le claim est libéré par les sorties de marquage (`resolved` / escalade).

## Comments

- **Contrainte posée par la revue de [01]–[04] : la reprise d'une garde périmée n'est pas un test-and-set.** `state_guard_take` prend la garde par `mkdir` (atomique, correct), mais son chemin de *reprise* est `rm -rf` puis `mkdir` : deux runs qui constatent tous deux un propriétaire mort peuvent repartir tous deux avec la garde (A efface et crée, B efface la garde neuve de A et crée la sienne). Non reproduit — **0 fois sur 140 essais**, y compris avec des racers synchronisés — mais la fenêtre est réelle à la lecture.

  Pourquoi ça atterrit ici plutôt que d'être corrigé à chaud : la primitive porte à la fois le **verrou de run** et le **claim**, et c'est ce ticket qui possède la politique de liveness (pid vivant, `CLAIM_TTL`, fail-open). Deux raisons de ne pas laisser traîner : [13] multipliera les prises concurrentes par `MAX_PARALLEL`, et les gardes périmées deviennent la normale dès que des itérations se font tuer (SIGTERM du filet smart-zone, rollback [07]) — donc le chemin rare d'aujourd'hui devient le chemin courant.

  Correctif proposé, sans marqueur susceptible de rester coincé : **déplacer la garde périmée par `mv` vers un nom unique au process** (`<garde>.stale.$$`). Renommer un répertoire est atomique et exclusif — un seul racer réussit, le second échoue en ENOENT — après quoi tout le monde repasse par le `mkdir` normal, qui départage. Aucun deadlock possible si le gagnant meurt entre les deux : la garde n'existe simplement plus et le suivant la prend.

  Le test qui vaut : forcer l'entrelacement en asseyant l'exclusivité du *déplacement* (deux appels successifs, le second doit échouer), pas en lançant N racers — une course qui ne se reproduit pas 140 fois sur 140 ne rougira pas davantage en CI.
