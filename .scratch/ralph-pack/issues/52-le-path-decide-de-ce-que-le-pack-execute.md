# 52 — le `PATH` décide de ce que le pack exécute, et le successeur en hérite figé

**What to build:** Décider ce que le pack fait du fait que **`PATH` est en amont de
tous ses contrôles**, et le tenir. [46] a fermé un genre de cette famille — « la
configuration git décide aussi de ce que git exécute » — en épinglant les sources
de configuration. Mais ce témoin *demande à git* ce que la configuration dit, donc
il est en aval d'un `git` interposé. Le `PATH` du pilote décide quel `git`, quel
`claude`, quel `at` le pack exécute ; une session peut écrire dans un répertoire
qui s'y trouve (`~/.local/bin`, `/usr/local/bin` sur beaucoup de macs,
`node_modules/.bin`), et ça survit au rollback, s'exécute dans l'arbre de process
du pilote, et depuis [09] **traverse le redémarrage** : `scheduler_command` fige ce
`PATH` dans la ligne mise en file.

**Blocked by:** None

**Write-surface:** `.claude/lib/gate.sh`, `.claude/lib/capability.sh`,
`.claude/lib/scheduler.sh`, `.claude/loop.sh`,
`.claude/ralph.config.sh.example`, `test/gate.bats`, `test/capability.bats`,
`test/scheduler.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

**Tags:** securite, frontiere-de-confiance

- [ ] Décider — et écrire la décision avec son prix — ce que le pack peut
      honnêtement tenir ici. Trois sorties possibles, elles ne se cumulent pas par
      réflexe :
      **(a) un témoin**, sur le modèle de [15] : ligne de base des répertoires du
      `PATH` prise par le pilote avant la première session, recomparée par
      itération, une dérive sort en `receipt_gap` **et** en ligne de `run.log` (la
      moitié que [46] a dû réparer pour les capacités). Ne rougit rien, ne défait
      rien. Prix : un `PATH` de développeur bouge tout seul (un `npm i -g`, un
      `brew upgrade`), donc le bruit est le vrai risque et la barre doit être
      calculée, pas devinée ;
      **(b) un refus d'armer**, sur le modèle exact de `gate_frontier_residue` : un
      run dont un répertoire du `PATH` a bougé pendant la nuit n'arme pas de
      successeur, parce qu'un run neuf adopterait ce `PATH` comme celui du projet.
      C'est le raisonnement de [09] mot pour mot, appliqué au second genre ;
      **(c) un préflight** qui refuse de démarrer quand `PATH` contient un
      répertoire écrivable *sous l'arbre du projet* (`.`, `node_modules/.bin`, un
      chemin relatif) — le cas où l'exposition n'est plus « hors du dépôt » mais
      dans l'arbre même que la session écrit.
      Ce qui n'est **pas** une sortie : figer un `PATH` minimal pour le pack. Le
      projet a le droit d'avoir son `claude` et son `git` où il veut, et un pack
      qui choisirait le sien casserait toute installation non standard en silence.
- [ ] `scheduler_command` dit ce qu'il transmet. Aujourd'hui le commentaire dit
      « `PATH` so the successor finds the same `claude` and the same `git` this run
      found », ce qui est vrai et incomplet : il transmet aussi ce qu'une session y
      aurait mis. La ligne du matin (`scheduler_caveat`) est l'endroit où ça se dit,
      ou bien c'est un refus d'armer — trancher, pas les deux.
- [ ] La ligne du tableau existe et nomme son propriétaire. Aujourd'hui la ligne
      « Ce qu'une session écrit **hors du dépôt** » dit déjà la phrase juste — *« la
      ligne « rien ne le fera ici » reste vraie de ce qui est écrit comme donnée ;
      elle ne couvre pas ce que le pack exécute ensuite »* — et ne donne qu'un
      propriétaire, [46], pour `~/.gitconfig`. Le `PATH` est le second cas et il
      n'en a aucun.
- [ ] Une mutation peut rendre la garantie livrée rouge. Si la décision est (a) ou
      (b), c'est mécanique. Si c'est seulement une phrase, **ne pas livrer de code
      mort** : la phrase va au tableau et le ticket dit pourquoi rien n'est
      vérifiable ([47] a écrit cette règle).

## Ce qui a été mesuré, le 30/08/2026 (passe transversale)

Sonde conservée : `.scratch/ralph-pack/sondes/passe-30-08/r5-le-path-du-pilote.bats`.

- **`R5a`.** Une session pose un `git` (passthrough enregistreur) dans un
  répertoire du `PATH` du pilote, depuis une itération **verte** (`rc=0`,
  `01-alpha resolved`, `committed 1 path(s)`). Le run courant fait **0** appel à
  travers lui ; le run **suivant** en fait **204**, dont `rev-parse --git-dir`,
  `rev-parse HEAD`, `worktree list --porcelain`, `rev-parse --git-common-dir`,
  `config --get core.excludesFile`. Aucune ligne de gate, aucune ligne de zone,
  aucun reçu, aucune dérive de capacité.
- **Pourquoi 0 pour le run courant, et c'est un piège de sonde autant qu'un fait
  du pack** : bash **hashe** les chemins de commandes. Le pilote avait résolu `git`
  bien avant que la session existe. Ce qui compte est donc tout bash **frais** —
  le run suivant, les `bash -c` de `TEST_CMD`/`TYPECHECK_CMD`, et le successeur.
  Une sonde qui ne mesure que le run courant conclut l'inverse de la vérité.
- **`R5b`.** La ligne mise en file porte le `PATH` du pilote **verbatim**, le
  répertoire posé par la session compris. `gate_frontier_residue` — la seule chose
  qui puisse refuser d'armer — ne rend rien : son périmètre est la configuration
  git partagée.
- **`R5c`.** `gate_config_keys` a 53 entrées. `PATH` est lu **une seule fois** dans
  tout le pack : `scheduler.sh:322`, pour le recopier dans la file.

## Ce qu'il faut savoir avant d'ouvrir ce code

- **`claude` est la même porte et elle est pire.** Le pack le lance par son nom nu.
  Un `claude` interposé possède toutes les sessions **et** toutes les lentilles de
  revue du run suivant, c'est-à-dire les deux moitiés du jugement.
- **Un `git` interposé ne contourne pas les contrôles du pack, il les fabrique.**
  Le verrou d'arbre ([22]) lit `rev-parse --git-dir`, la frontière de visibilité
  ([30], [41], [46]) lit `config --get` et `check-ignore`, l'arbre jugé ([21],
  [29]) est un `add`/`write-tree`. Un témoin bâti *avec* git ne peut pas témoigner
  *contre* git.
- **La différence avec « une session peut exécuter du code ».** Ça, c'est assumé au
  niveau du pack ([20], `--dangerously-skip-permissions`). Ce ticket porte trois
  choses de plus, et ce sont exactement celles qui ont fait de [46] un ticket :
  l'écriture **survit au rollback** (hors de tout arbre jugé), elle **s'exécute
  dans l'arbre de process du pilote** et non dans la session, et elle **traverse le
  redémarrage** jusqu'à un run que personne ne regarde.
- **Le témoin de [15] ne couvre pas ça.** Il regarde `.claude/*` dans l'arbre
  principal et dans le `$HOME` de l'opérateur — ce qu'un `claude` frais *charge*.
  Un répertoire du `PATH` n'est pas chargé, il est *exécuté*.
- **Ne pas armer un vrai binaire dans une sonde sans passthrough.** Le `git` planté
  par `R5a` réexécute le vrai ; un shim cassé ferait rougir la suite au lieu de
  mesurer la portée.

## Ce que [53] a laissé ici (livré le 30/08/2026)

- **La ligne mise en file a changé de forme.** Elle ne finit plus par une
  redirection : elle exécute `bash -c '<scheduler__wake>' ralph-successor <log>
  <repli> <loop.sh>`. `scheduler__wake` est le **préflight du job** — le shell qui
  tourne avant `loop.sh`, donc avant tout préflight et tout gate du pack — et
  c'est l'endroit prévu pour ce que ce ticket doit vérifier au réveil. Le
  commentaire de la fonction le dit ; y loger la réponse plutôt que d'en bâtir une
  seconde.
- **Trois contraintes pour y ajouter quelque chose** : la sortie doit rester **une
  seule ligne** (le shim d'`at` enregistre `command: <une ligne>` et les tests
  relisent par `sed`) ; les chemins arrivent en positionnels — `$1` le log, `$2`
  le repli, `$3` `loop.sh` — donc un argument ajouté décale la numérotation, à
  mettre **après** `$3` ; le shell du job est bash par chemin absolu et pas `sh`.
- **`scheduler.sh:322` a bougé.** Le `PATH` est toujours lu une seule fois, dans
  `scheduler_command`, mais le numéro de ligne de `R5c` est périmé.
- **La ligne porte maintenant `FEATURE` aussi**, et le refus d'armer a un code de
  retour par raison (`scheduler_outcome` en fait un mot de journal). Un refus
  d'armer que ce ticket ajouterait prend **un code neuf** et un mot neuf, pas un
  des cinq existants.
