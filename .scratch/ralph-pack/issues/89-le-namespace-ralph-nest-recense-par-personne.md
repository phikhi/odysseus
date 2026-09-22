# 89 — Le namespace `RALPH_*` n'est recensé par personne

**What to build:** Que l'hermétisme de la suite couvre ce que le pack se fabrique comme il couvre déjà ce que le projet configure : le namespace `RALPH_*` dérivé de la source, pas six noms écrits à la main.

**Blocked by:** None

**Write-surface:** `test/helpers/harness.bash`, `test/smoke.bats`, `test/mutate.sh`, `.claude/lib/retro.sh`, `.claude/lib/receipt.sh`, `.claude/lib/tracker.sh`, `.claude/lib/playthrough.sh`

**Status:** resolved

- [x] `harness__clear_env` **dérive** de la source du pack les noms `RALPH_*` qu'il doit effacer, comme il dérive déjà les clés de configuration du `.example` trois lignes plus haut. Un nom ajouté au pack est effacé le jour où il arrive.
- [x] Un test refuse le nom que la dérivation ne voit pas : une dérivation qui ne sait pas ce qu'elle ne voit pas ne prouve rien ([85]). Le critère du recensement est écrit dans le test, pas deviné.
- [x] Le pendant de `test/smoke.bats` « *an exported config key does not leak in* » existe pour le namespace du pack : un run sous un `RALPH_*` exporté ne mesure pas l'environnement. Asserter sur ce qui a changé, jamais sur le succès du run.
- [x] Les cinq noms qui **préservent** une valeur héritée au `source` sont tranchés un par un : soit la préservation est voulue et la ligne dit par qui elle est écrite, soit elle ne l'est pas et l'assignation devient inconditionnelle. Une réponse « ça ne se produit pas » n'en est pas une — c'est ce que [40] avait écrit pour un seul nom.
- [x] Une entrée de mutation par garantie livrée, avec le témoin appairé.

## Comments

- **Ordre validé par Philippe le 14/09/2026** : **[87] → [86] → [88] → [89]**.
  Le critère est celui d'habitude — minimiser la reprise, jamais l'urgence. [87]
  devant parce qu'il ne touche que `test/` et qu'il pose le filet de source sous
  le heredoc de prose que [86] va réécrire ; [88] derrière [86] parce qu'il
  généralise une forme dont [86] livre le précédent ; [89] en dernier, sans arête.

- **Ouvert par la passe transversale du 14/09/2026** (`../passe-transversale-14-09.md`,
  §5). Sonde : `../sondes/passe-14-09/q4-le-namespace-ralph-nest-recense-nulle-part.bats`.

- **Le compte, mesuré.** Le pack nomme **42** variables `RALPH_*`.
  `harness__clear_env` en unset **6** : `RALPH_CONFIG`, `RALPH_DIR`,
  `RALPH_PROJECT_ROOT`, `RALPH_RUN_LOCK`, `RALPH_TREE_LOCK`,
  `RALPH_SOFT_LIMIT_HIT`. Les soixante-quatre clés de configuration, elles, sont
  dérivées du `.example` par un `sed`, dans la même fonction, juste au-dessus.

- **La règle que les six tiennent est celle de [40]**, recopiée dans le ticket
  [19] : *« `loop.sh` l'assigne aujourd'hui sans condition, ce qui est la seule
  raison pour laquelle une valeur héritée du shell d'un développeur est
  inoffensive — et c'est aussi pour ça que `harness__clear_env` peut se permettre
  de ne pas le connaître. »* Trente-six noms dépendent de cette règle et rien ne la
  vérifie.

- **Les cinq qui ne la respectent pas.** Leur lib les assigne **au `source`**, en
  `${X:-}`, donc en préservant une valeur héritée :

  | Nom | Lib | Ce qu'il porte |
  |---|---|---|
  | `RALPH_RETRO_STATE` | `retro.sh:102` | le répertoire d'état du rétro — celui que `retro_guards` compose, et où vivent `capability.seen` et `brief.<id>`, les deux objets que [83] a montrés |
  | `RALPH_RECEIPT` | `receipt.sh:66` | le répertoire du reçu d'audit |
  | `RALPH_TRACKER_SAID` | `tracker.sh:168` | ce qui **fait taire** le repli d'un constat de tracker ([64]) |
  | `RALPH_PLAYTHROUGH_SPEC` | `playthrough.sh:198` | le témoin de spec pris avant la première session |
  | `RALPH_PLAYTHROUGH_OPENED` | `playthrough.sh:513` | ce que le gate de valeur a ouvert |

  Mesuré : les valeurs traversent le `source` des vingt-quatre libs intactes, et
  `retro_guards` — le recensement de zones que [85] vient de dériver — rend un
  `index.guard` sous un répertoire choisi par l'environnement.

- **Ce que ce n'est pas, écrit pour que le ticket ne se trompe pas de menace.**
  Ce n'est **pas** un canal de session. Aucun de ces noms n'est exporté par le pack
  — seul `RALPH_DIR` l'est — donc ni un `claude` jugé, ni un successeur `at`, ni
  une lentille ne les place. Vérifié : `scheduler_command` n'en met que quatre sur
  la ligne mise en file (`PATH`, `RALPH_CONFIG`, `FEATURE`, `RALPH_PROJECT_ROOT`),
  et les autres ne sont pas dans l'environnement du pilote pour qu'`at` les
  capture. L'injecteur est le shell d'un humain, ou un wrapper.

- **Ce que c'est.** La moitié manquante de la garantie d'hermétisme de la suite.
  `test/smoke.bats` porte un test entier — *« the environment is hermetic: an
  exported config key does not leak in »* — parce qu'un `STERILE_K` dans le shell
  d'un développeur ferait mesurer son shell à la place du pack, et le commentaire
  de `harness__clear_env` le dit : *« This is not paranoia »*. Le namespace que le
  pack se fabrique lui-même n'a pas ce test, et il fait sept fois la taille de ce
  que le harnais en connaît.

- **Piège de dérivation, et c'est le seul vrai travail du ticket.** Un
  `grep -o 'RALPH_[A-Z0-9_]*'` sur `.claude/` attrape aussi les noms qui ne sont
  que dans des **commentaires** (`RALPH_REAL_USAGE`, qui est un interrupteur de
  test et pas une variable de run) — c'est le piège de harnais déjà payé plusieurs
  fois dans ce dépôt, un grep structurel qui attrape les commentaires. Et unset
  un nom que le harnais **pose lui-même** ensuite casserait la suite. La
  dérivation doit donc distinguer trois choses et le dire : ce que le pack lit,
  ce que le pack écrit, et ce que le harnais fournit.

- **Piège de mutation.** Une entrée qui retire un nom de la liste dérivée doit
  rougir un test qui **exporte** ce nom et mesure un effet, pas un test qui
  compare deux listes — sinon la mutation prouve la dérivation et pas ce qu'elle
  achète. Le témoin appairé : le même run sans la variable exportée.

- **Indépendant des trois autres tickets de la passe.** Il ne touche que `test/`
  si les cinq préservations sont jugées volontaires ; il touche `lib/` sinon, et
  dans ce cas il faut refaire les deux gates.

- **Ordre validé par Philippe le 15/09/2026** : **[90] → [86] → [88] → [89]**.
  [87] est livré (`726e62c`) et a ouvert [90] en route. La place retenue pour
  [90] est **devant [86]**, par le critère habituel — minimiser la reprise,
  jamais l'urgence — et c'est mot pour mot l'argument qui avait mis [87] devant
  [86] : l'AC 4 de [86] veut que le paragraphe du tracker soit **la même phrase**
  que celle que `init_preflight` imprime à la console, or cette phrase-là vit dans
  un `init__note "…"`, une chaîne entre guillemets doubles que [87] ne garde pas
  et que [90] garde. Livré devant, [90] est le filet sous cette moitié-là de la
  réécriture ; livré derrière, il constate après coup et peut coûter une seconde
  passe sur `init.sh`. [88] derrière [86] parce qu'il généralise une forme dont
  [86] livre le précédent ; [89] en dernier, sans arête.

- **Ce que [88] laisse sous ce ticket, livré le 21/09/2026.** [88] touche
  `.claude/lib/tracker.sh`, qui est dans la write-surface de celui-ci, et y ajoute
  une opération publique (`tracker_session_rule`) plus son entrée dans la liste
  des **lectures** de `tracker__dispatch`. Deux conséquences pour le recensement :
  - **Aucun nom `RALPH_*` nouveau.** Le compte de 42 mesuré ci-dessus est
    inchangé, et `RALPH_TRACKER_SAID` — le cinquième des cinq préservations à
    trancher — n'a pas bougé de `tracker.sh:168`.
  - **Mais un global de pack de plus hors du namespace `RALPH_*`** :
    `GATE_SURFACE_FIELD` dans `.claude/lib/gate.sh`, qui porte le nom du champ que
    le scope-guard lit dans un ticket. Il est assigné **sans condition** au
    `source`, donc il tient la règle de [40] et une valeur héritée est inoffensive
    — et c'est précisément pour ça qu'il compte ici : l'AC 2 demande que le
    **critère** du recensement soit écrit dans le test, et un critère écrit
    « les noms `RALPH_*` » ne voit ni celui-ci, ni `INIT_CLAUDE_OPEN`, ni
    `LOOP__FINDINGS`, ni `ROUTER__PINNED_SURFACE`. Le pack se fabrique des globals
    sous le préfixe de leur module, pas seulement sous `RALPH_`. Trancher le
    périmètre explicitement plutôt que le laisser tomber du grep.

- **Livré le 22/09/2026.** Ce que le code ne dit pas.

  **Le périmètre, tranché.** Pas « les noms `RALPH_*` » : un global de ce pack est
  un nom `RALPH_*` **ou** `<MODULE>_*` où `<MODULE>` est un fichier source du pack.
  Le critère est écrit dans `harness_pack_globals` et **redit** dans le test, pour
  que les deux puissent se contredire. Le compte change d'ordre de grandeur : les
  42 noms `RALPH_*` mesurés à l'ouverture deviennent **149 globals**, dont
  `GATE_SURFACE_FIELD` que [88] signalait, `INIT_CLAUDE_OPEN`, `LOOP__FINDINGS`,
  `ROUTER__PINNED_SURFACE`, et les dix-huit `INIT_*` de l'installeur. Les noms nus
  égaux à un module — `RETRO`, `LENSES`, `CAPABILITY`, `SCHEDULER` — sont des clés
  de configuration et restent couverts par la dérivation du `.example` : le test
  le dit, c'est pourquoi le critère exige l'underscore.

  **Trois passes de forme, et pourquoi il en faut trois.** Une seule ne marche
  jamais : jeter les chaînes perd `"$RALPH_RETRO_STATE"`, la forme dans laquelle ce
  pack écrit presque toutes ses lectures ; les garder fait entrer `RALPH_REAL_USAGE=1`,
  qui est une **phrase** qu'`init.sh` imprime à un humain (`init.sh:368`) en plus du
  commentaire de `budget.sh:53` que le ticket nommait. Le piège de dérivation est
  donc plus dur que « un grep attrape les commentaires » : il attrape la **prose
  entre guillemets doubles**, celle que [90] a appris à voir. Et `RALPH_REAL_USAGE`
  n'est pas un nom neutre : c'est l'interrupteur que `test/budget.bats` lit **après**
  `harness_setup`, donc l'effacer transformait un `skip` bruyant en `skip` silencieux.
  Il est le seul écart entre le balayage large et le recensement, et le test l'exige
  **à l'unité** (`assert_equal "$missing" "RALPH_REAL_USAGE"`) : un second écart fait
  rougir.

  **La zone a déménagé.** `layering__shell_files` ([87]) est devenue
  `harness_pack_sources` dans `test/helpers/harness.bash`, parce que le recensement
  en fait un second appelant et que la règle 6 du `CLAUDE.md` dit ce qu'on fait d'un
  `__` à deux appelants. `test/layering.bats` la consomme, son commentaire de zone a
  suivi, et **l'entrée de mutation « 87 the derived zone stops at .claude » a été
  repointée de `$LAYERING` vers `$HARNESS`** — son témoin n'a pas bougé. Une seconde
  entrée [89] vise la même ligne avec le témoin de `smoke.bats` : la ligne porte
  maintenant deux garanties.

  **Le défaut trouvé en écrivant, et c'est la vraie trouvaille du ticket.**
  `select.sh`, `tracker-github.sh` et `tracker-gitlab.sh` ne correspondent à
  **aucune** des trois passes ; `claim.sh`, `lang.sh` et `lenses.sh` à deux sur
  trois. Un pipeline qui ne trouve rien sort `1`, et sous le `set -e` de chaque test
  ce code de retour **termine la boucle `while` en cours de marche** et rend `0` :
  mesuré à **21 noms au lieu de 149**, sans un mot. Le recensement était correct par
  accident, parce que le cache est construit dans un `if` — où errexit est désarmé,
  le piège que [59] a payé. Chaque passe finit donc par `|| true`, et le test
  rappelle la dérivation **hors** de ce `if` et compare les deux comptes. C'est la
  seule assertion du ticket qui mesure une troncature silencieuse.

  **Les cinq préservations, et la sixième.** Les cinq sont devenues
  inconditionnelles (`RALPH_X=''`) : rien ne les exporte — vérifié, le pack n'exporte
  que `RALPH_DIR` — donc le `${…:-}` ne préservait qu'une valeur du shell qui a lancé
  le run, et rien d'autre. La sixième, `RALPH_CONFIG` dans les **deux** points
  d'entrée, est la seule voulue et sa ligne dit maintenant par qui elle est écrite.
  Piège payé : le commentaire ajouté à `human-loop.sh` nommait `scheduler_command`,
  et le test structurel de [09] — *« the drain never arms a successor »* — compte les
  `scheduler_[a-z]` de ce fichier **commentaires compris**. Un run complet perdu.
  Une prose ajoutée à `human-loop.sh` ne doit nommer aucune fonction de ce module.

  **L'empreinte voit `init.sh` depuis ce ticket.** Le recensement est caché sous
  `$TMPDIR` sur la clé du template (la marche lit ~1 Mo de shell et tourne avant
  chacun des 975 tests, chacun dans son propre processus). Cette clé ne voyait pas
  `init.sh`, où vivent dix-huit des noms recensés : un cache clé sur une empreinte
  aveugle à l'une de ses entrées est un cache qui périme sans le dire. Le nom du
  fichier garde le préfixe `ralph-harness.` pour rester dans le balayage des
  templates périmés — pas de nouveau glob dans `$TMPDIR`.

  **Coût mesuré.** ~30 ms par test (l'empreinte, payée une seconde fois : la mettre
  en cache dans une variable casserait *« the project template is keyed by names as
  well as contents »*, qui l'appelle deux fois et exige qu'elle change). Un `mv` de
  `.claude/lib/select.sh` change l'empreinte, donc le cache, donc le recensement.

- **Write-surface réelle, plus large que celle annoncée.** Annoncée :
  `test/helpers/harness.bash`, `test/smoke.bats`, `test/mutate.sh`,
  `.claude/lib/retro.sh`, `.claude/lib/receipt.sh`, `.claude/lib/tracker.sh`,
  `.claude/lib/playthrough.sh`. Ajoutés, et pourquoi :
  - `test/layering.bats` — la zone y vivait, elle en sort (règle 6) ;
  - `.claude/loop.sh` et `.claude/human-loop.sh` — l'AC 4 demande que la ligne d'une
    préservation voulue dise par qui elle est écrite, et `RALPH_CONFIG` est écrit
    dans les deux points d'entrée.

- **Ce qui reste, pour la passe transversale qui suit.** Le recensement est caché
  dans un fichier de `$TMPDIR` que la suite écrit et relit. Dans **ce** dépôt,
  `TEST_CMD` est `bash test/run.sh`, donc une session jugée par le pack fait tourner
  la suite qui lit ce cache — et rien n'empêche cette session d'écrire dans
  `$TMPDIR`. Le template de projet a exactement le même statut depuis [01] et
  personne ne l'a jamais traité ; c'est la même question que [80] a tranchée pour le
  registre du run, posée cette fois au harnais. Ce n'est pas une ligne du tableau de
  `docs/frontiere-de-confiance.md` (aucune règle de prompt n'est en cause), c'est une
  question pour la sonde « run réel » de la prochaine passe.

- **Gates sur le code livré.** `bash test/run.sh` = **975 tests, 0 failures,
  6 skips opt-in** (aucun dans le canari) — les 971 de la baseline de [88] plus les
  quatre tests de ce ticket. `bash test/mutate.sh` = **1024 mutations, 0 not ok** —
  les 1010 de la baseline plus les quatorze entrées de [89], l'entrée « 87 the
  derived zone stops at .claude » ayant changé de fichier sans changer de témoin.
  Le rouge instable de la famille [38] (*« a lens the gate's own deadline killed is
  not read as a refusal »*) n'a tiré sur aucun des deux runs complets.
