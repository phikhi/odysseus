# 18 — Backends distants github + gitlab

**What to build:** Les implémentations distantes de l'adaptateur de tracker, satisfaisant **la même interface** que `local`, avec la forme d'intégration façonnée par le backend (claim = assignee, reçu = PR, `wait_ci`). La boucle reste agnostique.

**Blocked by:** 02, 10

**Write-surface:** `.claude/lib/tracker-github.sh`, `.claude/lib/tracker-gitlab.sh`, `test/tracker-remote.bats`

**Status:** ready-for-agent

- [ ] Les adaptateurs `github` et `gitlab` satisfont l'interface fixe ; la boucle reste agnostique (aucun changement de control-flow).
- [ ] En distant : claim = assignee ; reçu = la PR ; liveness du claim en **sidecar local** (concurrence mono-machine).
- [ ] `wait_ci` est ON par défaut si une CI est détectée (opt-out `WAIT_CI=off`) → intégration PR-par-itération.
- [ ] Le même scénario e2e que `local` (piloté par une API mockée) produit les mêmes transitions d'état observables.
- [ ] `tracker_ids` est implémenté par les deux backends ; un backend qui ne la fournit pas est détecté, pas subi.

## Comments

- **Contrainte posée par [05] : l'interface a une 8ᵉ opération, `tracker_ids`** (tous les tickets, quel que soit leur état, min-NN d'abord). Le scope-guard s'en sert pour distinguer un débordement dans un fichier neutre d'un débordement dans la write-surface d'un **autre** ticket. Attention au mode de panne : `tracker__dispatch` renvoie 3 pour une opération non implémentée, mais l'appelant (`gate__surface_owner`) itère sur une liste vide et conclut simplement que personne ne revendique le chemin. Un backend distant qui oublie `tracker_ids` **dégrade donc en silence** — tout drift contractuel devient un débordement interne, donc retry au lieu d'escalade. À traiter ici : implémenter l'opération, et/ou durcir le gate pour qu'une classification impossible escalade au lieu de se taire.
- Coût à surveiller : `gate__surface_owner` appelle `tracker_ids` puis lit un champ par ticket, pour chaque fichier hors surface. Bénin sur des fichiers markdown, à revoir si chaque lecture devient un appel réseau (cache par itération).
