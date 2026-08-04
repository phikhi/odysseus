# 33 — Un espace dans un nom de chemin suffit à sortir du forçage

**What to build:** Faire passer les chemins que le snapshot force dans l'arbre autrement que par un `for path in $liste`. `gate_tree_snapshot` force `gate_guarded_paths` et ce que `gate_newly_hidden` vient de rendre invisible ([24], [30]) ; les deux passent par une expansion de mot, donc un chemin qui contient un espace est découpé en deux pathspecs qui ne matchent rien, et le forçage échoue en silence. Le mécanisme central de [30] se contourne avec un espace. Pire dans l'autre sens : `gate_unguarded_ignored` compare des **chaînes entières** pour exclure ce qu'elle croit forcé, donc elle se taît sur ce chemin — il n'est ni jugé, ni défait, ni nommé.

**Blocked by:** None

**Write-surface:** `.claude/lib/gate.sh`, `.claude/lib/lenses.sh`, `.claude/ralph.config.sh.example`, `test/gate.bats`, `test/lenses.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** resolved

- [x] Un chemin caché dont le nom contient une espace est forcé dans l'arbre jugé comme n'importe quel autre : l'itération qui l'a caché est jugée à travers les règles qu'elle a reçues, ce que [30] promet déjà.
- [x] La même correction pour les chemins gardés (`GUARDED_PATHS` et les chemins scellés), qui empruntent la même boucle : un projet dont le répertoire gardé porte un espace n'a pas de garde du tout aujourd'hui.
- [x] Les deux moitiés restent d'accord : ce que le forçage n'a pas pu prendre doit être **nommé** par la ligne de zone, jamais tu. Un correctif qui répare le forçage sans vérifier ce point laisse le pire des deux mondes ouvert le jour où le forçage échoue pour une autre raison — un pathspec refusé est déjà un cas prévu et silencieux dans cette fonction.
- [x] Le test porte le témoin appairé : le même scénario avec un nom sans espace doit rougir, sinon il ne prouve rien sur l'espace.
- [x] La mutation vise le passage des chemins, pas le contenu de la liste.

## Comments

- **Origine : passe transversale du 03/08/2026** (fenêtre [06], [23], [28], [29], [30], [31]), question 5 posée sur le mécanisme livré par [30] : *qu'est-ce qu'une session peut écrire que ce contrôle-là ne verra pas ?*

  *Sonde — la sonde 2 de [30], avec une espace dans le nom.* Ticket `01-alpha`, surface `src/alpha.txt, .gitignore` — c'est le cas légitime que [30] a rendu gratuit : un ticket a le droit d'ajouter une règle d'ignore. La session écrit sa surface, ajoute `my dir/` au `.gitignore`, puis écrit `my dir/backdoor`, hors surface.

  ```
  ralph: gate: 01-alpha: tests=green typecheck=green scope=green
  ralph: gate: 01-alpha: this session moved the ignore frontier: .gitignore — …
  ralph: 01-alpha: committed 2 path(s)
  ralph: iteration 1: 01-alpha -> resolved

  fichier hors surface: survives     scope complaints: 0     zone line: (aucune)
  ```

  *Témoin — le même scénario, `mydir/` sans espace :*

  ```
  ralph: gate: scope red (exit 1)
    wrote mydir/backdoor, outside the declared write-surface
  ralph: 01-alpha: escalated to the human sink (failed-impl)
  fichier hors surface: gone        scope complaints: 3
  ```

  Une itération verte, un fichier hors write-surface qui survit, et **aucune ligne de zone** : la seule chose que [24] avait laissée pour ces cas — nommer ce que personne ne regarde — se taît aussi.

- **La cause, et elle est en deux endroits qui ne se contredisent qu'à cause de l'espace.** Dans `gate_tree_snapshot` :

  ```bash
  for path in $(gate_guarded_paths) $hidden; do
    GIT_INDEX_FILE="$index" git add -A --force -- "$path" >/dev/null 2>&1 || true
  done
  ```

  `$hidden` porte `my dir/` sur une ligne ; l'expansion de mot en fait `my` et `dir/`. Les deux `git add` échouent sur un pathspec qui ne matche rien — cas explicitement toléré par le commentaire au-dessus (« a project is free to name a path it does not have yet »), donc le `|| true` avale exactement l'erreur qui compte. Dans `gate__ignored_walk`, à l'inverse, l'exclusion se fait par `case "$hidden" in *"\n$file\n"*)`, une comparaison de chaîne complète : `my dir/` matche, donc le chemin est retiré de l'énumération *au motif qu'il est forcé*. Le forçage croit avoir pris, la ligne de zone croit qu'on l'a pris, personne ne l'a pris.

  Le même `for` est le seul chemin d'entrée des chemins gardés, donc un `GUARDED_PATHS` contenant un espace ne garde rien — et cette moitié appartient à [24], pas à [30] : elle est ouverte depuis plus longtemps et personne ne l'a sondée.

- **Le cas courant n'est pas l'attaque, comme d'habitude ([31]).** Un ticket qui ajoute légitimement `Design Assets/` ou `My Documents/` à un `.gitignore` fait exactement la même chose sans intention : pour cette itération-là, ce que ce répertoire contient n'est ni jugé ni annoncé. Le scénario hostile n'ajoute rien au mécanisme, il n'ajoute que le fichier écrit derrière.

- **Piège pour qui livrera ça.** Le réflexe est de citer la variable (`git add -A --force -- "$hidden"`), qui casse le cas que le commentaire protège : un seul pathspec refusé fait refuser **tout l'appel**, et `gate_guarded_paths` contient par construction des chemins qu'un projet n'a pas. Le passage doit rester un chemin par appel et devenir insensible à l'espace : une boucle `while IFS= read -r path` sur une liste ligne par ligne, ce que les deux producteurs rendent déjà (`gate_newly_hidden` imprime une ligne par chemin). `gate_guarded_paths`, lui, rend une **ligne unique séparée par des espaces** — c'est là que le format se décide, et le changer touche `gate_is_sealed`/`gate_in_surface`, qui itèrent aussi sur des mots. Décider dans le ticket jusqu'où le format change, et ne pas laisser deux conventions cohabiter dans un fichier qui en a déjà une.

  Second piège : `for path in $hidden` fait aussi de l'**expansion de glob**. Un chemin caché nommé `a[0].txt` ou contenant un `*` part dans le même trou par un autre mécanisme, et un test qui ne couvre que l'espace laisse celui-là ouvert.

- **Contrainte pour [19].** L'installeur écrit le `.gitignore` du projet cible ; s'il provisionne un jour un chemin à espace (un répertoire d'assets, un cache nommé par un outil), il tombe sous cette règle. Rien à faire de son côté, mais son test de provisioning est le bon endroit pour un chemin à espace, une fois ce ticket livré.

- **Contrainte pour [24] et [30], à écrire dans leur ticket au moment de livrer celui-ci.** La ligne de la frontière de confiance qui dit « les chemins gardés sont pris par force » et celle qui dit « ce que les règles épinglées ne cachaient pas est forcé dans l'arbre » sont toutes deux fausses pour un chemin à espace. Elles ne redeviennent vraies qu'ici.

- **La décision de format, tranchée ici — jusqu'où le format change (livré le 04/08/2026).** Le ticket délègue la décision ; elle tient en deux règles.

  **1. Toute liste que le pack se passe à lui-même voyage à raison d'une entrée par ligne.** Producteurs changés : `gate_sealed_paths`, `gate__sealed_config`, `gate_guarded_paths`, `gate_write_surface`. Consommateurs changés : la boucle de forçage de `gate_tree_snapshot`, `gate_in_surface`, `gate__ignored_holds_judged`. Deux formats *rédigés par un humain* alimentent ces listes, et chacun est converti **là où il est lu**, jamais en voyage : le champ `Write-surface:` d'un ticket (markdown sur une ligne, virgules et backticks) par `gate_write_surface`, et les clés de config qui nomment des globs (`SECURITY_PATHS`, `VISIBLE_PATHS`) par `lenses__triggered_by`. Un nouvel utilitaire public, `gate_authored_list`, porte la conversion pour qu'il n'y en ait qu'une définition. Ni l'un ni l'autre ne peut exprimer un chemin à espace, et c'est une propriété du format que l'humain tape, pas des listes que le pack construit.

  **2. `GUARDED_PATHS` est l'exception et se rédige un chemin par ligne**, parce qu'elle nomme des chemins et non des globs : c'est toute l'AC 2, un projet dont le répertoire gardé s'appelle `Design Assets` doit pouvoir le nommer. Écrit dans `ralph.config.sh.example`, avec l'exemple multi-lignes.

- **La seconde moitié du correctif, et elle n'était pas dans le ticket : le découpage ne suffit pas, il faut que les deux moitiés *interprètent* pareil.** Une fois la liste correctement coupée, le forçage passait chaque chemin à `git add`, qui lit un pathspec comme un motif, pendant que `gate__ignored_walk` le comparait via `gate_in_surface`, qui lit un motif de `case`. Deux moteurs de glob, sur la même valeur : `zone[1]` est un répertoire réel pour l'un, une classe de caractères pour l'autre — et un `for path in $liste` l'aurait de toute façon remplacé par `zone1` avant même d'arriver là.

  D'où une **décision de type** plutôt qu'un troisième rustine : les chemins gardés et scellés sont des *chemins*, lus littéralement des deux côtés — pathspecs `:(literal)` au forçage, nouveau `gate__under_path` (comparaison littérale, couvre ce qui est dessous) pour `gate_is_sealed` et pour l'exclusion de la ligne de zone. La write-surface reste une *liste de globs* et continue de passer par `gate_in_surface`. La documentation disait déjà « les chemins nommés par `GUARDED_PATHS` » ; c'est le code qui confondait les deux en réutilisant un matcher.

  **Le prix, assumé et testé** (`a guarded path written as a glob guards nothing, and says so`) : un `GUARDED_PATHS` rédigé comme un glob — `vendor/*` — ne garde plus rien. Mais les deux moitiés sont d'accord, donc la ligne de zone **nomme** `vendor/` comme un chemin que rien n'a jugé, au lieu d'en garder un en silence et de taire l'autre. C'est la forme testable de l'AC 3 : le forçage et l'énumération lisent la même liste de la même façon, donc ils ne peuvent plus diverger sur un nom.

- **Ce qui a été écarté, et pourquoi.** Faire *refuser le snapshot* quand un `git add` forcé échoue sur un chemin qui existe — l'autre lecture de l'AC 3. Écarté après avoir cherché le test : le seul discriminant bon marché est `[ -e "$path" ]`, et un répertoire gardé **vide** existe sans que git n'ait rien à y ajouter. Le contrôle aurait donc refusé de snapshotter des projets parfaitement sains, c'est-à-dire arrêté le run. L'accord structurel (une seule liste, une seule lecture) couvre les cas atteignables : les entrées de l'énumération viennent de `git ls-files`, donc elles existent, et `--force` est précisément ce qui retire l'autre motif de refus.

- **Deux sondes VACUOUS avant d'être vraies, à savoir pour la prochaine fois.** La première mutation visant `:(literal)` est restée verte : un pathspec git *sans* magie compare d'abord littéralement, donc `zone[1]` trouve `zone[1]` même quand `zone1` existe. Le cas où `:(literal)` change quelque chose est le chemin gardé rédigé comme un glob, pas le chemin gardé à métacaractère — le test a été réécrit sur `zone*`. La seconde, visant le découpage de `gate_in_surface`, est restée verte parce que le test qu'elle nommait assertait la sortie de `gate_write_surface` et non un *matching* : le découpage en mots et le découpage en lignes donnent le même résultat sur des entrées sans espace. Ce que la lecture ligne à ligne apporte en plus, et qui est maintenant testé, c'est que la liste n'est plus **globée contre l'arbre de travail** avant d'être comparée : un `src/*` déclaré arrivait sous la forme des fichiers qui existaient, donc un fichier que la session venait de **supprimer** tombait hors de sa propre write-surface. Un faux rouge, jamais sondé, trouvé en cherchant de quoi faire rougir une mutation.

- **Ce que le run complet de `mutate.sh` a rendu, et ce qu'il a fallu instruire avant de conclure.** 235 mutations, 4 `not ok`. Trois `DRIFTED` sont d'ici et ont été réparées : les entrées de [31] qui vident un groupe de `gate_sealed_paths` ancraient sur `printf '%s ' 'CLAUDE.md CLAUDE.local.md'`, un groupe par argument unique — les chemins sont maintenant un argument chacun, un par ligne. Ancres réécrites, les neuf entrées de [31] rejouées vertes.

  La quatrième, `23 a TERM nobody answers hangs the run for ever`, est venue `VACUOUS` et **n'est pas d'ici** : rejouée seule sur la branche → `VACUOUS, ok, ok` ; rejouée seule dans un worktree propre de `main` → `ok, VACUOUS, ok, ok`. Environ un tour sur quatre, indépendamment de ce ticket. La sonde et la cause à chercher sont dans **[38]**, et la contrainte est écrite dans [23]. Le point de méthode vaut d'être noté : le premier réflexe a été « ma branche fait revenir le run en 1 s au lieu de 35 s », ce qui aurait été grave ; c'est en remettant `gate.sh`, `lenses.sh` et le `.example` de `main` sous mes tests — et en voyant le défaut persister — puis en rejouant `main` que la flakiness est apparue. Une mesure qui diffère une fois n'est pas une différence.

- **Reste ouvert, nommé plutôt que corrigé.** `gate_tree_snapshot` avec pathspecs (`"$@"`, un seul appelant : `failures_tracker_snapshot` via `failures__issues_path`) passe toujours ses chemins sans `:(literal)`. Un `FEATURE` à métacaractère ferait porter la protection du tracker de [21] sur un autre répertoire. Non couvert ici parce que `FEATURE` est une clé de config lue une fois et que la branche est à un argument, mais c'est la même famille : la contrainte est écrite dans [21].

- **Contrainte posée par [27], livré le 03/08/2026 : une troisième liste de la même famille, dans un autre fichier.** `failures_tracker_snapshot` rend les ids du tracker joints par des espaces et `failures__strays` les compare mot à mot (`case "$seen" in *" $id "*)`) : un ticket dont le **nom de fichier** contient une espace est mal vu par ce chemin, exactement comme un chemin à espace l'est par le forçage du snapshot. [27] a corrigé son propre lecteur (la boucle de quarantaine lit ligne par ligne) et a laissé le format en place, parce que réparer un lecteur sans réparer le producteur ne gagne rien. Si le correctif d'ici touche à la convention de liste du pack — et le piège de ce ticket dit qu'il faudra trancher jusqu'où le format change — ces deux fonctions sont dans le même cas et doivent être décidées avec lui, pas découvertes après.
