# 10 — Reçu d'audit + journal de run (4 couches d'observabilité)

**What to build:** Les couches d'observabilité par-itération : le **reçu d'audit** (surface de relecture asynchrone) rendu par l'adaptateur de tracker, et le **journal de run** machine append-only — distincts du playthrough et de LEARNINGS. Quatre couches, jamais mélangées.

**Blocked by:** 05

**Write-surface:** `.claude/lib/receipt.sh`, `test/receipt.bats`

**Status:** ready-for-agent

- [ ] Après une itération (`resolved` ou escalade finale), `emit_receipt` produit un reçu contenant : résumé + les 4 verdicts de gate + preuves + méta + **diff par référence** (jamais inliné).
- [ ] En backend `local`, le reçu est un fichier sous `receipts/` ; l'interface permet à un backend distant de rendre le reçu comme PR.
- [ ] Le journal de run est append-only, une ligne par itération (tâche, is_error, coût, tours, utilisation) et **n'est jamais relu** pour choisir/marquer.
- [ ] Les 4 couches (journal / reçu / playthrough / LEARNINGS) sont des artefacts distincts, sans mélange.
