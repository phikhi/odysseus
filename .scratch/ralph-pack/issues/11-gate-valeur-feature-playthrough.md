# 11 — Gate de valeur feature (playthrough terminal + réinjection hybride)

**What to build:** Le **gate terminal** de niveau feature : à frontière vide, un subagent frais rejoue le flux du `spec.md` sur les **vrais assets** et produit un **playthrough persisté** (condition matérielle de clôture). Un playthrough rouge est traité en hybride borné. Attrape les **trous de câblage** que les tests unitaires ratent.

**Blocked by:** 07

**Write-surface:** `.claude/lib/playthrough.sh`, `test/playthrough.bats`

**Status:** ready-for-agent

- [ ] À frontière vide, **avant** l'exit succès, un subagent frais rejoue le flux utilisateur du `spec.md` sur les vrais assets et écrit `docs/playthroughs/<feature>.md`.
- [ ] La clôture de feature (exit succès) n'a lieu que si le playthrough est vert et persisté.
- [ ] Un trou de câblage **interne** réinjecte un ticket de câblage autonome en `ready-for-agent` ; un trou **contractuel** escalade en `ready-for-human`.
- [ ] La réinjection est bornée par `PLAYTHROUGH_REINJECT_MAX` (pas de boucle infinie).
- [ ] Un canari full-loop e2e est maintenu dans le gate comme régression du pack.

- **Contrainte posée par [26], livré le 29/07/2026 : la réinjection du ticket de câblage doit décider du compteur.** `Failures:` n'est remis à zéro que par `tracker_mark_resolved` (une livraison verte). `tracker_mark_ready` — le chemin qu'utilisera la réinjection de câblage de ce ticket — le laisse en place. Un ticket déjà réinjecté une fois, ou qui avait consommé des retries avant d'être livré puis rouvert par le playthrough, arrivera donc avec un budget entamé et pourra être escaladé à sa première tentative. À trancher ici, explicitement, et à écrire : soit la réinjection remet le compteur à zéro (et alors `PLAYTHROUGH_REINJECT_MAX` est le seul garde-fou contre la boucle infinie — c'est déjà son rôle), soit elle ne le remet pas et le ticket de câblage hérite d'un budget qu'il n'a pas dépensé. Le piège à ne pas rouvrir est écrit dans [26] : remettre le compteur à zéro entre deux retries est exactement ce que `RETRY_N` existe pour empêcher.

- **Contrainte posée par [06], livré le 30/07/2026 : la lentille Fidélité n'est pas le playthrough, et le recouvrement doit être décidé ici.** Le registre livre une lentille `fidelity`, déclenchée quand le ticket a une surface visible (tag `visible`, ou write-surface rencontrant `VISIBLE_PATHS`), qui demande à un modèle si la valeur du ticket est câblée jusqu'à l'utilisateur. C'est **par-ticket**, c'est **du jugement**, et son verdict n'est vérifié par rien. Le playthrough de ce ticket est **par-feature**, **matériel** (les vrais assets, un artefact persisté) et c'est une condition de clôture. Les deux se ressemblent assez pour qu'on soit tenté d'en supprimer un ; ce serait une erreur dans les deux sens :

  - remplacer le playthrough par la lentille, c'est remplacer une preuve par un avis ;
  - remplacer la lentille par le playthrough, c'est ne rien dire sur un trou de câblage avant la fin de la feature, quand la session qui l'a créé est morte depuis des heures.

  À écrire dans ce ticket : la lentille attrape tôt et faillible, le playthrough attrape tard et matériel. `VISUAL_CMD` / `VISUAL_REAL_ASSETS` / `RUN_CMD` restent la propriété de ce ticket ; `VISIBLE_PATHS` est celle de [06]. Si le playthrough veut savoir quels tickets avaient une surface visible, `lenses_visible_surface <ticket>` est déjà public et lit le ticket restauré du snapshot pré-session.

- **Et un détail d'ordonnancement dont ce ticket hérite.** La clôture de feature arrive à frontière vide, donc après la dernière itération verte, donc après la dernière phase de jugement. `GATE_TIMEOUT` est désormais **par phase** et non par gate : le budget de temps d'une itération n'est plus celui qu'on croyait, à recompter si le playthrough est branché dans la même fenêtre.

- **Contrainte posée par [13], livré le 06/08/2026 : toute écriture dans `issues/` doit passer par `tracker__dispatch`.** La boucle tient un registre des chemins de `issues/` qu'elle a elle-même écrits, alimenté depuis le dispatcher, et `failures_protect_tracker` les exclut de son delta — sans quoi une itération en vol défait le claim ou le marquage d'un frère. Une opération de tracker ajoutée ailleurs (un appel direct au backend, un `perl -pi` de commodité) est invisible à ce registre et sera défaite par le garde d'une itération voisine, en silence et seulement quand `MAX_PARALLEL > 1`.
