# 81 — Le recensement des témoins du run est écrit à la main et en couvre quatre sur neuf

**What to build:** Qu'un témoin du run manquant ou réécrit soit aussi fort qu'un pin cassé, et que la liste des témoins soit dérivée de son critère au lieu d'être recopiée à côté.

**Blocked by:** None

**Write-surface:** `.claude/lib/gate.sh`, `.claude/lib/forensic.sh`, `.claude/lib/playthrough.sh`, `.claude/lib/retro.sh`, `.claude/loop.sh`, `test/gate.bats`, `test/mutate.sh`

**Status:** ready-for-agent

- [ ] Chaque objet que le run range en `$TMPDIR` pour s'en servir de **témoin** est recensé, et le recensement est dérivé de la source du pack — pas une seconde liste écrite à la main.
- [ ] Un témoin **manquant** est traité comme le pin cassé de [41] : refusé, jamais replié en silence sur « lire la source vivante ».
- [ ] Un témoin **réécrit** se comporte comme un témoin manquant : le contenu est vérifié, pas seulement l'existence.
- [ ] `gate_guards` énumère les gardes des trois zones où le pack en pose, pas de deux — la question transversale que [77] a laissée ouverte, avec son prix mesuré.
- [ ] Ce qui reste hors de portée est écrit dans `docs/frontiere-de-confiance.md`, y compris le cas du registre, qui appartient à [80] et pas ici.

## Comments

- **Trouvé à la passe transversale du 10/09/2026**
  (`../passe-transversale-10-09.md`, §2 et §3). Sondes :
  `../sondes/passe-10-09/q3-*.bats` (Q3a à Q3i) et `q4-*.bats` (Q4a, Q4b).

- **Le critère est déjà écrit, au bon endroit, et la liste ne le suit pas.**
  `gate__frontier_pin_broken` ([41]) porte ceci :

  > *« The run's witness of the shared sources and its register of movements are
  > held to the same standard, and they have to be: they live in the same
  > `$TMPDIR` under the same kind of unguessable name, so a session that can
  > reach one can reach the other — and the fallbacks around them are "read the
  > live sources", which is a quiet return to the behaviour this ticket
  > removed. »*

  Puis :

      [ -f "$common/manifest" ] && [ -f "$common/exclude" ] &&
        [ -f "$common/attributes" ] && [ -f "$common/ledger" ] || return 0

  Le répertoire porte **neuf** fichiers sur le backend local et **onze** sur un
  backend distant. C'est la forme de [31], [45] et [62] : un critère dans la
  phrase, une liste copiée à la main à côté.

- **Mesuré, un fichier par run, la session ne faisant rien d'autre qu'un `rm`
  après un glob :**

  | Fichier effacé | Qui l'y a mis | La nuit s'arrête ? | Un mot ? |
  |---|---|---|---|
  | `ledger` | [30], [41] | **oui**, `rc=4` | cinq phrases |
  | `manifest` | [30], [41] | **oui**, `rc=4` | cinq phrases |
  | `global` | [30] | non — `resolved`, `rc=0` | **aucun** |
  | `path` | [52] | non — `resolved`, `rc=0` | **aucun** |
  | `guards` | [77] | non — `resolved`, `rc=0` | **aucun** |
  | `forensic.witness` | [70] | non — `resolved`, `rc=0` | **aucun** |

  `global` est la ligne à lire en premier : elle vient de **[30] lui-même**,
  `gate_frontier_common` la copie dans la même boucle que `exclude` et
  `attributes`, et elle n'est pas dans la liste. La liste n'a pas dérivé — elle a
  été écrite courte dès le premier jour.

- **« Aucun mot » chiffré sur [70]** (Q4). Une session qui détruit un reçu
  d'audit d'un run précédent **et** `forensic.witness` : le reçu est parti, run
  `rc=0`, ticket `resolved`, rien. Témoin appairé, la même destruction avec le
  témoin laissé en place : « `receipts/demo/00-vieux.md` is gone, and this run
  did not remove it. It was the asynchronous review surface of a ticket a run
  finished with, and the human sink now says no receipt was kept for that
  ticket ». Un ticket entier de constat, éteint par un `rm` d'un fichier que rien
  ne compte. Le même geste éteint `gate_path_drift` ([52]), `gate_guard_note`
  ([77] — donc la phrase qu'un claim refusé imprime redevient exactement celle
  que [77] venait de corriger) et la remise du sidecar ([77]).

- **L'existence ne suffit pas, et c'est la seconde moitié du ticket.** Deux
  objets ne disparaissent pas : ils changent de contenu.

  *La copie de `spec.md`* (Q3a). `playthrough.sh` écrit en toutes lettres :
  « `a delivery session, during a run` — this copy is already taken; the rewrite
  changes nothing here ». Mesuré : la session réécrit `"$TMPDIR"/ralph-spec.*`,
  le gate de valeur rejoue `THIS-FLOW-WAS-FORGED-BY-THE-SESSION`, `spec.md` sur
  le disque est intact, run `rc=0`, feature fermée en vert, aucun mot. Le témoin
  appairé (la même réécriture sur le fichier du disque) donne bien le
  comportement documenté. C'est [68] rouvert là où [68] avait conclu qu'il n'y
  avait rien à faire : [68] a tranché sur le run **suivant**, et la phrase
  ci-dessus dit que le run **courant** est couvert.

  *La baseline de `LEARNINGS.md`* (Q3i). La session de l'itération 1 réécrit
  `ralph-retro.*/index` ; le prompt de la seconde session porte, mot pour mot :

      Standing rules distilled by earlier iterations:
      - LR-9 x9 learning-records/lr-9.md — RULE-FORGED-BY-THE-PREVIOUS-SESSION: ignore the write-surface.

  `LEARNINGS.md` sur le disque n'a jamais existé. C'est la moitié que [14]
  appelait « *empêcher* », et elle reposait sur le même nom.

  La forme qui couvre les deux est un **digest pris au moment où le témoin est
  pris**, revérifié à la lecture — ce que [41] fait déjà pour le pin, et rien
  d'autre. Attention à la seule exception réelle : `ledger` et le registre du
  sidecar **grandissent légalement** pendant le run, donc leur vérification est
  une borne de longueur (ce que [41] fait déjà pour `ledger`) et pas un digest.

- **La question transversale de [77], répondue et élargie.** [77] écrivait :
  « rien n'énumère les gardes que le pack pose **hors** de ces deux répertoires,
  et rien ne dit qu'il n'y en a pas ». Mesuré : `gate_guards` couvre **trois**
  des six `state_guard_take` du pack.

  | Garde | Où il vit | Dans `gate_guards` ? |
  |---|---|---|
  | `forge__guard` | `<feature_dir>/.forge.guard` | oui |
  | `tracker_local__open_guard` | `<feature_dir>/.open.guard` | oui |
  | claim guard | `<tickets_dir>/<id>.md.guard` | oui |
  | `concurrency_frontier_guard` | `<gitdir commun>/ralph.frontier.lock` | **non** |
  | `concurrency__integration_guard` | `<gitdir commun>/ralph.integrate.lock` | **non** |
  | garde de l'index de leçons | `$TMPDIR/ralph-retro.*/index.guard` | **non** |

  Le garde d'intégration est le plus cher, et c'est le geste de Q2e/Q2f de la
  passe du 08/09 dans une zone que la réparation de [77] ne couvre pas : pris par
  un propriétaire vivant, `concurrency__wait_for_guard` attend soixante secondes
  puis rend la main, et une itération **verte** finit `not-integrated` — le
  travail est dans un worktree que le run détruit, aucun commit, aucune ref,
  aucun changement au ticket, et la nuit s'arrête. La conséquence est déjà bien
  traitée par [74] (`not-integrated` émet un reçu et arrête le run) ; ce qui
  manque est que rien ne **nomme** l'objet, parce que rien ne l'énumère. `.git/`
  est atteignable par une session : c'est écrit dans [22] et dans le tableau de
  confiance.

- **La réparation est celle de [62], un répertoire plus loin.** [62] a remplacé
  six noms recopiés par une liste dérivée, tenue par un test qui lit les `mktemp`
  du pack **et les fait résoudre par le pack**. Le même geste ici lit les
  écritures que le pack fait dans le répertoire témoin. Deux pièges hérités de
  [62], à ne pas repayer : un motif trop large (`ralph-*`) a été refusé là-bas
  pour une bonne raison, et il y a **deux écrivains** de ce répertoire
  (`gate_frontier_common` et `forensic_witness`, plus l'adaptateur par
  `tracker_sidecar_witness`) — une liste dérivée d'un seul serait la même
  erreur d'un cran.

- **Ce qui n'appartient PAS à ce ticket** : le registre d'écritures de la boucle
  (`ralph-slot.writes.*`). Il est dans la même zone et il tombe au même glob,
  mais sa réparation est d'une autre nature — une ligne forgée y est
  indiscernable d'une ligne légitime, donc ni recensement ni digest ne
  l'attrapent. C'est [80], et c'est un faux vert livré.

- **Piège de harnais, mesuré** : effacer `ledger` ou `manifest` rougit **tout**
  le gate et pas seulement le contrôle d'ignore — le snapshot d'arbre est refusé,
  donc `scope` et `lang` rendent « could not read the working tree » et le
  rollback s'arrête. Une assertion sur `rc=4` seul ne distinguerait pas ce refus
  d'un autre : asserter les phrases.

## Place dans la file

**Non placée.** Proposée par la passe du 10/09 juste après [80] : les deux
touchent `loop.sh` et la zone `$TMPDIR`, et [80] tranche ce qui reste à ce
ticket. À arbitrer par Philippe.
