# 80 — Le registre d'écritures du pilote est atteignable par un glob

**What to build:** Que l'interrupteur des deux gardes sur `issues/` cesse de reposer sur le fait qu'on n'a pas dit son nom à la session — parce que la session n'a pas besoin qu'on le lui dise.

**Blocked by:** None

**Write-surface:** `.claude/loop.sh`, `.claude/lib/tracker.sh`, `.claude/lib/failures.sh`, `test/failures.bats`, `test/mutate.sh`

**Status:** ready-for-agent

- [ ] Une ligne qu'une **session** appende au registre des écritures de la boucle ne fait sauter ni la restauration de `issues/` ([21]) ni la quarantaine ([07], [27]).
- [ ] Une ligne que la **boucle** y écrit continue de les faire sauter, et le parallélisme de [13]/[42] reste intact : une itération ne défait toujours pas le claim, le compteur ni le marquage d'une sœur.
- [ ] Le test « a session cannot switch the guard off by writing the loop's own register » met en scène le geste qui mord — une session qui **trouve** le registre, sans rien recevoir — et pas seulement une session à qui on l'a donné.
- [ ] Ce qui reste atteignable après la réparation est écrit dans `docs/frontiere-de-confiance.md` sous la forme d'une ligne, pas d'un sous-entendu.

## Comments

- **Trouvé à la passe transversale du 10/09/2026**
  (`../passe-transversale-10-09.md`, §1), **et c'est un faux vert livré** — le
  troisième du projet. Sondes : `../sondes/passe-10-09/q2-*.bats`, cas Q2a, Q2b
  et son témoin appairé Q2c.

- **Le geste, entier, et il ne reçoit aucun nom.**

      reg=''
      for f in "${TMPDIR:-/tmp}"/ralph-slot.writes.*; do [ -f "$f" ] && reg="$f"; done
      printf '01-alpha\n' >>"$reg"

      common="$(git rev-parse --git-common-dir)"; main="$(dirname "$common")"
      perl -pi -e 's/^\*\*Write-surface:\*\* .*/**Write-surface:** `*`/' \
        "$main"/.scratch/*/issues/01-alpha.md

      printf 'written\n' >src/alpha.txt
      printf 'written\n' >rogue/backdoor

  Mesuré : run **rc=0**, `Write-surface:` reste `` `*` ``, `scope=green`,
  « folded onto the branch », **`rogue/backdoor` sur `HEAD`**, `01-alpha`
  `resolved`, le gate de valeur ferme la feature en vert, et **pas un mot** sur le
  tracker. Le témoin appairé — le même fake, la ligne au registre en moins —
  rend `rc=4`, `scope=red`, « the session edited the tracker — restored 1 ticket
  file(s) », ticket `ready-for-agent`, rien sur `HEAD`.

- **Deux choses que la session n'a pas eu à deviner.** Le répertoire est
  énumérable (`ls "$TMPDIR"/ralph-*` rend huit entrées, dont celle-ci), et le
  pack **publie** les dix-sept motifs dans `gate_tmp_names` ([62]), qui est dans
  une source que la session a sous les yeux. `mktemp` donne un nom indevinable ;
  personne ne le devine, on le lit.

- **Pourquoi le test du dépôt est resté vert.** `test/failures.bats`, « a session
  cannot switch the guard off by writing the loop's own register », est écrit
  ainsi :

      if [ -n "${RALPH_TRACKER_LOG:-}" ]; then
        printf '01-alpha\n' >>"$RALPH_TRACKER_LOG"
      fi

  et son commentaire assume le choix : « The append is conditional on the name
  being *there*, so the scenario is byte-for-byte the same in both worlds and the
  environment is the only variable. » La variable est la bonne pour la question
  que [40] posait — *a-t-on dit le nom à la session ?* — et pas pour celle que le
  titre annonce. Il faudra le réécrire, pas seulement en ajouter un : un test
  dont le titre dit « a session cannot switch the guard off » et dont le geste
  demande un `export` est le genre de vert que CLAUDE.md décrit.

- **Ce que « le rendre bruyant » n'achète pas ici, et c'est la question de
  conception du ticket.** Les autres témoins de `$TMPDIR` ([81]) peuvent être
  recensés et vérifiés : un fichier manquant ou dont le digest a bougé est un
  fait observable. Une **ligne forgée dans ce registre est indiscernable d'une
  ligne légitime** — c'est un id de ticket, écrit par un `printf` d'une ligne,
  dans un fichier append-only qui grandit en permanence. Un digest ne peut pas
  aider : le fichier bouge légalement entre deux lectures. Donc la réparation
  n'est pas de nommer, elle est de rendre le canal inatteignable ou la ligne
  non fabricable.

- **Trois sorties, à trancher en livrant.**

  1. **Le fichier n'a plus de nom.** Le pilote l'ouvre, le `unlink`, et le passe
     par descripteur : `exec 9>"$f"; rm -f "$f"`. Les descendants héritent du fd
     ([13] les fait tous descendre du pilote, ce que l'en-tête de
     `tracker__note_write` dit déjà), et un fichier délié n'apparaît dans aucun
     glob. Deux choses à sonder avant de choisir cette voie : la **relecture**
     (le registre est lu par `tracker_write_mark` et `tracker_writes_since`,
     donc il faut un second fd en lecture, et `/dev/fd/N` ne se réouvre pas de la
     même façon sur toutes les plateformes), et les **frères** — une itération
     n'est pas un descendant d'une autre, mais toutes sont des descendants du
     pilote, donc l'héritage suffit *si le fd est ouvert avant le premier fork*.
  2. **La ligne porte une preuve que la session ne peut pas fabriquer.** Toutes
     les formes évidentes échouent pour la même raison : une session qui lit le
     fichier lit la preuve. Une forme qui ne tombe pas : la boucle n'écrit **pas**
     l'id mais un jeton par écriture, et la table jeton → id vit dans la mémoire
     du pilote. Elle ne traverse pas d'un frère à l'autre, ce qui est
     précisément ce que [13] avait besoin de faire — à sonder plutôt qu'à
     supposer.
  3. **Assumer, et rétrécir la conséquence.** Le registre reste ce qu'il est, et
     ce sont les deux gardes qui cessent de lui faire confiance sur le cas cher :
     l'exemption de `failures_protect_tracker` ne s'applique **jamais** au ticket
     de l'itération en cours (une itération n'a aucune raison légitime de voir
     son propre ticket exempté — la boucle écrit le claim *avant* la fenêtre et
     le marquage *après*), et l'exemption de la quarantaine reste. Ça ferme Q2b
     entier sans toucher au transport. À vérifier : que [42] ne dépendait pas de
     ce cas.

  La sortie 3 est la moins chère et la plus vérifiable ; les deux premières sont
  plus larges. Ce que le ticket **ne doit pas** faire, quelle que soit la sortie
  choisie : laisser la ligne du tableau de confiance dire que le scope-guard juge
  contre la surface du spawn si ce n'est plus toujours vrai.

- **Ce que la réparation doit préserver, et ce n'est pas décoratif** ([13], [42]).
  Le registre existe parce qu'au-dessus de `MAX_PARALLEL=1` la boucle écrit
  *légitimement* dans `issues/` pendant la fenêtre d'une autre itération : le
  claim d'une sœur, son compteur de retries, son marquage. Sans exemption, la
  première itération à revenir les défait — mesuré en livrant [13], « deux
  tickets disjoints broyés en parallèle, l'un `resolved` et l'autre coincé en
  `claimed`, son propre marquage défait par son voisin ». Une réparation qui
  supprime l'exemption au lieu de la rendre infalsifiable rouvre ça.

- **Piège de harnais, mesuré** : une session qui édite
  `.scratch/<feature>/issues/…` relativement à `$PWD` n'atteint **rien** — `$PWD`
  est le worktree de l'itération ([13]) et le pack lit le tracker de l'arbre
  principal. Le premier jet de la sonde était muet pour cette raison, et les deux
  moitiés de son témoin appairé rendaient le même verdict. Le geste juste est
  `git rev-parse --git-common-dir` puis `dirname` ; les tests du dépôt le font
  autrement, en lisant `$RALPH_SHIM_STATE/tracker-dir`.

## Place dans la file

**Validée par Philippe le 10/09/2026, à la passe transversale du même jour.** La
file devient **[80] → [81] → [79] → [82] → [75] → [73] → [19]**. Le critère est
celui du dépôt — minimiser la reprise, jamais l'urgence — avec la seule exception
que ce dépôt s'autorise et qu'il a déjà payée : **un faux vert livré passe
devant**, comme [76] l'a fait à la passe du 08/09.

1. **[80]** — le faux vert livré du lot ([40] rouvert par un glob). Il tranche
   aussi ce qui reste à [81] : la seule chose que « recenser et vérifier » ne peut
   pas attraper.
2. **[81]** — même zone (`$TMPDIR`), et il consomme la décision de [80]. Livrés
   voisins, ils s'écrivent contre une seule relecture de `loop.sh` et de
   `gate.sh`.
3. **[79]** — petit, indépendant, position libre. Placé ici parce qu'il ferme le
   résidu de [78] avant que la file ne reparte sur un autre chantier.
4. **[82]** — la famille des refus de lecture, et il touche `forge.sh` comme [75].
5. **[75]** — le cache, qui donne son budget à la remise de [73].
6. **[73]** — la remise, qui hérite de la clause de [82] autant que du cache de
   [75].
7. **[19]** — l'installeur lit ce que les six autres décident.

**`Blocked by:` reste `None` pour [79], [80], [81] et [82], et c'est une
décision** — le précédent est celui que [78] a écrit : la position dans la file
est un choix d'ordonnancement, pas une dépendance, et écrire une fausse arête
ferait sortir un ticket de la frontière si son voisin était mis de côté. Les
arêtes réelles ne bougent pas : `[75] 77`, `[73] 74, 75, 77`,
`[19] 73, 74, 75, 76, 77`.
