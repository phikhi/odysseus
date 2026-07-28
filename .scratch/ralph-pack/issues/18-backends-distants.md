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
- **Contrainte posée par [07] : une 9ᵉ opération, `tracker_block_on ID DEPS`** (retenir un ticket jusqu'à ce que les tickets listés soient `resolved`, en conservant les blocages déjà présents). Le re-slice s'en sert : le ticket trop gros est bloqué sur les tickets plus petits qu'il a produits, puis revient en frontière. Même mode de panne silencieux que `tracker_ids` : un backend qui ne l'implémente pas renvoie 3, et l'appelant continue — le parent repartirait alors en frontière **sans être bloqué**, donc serait re-tenté immédiatement et re-slicé en boucle. À implémenter, ou à faire échouer bruyamment.
- **Contrainte posée par [21] : le backend distant n'a aucune protection du tracker, et le silence est le mode de panne.** `failures_protect_tracker` compare deux tree objects de `.scratch/<FEATURE>/issues` autour du spawn et restaure ce qu'une session y a édité — un chemin de fichiers plus git, donc intrinsèquement le backend `local`. Sur un backend distant, le répertoire n'existe pas : les deux snapshots sont le tree vide, le delta est nul, et la protection **rend 0 sans un mot**. Pas d'erreur, pas de log, pas de garde. Or ce que la protection tient est ce qui rend le scope-guard fiable : sans elle, une session distante qui édite l'issue qu'elle est en train de livrer élargit sa write-surface, et le gate la juge sur la surface élargie. À traiter ici, et le choix doit être explicite plutôt qu'hérité : soit une opération d'adaptateur (snapshot/restore de l'état des tickets, ce que l'API permet de faire autrement), soit un refus bruyant tant que rien ne garde la zone. Un `return 0` silencieux est la forme exacte du faux vert que [21] vient de refermer.
