# Verrou de session plus fin (conditionnel à la concurrence par-ticket)

Type: grilling
Status: resolved
Blocked by: 15

> Durcissement v2 (modèle de référence : `session-lock.mjs` de Multiplyz). **Conditionnel à [15]** — n'existe que si la concurrence par-ticket est adoptée. Voir `ANALYSE-multiplyz-vs-odysseus.md` §6.7.

## Question

**Si** [15] adopte la concurrence par-ticket, le **verrou de run grossier [04]** suffit-il encore, ou faut-il un **verrou de session plus fin** — et à quelle complexité ?

Contexte : ce ticket est **bloqué par [15]**. Si [15] tranche « on garde 1 run/tracker », **ce ticket devient hors-scope** (à fermer). S'il tranche « N itérations parallèles », il faut un verrou plus fin. Multiplyz fournit un **modèle de référence** : `session-lock.mjs` — **consultatif fail-open**, `pid` liveness, `TTL`/`MAX_AGE`, `acquire`/`heartbeat`/`release`, **énumération fermée des terminaisons** (un `release` manqué = faux `BLOCKED`).

À trancher (seulement une fois débloqué par [15]) :
- **Le grossier suffit-il** : un run pilote N itérations dans N worktrees — le verrou de run [04] protège-t-il déjà, ou faut-il un claim/lock **par worktree** ?
- **Modèle** : reprendre les invariants Multiplyz (**fail-open strict** : tout état incertain → CLEAR, jamais de deadlock ; `heartbeat` aux frontières ; énumération **fermée** des sorties qui rendent le verrou).
- **En bash pur** : réimplémenter en shell (pidfile + `mtime` pour le TTL) plutôt qu'en node — cohérence avec le pack « fallback sans node » [09].
- **Complexité justifiée** : ne l'ajouter **que** si [15] le rend nécessaire — sinon la simplicité du verrou grossier [04] l'emporte.

## Answer

Décision verrouillée (grilling HITL). **Débloqué par [15]** (concurrence adoptée). [21] définit **uniquement la politique de liveness du claim** [15] — **aucun nouveau verrou** ; l'exclusion run-level reste le verrou de run grossier [04].

**D1 — Liveness : pid primaire (sans heartbeat) + TTL backstop + fail-open strict.**
- **pid-liveness primaire** (`kill -0 <pid>`) : le propriétaire du claim est une **itération `claude -p` courte-durée** dans un worktree → quand elle finit/crashe, **son pid meurt**, donc la liveness du pid reflète fidèlement l'état du claim. **Pas de heartbeat** (contrairement à Multiplyz, dont le propriétaire était l'app longue-durée) — simplification réelle.
- **TTL backstop** (`mtime` du fichier claim vs `CLAIM_TTL` ⚙️) : balaye un claim trop vieux même si le pid est ambigu → garde contre la **réutilisation de pid** par l'OS (seul trou de la liveness pid).
- **fail-open strict** : état incertain (pid indéterminable, fichier corrompu, horodatage illisible) → **balayable**, jamais de deadlock. Pire cas = collision non empêchée (= comportement mono-run actuel), jamais « tous les runs cèdent ».

**D2 — Bash-pur & discipline de libération.** `lib/claim.sh` du pack : `kill -0` (liveness) + `mtime` (TTL), atomicité par temp+`mv` [04] ; escape-hatch manuel (rééditer `Status`). **Libération du claim = énumération fermée déjà existante** : le claim est remplacé **exactement** par les sorties de marquage [04]/[08] — (a) gate vert → `resolved`, (b) échec/escalade → `ready-for-human` + rollback, (c) too-big → re-slice. Tout autre chemin = **crash** → claim résiduel, mais **pid mort → balayé immédiatement** (pas d'attente du TTL). Aucune nouvelle énumération : on réutilise les points de marquage existants.

**D3 — Minimalisme calibré.** Périmètre = **pid + TTL + fail-open**, ~quelques fonctions shell. **Ne PAS porter** la machinerie lourde de `session-lock.mjs` (heartbeat, TTL/`MAX_AGE` deux étages, énumération de 9 sorties) — elle répondait au problème « propriétaire longue-durée » qu'Odysseus n'a pas. Un seul ⚙️ `CLAIM_TTL` (`ralph.config.sh`), calibré sur ~2× la durée max d'itération. Documenter l'honnêteté : claim **consultatif** (pas de `flock` noyau), fail-open ; un CLEAR ne prouve pas l'absence de concurrent.

### Contraintes créées ailleurs
- **[04]** : le `claimed` (activé par [15]) porte la liveness définie ici ; le verrou de run grossier reste inchangé (run-level).
- **[06] control-flow** : le sweep des claims zombies = `kill -0` + `mtime` avant sélection ; libération via les sorties de marquage [04]/[08] déjà câblées.
- **[08] gate** : aucune nouvelle sortie — les 3 marquages (resolved / ready-for-human / re-slice) **sont** la libération du claim.
- **[09] form-factor** : `lib/claim.sh` (bash-pur) dans le pack ; `CLAIM_TTL` ⚙️ dans `ralph.config.sh` ; note d'honnêteté (consultatif, fail-open).
