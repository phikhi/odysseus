# 95 — Ce que le pack lance lui-même n'est rangé par personne

**What to build:** Que les trois programmes du projet que ce pack lance — `TEST_CMD`, `TYPECHECK_CMD`, `RUN_CMD`/`VISUAL_CMD` — soient repris et nommés au retour normal comme [92] l'a fait pour une session, ou que l'écart soit écrit là où le tableau parle déjà de ce qu'une session laisse tourner.

**Blocked by:** None

**Write-surface:** `.claude/lib/gate.sh`, `.claude/lib/playthrough.sh`, `.claude/lib/proc.sh`, `.claude/lib/session.sh`, `test/gate.bats`, `test/playthrough.bats`, `test/proc.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

- [ ] Les **trois** sites sont traités, pas le premier. Recensement dérivé plutôt que retapé : le pack a un seul `set -m` (`session.sh:73`) et trois `bash -c "$<CMD>"` (`gate.sh:4041` tests, `gate.sh:4048` typecheck, `playthrough.sh:291` run/visual). Un quatrième site ajouté demain doit faire rougir un test le jour où il est écrit — c'est la leçon de [91] sur `gate_path_programs`.
- [ ] Ce qu'un de ces programmes laisse tourner en **finissant normalement** est repris, ou l'écart est nommé à chaque fois avec son prix, comme [24] l'exige d'une zone que personne ne garde. Mesuré : un `sleep` laissé par `TEST_CMD` est **vivant quand le run a fini**, `ppid 1`, run **vert** (exit 0), ticket `resolved`, et **aucune ligne** ne le nomme.
- [ ] Le `pgid` est la contrainte et il est déjà tranché par [92] : le survivant mesuré porte le groupe **du pilote**, et `proc_group_members` refuse son propre groupe à dessein. Un sweep posé sans donner d'abord au fork un groupe à lui ne trouverait rien — le test doit le montrer, pas le supposer.
- [ ] La **course du chien de garde** est reprise, pas contournée. `gate__watchdog` vise les branches **par pid**, `gate__await` le range en lui envoyant TERM pendant qu'il agit, et [92] a payé cette course d'un rouge (`trap` armé avant le premier signal). Un groupe change ce que ce garde peut atteindre ; le test qui le tient met un `ps` lent en tête du `PATH` et nomme la même cible plusieurs fois — une course qu'on ne perd qu'habituellement ne prouve rien.
- [ ] Le **playthrough** est traité comme le membre le plus exposé : `RUN_CMD` **est** un serveur par conception (*« A server that boots correctly and waits is the normal case »*), il tourne dans l'**arbre principal** (`cd "$(ralph_project_root)"`) et non dans un worktree jetable, et son `proc_kill_tree` n'arrive que sur le chemin d'échéance.
- [ ] Le tableau gagne sa ligne, à côté de « Ce qu'une session laisse **tourner** derrière elle en finissant normalement » : la même phrase pour ce que le **pack** lance, avec le même prix écrit (TERM et rien après, un descendant qui `setsid` hors de portée).
- [ ] Une entrée de mutation par garantie livrée, avec son témoin appairé.

## Comments

- **Ouvert par la passe transversale du 23/09/2026** (`../passe-transversale-23-09.md`, §2). Sonde : `../sondes/passe-23-09/q2-ce-que-la-commande-de-test-laisse.bats`.

- **Ordre PROPOSÉ, à valider par Philippe** : **[95] → [94] → [96]**. Ce ticket passe devant sans être ni le plus gros ni le plus grave : il change la **forme du fork** que [94] doit ensuite traverser avec une classe, une zone et une posture. Concevoir ce canal avant que la forme du fork ne bouge, c'est le reprendre.

- **Rien d'hostile n'est nécessaire.** La mise en scène mesurée est un `&` et un `nohup` — ce que fait tout script qui monte un serveur avant ses tests. Le commentaire de `proc_kill_tree` décrit exactement ce cas pour expliquer pourquoi la marche d'arbre existe : *« une suite de tests qui pend, un serveur de dev monté par l'outil Bash d'une session »*. Il n'est traité que sur les chemins d'échéance, et seulement pour la session.

- **Pourquoi ça compte au-delà de la propreté** : ce que ces trois programmes laissent tourne **pendant le gate qui vient de les lancer**, avec `$TMPDIR` devant lui. Mesuré (sonde `q2b`) : un process laissé par `TEST_CMD` voit `tests.out scope.out typecheck.out lang.out` dans le répertoire du gate. Et mesuré de bout en bout (`q2d`) : il suffit à jouer le canal de [94] — ticket jamais résolu, travail roulé en arrière trois fois, `sterile run`, exit 4 — **sans aucune session hostile**. Témoin appairé `q2c` : vert, `resolved`, exit 0.

- **Le prix de [92] est hérité tel quel et doit être écrit à nouveau** : TERM et rien après ; un descendant qui quitte le groupe (`setsid`, un démon qui se démonise proprement — précisément le serveur de dev) est hors de portée du groupe comme il l'est de la chaîne de ppid. Le pack ne promettra pas que rien ne survit : il promet de reprendre ce qui est resté dans le groupe et de nommer ce qu'il a trouvé.

- **Ce que le commentaire de `session_spawn` dit aujourd'hui, et qu'il faudra réécrire plutôt que contourner** : *« It is not needed to collect the session and it is not wanted for the gate's branches, which this same shell forks a few moments later and which `gate__watchdog` aims at by pid. »* La seconde moitié de cette phrase est la décision que ce ticket rouvre, avec sa mesure.

- **Contrainte créée pour [94]** : si le fork des branches change de forme, le canal par lequel une branche rend une chaîne à son parent change de contexte. Écrit ici et dans [94].
