# 26 — `Failures:` compte des choses qui ne sont pas des échecs, et rien ne le remet à zéro

**What to build:** Rendre le compteur de retries fidèle à ce que son nom promet. Aujourd'hui `Failures:` est incrémenté par des événements qui ne sont pas des échecs d'implémentation — un claim dont le propriétaire n'est pas pingable et dont le TTL a expiré, y compris celui d'un **humain** — et il n'est remis à zéro par personne, ni par `tracker_mark_resolved`, ni par `tracker_mark_ready`. Un ticket peut donc être escaladé en `failed-impl` après avoir été livré vert.

**Blocked by:** None

**Write-surface:** `.claude/lib/failures.sh`, `.claude/lib/claim.sh`, `.claude/lib/tracker-local.sh`, `test/failures.bats`, `test/claim.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

- [ ] Un ticket marqué `resolved` repart d'une ardoise propre : le compteur ne survit pas à une livraison verte.
- [ ] Un claim que le pack ne peut pas pinger (tout `owner` non `pid:<n>`) et qui a seulement dépassé `CLAIM_TTL` ne consomme pas de retry en revenant sur la frontière — ou bien le pack assume de voler des tickets humains et le dit dans le ticket, dans le tableau de la frontière, et dans la note qu'il laisse.
- [ ] Une escalade `failed-impl` implique qu'au moins une session a réellement été jugée sur ce ticket.
- [ ] Le test distingue les deux causes d'incrément — une tentative jugée rouge, et un claim réclamé — plutôt que d'asserter la valeur du compteur.

## Comments

- **Origine : passe transversale 01→22, le 29/07/2026.** Sondé avec un ticket claimé `owner=alice at=2026-07-01T00:00:00Z` et `CLAIM_TTL=60`, rejoué trois fois de suite avec une session qui livre :

  ```
  run 1 -> status=resolved        failures=[1]  escalation=[]
  run 2 -> status=resolved        failures=[2]  escalation=[]
  run 3 -> status=ready-for-human failures=[3]  escalation=[failed-impl]
  ```

  Au run 3 le ticket est escaladé **sans qu'une session soit spawnée** : `failures_after_dead_owner` incrémente d'abord, compare au plafond, et escalade — alors que les deux runs précédents l'avaient livré vert. La raison écrite dans le ticket, `failed-impl`, est fausse dans les trois cas.

- **Deux défauts distincts, qui se composent.** Le premier est dans `failures_after_dead_owner` ([12]) : il compte l'attempt *avant* de savoir qu'il y en a eu une, ce qui est délibéré et défendu dans son propre commentaire — « le coût de l'erreur inverse est pire : un ticket qui tue son run à chaque fois serait re-broyé chaque nuit pour toujours ». Ce raisonnement tient pour un `owner=pid:<n>` dont le process a disparu. Il ne tient pas pour un `owner` que le pack a explicitement décidé de **ne pas** pinger : `claim.sh` écrit que « voler le ticket d'un humain serait pire que d'attendre le backstop », puis le vole quand le backstop tombe — et lui facture un échec. Avec le `CLAIM_TTL` par défaut de 5400 s, un humain qui s'assigne un ticket le matin le retrouve volé et pénalisé le soir.

  Le second est dans le cycle de vie du champ : `tracker_mark_resolved` fait `Status resolved, Claimed --drop` et laisse `Failures:` en place. Le compteur est donc cumulatif sur toute la vie du ticket, à travers les résolutions.

- **Ce qui était déjà écrit, et ce qui est nouveau.** [16] porte depuis longtemps « Remettre `Failures:` à zéro en réinjectant », mais uniquement pour `tracker_mark_ready` depuis le puits humain — et c'est un travail de la boucle humaine, qui n'existe pas encore. Ce que la sonde ajoute : le même trou existe sur `tracker_mark_resolved`, dans la boucle AFK, aujourd'hui. Et [16] a déjà noté que `failed-impl` peut arriver sans implémentation ratée ; ce qui est nouveau, c'est qu'il peut arriver après une implémentation **réussie**.

- **Piège pour qui livrera ça : remettre le compteur à zéro trop tôt rouvre un vrai trou.** Le compteur est ce qui borne le re-broyage d'un ticket toxique. Le remettre à zéro sur `unclaim` — donc entre deux retries — ferait boucler la boucle pour toujours sur un ticket dont chaque session est rouge, ce qui est exactement le mode de panne que `RETRY_N` existe pour empêcher. Le remettre à zéro sur `resolved` est sûr : un ticket vert n'est plus sur la frontière, et s'il y revient c'est pour une raison neuve.

- **Contrainte pour [16] et [11].** Les deux réinjectent : la boucle humaine depuis le puits, et le gate de valeur de [11] via un ticket de câblage. L'AC « `resolved` repart d'une ardoise propre » couvre le premier chemin de réinjection ; les autres doivent explicitement décider s'ils remettent le compteur à zéro, et leur ticket doit le dire — sinon un ticket réinjecté est escaladé à sa première tentative, sans retry, comme [16] l'avait déjà vu venir.
