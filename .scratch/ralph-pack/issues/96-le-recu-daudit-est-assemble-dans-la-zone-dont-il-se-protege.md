# 96 — Le reçu d'audit est assemblé dans la zone dont il se protège

**What to build:** Que le reçu d'audit — le seul document durable que la nuit produit sur elle-même — soit assemblé hors de portée de ce dont il rend compte, ou qu'il cesse d'affirmer dans son propre texte une garantie qu'il ne tient pas.

**Blocked by:** 94

**Write-surface:** `.claude/lib/receipt.sh`, `.claude/lib/gate.sh`, `test/receipt.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md` — **plus, écart déclaré en livrant** : `.claude/lib/session.sh` (le seul point de passage de `claude`, qui doit fermer le canal), `.claude/loop.sh` (la prose qui décrivait le workspace, fausse depuis ce ticket) et `test/smoke.bats` (la ligne de la liste hermétique qui décrivait `RALPH_RECEIPT` comme un chemin)

**Status:** resolved

- [x] Le **workspace** du reçu n'est plus tenu par un nom. C'est un `mktemp -d "$TMPDIR/ralph-receipt.XXXXXX"` et « un nom n'est pas une garde » est la racine de la passe du 10/09, payée par [80] et [81]. Ses pièces sont quatre fichiers texte — `facts`, `notes`, `gaps`, `branch.<nom>` — et `receipt__fact` lit la **dernière** occurrence, donc un `>>` suffit.
- [x] La **source** que le reçu cite (`$dir/<branche>.out`, via `receipt_keep_branch`) est celle que [94] aura traitée : ce ticket hérite de cette décision au lieu d'en prendre une seconde.
- [x] La **phrase que le document imprime sur lui-même** dit la vérité après réparation. Aujourd'hui il se termine par *« Assembled by the process that measured this iteration … It does **not** read `run.log` … so the session this receipt is about can rewrite it »* — une phrase qui oppose une garantie au journal tout en rangeant ses propres pièces dans la zone voisine. Même chose pour les trois paragraphes de tête de `lib/receipt.sh` : *« None of those is reachable from a session's write-surface »* est faux aux deux moitiés.
- [x] La ligne « Un reçu d'audit dit ce qui s'est vraiment passé » du tableau est réécrite avec ce qui la tient réellement.
- [x] Les tests mettent en scène un **survivant réel** et assertent le contenu du reçu **déposé** (`receipts/<feature>/<id>.md`), pas l'état d'un workspace. Témoin appairé obligatoire.
- [x] Une entrée de mutation par garantie livrée, avec son témoin appairé.

## Comments

- **Ouvert par la passe transversale du 23/09/2026** (`../passe-transversale-23-09.md`, §3). Sonde : `../sondes/passe-23-09/q4-le-recu-daudit.bats`.

- **Ordre VALIDÉ par Philippe le 23/09/2026** : **[95] → [94] → [96]**. Ce ticket en dernier parce qu'il cite `$dir/<branche>.out` comme source : ce qui lui reste en propre — son workspace et la phrase qu'il imprime sur lui-même — n'appartient qu'à lui.

- **Mesuré**, suite rouge, le reçu déposé dans `receipts/<feature>/01-alpha.md`. Témoin appairé, sans survivant : `tests=red`, findings `FAIL: 3 of 12 tests failed in src/alpha`, outcome `gate-red`. Avec un `nohup` laissé par la session qui écrit dans `$TMPDIR/ralph-receipt.*` : **`tests=green typecheck=green scope=green lang=green`**, findings *« the suite passed cleanly on the first attempt »*, outcome **`resolved`** — et le document forgé porte toujours sa propre phrase de garantie.

- **Le seul résidu qui trahit**, et il ne vaut pas une défense : `what the loop then did: escalated:failed-impl`, un fait écrit après la dernière forge du survivant. Un survivant qui couvrirait aussi ce fait ne laisserait rien. Ne pas construire la réparation sur « il reste une incohérence » : c'est un accident de séquence.

- **Ce qui distingue ce ticket de [94]** : ici rien n'est décidé. C'est ce qu'un humain lit **à la place** de ce qui s'est passé, et c'est le seul document qui survit à la nuit dans le dépôt. Une réparation qui se contenterait de le fiabiliser à moitié doit dire laquelle des deux moitiés elle tient.

- **La posture par défaut du pack, si le workspace ne peut pas sortir de `$TMPDIR`** : [39] — nommer ce qu'on ne sait pas adresser, et le nommer **à chaque tour** ([24]), pas une fois dans un document. Un reçu qui dirait dans son texte quelles de ses pièces sont à portée de l'itération dont il rend compte serait déjà plus honnête que celui d'aujourd'hui.

- **Ne pas chercher `RECEIPT_MAX_LINES`** : `receipt_preflight` refuse déjà au démarrage une valeur qui lit comme « off », et c'est la forme que [17] et [31] ont posée. Rien à rouvrir là.

- **Ce que [94] laisse, livré le 24/09/2026 — la décision dont ce ticket hérite est écrite.** `$dir/<branche>.out` **reste un fichier nommé** dans le répertoire du gate, et c'est une décision mesurée, pas un oubli. La borne évidente — la branche note la longueur de sa propre sortie, le parent refuse un fichier qui n'a plus cette longueur, la forme `grows` de [81] — a été **refusée sur mesure** : `proc_sweep` envoie un TERM à ce qu'une branche de commande a laissé tourner et dit lui-même qu'il ne le suit pas ([95]), donc un projet honnête dont le serveur de test log une ligne en s'arrêtant verrait ses constats refusés tous les matins. La raison est écrite au-dessus de `gate__report` et dans le tableau. Ce que ça borne : depuis [92] rien de ce fichier n'est un verdict, donc ce qu'un process qui y écrit achète est de la prose — dans le journal du matin et **dans ce reçu**. Donc : **ce ticket n'a pas à re-trancher le `.out`, il a à dire ce que son propre document vaut sachant que sa source de constats est celle-là.** Et `receipt_keep_branch` est l'autre lecteur : si ce ticket décide de nommer ce que le reçu ne tient pas, cette source est la première ligne à nommer.

- **Ce qui est neuf et réutilisable** : `gate_note` / `gate_noted` / `gate_notes_shut` (gate.sh) — un descripteur sur un fichier délié, hérité par une branche, fermé pour tout ce que le pack `exec` hors de lui-même. C'est le magasin à réutiliser quand un contrôle doit se méfier d'un fichier qu'une session peut écrire **et** que la réponse doit traverser un fork (le pendant de `RALPH_WITNESS_SEAL` de [81], qui ne traverse que dans le sens pilote → enfant). Le workspace du reçu, lui, est écrit par le **pilote** et lu par le **pilote** : le canal d'une branche ne s'y applique pas tel quel, mais la forme « ouvrir deux fois puis délier » si.

- **Livré le 27/09/2026.** Ce que le ticket avait supposé est faux, et c'est la
  trouvaille : « le workspace est écrit par le pilote et lu par le pilote, donc le
  canal d'une branche ne s'y applique pas ». **Le pack écrit dans le reçu depuis
  un sous-shell, et pas par accident.** Mesuré en instrumentant `BASH_SUBSHELL`
  sur les quatre écrivains et en passant six fichiers de la suite : **24
  écritures sur 5952** partent d'un niveau plus bas, par cinq chemins —
  `gate__gap` depuis `gate_tree_snapshot` (14, cinq appelants) et depuis
  `gate_restore_tree`, `tracker_local__open_refused` (6), `capability_drift` (3),
  `gate_path_drift` (1), plus `forensic_drift` que ce passage n'a pas exercé.
  La raison est toujours la même et elle est documentée à la ligne d'à côté : ces
  fonctions rendent leur réponse sur stdout, donc **tous** leurs appelants les
  prennent par une substitution de commande ([59]). Les jeter était la sortie la
  plus simple et elle est refusée : les trois phrases de dérive sont le seul
  compte-rendu qu'une itération donne d'une surface de capacité, d'un programme
  ou du document d'un humain qui bouge sous le run, et **[70] promet la sienne
  sur le reçu de l'itération en cours**.

- **Ce qui est livré, en deux objets et pas un.** Le store est
  `RECEIPT_STORE`, une **variable non exportée** du shell qui mesure : c'est
  l'asymétrie de [81] (une session hérite d'un environnement, pas d'un shell), et
  elle est hors de portée d'un `exec` par construction. Le canal est un
  `mktemp "$TMPDIR/ralph-receipt.XXXXXX"` **ouvert deux fois puis délié avant le
  premier octet** (`RECEIPT_CHANNEL_FD=5` / `RECEIPT_CHANNEL_BACK=4` — 3 est à
  `monitor_watch`, 7/6 au prompt de lentille, 9/8 aux notes du gate), la forme de
  [94]. **Toutes** les écritures passent par le canal, y compris celles du shell
  qui a ouvert le reçu, et `receipt__take` le rembobine dans la variable à chaque
  appel de ce shell-là : un store à deux entrées aurait laissé la rare — celle du
  sous-shell — exercée par presque rien. Ordre préservé, et pas de fork :
  `receipt__take` est un `read` builtin sur un fichier régulier.

- **Le prix du descripteur, mesuré avant d'être écrit** : un programme `exec`é
  hérite du bout écrivain et **forge un enregistrement en un `printf`** (mesuré
  sur bash 3.2.57, comme le reste : fermer un fd non ouvert rend 0, un drain
  incrémental par `read <&4` prend exactement ce qui est neuf, et
  `shut_exec cmd &` garde le pid du programme — donc le `$!` de `session_spawn`
  reste honnête). D'où `receipt_shut` / `receipt_shut_exec` à **deux** sites :
  `gate__command_branch` (les deux branches de commande du projet) et
  `session_spawn` (**tout** `claude` : session de livraison, lentille, retro,
  re-slice — un seul point de passage, donc un seul appel).

- **Le troisième site du recensement de [95] ne prend rien, et c'est une
  décision assertée** : `playthrough_close` tourne dans le **pilote**, qui
  n'ouvre aucun reçu — il n'y a pas de descripteur à donner. Un garde posé là
  aurait été un nom sans garantie. Le test « the playthrough's command line runs
  where no receipt is open » le mesure, donc **un ticket qui déplacerait le
  playthrough dans une itération sera prévenu par un rouge** au lieu de livrer une
  fuite.

- **Piège de harnais, et il a coûté un faux rouge avant d'être compris** : la
  question « ce process tient-il le descripteur ? » ne se pose **pas** par
  `ls /dev/fd`, comme [94] la pose un étage plus bas. `ls` ouvre le répertoire
  qu'il va lire, ce qui prend **le plus petit descripteur libre** — c'est-à-dire
  exactement le numéro sous test une fois que le pack l'a fermé. Mesuré sur un
  pack correct : la liste rend `0 1 10 11 2 3 4` et accuse 4, qui est la poignée
  d'`ls`. Les quatre tests demandent donc par **écriture** : ce qu'un forgeur a
  besoin de faire n'est pas de voir le descripteur, c'est d'écrire dessus. À
  savoir pour tout ticket qui reprend cette mise en scène sur des fds bas.

- **La phrase du document et la prose de tête disent maintenant les deux
  moitiés.** La forte : assemblé nulle part qu'un nom atteigne. La faible, à
  chaque itération et non une fois dans un document ([24], [39]) : la sortie de
  branche citée sous *Findings* vient de `$dir/<branche>.out`, un fichier nommé
  qu'un process de ce run peut écrire — la borne a été refusée sur mesure par
  [94] — et comme depuis [92] rien de ce fichier n'est un verdict, ce qu'un tel
  process achète est **la prose de cette section, jamais une couleur**. Le
  tableau de `docs/frontiere-de-confiance.md` porte la même paire, plus la
  citation retirée : l'ancienne ligne s'appuyait sur « le même secret que le
  registre de [40] », c'est-à-dire l'objet dont [80] a fait le troisième faux
  vert du projet.

- **Cinq entrées de mutation ont dû être re-visées** (leçon de [80] : une
  réparation périme les entrées voisines). `04 auto-compact` et
  `94 the project's test command keeps the channel open` visaient des lignes que
  ce ticket préfixe ; `10 the receipt keeps only what already scrolled past` et
  `10 a truncated branch` ont changé d'indentation ou de forme. Toutes `ok` après
  correction.

- **Et une entrée a été retirée avec sa mesure, ce qui est le seul cas du
  ticket** : `10 a workspace shared by every iteration in flight` visait la seule
  chose qui séparait deux itérations, un `mktemp -d` par itération. Ce qui les
  sépare maintenant est que les preuves sont une **variable de process** — deux
  itérations sont deux process. Les deux re-visées possibles ont été essayées et
  rendent **VACUOUS sur un test sain** : un nom fixe seul (chaque itération délie
  et recrée, donc chacune a son inode), puis un nom fixe **sans** le délien (un
  seul inode, mais chaque `open` a ses propres offsets et chaque store est sa
  propre variable — les documents sortent justes). Le test reste comme témoin ;
  il n'existe plus d'édition qui retire la propriété, comme pour une condition de
  terminaison. La raison est écrite à la place de l'entrée, dans `test/mutate.sh`.

- **Ce qui reste ouvert, et pour qui.** (1) `$dir/<branche>.out` — nommé
  ci-dessus, propriétaire personne : la borne est refusée sur mesure et ce que ça
  coûte est de la prose. (2) `session_spawn_interactive` (human-loop) ne ferme
  rien : aucun reçu n'est ouvert dans le drain, donc il n'y a rien à fermer, mais
  un ticket qui ouvrirait un reçu dans le second point d'entrée hérite du besoin
  — c'est la forme de [55]/[56]/[57], « les garanties du pack sont des propriétés
  de `loop.sh` ». (3) Le canal reste ouvert pendant toute l'itération : si un
  quatrième site venait à `exec` un programme étranger sans passer par
  `session_spawn` ni `gate__command_branch`, il hériterait du bout écrivain. Le
  recensement qui le dirait est celui de [95] ; rien ici ne le dérive à nouveau.
  (4) **Un lecteur du store appelé à l'intérieur d'un `receipt_shut` tuerait
  l'itération sous errexit** : `receipt__take` fait `while IFS= read -r line; do …
  done <&"$RECEIPT_CHANNEL_BACK"`, et une redirection sur un descripteur fermé
  rend 1, donc le `while` échoue et `set -e` prend l'itération. Aucun chemin n'y
  arrive aujourd'hui, et c'est vérifié plutôt que supposé : `receipt__put` ne
  prend `receipt__take` qu'**après** un `printf` réussi, `receipt_shut_exec`
  `exec`e immédiatement (donc aucun code du pack ne tourne descripteurs fermés),
  et le seul autre site, `receipt_shut gate_notes_shut proc_group_fork`, ne
  traverse que `proc_group_fork`, qui ne touche pas le reçu. Un ticket qui
  ajouterait une lecture du store sur l'un de ces chemins doit mettre un `|| true`
  sur la boucle — ce n'est pas fait ici pour ne pas ajouter un garde qu'aucun test
  ne peut faire rougir, et parce que le geste honnête pour un défaut atteignable
  serait un ticket, pas une ligne muette.

- **Faux vert trouvé le 29/09/2026, en commençant [98] → ticket [101].** Les enveloppes de fermeture (`receipt_shut`, `receipt_shut_exec`, `gate_notes_shut`) ferment par une redirection posée sur un appel de fonction ; bash 3.2 sauvegarde le descripteur sur une copie ≥ 10 sans close-on-exec, et le programme lancé en hérite. Mesuré (`../sondes/ticket-98/`) : `claude` tient le bout écrivain du reçu en fd 10, `TEST_CMD` celui du reçu et celui des notes du gate en fd 10 et 12, et une session jugée qui écrit sur le fd 10 fait apparaître sa ligne dans son propre reçu. Les tests de ce ticket demandent aux deux numéros dérivés du pack et restent verts. Un hook git posé par la session tient aussi le fd 5 de l'itération → [102].
