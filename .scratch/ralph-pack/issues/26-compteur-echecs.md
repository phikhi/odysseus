# 26 — `Failures:` compte des choses qui ne sont pas des échecs, et rien ne le remet à zéro

**What to build:** Rendre le compteur de retries fidèle à ce que son nom promet. Aujourd'hui `Failures:` est incrémenté par des événements qui ne sont pas des échecs d'implémentation — un claim dont le propriétaire n'est pas pingable et dont le TTL a expiré, y compris celui d'un **humain** — et il n'est remis à zéro par personne, ni par `tracker_mark_resolved`, ni par `tracker_mark_ready`. Un ticket peut donc être escaladé en `failed-impl` après avoir été livré vert.

**Blocked by:** None

**Write-surface:** `.claude/lib/failures.sh`, `.claude/lib/claim.sh`, `.claude/lib/tracker-local.sh`, `.claude/lib/tracker.sh`, `test/failures.bats`, `test/claim.bats`, `test/tracker-local.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`, `CONTEXT.md`, `README.md`

**Status:** resolved

- [x] Un ticket marqué `resolved` repart d'une ardoise propre : le compteur ne survit pas à une livraison verte. *`tracker_local_mark_resolved` lâche `Failures:` avec le claim.*
- [x] Un claim que le pack ne peut pas pinger (tout `owner` non `pid:<n>`) et qui a seulement dépassé `CLAIM_TTL` ne consomme pas de retry en revenant sur la frontière — ou bien le pack assume de voler des tickets humains et le dit dans le ticket, dans le tableau de la frontière, et dans la note qu'il laisse. *Les deux : il ne facture rien, **et** il dit le vol dans la note, le tableau et `CONTEXT.md` — le vol lui-même est le fail-open de [12], inchangé.*
- [x] Une escalade `failed-impl` implique qu'au moins une session a réellement été jugée sur ce ticket. *Elle n'est plus posée que par `failures_handle`, qui ne tourne qu'après un spawn ; le plafond du reclaim escalade en `decision`.*
- [x] Le test distingue les deux causes d'incrément — une tentative jugée rouge, et un claim réclamé — plutôt que d'asserter la valeur du compteur. *Un test par cause, plus un qui les compose sur le même ticket et vérifie que la raison d'escalade suit la dernière.*

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

## Livré le 29/07/2026

- **Ce qui tient maintenant, en trois lignes.** `tracker_local_mark_resolved` lâche `Failures:` en même temps que `Claimed` — l'obligation est écrite dans l'interface d'adaptateur (`tracker.sh`), pas seulement dans le backend, sinon [18] la réintroduit. `claim_owner_kind` (claim.sh) est la seule fonction qui connaisse la forme `owner=pid:<n>`, et `failures_after_dead_owner` ne facture que le genre `run`. Le plafond atteint par un reclaim escalade en `decision`, plus en `failed-impl`.

- **Décision : le prix, pas le vol.** Le fail-open de [12] reste entier — `CLAIM_TTL` prend le ticket d'un humain, et c'est voulu, l'alternative étant un ticket bloqué pour toujours. Ce qui change est la facture. Le vol est désormais **dit là où la personne qui a perdu le claim regardera** : une note sur le ticket, qui recopie le record verbatim parce que `tracker_unclaim` lâche le champ juste après — la note est la dernière copie du claim. Trois genres d'owner, deux prix : `run` (un pid du pack) facturé, `foreign` et `unreadable` rendus gratuitement. Un record illisible n'est pas attribuable à un run du pack, donc pas facturable non plus : le défaut par défaut de l'argument est `foreign`, pour qu'un appelant oublieux sous-borne le re-broyage (visible dans le tracker) au lieu de facturer des propriétaires qu'il n'a jamais pingés (invisible).

- **Décision : `decision` plutôt qu'une sixième raison.** Le jeu de `Escalation:` est fermé (`CONTEXT.md`), la boucle humaine route dessus, et [12] avait délibérément réutilisé `failed-impl` en écrivant que « implement/pair est le bon guichet pour un ticket qui tue son run ». L'AC 3 tranche l'inverse : un humain envoyé chez implement/pair va chercher une branche `failed/<ticket>` et une suite rouge qui n'ont jamais existé. Élargir le jeu fermé aurait été une décision de vocabulaire à imposer au routeur de [16], qui n'existe pas encore ; `decision` (→ grilling) est le bon guichet — quelqu'un doit arbitrer si le ticket tue son run ou si c'est l'hôte — et la note dit ce que la raison seule ne dit pas. **Si [16] veut deux guichets distincts, c'est lui qui ouvre la sixième raison**, avec `CONTEXT.md`.

- **Ce qui reste conflé, exprès : deux causes, un champ.** `Failures:` compte encore une tentative jugée rouge *et* un reclaim d'un run mort, dans le même entier. Un second champ aurait doublé l'état durable du tracker (spec §154) pour un distinguo qui existe déjà ailleurs : `run.log` porte `reclaimed-retry` / `reclaimed-returned` / `reclaimed-escalated` contre un verdict de gate, et la raison d'escalade dit laquelle des deux causes a dépensé le dernier retry. Conséquence assumée : un ticket dont le plafond tombe sur un reclaim part en `decision` même si des sessions avaient été jugées rouges avant — la note le dit au lieu de le taire (« des tentatives antérieures ont pu être jugées »).

- **Décision : le re-slice garde le compteur du parent.** `failures_reslice` réinjecte le parent par `tracker_mark_ready`, qui ne remet rien à zéro. Laissé tel quel, et c'est un choix : le parent revient avec ses **propres** critères d'acceptation, et ses tentatives rouges antérieures portaient sur les mêmes — c'est de la vraie matière. Le budget entamé est donc conservé. Ce n'est pas le même cas que [16] (un humain a corrigé quelque chose, la matière a changé) ni que [11].

- **Frontière de confiance, sondée avant d'écrire.** Le champ vit dans un fichier de ticket, donc une session peut l'écrire. Ce qui le tient est la restauration de `issues/` ([21]), et le fait que le bump lise la valeur **d'après** le snapshot pré-session. Sondé le 29/07/2026 : un ticket portant `Failures: 1`, `RETRY_N=2`, une session qui réécrit `**Failures:** 0` à chaque tentative et un gate rouge →

  ```
  exit=0  sessions=2  status=ready-for-human  failures=[3]  escalation=[failed-impl]
  2 lignes tracker-write dans run.log
  ```

  Le budget ne s'étend pas : la remise à zéro est annulée avant la lecture, et l'édition elle-même coûte l'itération. Le compteur remis à zéro par la boucle sur `resolved` n'ouvre donc rien de neuf — c'est le même chemin d'écriture que le bump, à l'intérieur de la même protection.

- **Piège pour la prochaine sonde : la sonde d'origine ne rougit sous aucune mutation prise seule.** Le défaut avait besoin des deux moitiés ; réparer l'une ferme le scénario que l'autre ouvrait. Reproduite telle quelle (trois nuits, trois claims repris, trois livraisons vertes), elle restait donc verte avec la facturation replantée *et* avec le zéro retiré — un test qui n'assertait que l'état final. Ce qui la porte est ce que le journal dit de **chaque nuit** : trois `reclaimed-returned`, zéro `reclaimed-retry`. C'est la même leçon que le mensonge d'un `assert_success` seul, un cran plus haut : un scénario composé doit asserter le chemin, pas l'arrivée.

- **Imprécision non corrigée, hors write-surface.** `loop.sh` journalise « reclaimed <id> from an owner that is gone -> <disposition> » pour tous les reclaims, y compris celui d'un `assignee:alice` que le pack n'a jamais pingé et qui est peut-être bien vivant. Le mot de disposition (`returned`) porte l'information neuve, et la note sur le ticket dit la vérité complète ; la phrase de `loop.sh` reste celle du fail-open de [12] (« tout ce qui est incertain compte comme mort »). À reformuler par qui touchera aux messages de la boucle.

- **Non traité, et pourquoi.** `tracker_mark_ready` ne remet toujours rien à zéro : c'est le chemin de réinjection de [16] et de [11], à eux de trancher (la ligne est écrite dans leurs tickets et dans `tracker.sh`). Le champ `Escalation:` n'est pas lâché par `mark_resolved` non plus — un ticket ne peut y arriver qu'en passant par une réinjection à la main qui aurait sauté `mark_ready`, donc hors de ce ticket.
