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

**Status:** ready-for-agent

- [ ] Une lentille déclenchée sur un fichier dont le nom porte un métacaractère de
      glob reçoit le diff **de ce fichier**, ou ne reçoit rien en le disant. Pas le
      diff d'un voisin.
- [ ] Le témoin appairé : le même scénario avec un nom ordinaire reste vert, sinon le
      test ne prouve rien sur le métacaractère ([48] pose la même exigence).
- [ ] L'entrée de mutation existe et rend le test rouge. C'est la raison pour
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
