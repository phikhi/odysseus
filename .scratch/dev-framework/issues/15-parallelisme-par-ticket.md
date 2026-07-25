# Parallélisme par-ticket au sein d'une feature (worktrees)

Type: grilling
Status: resolved
Blocked by: —

> Durcissement v2 (emprunt Multiplyz : worktrees parallèles). **Révise [04]** : « 1 run/tracker », concurrence par-ticket *hors-sujet*, `claimed` réservé. Voir `ANALYSE-multiplyz-vs-odysseus.md` §6.1.

## Question

Doit-on autoriser **N itérations en parallèle sur un même tracker**, et si oui comment — sans réintroduire les collisions que le **verrou de run grossier [04]** évitait ?

Contexte : [04] a **volontairement** laissé la concurrence par-ticket hors-sujet (le statut `claimed` du modèle wayfinder est **réservé comme point d'extension**). Multiplyz parallélise des stories dans des **worktrees isolés** (WIP ~3-4), séquence par **surfaces partagées**, et paie ça d'un **verrou de session** élaboré (cf. [21]).

À trancher :
- **Isolation** : un **git worktree** par ticket (comme Multiplyz) pour paralléliser sans conflit de working tree ; compatible avec le snapshot/rollback `HEAD` [08] ?
- **Séquencement par surfaces partagées** : comment détecter **sans humain** que deux tickets touchent une surface commune (schéma, config, lint, dépendance, composant partagé) et doivent être **séquencés** plutôt que parallélisés ? (Multiplyz le fait à la main via le planning.)
- **Claim atomique** : activer le `claimed` [04] — pose atomique avant spawn (temp+`mv`) + **balayage des claims zombies** (session morte).
- **Cap de parallélisme** (WIP) : plafond configurable dans `ralph.config.sh` (charge de review + coût).
- **Impact sur le marquage [04] et le gate [08]** : la boucle marque toujours après gate ; comment gérer N gates concurrents.
- **Devenir du verrou de run grossier [04]** : reste-t-il (1 *run* pilote, N *itérations*) ou est-il remplacé → **débloque [21]** (verrou plus fin).

Si la décision est **« non, on garde 1 run/tracker »**, alors **[21] devient hors-scope** (à fermer, cf. règle wayfinder).

## Answer

Décision verrouillée (grilling HITL). **Révise [04]** : on **adopte** la concurrence par-ticket que [04] avait laissée hors-sujet. **Débloque [21]**.

**D1 — Adoption via worktree-par-ticket.** Isolation = **un git worktree par itération** → N sessions fraîches écrivent chacune dans son arbre, zéro conflit de working tree. Le snapshot/rollback d'[08] (`PRE=HEAD` + `reset --hard`/`clean`) s'applique **dans le worktree du ticket** (rollback localisé).

**D2 — Séquencement des surfaces partagées, déterministe & AFK.** Chaque ticket déclare sa **write-surface** (globs des fichiers qu'il crée/modifie), produite par la discovery (`to-tickets`), **partie du contrat [05]** et **unifiée avec la déclaration du scope-guard [19]**. La boucle **ne parallélise que des write-surfaces disjointes** ; chevauchement → **séquence** (disjonction de globs, zéro humain, zéro LLM). Les « contrats partagés » (schéma/config/lint/manifeste dep/composant) sont des fichiers → couverts s'ils sont déclarés. **Filet** : le scope-guard [19] échoue au gate si un ticket écrit hors de sa surface → déclaration honnête. **Fail-safe** : surface non-déclarée → en conflit avec tout (tourne seule). Seules les **écritures** comptent.

**D3 — Claim atomique + sweep délégué à [21].** `claimed` [04] **activé** ; frontière = `open ∧ unblocked ∧ ready-for-agent ∧ non-claimed`. **Claim atomique avant spawn** (temp+`mv`, idiome de marquage [04]) → un picker concurrent saute le ticket. Le claim **porte l'identité + un horodatage** (pid + heure/heartbeat) pour permettre le **balayage des zombies**. La **politique de liveness** (pid vivant / TTL / heartbeat) est **déléguée à [21]** — ce ticket pose la forme, [21] pose la politique.

**D4 — Cap WIP + throttle budget.** Cap **`MAX_PARALLEL`** (⚙️ `ralph.config.sh`, défaut ~3) bornant collision + charge de review + combustion. Le signal budget d'[07] (`utilization` de `/api/oauth/usage`) est **compte-global** → il **voit déjà** la charge parallèle, aucune nouvelle mesure. Le check budget **gate chaque *spawn*** : parallélisme effectif = **min(`MAX_PARALLEL`, budget)** ; sous pression → **throttle** (spawn moins, laisse finir) ; franchement au-dessus → **drain jusqu'à frontière propre puis pause/reprise [07]**. Jamais spawn dans le mur.

**D5 — Gates concurrents, marquage, intégration, verrou de run.** Gates **par-worktree, indépendants** (pas d'état git partagé) ; **réserve** : ressource de test partagée (DB/port) = affaire du projet cible, atténuée par D2+D4, fallback **`MAX_PARALLEL=1`**. Marquage [04] **inchangé** (temp+`mv` par-fichier ; N marquages sur tickets différents = sûrs ; le claim ferme la course même-ticket). **Intégration sérialisée** : la boucle **replie chaque worktree gaté sur la branche principale un à la fois** (surfaces disjointes → sans conflit) — **build parallèle, intégration sérielle**. Le **verrou de run grossier [04] RESTE** (« 1 run pilote, N itérations ») ; non remplacé, **complété** par le claim (D3) + la liveness [21].

### Contraintes créées ailleurs
- **[04] révisé** : concurrence par-ticket **adoptée** (D4 de [04] mis à jour) ; `claimed` **activé** ; verrou de run grossier **conservé** (run-level), complété par le claim (ticket-level).
- **[05] contrat** : `to-tickets` doit produire la **write-surface** de chaque ticket (globs), unifiée avec [19] — **exigence nouvelle du contrat**.
- **[06] control-flow** : la boucle (a) sélectionne **N** tickets à write-surfaces disjointes non-claimed, (b) claim-atomic + spawn jusqu'à `MAX_PARALLEL` (spawn-gated budget [07]), (c) **sérialise l'intégration** des worktrees gatés, (d) balaye les claims zombies (politique [21]).
- **[07] budget** : le check budget **gate le spawn** (pas seulement l'itération) ; throttle sous pression ; signal compte-global couvre l'agrégat.
- **[08]/[09]** : gates par-worktree ; **ressource de test partagée → fallback `MAX_PARALLEL=1`** documenté ; `MAX_PARALLEL` ⚙️ dans `ralph.config.sh`.
- **[11] apprentissage** : les **records** sont per-fichier atomiques (OK concurrent) ; la mise à jour du **`LEARNINGS.md` (index, fichier unique)** est **sérialisée au même point que l'intégration** (repli du worktree gaté) → résout la contention d'index notée en [11].
- **[19] scope-guard** : la **write-surface déclarée est le mécanisme partagé** (parallél-safety + scope-guard) ; [19] en est le filet d'application.
- **[21] débloqué** : ne traite que la **liveness du claim** (fail-open/TTL/heartbeat) ; l'exclusion run-level reste [04].
