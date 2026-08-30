# 46 — La configuration git décide aussi de ce que git exécute

**What to build:** Élargir le pin de [30] de son critère implicite — « ce qu'un contrôle **voit** » — à celui qu'il aurait dû avoir : « ce qu'une session peut écrire dans la configuration git et qui change ce que **le pack** fait ». [30] a épinglé `.git/info/exclude` et `core.excludesFile` parce que ces deux-là décident de la visibilité des contrôles. La même configuration porte des clés qui décident de ce que git **lance** (`core.fsmonitor` est un chemin de programme) et de ce que git **produit** (`filter.<n>.smudge`, activé par `.git/info/attributes`). Aucune n'est épinglée, aucune n'est regardée, et les deux sont écrivables par une session — dans `.git/config`, dont le tableau de confiance dit déjà « vérifié par rien », et dans le `~/.gitconfig` de l'opérateur, la porte que [15] a ouverte et dont il n'a mesuré que la moitié « capacité ». Et, parce qu'un témoin de plus posé sur le canal actuel s'évaporerait exactement sur les runs qu'on lit le matin, ce ticket doit d'abord rendre ce canal aussi large que son critère.

**Blocked by:** None

**Write-surface:** `.claude/lib/gate.sh`, `.claude/loop.sh`, `.claude/lib/capability.sh`, `.claude/lib/receipt.sh`, `.claude/ralph.config.sh.example`, `test/gate.bats`, `test/capability.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** resolved

- [x] Une session qui écrit `core.fsmonitor` — dans `<arbre principal>/.git/config` ou dans `$HOME/.gitconfig` — ne fait plus tourner sa commande dans l'arbre de processus du pack en silence. Le verdict (empêcher, défaire, ou seulement dire) est une décision de ce ticket ; ce qui n'est pas négociable, c'est qu'un run ne finisse pas `resolved` sans une phrase.
- [x] Un filtre `smudge` installé par une itération ne réécrit plus ce que les itérations suivantes lisent sans qu'aucun contrôle ne puisse le voir. Même remarque sur le verdict, et la borne est déjà mesurée : ça n'atteint ni le ticket, ni la `Write-surface:`, ni l'historique.
- [x] La liste des clés est **dérivée de son critère** et non des trois que la passe a sondées ([31]). Le critère est : ce qu'une session peut mettre dans une source de configuration git et qui fait que git exécute un programme ou transforme un contenu. Ce que la sonde a montré ne pas tirer (`core.hooksPath`, `diff.external`) est écrit à côté, avec la raison — c'est la borne, pas une omission.
- [x] Le témoin de [15] atteint un document sur **toutes** les itérations où il tire, y compris celle sur laquelle le run s'arrête. Aujourd'hui `capability_drift` tourne à chaque itération et n'écrit qu'un `receipt_gap` ; le reçu n'est émis que sur les quatre routes de [45], et `capability__log` n'écrit que stdout — le journal n'est écrit que par le pilote.
- [x] `ralph.config.sh.example` cesse de dire de ce témoin qu'« il est sur chaque reçu ».
- [x] Le tableau de `docs/frontiere-de-confiance.md` porte la ligne, et dit ce qui la tient — ou l'aveu que rien ne la tient.

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

## Livraison, le 29/08/2026

Les sondes de la passe du 26/08 ont **toutes été rejouées** avant d'écrire une
ligne (`.scratch/ralph-pack/sondes/passe-26-08/`, sortie complète relue) : P1c et
P3a reproduisent (252 exécutions de `core.fsmonitor` sur un run de deux
itérations, deux `resolved`, silence total), P7 reproduit (le `CONTEXT.md` de la
session 2 est réécrit, l'arbre principal et le blob intacts), P8 reproduit les
bornes, P2b/P2c/P3b reproduisent le témoin sans canal. P1a (`core.hooksPath`) et
P1d (`diff.external`) ne tirent toujours pas. Une seule sonde ne reproduit pas
et c'est un défaut de la sonde : **P2a écrit `fsmonitor = …` sans en-tête de
section**, donc la clé atterrit dans la dernière section du fichier et n'est pas
`core.fsmonitor` — c'est P3a qui porte cette trouvaille, avec l'en-tête.

Les sondes de ce ticket sont dans `.scratch/ralph-pack/sondes/ticket-46/`, même
convention (elles finissent par un `false` volontaire).

### Ce que le ticket a dû trancher, et la réponse

**Le verdict : remettre et rougir, pas seulement dire.** L'AC laissait le choix
entre empêcher, défaire et dire. « Dire » ne suffit pas ici et la raison est
mesurée : sans remise, le filtre `smudge` reste armé pour **tous** les worktrees
que le run crée ensuite, et `core.fsmonitor` continue de tourner dans l'arbre de
processus du pilote — un run qui se contenterait de le nommer produirait une nuit
entière de sessions empoisonnées, chacune avec sa phrase. C'est exactement
l'argument de [30] pour le genre `dir` (« une itération rouge achèterait la
nuit »), et il vaut plus fort ici parce que ce qui continue n'est pas une
cécité mais une exécution.

**Le mécanisme : un quatrième genre sur la frontière de [30], pas un second
mécanisme.** Le ticket dit « [30] a posé exactement le bon mécanisme sur la
moitié visibilité ». La conséquence pratique est qu'il ne fallait rien rebâtir :
le témoin par run de [41], le pin par itération, le registre des mouvements,
l'attribution « toute itération en vol est facturée », le garde dans le
répertoire git commun et les trois sites de [32] sont déjà là et sont déjà les
bons. Ce que [46] ajoute est un genre `cfg` dans le manifeste et sa remise.
Bâtir un mécanisme parallèle aurait dupliqué le registre — et un registre
dupliqué, c'est deux endroits où corriger la prochaine leçon de [41].

**Le renommage, et pourquoi il n'était pas cosmétique.** `gate_ignore_frontier`
qui rend un constat sur `core.fsmonitor` est un nom qui ment, et ce dépôt a un
document entier sur ce que coûtent les noms qui mentent. La machinerie *partagée*
par les deux questions est renommée en `gate_frontier*` / `gate__frontier_*`
(entrée publique, manifeste, `moved`, `restore`, `pinned`/`current`, `record`,
`share`, `mark`, `ledger_len`, `pin_broken`, `pin`, `common`), et les variables
avec (`RALPH_GATE_IGNORE` → `RALPH_GATE_FRONTIER`, `RALPH_IGNORE_PIN` →
`RALPH_FRONTIER_PIN`, `RALPH_IGNORE_COMMON` → `RALPH_FRONTIER_COMMON`). Ce qui
reste `gate__ignore_*` est ce qui ne parle que d'ignore : les règles de l'arbre,
le chemin de l'`exclude`, celui du fichier global, `gate_newly_hidden`,
`gate_moved_tree_rules`. Trois entrées de mutation ont dérivé et une seule à
cause du renommage ; les notes sont écrites dans [30], [32], [40] et [41].

**La liste des clés, dérivée du critère.** Elle vit dans `gate_config_keys`, une
expression régulière étendue par ligne, comparée à la configuration **effective**
(`git config --list` résout système, global, local, worktree et les `include`) —
ce qui est la bonne question : pas « qu'y a-t-il dans ce fichier » mais « que va
faire git ». Trois familles : ce que git *exécute* (`core.fsmonitor`,
`core.hooksPath`, `core.sshCommand`, `credential.*.helper`, `diff.external`,
`diff.*.command`, `diff.*.textconv`, `merge.*.driver`, `filter.*.{clean,smudge,
process}`, `gpg.program`, `commit.gpgsign`, `trailer.*.cmd`, `*tool.*.cmd`,
`remote.*.{uploadpack,receivepack,proxy}`, `uploadpack.packObjectsHook`,
`init.templateDir`, `core.pager`/`pager.*`, `core.editor`/`sequence.editor`,
`core.askPass`, `web.browser`, `sendemail.smtpServer`, `protocol.*.allow`,
`ssh.variant`), ce qu'il *transforme* (`core.autocrlf`, `core.eol`,
`core.safecrlf`, `core.symlinks`, `core.attributesFile`, `core.quotePath`,
`core.precomposeUnicode`, `core.protect{NTFS,HFS}`), et **d'où les précédentes
sont lues** (`include.path`, `includeIf.*.path`, `extensions.worktreeConfig`) —
cette troisième famille n'est pas un ajout de confort : elle décide si la remise
a une cible.

Ce qui n'y est **pas**, avec la raison à chaque fois, parce qu'une liste avec une
omission muette est exactement le défaut que ce ticket répare :

- `alias.*` — un alias `!commande` est un programme, mais git refuse un alias
  portant le nom d'une sous-commande native et le pack n'appelle que des natives.
  C'est une propriété de **git**, donc une borne et pas un pari sur les appelants
  actuels du pack ;
- `core.excludesFile` — propriétaire [30], une ligne plus haut. Deux mécanismes
  qui remettent la même clé la remettent deux fois et la facturent deux fois ;
- `core.worktree`, `core.bare` — elles décident de ce que git *adresse*, pas de
  ce qu'il exécute ou transforme. Autre question, sans propriétaire, écrite ici
  plutôt que laissée ressembler à un oubli.

Et deux clés y sont **bien que la sonde les ait mesurées inertes**, ce qui est la
même règle de [31] lue dans l'autre sens : `core.hooksPath` ne tire pas parce que
`failures_make_durable` commite par la plomberie exprès, `diff.external` ne tire
pas parce que tous les diffs du pack sont `--name-only`/`--name-status`. Ce sont
deux faits sur les **appelants actuels du pack**, pas sur git : les retirer
rendrait la liste dérivée du code, et le ticket qui échangerait un `commit-tree`
contre un `git commit` rouvrirait le trou sans rien pour le remarquer. L'AC
demandait de les écrire « à côté » ; les surveiller quand même est plus strict et
la raison est écrite dans `gate_config_keys`.

**Le `.gitattributes` de l'arbre n'est pas une source ici**, et c'est la
distinction `tree`/`dir` de [30] redite : c'est un chemin de l'arbre que le
scope-guard compare, donc jugé comme un autre, couvert par la question de la
write-surface et défait par le rollback. Ce qui entre est
`<répertoire git commun>/info/attributes` : dans aucun arbre, déclarable dans
aucune write-surface, partagé par tous les worktrees — les trois propriétés qui
ont mis `info/exclude` sur cette frontière.

### La trouvaille que ce ticket a faite en écrivant, et qui a déplacé la remise

Question 5 posée **avant** d'écrire : *que peut faire une session que rien ne
vérifie, dans la fenêtre où le correctif n'agit pas encore ?* Les trois sites de
[32] sont tous **derrière** `failures_protect_tracker`, et ce garde-là lit et
écrit `issues/` **à travers git** : `failures_tracker_tree` stage le répertoire
pour le comparer (donc à travers le `clean`) et `checkout-index` le ressort (donc
à travers le `smudge`). Une session qui installait un filtre faisait donc
réécrire **tous les tickets sur le disque**, durablement et pour les runs
suivants, avant qu'aucun contrôle n'ait regardé la configuration.

D'où `gate_frontier_put_back`, appelé par `loop__iterate` dès que la session est
partie (après le garde d'orphelin de [44] : un orphelin n'agit pas). Le gate
rappelle `gate_frontier`, ne trouve plus rien qui ait bougé, et lit le mouvement
dans le **registre** — ce pour quoi le registre existe. Sonde `q2.bats` Q5 :
les tickets ne portent pas le marqueur du filtre.

**Et cette deuxième porte a cassé une invariante de [41], qui était une
convention et est maintenant une propriété.** [41] avait écrit « un seul appelant
par itération, quel que soit le chemin », et `failures_handle` garde un drapeau
pour l'honorer, parce qu'un mouvement **qu'aucune remise ne peut défaire** est
re-détecté à chaque regard. Sonde Q3 avant correction : le constat
`~/.gitconfig` apparaissait **deux fois** sur la sortie du scope-guard, donc
l'itération était facturée deux fois et tout frère en vol avec elle.
`gate__frontier_record` refuse maintenant d'ajouter une ligne que **ce pin** a
déjà enregistrée et **pas encore lue** — la règle est passée de la convention
d'appel au registre lui-même, ce qui rend un troisième appelant sûr. La portée
« pas encore lue » n'est pas un détail : après que `gate_run` a lu sa part, la
marque est passée devant, donc la même phrase enregistrée plus tard est un
événement neuf — c'est le cas du re-slice de [32], dont la session de
planification peut bouger la même source une seconde fois, et le déduire
sous-déclarerait un mouvement que rien d'autre ne nomme.

### Le canal du témoin de [15], fait en premier comme le ticket le demandait

`capability_drift` **rend** maintenant ses lignes (`sujet<TAB>outcome<TAB>message`,
la forme que `tracker_preflight` utilise déjà) au lieu de les imprimer, garde son
`receipt_gap`, et l'itération les passe au pilote par son slot — du bookkeeping et
jamais une décision ([13]). `loop__finish` en fait une ligne de `run.log` par
surface, **le sujet portant la surface** : `loop__report_tracker_findings` fait
déjà exactement ça pour un id en double, et une ligne qui ne nomme rien envoie un
humain nulle part. Transcrit et jamais remesuré : c'est l'itération qui a pris la
mesure, et redemander dans le pilote répondrait sur un autre instant — une
surface qu'un frère aurait remise entre les deux serait une dérive qui atteint le
reçu et pas le journal, c'est-à-dire la coupure qu'on répare.

`ralph.config.sh.example` disait « il est sur chaque reçu ». C'était faux et la
correction ne se contente pas de retirer la phrase : elle dit où ça atterrit
maintenant, et pourquoi il y a deux documents.

### Ce qui reste, écrit comme des choix

- **Rien n'écrit hors du dépôt**, ici comme partout. Une valeur qui répond encore
  après l'`unset` — le `~/.gitconfig` de l'opérateur, la configuration de la
  machine, ou une clé qu'une session a **supprimée** (le pin ne garde qu'une
  empreinte, pas la valeur) — est nommée comme non remise, et l'itération, plus
  toutes celles du run après elle, reste rouge dessus. Fail-closed et bruyant.
  Le prix, assumé : une session peut en une ligne faire escalader le reste du
  tracker au puits humain, chaque fois avec un reçu qui nomme la clé — plus cher
  pour elle qu'un silence, et récupérable par un humain. Stocker les valeurs dans
  le témoin a été refusé : ça remettrait dans la configuration **locale** une
  valeur qui venait du global, donc ça muterait durablement le dépôt d'un
  opérateur pour répondre à une question sur une session.
- **Un faux rouge est possible** si l'opérateur édite lui-même une de ces clés
  pendant la nuit. C'est le même échange que [30] a pris pour `core.excludesFile`
  et le fichier d'exclusion global, et le sens de l'erreur est le choix : un faux
  vert laisse une session acheter une livraison, un faux rouge coûte une session.
  Noter que [15] refuse de rougir sur le `$HOME` et que [30] rougit : la
  différence est ce que la clé décide, et elle est écrite au tableau.
- **Une sous-section peut porter une tabulation**, que le manifeste ne peut pas
  transporter. Ces clés sont repliées sur une seule ligne, nommées comme telles,
  et remises **seulement si le run n'en avait aucune** — sinon on retirerait à
  l'opérateur une configuration que ce garde ne sait pas distinguer de celle de
  la session. Même posture que [39] sur un chemin que git cite : le nommer,
  jamais prétendre l'avoir adressé.
- **Un run tué** ne passe par aucune de ces portes, donc sa configuration reste
  déplacée : même résidu que [30], même racine (le témoin meurt dans `$TMPDIR`).
- **La fenêtre de la session elle-même** n'est pas fermée et ne peut pas l'être
  par ce mécanisme : `core.fsmonitor` tourne pendant que la session vit. Ce que
  la remise avancée ramène, mesuré : 252 exécutions sur un run de deux
  itérations avant, 12 après (sonde Q2).

### Ce que ça laisse aux tickets suivants

- **[19]** provisionne `ralph.config.sh` et balaye `$TMPDIR`. Deux contraintes
  neuves : son installeur ne doit écrire **aucune** clé de `gate_config_keys` dans
  un dépôt pendant qu'un run tourne (ce serait un rouge légitime), et le balayage
  hérite d'un troisième répertoire par run dans `$TMPDIR` — inchangé en nombre,
  c'est le même `ralph-frontier.XXXXXX` de [41].
- **[11]** ajoute une branche de gate : elle hérite du canal tel qu'il est
  maintenant, journal compris, et ses verdicts arrivent sur le reçu par la route
  existante.
- **[18]** (backends distants) : `gate_config_keys` parle de la configuration git
  de l'arbre local ; un backend distant ne change rien ici, mais un backend qui
  ferait un `git fetch`/`git push` réveillerait `remote.*.uploadpack`,
  `credential.*.helper` et `protocol.*.allow`, qui sont déjà surveillées.
- Note écrite dans **[30]**, **[32]**, **[40]**, **[41]** (renommage et registre),
  **[15]** (canal durable) et **[19]**.

### Ce que le gate de mutation a trouvé, et c'est la trouvaille de fin de ticket

Première passe complète : `run.sh` vert, `mutate.sh` **3 `VACUOUS`**. Aucun n'était
un test à réécrire sans diagnostic, et les trois disent trois choses différentes.

**1. `41 a crashed iteration's movement never reaches its siblings` — la garantie a
gagné un second propriétaire, plus tôt dans l'itération.** C'est exactement la
famille que [43] avait nommée dans l'entrée `32 the restore is bolted onto every
class`. L'édition retirait `failures__frontier` du chemin crash ; depuis que
`loop__iterate` remet la frontière dès le retour de la session, le mouvement est
enregistré **avant** d'y arriver, donc le frère est facturé quand même et le test
reste vert. Ni l'un ni l'autre propriétaire n'est nécessaire seul : aucune édition
d'un seul fichier ne retire cette garantie. L'entrée vise maintenant la **ligne
d'écriture du registre**, par laquelle les deux propriétaires passent. L'entrée de
[32] garde l'ancienne édition — elle reste `ok`, parce qu'elle retire ce que seul
`failures__frontier` fait : la **phrase** sur le document de l'itération crashée.

**2. `46 the frontier is put back only once the tracker has been read` — la sonde
était fausse, pas le pack.** Mon scénario donnait au filtre un `clean` identité
(`sed s/Status/Status/`), donc l'arbre de `issues/` ne bougeait pas, donc
`failures_protect_tracker` sortait sur son `[ "$after" != "$before" ] || return 0`
sans jamais appeler `checkout-index` : le test était vert des deux côtés parce que
la fenêtre n'était pas ouverte. Le scénario honnête est celui où le garde a
vraiment quelque chose à restaurer — **la session édite son propre ticket** et
installe le `smudge`. Le test asserte maintenant les deux moitiés : l'édition de la
session a bien été défaite (sinon il serait vert parce que rien n'a été écrit), et
ce qui a été réécrit n'est pas passé par le filtre.

**3. `46 one movement is recorded once per look instead of once per iteration` — le
test asseyait une présence là où la garantie est un compte.** `assert_output_contains`
est satisfait par une ligne en double, qui est précisément le défaut. Le test compte
maintenant les occurrences et exige `1`.

Les trois entrées rejouées pour de vrai après correction : `ok`, `ok`, `ok`.

### Baseline, mesurée le 29/08/2026 sur cette branche

- `bash test/run.sh` = **547 tests, 0 failures, 6 skips opt-in** (540 avant, +7 :
  six dans `test/gate.bats`, un dans `test/capability.bats`).
- `bash test/mutate.sh` = **526 mutations, 0 `not ok`** (517 avant, +9).

Aucun nom toléré des deux côtés, canari compris. Les trois `DRIFTED` du premier
passage à blanc étaient des ancres de [44], [41] et [15] : garanties vérifiées
puis ré-ancrées, aucune n'avait perdu son propriétaire.

- **[09], le 29/08/2026 : le résidu que ce ticket a nommé et assumé n'est plus
  franchi par un successeur programmé.** Ce ticket écrivait : « une clé qu'une
  session supprime, ou qui répond depuis hors dépôt, n'est pas remise — nommée,
  rouge, et rouge pour tout le reste du run », et laissait à [09] la question de
  ce qu'un successeur en hérite. Réponse livrée : **rien n'est armé**. Une
  fonction publique neuve, `gate_frontier_residue`, pose la même différence
  symétrique un niveau plus haut — contre le manifeste du témoin de **run**, sur
  les sources partagées seulement — et le pilote la lit en queue de `loop_main`.
  Le raisonnement est le vôtre : un run neuf épingle la configuration qu'il
  trouve, donc un successeur adopterait `core.fsmonitor` comme celui du projet et
  le ferait exécuter par git dans l'arbre de process du pilote à chaque
  rafraîchissement d'index, toute la nuit, sans un mot — et l'humain que ce
  successeur remplace est celui qui aurait lu le reçu. Deux notes pour la suite :
  la fonction a été placée **après** `gate__frontier_share` parce qu'une fonction
  neuve plus haut peut rendre une ancre de mutation ambiguë (le piège que ce
  ticket-ci a écrit) ; et l'entrée de mutation `46 the configuration half of the
  frontier is never read` rend aussi ce lecteur aveugle, ce qui est correct — les
  deux lisent `gate__config_manifest`.
