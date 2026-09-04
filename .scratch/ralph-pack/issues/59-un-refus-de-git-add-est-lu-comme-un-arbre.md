# 59 — Un refus de `git add` est lu comme un arbre, et le refus documenté n'existe pas

**What to build:** Rendre à `gate_tree_snapshot` le refus que son propre
commentaire décrit, et qui n'a jamais été en vol. Le commentaire (l. 2131-2136 de
`.claude/lib/gate.sh`) écrit, pour la branche à pathspec :

> No `|| true`, unlike the branch below, and the asymmetry is the whole point …
> `set -e` takes the function down, the caller gets no tree, and that is the
> refusal it needs — **a tracker guard handed an empty tree instead would read it
> as "the session changed nothing"**.

Ce refus repose sur `set -e`. Or les **onze** appelants de cette fonction
l'invoquent tous sous la forme `x="$(gate_tree_snapshot …)" || x=""`, et un
`||` **suspend errexit sur toute l'extension dynamique** de ce qu'il encadre
(mesuré, pas déduit : un `false` au milieu de la fonction ne la tue pas). La
fonction va donc jusqu'au bout, `git write-tree` rend l'arbre vide ou un arbre
amputé, `[ -n "$tree" ]` le trouve non vide, et l'appelant reçoit **rc=0 et un
arbre** là où il croit recevoir un refus.

Ce que ça donne dépend de la branche, et les deux sont mesurées :

- **branche sans pathspec** — `git add -A` échoue **WHOLE** sur un fichier
  illisible et laisse l'index **vide** ; seul le forçage de `GUARDED_PATHS`
  (`|| true`) remet quelque chose. L'arbre jugé ne contient plus que `.claude/`,
  donc **tout le reste du dépôt a l'air supprimé par la session**.
- **branche à pathspec** — un pathspec qui ne matche rien, ou un fichier de
  ticket illisible, rend l'**arbre vide** avec rc=0, c'est-à-dire exactement ce
  que le commentaire décrit comme impossible.

**Blocked by:** None

**Write-surface:** `.claude/lib/gate.sh`, `.claude/loop.sh`,
`.claude/lib/failures.sh`, `test/gate.bats`, `test/failures.bats`,
`test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** resolved

**Tags:** securite, frontiere-de-confiance

- [x] **Un arbre que git n'a pas pu construire n'est plus rendu comme un arbre.**
      Le refus doit voyager par le **code de retour** et pas par `set -e`, parce
      que la forme d'appel qui suspend errexit est celle de tous les appelants et
      qu'il n'y a aucune raison de leur demander de changer ([53] a déjà consigné
      la règle : *un refus rendu par substitution de commande passe par le code
      de retour, pas par une variable*). Décider explicitement entre : rendre
      non-zéro quand un `git add` a échoué, ou rendre l'arbre en disant ce qui
      manque — et écrire le prix de l'option retenue.
- [x] **Le faux livré est fermé.** Mesuré : sous une write-surface qui couvre les
      chemins que l'arbre amputé prétend supprimés, l'itération sort
      `scope=green`, `failures_make_durable` ne trouve rien à enregistrer (les
      chemins refusés laissent `newtree == head^{tree}`), `concurrency_integrate`
      rend 0 sur un fold qui n'a rien à faire, et **le ticket est marqué
      `resolved` sans que `HEAD` bouge et sans que la livraison réelle de la
      session soit nulle part**. C'est le défaut de [35] par une porte que [35] ne
      couvre pas : `gate__nothing_delivered` compare `base` à l'arbre jugé, et
      l'amputation *est* une différence.
- [x] **La fausse accusation cesse.** Mesuré sous une surface étroite : trois
      itérations `scope=red` disant `wrote CONTEXT.md, outside the declared
      write-surface` — la session n'a **pas écrit** ce fichier, elle l'a rendu
      illisible — budget de retries brûlé, `Escalation: failed-impl`, et le
      guichet `implement` qui demande à un humain « Why is the code wrong » à
      propos d'un code qu'aucun gate n'a lu. **Aucune ligne ne nomme la cause**
      (0 occurrence de `unreadable` / `permission` dans toute la sortie).
- [x] **Le garde du tracker aussi.** Mesuré : un seul fichier de ticket illisible
      fait rendre l'arbre vide à `failures_tracker_tree`, donc
      `diff-tree before after` marque **tous** les tickets `D`, donc
      `failures_protect_tracker` les restaure tous et refuse le vert en accusant
      une session qui n'a rien écrit — la panne de [49], reproduite par l'autre
      bout.
- [x] **Le cas qui échappe même à un refus, nommé plutôt que tu.** Un
      *répertoire* en mode 000 fait rendre `git add -A` **rc=0** avec un simple
      `warning: could not open directory`, et les chemins dessous manquent
      silencieusement de l'arbre. Un correctif fondé sur le code de retour ne
      l'attrape pas ; dire qui garde ce cas, ou avouer que personne.
- [x] **Chercher les autres appelants qui comptent sur `set -e` sous un `||`.**
      La forme est générale, pas locale à cette fonction : `x="$(f)" || x=""`
      désarme tout ce que `f` refuse par errexit. Un balayage, et ce qu'il trouve
      écrit ici.
- [x] **Une mutation par garantie livrée**, témoin appairé vérifié à la main.

## Comments

- **Origine : passe transversale du 01/09/2026.** Sondes conservées :
  `.scratch/ralph-pack/sondes/passe-01-09/q2-l-arbre-juge-est-vide-quand-un-fichier-est-illisible.bats`
  (Q2a à Q2g), avec le témoin appairé pour chaque cas.

- **Ce que la mesure a rendu, textuellement.**

      Q2a  arbre jugé = 16403f7…  entries=24  top-level=.claude
           HEAD                    entries=26  top-level=.claude .scratch CONTEXT.md
      Q2b  témoin, tout lisible    entries=27
      Q2f  gate_tree_snapshot "no/such/path" → 4b825dc… (l'arbre vide), rc=0
      Q2g  un ticket illisible → after=4b825dc…, diff-tree rend D sur les DEUX tickets

- **Ce qui rend le déclencheur atteignable sans rien d'hostile.** Un fichier que
  l'utilisateur ne peut pas ouvrir dans un arbre non ignoré : un montage qui pose
  un fichier appartenant à un autre propriétaire, un outil qui écrit en mode 000,
  un `chmod` dans un script de build. La zone **ignorée** est hors de portée
  (`git add -A` ne l'ouvre pas), ce qui borne le déclencheur sans le fermer. Le
  fichier n'a pas besoin d'être dans la write-surface du ticket ni d'avoir été
  écrit par la session : il suffit qu'il soit dans l'arbre au moment du snapshot.

- **La fenêtre exacte compte, et elle explique pourquoi ce n'est pas [34].**
  [34] a fermé « une mesure refusée n'est pas une livraison vide » **du côté du
  scope-guard**, qui refuse quand l'arbre est illisible. Ici l'arbre n'est pas
  illisible : il est *construit*, et il est faux. Le contrôle de [34] n'a rien à
  voir avec quoi rougir.

- **Ce que ce ticket laisse à [11], et il faut l'y écrire.** Le gate de valeur
  ajoute une branche qui lira l'arbre jugé. Tant que l'arbre jugé peut être un
  arbre amputé rendu avec rc=0, une branche de plus est une opinion de plus sur
  un objet faux.

## Livraison — 03/09/2026

- **La décision, et le prix retenu.** Le refus voyage par le **code de retour**.
  L'autre option — rendre l'arbre en disant ce qui manque — a été écartée pour
  une raison qui n'est pas de goût : les onze consommateurs de cette valeur sont
  des *gardes*, et il n'existe aucun appelant capable d'agir sur « voici un
  arbre, moins quelque chose ». Les onze fail-closent déjà sur la chaîne vide,
  vérifié un par un avant d'écrire — `gate__scope_guard` et `lang_check`
  rougissent en mots ([34]), `gate_changed_files`, `gate_restore_tree`,
  `gate_unjudged_changes`, `failures_rollback`, `failures_protect_tracker` et
  `gate__contain_lens_writes` refusent de conclure —, **donc le correctif est
  local à la fonction** : aucune ligne de `loop.sh` ni de `failures.sh` n'a eu à
  changer, alors que la write-surface les déclarait.
  Le prix, mesuré sur le run réel : un projet portant un chemin illisible hors de
  sa zone ignorée voit tous ses snapshots refusés, donc l'itération rouge au
  scope-guard, le rollback qui refuse à son tour et le run qui s'arrête —
  `exit 4`, ticket rendu `ready-for-agent` avec un `Failures: 1`, sans escalade.
  C'est-à-dire **une itération au lieu de trois**, et une cause nommée à chaque
  ligne au lieu de zéro. Ce prix est celui d'un chemin **illisible**, et pas celui
  d'un chemin absent : voir la frontière ci-dessous.

- **La frontière du refus, et le fait que ce ticket l'a d'abord tracée au mauvais
  endroit.** La règle livrée tient en une phrase, la même dans les deux branches :
  **refuser ce que git n'a pas pu *lire*, jamais ce qui n'est simplement *pas
  là*.** Le premier jet suivait le commentaire d'origine, qui affirmait que sur la
  branche à pathspec « un pathspec qui ne matche rien veut dire que l'appelant ne
  peut pas recevoir ce qu'il demande à surveiller », et refusait donc tout
  non-zéro. **La suite complète a dit non** : `failures.bats` « a session that
  deletes the whole tracker gets it back » est passé rouge — une session qui
  `rm -rf` le tracker laisse le second instantané sans rien à matcher, l'arbre
  vide est alors la **vraie** réponse, et c'est sa différence avec le premier
  instantané qui fait reconstruire tout le répertoire ([21]). Le correctif
  emportait la garantie qu'il devait protéger.
  La direction que l'ancien commentaire craignait est l'**autre**, et elle est
  bien fermée : un instantané d'*avant* rendu vide alors que les tickets sont là
  lirait toute écriture suivante comme une création et laisserait les éditions de
  la session en place — ça n'arrive que si git ne peut pas les lire, `rc=1`, ce
  qui refuse. C'est le seul endroit de ce ticket où la mesure a contredit le
  ticket lui-même, et c'est une entrée de mutation à part
  (`59 a tracker that holds nothing is refused instead of read`) pour que ça ne
  revienne pas.

- **Ce qui a été mesuré sur git avant d'écrire une ligne** (git 2.50.1, hors du
  pack, chaque cas avec son témoin) :

      git add -A, fichier 000                 → rc=128, index VIDE  (échec whole)
      git add -A --ignore-errors, fichier 000 → rc=1,   index complet moins lui
      pathspec qui ne matche rien             → rc=128 (avec ou sans --ignore-errors)
      pathspec sur un fichier 000             → rc=1   sous --ignore-errors
      répertoire 000                          → rc=0 + warning: could not open directory
      répertoire 000 *ignoré*                 → rc=0, aucun message  (hors de portée)
      fichier 000 *ignoré*                    → rc=0, aucun message  (hors de portée)
      répertoire vide comme chemin gardé      → rc=0  (pas de faux refus)

  Le fait qui décide de tout le correctif est le deuxième : `--ignore-errors`
  sépare par un **code** les deux cas que le `|| true` ne pouvait que confondre.
  « Un chemin que le projet n'a pas encore créé » reste `128` et reste toléré ;
  « un chemin que git ne peut pas lire » devient `1` et refuse. Sans lui il aurait
  fallu discriminer sur le message, c'est-à-dire payer une dépendance à la
  formulation de git pour un cas qui a un code.

- **Le répertoire en mode 000 : quelqu'un le garde, et c'est un message.** Il n'a
  aucun code de retour, donc le refus se lit sur `stderr` (`could not open
  directory`), sous `LC_ALL=C` à chaque appel pour qu'un git traduit ne fasse pas
  cesser la correspondance en silence. Le prix est écrit dans le code : un git qui
  reformule ce warning perd cette moitié sans le dire — la moitié par code de
  retour n'est pas touchée. Entre un garde qui dépend d'une chaîne et pas de garde
  du tout, le choix est le premier, et il est assumé plutôt que subi. Ce qui rend
  ce détecteur sûr est mesuré : git n'ouvre pas un répertoire qu'il exclut, donc
  un `node_modules` illisible ne déclenche rien.

- **Le balayage demandé, et ce qu'il a trouvé.** Trois passes.

  1. *La forme d'appel.* Une soixantaine de sites de la forme
     `x="$(f)" || …` / `if ! x="$(f)"` dans le pack : errexit y est suspendu pour
     tout ce que `f` fait. C'est général et ce n'est pas un défaut en soi.
  2. *La seule chose qui rend ça dangereux* : une fonction qui **continue après un
     échec et imprime quand même une valeur plausible**. Une fonction qui meurt ou
     qui n'imprime rien rend la chaîne vide dans les deux cas, donc l'appelant est
     au même endroit. Scan de tous les corps de fonction pour une commande nue et
     non gardée (`git`, `mv`, `cp`, `mkdir`, `chmod`, `ln`, `touch`, `cd`, `eval`)
     : **rien d'autre que des `rm -f` de nettoyage**, deux pipelines `git
     diff-tree` terminaux (leur code *est* la valeur de retour, donc l'appelant le
     reçoit), et le `cd "$(ralph_project_root)"` de `loop_main` — dont le statut
     n'est consommé par personne, l'entrée du programme, donc errexit y répond
     encore. `gate_tree_snapshot` était le seul cas.
  3. *Les commentaires qui invoquent `set -e` comme mécanisme* : trois occurrences.
     Celle de `gate_tree_snapshot` (ce ticket) ; celle de `budget.sh` l. 420, qui
     est l'inverse — un `if` écrit **exprès** pour qu'un test faux ne tue pas la
     fonction ; et le `set -e` de `loop__iterate`, qui **réarme** errexit dans le
     sous-shell de l'itération et n'est pas sous une substitution.

  **Et la trouvaille qui a valu du code** : la forme qui masque un statut sans
  qu'aucun `||` ne soit écrit, `local x="$(f)"` — `local` rend 0 quoi qu'ait
  répondu `f`. Le pack n'en a **aucune** aujourd'hui (le seul candidat,
  `scheduler.sh` l. 182, est un `${1:-$(…)}`, une valeur par défaut dont le statut
  n'a jamais été celui de la substitution). Mais un seul appelant écrit comme ça
  remettrait le trou de ce ticket sans qu'un test le remarque, puisque le refus
  livré ici *est* un code de retour. C'est devenu une règle de `test/layering.bats`
  — le seul fichier qui lise le pack expédié — avec sa violation plantée et son
  témoin appairé (la valeur par défaut, qui ne doit **pas** être signalée : une
  règle qu'on contourne est une règle qu'on n'obéit pas).

- **Sept entrées de mutation existantes sont passées `DRIFTED`, et ce n'est pas du
  bruit.** Réécrire les trois `git add` de la fonction a déplacé les lignes
  porteuses de `05 the snapshot ignores untracked files`,
  `21 the tracker snapshot obeys the project's ignore rules`,
  `24 the snapshot obeys the ignore rules on a guarded path`, des trois entrées
  de [33] sur le forçage et de `34 the snapshot's pathspec branch hands git a
  pattern`. Chacune a été **ré-ancrée puis rejouée pour de vrai** : les sept
  rendent `ok`, donc les garanties de [05], [21], [24], [33] et [34] sont encore
  portées par le nouveau code. Deux choses apprises en les ré-ancrant, écrites ici
  parce qu'elles piègeront la prochaine :
  - **les deux branches ont maintenant une ligne d'`git add` byte-identique**, donc
    tout ancrage sur cette ligne seule matche la **première** (la branche à
    pathspec) — le piège que l'en-tête de `mutate.sh` documente depuis [29]. Les
    entrées visent désormais le contexte qui nomme la branche :
    `for path in "$@"` pour l'une, `[ -n "$path" ] || continue` pour l'autre ;
  - **une mutation ne peut plus supprimer l'affectation de `diag`/`rc`** : les deux
    lignes suivantes les lisent et le pack tourne sous `set -u`, donc l'édition
    casserait le fichier au lieu de retirer la garantie — un `BROKEN` déguisé en
    `ok`, exactement les douze entrées qui ont menti. Les remplacements
    réintroduisent toujours les deux variables.

- **Écarts de write-surface, dans les deux sens.** `test/layering.bats` a été
  édité et n'était pas déclaré (c'est la règle ci-dessus) ; `.claude/loop.sh` et
  `.claude/lib/failures.sh` étaient déclarés et n'ont pas eu à bouger, les onze
  appelants étant déjà fail-closed.

- **Ce que le run rend maintenant, sur les sondes conservées** (rejouées telles
  quelles, `sondes/passe-01-09/q2-*.bats`) :

      Q2a  tree=REFUSED                       (était : 24 entrées, top-level=.claude)
      Q2b  témoin lisible → 27 entrées        (inchangé)
      Q2f  "no/such/path" → l'arbre vide, rc=0 — INCHANGÉ, et c'est voulu :
           « rien à cet endroit » est un fait, pas un refus de mesurer
      Q2g  ticket illisible → after=REFUSED, diff-tree ne rend RIEN
           (était : D sur les deux tickets)
      Q2c  surface étroite → 1 itération, `ready-for-agent`, Escalation vide,
           zéro « wrote CONTEXT.md », la cause nommée trois fois
      Q2e  surface large   → `ready-for-agent`, HEAD immobile, pas de `resolved`

- **Ce que ça ferme pour [11], écrit aussi là-bas.** L'arbre jugé rendu avec
  `rc=0` ne peut plus être un arbre amputé : une branche de plus du gate de valeur
  lira soit un arbre complet, soit rien. La seconde contrainte que la passe avait
  laissée à [11] — la fenêtre entre l'arbre jugé et le commit durable — n'est pas
  celle-ci et reste ouverte ; elle appartient à [60].

- **Ce qui reste ouvert et n'appartient pas à ce ticket.** Un `128` du forçage qui
  ne serait pas « pathspec did not match » (un verrou d'index tenu, par exemple)
  est encore avalé : c'était déjà le cas, le séparer coûterait la dépendance au
  message pour un cas que personne n'a construit. Et `failures_preserve_attempt`
  bâtit lui aussi un index pour la branche `failed/<ticket>` : c'est de la
  forensique, pas un verdict, et rien ici ne la juge.
  Le dernier `git write-tree` de la fonction refuse toujours **sans nommer sa
  cause** (`[ -n "$tree" ] || return 1`) : c'est le comportement d'avant ce
  ticket, il reste correct — le refus voyage — et il n'est plus atteignable par
  un `git add` refusé, puisque celui-là est intercepté au-dessus. Ce qui l'atteint
  encore est un dépôt cassé, où l'itération est de toute façon rouge et le
  scope-guard le dit en mots.
