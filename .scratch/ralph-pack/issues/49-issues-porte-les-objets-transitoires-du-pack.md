# 49 — `issues/` porte les objets transitoires du pack, et la restauration les ressuscite

**What to build:** Décider ce que le pack fait de **ses propres** objets d'exécution
posés dans des répertoires dont les gardes sont écrits contre une autre forme, et le
tenir aux deux endroits où il en pose. `failures_protect_tracker` traite `issues/`
comme « un répertoire de fichiers de ticket » et restaure tout ce qui y a bougé
autour d'une session ; or le pack y écrit trois sortes de transitoires
(`<id>.md.guard/` du claim, `<id>.md.tmp.XXXXXX` de `state_atomic_write`,
`<id>.md.work.XXXXXX` et `.work.XXXXXX.p` de `set_fields`), dont l'exemption de
[13]/[42] ne peut structurellement pas s'occuper parce qu'elle est indexée par
**id**. Et `docs/frontiere-de-confiance.md` traite `.scratch/<feature>/` comme une
zone qui ne vaut qu'un verrou de run, alors que [47] y a mis un garde dont une
session peut se rendre propriétaire — ce qui n'achète pas « une collision » mais
l'espace des numéros entier, pour la nuit et pour les runs suivants.

**Blocked by:** None

**Write-surface:** `.claude/lib/failures.sh`, `.claude/lib/tracker-local.sh`,
`.claude/lib/state.sh`, `.claude/lib/gate.sh`, `test/failures.bats`,
`test/tracker-local.bats`, `test/state.bats`, `test/gate.bats`, `test/mutate.sh`,
`docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

- [ ] Un transitoire que le pack écrit dans `issues/` et qui disparaît dans la
      fenêtre d'une sœur n'est plus **ressuscité** par `failures_protect_tracker`.
      Deux directions possibles et il faut trancher, pas les cumuler par réflexe :
      filtrer la comparaison sur ce qui est un fichier de ticket, ou sortir les
      transitoires de `issues/` comme [47] a sorti le sien. Écrire la décision et
      son prix — filtrer laisse une session déposer un non-`.md` dans `issues/` que
      ni ce garde ni la quarantaine ne regardent ; déplacer touche `state.sh`, donc
      tout écrivain atomique du pack, et un temporaire doit rester sur le même
      système de fichiers que sa cible pour que le `mv` soit atomique.
- [ ] Un contrôle cesse d'**accuser** une session de ce qu'elle n'a pas fait. La
      note écrite aujourd'hui sur le ticket dit « The 01-alpha session edited the
      tracker itself (N ticket file(s)) » quand la session n'a rien écrit et que les
      N ne sont pas des tickets. C'est la famille que
      `docs/frontiere-de-confiance.md` existe pour attraper ([30] sur
      `core.excludesFile`, [37] sur la quarantaine).
- [ ] Un garde de claim ressuscité ne peut plus sortir un ticket de la frontière
      pour le reste du run. Le garde revient avec le pid du **pilote**, qui est
      vivant, et rien ne le relâche jamais — `state_guard_release` ne suit qu'une
      prise réussie. Le ticket reste `ready-for-agent` sur la frontière, le run
      s'arrête stérile, et la seule phrase émise est fausse : « could not claim
      02-beta — someone else has it » désigne un propriétaire qui n'existe pas.
- [ ] `run.log` cesse d'être **muet** sur un ticket qu'aucune itération n'a pu
      réclamer. Aujourd'hui il n'a aucune ligne pour lui : seule la console dit
      quelque chose, et personne ne lit une console le matin ([45]).
- [ ] Le tableau de `docs/frontiere-de-confiance.md` dit ce qu'une session achète en
      **posant** le garde d'ouverture, et pas seulement en le supprimant. La ligne
      actuelle ([47]) ne nomme que la suppression et en chiffre le prix à « une
      collision entre deux écrivains de la boucle ». Mesuré : une pose survit au
      run, éteint les trois producteurs de tickets **et** `tracker_renumber`,
      c'est-à-dire la réparation de [27] elle-même.
- [ ] La cause d'un refus d'allocation atteint un document durable, ou il est écrit
      qu'elle ne le fait pas. Les deux lignes qui nomment le garde sont des
      `printf … >&2` de `tracker_local__open` ; le reçu porte les `gap`
      (« could not create the ticket for … ») sans la raison, et `run.log`
      enregistre `action=escalated:too-big`, qui est la mauvaise cause.
- [ ] Un `.open.guard` laissé par un run tué est compté ou balayé par quelqu'un, ou
      il est écrit que personne ne le fait. Aujourd'hui il traverse un run vert
      entier en silence : `gate_leftovers` ne regarde que `$TMPDIR`, et le verrou de
      run — le voisin dont ce garde « hérite l'exposition » — est relâché par son
      trap `EXIT`, ce qui n'est pas le cas de celui-ci.
- [ ] Le commentaire de `state.sh` cesse d'être faux par omission. Il énumère ce qui
      couvre en aval la course qu'il ne ferme pas — « les verrous revérifiés à
      chaque itération, le claim qui est un test-and-set sur le `Status:` » — et [47]
      a ajouté un consommateur dont la correction **est** l'exclusion mutuelle, sans
      rien en aval qui revérifie.

## Comments

- **Origine : passe transversale du 27/08/2026**, sur `main` à `fcf45e1` (merge de
  [47]), avant [39]. Document dans
  `.scratch/ralph-pack/passe-transversale-27-08.md`, sondes conservées dans
  `.scratch/ralph-pack/sondes/passe-27-08/` (`q5` Q5a–Q5e, `q6` Q6a/Q6b pour la
  trouvaille 1 ; `q1` Q1a/Q1b et `q2` Q2a pour la trouvaille 2). Ce sont des
  instruments : chacune finit par un `false` volontaire.

- **La racine, et c'est elle qui justifie un seul ticket pour deux sites.** Le pack
  range ses objets d'exécution dans des répertoires dont les gardes sont écrits
  contre une autre forme. [47] a **nommé** ce danger — « `issues/` est l'arbre que
  `failures_protect_tracker` compare autour de chaque session, donc un garde pris là
  arriverait comme un chemin `A`/`D` que la restauration tenterait de
  `checkout-index` » — et s'en est servi pour écarter *son* garde. Personne n'est
  retourné voir ce qui y était déjà, ni ce que la zone d'accueil vaut maintenant
  qu'un garde y vit. Les deux moitiés éditent le même paragraphe du tableau ; les
  séparer coûte deux passes de mutation sur les mêmes fichiers.

- **Pourquoi le registre ne peut pas aider, et il ne faut pas essayer.**
  `failures_protect_tracker` exempte par `failures__in_list "$(basename "$path" .md)"
  "$ours"`. Pour `.../02-beta.md.guard/pid` ce basename est `pid` ; pour
  `02-beta.md.work.IDdYXp` c'est le nom entier. Aucun n'est jamais un id. Sondé
  plutôt que déduit (`q5` Q5e) : registre correctement rempli avec `02-beta`,
  `restored 3 ticket file(s)` quand même. L'exemption est juste et [42] a coûté un
  ticket pour l'installer — la réparation est ailleurs.

- **Le cas miroir est sain, et il borne le ticket.** Un transitoire qui **apparaît**
  dans la fenêtre est un `A`, la branche `A` ne fait rien, `restored` reste à zéro,
  aucune note (`q5` Q5b). Et `tracker_ids` ne glob que `*.md`, donc aucun de ces
  chemins ne devient un intrus pour la quarantaine. Ce qui doit changer est le seul
  chemin `D`.

- **La largeur de la fenêtre, mesurée — à ne pas surestimer en la citant.**
  `failures_tracker_tree` est un `git add -A` de **35 ms** sur `issues/` ; un
  `set_fields` expose son `.work` pendant **15 ms** ; un claim + un unclaim coûtent
  64 ms (`q6` Q6b). Le `52 sur 60` de `q6` Q6a est mesuré avec une sœur qui écrit
  **en boucle**, ce qui est le pire cas et pas l'exploitation. L'énoncé honnête est
  « rare par itération, certain sur un run assez long » : à `MAX_PARALLEL>1`, sur
  des centaines d'itérations, c'est une loterie qu'on finit par gagner. Ne pas
  écrire un test qui *mesure* cette probabilité — le harnais a déjà payé cette
  leçon deux fois ([38]). Le test qui tient la garantie est au niveau du module,
  comme `q5` : on met l'état à la main et on assert ce que la restauration en fait.

- **Ce que la trouvaille 2 n'est pas.** Ce n'est pas un faux vert : le pack
  **refuse** d'allouer plutôt que d'allouer sans garde, et la décision de [47] tient.
  C'est un déni durable dont la cause n'atteint aucun document. Et la porte
  d'entrée n'est pas neuve — `.scratch/<feature>/` est déclaré non jugé depuis [12],
  le scope-guard juge le worktree et `ralph_feature_dir` résout dans l'arbre
  principal via `RALPH_DIR` (vérifié, `q1` Q1b : aucune ligne de zone, `scope=green`).
  Ce qui est neuf est **ce que cette zone achète**.

- **Angles déjà disculpés par la passe — ne pas les resonder.**
  `state_guard_release` avec deux sœurs en vol (une sœur refusée ne relâche rien,
  `q4` Q4c ; et un sous-shell n'hérite pas du trap `EXIT`) ; la double reprise d'un
  garde périmé (`q4` Q4a, barrière d'attente active, `both=0` sur 300 tours — la
  course est stagée, pas gagnée, et elle est déjà écrite comme une limite non
  réparée) ; le slug d'un plan de re-slice comme nom de fichier
  (`failures__plan_slug` fait `tr -c 'a-z0-9-' ' '` puis prend le premier mot) ; le
  refus bout en bout du re-slice, qui fonctionne et se dit sur le reçu (`q3`).

- **Deux observations mineures récoltées au passage, à traiter ici si c'est gratuit
  et à laisser sinon.** (a) Le chemin « le re-slice n'a créé aucun enfant » n'écrit
  **rien sur le ticket**, alors que le chemin « split incomplet » y écrit une note :
  un humain qui trie le matin ne distingue pas une allocation refusée d'un plan
  inutilisable sans ouvrir le reçu. (b) La borne annoncée du garde d'ouverture est
  de 6 s et la mesure donne **8 s** (120 × 0,05 s plus le coût de la boucle), et
  `tracker_renumber` la paie **par intrus** : dix fichiers déposés par une session
  coûtent 80 s d'itération immobile.

- **Ordre.** Avant [16] et [18] : [16] est la boucle humaine, donc exactement le
  lecteur d'une frontière dont un ticket a disparu sans qu'aucun journal le dise ; et
  [18] doit implémenter `claim`, `open_ticket` et `open_unique` sur un backend
  distant, donc hériter de la clause « le répertoire du tracker ne contient pas que
  des tickets, et un garde autour d'une session ne doit pas prendre le reste pour
  une édition » plutôt que la redécouvrir. Disjoint de [39], de [46] et de [09].

- **Pièges de harnais, récoltés en écrivant les sondes.** Deux `&` nus ne mettent
  rien en concurrence — le coût du fork est plus large que la fenêtre, et Q4a
  rendait `a_only=3 b_only=297` avant qu'une barrière d'attente active ne ramène
  145/155. Et `set -euo pipefail` plus une affectation depuis une substitution qui
  échoue tue le `pack_run` : la sonde ne rougit pas, elle **pend**, parce que
  l'écrivain lancé en fond garde le tuyau de stdout ouvert et que le `run` de bats
  attend pour toujours. Un `pack_run` dont la sortie est vide n'est pas « en cours ».
