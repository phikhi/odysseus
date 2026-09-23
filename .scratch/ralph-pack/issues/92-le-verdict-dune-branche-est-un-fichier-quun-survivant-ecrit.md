# 92 — Le verdict d'une branche est un fichier qu'un survivant écrit

**What to build:** Que le verdict d'une branche du gate ne voyage plus par un fichier qu'un process laissé derrière elle par la session jugée peut écrire — et que ce qu'une session laisse derrière elle en finissant normalement soit tranché plutôt que non-dit.

**Blocked by:** 91

**Write-surface:** `.claude/lib/gate.sh`, `.claude/lib/proc.sh`, `.claude/lib/monitor.sh`, `.claude/lib/session.sh`, `test/gate.bats`, `test/proc.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** resolved

- [x] Le verdict d'une branche arrive à `gate__aggregate` par un canal qu'un process extérieur à l'arbre du pilote ne peut pas écrire. `gate__await` jette aujourd'hui le statut du `wait` à dessein (*« le verdict d'une branche est le fichier `.rc` qu'elle a écrit »*) alors que `proc_collect` le lui rend : le commentaire qui porte cette décision est à réécrire, pas à contourner.
- [x] Les **trois** réponses restent distinctes après la réparation : une branche qui rend un code, une branche tuée à l'échéance (`timed-out`), une branche partie sans rien laisser. [43] et [45] ont payé cette distinction ; un canal qui les confondrait produirait un document disant `tests=red` sans qu'une ligne dise que rien n'a tourné.
- [x] Ce qu'une session laisse derrière elle en **finissant normalement** est tranché. `proc_kill_tree` a quatre appelants et les quatre sont des échéances ; au retour normal, rien ne marche l'arbre. Deux sorties possibles et une seule à choisir, avec son prix écrit : un **groupe de process** pour la session (que `proc_kill_tree` dit en toutes lettres que ce shell ne fabrique jamais), ou l'aveu dans le tableau que le pack ne reprend pas ce qu'une session a démarré. « `proc_kill_tree` sur le pid après coup » n'en est pas une : le pid est mort et ses enfants sont déjà reparentés à `init`.
- [x] La ligne « Ce qu'une session peut atteindre pendant qu'une **autre** itération est jugée » du tableau est réécrite : sa prémisse (*« aucune session n'était vivante pendant qu'un gate écrivait »*) et sa borne (*« rien de tout ça n'est ouvert à `MAX_PARALLEL=1` »*) sont fausses toutes les deux.
- [x] Les tests mettent en scène un **survivant réel** et assertent ce qui a changé : sur une suite rouge, le ticket ne part pas `resolved`. Témoin appairé obligatoire — sans survivant, le même scénario doit rougir.
- [x] Une entrée de mutation par garantie livrée, avec le témoin appairé.

## Comments

- **Ordre validé par Philippe le 22/09/2026** : **[91] → [92] → [93]**.
  Le critère est celui d'habitude — minimiser la reprise, jamais l'urgence. [91]
  devant parce qu'un `bash` planté possède l'interpréteur des quatre commandes du
  projet et rendrait inutile toute réparation faite à l'intérieur du gate ; [92]
  ensuite, seul ticket qui touche le cycle de vie d'une session, et il réécrit la
  borne de la ligne 35 du tableau ; [93] en dernier, purement dans `test/`, sa
  ligne de tableau étant l'aveu générique dont les deux autres sont les cas
  adressables.

- **Ouvert par la passe transversale du 22/09/2026** (`../passe-transversale-22-09.md`,
  §2). Sonde : `../sondes/passe-22-09/q3-le-verdict-ecrit-par-un-survivant.bats`.

- **Mesuré à `MAX_PARALLEL=1`, la valeur livrée**, suite rouge
  (`stub_exit tests 1`) dans les deux cas. Témoin appairé, sans survivant :
  `tests=red` trois fois, deux retries frais, ticket `ready-for-human`, `exit 4`.
  Avec un process laissé par la session : `tests=green typecheck=green
  scope=green lang=green`, ticket **`resolved`**, run `exit 0`, **dès la première
  itération**, et aucune ligne ne nomme quoi que ce soit. `gate_run` finit par
  `rm -rf "$dir"`, donc il n'en reste rien non plus.

- **Le survivant n'a rien d'exotique** : un `nohup` qui attend
  `$TMPDIR/ralph-gate.*` et réécrit `0` dans les `.rc`. Troisième mesure, sans
  rien d'hostile : une session qui laisse un `sleep` est **encore vivante quand le
  run a fini**, reparentée à `init` (`ppid 1`). C'est le cas que le commentaire de
  `proc_kill_tree` décrit pour expliquer pourquoi la marche existe — *« un serveur
  de dev monté par l'outil Bash d'une session »* — et il n'est traité que sur les
  chemins d'échéance.

- **Ce que ce ticket ne rouvre pas.** L'écriture d'un verdict par une session
  **sœur** au-dessus de `MAX_PARALLEL=1` est nommée, mesurée et assumée par le
  tableau depuis [13], et [80] y a ajouté un poste. Ce qui est faux est la borne :
  « la session a fini » et « les process de la session ont fini » sont deux choses.

- **La forme est celle de [80] et [81]**, un cran plus loin : `$dir/*.rc` est un
  `mktemp` sous `$TMPDIR`, dans un répertoire qu'un `ls` énumère, et **créé après
  le sceau de [81]** — donc hors de tout ce que ce sceau couvre, par construction
  et non par oubli.

- **Contrainte héritée de [91]** : tant que `bash` n'est pas surveillé, une
  session peut planter l'interpréteur des quatre commandes du projet et le canal
  du verdict ne change rien pour elle. [91] passe devant pour cette raison.

- **Livré le 23/09/2026.** Deux garanties et un aveu, et les trois ont changé du
  code.

- **La sortie choisie pour « ce qu'une session laisse en finissant normalement » :
  le groupe de process.** `session_spawn` arme `set -m` le temps d'un seul fork —
  la session devient chef d'un groupe à elle — et `session__sweep` demande à ce
  qui reste dans ce groupe de s'arrêter, puis le nomme sur `stderr`. Le prix est
  écrit dans `docs/frontiere-de-confiance.md` (nouvelle ligne, juste sous la 35) :
  TERM et rien après, un descendant qui `setsid` est hors de portée du groupe
  comme il l'est de la chaîne de ppid, et `proc_group_members` **énumère** les
  membres au lieu de signaler le numéro.

- **Pourquoi « `proc_kill_tree` sur le pid après coup » est bien impossible, et
  pourquoi le groupe ne l'est pas.** Sondé sur 3.2.57 : bash récolte un fils en
  arrière-plan dans son propre handler `SIGCHLD`, donc quand `monitor_watch` rend
  la main le pid de la session est **déjà sorti de la table des process**, sans
  qu'on ait attendu quoi que ce soit — `kill -0` échoue au bout de ~0,9 s, `ps -p`
  ne rend rien. Le *groupe*, lui, est encore là : son numéro est tenu tant qu'un
  membre existe, et c'est exactement le survivant qu'on cherche. Donc soit la
  session a laissé quelque chose et le numéro le nomme, soit elle n'a rien laissé
  et il n'y a rien à trouver.

- **Le prix du groupe que j'ai cru mesurer et qui n'en est pas un.** Première
  hypothèse : `set -m` polluerait `run.log` avec les notifications de job de bash
  (`line NN: 12345 Terminated: 15  …claude -p --model…`). **Mesuré : la
  notification arrive avec ou sans `set -m`** (3.2.57, six essais) — elle est
  imprimée sur le stderr de la première commande qui suit la mort du job, et dans
  le pack cette commande est le `wait` de `proc_collect`, dont le stderr est
  redirigé. Ce n'est donc pas un argument contre le groupe. À ne pas re-sonder.

- **Le piège qui a coûté un rouge, et qui est le vrai contenu technique du
  ticket.** Le premier jet faisait répondre le chien de garde par son statut de
  sortie, et `test/loop-happy-path.bats` « bounded by the deadline » est passée au
  rouge : `gate__await` collecte les branches **puis** TERM le chien de garde — or
  les branches ne meurent *que parce que* le chien de garde les a tuées, donc ce
  TERM arrive pendant qu'il est encore dans `proc_kill_tree`, à forker un `ps` par
  niveau et par cible. Réponse 143, cause perdue. Le correctif est
  `trap "exit $GATE_WATCHDOG_FIRED" TERM` **armé avant le premier signal** : entre
  le moment où `proc_countdown` réussit et le `trap`, rien ne peut envoyer ce TERM
  puisqu'aucune branche n'est encore morte. Le test qui le tient
  (`test/gate.bats` « still says so when it is put away ») met un `ps` lent sur le
  PATH et nomme la même cible quatre fois : une course qu'on ne perd
  qu'habituellement ne prouve rien.

- **Le `.rc` n'est pas gardé comme diagnostic, il n'est plus écrit du tout.**
  `gate_run` finit par `rm -rf "$dir"`, donc personne ne l'aurait jamais lu ; le
  laisser aurait laissé l'objet forgeable en place pour le prochain lecteur. Idem
  pour le marqueur `timed-out`, qui décidait **deux** choses et pas une : la
  phrase d'une branche sans verdict, et le droit de la phase des lentilles de lire
  un refus dans un flux (`lenses_refused_posture`) — un survivant qui déposait ce
  fichier faisait compter comme une tentative une lentille que l'API n'a jamais
  laissée démarrer.

- **Les trois réponses, après réparation** : `0` vert ; `1..127` « red (exit N) »,
  la branche a atteint la fin de sa commande ; `>128` la branche est morte d'un
  signal sans y arriver, et `GATE_TIMED_OUT` tranche entre « timed out » et « no
  verdict ». Une commande que le noyau tue tombe sur le second bras, et c'est sa
  place : une suite qui segfaulte n'a rien jugé non plus.

- **Ce que ça coûte, écrit comme tel** : la fenêtre que `proc_collect` documente
  devient un verdict. Une branche qui finit dans l'instant où un signal trappé
  atteint le shell rend un statut >128 et se lit « no verdict » — rouge, là où le
  fichier disait vert. C'est la direction prudente et le même échange que ce
  commentaire fait déjà pour une session.

- **Ce qui reste à portée d'un survivant et qui n'est pas un verdict** (nommé
  ligne 35 du tableau, pas refermé ici) : `$dir/<branche>.out` — donc les constats
  du reçu, de la prose —, `$dir/scope.class` — la classe d'échec, donc le budget
  de reprise, jamais un vert —, `$dir/lang.zone`, et le répertoire de slot. Aucun
  ne peut rendre un rouge vert. Si ça vaut un ticket, c'est à une passe de le
  dire.

- **Mutations** : 7 nouvelles entrées `92`, 6 ré-ancrées (`05 a branch with no
  verdict counts green` visait `-z "$brc"`, qui n'arrive plus — ré-ancrée sur
  `>128` ; `25 the branches are collected with a bare wait again`, `07` ×3, `36 a
  deadline that fires at nobody loses the cause` — l'édition déplace la réponse
  dans la boucle au lieu de retirer une écriture —, `43 a lens the watchdog
  killed…`, `06 a lens that never returns…`). Une entrée a été mesurée VACUOUS et
  re-visée : « the deadline never reports that it expired » est portée **deux
  fois** (le `return` et le `trap`), et sur un vrai gate c'est toujours le `trap`
  qui répond — l'entrée nomme donc le test unitaire d'un délai que personne ne
  range.
