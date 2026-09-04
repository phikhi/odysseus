# 11 — Gate de valeur feature (playthrough terminal + réinjection hybride)

**What to build:** Le **gate terminal** de niveau feature : à frontière vide, un subagent frais rejoue le flux du `spec.md` sur les **vrais assets** et produit un **playthrough persisté** (condition matérielle de clôture). Un playthrough rouge est traité en hybride borné. Attrape les **trous de câblage** que les tests unitaires ratent.

**Blocked by:** 07

**Write-surface:** `.claude/lib/playthrough.sh`, `test/playthrough.bats`

**Status:** resolved

- [x] À frontière vide, **avant** l'exit succès, un subagent frais rejoue le flux utilisateur du `spec.md` sur les vrais assets et écrit `docs/playthroughs/<feature>.md`.
- [x] La clôture de feature (exit succès) n'a lieu que si le playthrough est vert et persisté.
- [x] Un trou de câblage **interne** réinjecte un ticket de câblage autonome en `ready-for-agent` ; un trou **contractuel** escalade en `ready-for-human`.
- [x] La réinjection est bornée par `PLAYTHROUGH_REINJECT_MAX` (pas de boucle infinie).
- [x] Un canari full-loop e2e est maintenu dans le gate comme régression du pack.

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
  - **Trois champs du ticket n'étaient gardés par personne ; [61] les a repris,
    livré le 04/09/2026, et ce que tu en hérites a changé.** Le pin de [55]
    couvrait `Escalation:` et `Write-surface:` ; `Failures:` s'y ajoute au **même
    appel `router_pin`**, et `router_desk` le lit désormais par `router__field`.
    Donc : *si tu ouvres un troisième point d'entrée, `router_pin` est encore plus
    obligatoire qu'avant l'appeler avant toute transition et avant tout dossier* —
    il porte maintenant trois champs, l'arbre de travail et un instantané du
    tracker à quatre champs plus un digest par ticket. Ce que [61] n'a **pas**
    fermé et dont tu hérites tel quel : rien n'est *restauré* de `Failures:`, de
    `Blocked by:` ni du corps — ils sont **nommés** au retour de chaque session
    routée et laissés là ; et l'épingle vaut pour un drain, le drain suivant
    relit le fichier.
  - **Une contrainte de forme de plus, mécanique depuis [61] et refusée par
    `test/layering.bats`** : dans un heredoc **non cité**, toute backtick doit
    être échappée (`` \` ``). `playthrough.sh` va construire un prompt de
    subagent, donc de la prose markdown qui nomme des chemins et des champs entre
    backticks — c'est exactement le site où ça a cassé (`router_prompt`, [58]).
    Une backtick non échappée y est une substitution de commande : la prose part
    au modèle avec un trou, l'humain reçoit un `command not found`, et rien ne
    rougit. `layering_heredoc_prose` te le refuse ; citer le heredoc
    (`<<'PROMPT'`) est la forme qui ne peut plus jamais échouer.

## Livraison — 04/09/2026

`.claude/lib/playthrough.sh` (nouveau), câblé dans `loop.sh` à l'endroit où la
frontière se vide, plus une ligne dans `receipt.sh` et un paragraphe dans
l'exemple de config. `test/playthrough.bats` (22 tests), un test de canari,
21 entrées de mutation.

### La forme livrée, en une passe

Le pilote, à frontière vide et **après avoir collecté toute itération en vol**,
appelle `playthrough_close`, qui répond en trois codes parce que le pilote en
fait trois choses différentes : `0` la feature se clôt (l'`exit 0` d'avant),
`1` un ticket de câblage est sur la frontière **et la boucle repart** (le scan
est sans mémoire, donc le tour suivant le trouve comme il trouverait celui d'un
humain), `2` la feature ne se clôt pas → `stop_code=4`, ce qui fait passer le run
par le seul teardown qui existe. Chaque issue laisse une ligne au journal
(`playthrough-green`, `playthrough-reinjected`, `playthrough-blocked`) : « la
frontière s'est vidée et le run a continué à moudre » n'est reconstituable
depuis aucun ticket.

La moitié matérielle est **au pack** : `RUN_CMD` puis `VISUAL_CMD`, chacun borné
par `GATE_TIMEOUT` (par phase depuis [23] — c'est la phase suivante, pas un
budget de plus), lancés dans la racine du projet, transcriptions capturées. La
moitié modèle est **en lecture seule** : `lenses_posture`, une seule définition
([20]), lignes taguées, et c'est le pack qui écrit le document, le ticket et le
statut. Modèle propose, pack dispose — la règle de [14], appliquée un cran plus
haut.

### Les décisions, et pourquoi celles-là

- **Un subagent avec `Bash` a été refusé.** Il aurait été une session non
  supervisée avec droit d'écriture sur l'arbre de l'opérateur — pas de worktree,
  pas de scope-guard, pas de gate, pas de rollback — donc strictement plus large
  que toute ligne de `docs/frontiere-de-confiance.md`, dont chaque entrée porte
  au moins sur un arbre que le pack jette. Le prix est écrit au tableau : « le
  playthrough tourne sur les vrais assets » n'est tenu par rien, `VISUAL_REAL_ASSETS`
  est une affirmation du projet cible, et ce que le pack tient à la place est
  qu'un projet qui ne l'a pas faite **ne clôt aucune feature**.
- **`Failures:`, la question que [26] puis [16] ont laissée à ce chemin :
  tranchée par construction.** La réinjection ouvre un ticket **neuf**, donc sans
  `Failures:` du tout : rien n'est hérité, rien n'est effacé,
  `tracker_clear_failures` n'est jamais appelé d'ici. `RETRY_N` borne les
  tentatives sur le ticket de câblage, `PLAYTHROUGH_REINJECT_MAX` borne le nombre
  de ces tickets, et les deux bornes portent chacune sur une question différente.
  Rouvrir le ticket déjà livré était l'autre route, mauvaise dans les deux sens,
  comme [16] l'avait calculé.
- **La réinjection ne passe par aucune transition, et c'est mesuré.**
  `router_may_reinject` refuse tant que l'arbre porte quelque chose que `HEAD`
  n'a pas ; sondé à frontière vide après un run vert ordinaire avec la retro
  allumée, `router__tree_dirt` répond déjà **trois chemins**, tous écrits par le
  pack (`LEARNINGS.md`, `learning-records/…`, `receipts/demo/01-alpha.md`). Un
  chemin de réinjection passant par cette porte aurait refusé sur l'écriture du
  pack, à chaque run, dans une phrase écrite pour un humain absent — exactement
  ce que [56] avait demandé de mesurer d'abord. Donc : ouverture d'un ticket neuf
  par l'adaptateur, comme `capability_propose`. Aucun `Status:` n'est touché,
  donc `router_pin` n'est pas appelé — le pin est la condition d'une
  **transition** ([55], [58]), pas d'une écriture — et ce ticket n'ouvre pas un
  troisième point d'entrée au sens de la passe du 31/08.
- **Le déclenchement est le chemin de l'`exit 0` et lui seul** (`iteration > 0`).
  Un run dont la frontière était vide au départ n'a rien moulu et n'a rien à
  clore ; y dépenser une session et les commandes du projet ferait payer chaque
  démarrage contre le mauvais tracker. Le résidu est écrit : un run qui meurt
  entre sa dernière itération et cette ligne laisse la feature non close jusqu'à
  ce qu'un ticket soit moulu à nouveau.
- **Le compte des réinjections se lit dans le tracker**, pas dans une variable du
  run : un compteur en mémoire se remet à zéro au redémarrage, et la borne ne
  bornerait plus rien sur une nuit qui a planté. Le compte est le nombre de
  tickets `*-playthrough-wiring-*` que la feature porte déjà ; il est faux dans un
  seul sens (une session qui en forge un pousse vers l'humain, une session qui en
  supprime un est remise par le garde de [21]). Le prix : il court sur la vie de
  la feature et pas sur le run.
- **Deux préfixes de slug, et c'est la borne qui l'exige.**
  `playthrough-wiring-*` pour ce qui repart sur la frontière,
  `playthrough-gap-*` pour ce qui va au puits. Un préfixe unique aurait fait
  dépenser le budget de réinjection par des escalades — c'est-à-dire par des
  tickets que personne n'a réinjectés.
- **Terminaison, en deux gardes plutôt qu'un.** `tracker_open_unique` déduplique
  sur le slug, donc le même trou nommé deux fois n'ouvre qu'un ticket et le
  second tour **demande un humain** au lieu de tourner ; et la borne coupe de
  toute façon. Les deux entrées de mutation correspondantes retirent le garde
  dans la direction qui **termine encore** : un ticket de trop, jamais une boucle
  — une mutation qui ferait tourner `mutate.sh` indéfiniment laisserait un défaut
  planté dans l'arbre.
- **La write-surface du ticket de câblage vient du modèle, et elle est filtrée.**
  Refusée si elle est vide (une surface vide est le cas fail-safe du scope-guard :
  tout ce que la session écrit déborde, donc le ticket serait indélivrable par
  quiconque) et refusée si elle couvre un chemin scellé (sinon le ticket enverrait
  une session passer une nuit sur du travail que `gate_is_sealed` rougit à chaque
  fois). Dans les deux cas, le trou part au puits humain.

### Ce que la question de la frontière de confiance a trouvé, et qui n'était pas dans le ticket

**`spec.md` est écrivable par les sessions qu'on juge.** Il vit dans
`.scratch/<feature>/`, la zone que `gate_is_bookkeeping` fait enjamber au
scope-guard et que le rollback ne défait pas ; [21] garde `issues/` *à
l'intérieur* de cette zone et s'arrête là. Un gate de valeur qui lit le fichier à
la fin demande « la feature fait-elle ce que la **dernière session** a dit qu'elle
promettait ». C'est le corollaire que ce projet s'est écrit après [21], mot pour
mot. Donc `playthrough_witness` : le pilote copie `spec.md` dans `$TMPDIR` sous un
nom `mktemp` qu'il n'exporte jamais, **avant la première session**, et le gate ne
rejoue que cette copie — fail-closed, il refuse s'il n'y a pas de témoin plutôt
que de se replier sur le fichier. Sondé par un test qui fait réécrire la vraie
spec par la session de livraison : le prompt du gate porte le flux d'origine.

### Pièges rencontrés, à ne pas repayer

- **Le pin d'ignore de l'itération est mort quand le playthrough tourne.**
  `loop__finish` supprime le répertoire du pin en collectant l'itération, mais le
  pilote garde `RALPH_FRONTIER_PIN` pointant dessus ; `gate__frontier_pin_broken`
  répond alors « cassé » et `gate_tree_snapshot` **refuse**. Sans le
  `local RALPH_FRONTIER_PIN=''` de `playthrough_close`, le gate de valeur aurait
  répondu « rien n'a pu être mesuré » sur **tout run ayant livré** — un refus qui
  a l'air de fonctionner. Le `local` d'une variable qu'on ne possède pas est la
  forme que `proc_countdown` utilise déjà pour sa paire d'ownership.
- **Un `head` dans le groupe qui écrit le document.** Le `{ … } | state_atomic_write`
  tourne dans un sous-shell sous `errexit` : un `lenses_findings | head -n N` y
  prend un SIGPIPE, et le document se serait terminé à cette section-là sans que
  rien ne le dise. `|| true` sur le **pipeline**, pas sur la dernière commande.
- **Le harnais ne peut pas éteindre ce palier**, contrairement aux lentilles et à
  la retro : il est donc injecté **allumé** (`stub-cmd run`, `stub-cmd visual`,
  `VISUAL_REAL_ASSETS=1`) et le faux `claude` répond `pass` par défaut. Et le faux
  répond au gate de valeur **même quand un test a installé un scénario** — un
  script remplace tout le faux, donc les quinze tests qui scriptent une session et
  vident ensuite leur frontière auraient tous mesuré le chemin de l'escalade. Un
  test qui veut piloter ce palier utilise `playthrough_answer`.
- **Trois assertions de comptage de sessions ont bougé de 1** (deux dans
  `loop-happy-path.bats`, une dans `budget.bats`), plus deux comptes de lignes de
  journal. Elles sont désormais **appairées** avec `playthrough_call_count` : un
  nombre qui ne dit que « 3 » resterait vert si le gate de valeur cessait de
  tourner et qu'une lentille se mettait à tourner.

### Contraintes créées ailleurs — écrites aussi dans les tickets concernés

- **[18] backends distants** : `playthrough__injected` compte les tickets de
  câblage **en lisant le slug dans l'id**. Un backend qui numérote côté serveur
  rend des ids qui ne portent pas le slug ; le compte resterait à zéro et
  `PLAYTHROUGH_REINJECT_MAX` ne bornerait plus rien. Et `tracker_open_unique` est
  la déduplication qui garantit la terminaison — un backend qui ne l'implémente
  pas fait refuser bruyamment l'ouverture, ce qui est le bon échec, mais il doit
  répondre à la question plutôt qu'en hériter.
- **[19] installeur** : `docs/playthroughs/` est provisionné par [19] (spec §6),
  et les trois clés du gate de valeur sont une **confirmation forcée** — un
  installeur qui écrit une config avec `RUN_CMD` vide produit un projet qui ne
  clôt jamais une feature et sort en `4` chaque nuit. Il doit le dire à voix
  haute au moment de l'installation.
- **[48] nom de ticket portant un saut de ligne** : ce chemin ouvre des tickets
  dont le slug vient d'un titre écrit par un modèle. `playthrough__oneline` retire
  les caractères de contrôle avant `playthrough__slug`, donc aucun saut de ligne
  n'entre dans un id par ici.

### Résidus assumés

- `docs/playthroughs/<feature>.md` est écrit dans l'arbre principal et **non
  commité**, comme `LEARNINGS.md`, `learning-records/`, `docs/adr/` et
  `receipts/` avant lui. Conséquence pour un humain qui draine ensuite :
  `router_may_reinject` lui liste ce chemin de plus. Le canari l'asserte, pour que
  changer ça soit un acte délibéré.
- Un run tué laisse `ralph-spec.*` (fichier) et `ralph-playthrough.*` (répertoire)
  dans `$TMPDIR`, que `gate__tmp_leftovers` ne compte pas — sa liste est déjà plus
  étroite que son critère (`ralph-receipt.*`, `ralph-retro.*` n'y sont pas non
  plus). Classe [31]/[45], à regarder à la prochaine passe transversale.
- La borne de transcription (`PLAYTHROUGH_TRANSCRIPT_LINES`, 200) n'est pas une
  clé de config, délibérément : un projet qui pourrait la mettre à zéro obtiendrait
  un document sans preuve et un prompt sans matière. Ce qui est coupé est compté à
  voix haute dans le document.

### Gates

`bash test/run.sh` et `bash test/mutate.sh` — chiffres dans le message de merge.
