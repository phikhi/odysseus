# Gate QA par itération & gestion des échecs

Type: grilling
Status: resolved
Blocked by: 03, 06

> **⚠️ En révision — durcissement v2.** La décision v1 ci-dessous est conservée comme record, mais le gate est étendu par le durcissement Multiplyz : **gate de valeur bout-en-bout au niveau feature** [12] (le gate par-ticket ne prouve pas la feature assemblée — échec AUDIT Multiplyz), **vérif visuelle réelle** [13], **3ᵉ axe de revue « fidélité »** [14] (au-delà de Standards\|Spec), **reçu d'audit** [18], **scope-guard** [19]. Voir `map.md`.

## Question

Qu'est-ce qui fait qu'une tâche est **« resolved »**, et que fait la boucle d'un **échec** ?

À trancher (s'appuie sur l'unité [03] et le control-flow [06]) :
- **Critères de résolution** : tests verts (`tdd`) + `code-review` deux axes passé + typecheck. Le tout dans la même session fraîche, ou une session de vérif séparée (contexte isolé) ?
- **Qui juge** : l'agent lui-même s'auto-valide (risque de complaisance), ou un subagent `code-review` indépendant sert de porte ?
- **Échec** : retry immédiat (même contexte frais), re-file en fin de frontière, ou marquer `failed` et escalader ?
- **Seuil d'escalade** : après combien d'échecs un ticket revient-il à l'humain (lié à « reprise après échec profond », en brume) ?
- Que garde-t-on d'une itération échouée (diff partiel ? rollback propre ?) pour ne pas polluer la suivante.

### Contraintes héritées du ticket 03 (Unité & <200K)

- **Slice avortée par le filet 200K** = cas d'échec à traiter ici : rollback propre du diff partiel obligatoire (aucune slice à demi).
- **Escalade « propose-puis-valide »** : une slice trop grosse est marquée `ready-for-human` avec une **proposition de re-découpage** attachée (générée par la boucle via `to-tickets`) ; l'humain valide/édite → sous-slices ré-injectées en frontière. Distinguer ce cas (trop-gros → re-découper) d'un échec de tests (retry/escalade classique). **(Révisé par cette résolution : le re-découpage est désormais autonome — voir Answer et [03] mis à jour.)**

## Answer

Décision verrouillée (grilling HITL). S'appuie sur l'unité/200K [03] et le control-flow [06] ; consomme le classifieur budget [07] en amont ; applique la ligne interne/contractuel [05].

**Décision 1 — Architecture du gate (qui juge, où).** Gate en **deux natures**, exécutées **en parallèle** :
- **Checks objectifs** (tests verts + typecheck) → lancés **directement par la boucle bash** : déterministe, gratuit, zéro LLM, **complaisance impossible**. Verdict = code retour.
- **code-review deux axes** → **session `claude -p` fraîche et isolée** qui juge le diff, **indépendante** de la session delivery (pas d'auto-validation) et hors de son budget 200K. Le skill `/code-review` **fane déjà en interne en deux sous-agents parallèles** (axe *Standards* = conventions du repo, axe *Spec* = conformité à l'issue/AC) → l'isolation multi-agents est acquise là où il y a du *jugement*, sans effort.
- Les **trois checks tournent concurremment** (le bash backgroundise `tests`, `typecheck`, la session review ; `wait` ; agrège) → gain de latence, sans transformer l'objectif en appel LLM.
- Corollaire pour [06] : la session delivery *construit* via `/tdd` ; son `/code-review` interne est **redondant** avec le gate → l'omettre pour économiser du budget.

**Critères de *resolved*.** Les **trois** checks verts : tests + typecheck + code-review deux axes. Les critères d'acceptation du ticket doivent être **machine-vérifiables**, **e2e inclus dès qu'il y a une surface visible** [05]. Le marquage `resolved` est écrit par **la boucle, après le gate**, atomiquement (temp+`mv`), et incrémente le **compteur de résolutions** que lit le détecteur de run stérile [06].

**Décision 2 — Politique d'échec & seuil.** Taxonomie complète des issues d'une itération :
- **Budget** (classifieur [07]) → pause/reprise, **pas un échec**.
- **Too-big** (filet 150K OU flag pré-vol [03]) → **re-slice autonome** (voir ci-dessous), **pas de retry**.
- **Ambiguïté contractuelle** (touche un AC, [05]) → escalade `ready-for-human` **directe**, **pas de retry** (retenter ne lève pas une ambiguïté).
- **Échec de gate** (tests rouges / typecheck KO / code-review rejette) **ou crash non-budget** → **retry N fresh** : nouvelle session fraîche sur le même ticket (le contexte neuf peut réussir là où le précédent a calé), jusqu'à **N (défaut 2, configurable)** ; au-delà → `ready-for-human` avec **notes d'échec + dernière tentative préservée**. Le compteur **`Failures:` vit sur le ticket** [04] (autoritaire → une session fraîche le relit). Ceci **gradue le fog « reprise après échec profond »** : la reprise profonde EST l'escalade après N.

**Too-big → re-découpage autonome (révise [03]).** Une slice trop grosse ne remonte **pas** à l'humain par défaut. La boucle **re-découpe elle-même** (via `to-tickets`) **en préservant les critères d'acceptation** (même comportement livré, granularité plus fine) et **ré-injecte les sous-slices en frontière** — zéro humain, le tout **loggé** (`run.log` + note sur le ticket parent). C'est une décision *interne* au sens [05] (aucun impact sur les AC) → autonome. **Soupape humaine unique** : si découper proprement est **impossible sans toucher aux AC/au scope** (cas *contractuel*), alors seulement `ready-for-human`. Évite une dérive de scope silencieuse tout en gardant l'AFK sur le cas courant.

**Décision 3 — Rollback d'une itération échouée.** Aucune slice à demi [03] : le working tree doit être propre pour l'itération suivante. La boucle **snapshote `HEAD` avant le spawn** (`PRE=$(git rev-parse HEAD)`). Sur échec → `git reset --hard $PRE` + `git clean -fd` : le tree revient à l'état pré-itération **quels que soient les commits** de la session (compatible avec « la session commit » de [06]). **Entre retries** : on jette (repart propre). **À l'escalade finale** (après N) : brancher/patcher `failed/<ticket>` la dernière tentative **avant** le reset, linkée à l'escalade → l'humain hérite du contexte sans repartir de zéro.

### Contraintes créées ailleurs

- **[09] Form-factor** : le gate suppose des **commandes de test/typecheck configurables** par projet (comment la boucle lance `tests`/`typecheck`) et un **projet git** dans l'environnement cible (rollback + branches `failed/<ticket>`) ; à embarquer/documenter dans le form-factor.
- **[06]** (refinement) : omettre le `/code-review` interne de la session delivery (le gate le fait, indépendant) ; la boucle snapshote `HEAD` avant spawn pour le rollback ; le gate lance ses 3 checks en parallèle.
- **[03]** : décision « slice qui trébuche » **révisée** — re-découpage autonome par défaut (voir ce ticket), plus « propose-puis-valide » que dans le cas résiduel où les AC ne peuvent être préservées.
