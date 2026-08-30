# 52 — le `PATH` décide de ce que le pack exécute, et le successeur en hérite figé

**What to build:** Décider ce que le pack fait du fait que **`PATH` est en amont de
tous ses contrôles**, et le tenir. [46] a fermé un genre de cette famille — « la
configuration git décide aussi de ce que git exécute » — en épinglant les sources
de configuration. Mais ce témoin *demande à git* ce que la configuration dit, donc
il est en aval d'un `git` interposé. Le `PATH` du pilote décide quel `git`, quel
`claude`, quel `at` le pack exécute ; une session peut écrire dans un répertoire
qui s'y trouve (`~/.local/bin`, `/usr/local/bin` sur beaucoup de macs,
`node_modules/.bin`), et ça survit au rollback, s'exécute dans l'arbre de process
du pilote, et depuis [09] **traverse le redémarrage** : `scheduler_command` fige ce
`PATH` dans la ligne mise en file.

**Blocked by:** None

**Write-surface:** `.claude/lib/gate.sh`, `.claude/lib/capability.sh`,
`.claude/lib/scheduler.sh`, `.claude/loop.sh`,
`.claude/ralph.config.sh.example`, `test/gate.bats`, `test/capability.bats`,
`test/scheduler.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** resolved

**Tags:** securite, frontiere-de-confiance

- [x] Décider — et écrire la décision avec son prix — ce que le pack peut
      honnêtement tenir ici. Trois sorties possibles, elles ne se cumulent pas par
      réflexe :
      **(a) un témoin**, sur le modèle de [15] : ligne de base des répertoires du
      `PATH` prise par le pilote avant la première session, recomparée par
      itération, une dérive sort en `receipt_gap` **et** en ligne de `run.log` (la
      moitié que [46] a dû réparer pour les capacités). Ne rougit rien, ne défait
      rien. Prix : un `PATH` de développeur bouge tout seul (un `npm i -g`, un
      `brew upgrade`), donc le bruit est le vrai risque et la barre doit être
      calculée, pas devinée ;
      **(b) un refus d'armer**, sur le modèle exact de `gate_frontier_residue` : un
      run dont un répertoire du `PATH` a bougé pendant la nuit n'arme pas de
      successeur, parce qu'un run neuf adopterait ce `PATH` comme celui du projet.
      C'est le raisonnement de [09] mot pour mot, appliqué au second genre ;
      **(c) un préflight** qui refuse de démarrer quand `PATH` contient un
      répertoire écrivable *sous l'arbre du projet* (`.`, `node_modules/.bin`, un
      chemin relatif) — le cas où l'exposition n'est plus « hors du dépôt » mais
      dans l'arbre même que la session écrit.
      Ce qui n'est **pas** une sortie : figer un `PATH` minimal pour le pack. Le
      projet a le droit d'avoir son `claude` et son `git` où il veut, et un pack
      qui choisirait le sien casserait toute installation non standard en silence.
- [x] `scheduler_command` dit ce qu'il transmet. Aujourd'hui le commentaire dit
      « `PATH` so the successor finds the same `claude` and the same `git` this run
      found », ce qui est vrai et incomplet : il transmet aussi ce qu'une session y
      aurait mis. La ligne du matin (`scheduler_caveat`) est l'endroit où ça se dit,
      ou bien c'est un refus d'armer — trancher, pas les deux.
- [x] La ligne du tableau existe et nomme son propriétaire. Aujourd'hui la ligne
      « Ce qu'une session écrit **hors du dépôt** » dit déjà la phrase juste — *« la
      ligne « rien ne le fera ici » reste vraie de ce qui est écrit comme donnée ;
      elle ne couvre pas ce que le pack exécute ensuite »* — et ne donne qu'un
      propriétaire, [46], pour `~/.gitconfig`. Le `PATH` est le second cas et il
      n'en a aucun.
- [x] Une mutation peut rendre la garantie livrée rouge. Si la décision est (a) ou
      (b), c'est mécanique. Si c'est seulement une phrase, **ne pas livrer de code
      mort** : la phrase va au tableau et le ticket dit pourquoi rien n'est
      vérifiable ([47] a écrit cette règle).

## Ce qui a été mesuré, le 30/08/2026 (passe transversale)

Sonde conservée : `.scratch/ralph-pack/sondes/passe-30-08/r5-le-path-du-pilote.bats`.

- **`R5a`.** Une session pose un `git` (passthrough enregistreur) dans un
  répertoire du `PATH` du pilote, depuis une itération **verte** (`rc=0`,
  `01-alpha resolved`, `committed 1 path(s)`). Le run courant fait **0** appel à
  travers lui ; le run **suivant** en fait **204**, dont `rev-parse --git-dir`,
  `rev-parse HEAD`, `worktree list --porcelain`, `rev-parse --git-common-dir`,
  `config --get core.excludesFile`. Aucune ligne de gate, aucune ligne de zone,
  aucun reçu, aucune dérive de capacité.
- **Pourquoi 0 pour le run courant, et c'est un piège de sonde autant qu'un fait
  du pack** : bash **hashe** les chemins de commandes. Le pilote avait résolu `git`
  bien avant que la session existe. Ce qui compte est donc tout bash **frais** —
  le run suivant, les `bash -c` de `TEST_CMD`/`TYPECHECK_CMD`, et le successeur.
  Une sonde qui ne mesure que le run courant conclut l'inverse de la vérité.
- **`R5b`.** La ligne mise en file porte le `PATH` du pilote **verbatim**, le
  répertoire posé par la session compris. `gate_frontier_residue` — la seule chose
  qui puisse refuser d'armer — ne rend rien : son périmètre est la configuration
  git partagée.
- **`R5c`.** `gate_config_keys` a 53 entrées. `PATH` est lu **une seule fois** dans
  tout le pack : `scheduler.sh:322`, pour le recopier dans la file.

## Ce qu'il faut savoir avant d'ouvrir ce code

- **`claude` est la même porte et elle est pire.** Le pack le lance par son nom nu.
  Un `claude` interposé possède toutes les sessions **et** toutes les lentilles de
  revue du run suivant, c'est-à-dire les deux moitiés du jugement.
- **Un `git` interposé ne contourne pas les contrôles du pack, il les fabrique.**
  Le verrou d'arbre ([22]) lit `rev-parse --git-dir`, la frontière de visibilité
  ([30], [41], [46]) lit `config --get` et `check-ignore`, l'arbre jugé ([21],
  [29]) est un `add`/`write-tree`. Un témoin bâti *avec* git ne peut pas témoigner
  *contre* git.
- **La différence avec « une session peut exécuter du code ».** Ça, c'est assumé au
  niveau du pack ([20], `--dangerously-skip-permissions`). Ce ticket porte trois
  choses de plus, et ce sont exactement celles qui ont fait de [46] un ticket :
  l'écriture **survit au rollback** (hors de tout arbre jugé), elle **s'exécute
  dans l'arbre de process du pilote** et non dans la session, et elle **traverse le
  redémarrage** jusqu'à un run que personne ne regarde.
- **Le témoin de [15] ne couvre pas ça.** Il regarde `.claude/*` dans l'arbre
  principal et dans le `$HOME` de l'opérateur — ce qu'un `claude` frais *charge*.
  Un répertoire du `PATH` n'est pas chargé, il est *exécuté*.
- **Ne pas armer un vrai binaire dans une sonde sans passthrough.** Le `git` planté
  par `R5a` réexécute le vrai ; un shim cassé ferait rougir la suite au lieu de
  mesurer la portée.

## Ce que [53] a laissé ici (livré le 30/08/2026)

- **La ligne mise en file a changé de forme.** Elle ne finit plus par une
  redirection : elle exécute `bash -c '<scheduler__wake>' ralph-successor <log>
  <repli> <loop.sh>`. `scheduler__wake` est le **préflight du job** — le shell qui
  tourne avant `loop.sh`, donc avant tout préflight et tout gate du pack — et
  c'est l'endroit prévu pour ce que ce ticket doit vérifier au réveil. Le
  commentaire de la fonction le dit ; y loger la réponse plutôt que d'en bâtir une
  seconde.
- **Trois contraintes pour y ajouter quelque chose** : la sortie doit rester **une
  seule ligne** (le shim d'`at` enregistre `command: <une ligne>` et les tests
  relisent par `sed`) ; les chemins arrivent en positionnels — `$1` le log, `$2`
  le repli, `$3` `loop.sh` — donc un argument ajouté décale la numérotation, à
  mettre **après** `$3` ; le shell du job est bash par chemin absolu et pas `sh`.
- **`scheduler.sh:322` a bougé.** Le `PATH` est toujours lu une seule fois, dans
  `scheduler_command`, mais le numéro de ligne de `R5c` est périmé.
- **La ligne porte maintenant `FEATURE` aussi**, et le refus d'armer a un code de
  retour par raison (`scheduler_outcome` en fait un mot de journal). Un refus
  d'armer que ce ticket ajouterait prend **un code neuf** et un mot neuf, pas un
  des cinq existants.

## Ce qui a été livré, le 30/08/2026

**La décision : (a) et (b), tirés d'une seule mesure — et (c) réduit au seul
sous-cas qu'aucun témoin ne peut couvrir.** Ce ne sont pas trois sorties
cumulées par réflexe, c'est une mesure et deux consommateurs, plus un refus qui
répond à une question différente.

- **(a) le témoin.** `gate_path_witness` prend la ligne de base dans le
  répertoire-témoin du run (`gate_frontier_common`, `$TMPDIR`, jamais exporté),
  avant la première session. `gate_path_drift` la rejoue à la fin de chaque
  itération et rend `sujet<TAB>issue<TAB>message` — un `receipt_gap` **et** une
  ligne de `run.log` qui traverse par le slot. C'est [46] sur [15] repris tel
  quel : le reçu n'existe que sur quatre routes, donc une itération qui finit sur
  un retry frais n'en produit aucun, et un run qui *s'arrête* là n'a pas
  d'itération suivante pour en produire un. Ne rougit rien, ne défait rien.
- **(b) le refus d'armer.** `scheduler_arm` prend un cinquième argument,
  `gate_path_residue` lu par le pilote sur le même témoin, rend **6** et
  `scheduler_outcome` en fait `successor-blocked-path`. **Posé avant le refus de
  résidu**, et ce n'est pas cosmétique : `gate_frontier_residue` demande à *git*
  ce que la configuration de git dit, donc un `git` interposé ne franchit pas ce
  contrôle — il en écrit la réponse. Refuser sur le résidu d'abord, c'est refuser
  la nuit pour la raison que la plante a choisi de donner.
- **(c) refusé comme sortie, sauf sur un sous-cas.** Un préflight qui refuserait
  un `PATH` pointant dans l'arbre refuserait `node_modules/.bin`, c'est-à-dire
  `npm run`, c'est-à-dire une façon ordinaire de démarrer un run — et un
  répertoire **absolu** sous l'arbre du projet est surveillé par (a) comme un
  autre. Ce qui est refusé est l'entrée **vide ou relative** (`.`, `..`, `bin`,
  le vide qu'un deux-points en trop laisse) : elle ne nomme pas *un* répertoire,
  elle en nomme un différent dans chaque shell que le pack démarre — le pilote,
  le worktree d'une itération, le `bash -c` de `TEST_CMD`, le shell du job d'un
  successeur. Aucune ligne de base ne peut la couvrir, donc `gate_path_preflight`
  refuse (`exit 2`) au lieu de la mesurer malhonnêtement.

**Où la barre est posée, et pourquoi elle est calculée.** Le témoin évident —
les *répertoires* du `PATH` — est faux deux fois : il surveille des milliers de
fichiers que le pack n'exécute jamais (donc n'importe quel `brew upgrade` le
remue : du bruit, sur un canal dont la conséquence est de refuser un successeur),
et il ne dit toujours pas **quel programme a répondu**. Ce qui est surveillé est
donc la **résolution et le contenu des noms que le pack exécute** :
`gate_path_programs`, 32 noms dérivés du critère « ce que ce pack lance par son
nom nu et croit ensuite ». Les *builtins* de bash en sont absents et c'est le
critère et pas un oubli — `printf`, `read`, `test`, `[`, `kill`, `command` sont
résolus par le shell et jamais par `PATH`, donc aucun fichier ne peut s'y
substituer ; `kill` apparaît trente-sept fois dans le pack et n'est pas
substituable.

**`scheduler_command` : un refus, pas une phrase.** Le commentaire dit maintenant
ce qu'il transmet vraiment, et pourquoi la réponse n'est pas dans
`scheduler_caveat` : une phrase à côté d'un job qui a été mis en file quand même
est une phrase que personne n'est là pour lire — et n'être personne est toute la
prémisse de [09]. L'en-tête du module a une quatrième entrée dans « ce que la
ligne mise en file porte ».

## Le piège qui a coûté le plus, et il est dans l'instrument lui-même

**`command -v` et `type -P` répondent depuis la table de hachage de bash.** Le
pilote a résolu `git` bien avant que la première session existe ; un témoin bâti
sur `command -v` rend donc « rien n'a bougé » **exactement sur le run dont le
successeur exécutera la plante**. Mesuré en livrant : le premier jet du témoin
utilisait `command -v`, le test bout-en-bout de la plante est sorti rouge sans
qu'aucune ligne de dérive n'apparaisse, et la cause est la même phrase que la
sonde `R5a` avait déjà écrite pour le pack (« bash hashe ») — reproduite une
couche plus bas, dans l'outil censé la détecter.

Reproduction en trois lignes (`PATH` inchangé, donc la table n'est pas vidée) :

```bash
export PATH="$PWD/d:$PATH"      # d/ est vide
git --version >/dev/null        # ce shell hashe /usr/bin/git
printf '#!/bin/sh\nexit 0\n' >d/git; chmod +x d/git
command -v git                  # /usr/bin/git      ← la table
bash -c 'command -v git'        # $PWD/d/git        ← un shell frais
```

`hash -r` corrigerait la réponse **et achèterait le défaut avec** : le shell qui
vide sa table est celui qui exécute ensuite ce qu'il vient de trouver. La
recherche est donc faite à la main sur `PATH` (`gate__path_where`), ce qui a un
second effet voulu : la fonction n'exécute rien, ce qui est ce qui permet à
`gate_path_preflight` de tourner *avant* le premier programme du pack.

Le test qui l'épingle demande les deux réponses côte à côte (`hash-says` /
`search-says`) et exige qu'elles diffèrent — c'est la seule forme qui rougit
quand on revient à `command -v`.

## Écarts, décisions et pièges

- **`loop.sh` calcule `RALPH_DIR` par expansion de paramètre au lieu de
  `dirname`.** Sans ça, la garantie « le refus arrive avant que le pack n'exécute
  un programme par son nom » est fausse du fichier lui-même : `dirname` était le
  premier programme résolu à travers le `PATH` refusé, trois douzaines de lignes
  avant que quoi que ce soit puisse le dire. `cd` et `pwd` sont des builtins. Le
  test le mesure avec deux enregistreurs (`git`, `dirname`) en tête de `PATH` et
  un témoin appairé qui vérifie que les mêmes enregistreurs **tournent** quand le
  `PATH` est absolu — sans lui, un préflight qui refuserait tout passerait aussi
  bien.
- **`gate_path_preflight` est appelé hors de `loop_preflight`**, en première
  ligne de `loop_main` : `loop_preflight` résout déjà le répertoire de la feature
  (donc `git`) avant de décider quoi que ce soit. Même code de sortie (2).
- **Écart de write-surface** : `.claude/lib/capability.sh`,
  `.claude/ralph.config.sh.example` et `test/capability.bats` étaient déclarés et
  n'ont pas été touchés. `capability.sh` est le *modèle* (témoin, jamais un
  contrôle) et pas le propriétaire : son critère est « ce qu'un `claude` frais
  *charge* », celui-ci est « ce que le pack *exécute* ». Le propriétaire est
  `gate.sh`, qui porte déjà « qui décide de ce que git exécute » ([46]) et
  `gate_frontier_residue`, le producteur du refus d'armer. **Aucune clé de
  configuration n'a été ajoutée, et c'est voulu** : une clé serait un interrupteur
  pour éteindre ce contrôle, et ce tableau existe pour refuser cette forme.
- **Rien n'a été logé dans `scheduler__wake`**, et le commentaire de la fonction
  le dit pour que la question ne soit pas rouverte au jugé. Sa règle (« tout ce
  qui doit être vrai avant qu'on fasse confiance à `loop.sh` ») est respectée par
  l'autre bout : `loop.sh` *peut* poser cette question-là avant d'exécuter quoi
  que ce soit, donc une copie dans la ligne mise en file serait une seconde
  orthographe d'une règle et une seule des deux serait sous test. Ce qui, lui, ne
  peut pas être vérifié depuis le job est l'autre moitié — « ces programmes
  sont-ils ceux que le run mourant avait » — parce que la ligne de base est morte
  avec le run qui l'a prise. D'où un refus d'armer et pas un contrôle au réveil.
- **Coût mesuré** : ~0,9 s par témoin sur cette machine, dominé par le `cksum` du
  binaire `claude` (325 Mo). Une fois au démarrage du run, une fois par itération.
  Une itération dure des minutes ; dans la suite, `claude` est un shim de 18 Ko et
  c'est gratuit. Le contenu et non les métadonnées, par cohérence avec
  `gate__digest` et `capability__digest`, et parce qu'une empreinte
  taille+mtime se rejoue avec un `touch -r`.
- **Un défaut de cette livraison, trouvé en posant la question 5 sur elle-même.**
  `-` est la réponse pour un nom qu'aucun répertoire du `PATH` ne porte, et
  `[ -f - ]` est **vrai** dans un répertoire courant qui contient un fichier
  nommé `-` — qu'une session écrit d'une redirection de travers, dans le worktree
  même où `gate_path_drift` tourne. Sans garde, tous les noms absents de la
  machine (`systemd-run` sur macOS) se seraient mis à digérer *ce fichier-là* : une
  ligne de dérive accusant un programme que personne n'a touché, et un successeur
  refusé pour ça. C'est le défaut de [49] — une note qui accuse une session qui
  n'a rien écrit — atteint par une autre porte. Le digest n'est donc demandé que
  d'un chemin **absolu**. Trouvé avant le premier gate complet, en relisant la
  livraison avec la question de la frontière plutôt qu'après.
- **Ce que le témoin lui-même expose** : il vit dans le répertoire-témoin du run
  (`$TMPDIR`, nom `mktemp`, jamais exporté) — le même secret que le pin d'ignore
  ([30]) et le registre ([40]), donc la même exposition et pas une nouvelle. Une
  session qui en connaîtrait le nom réécrirait `path` pour faire correspondre sa
  plante. Et dans l'autre sens, une session qui *ajouterait* une ligne fausse
  achèterait un refus d'armer — la nuit finit avec un humain, le côté prudent, la
  même direction que le marqueur forgé de [09].
- **Une seconde entrée refusée au préflight, et elle ne vient pas d'une menace.**
  Une entrée de `PATH` dont le nom porte une **tabulation ou un saut de ligne** ne
  peut pas voyager dans le témoin, qui est tabulé : `/dir<TAB>x/git` se relit
  comme trois fragments de deux champs, la comparaison ne retombe plus jamais
  juste, la ligne de dérive part à chaque itération et plus aucun successeur n'est
  armé sur cette machine — en silence. Une session ne peut pas changer le `PATH`
  du pilote, donc ce n'est pas une porte : c'est la posture de [39], nommer ce
  qu'on ne sait pas adresser plutôt que faire semblant. Le piège d'écriture
  correspondant est consigné : `nl="$(printf '\n')"` est la **chaîne vide** (une
  substitution de commande retire tous les sauts de ligne finaux) et une aiguille
  vide matche *toutes* les entrées — le refus refuserait la machine. La variable
  porte donc un saut de ligne littéral, et une mutation le vérifie.
- **Quatorze mutations, toutes `ok`, aucune VACUOUS.** Elles couvrent
  les deux moitiés de la mesure (résolution, contenu), les deux consommateurs
  (dérive, refus d'armer), les deux moitiés du câblage (pilote, scheduler), les
  trois moitiés du préflight (l'appel, *quand* il arrive, et la clause qui refuse
  l'entrée intransportable), l'aiguille du saut de ligne, le `case` qui rend
  l'entrée vide visible, le garde du `-`, le sujet de la ligne de journal, et
  `claude` dans la liste.
- **Une mutation refusée** : retirer le `:` sentinelle de
  `gate_path_preflight` (`list="${PATH:-}:"`) est une **condition de terminaison**
  — sans lui `${list#*:}` sur une chaîne sans deux-points rend la chaîne
  inchangée, donc une boucle infinie et un `mutate.sh` bloqué avec un défaut
  planté dans l'arbre. C'est le cas que l'en-tête de `mutate.sh` décrit. La même
  garantie est mutée par l'autre bout : le `case` qui accepte l'entrée vide.
- **Les tests ne peuvent pas planter un vrai `git` cassé.** Toutes les plantes de
  ce ticket sont des passthrough (`exec "$real" "$@"`), comme la sonde `R5a` :
  un shim cassé ferait rougir la suite au lieu de mesurer la portée.

## Ce que ça laisse au ticket suivant

- **La liste est une dette, la même que `gate_config_keys`.** Un site d'appel
  ajouté au pack dans un programme absent de `gate_path_programs` rouvre le trou
  sans que rien le remarque. C'est écrit aux deux endroits.
- **Le témoin est par run.** Une plante déjà là au démarrage *est* la ligne de
  base : elle ne sera jamais nommée. Limite structurelle de tout témoin, que [15]
  porte déjà, et la raison pour laquelle le refus d'armer compte plus que la
  ligne de reçu — il empêche la chaîne automatique, il ne guérit pas la nuit
  d'avant.
- **`cksum` est sur la liste parce que le témoin est calculé avec.** Une plante
  qu'un run antérieur a laissée fabrique ce manifeste. Même phrase que « un
  témoin bâti avec git ne témoigne pas contre git », un cran plus bas.
- **La sonde `R5a`/`R5b` est périmée dans sa question** : `R5b` cherchait
  `gate_frontier_residue` comme « la seule chose qui puisse refuser d'armer ».
  Il y en a deux maintenant, et c'est la seconde qui répond. La sonde reste
  utile pour `R5a` (la portée du run suivant), qui n'a pas changé et ne changera
  pas : rien ici ne défait une plante.

## Les deux gates, le 30/08/2026

- `bash test/run.sh` = **598 tests, 0 failures, 6 skips opt-in** (base de [53] :
  584 ; +14, dont 10 dans `gate.bats` et 4 dans `scheduler.bats`).
- `bash test/mutate.sh` = **579 mutations, 1 not ok** (base : 565 ; +14).
- Le seul rouge est `VACUOUS 23 the wall clock restarts whenever the session
  writes`, et il est **disculpé** : rejoué **4 fois sur 4 en isolé, `ok`** — donc
  le test a bien ses dents sur cette branche, ce qu'un test rendu creux par la
  branche ne pourrait pas avoir — et la branche ne touche **ni** le fichier muté
  (`.claude/lib/monitor.sh`) **ni** le test (`test/smart-zone.bats`),
  `git diff --stat` sur ces deux chemins étant vide. C'est la famille consignée
  des tests à deadline, dont un VACUOUS se rejoue seul avant d'être lu comme une
  régression. Pas de charge artificielle pour reproduire : les gaps de cette
  famille sont du wall-clock, pas du CPU.
