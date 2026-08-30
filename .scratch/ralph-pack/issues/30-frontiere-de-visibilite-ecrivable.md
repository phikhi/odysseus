# 30 — La frontière de visibilité de tous les contrôles est écrivable par une session

**What to build:** Fermer, ou déclarer avec son propriétaire, le fait qu'une session **choisit** ce que le pack peut voir. [24] a écrit qu'« un contrôle qui délègue sa visibilité à un fichier que le projet écrit doit dire jusqu'où il voit » ; la moitié manquante est **qui écrit ce fichier**. Les règles d'ignore ne sont pas une propriété du projet : ce sont des fichiers, et une session peut les écrire. Deux chemins, dont un ne demande aucune write-surface parce que rien dans le pack ne regarde `.git/`.

**Blocked by:** None

**Write-surface:** `.claude/lib/gate.sh`, `.claude/ralph.config.sh.example`, `test/gate.bats`, `test/canary.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`, `CONTEXT.md`, `README.md`

**Status:** resolved

- [x] Une session qui élargit la zone aveugle ne rend pas une itération verte, ou bien le pack le déclare et dit qui garde ça. Les deux chemins sont couverts nommément : `.git/info/exclude` (et son équivalent `core.excludesFile` dans `.git/config`), et le `.gitignore` du projet quand un ticket le déclare dans sa surface. *Les deux rendent l'itération rouge, par deux mécanismes : l'arbre jugé est snapshotté à travers les **règles épinglées** du spawn, donc ce que la nouvelle règle cache est jugé quand même ; et les deux sources du répertoire git sont en plus **remises** et portent leur propre finding sur le scope-guard. Quatre sources couvertes et non deux — le fichier d'exclusion global est la quatrième, nommé sans être remis.*
- [x] Le cas `.gitignore` est traité sans casser le cas légitime : un ticket a le droit d'ajouter une règle d'ignore (c'est du travail de projet normal, et [19] en fait), mais pas d'en profiter dans la **même** itération. La règle qui décide doit être celle d'avant la session, comme la write-surface l'est depuis [21]. *Le corollaire du ticket a été suivi : les règles d'avant la session décident, ce qui rend cette AC gratuite. Test `an ignore rule a ticket delivered counts from the next iteration` — itération 1 ajoute `dist/`, écrit `dist/out` dans sa surface, passe au vert et commite la règle ; itération 2 écrit `dist/other` hors surface et n'est pas vue, parce que la zone est maintenant honnêtement celle du projet ([24]).*
- [x] La ligne de zone de [24] cesse de mentir dans l'autre sens : un projet qui ignore `.scratch/` sans l'avoir commité voit son **tracker** annoncé comme chemin non jugé, alors que [21] le protège par un snapshot forcé. *Un répertoire replié qui **contient** un chemin que le pack juge est parcouru d'un niveau au lieu d'être annoncé en bloc. Tenu dans les deux sens par une assertion unique : `.scratch/other-feature/` est nommé, `.scratch/<feature>/` non — une marche qui aurait tout tu passerait la première moitié et raterait la seconde.*
- [x] Ce que ce ticket **ne** peut pas fermer est écrit avec son propriétaire, pas laissé implicite : `.git/` reste hors de portée d'un contrôle qui diffe des trees git, et un run AFK sur un dépôt dont une session peut réécrire la configuration git est une posture, pas un accident. *Trois résidus écrits plus bas, dont deux ne sont pas ceux que le ticket attendait : l'élargissement **hors du dépôt** survit aux itérations suivantes, `.git/info/attributes` n'a ni sonde ni propriétaire, et un témoin détruit ferme le contrôle au lieu de l'ouvrir.*
- [x] La ligne correspondante de `docs/frontiere-de-confiance.md` existe et distingue les deux moitiés : jusqu'où le contrôle voit, et qui déplace cette frontière. *Ligne réécrite (« La frontière de visibilité de tous les contrôles est une propriété du projet, pas un choix de la session »), plus trois lignes voisines corrigées et trois corollaires.*

## Comments

- **Origine : passe transversale 24→26, le 30/07/2026.** Trouvé en posant la question 5 sur le livrable de [24] lui-même : la zone ignorée est nommée à chaque tour, mais **qui décide de son contenu** n'avait été posé nulle part. Deux sondes.

  *Sonde 1 — `.git/info/exclude`, et aucune write-surface n'est nécessaire.* Un vrai `git init` crée ce fichier (vérifié sur ce dépôt : présent). Une session ajoute `rogue/` dedans et écrit `rogue/backdoor`, hors de sa surface. Deux tickets à la suite :

  ```
  exit=0   01-alpha=resolved   02-beta=resolved
  rogue/backdoor: survives     rogue/second: survives
  scope complaints: 0
  ralph: gate: 02-beta: nothing in this gate judged 1 ignored path(s): rogue/
  ```

  Zéro plainte du scope-guard, deux itérations vertes, les deux fichiers en place. La ligne de [24] nomme bien `rogue/` — mais elle nomme la **conséquence**, pas la cause, et un humain qui lit le matin n'a aucun moyen de distinguer « le projet ignore un cache de build » de « une session a décidé que ce répertoire serait invisible ». Le fichier qui porte la décision vit dans `.git/`, donc il survit au rollback, il survit au run, et il n'est dans aucun tree que quoi que ce soit compare.

  *Sonde 2 — le `.gitignore`, quand un ticket le déclare, cache ce que la session écrit dans la même itération.* Surface `src/alpha.txt`, `.gitignore` ; la session écrit `src/alpha.txt`, `lib/rogue.sh` et ajoute `lib/` au `.gitignore` :

  ```
  exit=0  status=resolved
  lib/rogue.sh exists: yes
  commit: 01-alpha: iteration delivered (gate green)  .gitignore | 1 +  src/alpha.txt | 1 +
  ralph: gate: 01-alpha: nothing in this gate judged 1 ignored path(s): lib/
  ```

  Le scope-guard ne voit que `.gitignore`, qui est dans la surface : vert. `lib/rogue.sh` reste. Et la boucle **commite la règle**, donc l'aveuglement est durable : tous les runs suivants héritent d'un `.gitignore` qui cache `lib/`, et la ligne de zone dira `lib/` pour toujours, indistinguable d'un répertoire de build légitime.

- **Ce que la faille ne casse pas, sondé pour ne pas surestimer.** `--force` l'emporte sur toute règle d'ignore, donc les deux snapshots forcés du pack sont immunisés. Une session qui écrit `.claude/` **et** `.scratch/` dans `.git/info/exclude`, réécrit `.claude/lib/gate.sh` et met sa propre write-surface à `*` :

  ```
  exit=4  status=ready-for-agent
  gate.sh nommé par le scope-guard : oui        tracker restauré : oui
  Write-surface: `src/alpha.txt`  (remise)      gate.sh: dernière ligne d'origine
  ```

  Le scellement de [24] et la protection du tracker de [21] tiennent donc. Le trou est borné à **tout ce qui est hors de `GUARDED_PATHS`** — c'est-à-dire le code du projet cible, ce que la boucle existe pour écrire.

- **Piège pour qui livrera ça, et il est le cœur du ticket.** La tentation est de forcer l'arbre entier. C'est exactement ce que le commentaire de `gate_tree_snapshot` refuse depuis [24], pour une raison qui n'a pas bougé : le build output du projet entrerait dans le tree jugé, chaque itération honnête ressemblerait à un débordement, et chaque rollback supprimerait un cache. La piste plausible est asymétrique : **comparer les règles d'ignore effectives avant et après la session** (`.gitignore` de l'arbre, `.git/info/exclude`, `core.excludesFile`) et rougir sur un **élargissement**, sans rien dire d'un rétrécissement ni du contenu de la zone. Une règle ajoutée pendant la session est un déplacement de frontière, et c'est ça qui est jugeable — pas les fichiers derrière.

  Corollaire à trancher dans le ticket : le scope-guard doit-il juger sur les règles **d'avant** la session, comme il juge déjà sur la write-surface d'avant la session ([21]) ? C'est la réponse la plus cohérente avec le reste du pack, et elle rend l'AC 2 gratuite — un ticket peut ajouter une règle, elle ne s'applique qu'au tour suivant.

- **Ce que `.git/` implique, et pourquoi ce n'est pas qu'une histoire d'ignore.** La même absence de contrôle couvre `.git/config` (donc `core.excludesFile`, et le reste de la configuration git que le pack utilise à chaque itération) et `.git/info/attributes` (un filtre `smudge` réécrirait le contenu que `git checkout-index` produit — c'est-à-dire ce que le **rollback** restaure). Aucune des deux n'est sondée ici ; elles appartiennent à la même famille et le ticket doit dire s'il les traite ou les nomme. [22] savait déjà que `.git/` est atteignable par une session — il l'écrit à propos du verrou d'arbre — mais personne n'avait tiré la conséquence pour la **visibilité** des contrôles.

- **Contrainte pour [13].** Un worktree par itération ne referme pas ce trou : `info/exclude` et `config` vivent dans le répertoire git **commun**, partagé par tous les worktrees liés. Ce que [13] referme est la zone ignorée du répertoire de travail (les fichiers non suivis ne sont pas portés par un worktree neuf), pas les règles qui décident de ce qui est ignoré. À écrire dans son ticket : l'isolation par worktree est une réponse à [24], pas à celui-ci.

- **Contrainte pour [19].** L'installeur écrit le `.gitignore` du projet cible, donc il est le premier client légitime de la règle « une règle d'ignore ajoutée ne s'applique qu'au tour suivant ». Et il ne peut rien faire pour `.git/info/exclude`, qui n'est pas versionné : ce que l'installeur peut provisionner s'arrête à l'arbre.

- **La troisième trouvaille, plus petite : la ligne de zone nomme le tracker.** Un projet qui ignore `.scratch/` **sans avoir commité le tracker** :

  ```
  ralph: gate: 01-alpha: nothing in this gate judged 1 ignored path(s): .scratch/
  ```

  Faux : `failures_tracker_tree` snapshotte `issues/` avec `--force`, donc le tracker est jugé et restauré ([21]). La mécanique est double — `git ls-files --directory` replie le répertoire entier en une ligne, et `gate_is_bookkeeping` ne reconnaît que `.scratch/<feature>/*`, donc un `.scratch/` replié ne matche pas. C'est le mensonge symétrique que [24] avait explicitement gardé pour les chemins gardés (« nommer un chemin que le gate a bien jugé est un mensonge dans l'autre sens », tenu par deux refutations) et laissé ouvert pour celui-là. Configuration plausible : une installation fraîche, un premier run avant le premier commit du tracker.

## Livraison — 03/08/2026

**Ce qui a été tranché, et le corollaire du ticket a gagné.** La piste écrite dans les commentaires (« comparer les règles avant et après, rougir sur un élargissement ») a été retenue *comme signal de coût* et pas comme verdict, parce que rougir sur un élargissement contredit l'AC 2 : un ticket a le droit d'ajouter une règle. Le verdict est ailleurs, et c'est le corollaire : **les règles qui décident d'une itération sont celles qu'elle a reçues.**

- `gate_ignore_pin` relève, avant le spawn, un **dépôt-témoin** : un `git init --template=<vide>` dans un répertoire temporaire, portant une copie de chaque source de règles et **aucun fichier du projet**. `gate_tree_snapshot` force dans l'arbre jugé tout ce qui est caché maintenant mais que ces règles ne cachaient pas.
- La question « ces règles auraient-elles caché ce chemin ? » est posée à `git check-ignore` dans le témoin, jamais à un parseur maison. Sondé le 03/08/2026 : `check-ignore` répond sur des noms de chemins sans jamais les stater, honore un `.gitignore` imbriqué relativement à son répertoire, un pattern répertoire-seul contre un fichier sous lui, et `--stdin` en un seul process. Réimplémenter gitignore en bash aurait été le vrai piège du ticket.
- **Quatre sources, trois traitements**, et la différence n'est pas cosmétique : le `.gitignore` de l'arbre est du travail de projet (rien de rougi, rien de défait, effet au tour suivant) ; `.git/info/exclude` et `core.excludesFile` ne sont versionnés par rien et déclarables dans aucune write-surface, donc **remis** depuis le témoin *et* rouges au même titre que la configuration scellée ; le fichier d'exclusion global est rouge et hors de portée.

**Pourquoi la remise, et pas seulement la détection.** Sans elle, une itération rouge achète la nuit : la frontière élargie est ce que l'itération **suivante** épingle, donc `rogue/` devient légitimement invisible au deuxième tour et le pack ne peut plus faire la différence avec un cache de build. Les deux alternatives ont été déroulées et écartées. Épingler ces sources **au démarrage du run** referme le trou sans écrire dans `.git/` — mais alors une session hostile rougit *toutes* les itérations suivantes, en facturant `Failures:` à des tickets innocents jusqu'à l'escalade. Ne rien remettre du tout et le déclarer était la troisième : c'est ce qui reste pour la source hors du dépôt, faute de pouvoir faire mieux, et ça se voit dans la liste des résidus.

**Le scope-guard porte le finding, la ligne de zone porte la cause.** Un déplacement hors de l'arbre est un finding du scope-guard (`moved the ignore frontier in .git/info/exclude, which decides what every check here can see — no write-surface may cover it (put back)`), classe `internal`, retryable — une session fraîche repart de règles déjà remises. Un déplacement dans l'arbre est une **ligne** et pas un verdict (`this session moved the ignore frontier: .gitignore — this iteration was judged through the rules it was handed, the new ones apply from the next`) : c'est la cause que [24] ne disait pas, sa ligne de zone ne nommant que la conséquence.

**Ce que les sondes ont trouvé et que le code ne dit pas.**

- *Deux défauts trouvés par la première sonde, tous les deux du même genre.* `git init --template=<vide>` ne crée pas `.git/info/`, donc l'écriture du témoin échouait — et le harnais de test faisait le même choix, donc le projet fixture n'avait **aucun** `.git/info/exclude` là où tout `git init` réel en crée un. La sonde 1 écrivait dans un répertoire absent : l'élargissement échouait *avec* elle, ce qui ressemblait à un contrôle qui marche. Corrigé des deux côtés (`mkdir -p` dans le pin et dans la remise, `.git/info/exclude` provisionné par `harness__init_git`), et c'est le troisième corollaire écrit dans la frontière de confiance.
- *Une ligne qui mentait dans l'autre sens.* `core.excludesFile` déplace **deux** sources d'un coup — la clé, et le fichier qu'elle désigne maintenant. Mesurées d'un seul regard, la remise de la clé était annoncée, puis le fichier hors dépôt était annoncé comme irrécupérable — un fichier qu'aucune session n'avait touché et qui était déjà hors jeu. Mesure en deux temps depuis : les sources du répertoire git d'abord, puis **un second regard** pour celles du dehors. C'est la leçon de [29] (« une ligne qui dit *je n'ai pas pu* doit être nette de ce qu'elle a pu ») un ticket plus loin, et le test le tient par une réfutation (`refute_output_contains ".git/my-excludes"`).
- *Le diagnostic sortait sur stdout.* Tous les appelants de `gate_tree_snapshot` prennent l'arbre par substitution de commande, donc la ligne « je refuse de snapshotter » était capturée dans la variable puis jetée avec le statut : le refus arrivait en aval sans cause. Sur stderr depuis, sondé en détruisant un témoin en cours de session.
- *L'ordre n'est pas porteur, et c'est écrit comme tel.* Le commentaire disait que la remise doit tomber avant l'arbre jugé « sinon le verdict change ». Faux : l'arbre passe par le témoin dans les deux cas. La mutation le prouve — l'entrée qui retire le forçage revient `VACUOUS` contre le test `.git/info/exclude`, précisément parce que la remise l'a déjà rendu visible. Le commentaire dit maintenant ce que l'ordre achète réellement (l'itération *suivante*), et les deux mutations du forçage visent les deux tests où il est la seule chose qui tient : une règle de l'arbre, et une règle que le run n'a pas pu remettre.
- *Le chemin qu'aucun gate ne couvre.* Une session de re-slice ([07]) n'est jugée par aucun gate — tout ce qu'elle produit est jeté — donc rien n'aurait remis les règles qu'elle déplace, et l'itération suivante aurait épinglé l'élargissement. `gate_ignore_frontier` a donc un second appelant dans `failures_reslice`, avec sa ligne de journal : il n'y a pas de gate là pour porter un finding. C'est le même argument que le second appelant de `gate_restore_tree`.

**Le coût, mesuré.** Sur un dépôt de 420 fichiers dont 400 sous `node_modules/` et 20 `.gitignore` imbriqués : un témoin coûte 0,34 s, un snapshot passe de 0,21 s à 0,34 s, et 0,39 s quand la frontière a bougé. Environ huit snapshots par itération, donc ~1 s de plus par itération, contre une session qui dure des minutes. Le chemin coûteux — parcourir la zone ignorée et interroger le témoin — ne tourne **que** si le manifeste dit qu'une source a bougé, ce qui est le cas rare ; le manifeste, lui, coûte un `git ls-files` et quelques `cksum`. Aucun objet git laissé dans le témoin (il n'écrit jamais rien), et aucun témoin survivant à un run.

**Trois trouvailles dans le harnais, dont deux sont des faux verts.**

1. *Le fingerprint du template ignorait le harnais.* `harness__pack_fingerprint` hachait `.claude` et `test/fixtures`, pas `test/helpers/harness.bash` — alors que le template porte un `.git` entier construit par `harness__build_project`. Une mutation qui retirait une ligne de cette construction réutilisait un projet fabriqué **avant** la mutation, et rendait `VACUOUS` sur un test parfaitement sain. Le harnais est dans la clé depuis.
2. *`mutate.sh` déguisait un filtre erroné en test vacuous.* Le verdict « 0 failures » était testé **avant** « 0 tests », donc un `-f` qui ne matchait rien affichait `VACUOUS` — c'est-à-dire « ce test est un mensonge » à propos d'un test qui n'a jamais tourné, et la réparation évidente aurait été de réécrire un test correct. Ordre inversé. Le gate qui vérifie les tests est un test, et c'est la deuxième fois que ce fichier mentait sur ses propres verdicts.
3. *Une réfutation vacuous évitée de justesse dans le canari.* La réfutation ajoutée à `the run leaves nothing of its own behind` lisait `$loop_output`, qui n'existe pas dans ce test-là — quatre `run` intermédiaires avaient écrasé `$output`. Une réfutation contre une chaîne vide ne peut pas échouer, ce que ce fichier a déjà payé deux fois. Corrigé, et la réfutation porte maintenant un **témoin** (`assert_output_contains "nothing in this gate judged"`) qui prouve que la sortie lue est bien celle de la boucle.

**Le canari.** Le monde hostile gagne la source de règles que tout dépôt réel possède et qu'aucun ticket ne peut déclarer : un `.git/info/exclude` portant l'exclusion locale d'un humain, avec un fichier derrière. C'est la direction qui compte ici, celle de [31] — le cas courant n'est pas l'attaque : trois itérations doivent être vertes **à travers** les exclusions locales de quelqu'un d'autre, le fichier derrière doit être intact à la fin, et le run ne doit jamais prétendre que quelqu'un a déplacé la frontière.

**Écart de write-surface déclaré.** La surface annonçait `.claude/lib/gate.sh`, `.claude/ralph.config.sh.example`, `test/gate.bats`, `test/canary.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`, `CONTEXT.md`, `README.md`. Ajoutés, chacun pour une raison qui n'était pas contournable :

- **`.claude/loop.sh`** — le témoin doit être relevé une fois par itération, avant le spawn, et la boucle est le seul endroit qui connaît cette frontière. Placé **avant le claim** exprès : une machine qui ne peut pas fournir de témoin refuse l'itération (`exit 4`) sans rien à défaire.
- **`.claude/lib/failures.sh`** — le second appelant, ci-dessus. Trois lignes.
- **`test/helpers/harness.bash`** — le `.git/info/exclude` absent, et le fingerprint aveugle au harnais. Sans le premier, aucun test de ce ticket ne pouvait exercer la source principale.
- **`test/failures.bats`** — le test du chemin re-slice.

**Ce qui reste, et où.**

- **L'élargissement hors du dépôt survit aux itérations suivantes.** Un `core.excludesFile` posé dans la config de l'utilisateur, ou un `~/.config/git/ignore` réécrit : l'itération qui l'a fait est rouge et jugée à travers le témoin, mais le run ne peut pas remettre ce qui est hors de l'arbre, donc le témoin de l'itération suivante épingle l'élargissement. Test `a frontier this run could not put back says so instead of claiming it did`. Propriétaire : personne, et c'est la posture de [24] — le rempart pour ce qu'une session écrit hors du dépôt est l'isolation de l'hôte.
- **`.git/info/attributes` n'a ni sonde ni propriétaire.** Un filtre `smudge` réécrit ce que le `git checkout-index` du **rollback** produit. Même famille, pas traité ici : ce n'est pas une règle de visibilité mais une règle de contenu, et le mécanisme épinglé de ce ticket ne s'y applique pas tel quel. Écrit dans le tableau de la frontière comme un trou sans propriétaire.
- **Un témoin détruit ferme le contrôle.** Il vit dans `$TMPDIR`, qu'une session peut atteindre. Sondé : `gate_tree_snapshot` refuse de rendre un arbre, le scope-guard refuse de passer — et **le rollback ne défait rien non plus**, donc l'itération est rouge avec ses écritures encore en place. C'est le bon sens du fail-closed, et le prix est écrit ici parce qu'aucune ligne du code ne le dit.
- **[13] ne referme rien ici**, contrairement à ce que l'isolation par worktree referme pour [24] : `info/exclude` et `config` vivent dans le répertoire git **commun**, partagé par tous les worktrees liés. Contrainte déjà écrite dans son ticket par ce ticket-ci.
- **[19] est le premier client légitime** de « une règle ajoutée compte au tour suivant », et ne peut rien provisionner dans `.git/info/exclude`, qui n'est pas versionné. Déjà écrit dans son ticket.
- **[10]** hérite de deux lignes de stdout supplémentaires (le finding de frontière côté scope-guard, la ligne de cause côté gate) et d'aucun champ de journal, comme la zone de [24].
- **Constaté au passage, hors de ce ticket.** `failures_make_durable` annonce `committed N path(s)` en comptant les chemins *approuvés* et non ceux que git a acceptés : un chemin ignoré est refusé par son `git add` sans `--force` (sondé — les autres chemins du lot passent quand même, seul l'ignoré tombe). C'est l'asymétrie « gardé ne veut pas dire commité » de [24], et depuis ce ticket elle est atteignable par un ticket qui ajoute légitimement une règle d'ignore couvrant ce qu'il écrit. La ligne surcompte, elle ne mange rien. Pas corrigé ici — `failures.sh` n'était ouvert que pour le re-slice, et une ligne de compte demande son propre test.

## Ce que la passe transversale du 03/08/2026 a trouvé dans ce livrable

Trois trous, tous dans le mécanisme et aucun dans la doctrine : les règles épinglées restent la bonne réponse, et le corollaire (« de quand date ce sur quoi ce contrôle s'appuie ») tient. Chacun a son ticket, avec sa sonde et son témoin.

- **[32] — la remise ne tombe que là où un gate a jugé.** `gate_ignore_frontier` a deux appelants : `gate_run` et `failures_reslice`. Une itération dont la session **crashe** ou qu'un délai de [23] coupe n'est ni gatée ni re-slicée, donc l'élargissement reste, et l'itération suivante l'épingle comme la configuration du projet et écrit derrière au vert. C'est précisément la nuit que la remise a été écrite pour empêcher, et le prix pour la session est un `exit 1`. Le commentaire du second appelant dit pourtant la bonne chose (« a planning session is a session, it is never gated ») : le raisonnement était juste et n'a pas été appliqué à la session d'itération, qui n'est pas gatée sur deux de ses quatre issues. La liste des issues est le `case` de `failures_classify` depuis [07] ; ce ticket n'est pas allé la lire.
- **[33] — refermé le 04/08/2026.** Le forçage lit les deux listes ligne par ligne et passe des pathspecs `:(literal)` ; l'exclusion de la ligne de zone lit la même liste de la même façon. La phrase de ce ticket « ce que les règles épinglées ne cachaient pas est forcé dans l'arbre » n'était vraie que pour un chemin sans espace ni métacaractère avant cette date. Le constat d'origine :
- **[33] — un espace suffit à sortir du forçage.** `gate_tree_snapshot` force `$hidden` par un `for path in`, donc `my dir/` devient deux pathspecs qui ne matchent rien, avalés par le `|| true` prévu pour les chemins qu'un projet n'a pas. Et `gate__ignored_walk`, qui exclut ce chemin de la ligne de zone, compare des **chaînes entières** : il le croit forcé et se taît. Ni jugé, ni défait, ni nommé — sondé sur le cas légitime que ce ticket avait rendu gratuit (un `.gitignore` déclaré dans la surface), itération verte avec un fichier hors surface en place.
- **[34] — le témoin détruit blanchit au tour suivant.** Le résidu écrit ici (« un témoin détruit ferme le contrôle, l'itération est rouge avec ses écritures encore en place ») s'arrête un tour trop tôt : l'itération suivante prend cet arbre pour un état d'avant, donc les écritures hors surface ne sont plus le changement de personne. Le fail-closed est un blanchiment en deux coups au prix d'un retry. Le même ticket porte l'autre moitié, qui est un vrai fail-open : le refus de snapshot que ce ticket a introduit est lu comme une liste vide par `gate_unjudged_changes`, donc le confinement des écritures de lentille ([06]) passe au vert sans avoir mesuré.

- **Passe transversale du 06/08/2026 : la remise est juste, son imputation ne l'est plus.** `.git/info/exclude` et `core.excludesFile` vivent dans le répertoire git commun ; depuis [13] plusieurs itérations les épinglent à des instants différents et les remettent sans verrou. `gate_ignore_frontier` répond à « la frontière a-t-elle bougé depuis mon témoin » et jamais à « qui l'a bougée » : sondé, le frère innocent est rougi, rollbacké et facturé d'un retry, et la session qui a élargi trouve la frontière déjà remise et sort verte. C'est [41]. Ce que ce ticket a construit n'est pas en cause — le témoin, la question posée à `git check-ignore`, la remise vérifiée — c'est le fait qu'il n'y avait qu'un acteur quand la question a été formulée.

- **Passe transversale du 26/08/2026 : le pin a le bon mécanisme et la moitié du critère —
  c'est [46].** Ce ticket a épinglé `.git/info/exclude` et `core.excludesFile` parce qu'ils
  décident de ce qu'un contrôle **voit**. La même configuration porte des clés qui décident
  de ce que git **lance** (`core.fsmonitor` est un chemin de programme : 248 exécutions sur
  un run de deux itérations, dans l'arbre de processus du pilote, run vert et silence) et de
  ce que git **produit** (`filter.<n>.smudge` via `.git/info/attributes` : une itération
  réécrit le `CONTEXT.md` que les suivantes lisent, sans qu'aucun diff de tree puisse le
  voir, puisque les deux trees sont smudgés de la même façon). Les deux sources sont
  écrivables par une session — `<arbre principal>/.git/config` et `~/.gitconfig`. Sondes :
  `.scratch/ralph-pack/sondes/passe-26-08/`, `p1c`, `p3` P3a, `p7`, `p8`.
- **[46], le 29/08/2026 : la machinerie de ce ticket porte maintenant deux questions, et elle a été renommée pour le dire.** Le pin, le manifeste, la comparaison, la remise, le registre et les trois sites de [32] sont exactement ceux de ce ticket-ci ; [46] y ajoute un **quatrième genre**, `cfg`, pour ce qu'une session met dans la configuration git et qui fait que git *exécute un programme* ou *transforme un contenu* (`core.fsmonitor`, `filter.<n>.smudge`, `.git/info/attributes`, et la liste dérivée du critère dans `gate_config_keys`). Un `gate_ignore_frontier` qui rend un constat sur `core.fsmonitor` est un nom qui ment, donc la partie **partagée** s'appelle maintenant `gate_frontier` / `gate_frontier_common` / `gate_frontier_pin` / `gate_frontier_moved` / `gate__frontier_{manifest,pin_manifest,restore,detect,record,share,mark,ledger_len,pinned,current,pin_broken,info_path}`, et les variables avec : `RALPH_GATE_IGNORE` → `RALPH_GATE_FRONTIER`, `RALPH_IGNORE_PIN` → `RALPH_FRONTIER_PIN`, `RALPH_IGNORE_COMMON` → `RALPH_FRONTIER_COMMON`. Ce qui ne parle que d'ignore garde son nom : `gate__ignore_tree_rules`, `gate__ignore_exclude_path`, `gate__ignore_global_path`, `gate__ignore_{tree,shared}_manifest`, `gate_moved_tree_rules`, `gate_newly_hidden`. Le manifeste est aussi passé de **un producteur à trois** — arbre, sources partagées d'ignore, configuration — parce que `gate__frontier_pin_manifest` ne demandait la moitié arbre que pour jeter le reste, et le reste coûte désormais une interrogation de `git config`.

- **Et une entrée de mutation de ce ticket a dû être ré-ancrée, pour la raison exacte que l'en-tête de `test/mutate.sh` documente.** `30 a restore that was only attempted reports success` visait la ligne `[ "$(gate__frontier_current "$name")" = "$pinned" ]` ; `gate__config_restore` finit par la même comparaison et vit **plus haut** dans le fichier, donc la substitution sans `/g` serait allée sur la mauvaise fonction en laissant ce test intact. Elle est maintenant ancrée sur le `esac` qui la précède. La garantie n'a pas bougé : la remise vérifie toujours son résultat.

- **[09], le 29/08/2026 : le résidu de ce ticket a maintenant un lecteur, et une conséquence.** `gate_frontier_residue` est une fonction publique neuve, placée après `gate__frontier_share` — la même différence symétrique un niveau plus haut : contre le manifeste du témoin de **run** et sur les sources **partagées** seulement (`.git/info/exclude`, `core.excludesFile`, le fichier global, les clés `cfg`, `.git/info/attributes`). C'est ce qui la fait dire « résidu » et pas « mouvement » : au moment où on la lit, toute remise qui pouvait tirer a tiré, donc ce qui diffère encore est ce qu'aucune remise n'a atteint. La moitié `tree` en est exclue exprès — un `.gitignore` qu'une session écrit est du travail de projet, et le run suivant est censé le recevoir. Le lecteur est `loop__arm_successor` : **un run qui laisse un résidu n'arme aucun successeur**, parce qu'un run neuf épingle la configuration qu'il trouve et adopterait donc le résidu comme celui du projet, en silence. Deux choses à savoir avant de toucher au manifeste : un ticket qui en change la **forme** (les trois colonnes `kind<TAB>name<TAB>digest`) casse ce lecteur en plus des deux existants ; et le témoin du run doit rester vivant jusqu'à la queue de `loop_main`, l'armement se lisant dessus avant le `rm -rf`.

- **[50], le 30/08/2026 : ce que `gate_newly_hidden` force dans l'arbre jugé arrive
  maintenant aussi dans l'historique.** Ce ticket a fermé « une session ne peut pas
  élargir l'angle mort dans lequel elle est jugée » ; il restait ouvert par l'autre
  bout — une session pouvait changer **ce que son itération commite** en écrivant une
  règle d'ignore. Sondé (`sondes/ticket-50/p1`, P1b) : la session écrit `build/out.txt`
  puis ajoute `build/` au `.gitignore`, les deux dans sa surface ; l'itération est
  verte, la règle est commitée, le fichier ne l'est pas, le ticket est `resolved`. Un
  faux livré en deux lignes, plus délibéré que le cas gardé de [24]. `git add --force`
  dans `failures_make_durable` rend exactement ce qui serait arrivé sans la règle de la
  session — le miroir de la garantie de ce ticket, et il vaut la peine de le lire comme
  tel : la liste `gate_newly_hidden` a désormais **deux** consommateurs qui doivent
  découper la zone de la même façon, le snapshot et le commit.
