# 92 — Le verdict d'une branche est un fichier qu'un survivant écrit

**What to build:** Que le verdict d'une branche du gate ne voyage plus par un fichier qu'un process laissé derrière elle par la session jugée peut écrire — et que ce qu'une session laisse derrière elle en finissant normalement soit tranché plutôt que non-dit.

**Blocked by:** 91

**Write-surface:** `.claude/lib/gate.sh`, `.claude/lib/proc.sh`, `.claude/lib/monitor.sh`, `.claude/lib/session.sh`, `test/gate.bats`, `test/proc.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

- [ ] Le verdict d'une branche arrive à `gate__aggregate` par un canal qu'un process extérieur à l'arbre du pilote ne peut pas écrire. `gate__await` jette aujourd'hui le statut du `wait` à dessein (*« le verdict d'une branche est le fichier `.rc` qu'elle a écrit »*) alors que `proc_collect` le lui rend : le commentaire qui porte cette décision est à réécrire, pas à contourner.
- [ ] Les **trois** réponses restent distinctes après la réparation : une branche qui rend un code, une branche tuée à l'échéance (`timed-out`), une branche partie sans rien laisser. [43] et [45] ont payé cette distinction ; un canal qui les confondrait produirait un document disant `tests=red` sans qu'une ligne dise que rien n'a tourné.
- [ ] Ce qu'une session laisse derrière elle en **finissant normalement** est tranché. `proc_kill_tree` a quatre appelants et les quatre sont des échéances ; au retour normal, rien ne marche l'arbre. Deux sorties possibles et une seule à choisir, avec son prix écrit : un **groupe de process** pour la session (que `proc_kill_tree` dit en toutes lettres que ce shell ne fabrique jamais), ou l'aveu dans le tableau que le pack ne reprend pas ce qu'une session a démarré. « `proc_kill_tree` sur le pid après coup » n'en est pas une : le pid est mort et ses enfants sont déjà reparentés à `init`.
- [ ] La ligne « Ce qu'une session peut atteindre pendant qu'une **autre** itération est jugée » du tableau est réécrite : sa prémisse (*« aucune session n'était vivante pendant qu'un gate écrivait »*) et sa borne (*« rien de tout ça n'est ouvert à `MAX_PARALLEL=1` »*) sont fausses toutes les deux.
- [ ] Les tests mettent en scène un **survivant réel** et assertent ce qui a changé : sur une suite rouge, le ticket ne part pas `resolved`. Témoin appairé obligatoire — sans survivant, le même scénario doit rougir.
- [ ] Une entrée de mutation par garantie livrée, avec le témoin appairé.

## Comments

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
