# Modèle d'état & source de vérité de la boucle

Type: grilling
Status: resolved
Blocked by: —

> **⚠️ En révision — durcissement v2.** La décision v1 ci-dessous est conservée comme record, mais plusieurs de ses points sont rouverts par le durcissement Multiplyz : le **journal non-autoritaire** (D1) par [11] (mémoire de leçons apprise), la **concurrence par-ticket hors-sujet + `claimed` réservé** (D4) par [15] (worktrees parallèles) et [21] (verrou fin), l'**observabilité minimale** par [18] (reçu d'audit). Voir `map.md` (Décisions en révision).

## Question

Où vit l'**état** que la boucle lit/écrit entre deux itérations à contexte frais, et quel est le **vocabulaire du domaine** ?

À trancher (via `/domain-modeling`) :
- **Source de vérité** : le tracker (`.scratch/<feature>/issues/`) est-il l'unique état, ou faut-il un journal de run / une file séparés ?
- Termes à définir : *tâche*, *run*, *itération*, *fenêtre de budget*, *frontière* (tickets prêts). Écrire le glossaire.
- Comment une itération **choisit** la prochaine tâche sans contexte hérité (relecture pure des fichiers : statut, blocage, triage `ready-for-agent`) ?
- Comment une itération **marque** son résultat de façon durable et atomique (statut resolved/failed, sortie, coût) pour que la suivante reparte propre ?
- Concurrence : plusieurs runs/projets en parallèle — verrou nécessaire, ou hors sujet ?

## Answer

Décision verrouillée (grilling HITL + domain-modeling).

**Source de vérité (D1).** Le **tracker est l'unique autorité** de l'état des tâches : tout ce qui pilote la sélection et la résolution vit *sur le ticket* (Status, `Blocked by`, triage, `Failures:` le cas échéant, note de résolution). En plus, un **journal de run** append-only par feature (`run.log`) capte l'observabilité (par itération : tâche, succès/échec, coût `total_cost_usd`, tours, horodatage). Le journal est **non autoritaire** : jamais lu pour choisir ni résoudre une tâche. Invariant préservé : une session fraîche reconstruit tout ce dont elle a besoin en relisant le tracker seul → « relu à neuf à chaque itération ».

**Choix de la tâche (D2).** Sélection = **scan sans mémoire** du tracker (jamais du journal) à chaque itération. Frontière = `Status != resolved ∧ tous les Blocked-by resolved ∧ triage == ready-for-agent`. Choix = **plus petit numéro d'abord** (déterministe, suit la numérotation tracer-bullet de `to-tickets`, runs reproductibles). La boucle ne **promeut** jamais le triage ; elle ne fait que **rétrograder** en `ready-for-human` sur escalade (cf. [03]). Le crash-recovery d'un run unique est du retry idempotent : le ticket interrompu reste `open+ready` (marqué seulement après gate) → re-piochée → refaite par une session fraîche.

**Marquage du résultat (D3).** C'est **la boucle** qui grave, **après le gate QA** [08] — jamais la session. La session ne produit que le *travail* (commit dans le projet cible) et ne touche jamais son statut ; on évite l'auto-report peu fiable et le demi-état d'une session morte. La boucle inspecte la sortie (`is_error`/exit code/`total_cost_usd`, faits [01]), passe le gate, puis écrit `Status: resolved` (succès) ou rétrograde en `ready-for-human` (échec/escalade). **Atomicité** : écriture dans un `.tmp` puis `mv` (rename POSIX atomique) sur le fichier ticket → bascule indivisible, sans dépendance à git (ce repo n'est pas un dépôt git ; le framework doit se déposer dans n'importe quel projet). Le journal étant non autoritaire, une ligne manquante après crash est sans danger. Le rollback du *code* (slice avortée) reste une affaire git dans le projet cible, propriété de [08].

**Concurrence (D4).** **Un run par tracker**, garanti par un **verrou de run grossier** (un par feature) qui empêche le double-run accidentel sur le même `.scratch/<feature>/`. Le parallélisme **entre features** est gratuit (trackers séparés, zéro état partagé). La concurrence **par-ticket** est **hors sujet** ; le statut `claimed` (déjà dans le modèle wayfinder) est réservé comme point d'extension futur (claim atomique avant spawn + balayage des claims zombies) si un jour on veut N itérations parallèles sur un même tracker.

**Glossaire (D5).** Les termes demandés (*tâche, run, itération, fenêtre de budget, frontière*) étaient déjà dans `CONTEXT.md`. Ajoutés par ce ticket : **Journal de run** et **Verrou de run**.

**Contraintes créées ailleurs :**
- **Control-flow [06]** : implémenter (a) le scan-select stateless (min NN sur `open ∧ unblocked ∧ ready-for-agent`), (b) le marquage temp+rename post-gate, (c) l'append `run.log`, (d) l'acquisition du verrou de run (flock/pidfile) au démarrage. Le *comment* bash exact est du ressort de [06].
- **Gate QA [08]** : la boucle écrit le Status selon le verdict du gate ; si la politique de retry utilise un compteur d'échecs, il vit **sur le ticket** (`Failures:`, autoritaire) — le *N* (nombre de retries avant escalade) reste à décider en [08].
- **Fog « Observabilité »** : le journal de run en est désormais le **substrat décidé** ; le reste (quels champs exacts, comment les exposer à l'humain) descend avec [06].
