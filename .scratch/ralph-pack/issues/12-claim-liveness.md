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
- **Confirmation par [07] : les gardes périmées deviennent bien le chemin courant.** Le rollback livré ne tue pas de session (il tourne après `wait`), mais le chien de garde du gate (`GATE_TIMEOUT`) descend maintenant tout l'arbre de processus d'une branche qui dépasse, et le filet [04] tue les sessions à la limite molle. Un run tué au mauvais moment laisse une garde de claim derrière lui, et c'est la reprise de garde périmée décrite ci-dessus qui la récupère.
- **Trou consigné par [21], à trancher ici : rien ne garde `.run.lock/` d'une session.** Le verrou de run vit sous `.scratch/<feature>/.run.lock/`, exactement la zone que le scope-guard et le rollback excluent tous deux comme bookkeeping. La protection de [21] restaure `issues/` et **s'arrête là** — elle ne peut pas s'étendre au reste de `.scratch/<feature>/`, parce que le flux `.session.*.jsonl` s'y écrit *pendant* la fenêtre qu'elle surveille, donc chaque itération y aurait un delta légitime. Conséquence : une session qui fait `rm -rf .scratch/<feature>/.run.lock` laisse un second run démarrer sur le même tracker, et le premier ne le sait pas. Rien ne le détecte, rien ne l'annule. La politique de liveness étant ici, c'est ici qu'il faut décider ce qui tient le verrou : un fichier sentinelle hors de la zone que les sessions peuvent atteindre, une vérification que le verrou tenu est toujours *le nôtre* entre deux itérations, ou l'aveu explicite dans `docs/frontiere-de-confiance.md` que rien ne le tient. Ligne déjà ajoutée au tableau, en attente de propriétaire.

- **Le trou du verrou de run n'est pas théorique : sondé le 28/07/2026, il est vivant et silencieux.** Scénario : deux tickets, la session de l'itération 1 fait `rm -rf .scratch/<feature>/.run.lock`. Résultat observé :

  ```
  exit 0
  session 1: LOCK ABSENT
  session 2: LOCK ABSENT
  lock après le run: absent
  statuts: 01=resolved 02=resolved
  ```

  Le run **continue sans un mot**, l'itération 2 est broyée sans verrou, et rien dans la sortie ni dans le journal ne dit qu'il n'en tenait plus. Le lock n'est jamais recréé — `run_lock_acquire` n'est appelé qu'une fois, au démarrage — et `run_lock_release` ne se plaint pas d'un verrou absent (`[ -d "$guard" ] || return 0`).

  **Pourquoi c'est un faux vert et pas seulement une gêne** : à partir de là, une seconde invocation de `loop.sh` démarre (le `mkdir` réussit, il n'y a plus rien) et broie en parallèle — sans qu'aucun `MAX_PARALLEL` n'existe. Le claim atomique empêche les deux runs de prendre le même ticket, mais le **commit sur vert** de [07] est global : `git update-ref HEAD` sans vérification de l'ancienne valeur, donc deux runs qui commitent s'écrasent l'un l'autre. Du travail gaté vert disparaît de l'historique, et les deux runs rapportent `resolved`.

  **Correctif minimal, à trancher ici** : la boucle re-vérifie en tête de chaque itération que le verrou qu'elle a pris est toujours là *et* toujours le sien (`run_lock_held_by` = `$$`), et s'arrête bruyamment sinon — un code de sortie de garde, comme l'arrêt sur stérilité. Ça transforme un faux vert silencieux en arrêt lisible, sans rien décider de la politique de liveness. Le correctif complet (sortir le verrou de la zone que les sessions atteignent) est un choix de conception qui appartient à ce ticket.
