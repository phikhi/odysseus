# 09 — Auto-chaînage : successeur one-shot + scheduler

**What to build:** Le franchissement d'un mur hebdomadaire sans faire dormir un process des jours : un **successeur one-shot** programmé au reset de la fenêtre bloquante, via une chaîne de scheduler auto-détectée et ordonnée par survie au reboot, avec repli humain si aucun scheduler.

**Blocked by:** 08

**Write-surface:** `.claude/lib/scheduler.sh`, `test/scheduler.bats`

**Status:** resolved

- [x] Un mur hebdo programme un successeur one-shot au `resets_at` de la fenêtre bloquante — **jamais `+7j`** : le plafond est porté par la fenêtre (`five_hour` 5 h, `seven_day*` 7 j), pas par une soustraction.
- [x] La chaîne de scheduler est auto-détectée et ordonnée par survie au reboot (`at` avant `systemd-run` transient ; variantes par plateforme Linux/macOS) ; le skill cloud `schedule` n'est **pas** dans la chaîne locale, et l'écrire dans `SCHEDULER` est refusé au préflight avec sa raison.
- [x] Sans scheduler disponible, la boucle sort proprement en `pause-hebdo` (repli humain) — même `exit 6`, ligne de journal `weekly-pause`.
- [x] Anti-double-run : marqueur singleton à côté du verrou d'arbre, et le verrou de run comme filet — asserté en **exécutant** la commande mise en file contre un verrou tenu.
- [x] Un fake `at` reçoit exactement une programmation, avec la bonne échéance (vérifié via le seam), arrondie à la minute supérieure.

## Comments

- **Contrainte posée par la revue de [01]–[04] : les codes de sortie de `loop.sh` ont changé.** `0` signifie désormais « ce run a drainé la frontière » et **`5` « la frontière était déjà vide au démarrage »** (mauvais `FEATURE`, tout en triage, tracker illisible). Un successeur one-shot qui se réveille doit traiter `5` comme « plus rien à faire », pas comme un échec — et surtout ne pas se re-programmer en boucle dessus. `2` couvre maintenant aussi une config qui viderait le gate de son sens (`TEST_CMD`/`TYPECHECK_CMD` vides), ce qui est un cas où re-programmer un successeur ne servirait à rien : il refusera pareil.

- **Contrainte posée par [08], livré le 05/08/2026 : le mur hebdo existe déjà, il sort en `6`, et il t'attend.** `loop.sh` a un sixième code de sortie : `6`, « le budget d'usage bloque ce run ». Il tombe dans deux cas et deux seulement — une fenêtre `seven_day` (ou `seven_day_opus` quand `MODEL` nomme un opus) au-dessus de `THRESH_WEEK`, et une fenêtre de session dont le reset n'est pas un instant que le run peut attendre (`BUDGET_MAX_PAUSE`, ou un reset illisible). `6` et pas `4` est délibéré et c'est pour ce ticket : tous les autres arrêts sont des décisions que le run a prises sur lui-même, celui-ci est un mur qui se lève tout seul à un instant connu. Trois choses à savoir en écrivant le successeur :
  - **L'instant est déjà calculé** : `RALPH_BUDGET_RESET` (epoch) et `RALPH_BUDGET_WINDOW` sont posés par `budget_check` dans le shell de la boucle au moment où elle décide de s'arrêter, et la ligne de `run.log` est `budget-wall`. Il n'y a pas de second appel à l'endpoint à faire.
  - **Ne jamais programmer sur un reset que rien n'a mesuré.** Le cas « reset illisible » sort avec le *même* code 6, et son `RALPH_BUDGET_RESET` est vide ou hors du cap. Un successeur qui lit ce champ sans le vérifier programmerait à l'epoch 0 — c'est la forme exacte du repli qui se désarme tout seul ([27]). Le message de la boucle distingue déjà les deux ; le champ, lui, demande une garde.
  - **La source compte.** `RALPH_BUDGET_SOURCE` vaut `endpoint` ou `stream`. `stream` veut dire que l'instant vient du `rate_limit_event` d'une session, c'est-à-dire d'un fichier que la session jugée peut écrire ([08] borne ce que ça coûte à une pause ; un successeur programmé des jours plus loin sur la même valeur ne serait plus borné du tout). Programmer sur `stream` demande au minimum le même plafond que `BUDGET_MAX_PAUSE`, et l'AC « jamais +7j » ne suffit pas à le tenir.

- **Contrainte posée par [13], livré le 06/08/2026 : le successeur est armé par le pilote, jamais par une itération.** `loop_main` est devenu un pilote qui forke N itérations et les draine avant de sortir, donc l'instant d'armement est *après* la dernière itération en vol — et pas au moment où le mur budget est vu. Les deux sorties concernées (`exit 6`) passent désormais par un `stop_code` qui draine ; un `exit` immédiat laisserait un `claude` par slot en train de brûler du quota que le successeur est censé économiser ([28]).

- **Contrainte posée par [14], livré le 24/08/2026 : la préemption de la quatrième couche ne traverse pas un redémarrage.** Ce qu'une session reçoit comme leçons est servi depuis une **copie que le pilote prend au démarrage du run**, dans `$TMPDIR`, avant qu'aucune session n'existe — ce qui fait qu'une réécriture de `LEARNINGS.md` en cours de run n'atteint aucun prompt de ce run. Un successeur est un run neuf : il relit sa ligne de base **depuis le fichier**, dans l'arbre principal, que rien n'a jugé entre-temps. Donc la garantie « ce qu'un prompt reçoit vient de cette boucle » vaut *par run* et pas d'un run à l'autre. Ce ticket est celui qui enchaîne les runs, donc c'est ici que la question se pose : soit le successeur est traité comme un run neuf et la limite est assumée telle qu'écrite dans `docs/frontiere-de-confiance.md`, soit l'auto-chaînage transmet quelque chose — et alors ce quelque chose devient un canal à sceller comme les autres.

  Le canal de reprise entre deux tentatives est, lui, franchement **par run** : il meurt avec le pilote et un ticket retryé après un redémarrage repart sans rien savoir de la tentative d'avant.

- **Contrainte posée par la passe transversale du 26/08/2026 : le témoin de [15] est par run
  lui aussi, et il perd plus que la préemption de [14].** Le paragraphe ci-dessus dit que la
  copie de `LEARNINGS.md` ne traverse pas un redémarrage. Le témoin de capacités a la même
  forme par run — ligne de base au démarrage, comparaison à chaque itération — mais avec une
  différence qui compte ici : sur un run qui **s'arrête sur une itération retryée** (mur
  budget compris, donc `exit 6`, donc exactement le cas que ce ticket enchaîne), la dérive
  détectée n'atteint ni le reçu ni `run.log`, et le successeur la reprend comme ligne de
  base. L'événement n'est donc pas différé, il est perdu. Le canal est le sujet de [46] ; ce
  qui appartient à ce ticket est la même question que pour [14] : soit le successeur est un
  run neuf et la limite est assumée telle qu'écrite, soit l'auto-chaînage transmet une ligne
  de base — et alors elle devient un canal à sceller comme les autres. Sondes :
  `.scratch/ralph-pack/sondes/passe-26-08/p2.bats` P2c et `p3.bats` P3b.

- **[46], livré le 29/08/2026 : la moitié « l'événement est perdu » est refermée, la
  question qui appartient à ce ticket ne l'est pas.** Le paragraphe ci-dessus disait
  que sur un `exit 6` — un mur budget, donc exactement le cas que ce ticket enchaîne
  — la dérive de capacités détectée n'atteignait ni le reçu ni `run.log`, et que le
  successeur la reprenait comme ligne de base : l'événement était perdu, pas différé.
  Le canal est réparé : `capability_drift` rend ses lignes, l'itération les passe au
  pilote par son slot, et `loop__finish` écrit une ligne `run.log` par surface avec
  **la surface en sujet**. Un humain qui lit le journal du run mort le matin voit
  donc ce qui a bougé.

  Ce qui reste à trancher **ici** est inchangé et c'est la même question que pour
  [14] : le témoin est toujours **par run**, donc le successeur reprend l'état
  courant comme sa propre ligne de base et ne redira rien de ce que le run précédent
  a vu. Soit le successeur est un run neuf et la limite est assumée telle qu'écrite
  dans `docs/frontiere-de-confiance.md`, soit l'auto-chaînage transmet une ligne de
  base — et alors elle devient un canal à sceller comme les autres, dans un fichier
  qu'aucune session ne peut écrire ni nommer ([40] : ce n'est pas « hors de l'arbre »
  qui protège un secret, c'est « qui en connaît le nom »).

- **[46] ajoute une contrainte au successeur lui-même.** Un run neuf reprend la
  configuration git courante comme frontière épinglée (`gate_frontier_common`), donc
  une clé que la session d'un run précédent a laissée dans `<arbre>/.git/config` ou
  dans `~/.gitconfig` et que ce run-là n'a pas pu remettre devient la **ligne de
  base** du successeur, en silence. C'est le même résidu que [30] laisse pour un run
  tué, et il est écrit au tableau ; ce qui est neuf est qu'un successeur *programmé*
  le franchit à coup sûr, là où un run relancé à la main est relancé par un humain
  qui a lu le reçu. À décider ici, avec le reste : ce que le successeur relit et ce
  qu'il hérite.

## Livraison, le 29/08/2026

`.claude/lib/scheduler.sh` (neuf) et `test/scheduler.bats` (neuf, 30 tests), plus
les écarts de write-surface listés plus bas.

### La décision que [14], [15] et [46] avaient laissée ici

**Un successeur est un run neuf et n'hérite rien.** La ligne mise en file porte
`PATH`, `RALPH_CONFIG` sous le nom qu'il a réellement, `RALPH_PROJECT_ROOT` s'il
y en a un, le chemin de `loop.sh`, et une redirection. Rien d'autre.

L'autre sortie — transmettre une ligne de base — a été refusée sur l'argument de
[40] et pas sur l'effort : transmettre veut dire un fichier, et **la ligne de
commande d'un job en file est lisible par tout ce qui tourne sous cet
utilisateur** (`at -c` l'imprime). Le nom de ce fichier serait donc un nom qu'une
session peut apprendre, c'est-à-dire exactement le canal que [40] a fermé. La
limite est assumée telle qu'écrite dans `docs/frontiere-de-confiance.md` : ce
qu'un run a vu et n'a pas eu le temps de dire n'est redit par personne.

**Un seul cas est refermé plutôt qu'assumé, et c'est celui que [46] a nommé.**
Quand le run laisse une source de configuration ailleurs qu'il ne l'a trouvée,
`gate_frontier_residue` la nomme et **rien n'est armé** — repli humain. Le
raisonnement : un run neuf épingle ce qu'il trouve, donc le successeur adopterait
le résidu comme celui du projet et ferait exécuter par git, dans l'arbre de
process du pilote, à chaque rafraîchissement d'index, un programme qu'une session
a choisi. Et l'humain que ce successeur remplace est précisément celui qui aurait
lu le reçu. Prévenir sur la ligne d'armement aurait été moins cher et faux : la
ligne serait lue au matin, après la nuit.

### Ce qui a été construit

- **`scheduler_candidates` / `scheduler_chain`** : la liste ordonnée par
  plateforme (pure, la plateforme est un **argument** avec un défaut — l'ordre
  *est* la garantie, et une garantie testée sur la machine qui fait tourner la
  suite est testée sur une des deux plateformes promises), puis le filtre par
  `command -v`. `at` avant `systemd-run` parce que l'un spoole sur disque et
  l'autre vit dans `/run` (tmpfs). Une seule entrée sur macOS.
- **`scheduler_deadline`** : quatre gardes, et chacun est une façon dont le reset
  n'est pas un instant que quelque chose a mesuré — lisible, futur, dans le
  plafond de **sa propre fenêtre** (`five_hour` 5 h, `seven_day*` 7 j, un nom
  inconnu refusé), et le plafond `BUDGET_MAX_PAUSE` en plus quand la source est
  `stream`. « Jamais +7 j » est donc un plafond que la fenêtre porte, pas un
  calcul qu'on s'interdit. Répond par variables (`RALPH_SUCCESSOR_AT`,
  `RALPH_SUCCESSOR_WHY`) comme `budget_check`, la refus et l'instant étant deux
  réponses à une question.
- **`scheduler_arm`** : `WEEKLY_RESUME` → résidu → instant → singleton → chaîne →
  soumission. Imprime les lignes du matin sur stdout, rend non-zéro quand rien
  n'a été armé (ce qui est le repli, pas une erreur).
- **`scheduler_caveat`** : ce que le mécanisme choisi *ne peut pas* promettre,
  sur la ligne d'à côté. `at` répond de la file et jamais du job ; `atrun` est
  livré désactivé sur macOS ; un timer transient meurt au reboot et un `--user`
  au logout sans linger.
- **Le marqueur singleton** `<gitdir>/ralph.successor`, à côté du verrou d'arbre
  et pour sa raison ([22]) : hors de portée d'un `git add -A`, d'un `git clean`
  et d'un `rm -rf .scratch`, et déjà par arbre de travail, ce qui est la
  granularité d'un successeur. Rien ne l'efface : un successeur qui se réveille
  trouve son propre marqueur dans le passé et écrit par-dessus.
- **`gate_frontier_residue`** (gate.sh) : la différence symétrique de [46] un
  niveau au-dessus — contre le témoin du **run** et sur les sources partagées
  seulement. La moitié `tree` en est exclue exprès : un `.gitignore` qu'une
  session écrit est du travail de projet, et le run suivant est *censé* le
  recevoir.
- **Le pilote** : `scheduler_preflight` dans `loop_preflight`, et
  `loop__arm_successor` en queue de `loop_main`, **après la boucle** (donc après
  drainage : `stop_code=6` déclenche un drain) et **avant** que le témoin de
  frontière du run ne soit détruit, puisque le résidu se lit dessus.

### Décisions à connaître avant de rouvrir ce code

- **Le code de sortie reste `6`, armé ou non.** Un septième code se serait
  propagé dans l'en-tête de `loop.sh`, dans [08], et dans tout consommateur.
  Ce que le code dit est *pourquoi ce run s'est arrêté* ; ce qui a été armé est
  une ligne de journal — `successor-armed` contre `weekly-pause` — parce qu'un
  lecteur qui doit agir sur la différence lit le journal et pas un statut.
- **On arme sur les *deux* causes d'`exit 6`, et ce sont les gardes qui les
  séparent.** Le mur hebdo passe ; la fenêtre de session dont le reset est
  illisible est refusée par le garde « lisible ». Une fenêtre de session dont le
  reset est *lisible mais plus loin que `BUDGET_MAX_PAUSE`* est armée, et c'est
  voulu : c'est exactement le cas qu'un successeur résout mieux qu'un arrêt.
- **Pas de sonde `atrun` sur macOS.** Elle demande `launchctl`, elle n'est pas
  testable à travers le seam du harnais, et un contrôle qui répondrait
  « activé » sur une machine où le démon vient d'être arrêté serait le faux vert
  que ce dépôt refuse. À la place, la phrase de `scheduler_caveat`, avec sa
  variante macOS. Conséquence : sur un mac sans `atrun`, `at` prend la
  soumission, rien ne tourne, et la seule chose qui le dit est cette phrase.
- **Ni LaunchAgent auto-désinstallant ni crontab auto-effaçant**, tous deux dans
  la recherche : ce sont des patterns communautaires, l'un installe un `.plist`
  dans le `~/Library` d'un humain et l'autre a une course d'édition de crontab
  que rien ici ne sérialise. Le repli humain est préférable à un mécanisme dont
  le mode de panne est « la ligne reste et se rejoue dans un an ».
- **`at -t` prend des minutes entières, et l'arrondi est vers le haut.** Vers le
  bas réveille le run *avant* que le mur ne se lève : il retrouve la même fenêtre,
  s'arrête, et réarme. Le test le fixe à 30 s après la minute pleine — pris
  sur l'horloge, l'arrondi haut et bas coïncident une fois sur soixante et la
  mutation rapporterait `ok` cinquante-neuf fois puis mentirait.

### Écarts de write-surface (assumés, listés)

La write-surface déclarée est `.claude/lib/scheduler.sh` + `test/scheduler.bats`.
Ont aussi été touchés, aucun de façon évitable :

- `.claude/loop.sh` — le préflight, l'appel après drainage, la ligne du mur (qui
  disait « belongs to [09] »), et l'en-tête des codes de sortie. Rien de ce
  ticket n'est atteignable sans un appelant.
- `.claude/lib/gate.sh` — `gate_frontier_residue`, ~10 lignes, ajoutées **après**
  `gate__frontier_share` : une fonction neuve placée plus haut aurait pu rendre
  ambiguë une ancre de mutation existante ([46]).
- `.claude/ralph.config.sh.example` — commentaires de `SCHEDULER` et
  `WEEKLY_RESUME` seulement, les valeurs étaient déjà là et sont inchangées.
- `test/helpers/harness.bash` — `at_call_count`, à côté de `at_calls`/`at_exit` :
  zéro est la réponse dont ce fichier a le plus besoin, et un enregistrement vide
  se lit comme un fichier absent.
- `test/budget.bats` — le test du mur hebdo assertait `[09]` dans la sortie ;
  il asserte maintenant que la passation a eu lieu (`at_call_count` = 1).
- `test/mutate.sh` — 30 entrées.
- `docs/frontiere-de-confiance.md` — deux lignes neuves ; `CONTEXT.md` — les deux
  entrées d'auto-chaînage corrigées (elles décrivaient une chaîne à cinq maillons
  qui n'a jamais été livrée) et une entrée `Repli hebdo`.

### Pièges rencontrés

- **Un test qui fait échouer `at` fait tomber la chaîne sur `systemd-run`**, et
  sur une machine Linux qui en a un, la suite armerait un vrai timer transient.
  Le test qui met `at_exit 1` épingle donc `SCHEDULER=at`. Ce piège vaut pour
  toute entrée future qui casse une soumission.
- **Le filtre de chaîne ne se teste pas en comptant sur l'absence de systemd** :
  la suite tourne sur les deux plateformes. Il se teste en retirant `at` du
  `PATH` dans un sous-shell.
- **`'' | *[!0-9]*)` apparaît deux fois** dans `scheduler.sh` (le garde de
  l'instant et celui du marqueur). L'entrée de mutation ancre sur la ligne
  suivante, sans quoi elle aurait édité la première par hasard — la forme exacte
  des deux ancres non uniques que [29] avait fabriquées.
- **La sonde de résidu bout en bout ne doit pas armer `core.fsmonitor` pour de
  vrai** : git l'exécuterait à chaque rafraîchissement d'index de la suite.
  `help.browser` est sur la liste dérivée de [46] et n'est exécuté par rien ici.
  Elle a aussi besoin de `USAGE_CACHE_TTL=0` : le cache de 180 s de [08] ne fait
  poser qu'une seule question par run, donc le second corps de `usage_respond`
  n'aurait jamais été servi et le mur ne se serait jamais levé.
- **`assert_output_contains` matche littéralement** (`case` avec `"$1"` cité),
  donc l'ancienne assertion `"[09]"` de `budget.bats` continuait de passer avec
  le nouveau message : elle était devenue vraie pour une autre raison. Remplacée.

### Ce que ce ticket laisse aux autres

- **[08]** : `RALPH_BUDGET_WINDOW/RESET/SOURCE` sont désormais lus **en queue de
  `loop_main`**, longtemps après que `budget_check` les a posés. Ce sont des
  variables du shell du pilote ; un changement qui déplacerait `budget_check`
  dans un sous-shell ou une itération casserait l'armement en silence.
- **[13] / [28]** : l'armement est en queue de `loop_main`, donc après drainage.
  Un `exit` anticipé sur `stop_code=6` armerait pendant qu'un `claude` par slot
  brûle encore le quota que le successeur existe pour économiser. Aucune mutation
  ne peut rendre ce placement rouge — ce qui le porte est la structure
  (`stop_code` déclenche un drain) plus l'assertion « exactement un ».
- **[16]** : la boucle humaine est l'autre point d'entrée et ne doit **jamais**
  armer — un successeur programmé pendant qu'un humain draine remettrait deux
  runs sur un arbre. `SCHEDULER` et `WEEKLY_RESUME` appartiennent au chemin AFK.
- **[19]** : deux objets neufs à balayer/provisionner — `successor.log` dans
  `.scratch/<feature>/` (à couvrir par le `.gitignore` que [19] écrit, comme
  `run.log`) et le marqueur `<gitdir>/ralph.successor`, qu'un successeur qui ne
  s'est jamais réveillé laisse derrière lui. Et la confirmation forcée de
  l'installeur doit écrire `SCHEDULER` / `WEEKLY_RESUME` : les deux clés sont
  refusées au préflight si elles sont vides ou hors du jeu.
- **[30] / [46]** : `gate_frontier_residue` est un nouveau lecteur du manifeste
  du témoin de run. Un ticket qui change la forme de ce manifeste doit le garder.
- **[10] / [45]** : un mur budget ne produit aucun reçu — il n'y a pas
  d'itération à raconter — donc ce que ce ticket écrit ne vit que dans `run.log`
  et sur stdout. Si un jour un reçu de *run* existe, l'armement y appartient.
- **Tempête d'armement** : un successeur qui se réveille et retrouve le mur
  réarme, mais seulement si l'endpoint donne un reset **futur** ; un reset déjà
  passé est refusé, donc la chaîne se termine. Un endpoint qui répondrait chaque
  fois « une semaine de plus » armerait chaque semaine, ce qui est le
  comportement voulu et pas une boucle.

### Chiffres

- `bash test/run.sh` = **577 tests, 0 failures, 6 skips** opt-in (547 avant, +30,
  tous dans `test/scheduler.bats`).
- `bash test/mutate.sh` = **556 mutations, 0 `not ok`** (526 avant, +30) — aucun
  nom toléré, canari compris. Le passage à blanc (`-n`) rendait déjà 556/0, donc
  **aucune ancre n'a dérivé**, y compris celles de [46], [41], [44] et [30] dans
  `gate.sh` et `loop.sh`, que ce ticket a rouverts. Ce qui l'explique : la
  fonction neuve de `gate.sh` a été posée après `gate__frontier_share` et les
  ajouts de `loop.sh` sont un appel de préflight, une fonction neuve et un `if`
  en queue de `loop_main` — aucune ligne porteuse d'une garantie existante n'a
  bougé.
- Un seul `not ok` au premier passage, et il faut le dire parce qu'il a la forme
  d'un piège connu : `DRIFTED 09 a second successor is armed over the first`,
  « no test matches -f … ». Le filtre citait une phrase de l'**assertion**
  (`for this working tree`) et pas du **nom** du test (`for this tree`). C'est le
  cas que l'en-tête de `mutate.sh` demande d'interroger en premier — « aucun test
  n'a tourné » avant « aucun test n'a rougi » — sans quoi il se serait lu comme un
  test creux. Filtre corrigé, entrée rejouée `ok`.

## Note de la passe transversale du 30/08/2026

Les cinq angles que ce ticket avait ouverts ont été sondés
(`.scratch/ralph-pack/sondes/passe-30-08/`). **Quatre trouvailles, deux tickets,
et une hypothèse de l'angle (a) à corriger.**

- **(a) le kill entre le mur et la queue — l'hypothèse était fausse.** `run.log`
  n'est pas muet : il porte `budget-wall` **seul**, ce qui distingue bien les
  trois fins (`budget-wall successor-armed` · `budget-wall weekly-pause` ·
  `budget-wall`). Ce qui manque est que ce troisième état soit écrit comme un
  état, et que la phrase qui promet l'armement ne soit pas un `loop_log` mourant
  avec le process. Repris par [53].
- **(b) le marqueur — pire que « pas balayé ».** Une session l'atteint depuis une
  itération **verte** (`git rev-parse --git-common-dir`), et comme rien ne
  l'efface et que `scheduler_armed_at` ne compare que son premier champ à `now`,
  l'instant qu'elle écrit décide *combien de nuits* l'armement est éteint — deux
  mesurées, marqueur intact. Le tableau disait « la nuit » au singulier ; corrigé.
  Et `run.log` enregistre `weekly-pause`, le mot exact d'un projet ayant choisi
  `WEEKLY_RESUME=human` : la cause n'atteint aucun document durable. Repris par
  [53].
- **(c) `successor.log` — le canal est choisi par la session.** La redirection est
  la première chose que le shell du job fait, avant `loop.sh`. Répertoire → le job
  sort en 1 et **`loop.sh` ne démarre jamais** ; lien vers `.claude/settings.json`
  → le successeur **écrit dans le chemin scellé** (153 → 1240 octets), depuis une
  itération verte, bout en bout. Repris par [53].
- **(d) deux features d'un arbre — angle disculpé.** Le verrou d'arbre refuse le
  second run avant que la question du marqueur se pose. Séquentiellement, la
  première feature prend l'unique créneau de l'arbre : voulu, écrit, pas réparé.
- **(e) le `PATH` figé — la plus grosse, et elle dépasse ce ticket.** Une session
  qui pose un `git` dans un répertoire du `PATH` n'atteint pas le run courant
  (bash avait hashé `git`) mais **204 appels du run suivant**, dont ceux dont
  vivent le verrou d'arbre, la frontière de visibilité et l'arbre jugé. Ce ticket
  y ajoute que le `PATH` est **figé dans la file** et rejoue des jours plus tard
  sans humain. Ticket [52], qui est le second cas de la phrase que [46] avait
  écrite (« ce que le pack exécute ensuite ») et qui n'avait pas de propriétaire.

Ce que cette passe formule et qu'il faut garder : **ce ticket a demandé avec soin
ce qu'un successeur hérite comme *ligne de base*, jamais ce qu'il hérite comme
*contexte d'exécution*** — quel programme (`PATH`), quel travail (`FEATURE`, que
la ligne ne porte pas), quel canal (`successor.log`), et si oui ou non (le
marqueur).
