# 111 — Ce que lisent le juge du rétro et celui du gate de valeur est un fichier nommé

**What to build:** Que ce que le pack **donne à lire** au juge du rétro et à celui du gate de valeur — leur prompt, et pour le gate de valeur les deux transcriptions que le prompt cite — ne soit plus un fichier nommé de `$TMPDIR` entre son écriture et sa lecture, ou que chaque étage dise ce que sa réponse vaut. C'est la moitié **entrée** de ce que [97] a fermé côté **sortie** : [97] garantit que le verdict lu est celui que le juge a écrit, pas que la question lue est celle que le pack a posée.

**Blocked by:** None

**Write-surface:** `.claude/lib/retro.sh`, `.claude/lib/playthrough.sh`, `.claude/lib/session.sh`, `.claude/lib/lenses.sh`, `.claude/lib/proc.sh`, `test/retro.bats`, `test/playthrough.bats`, `test/canary.bats`, `test/gate.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** needs-triage

- [ ] Le **prompt du rétro** (`$RALPH_RETRO_STATE/session.XXXXXX/prompt`, écrit par `retro__prompt >"$dir/prompt"` puis donné à `claude` sur stdin par `session_spawn`) n'est plus lisible ni écrivable par un process extérieur à la descendance du pilote entre son écriture et sa lecture. Sa sortie est la plus durable du pack : `LEARNINGS.md`, que lit toute session suivante.
- [ ] Le **prompt du gate de valeur** (`ralph-playthrough.XXXXXX/prompt`), même exigence : sa sortie ferme une feature, écrit `docs/playthroughs/` et ouvre (ou n'ouvre pas) le ticket du trou.
- [ ] Les **deux transcriptions** du gate de valeur (`run.out`, `visual.out`, lues par `playthrough__transcript` dans le prompt et recopiées dans le document) sont tranchées : fermées par le même mécanisme, ou l'aveu au tableau. Elles sont la « moitié matérielle » du document — *« this loop ran them, no model did »* — et un survivant qui y écrit fait mentir cette phrase.
- [ ] Mesuré par une sonde sur une commande de projet qui **écrit** (le montage de `../sondes/ticket-97/q1` utilise `stub-cmd`, dont les transcriptions sont vides et n'ont pas été atteintes).
- [ ] Témoin appairé et survivant réel sur les deux juges, une entrée de `test/mutate.sh` par garantie, la ligne du tableau « Ce qu'un flux de session dit » (point 5) et les lignes « Une leçon injectée… » et « Le verdict du playthrough… » relues.
- [ ] Si la réparation prend des **descripteurs**, le recensement est mis à jour au-dessus de `LOOP_SLOT_FD` dans `loop.sh`, le seul endroit où il est écrit depuis [97]. Contrainte connue : dans une branche de lentille, 3 et 7 sont pris par le flux pendant la session et 6 par le prompt ; dans l'itération (où tourne le rétro) 6 et 7 sont libres hors de la session, 3 et 7 pris pendant ; au pilote (où tourne le gate de valeur), 11–254 sont les lecteurs des itérations.

## Comments

- **Ouvert le 28/10/2026 en livrant [97]**, qui ne l'a pas fermé : décision de Philippe (« ticket [111] », plutôt qu'élargir [97]). Trouvé en posant la question de la frontière de confiance avant d'écrire : le flux fermé, que lit le juge ?

- **Mesuré** (`../sondes/ticket-97/q1-lentree-des-juges.bats`, branche de [97]) : un survivant planté par la session de livraison qui **ajoute** une ligne marquée au prompt tant qu'elle n'y est pas — le prompt du rétro (appel 3) et celui du gate de valeur (appel 4) **ont reçu la ligne**. Un premier essai qui n'ajoutait qu'une fois n'a rien fait arriver : le pack écrit ces fichiers par `>` et écrase un ajout fait avant la fin de son écriture. La fenêtre gagnable est donc entre la fin de l'écriture et l'ouverture par `session_spawn` — que [97] a **élargie** de l'ouverture du canal du flux (`mktemp`, double ouverture, `lsof +L1`, ~90 ms).

- **Ce qui est déjà fait ailleurs, et à réutiliser plutôt qu'à refaire** : le prompt d'une lentille est sans nom depuis [94] (`lenses__prompt_open` : `proc_channel_open 7 6`, puis `/dev/fd/6` comme chemin de prompt — `session_spawn` l'ouvre, sur darwin c'est un `dup` du bout lecteur). Un second appelant de ce mécanisme le rend public (règle des couches : un `__` à deux appelants est mal nommé).

- **Ce que le faux `claude` ne dit pas** : il répond ce que le test a scripté, quoi que dise son prompt. La sonde mesure la **question reçue** ; qu'un vrai modèle y obéisse est l'hypothèse qui fait de ce trou une forge, et elle n'est pas à prouver pour fermer une entrée qu'un tiers écrit.

- **Hors critère, mais même famille, à trancher au tri** : le prompt de la **session de livraison** (`.scratch/<feature>/.session.<pilote>.<n>.jsonl.prompt`, écrit par `loop_session_prompt`, nommé pour toute la session). Un survivant d'une itération précédente peut y écrire avant que la suivante le lise. Ce n'est pas un juge, c'est la session jugée — ce qu'elle reçoit décide de ce qu'elle livre, pas d'un verdict ; à dire au tableau ou à fermer avec les deux autres.

- **Contrainte venue de [97] pour l'installeur (`init.sh`, hors de la write-surface de [97])** : le bloc que `init.sh` écrit dans le `.gitignore` du projet cible couvre `.scratch/*/.session.*.jsonl`. Depuis [97] le flux de livraison n'a de nom que l'instant entre son `mktemp` (`.session.<pilote>.<n>.jsonl.XXXXXX`, que le motif ne couvre même pas) et son délien : la ligne est **morte sans être fausse**. Le prompt de livraison, lui (`….jsonl.prompt`), n'est pas couvert non plus et vit dans `.scratch/<feature>/` le temps de la session — sous `gate_is_bookkeeping`, donc invisible au scope-guard, mais pas ignoré par git. Si ce ticket rend ce prompt sans nom, la ligne du `.gitignore` est à retirer ou à réécrire par celui qui touche `init.sh` (et son test `test/install.bats`), pas à laisser deviner.
