# 62 — `gate__tmp_leftovers` compte six des dix-huit noms que le pack pose dans `$TMPDIR`

**What to build:** Dériver la liste de `gate__tmp_leftovers` de son critère plutôt que de la recopier à la main, et écrire le résultat là où [19] le lira comme spécification de balayage.

**Blocked by:** None

**Write-surface:** `.claude/lib/gate.sh`, `test/gate.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** resolved

**Tags:** observability, gate

- [x] La liste de `gate__tmp_leftovers` couvre **tous** les noms de premier niveau que le pack pose dans `$TMPDIR`, ou bien elle est dérivée d'un motif unique et le prix de ce motif est écrit (`$TMPDIR` est partagé avec d'autres dépôts et avec `ralph-test.*`). — **La liste**, `gate_tmp_names`, dix-sept globs pour dix-huit producteurs ; le motif unique examiné et refusé, prix écrit dans le code et au tableau.
- [x] Un test qui **rougit quand un producteur est ajouté sans être couvert** — pas une liste de dix-huit assertions recopiée à côté de la liste du code, qui serait le même défaut une couche plus haut. La forme évidente est un balayage de `.claude/**` à la recherche des `mktemp` de premier niveau, comparé à ce que le contrôle attrape (modèle : `gate_config_keys` et ses 53 entrées).
- [x] La phrase dit encore la vérité : elle annonce des « temporary director(ies) » et compte aussi des fichiers (`ralph-slot.writes.*` est déjà dans ce cas aujourd'hui).
- [x] Entrée de mutation par garantie livrée, plus le témoin appairé.
- [x] La note pour [19] est écrite **dans [19]**, pas seulement ici.

## Comments

- **Trouvé par la passe transversale du 05/09/2026** (`../passe-transversale-05-09.md`, §1). Sondes : `../sondes/passe-05-09/q1-*.bats`.

- **Le critère est dans la phrase, la liste est à côté.** Le message dit : « N temporary director(ies) **from earlier runs** are still in `$TMPDIR`: **a run killed mid-iteration leaves one behind**, and nothing here removes them ». La liste énumère cinq motifs — `ralph-gate.*`, `ralph-ignore.*`, `ralph-worktree.*`, `ralph-slot.*`, `ralph-frontier.*` — et `grep -rn mktemp .claude/` en donne dix-huit au premier niveau de `$TMPDIR`. Forme exacte de [31] (un scellement plus étroit que son critère) et de [45] (un reçu avec moins de producteurs que son critère).

- **Mesuré, un nom par run, vieilli de 25 h** (`q1` Q1a) — 6 vus, 12 non :

  | vu | nom | producteur |
  |---|---|---|
  | ✅ | `ralph-slot.*` | `loop.sh:1087` |
  | ✅ | `ralph-slot.writes.*` | `loop.sh:1396`, par le glob du précédent |
  | ✅ | `ralph-frontier.*` | `gate.sh:656` |
  | ✅ | `ralph-ignore.*` | `gate.sh:764` |
  | ✅ | `ralph-gate.*` | `gate.sh:3130` |
  | ✅ | `ralph-worktree.*` | `concurrency.sh:298` |
  | ❌ | `ralph-receipt.*` | `receipt.sh:100` — **un répertoire** |
  | ❌ | `ralph-retro.*` | `retro.sh:164` — **un répertoire** |
  | ❌ | `ralph-playthrough.*` | `playthrough.sh:699` — **un répertoire**, [11] |
  | ❌ | `ralph-spec.*` | `playthrough.sh:229` — le témoin du flux, [11] |
  | ❌ | `ralph-tracker.*` | `failures.sh:764` |
  | ❌ | `ralph-failed.*` | `failures.sh:1029` |
  | ❌ | `ralph-durable.*` | `failures.sh:1112` |
  | ❌ | `ralph-reslice.*` | `failures.sh:1259` |
  | ❌ | `ralph-index.*` | `gate.sh:2224` |
  | ❌ | `ralph-restore.*` | `gate.sh:2441` |
  | ❌ | `ralph-fold.*` | `concurrency.sh:533` |
  | ❌ | `ralph-refresh.*` | `concurrency.sh:652` |

- **Run réel** (`q1` Q1b) : un run tué au `KILL` pendant le gate laisse **neuf** entrées, le contrôle en compte **six**. Les trois muettes sont `ralph-receipt.*`, `ralph-retro.*` et `ralph-spec.*`. **Témoin appairé** (Q1c) : un run qui finit normalement laisse **zéro**, donc ce qui reste est bien ce que le critère décrit. Trois des muettes sont des **répertoires** — l'échappatoire « la phrase dit *director(ies)* » ne tient pas, elle en compte six et en laisse trois du même genre. Et deux des trois muettes du run réel sont des livraisons de **[11]** : la dérive est en train de se faire, ce n'est pas un héritage ancien.

- **Ce que ça coûte aujourd'hui, chiffré ailleurs.** Le balayage de `$TMPDIR` en fin de ticket est fait à la main dans ce dépôt (mesure du 03/09/2026 : `1,0 Go → 49 Mo`, environ 1 Go de résidus par ticket, dont l'essentiel vient du harnais de test et non du pack). Ce ticket ne balaie rien — `gate_leftovers` **dit et ne balaie pas**, c'est une décision écrite —, il rend le compte honnête.

- **Piège à ne pas répéter.** `-mtime +0` veut dire *strictement plus de 24 h* : un test qui pose un résidu et l'interroge tout de suite mesure `0` quelle que soit la liste. Vieillir avec `touch -t` (`date -v-25H`).

- **Ce que le motif unique coûterait, à mesurer avant de le choisir.** `ralph-*` attraperait aussi `ralph-test.*` (le répertoire du harnais de test lui-même) et les résidus des runs d'autres dépôts sur la même machine — ce qui est déjà vrai des six noms actuels et que le commentaire assume explicitement (« a directory nobody has touched in twenty-four hours belongs to no run that is still going »). Le choix à écrire est donc : dériver le motif, ou dériver la liste, et dans les deux cas ce qui rougit quand un producteur est ajouté.

- **Place dans la file, validée par Philippe le 05/09/2026 : deuxième**, après
  [63] et avant [65], [64], [18], [19]. La raison n'est pas l'arête vers [19] mais
  ce que ce ticket livre : **le contrôle qui rougit quand un producteur est ajouté
  sans être couvert**. Installé tôt, il travaille pour les quatre tickets qui
  suivent — [18] en particulier, qui a toutes les chances d'ajouter un `mktemp`
  (un backend distant qui cache des réponses). Installé juste avant [19] seulement,
  il arriverait après le producteur qu'il aurait dû attraper. `[19] Blocked by:`
  porte maintenant `62`.

## Livraison (05/09/2026)

- **Ce qui est livré.** `gate_tmp_names` — dix-sept globs, publics, pour les
  dix-huit producteurs du pack (`ralph-slot.*` attrape `ralph-slot.writes.*`,
  que le pilote écrit à côté du slot) — et `gate__tmp_leftovers` qui construit son
  expression `find` à partir de cette liste au lieu de la porter en dur. La phrase
  dit maintenant `N temporary file(s) and director(ies) from earlier runs are
  still in …` : elle comptait des fichiers depuis [05] (dix des dix-huit appels
  sont des `mktemp` sans `-d`) en annonçant des répertoires.

- **La décision demandée par le ticket, tranchée : la LISTE, pas le motif, et le
  prix du motif est écrit** (dans `gate.sh`, dans le tableau de
  `docs/frontiere-de-confiance.md`, et dans [19] qui balaiera). `ralph-*`
  couvrirait gratuitement un producteur ajouté demain — ce qui est exactement ce
  que le test livré ici doit garantir autrement — mais cet espace de noms a **deux
  écrivains** : le pack et son propre harnais de test. `ralph-test.*` par test,
  `ralph-mutate.*` par passe de mutation, `ralph-contract.*`, et surtout
  `ralph-harness.*`, le cache de templates que la suite garde **sept jours à
  dessein** (`test/helpers/harness.bash`, `find -mtime +7`). Un `ralph-*` rendrait
  donc deux choses fausses : la ligne du matin compterait un cache **vivant**
  comme le débris d'un run tué, et le nombre qu'elle imprime dépendrait de l'âge
  du cache de la machine — sur ce dépôt-ci, le seul où le harnais existe, mais
  c'est le dépôt où le pack est développé.

- **La dérivation à l'exécution a aussi été refusée, et pour la raison la plus
  ancienne du document de frontière.** `gate__tmp_leftovers` aurait pu relire les
  `mktemp` de `.claude/**` à chaque run : ce serait la même liste dérivée une
  couche mieux. Mais la source du pack est dans l'arbre qu'une session écrit, et
  un contrôle qui lit un fichier qu'une session peut écrire n'est pas un contrôle.
  La dérivation vit donc dans le test, qui tourne sur la source livrée.

- **Le test qui rougit quand un producteur est ajouté** (`every name the pack puts
  at the top of TMPDIR is counted by the sweep list`, `test/gate.bats`). Trois
  étapes, aucune ne recopie la liste : il lit les `mktemp` du pack **déposé**
  (`$PACK_DIR`, commentaires écartés) ; il fait **résoudre chaque expression par
  le pack lui-même** dans un `pack_run` avec `TMPDIR` pointé sur un bac à sable —
  c'est ce qui lui fait voir `concurrency_worktree_path`, dont le chemin sort
  d'une fonction (`$(concurrency__prefix)XXXXXX`) et qu'un scan textuel raterait
  **en silence**, donc dans la direction qui rend vert ; puis il pose chaque nom
  de premier niveau, seul, dans un répertoire vide, le vieillit de 25 h et demande
  au contrôle. Il vérifie aussi les deux autres bords : un `mktemp` écrit dans une
  forme qu'il ne sait pas lire est une **erreur** et non un silence, et un nom de
  `gate_tmp_names` que plus aucun appel ne produit rougit également (une liste
  peut être fausse des deux côtés).

- **Les deux limites du test sont écrites dedans, pas découvertes plus tard.** Il
  ne voit que les `mktemp` — d'où le second test, `only a mktemp call composes a
  top-level name in TMPDIR`, qui refuse qu'une ligne du pack compose
  `${TMPDIR:-/tmp}/<nom>` ailleurs que dans un appel `mktemp`. Et il ne voit pas
  un chemin composé en **deux temps** (le répertoire dans une variable sur une
  ligne, le nom sur la variable à la suivante) : écrit dans le test, écrit au
  tableau, écrit dans [18] et [19] qui sont les deux tickets en position de le
  faire. La résolution laisse les variables non liées se développer en vide, ce
  qui classe `$RALPH_RETRO_STATE/read.*` comme « pas au premier niveau » — ce
  qu'il est réellement, puisqu'il vit *dans* `ralph-retro.*`.

- **Sonde du run réel rejouée sur le code livré** (`../sondes/passe-05-09/q1`) :
  Q1b, un run tué au `KILL` pendant le gate laisse **9** entrées et le contrôle en
  compte **9** (c'était 6). Témoin appairé Q1c : un run qui finit normalement
  laisse toujours **0**, donc l'élargissement n'a pas transformé le compte en
  bruit. Le README des sondes porte la mesure d'après-correctif à côté de celle
  d'avant.

- **Six entrées de mutation, une par garantie, dans les deux directions.** Liste
  trop étroite (`ralph-receipt.*` retiré) et liste trop large (`ralph-nothing.*`
  ajouté) ; producteur ajouté sans ligne dans la liste et producteur ajouté
  **hors** d'un `mktemp` — les deux visent `state.sh` et y **ajoutent une fonction
  que personne n'appelle**, parce que ce qui doit être vu est la présence dans la
  source, pas un comportement ; la liste vidée (`gate_tmp_names` qui rend zéro
  nom, donc un contrôle muet) ; et le compte restreint aux répertoires, qui est la
  lecture que l'ancienne phrase décrivait. Les deux entrées `36` existantes
  (`nothing names what earlier runs left in TMPDIR`, `a run beside this one is
  counted as a leak`) ont été **rejouées pour de vrai** et restent `ok` : l'ancre
  du `-mtime +0` n'a pas bougé.

- **Piège confirmé, celui que le ticket nommait.** `-mtime +0` veut dire
  *strictement* plus de 24 h : un résidu posé et interrogé dans la même seconde
  est compté par personne, quelle que soit la liste. Le test vieillit avec
  `touch -t "$(date -v-25H …)"`. Un test écrit sans ça aurait été vert avec les
  dix-sept noms **et** avec les six.

- **Écarts de write-surface, assumés.** Déclarée : `.claude/lib/gate.sh`,
  `test/gate.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md` — tous les
  quatre touchés. En plus, quatre artefacts de `.scratch/` qu'aucun code ne lit :
  [19] (exigé par les AC), [18] (le producteur que ce ticket a été avancé pour
  attraper), [36] (dont un commentaire cite la phrase qui a changé de texte) et le
  README des sondes.

- **Un constat qui n'appartient pas à ce ticket, écrit dans [16].**
  `human-loop.sh` n'appelle pas `gate_leftovers` : un drainage humain démarré
  après un run tué ne nomme aucun résidu — ni `$TMPDIR`, ni les gardes morts de
  [49], ni le successeur de [53] — alors que c'est la situation même où un humain
  vient voir ce qui s'est passé. Même racine que [55]/[56]/[57]. Inerte, donc pas
  un faux vert : c'est un silence, et il mérite une passe transversale plutôt
  qu'un élargissement de write-surface décidé ici.

- **Les deux gates, mesurés d'un bloc sur le code livré** : `bash test/run.sh` =
  **721 tests, 0 failures, 6 skips** (719 + 2 nouveaux ; les 6 skips sont les
  opt-in réseau/binaire réel, aucun dans le canari) et `bash test/mutate.sh` =
  **718 mutations, 0 not ok** (712 + 6). Arbre propre après coup, aucun défaut
  planté. Nouvelle baseline pour le ticket suivant. Le premier `run.sh` a été
  **jeté et relancé** : un commentaire de `gate.sh` avait été corrigé pendant
  qu'il tournait, et un gate mesuré à cheval sur deux versions du pack ne mesure
  rien.

- **Contraintes écrites ailleurs** : [19] (la spécification du balayage est
  `gate_tmp_names`, publique ; l'appeler et non la recopier ; le seuil d'âge est
  une contrainte ; `ralph-*` refusé et pourquoi ; `init.sh` est **hors**
  `.claude/**` donc invisible à la dérivation), [18] (tout `mktemp` de premier
  niveau d'un backend distant doit avoir sa ligne, et les deux formes qui
  échappent encore), [36] (la phrase a changé de texte), [16] (`human-loop.sh` ne
  dit rien des résidus).
