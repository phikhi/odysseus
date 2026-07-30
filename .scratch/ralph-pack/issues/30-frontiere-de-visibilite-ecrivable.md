# 30 — La frontière de visibilité de tous les contrôles est écrivable par une session

**What to build:** Fermer, ou déclarer avec son propriétaire, le fait qu'une session **choisit** ce que le pack peut voir. [24] a écrit qu'« un contrôle qui délègue sa visibilité à un fichier que le projet écrit doit dire jusqu'où il voit » ; la moitié manquante est **qui écrit ce fichier**. Les règles d'ignore ne sont pas une propriété du projet : ce sont des fichiers, et une session peut les écrire. Deux chemins, dont un ne demande aucune write-surface parce que rien dans le pack ne regarde `.git/`.

**Blocked by:** None

**Write-surface:** `.claude/lib/gate.sh`, `.claude/ralph.config.sh.example`, `test/gate.bats`, `test/canary.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`, `CONTEXT.md`, `README.md`

**Status:** ready-for-agent

- [ ] Une session qui élargit la zone aveugle ne rend pas une itération verte, ou bien le pack le déclare et dit qui garde ça. Les deux chemins sont couverts nommément : `.git/info/exclude` (et son équivalent `core.excludesFile` dans `.git/config`), et le `.gitignore` du projet quand un ticket le déclare dans sa surface.
- [ ] Le cas `.gitignore` est traité sans casser le cas légitime : un ticket a le droit d'ajouter une règle d'ignore (c'est du travail de projet normal, et [19] en fait), mais pas d'en profiter dans la **même** itération. La règle qui décide doit être celle d'avant la session, comme la write-surface l'est depuis [21].
- [ ] La ligne de zone de [24] cesse de mentir dans l'autre sens : un projet qui ignore `.scratch/` sans l'avoir commité voit son **tracker** annoncé comme chemin non jugé, alors que [21] le protège par un snapshot forcé. Nommer un chemin que le pack juge est un mensonge symétrique, et [24] avait posé exactement cette exigence pour les chemins gardés.
- [ ] Ce que ce ticket **ne** peut pas fermer est écrit avec son propriétaire, pas laissé implicite : `.git/` reste hors de portée d'un contrôle qui diffe des trees git, et un run AFK sur un dépôt dont une session peut réécrire la configuration git est une posture, pas un accident.
- [ ] La ligne correspondante de `docs/frontiere-de-confiance.md` existe et distingue les deux moitiés : jusqu'où le contrôle voit, et qui déplace cette frontière.

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
