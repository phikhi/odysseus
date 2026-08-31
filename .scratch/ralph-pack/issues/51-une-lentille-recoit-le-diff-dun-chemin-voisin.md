# 51 — Une lentille reçoit le diff d'un chemin voisin

**What to build:** Fermer la dernière lecture d'un chemin comme **motif** dans le
pack. `lenses.sh` bâtit le prompt d'une lentille avec
`git diff-tree -p --no-color "$base" "$tree" -- "$file"`, où `$file` sort de
`gate_changed_files` : c'est un chemin, et git le lit comme un pathspec, donc comme
un motif. Un fichier réellement nommé `src/zone[1].ts` fait montrer à la lentille le
diff de `src/zone1.ts` — ou rien du tout. Un modèle qui juge le mauvais diff rend un
verdict que rien ne vérifie ([06] : « le verdict d'une lentille dit la vérité →
Rien »), donc l'erreur ne se voit à aucun endroit.

**Blocked by:** None

**Write-surface:** `.claude/lib/lenses.sh`, `test/lenses.bats`, `test/mutate.sh`

**Status:** resolved

- [x] Une lentille déclenchée sur un fichier dont le nom porte un métacaractère de
      glob reçoit le diff **de ce fichier**, ou ne reçoit rien en le disant. Pas le
      diff d'un voisin.
- [x] Le témoin appairé : le même scénario avec un nom ordinaire reste vert, sinon le
      test ne prouve rien sur le métacaractère ([48] pose la même exigence).
- [x] L'entrée de mutation existe et rend le test rouge. C'est la raison pour
      laquelle [39] n'a **pas** livré ce correctif d'un caractère : `lenses.sh` et
      `test/lenses.bats` étaient hors de sa surface, donc aucune mutation ne pouvait
      le mesurer — et une réparation que rien ne rougit est une phrase dans un
      tableau, pas du code.

## Comments

- **Origine : livraison de [39], le 27/08/2026.** Trouvé en énumérant les lecteurs de
  `gate_changed_files` pour savoir lesquels héritaient du correctif de quotage.
  Celui-ci en hérite pour la famille non-ASCII — le nom arrive désormais tel quel,
  donc le `-- "$file"` matche — et reste ouvert pour la famille du **motif**, qui est
  celle de [33] et [34] et pas celle de [39].

- **Le correctif tient en un `:(literal)`**, exactement comme les trois que [39] a
  posés dans `gate_tree_snapshot`, `failures_make_durable`, `failures_rollback` et
  `concurrency__refresh`. Ce qui coûte, ici, c'est le test : il faut faire déclencher
  une lentille sur un fichier au nom métacaracté et lire ce que le prompt a réellement
  reçu. `test/lenses.bats` a déjà des tests qui inspectent le prompt d'une lentille —
  s'appuyer dessus plutôt que d'inventer un observatoire.

- **Vérifier les voisins avant de conclure.** `lenses.sh` construit aussi la liste des
  fichiers changés dans le même prompt (`gate_changed_files "$base" "$tree"`) et
  choisit les lentilles déclenchées par `gate_in_surface`, qui lit **des globs
  écrits par un humain** et doit continuer à le faire. La question à poser fichier par
  fichier est celle de [33] : cette liste-ci est-elle des chemins ou des motifs ? Une
  seule réponse par lecteur, et elle doit être écrite à côté.

## Livraison — 31/08/2026

- **Le défaut n'est pas celui que le ticket décrivait, et c'est la trouvaille.** Le
  ticket disait « fait montrer à la lentille le diff de `src/zone1.ts` — ou rien du
  tout ». Sondé avant d'écrire le test : **un pathspec git est wildmatché seulement en
  repli**, après un essai littéral. Donc le fichier nommé revient **toujours**, des
  deux côtés du correctif, et ce qui change est le **sur-match** — exactement ce que
  [39] avait déjà mesuré pour `gate_tree_snapshot` (commentaire de
  `test/gate.bats:1884`, « the mutation reported VACUOUS against a test that looked
  exactly right »). Un test écrit sur la formulation du ticket — « la lentille reçoit
  le diff du voisin **au lieu** du sien » — aurait été vert des deux côtés. La sonde :

      git diff-tree -p "$base" "$tree" -- 'src/zone[1].ts'
      → diff de src/zone1.ts, PUIS diff de src/zone[1].ts   (les deux)
      git diff-tree -p "$base" "$tree" -- ':(literal)src/zone[1].ts'
      → diff de src/zone[1].ts seul

  D'où la forme de l'assertion : le test **compte les en-têtes `diff --git`**, trois
  nombres (le fichier métacaracté : 1, le voisin : 1, le total : 2). Sous mutation :
  1 / **2** / 3. Un `refute_output_contains` sur le voisin était impossible — le
  voisin a changé lui aussi, donc son diff est légitimement dans le prompt une fois.

- **Ce que le sur-match coûte vraiment**, et c'est plus que du bruit : la lentille lit
  le changement d'un fichier sous l'en-tête d'un autre, **et** le diff dupliqué est
  compté deux fois contre `LENS_DIFF_MAX_LINES`. Sur une itération large, la troncature
  annoncée tombe donc plus tôt qu'elle ne le devrait, et ce qui est coupé est du diff
  qu'aucune lentille ne verra — sans que rien ne le dise autrement que par la ligne
  générique « cut at N lines ».

- **Le témoin appairé est un `@test` séparé** (`the same two files under ordinary
  names put one diff each in the prompt`), pas une assertion de plus dans le premier.
  Raison : le test du défaut asserte des **nombres**, et un compteur est précisément le
  genre d'assertion qui peut avoir raison sur la mauvaise chose — si `lenses__patch`
  cessait d'émettre un diff par fichier, ou si le compteur lisait le prompt de travers,
  le test du métacaractère resterait vert sur un mécanisme qui n'a plus rien de
  littéral. Vérifié **à la main** comme le demande la mémoire des pièges : mutation
  appliquée par `perl` sur `lenses.sh`, test du défaut rouge (`expected: 1, actual: 2`),
  témoin **vert**, puis correctif remis.

- **Le filtre de mutation (`not its neighbour`) ne matche qu'un test**, vérifié :
  `test/run.sh test/lenses.bats -f "not its neighbour"` → `1 tests`. Et le `-f` de
  `mutate.sh` est un **sous-chaîne littérale** (`case "$label" in *"$FILTER"*`), pas un
  glob : `-f "51 the lens diff*"` ne matche rien à cause de l'astérisque.

- **Les trois lecteurs de listes de ce module, une réponse chacun, écrite à côté**
  (AC 3) :
  1. `lenses__write_prompt`, `files="$(gate_changed_files ...)"` → **des chemins**, et
     rien ne les matche : la liste est imprimée dans le prompt pour qu'un modèle la
     lise. Un nom métacaracté y arrive tel qu'il est.
  2. `lenses__patch`, `-- "$file"` → **le défaut**. C'était le seul endroit du module
     qui rendait une entrée de cette liste à git comme un motif. Corrigé.
  3. `lenses__triggered_by`, les deux `gate_in_surface` → **des motifs des deux côtés,
     et ça doit rester**. Ni la write-surface d'un ticket ni `VISIBLE_PATHS` /
     `SECURITY_PATHS` ne sont des chemins sur le disque ; ce sont des globs écrits par
     un humain, et l'intersection est approximée dans la direction « déclencher la
     lentille », la seule sûre. Déjà documenté sur place depuis [33] ; inchangé.

- **Ce que le correctif ferme en plus, sans que le test le mesure : le deux-points
  initial.** Sondé : un fichier livré à la racine nommé `:odd.txt` fait de
  `-- ':odd.txt'` une **magie de pathspec** (git lit `:` puis la magie courte, ne
  reconnaît pas `o`, et le chemin devient `odd.txt`), donc la lentille n'aurait reçu
  **aucun** diff pour lui — le cas « ou rien du tout » que le ticket prêtait au
  métacaractère de glob. `:(literal)` le couvre aussi. Non testé ici : le nom est à la
  racine, donc hors de la write-surface `src/*` du scénario, et l'étendre demandait de
  sonder ce que le reste du pack fait d'un tel nom — hors sujet pour ce ticket. C'est
  écrit dans [54], à qui ce fait sert directement.

- **Trouvé et non réparé, dans ce fichier : `lenses_has_tag`.** Elle lit les tags par
  `for tag in $(tracker_field ... )`, non cité — donc glob-expansé contre le répertoire
  courant en plus d'être découpé en mots, la panne de la famille [33]/[37]. Portée
  réelle : les tags sont restaurés par [21] **avant** que les prédicats ne lisent, donc
  une session ne peut pas les écrire ; il faut un humain qui écrive un métacaractère
  dans un tag **et** un fichier du projet portant exactement le nom `visible` ou
  `security` pour que ça change une décision. Hors des AC de ce ticket et hors de sa
  famille (ce n'est pas un lecteur de `gate_changed_files`). Laissé pour la passe
  transversale qui suit immédiatement, qui décidera s'il vaut un ticket : c'est la
  dernière liste de ce module qui n'est jamais passée par `gate_authored_list`.

- **Tableau de frontière** : ligne « Le verdict d'une lentille dit la vérité » élargie.
  La case reste **Rien** — [51] ne rend pas un verdict vérifiable — mais sa première
  phrase (« un modèle frais qui juge le diff d'un autre ») supposait une prémisse que
  rien ne tenait, et qui est tenue maintenant.
