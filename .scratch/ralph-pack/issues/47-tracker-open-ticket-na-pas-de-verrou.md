# 47 — `tracker_open_ticket` n'a pas de verrou, et ses deux réparations le manquent

**What to build:** Sérialiser l'attribution d'un `NN` par `tracker_open_ticket`, et décider ce qui répare une collision que **la boucle elle-même** a créée. `tracker_local__next_nn` lit le répertoire, prend le max et écrit ; il n'y a aucun verrou, et il y a maintenant trois producteurs (`failures_reslice`, l'escalade de [14], `capability_propose`). Deux ouvertures concurrentes prennent le même numéro — reproduit. La conséquence est celle de [27] et elle est permanente : un bare number cesse de résoudre, et tout ticket portant `Blocked by: NN` quitte la frontière pour de bon. Les deux contrôles qui existent ne peuvent structurellement pas l'attraper : `tracker_preflight` tourne une fois au démarrage du run, et la renumérotation de `failures_quarantine_strays` est désarmée par le registre des écritures de la boucle ([13]/[42]) — précisément parce que c'est la boucle qui a écrit.

**Blocked by:** None

**Write-surface:** `.claude/lib/tracker-local.sh`, `.claude/lib/tracker.sh`, `test/tracker-local.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

- [ ] Deux ouvertures de ticket en vol ne prennent jamais le même `NN`. Le mécanisme existe déjà à côté : `tracker_local_claim` fait sa lecture-écriture sous `state_guard_take` pour exactement cette raison, et l'écrit.
- [ ] La dédup de `capability_propose` ne peut plus ouvrir deux fois la même proposition : elle lit `tracker_ids` avant d'écrire, donc elle a la même course par le même bout.
- [ ] Une collision qui existerait quand même a un chemin de réparation, ou une phrase qui dit qu'elle n'en a pas. Aujourd'hui elle n'a ni l'un ni l'autre : elle naît après le préflight et le registre exempte celle de la boucle.
- [ ] Le tableau de `docs/frontiere-de-confiance.md` dit ce qui tient « un ticket est identifiable par son `NN` » **quand c'est la boucle qui écrit**. La ligne actuelle ([27]) parle du mauvais écrivain.

## Comments

- **Origine : passe transversale du 26/08/2026**, sur `main` à `3d6915b`. Document dans `.scratch/ralph-pack/passe-transversale-26-08.md`, sondes conservées dans `.scratch/ralph-pack/sondes/passe-26-08/` (`p4.bats` P4a, `p5.bats` P5a). L'angle avait été **écrit** par [15] dans [13] et dans [27] ; la passe l'a reproduit, et a trouvé que ces deux tickets-là sont `resolved` — donc qu'aucun ticket ouvert de la file ne le lirait jamais. C'est ce ticket qui leur donne un propriétaire.

- **La fenêtre est plus large qu'on ne la lit.** `tracker_local_open_ticket` calcule `nn` **avant** de lire le corps sur stdin (`body="$(cat)"` vient après). Elle reste donc ouverte aussi longtemps que l'appelant met à produire ce corps — ce qui, pour un re-slice, est le temps d'un plan. La sonde s'en sert : elle tient la première ouverture sur un fifo, fait passer la seconde en entier, puis relâche.

      === second opened: 03-second
      === first opened: 03-first
      === tracker
      01-alpha.md  02-beta.md  03-first.md  03-second.md
      === can a bare number resolve?
      rc=1 out=tracker: "03" matches 2 tickets — an ambiguous id is never safe to resolve

  Et le ticket bloqué sur `03` ne rentre plus dans la frontière : `tracker_local__is_unblocked` rend faux dès que `tracker_local__path` refuse.

- **Les deux réparations, et pourquoi aucune n'agit.**

  *`tracker_preflight`* nomme parfaitement le cas — sondé, il rend `03 ambiguous-id two or more tickets carry the number 03 (03-first, 03-second)`. Il tourne **une fois, au démarrage du run** ([27] : « ce qui reste est un humain éditant le répertoire à la main »). Cette collision-là naît en cours de run, donc il ne la verra qu'à la nuit suivante, quand les tickets qui pointent dessus sont déjà sortis de la frontière.

  *`failures_quarantine_strays`* renumérote — c'est tout le sens de [27] — mais seulement ce qui n'est pas dans le registre des écritures de la boucle ([13], lu par les deux gardes depuis [42]). Sondé côte à côte (`p5` P5a), les deux moitiés du même appel :

      === the loop created them (ids in the register)
      rc=0 tracker: 01-alpha.md 02-first.md 02-second.md
      === a session created them (empty register)
      ralph: … quarantined 03-first 02-second
      ralph: … renumbered 02-first -> 03-first

  **Le registre qui protège les écritures de la boucle est exactement ce qui désarme la réparation quand c'est la boucle qui a écrit la collision.** Deux mécanismes corrects séparément, un trou à leur composition — la question 4 de `CLAUDE.md`. Ne pas « corriger » en faisant lire le registre autrement : l'exemption est juste, et [42] a coûté un ticket pour l'installer. Ce qui manque est en amont.

- **Ce que la sonde ne prouve pas, et qu'il ne faut pas prétendre.** Elle met les deux ouvertures en vol à la main, avec un fifo. Elle ne mesure pas la probabilité de la course en exploitation, et un test qui la mesurerait mesurerait la machine — le harnais a déjà payé cette leçon deux fois. Le test qui tient la garantie doit être au niveau du module, comme celui de la clé du brief de [14] : deux appels sérialisés par le garde, pas deux processus lancés en espérant.

- **Ordre.** Avant [16] et [18] : [16] vide le puits où les doublons de proposition atterrissent, et [18] doit implémenter `open_ticket` sur un backend distant — `tracker.sh` lui dit déjà qu'il doit répondre à « que fait `tracker_ids` quand deux tickets réclament un identifiant », et il vaut mieux qu'il hérite de la réponse que de la redécouvrir.
