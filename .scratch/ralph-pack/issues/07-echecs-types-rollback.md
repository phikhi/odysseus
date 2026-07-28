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
- [ ] Un gate vert rend le travail de l'itération **durable** avant l'itération suivante ; un rollback ultérieur ne détruit rien de ce qui a déjà été gaté vert.

## Comments

- **Contrainte posée par [05] : un gate vert doit commiter.** Aujourd'hui rien ne rend durable le travail d'une itération résolue — il reste non commité dans l'arbre. Le `git reset --hard $PRE` + `git clean -fd` prévu ici **détruirait donc tout ce que le run a produit depuis son démarrage**, pas seulement la tentative ratée. Le rollback n'est correct qu'à partir du moment où chaque itération verte est commitée : le `HEAD` pré-spawn devient alors réellement « l'état d'avant cette itération ». C'est aussi ce qui donnera au reçu d'audit [10] un diff à référencer.
- Le scope-guard, lui, ne dépend plus de ce commit : il compare deux snapshots d'arbre pris autour de la session ([05] a dû le corriger après coup, voir ses commentaires). Mais il reste un `git rev-parse HEAD` pré-spawn à prendre **ici**, pour le rollback — un objet tree n'est pas un commit et ne se `reset --hard` pas.
- **Ce que [05] laisse à câbler ici** : `RALPH_GATE_SCOPE_CLASS` vaut `internal` (write-surface trop étroite → retry-N) ou `contract` (débordement dans la write-surface d'un autre ticket → escalade directe `ready-for-human`, sans consommer de retry, conformément à la décision de discovery [19]). La boucle logge la classe aujourd'hui ; personne n'agit dessus.
- **Trou connu à couvrir** : aucune branche du gate n'a de timeout. Une `TEST_CMD` qui pend fait pendre le run indéfiniment — le filet smart-zone ne surveille que la session. Un échec par timeout est un échec typé de plus.
