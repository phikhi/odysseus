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

- **Contrainte de la passe transversale du 06/08/2026.** Même question qu'à [16] : le câblage de réinjection écrit dans `issues/` hors d'une itération, et les deux gardes du tracker traitent ce qui n'est pas au registre comme l'œuvre de la session jugée ([42]). Dire par où passent ces écritures.

## Comments

- **Contrainte posée par [10], livré le 07/08/2026 : la troisième couche existe maintenant, et elle a une place réservée dans le reçu.** Le reçu d'audit est **par itération finale** (livrée ou escaladée) et **par ticket** ; le playthrough est par feature et matériel. Les quatre couches sont distinctes et le restent : un playthrough écrit dans un reçu ferait de la preuve de fin de feature un paragraphe d'un document par ticket, que la rétention (`RECEIPTS_RETENTION_DAYS`) efface. Ce que ce ticket a le droit de faire, et c'est la façon de les relier sans les mélanger : la section « What to read » du reçu référence des **objets et des chemins**, jamais du contenu — un playthrough persisté y a sa ligne, comme le commit et la branche `failed/`.

- **Contrainte posée par [16], livré le 31/08/2026 : la décision sur `Failures:` se
  prend par chemin de réinjection, et celui-ci est le tien.** [26] avait laissé ouverte
  la question « qui remet le compteur à zéro », en l'écrivant au-dessus de
  `tracker_field` dans `lib/tracker.sh` : `tracker_mark_resolved` le vide,
  `tracker_mark_ready` non. [16] l'a tranchée **pour le puits humain** et
  **délibérément pas dans l'opération** : `mark_ready` a un second appelant
  (`failures_reslice`, qui marque un parent en attente de ses enfants), et vider le
  compteur dedans aurait pris la décision pour ce ticket-ci et pour le re-slice depuis
  un ticket qui ne les regardait pas.
  Ce qui est donc disponible pour toi : une opération d'adaptateur
  `tracker_clear_failures ID` (elle *retire* le champ plutôt que d'écrire `0`, la même
  geste que `mark_resolved`, parce que `bump_failures` lit un champ absent et un `0` de
  la même façon et qu'un ticket portant `Failures: 0` se lit, pour un humain, comme un
  ticket qui a été tenté sans échouer). Et ce qui reste à décider ici : **une réinjection
  hybride après un playthrough rouge remet-elle le budget de retries à zéro ?**
  Attention au sens de l'erreur — sans le zéro, un ticket réinjecté avec `Failures: 3`
  sous `RETRY_N=2` est escaladé à sa **première** tentative, sans retry ; avec le zéro
  sur un chemin qui boucle, c'est `RETRY_N` qui cesse de borner quoi que ce soit.
- **Et ce que [16] a construit et que tu hérites** : si ce ticket ouvre un troisième
  point d'entrée ou une seconde boucle, `router_may_sign_off` est le refus qui garde
  `resolved` hors de portée de tout ce qui n'est pas un `sign-off`, et il est **à côté
  de la transition et pas dans le menu qui l'offre**, précisément pour qu'un second
  appelant en hérite au lieu de le recopier.

- **Passe transversale du 31/08/2026 : ce que tu hérites de [16] si tu ouvres un
  second point d'entrée avant que [55], [56] et [57] ne soient livrés.** La racine
  de cette passe est que *toutes les garanties du pack sont des propriétés de
  `loop.sh`, pas du pack* — [16] a ajouté un appelant et n'en a hérité aucune. Les
  trois formes, sondées et conservées sous
  `.scratch/ralph-pack/sondes/passe-31-08/` :
  **(1)** `router_may_sign_off` et `router_may_reinject` sont bien placés — à côté
  de la transition, pas dans le menu, précisément pour que tu en hérites — mais ils
  lisent `Escalation:` et `Write-surface:` **sur un ticket que la session routée
  peut écrire**, sans le snapshot de [21] derrière. En hériter, aujourd'hui, c'est
  hériter du trou ([55]).
  **(2)** La réinjection promet « une session fraîche et tout le gate décident
  maintenant » ; c'est faux pour du travail non commité, qui est l'état par défaut
  à la sortie d'une conversation ([56]). Si ce ticket ouvre un chemin de
  réinjection hybride, la question du zéro sur `Failures:` ci-dessus est la
  *seconde* à poser : la première est **est-ce que ce que l'humain a écrit est
  seulement dans l'arbre que le worktree de l'itération va porter**.
  **(3)** `run_lock_is_ours` et `tree_lock_is_ours` n'ont qu'un appelant, et ce
  n'est pas `human-loop.sh` ([57]). Un troisième point d'entrée doit les appeler,
  pas les recopier.
  Et un piège de forme : `human_loop__report_tracker_findings` alimente son
  `while read` par un heredoc **sur stdin** — inoffensif tant que rien de ce qu'il
  appelle ne lit stdin, mortel dès qu'un appel s'y ajoute. C'est le défaut que [16]
  a réparé dans sa boucle principale en passant la liste sur fd 3.

- **Contrainte posée par [55], livré le 31/08/2026 : un point d'entrée qui appelle
  une transition doit épingler le ticket d'abord.** La forme **(1)** ci-dessus est
  fermée, et sa réparation te fait un devoir. `router_may_sign_off` et
  `router_may_reinject` ne lisent plus `Escalation:` ni `Write-surface:` sur le
  fichier : ils lisent ce que `router_pin ID` a pris, une fois, avant le dossier et
  avant toute session — parce que la session routée écrit dans cet arbre sans
  worktree, sans scope-guard, sans gate et sans rollback, et que le menu est
  ré-offert dès qu'elle rend la main. Les deux refus sont **fail-closed** : une
  transition sur un ticket que rien n'a épinglé est refusée, avec sa phrase. C'est
  volontairement bruyant — un repli sur le tracker t'aurait rendu le trou au lieu du
  garde, en silence et en vert. Donc : `router_pin` avant `router_reinject`, y
  compris sur un chemin de réinjection hybride qui n'ouvre aucune session (le pin
  y est gratuit et c'est ce qui rend le refus lisible).
- **Et la frontière du pin, à ne pas croire plus large qu'elle n'est** : deux
  champs, du seul ticket tenu. `Failures:` — le compteur que la décision ci-dessus
  te demande de trancher — n'est **pas** épinglé, et une session routée peut
  l'écrire. Ça ne change aucune transition aujourd'hui ; ça en changerait une le
  jour où une réinjection déciderait sur lui.

- **Contrainte posée par [56], livré le 01/09/2026 : `router_may_reinject` refuse
  maintenant sur l'arbre de travail, et tu en hérites sans rien écrire.** La forme
  **(2)** ci-dessus est fermée : le refus demande ce que l'arbre porte que `HEAD`
  ne porte pas (`git diff --name-only HEAD` plus `git ls-files --others
  --exclude-standard`, moins `gate_is_bookkeeping` et moins la zone ignorée) et
  refuse tant qu'il reste quelque chose. Deux conséquences pour un chemin de
  réinjection hybride :
  - il est **à côté de la transition**, donc tout appelant de `router_reinject`
    l'a. Un chemin qui appellerait `tracker_mark_ready` directement ne l'aurait
    pas — c'est exactement la raison pour laquelle il n'est pas dans le menu.
  - la question qu'il pose n'a de sens que **là où un humain écrit**. Une
    réinjection déclenchée par un playthrough rouge tourne dans l'arbre du
    pilote, à un moment où le pack lui-même est en train d'écrire ; si ce ticket
    réinjecte depuis une itération ou depuis le pilote plutôt que depuis un
    drainage, mesurer d'abord ce que `router__tree_dirt` y voit — un refus qui
    tomberait sur l'écriture du pack serait un run qui refuse d'avancer et le
    dit dans une phrase écrite pour un humain.
  Et le témoin d'arbre pris par `router_pin` (`ROUTER__PINNED_TREE`) est une
  **base de comparaison**, pas une valeur sur laquelle un refus décide : le refus
  lit toujours l'arbre courant, pour qu'un humain qui commite dans un autre
  terminal et retape `r` passe. Ne pas le lire comme un second pin.

- **Contrainte posée par [58], livré le 01/09/2026 : un troisième objet voyage
  dans `router_pin`, et celui-là a besoin d'un appelant qui le déclenche au bon
  moment.** `ROUTER__PINNED_TRACKER` tient le `Status:` et l'`Escalation:` de
  *chaque* ticket au moment où le drain a pris le sien ;
  `router_protect_tracker ID` le relit et remet en place tout ticket que la
  session a sorti du puits ou de la frontière. Trois choses à savoir si ce ticket
  ouvre un second point d'entrée :
  - **le pin reste la condition d'entrée**, ici aussi et de la même façon
    fail-closed : `router_protect_tracker` sur un ticket que rien n'a épinglé
    **refuse bruyamment** — avec un pin vide, chaque ticket du tracker se lirait
    comme apparu pendant la session. Donc `router_pin` avant, toujours.
  - **il se lit au retour d'une session, et nulle part ailleurs.** Un chemin de
    réinjection qui n'ouvre aucune session n'a rien à protéger : personne n'a
    écrit dans `issues/` entre le pin et la transition. L'appeler quand même
    coûte une double lecture du tracker et ne peut rien trouver.
  - **il écrit dans `issues/`**, donc il n'est légitime que sous le verrou de run
    — ce que `human_loop_main` tient. Un appel depuis une itération ou depuis le
    pilote se ferait à côté des deux gardes de [21]/[42], qui ne sauraient pas le
    distinguer d'une session : mesurer avant, comme pour le témoin d'arbre.

- **Ce que la passe transversale du 01/09 laisse à ce ticket.** Deux contraintes,
  écrites ici et pas seulement dans leurs tickets ([59] et [61]).

  - **L'arbre jugé n'est pas toujours l'arbre** ([59]). `gate_tree_snapshot`
    documente un refus qui repose sur `set -e` ; ses onze appelants l'invoquent
    sous `x="$(…)" || x=""`, ce qui suspend errexit — donc un `git add -A` que
    git refuse rend un arbre **amputé** (ou vide) avec `rc=0`. Mesuré : un seul
    fichier illisible dans l'arbre et le tree jugé ne contient plus que
    `.claude/`. Une branche de gate de plus est une opinion de plus sur cet objet,
    et une opinion de valeur portée sur un arbre où tout a l'air supprimé n'a
    aucun sens honnête. **Ne pas ajouter cette branche avant que [59] ait décidé
    ce que le pack fait d'un refus de git** — ou, si l'ordre change, lire
    `RALPH_GATE_TREE` en sachant qu'il peut être faux.

    **Levée le 03/09/2026 par la livraison de [59], et voici ce qu'elle laisse
    exactement.** Le refus voyage maintenant par le code de retour :
    `RALPH_GATE_TREE` est soit un arbre où se trouve **tout ce que git a pu lire**
    à travers les règles du spawn, soit la **chaîne vide** — il n'y a plus de
    troisième valeur, c'est-à-dire plus d'arbre amputé rendu avec `rc=0`. Donc la branche que ce ticket ajoute doit
    faire une seule chose de plus que juger : **refuser de conclure sur un arbre
    vide**, comme les huit autres lecteurs (`gate__scope_guard`, `lang_check`,
    `gate_changed_files`, `gate__nothing_delivered`, `gate_restore_tree`,
    `gate_unjudged_changes`, `failures_rollback`, `gate__contain_lens_writes`).
    Une branche de valeur qui lirait un arbre vide comme « rien à juger » et
    rendrait vert serait le faux livré de [35] par une neuvième porte. Et si elle
    prend un snapshot **à elle** au lieu de recevoir `RALPH_GATE_TREE`, elle parle
    d'un autre arbre que les autres branches ([29]) *et* elle peut désormais se
    voir refuser ce snapshot : `gate_tree_snapshot` rend non-zéro, ce qui doit
    rougir la branche et pas la faire disparaître.

    **Une contrainte de forme, mécanique depuis [59] et refusée par
    `test/layering.bats`** : ne jamais écrire `local x="$(gate_tree_snapshot)"`.
    `local` rend 0 quoi qu'ait répondu la fonction, donc cette forme rachète en un
    mot-clé tout ce que [59] a livré. Deux instructions : `local x` puis
    `x="$(…)" || x=""`.
  - **Trois champs du ticket ne sont gardés par personne, et deux d'entre eux
    décident** ([61]). Le pin de [55] couvre `Escalation:` et `Write-surface:`,
    l'instantané de [58] couvre `Status:`. `Failures:` reste lu **sur le fichier**
    par `router_desk`, et il déplace le guichet — donc la question, le traitement
    et tout le prompt — de la session **suivante** sur le même ticket
    (`decision` → `admit` ou `triage-host`, mesuré). Le corps aussi : il *est* le
    prompt d'une session routée future. Un second point d'entrée bâti sur ces
    entrées hérite du trou et pas du garde, ce que le fail-closed de [55] avait
    justement refusé de faire.
