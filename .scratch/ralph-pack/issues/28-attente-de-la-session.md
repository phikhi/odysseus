# 28 — La session n'est pas attendue quand le stop tombe pendant son extinction

**What to build:** Fermer le second exemplaire du défaut de [25]. `session_spawn` attend `claude` avec un `wait "$pid"` nu, que bash court-circuite dès qu'un signal piégé arrive — le trap `loop_request_stop` en est un. La boucle reprend alors la main pendant que `claude` tourne encore : elle juge, rollbacke, `rm -f` le flux qu'il écrit, et sort du run en le laissant vivant. La primitive de collecte existe déjà (`gate__collect`), mais elle est privée au gate : la première décision de ce ticket est de dire **où elle vit**.

**Blocked by:** None

**Write-surface:** `.claude/lib/session.sh`, `.claude/lib/gate.sh`, `.claude/lib/state.sh`, `test/smart-zone.bats`, `test/gate.bats`, `test/layering.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** resolved

- [x] Un TERM reçu pendant qu'une session se ferme ne fait pas sortir la boucle avant elle : `claude` est attendu jusqu'à son code de retour. Aucun `claude` ne survit au run — par deux mécanismes différents, et c'est le point : `proc_collect` pour la session, `gate__kill_tree` pour une lentille, qui n'est pas exposée à cette fenêtre du tout (voir le commentaire).
- [x] Le flux de session n'est pas supprimé tant qu'un `claude` peut encore y écrire — et c'est asserté par ce que la boucle **lit** dedans après le stop (`turns=7`), pas par l'ordre des lignes de `loop.sh`.
- [x] La primitive de collecte a un seul exemplaire dans le pack : `proc_collect`, dans `.claude/lib/proc.sh`. Elle **rend le code de sortie** au lieu de 0, ce que la version privée du gate ne faisait pas et dont `session_spawn` a besoin.
- [x] Le test vise la fenêtre **soft-limit**, la seule où `wait` bloque vraiment, et il a été écrit **avant** le correctif : `test/smart-zone.bats`, « a graceful kill during a session's shutdown waits for it ».
- [x] La ligne « Une itération en cours finit quand un humain arrête le run » de `docs/frontiere-de-confiance.md` cesse de décrire une fenêtre ouverte — et gagne ce que ni [25] ni ce ticket n'avaient sondé : ce qu'un vrai Ctrl-C fait.

## Comments

- **Origine : question 4 posée en livrant [25], le 29/07/2026.** Le trou du gate était un `wait` nu ; `grep -n '\bwait\b' .claude/` en rend **deux**, et le second est écrit séparément avec la même faille. La leçon est dans `docs/frontiere-de-confiance.md` : une primitive de la boucle est un défaut répété autant de fois qu'elle est appelée.

- **Pourquoi la fenêtre est réelle, et laquelle viser.** `monitor_watch` sort de sa boucle de deux façons. Sur le chemin normal il attend d'avoir constaté le process parti (`alive=0`, plus une dernière lecture), donc le `wait` qui suit ne bloque pas : la fenêtre est de l'ordre de la microseconde, et si elle est touchée la conséquence est une session verte rollbackée et retryée. Sur le chemin **soft-limit** il fait `kill -TERM` puis `rc=1; break` — il rend la main *sans* attendre que `claude` meure. `wait` bloque alors pendant toute l'extinction, et un vrai `claude` ne se ferme pas instantanément. C'est cette fenêtre qu'il faut tester.

- **Sonde reproduite, le 29/07/2026, avec témoin dans les deux sens.** `SOFT_LIMIT_TOKENS=1000`, un faux `claude` qui émet un `usage` à 5010 tokens, **ignore** le TERM du moniteur (`trap '' TERM`), pose un marqueur 0,6 s plus tard — le temps que le moniteur ait tiré et que la boucle soit entrée dans `wait` — puis vit 8 s de plus. Seule la première session est lente : sinon le `claude` du re-slice tient le run plus longtemps que celui qu'on observe et l'orphelin a le temps de finir, ce qui a masqué la sonde au premier essai.

  ```
  ralph: iteration 1: 01-alpha
  ralph: stop requested — finishing the current iteration
  ralph: session crossed the 1000-token soft limit (peak 5010) — terminated
  ralph: 01-alpha: no re-slice plan came back
  ralph: 01-alpha: escalated to the human sink (too-big)
  ralph: stopped on request after 1 iterations
  === ORPHELIN : le run est sorti, claude tournait encore ===
  ```

  Témoin, même scénario sans TERM envoyé au run : `=== claude avait fini quand le run est sorti ===`. C'est bien l'interruption du `wait` qui produit l'orphelin, pas le chemin soft-limit lui-même.

- **Ce que la sonde ne change pas, et pourquoi la gravité reste bornée.** Le *verdict* est le même dans les deux cas : `RALPH_SOFT_LIMIT_HIT` valant 1, la boucle prend la branche `over-soft-limit` quel que soit le code que `wait` a rendu. Ce qui fuit est le process et le quota, pas la décision. Sur le chemin normal en revanche, une interruption ferait passer une session verte en `failed` — fenêtre minuscule, conséquence franche.

- **Conjonction requise, à peser pour la priorité.** Il faut un humain qui arrête le run *pendant* l'extinction d'une session qui vient de franchir la limite douce. Rare. Ce qui le rend digne d'un ticket : la conséquence est du quota brûlé sans surveillance sur un run AFK — le budget est un abonnement, donc c'est de la capacité prise à la nuit suivante — et [06] multiplie les appelants de `session_spawn`.

- **Contrainte pour [06].** Une lentille qui lance `claude` passe par `session_spawn` ([20]), donc elle héritera de cette primitive. Deux choses à savoir : dans une branche de gate les traps du parent sont **réinitialisés** (bash ne conserve pas un trap non ignoré dans un sous-shell), donc une branche ne reçoit pas le TERM du run et n'est pas exposée à cette fenêtre ; mais la branche est tuée par le chien de garde via `gate__kill_tree`, qui descend l'arbre de processus — c'est ce chemin-là, et non `wait`, qui doit garantir qu'aucun `claude` de lentille ne survit à un dépassement de `GATE_TIMEOUT`.

- **Contrainte pour [23].** Le pendant temporel d'une session qui pend est ce ticket-là, et les deux se rejoignent sur `session.sh`. Un timeout de session qui tuerait `claude` sans l'attendre reproduirait exactement l'orphelin décrit ici : le piège déjà noté dans [23] (« un timeout n'est pas un over-soft-limit ») en a un second, celui-ci.

## Livré le 30/07/2026

- **La sonde du ticket a d'abord été rejouée comme test, avant une ligne de correctif** — `test/smart-zone.bats`, « a graceful kill during a session's shutdown waits for it ». Rouge sur l'assertion exacte de l'orphelin : `expected file to exist: .../session-finished`. Le témoin est le correctif lui-même (la même assertion passe après), et le mutant `wait "$pid" || rc=$?` la refait rougir.

- **Où vit la primitive : `.claude/lib/proc.sh`, un module d'une seule fonction.** La question posée par le ticket était la première à trancher, et aucun fichier existant ne pouvait l'héberger. `gate.sh` et `session.sh` se seraient rendus dépendants l'un de l'autre, ce que `test/layering.bats` refuse ; `state.sh` — le seul autre candidat, et il était dans la write-surface pour ça — parle d'état de run (racine du projet, écriture atomique, verrous), pas de processus enfants. Un module d'une fonction est le bon prix quand la fonction est une primitive : le module *est* la trace de pourquoi elle ne vit chez personne. Rien à câbler, `loop.sh` sourçant `lib/*.sh` en ordre lexical.

- **Ce que la primitive fait de plus que la version privée du gate : elle rend le code de sortie.** `gate__collect` répondait `return 0` dans les deux sorties, ce qui était correct pour son seul appelant — le gate lit ses verdicts dans les fichiers `.rc`. `session_spawn` rend au contraire le code de la session à la boucle, qui en fait `outcome=failed`. Une primitive qui répond 0 pour tout enfant transforme une session morte en ticket résolu. Deux conséquences : `gate__await` jette explicitement le statut (`|| true`, sinon `set -e` sort du gate quand le chien de garde répond 143, ce qui est attendu puisqu'on vient de le tuer), et la garantie « le statut remonte » a sa propre mutation, pointée sur un test qui existait déjà (`failures.bats`, « a dead session is retried too »). Une mutation de plus valait mieux qu'un test unitaire redondant.

- **Ce qui n'a pas été déplacé, et pourquoi c'est un choix.** `gate__kill_tree` est le voisin immédiat de la primitive et [23] en aura besoin pour tuer `claude` avec ses outils. Il reste privé au gate : la règle 6 dit « un second appelant veut dire que la fonction est publique », pas « anticipe-le ». Le déplacement coûtera un rename le jour où [23] l'appellera — noté dans [23].

- **Le seul test que ni le gate ni la session ne pouvaient couvrir** : `test/proc.bats`, « an interrupted wait still answers the status the child really exited with ». Les deux tests de bout en bout prouvent l'**attente** (la branche et la session ont le temps de finir) mais aucun ne prouve le **statut** : sur le chemin soft-limit `RALPH_SOFT_LIMIT_HIT` décide de l'issue quoi que `wait` ait rendu, et sur le chemin normal la fenêtre est de quelques microsecondes. Or c'est là que se cache la conséquence franche : un `wait` nu rend 143 quand un trap l'a coupé, et la boucle lit ce 143 comme le code de la session — un humain qui tape Ctrl-C transformait une session qui allait réussir en crash, rollback compris. Le test est déterministe (fils qui sort 7 après 1 s, signal au shell à 0,3 s) et rouge sur le mutant.

- **La moitié « lentille » de « aucun `claude` ne survit au run », qui n'était couverte par rien.** Une branche de gate tourne dans un sous-shell, qui ne conserve pas le trap du parent : une lentille n'est donc **jamais** exposée à la fenêtre que ce ticket ferme. Ce qui doit tenir pour elle est autre chose — que le chien de garde descende l'arbre de processus, une lentille étant un petit-fils de la boucle. `test/lenses.bats`, « the lens phase has a deadline of its own », enregistre maintenant le pid de la lentille et vérifie qu'il n'est plus là quand le run est sorti. Mutant validé à la main avant d'être ajouté : sans la récursion de `gate__kill_tree`, le message est `the lens session outlived the run the watchdog stopped`.

- **Trouvaille : ni [25] ni ce ticket n'avaient sondé ce qu'un humain fait réellement pour arrêter un run.** Les deux raisonnements sont écrits contre un `kill -TERM <pid>`, qui ne va qu'au run. Un Ctrl-C envoie SIGINT au **groupe de processus** entier — donc aussi à `claude`, aux branches du gate et à `TEST_CMD`. Sur cette lecture, le correctif de [25] ne couvrait que la moitié des cas et un Ctrl-C démantelait l'itération. Sondé le 30/07/2026 dans les deux fenêtres (gate et extinction de session), avec `set -m` pour que le run ait son propre groupe et `kill -INT -$pgid` :

  ```
  ralph: stop requested — finishing the current iteration
  ralph: gate: 01-alpha: tests=green typecheck=green scope=green
  ralph: iteration 1: 01-alpha -> resolved
  === gate-finished: yes   === Failures: (vide)
  ```

  ```
  ralph: session crossed the 5000-token soft limit (peak 9015) — terminated
  === session-finished: yes
  2026-07-30T18:38:12Z  01-alpha  over-soft-limit  turns=7  cost=0.3  tokens=9015
  ```

  Ça tient, et **pas grâce au pack** : sondé directement, sur bash 3.2.57, un enfant asynchrone d'un shell non interactif a SIGINT sur `SIG_IGN` (`after INT: child ALIVE`, `after TERM: child gone`). C'est une garantie empruntée au shell, que personne ici n'avait écrite ni vérifiée — d'où le corollaire ajouté à `docs/frontiere-de-confiance.md`. Ce qui ne tient pas, et n'a pas de correctif : un `kill -TERM` adressé au groupe entier tue `claude` et les branches. Ce n'est pas une fuite — rien ne survit — mais ce n'est pas un arrêt gracieux.

- **Ce que le correctif ne fait pas, délibérément, exactement comme [25] : le stop n'a pas de délai à lui.** La session est maintenant attendue jusqu'au bout, donc un `claude` qui ignore le TERM du moniteur fait pendre le run. Ce n'est pas une régression — sans stop, le `wait` nu pendait déjà de la même façon ; ce qui disparaît est une sortie de secours involontaire, qui coûtait un orphelin et du quota. Combien de temps une session peut durer est la question de [23], et d'elle seule. Escalader TERM puis KILL depuis le moniteur reviendrait à inventer ici une seconde notion de « trop long » : à écrire dans [23], pas dans `monitor.sh`.

- **Une course reste, et elle n'est pas testable.** Un enfant qui meurt dans l'instant où un signal piégé arrive est indistinguable d'un enfant tué par ce signal : `wait` rend > 128 et `kill -0` échoue, donc 143 est rendu à la place du vrai code. Quelques microsecondes, et seulement sur le chemin normal — où le moniteur a déjà constaté le process parti avant qu'on arrive au `wait`, donc aucun signal n'est en attente. Un troisième `wait` la refermerait (un fils non moissonné rend son vrai code), et il a été écarté : son effet n'est observable que dans la course elle-même, donc aucune mutation ne peut le couvrir. Ce qu'elle coûte est une session verte retryée, jamais une rouge passée. Écrit dans le commentaire de `proc_collect`.

- **Trouvaille de la suite complète : un module neuf casse un harnais qui énumère les libs à la main, et le message accuse le mauvais côté.** `test/contract-claude.bash` sourçait `monitor.sh` et `session.sh` nommément avant d'appeler `session_spawn` — une liste correcte jusqu'à ce qu'un lib gagne une dépendance. Le symptôme n'était pas « proc.sh manque » mais :

  ```
  .claude/lib/session.sh: line 52: proc_collect: command not found
  the session exited 127 on a prompt that cannot fail: the loop would count this iteration as failed
  -> the fake claude has drifted from the real format: fix test/helpers/shims/claude
  ```

  Le contrat envoyait donc réparer le **shim**, alors que rien n'avait dérivé : c'est le pack qui ne se chargeait pas. Le spawn du contrat source maintenant `lib/*.sh` en entier, comme `loop.sh` — un harnais qui énumère le pack à la main teste un pack qui n'est pas celui qu'on installe. `contract__load_pack` garde sa liste explicite, à dessein et c'est écrit : lui charge dans le shell du test, où déverser tout le namespace du pack à côté des helpers serait pire.

- **Trouvaille du gate de mutation, et elle vise ce ticket : un délai de fake peut porter la mutation d'un *autre* ticket.** Le fake de lentille dormait 120 s ; je l'ai raccourci à 30 pour ne pas laisser un `sleep` orphelin quand mon assertion tue une lentille survivante. La suite est restée verte et `test/mutate.sh` a rendu `VACUOUS 06 a lens that never returns is left to hang`. Le mécanisme : cette mutation retire le chien de garde, le test donne 60 s au run pour revenir, et une lentille qui finit d'elle-même en 30 s revient dans ce délai — elle n'a émis aucun verdict, donc le gate est rouge de toute façon et l'assertion du test passe. La garantie de terminaison de [06] n'était plus couverte, sans qu'un seul test rougisse. Deux choses à retenir : le nombre est revenu à 120 avec **le commentaire qui dit pourquoi il est porteur**, et la règle générale — dans un test qui couvre une terminaison, tout délai est une constante de couverture, y compris ceux qui appartiennent à un ticket qu'on ne touche pas.

- **Écarts de write-surface, assumés, cinq fichiers en plus des huit déclarés.** `.claude/lib/proc.sh` et `test/proc.bats` : la write-surface a été écrite en supposant que la primitive irait dans un fichier existant, et la décision du ticket a été de créer le module. `test/lenses.bats` : la moitié lentille de l'AC 1 s'assertait là et nulle part ailleurs. `README.md` : sa ligne « Failles connues » nommait ce ticket comme ouvert, et sa section Structure énumère les libs — elle gagne `proc.sh`, plus `claim.sh` et `lenses.sh` qui manquaient depuis [12] et [06], et la liste des livrés gagne [28] et [31], oublié par son propre ticket. `test/helpers/claude-contract.bash` : trouvé par la suite complète, voir le point ci-dessus. `test/gate.bats` reste dans la write-surface mais **perd** un test, migré vers `test/proc.bats` avec un renvoi à sa place.
