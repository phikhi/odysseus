# 48 — Un nom de ticket qui porte un saut de ligne

**What to build:** Décider ce que le pack fait d'un fichier de ticket dont le nom
contient un **saut de ligne**, et le tenir. Depuis [37] toute liste d'ids voyage à
raison d'un id par ligne et se compare ligne entière ; c'est ce qui referme l'espace
et le métacaractère de glob, et c'est aussi ce qui laisse le saut de ligne ouvert —
la convention *est* le séparateur. Un `99-a<LF>b.md` déposé par une session est donc
encore vu comme **deux** ids qui ne résolvent rien.

**Blocked by:** None

**Write-surface:** `.claude/lib/tracker-local.sh`, `.claude/lib/failures.sh`,
`test/tracker-local.bats`, `test/failures.bats`, `test/mutate.sh`,
`docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

- [ ] Un ticket dont le nom de fichier porte un saut de ligne ne produit plus d'id
      fantôme sur la frontière : soit il est adressable, soit il est refusé — mais
      pas « annoncé mis en quarantaine » alors qu'il est resté `ready-for-agent`.
- [ ] La ligne de journal ne ment plus. Aujourd'hui `failures_quarantine_strays`
      écrit `quarantined 99-a, b` sans avoir escaladé quoi que ce soit ; un contrôle
      qui annonce avoir agi est exactement ce que `docs/frontiere-de-confiance.md`
      existe pour attraper.
- [ ] Le test porte le témoin appairé : le même scénario avec un nom d'une seule
      ligne doit rester vert, sinon il ne prouve rien sur le saut de ligne.
- [ ] La ligne de `docs/frontiere-de-confiance.md` ouverte par [37] est mise à jour
      avec ce qui tient réellement, ou avec l'aveu que la décision est de refuser.

## Comments

- **Origine : livraison de [37], le 27/08/2026.** Sonde conservée :
  `.scratch/ralph-pack/sondes/37/s3-saut-de-ligne.bats`, tournée **après** correctif
  — ce qu'elle mesure est ce qui reste, pas ce que [37] a fermé. Sortie :
  `ids[01-alpha|99-a|b|]`, `strays[99-a|b|]`, deux `could not give … a number of its
  own`, `quarantined 99-a, b`, statut du fichier réel `ready-for-agent`, et
  `tracker_frontier` rend `01-alpha|99-a|b|`.

- **Ce que ça coûte réellement, et pourquoi ce n'est pas un faux vert.** Les deux
  fantômes entrent dans la frontière mais aucun n'est réclamable — `tracker_claim`
  échoue, l'itération compte stérile, et le run s'arrête sur `STERILE_K`. Donc :
  un run qui ne broie rien, une ligne de journal qui ment, et un ticket que la
  session s'est écrit avec la surface de son choix mais que personne ne peut broyer.
  À ordonner comme tel : ce n'est pas la gravité qui décide dans ce dépôt, c'est la
  reprise — et ce ticket ne bloque personne.

- **Les deux directions, à trancher explicitement.** *Refuser* est bon marché : le
  backend local peut ne pas rendre un nom qui contient un `\n` et le dire une fois,
  mais un ticket invisible est pire qu'un ticket inadressable si personne ne lit la
  ligne. *Porter* le nom demande un transport délimité par NUL — `read -d ''`,
  `find -print0` — qu'un heredoc ne peut pas véhiculer : c'est une réécriture du
  passage, pas une ligne, et elle toucherait les huit lecteurs que [37] vient
  d'unifier. Écrire la décision, pas seulement le correctif.

- **Ce que [39] laisse à ce ticket, livré le 27/08/2026.** Deux choses, et la
  première change le décor. (1) `failures_protect_tracker` lit `issues/` par un
  `diff-tree --name-status` qui passe désormais `core.quotePath=false`, donc un
  ticket dont le nom porte un **accent** est adressable et n'a jamais été le sujet
  ici ; ce qui reste sur ce chemin est exactement le résidu que git cite quoi que
  dise ce réglage — saut de ligne, tabulation, guillemet, contre-oblique. (2) La
  question « porter ou refuser » a déjà été tranchée pour les listes de **chemins**
  et la ligne du tableau de confiance porte l'argument complet : `-z` a été refusé
  parce que le quotage de git protège la convention — un nom à saut de ligne arrive
  comme **une** ligne citée, donc il ne coupe jamais une liste en silence, et
  chaque consommateur peut le refuser à voix haute. **Ce sondage vaut ici et il
  change la moitié « porter » de la décision** : le transport délimité par NUL
  n'est pas nécessaire pour *voir* le nom d'un seul tenant, il ne l'est que pour
  *l'adresser*. Vérifier avant de bâtir : la sonde `s3-saut-de-ligne.bats` a été
  écrite avant [39] et le producteur qui l'alimente a changé — un id fantôme
  produit par un `ls` n'est pas un id fantôme produit par `diff-tree`, et les deux
  lecteurs du tracker ne passent pas par le même.

- **Contrainte pour [18].** L'en-tête de `lib/tracker.sh` pose « un id par ligne »
  comme une clause de l'interface des backends depuis [37]. Ce ticket peut la
  changer ; s'il le fait, c'est cette phrase-là qu'il faut réécrire, pas seulement
  le backend local — un adaptateur distant lit ce contrat et rien d'autre.

- **Le sondage que le commentaire ci-dessus réclamait est fait, le 30/08/2026, et
  il tranche la moitié « porter » de la décision.** Sonde jetable (deux `pack_run`,
  reproduction en trois lignes ci-dessous), plus `s3-saut-de-ligne.bats` rejouée sur
  `82acfcf`. **Il n'y a qu'un producteur cassé, pas deux.**

  Le lecteur **git** de `issues/` est déjà correct depuis [39] + [49]. Le nom arrive
  sur **une seule ligne**, cité par git quoi que dise `core.quotePath` —
  `sed -n l` rend `A\t".scratch/demo/issues/99-a\nb.md"$` — et
  `failures_protect_tracker` le nomme puis refuse de vouer :

      ralph: 01-alpha: ".scratch/demo/issues/99-a\nb.md" moved in the tracker under
        a name this guard cannot address — nothing was put back for it
      ralph: 01-alpha: a path in the tracker moved under a name this guard cannot
        address — nothing here can vouch for the tracker, so the iteration cannot be green

  Le lecteur **glob** est le seul qui casse : `tracker_ids` et `tracker_frontier`
  rendent `01-alpha|99-a|b|`, et `failures_quarantine_strays` annonce
  `quarantined 99-a, b` en laissant le fichier intact.

  **Conséquence pour la décision.** « Porter » (transport NUL) n'achète plus que la
  capacité de **broyer** un ticket qu'un autre garde du même run refuse déjà de
  vouer — donc une itération qui ne peut pas être verte — et que [07]/[21] mettent
  de toute façon en quarantaine puisqu'une session l'a créé. La moitié « porter »
  est donc sans motif : **refuser au producteur glob**, à voix haute, et l'écrire.
  La clause d'interface « un id par ligne » de `lib/tracker.sh` **ne change pas** ;
  ce ticket lui en ajoute une, additive : *un backend ne rend jamais un id qui
  contient un saut de ligne*. `lib/tracker.sh` reste hors de la write-surface.

  **Et une chose que ni la sonde s3 ni ce ticket ne disaient** : dans un run réel
  les deux lecteurs parlent en même temps sur le même nom. L'itération est rouge
  (le garde git refuse de vouer) **et** la frontière est polluée par deux fantômes
  irréclamables. Le test du correctif doit couvrir les deux, sinon il prouve la
  moitié de la panne.

  **Conséquence pour l'ordre** : l'arête `[48] → [18]` passe de forte à moyenne (une
  clause additive, pas une réécriture de contrat), et les arêtes `[48] → [16]` et
  `[48] → [11]` tombent à zéro — aucun format ne change, et personne ne bâtit contre
  des ids fantômes.

  Reproduction :

      before="$(failures_tracker_tree)"
      printf '...' >"$(ralph_feature_dir)/issues/99-a"$'\n'"b.md"
      failures_protect_tracker 01-alpha "$before"
