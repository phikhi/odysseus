# 46 — La configuration git décide aussi de ce que git exécute

**What to build:** Élargir le pin de [30] de son critère implicite — « ce qu'un contrôle **voit** » — à celui qu'il aurait dû avoir : « ce qu'une session peut écrire dans la configuration git et qui change ce que **le pack** fait ». [30] a épinglé `.git/info/exclude` et `core.excludesFile` parce que ces deux-là décident de la visibilité des contrôles. La même configuration porte des clés qui décident de ce que git **lance** (`core.fsmonitor` est un chemin de programme) et de ce que git **produit** (`filter.<n>.smudge`, activé par `.git/info/attributes`). Aucune n'est épinglée, aucune n'est regardée, et les deux sont écrivables par une session — dans `.git/config`, dont le tableau de confiance dit déjà « vérifié par rien », et dans le `~/.gitconfig` de l'opérateur, la porte que [15] a ouverte et dont il n'a mesuré que la moitié « capacité ». Et, parce qu'un témoin de plus posé sur le canal actuel s'évaporerait exactement sur les runs qu'on lit le matin, ce ticket doit d'abord rendre ce canal aussi large que son critère.

**Blocked by:** None

**Write-surface:** `.claude/lib/gate.sh`, `.claude/loop.sh`, `.claude/lib/capability.sh`, `.claude/lib/receipt.sh`, `.claude/ralph.config.sh.example`, `test/gate.bats`, `test/capability.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

- [ ] Une session qui écrit `core.fsmonitor` — dans `<arbre principal>/.git/config` ou dans `$HOME/.gitconfig` — ne fait plus tourner sa commande dans l'arbre de processus du pack en silence. Le verdict (empêcher, défaire, ou seulement dire) est une décision de ce ticket ; ce qui n'est pas négociable, c'est qu'un run ne finisse pas `resolved` sans une phrase.
- [ ] Un filtre `smudge` installé par une itération ne réécrit plus ce que les itérations suivantes lisent sans qu'aucun contrôle ne puisse le voir. Même remarque sur le verdict, et la borne est déjà mesurée : ça n'atteint ni le ticket, ni la `Write-surface:`, ni l'historique.
- [ ] La liste des clés est **dérivée de son critère** et non des trois que la passe a sondées ([31]). Le critère est : ce qu'une session peut mettre dans une source de configuration git et qui fait que git exécute un programme ou transforme un contenu. Ce que la sonde a montré ne pas tirer (`core.hooksPath`, `diff.external`) est écrit à côté, avec la raison — c'est la borne, pas une omission.
- [ ] Le témoin de [15] atteint un document sur **toutes** les itérations où il tire, y compris celle sur laquelle le run s'arrête. Aujourd'hui `capability_drift` tourne à chaque itération et n'écrit qu'un `receipt_gap` ; le reçu n'est émis que sur les quatre routes de [45], et `capability__log` n'écrit que stdout — le journal n'est écrit que par le pilote.
- [ ] `ralph.config.sh.example` cesse de dire de ce témoin qu'« il est sur chaque reçu ».
- [ ] Le tableau de `docs/frontiere-de-confiance.md` porte la ligne, et dit ce qui la tient — ou l'aveu que rien ne la tient.

## Comments

- **Origine : passe transversale du 26/08/2026** (fenêtre [45]/[14]/[15]), sur `main` à `3d6915b`. Le document est dans `.scratch/ralph-pack/passe-transversale-26-08.md` et **les sondes sont conservées** dans `.scratch/ralph-pack/sondes/passe-26-08/` — ce sont des instruments qui finissent par un `false` volontaire, pas des tests, et `test/run.sh` sans argument ne les ramasse pas. Les rejouer une par une avant d'écrire quoi que ce soit.

- **La racine, et c'est elle le ticket.** Ce pack a appris à se méfier de ce qu'une session écrit dans un **arbre**. Il ne s'est jamais demandé ce qu'elle écrit dans les fichiers qui décident de ce que *lui-même* exécute. [30] a posé exactement le bon mécanisme — un pin de contenu, comparé, qui rougit l'itération — sur la moitié « visibilité » du sujet. L'autre moitié n'a jamais été posée. Ne pas rallonger une liste de clés : relire la question.

  *Ce qui est déjà pensé, et qu'il ne faut pas défaire.* `failures_make_durable` utilise la **plomberie** exprès (« Plumbing rather than `git commit`, so the target project's hooks, signing config and commit template have no say »). C'est ce qui fait que `core.hooksPath` ne tire jamais — sondé, le `post-commit` n'est pas appelé. Le pack a donc déjà traité la configuration git comme une surface d'attaque ; il l'a bornée au dépôt et aux *hooks*.

- **Trouvaille 1 — `core.fsmonitor` est une commande, et le pack la lance.** Git le lance à chaque rafraîchissement d'index : chaque `git add -A` du snapshot, chaque `git status`, chaque worktree. Sondé (`p1c-fsmonitor.bats` pour `~/.gitconfig`, `p3.bats` P3a pour `.git/config`) : **248 exécutions sur un run de deux itérations**, parent = `git` lui-même, donc dans l'arbre de processus du pilote — pas dans celui d'une session, pas dans un worktree, pas sous un gate. Les deux tickets sortent `resolved`, `run.log` ne dit rien, aucun reçu ne dit rien.

  Les deux emplacements sont suffisants séparément et il faut les traiter tous les deux. `.git/config` est le plus proche (l'arbre principal se trouve par `git worktree list`, et le tableau dit déjà de ce répertoire que « le rempart est l'isolation de l'hôte » — l'isolation borne le rayon, elle ne dit rien du fait que le pack exécute la commande lui-même). `~/.gitconfig` est la porte de [15] : `--setting-sources user` ([06]) suppose que le `$HOME` de l'opérateur n'est pas écrivable par la session jugée, et [15] a montré qu'il l'est. Un hook de `~/.claude/settings.json` tourne dans le process de la **session suivante** ; une clé `core.fsmonitor` tourne dans le process **du pack**.

  Cas voisin sain, sondé pour borner (`p1b` P1e) : du texte qui n'est pas de la config dans `~/.gitconfig` ne passe pas en silence — `rc=4`, `scope=red lang=red`, « cannot read the working tree », le run s'arrête et un reçu est émis (c'est la cinquième trouvaille de [45] qui le tient). Le mode de panne bruyant est déjà couvert ; c'est le mode de panne utile qui ne l'est pas.

- **Trouvaille 2 — le filtre `smudge`, que le tableau annonçait « non sondé ».** Il l'est maintenant. Vérifié d'abord hors du pack : `.git/info/attributes` et `[filter "x"] smudge` vivent dans le répertoire git **commun**, donc ils s'appliquent dans un worktree lié, et `git checkout-index` y passe le smudge. Puis dans le pack (`p7.bats`) : l'itération 1 installe le filtre, l'itération 2 est un worktree neuf, et sa session reçoit un `CONTEXT.md` réécrit alors que le blob git et l'arbre principal portent l'original. Gate vert des deux côtés, deux `resolved`, silence complet.

  Aucun contrôle ne **peut** le voir : le scope-guard compare deux trees et les deux sont smudgés de la même façon, donc le diff est vide. `CONTEXT.md` est le premier document que le prompt de session nomme, et `docs/adr/` — que la lentille Standards va lire — est dans le même cas. C'est la route que [14] a fermée pour `LEARNINGS.md` en le servant depuis une copie du pilote ; elle est ouverte pour tout le reste de l'arbre.

  **La borne, mesurée et pas supposée** (`p8.bats`) : le ticket et sa `Write-surface:` sont lus dans l'arbre principal, hors du worktree, donc **pas** smudgés — le scope-guard a bien rougi le chemin hors surface et le prompt portait la vraie surface. Et rien de réécrit n'atteint l'historique : le commit sur vert ne prend que les chemins que le scope-guard a approuvés (`p7` : arbre principal et blob intacts). Le contexte est empoisonnable, le contrôle ne l'est pas — c'est ce qui décide de la gravité, et c'est aussi ce qu'un correctif ne doit pas casser.

- **Trouvaille 3 — pourquoi elle passe *avant* les deux autres dans ce ticket.** La réponse naturelle à un `.gitconfig` qu'on ne peut pas défaire est un témoin de plus. Posé sur le canal d'aujourd'hui, ce serait un détecteur dont les événements disparaissent exactement sur les runs qui s'arrêtent mal.

  `capability_drift` tourne à chaque itération (`loop.sh:813`, hors du `if emit`) et c'est écrit comme un choix délibéré. Mais il écrit un `receipt_gap`, et le reçu n'est émis que sur les quatre routes de [45] ; l'autre canal, `capability__log`, est un `printf` sur stdout, et `run.log` n'est écrit que par le pilote (`loop_journal_append`), jamais par le shell d'itération. Sondé :

  - itération retryée **suivie d'autres** (`p2` P2b) : le témoin finit par arriver, parce que la ligne de base est celle du run et que l'itération d'escalade émet. Conforme à ce que [15] annonce ;
  - itération retryée sur laquelle **le run s'arrête** (`p2` P2c, `ITER_CAP` — et donc aussi `STERILE_K`, un arrêt demandé, un mur budget) : **aucun reçu, aucune ligne de journal**, et le fichier est là ;
  - au run **suivant** (`p3` P3b) : le témoin est par run ([15], limite 5), donc il reprend le fichier comme ligne de base — le silence est **définitif**, pas différé.

  C'est [45] appliqué à [15], et la même racine que la passe du 07/08 : un producteur plus étroit que le critère écrit à côté de lui.

- **Mineur de la même famille, à trancher ici ou à écrire comme un choix.** `capability_review` — donc le `receipt_note` qui avoue `CAPABILITY=off` — n'est atteignable que par `retro_run`, qui sort avant lui quand `RETRO=off`. Un projet en `RETRO=off` + `CAPABILITY=on` n'a aucune revue de capacités et le reçu attribue le silence au seul tier retro. Le témoin, lui, est bien indépendant des deux clés : l'AC 4 de [15] tient (sondé, `p5` P5c).

- **Ce qu'il ne faut pas resonder** (disculpé le 26/08/2026) : `core.hooksPath`, `diff.external`, le ticket et la `Write-surface:` face au smudge, l'historique face au smudge, `CAPABILITY=off` face au témoin, et la lentille de la même itération face au `$HOME` — cette dernière est la limite 3 que [15] a **écrite**, confirmée conforme (`p5` P5b : la lentille voit bien ce que la session qu'elle juge vient d'écrire), pas une trouvaille.

- **Ordre.** Avant [11] et [19] : [11] ajoute une branche de gate donc des verdicts au reçu et hériterait du canal tel qu'il est ; [19] provisionne les clés de `ralph.config.sh` et le balayage. Après [47], qui est plus court et dont [16] et [18] dépendent plus directement.

- **Ordre, revu par la passe du 27/08/2026.** [49] passe **avant** : les deux tickets réécrivent des lignes de `docs/frontiere-de-confiance.md`, et [49] corrige le paragraphe que [47] vient d'y écrire (ce qu'une session achète en *posant* le garde d'ouverture, et non seulement en le supprimant). Corriger avant d'ajouter évite de rejouer la même passe de mutation deux fois sur le même fichier. Rien d'autre ne change pour ce ticket : les deux sujets sont disjoints.
