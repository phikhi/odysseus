# 57 — le drain ne redemande jamais s'il tient encore ses verrous

**What to build:** Donner au second point d'entrée la question que le premier
repose à chaque itération. `loop.sh` demande `run_lock_is_ours` puis
`tree_lock_is_ours` à chaque tour (l. 1468 et 1477) et s'arrête bruyamment si la
réponse est non — parce que le verrou de run vit sous `.scratch/<feature>/`, que
le scope-guard laisse comme bookkeeping, et que [12] a montré qu'une session peut
l'effacer. `human-loop.sh` prend les deux verrous et ne les redemande **jamais**,
alors que c'est le point d'entrée qui met un `claude` **non jugé** dans l'arbre
principal — donc celui où perdre le verrou coûte le plus cher.

**Blocked by:** None

**Write-surface:** `.claude/human-loop.sh`, `.claude/lib/state.sh`,
`test/human-loop.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** resolved

**Tags:** securite, frontiere-de-confiance

- [x] **Le drain repose les deux questions**, séparément, à chaque ticket du
      puits — pour la raison que `loop.sh` écrit à côté des siennes : les deux
      réponses peuvent différer, `.git/` n'étant hors de portée que d'un
      `git add -A`, d'un `git clean` et d'un `rm -rf .scratch`, pas d'une session
      qui efface le répertoire. *`human_loop__locks_are_ours`, en tête du menu de
      `human_loop__drain_one` : une fois par ticket, et une fois de plus avant
      chaque décision prise dessus. Le placement a changé en cours de livraison —
      voir les commentaires, c'est la trouvaille de ce ticket.*
- [x] **Il s'arrête plutôt que de continuer**, et le code de sortie choisi est
      écrit dans l'en-tête de `human-loop.sh` avec les cinq autres. Continuer,
      c'est ouvrir un second `claude` non jugé dans un arbre qu'un run peut
      maintenant réclamer. *`4`, le code que `loop.sh` donne à un garde qui
      arrête un run ; délibérément pas `3`, qu'un humain qui quitte laisse déjà.*
- [x] **`run_lock_is_ours` et `tree_lock_is_ours` gagnent un second appelant** :
      vérifier qu'elles n'ont pas besoin d'être renommées (une `__` avec deux
      appelants est publique — `test/layering.bats`), et que le commentaire de
      `state.sh` cesse de dire une chose fausse pour la moitié du pack. *Aucun
      renommage : les deux noms sont déjà publics (pas de `__`), et
      `test/layering.bats` refuse exactement l'inverse — un appel dans les
      internes d'un voisin. Les trois commentaires de `state.sh` qui parlaient
      d'« every iteration » nomment maintenant les deux appelants.*
- [x] **Une mutation par garantie livrée**, témoin appairé vérifié à la main.
      *Cinq entrées `57 …`, toutes `ok`.*

## Ce que la passe du 31/08 a mesuré

Sondes conservées :
`.scratch/ralph-pack/sondes/passe-31-08/p4-le-verrou-que-le-drain-ne-revérifie-jamais.bats`.
Deux tickets dans le puits : la session routée du premier efface les deux verrous,
celle du second enregistre ce qu'il en reste **pendant que le drain tourne
encore**.

- **P4a** — la seconde session routée voit :

      run lock  : ABSENT
      tree lock : ABSENT

  Le drain continue, ouvre le second `claude` non jugé dans l'arbre principal,
  parcourt le puits jusqu'au bout et sort normalement. **Aucune ligne ne le
  nomme.** `state_locks_release` à la sortie est un no-op silencieux.
- **P4b, témoin appairé** — même paire de sessions, sans l'effacement :
  `run lock : présent`, `tree lock : présent`.
- **P4c — le même effacement sur le chemin AFK**, pour la comparaison :

      ralph: the run lock is gone or not ours any more after 1 iterations —
      stopping rather than grinding beside another run

Les deux points d'entrée donnent donc des réponses opposées au même événement, et
celui qui se tait est celui qui met une session non jugée dans l'arbre de
l'opérateur.

## Ce que ça rend faux ailleurs

`.claude/lib/state.sh` écrit, pour justifier de laisser une course ouverte dans
`state_guard_take` : « Two of the three callers are covered downstream — the run
and tree locks are **re-checked for ownership on every iteration**
(`*_is_ours`) ». Cette phrase est vraie de `loop.sh` et fausse de
`human-loop.sh` depuis [16]. C'est la question 4 de CLAUDE.md dans sa forme la
plus simple : une garantie écrite pour un appelant, et un second appelant arrivé
sans elle.

## Pièges connus, pour celui qui livre

- **Un verrou effacé n'est pas un verrou volé.** `state_guard_take` récupère le
  garde d'un propriétaire mort : la question à poser est bien « est-ce encore le
  nôtre » (`$$` contre `pid`), pas « existe-t-il ».
- **`$$` dans une itération du pilote est le pid du pilote** ([47]), et le drain
  n'a pas de sous-shell par ticket — mais `router_sink` et les substitutions de
  commande en ont : ne pas poser la question depuis l'un d'eux.
- **La sonde n'a pas besoin de concurrence** : deux tickets et deux sessions
  routées suffisent, la seconde observant pendant que le drain vit. Un `&` nu ne
  met rien en concurrence (piège de la passe du 27/08).
- **Ce ticket est le moins cher des trois ouverts par la passe** et il est délié
  ([55] et [56] le nomment en `Blocked by:`) : les trois écrivent
  `.claude/human-loop.sh`, et deux tickets dessinés sur un fichier sont un
  `decision` que le pack sait produire tout seul.

## Comments

- **LIVRÉ le 31/08/2026.** `human_loop__locks_are_ours` et
  `human_loop__stop_lost_lock` dans `.claude/human-loop.sh`, un seul appel en tête
  du menu de `human_loop__drain_one`, le code `4` documenté dans l'en-tête du
  fichier et dans celui de `drain_one`. Trois tests dans `test/human-loop.bats`
  (les deux pertes, plus le témoin appairé), cinq entrées de mutation, la ligne
  « Un drainage et un run AFK ne se marchent pas dessus » du tableau réécrite.

- **LA TROUVAILLE : la frontière de ticket que l'AC demande est le PLUS PETIT des
  deux moments, et elle est indémontrable si on la livre seule.** Le premier jet
  posait la question dans `human_loop_main`, avant chaque ticket, exactement comme
  l'AC l'écrit. Les trois tests passaient, les quatre mutations rendaient `ok`. Puis
  la sonde « run réel » de la question 3 : *que fait un humain qui répond `o` deux
  fois ?* Le menu est ré-offert après une session — c'est écrit dans le commentaire
  de `drain_one` depuis [16] — donc une session routée qui efface un verrou revient
  à un prompt qui propose `o`, et le second `claude` non jugé s'ouvre **sur le même
  ticket**, sans jamais franchir la frontière que le ticket venait de garder. Le
  contrôle demandé ratait le cas le plus court.

- **Et les deux emplacements ne peuvent pas coexister.** Une fois la question posée
  en tête du menu, elle couvre aussi la frontière de ticket : la première passe de
  la boucle *est* cette frontière. Un second contrôle dans `human_loop_main` serait
  du code mort derrière celui-là — rien ne s'exécute entre la dernière passe du menu
  d'un ticket et la première du suivant, donc **aucune mutation ne peut les
  distinguer**, et une garantie qu'aucune mutation ne peut retirer est une phrase et
  pas un contrôle (règle de [47]). Le contrôle de `human_loop_main` a donc été
  retiré, pas gardé « au cas où ». Ce que ça coûte, écrit plutôt que caché : le
  dossier du ticket est imprimé avant le refus, parce que `router_dossier` précède
  la boucle. C'est une lecture d'`issues/`, elle ne coûte rien, et un drain qui
  montre le ticket puis dit pourquoi il s'arrête n'est pas moins honnête.

- **La cinquième mutation est celle qui vaut le ticket.**
  `57 the drain asks at the ticket and not after each decision` déplace l'appel
  d'une ligne — hors de la boucle du menu, juste avant elle. Les deux questions
  survivent, les deux messages survivent, le code de sortie survit, et le drain
  ouvre quand même le second `claude`. C'est le seul contrôle qui distingue le
  ticket livré du ticket écrit.

- **Ce qui a décidé la forme des tests : le scénario à deux tickets ne mesure plus
  la même chose.** Avec le contrôle en tête du menu, la paire de tickets de la sonde
  P4a s'arrête sur le **premier** (`stopped with 20-first`), et pas sur le second :
  le refus arrive au retour de la session, pas à la frontière. Les deux tests
  gardent quand même les deux tickets — le second sert à asserter qu'il n'a jamais
  été offert (`dossier_line 21-second` vide), ce qui est la moitié « le drain
  s'arrête » de la garantie. Le témoin appairé consomme les mêmes réponses (`o o n
  o n`) et compte **trois** sessions : deux sur le premier ticket, une sur le
  second. Un témoin qui n'aurait ouvert qu'une session par ticket aurait été vert
  contre le placement.

- **Les deux questions restent deux entrées de mutation, pour la raison qui les
  sépare dans le code.** Le test du verrou d'arbre efface `.git/ralph.tree.lock` et
  laisse le verrou de run intact ; celui du verrou de run fait l'inverse. Une seule
  question pour les deux verrous serait verte contre la moitié des façons d'en
  perdre un — c'est ce que `refute_output_contains "the run lock is gone"` mesure
  dans le test de l'arbre.

- **Les pièges annoncés en tête de ticket, vérifiés.** `$$` : la question est posée
  depuis `human_loop__drain_one`, appelée par `human_loop_main` par
  `human_loop__drain_one "$id" || rc=$?` — aucune substitution de commande, aucun
  pipe, et la boucle du puits est nourrie par un heredoc et pas par un pipe, donc
  rien n'est un sous-shell et l'`exit` est bien celui du processus. Un verrou effacé
  n'est pas un verrou volé : `*_is_ours` compare `$$` au propriétaire enregistré, ce
  qui répond « non » dans les deux cas — c'est déjà la forme que `test/state.bats`
  couvre pour `loop.sh`.

- **Ce qui reste ouvert, et c'est écrit au tableau.** La fenêtre à l'*intérieur*
  d'une session : une session routée qui efface un verrou continue d'écrire jusqu'à
  ce qu'elle sorte, et le drain ne l'interrompt pas. C'est la même fenêtre que
  `loop.sh` a à l'intérieur d'une itération, pour la même raison — il n'y a pas de
  troisième processus pour surveiller le deuxième — et la refermer ne se fait pas
  par un contrôle de plus dans cette boucle.

- **Ce que [55] et [56] héritent.** Les deux écrivent le même fichier et le
  nomment en `Blocked by:`. Ils héritent d'un code de sortie de plus (`4`), d'un
  `human_loop__drain_one` qui rend maintenant **quatre** codes et dont le `case` de
  `human_loop_main` doit continuer à traiter le `4` avant le `*)` — une nouvelle
  branche ajoutée à ce `case` sans regarder ce que `4` veut dire compterait un
  verrou perdu comme un ticket laissé en place. Et ils héritent de la règle que ce
  ticket a mesurée : dans cette boucle, **le menu est le vrai point de convergence**,
  pas la frontière de ticket. Un contrôle que [55] ou [56] poserait dans
  `human_loop_main` aurait le même angle mort que celui-ci avait au premier jet.
