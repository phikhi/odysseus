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

- **Contrainte pour [18].** L'en-tête de `lib/tracker.sh` pose « un id par ligne »
  comme une clause de l'interface des backends depuis [37]. Ce ticket peut la
  changer ; s'il le fait, c'est cette phrase-là qu'il faut réécrire, pas seulement
  le backend local — un adaptateur distant lit ce contrat et rien d'autre.
