# 02 — Adaptateur `local` + modèle d'état

**What to build:** L'interface d'adaptateur de tracker et son implémentation `local` (fichiers markdown), plus le modèle d'état : sélection de frontière, marquage atomique, verrou de run. À partir de tickets fixtures, les opérations produisent la bonne frontière et les bonnes transitions d'état, observables via le seam. Le tracker devient la seule autorité d'état : une relecture du tracker seul reconstruit tout.

**Blocked by:** 01

**Write-surface:** `.claude/lib/tracker-local.sh`, `.claude/lib/select.sh`, `.claude/lib/state.sh`, `test/tracker-local.bats`, `test/state.bats`

**Status:** ready-for-agent

- [ ] L'interface d'adaptateur est fixée (`frontier`, `read_ticket`, `claim`, `mark_resolved`/`mark_*`, `open_ticket`, `append_note`, `emit_receipt`) ; l'impl `local` la satisfait sur `.scratch/<feature>/issues/NN-*.md`.
- [ ] `frontier` ne retourne que les tickets `open ∧ unblocked ∧ ready-for-agent ∧ non-claimed`, ordonnés min-NN ; un ticket dont `Blocked by:` n'est pas entièrement résolu est exclu.
- [ ] Le marquage est atomique (écriture temp + `mv`) : un crash pendant le marquage ne laisse jamais un ticket dans un état partiel.
- [ ] Le verrou de run empêche un second run de démarrer sur le même tracker et est libéré à la sortie.
- [ ] Une relecture du seul tracker reconstruit l'état complet (aucun état hors-tracker requis).
