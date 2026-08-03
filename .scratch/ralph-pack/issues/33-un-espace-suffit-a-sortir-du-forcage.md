# 33 — Un espace dans un nom de chemin suffit à sortir du forçage

**What to build:** Faire passer les chemins que le snapshot force dans l'arbre autrement que par un `for path in $liste`. `gate_tree_snapshot` force `gate_guarded_paths` et ce que `gate_newly_hidden` vient de rendre invisible ([24], [30]) ; les deux passent par une expansion de mot, donc un chemin qui contient un espace est découpé en deux pathspecs qui ne matchent rien, et le forçage échoue en silence. Le mécanisme central de [30] se contourne avec un espace. Pire dans l'autre sens : `gate_unguarded_ignored` compare des **chaînes entières** pour exclure ce qu'elle croit forcé, donc elle se taît sur ce chemin — il n'est ni jugé, ni défait, ni nommé.

**Blocked by:** None

**Write-surface:** `.claude/lib/gate.sh`, `test/gate.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

- [ ] Un chemin caché dont le nom contient une espace est forcé dans l'arbre jugé comme n'importe quel autre : l'itération qui l'a caché est jugée à travers les règles qu'elle a reçues, ce que [30] promet déjà.
- [ ] La même correction pour les chemins gardés (`GUARDED_PATHS` et les chemins scellés), qui empruntent la même boucle : un projet dont le répertoire gardé porte un espace n'a pas de garde du tout aujourd'hui.
- [ ] Les deux moitiés restent d'accord : ce que le forçage n'a pas pu prendre doit être **nommé** par la ligne de zone, jamais tu. Un correctif qui répare le forçage sans vérifier ce point laisse le pire des deux mondes ouvert le jour où le forçage échoue pour une autre raison — un pathspec refusé est déjà un cas prévu et silencieux dans cette fonction.
- [ ] Le test porte le témoin appairé : le même scénario avec un nom sans espace doit rougir, sinon il ne prouve rien sur l'espace.
- [ ] La mutation vise le passage des chemins, pas le contenu de la liste.

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
