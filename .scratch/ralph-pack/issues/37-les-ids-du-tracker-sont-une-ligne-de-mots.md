# 37 — Les ids du tracker sont une ligne de mots

**What to build:** Faire passer les ids du tracker par la convention que [33] a posée pour les chemins — une entrée par ligne, lue ligne par ligne — au lieu d'une ligne de mots recoupée par `for id in $(tracker_ids)`. `tracker_local_ids` rend un id par ligne, et un id est un **nom de fichier que la session choisit** : `99-my ticket.md` donne l'id `99-my ticket`, qu'un `for` découpe en deux ids inexistants. `failures_tracker_snapshot` va plus loin et rejoint tout par des espaces (`printf ' %s' "$(tracker_ids | tr '\n' ' ')"`) avant que `failures__strays` ne compare mot à mot (`case "$seen" in *" $id "*`). Sept appelants font le même découpage.

**Blocked by:** None

**Write-surface:** `.claude/lib/failures.sh`, `.claude/lib/tracker.sh`, `.claude/lib/claim.sh`, `.claude/lib/gate.sh`, `.claude/loop.sh`, `test/failures.bats`, `test/tracker-local.bats`, `test/claim.bats`, `test/gate.bats`, `test/receipt.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md` — les cinq derniers ajoutés en cours de livraison, voir le commentaire « au-delà de ses sept boucles »

**Status:** resolved

- [x] Un ticket dont le nom de fichier porte une espace est vu comme **un** id par la détection d'intrus (`failures__strays`), mis en quarantaine sous ce nom-là, et renuméroté par `tracker_renumber` comme n'importe quel autre.
- [x] Les sept `for id in $(tracker_ids)` du pack (`claim.sh`, `failures.sh`, `gate.sh`, `tracker.sh` ×4) lisent ligne par ligne : un id à espace n'est plus deux ids fantômes, et un id à métacaractère n'est plus remplacé par ce que le glob trouve dans le répertoire courant.
- [x] Le format d'échange de `failures_tracker_snapshot` suit la même convention que le reste du pack depuis [33] — un id par ligne — et son lecteur compare des lignes entières.
- [x] Le test porte le témoin appairé : le même scénario avec un nom sans espace doit rougir, sinon il ne prouve rien sur l'espace. Et un id à métacaractère (`99-a[0]`) est couvert, sinon la moitié glob du défaut reste ouverte.
- [x] La mutation vise le passage des ids, pas le contenu du tracker.

## Comments

- **Origine : livraison de [33], le 04/08/2026.** [27] avait nommé cette famille et laissé le producteur en place, en écrivant que si un correctif touchait la convention de liste du pack, ces deux fonctions devaient être **décidées avec lui**. [33] a touché la convention — toute liste que le pack se passe à lui-même voyage à raison d'une entrée par ligne, les chemins gardés et scellés sont lus littéralement — et la décision est : **même convention, ticket séparé**, parce que ce n'est pas le même espace de noms. [33] tenait des chemins de fichiers dans `gate.sh` et `lenses.sh` ; ici il s'agit de l'espace d'ids du tracker, sept appelants dans quatre libs, et la moitié de la question est de savoir jusqu'où un id à espace survit *ailleurs* que dans ces boucles (résolution `Blocked by:`, `tracker_field`, `tracker_renumber`, le prompt de session).

- **Ce qui rend le défaut atteignable, et c'est la frontière de confiance.** Un id n'est pas une donnée du pack, c'est le nom d'un fichier qu'une session dépose dans `issues/`. C'est exactement le corollaire de [27] — « une borne calculée à partir d'un nom de fichier qu'une session choisit n'est pas une borne » — appliqué non plus au numéro mais au découpage. La sonde à écrire : une session qui crée `.scratch/<feature>/issues/99-my ticket.md`, puis regarder ce que `failures_quarantine_strays` met en quarantaine et sous quel nom.

- **Piège attendu.** `tracker_renumber` et la quarantaine manipulent le nom de fichier ; un id à espace y arrive comme argument, ce qui est correct tant que tout est cité. Le vrai risque est ailleurs : un id à espace qui traverserait la boucle et finirait dans `Blocked by:` — champ dont [27] dit qu'il se lit par `tr ',' ' '`, donc un troisième découpage en mots, dans un troisième format rédigé par un humain. Décider aussi de celui-là, ou écrire pourquoi il reste tel quel : un `Blocked by:` est de la prose de ticket, comme le champ `Write-surface:`, et [33] a laissé les formats rédigés inchangés en les convertissant à la lecture. La réponse est probablement la même — mais elle doit être écrite, pas supposée.

- ~~**Contrainte pour [21].** `gate_tree_snapshot "$(failures__issues_path)"` — la branche à pathspecs — passe encore son chemin sans `:(literal)`.~~ **Fait par [34], le 04/08/2026**, qui devait de toute façon énumérer tous les appelants de cette fonction : la branche à pathspecs passe `:(literal)` et un `git add` par chemin, la décision de type étant la même que pour les chemins gardés — un chemin, pas un glob. Test `a path handed to the snapshot is taken literally, not as a pattern` (gate.bats), avec sa réfutation (`zone1/` ne doit pas entrer). Ce qui reste ici : la protection du tracker snapshotte maintenant *le bon répertoire* quel que soit le nom de la feature, mais tout ce qui **compare** des ids continue de les recouper en mots — c'est le sujet de ce ticket, et le `:(literal)` ne le referme pas.

- **Contrainte héritée de [34], à sonder ici.** `gate_tree_snapshot` refuse désormais explicitement dans sa branche à pathspecs : pas de `|| true` sur le `git add`, donc un pathspec qui ne matche rien fait tomber la fonction sous `set -e` et l'appelant n'obtient aucun arbre — ce qui est la bonne réponse pour un garde (un arbre vide se lirait « la session n'a rien changé »). Un id ou un `FEATURE` que ce ticket rend traversable ne doit pas transformer ce refus en silence : la sonde à faire est un tracker dont le répertoire existe et un ticket dont le nom porte une espace, en vérifiant que le refus tombe seulement quand il doit tomber.

- **Livré le 27/08/2026.** Ce que les sondes ont montré avant correctif
  (`.scratch/ralph-pack/sondes/37/`, `s1-espace.bats` et `s2-ailleurs.bats`) —
  quatre conséquences distinctes, pas une :

  1. **La quarantaine annonce avoir agi sur un ticket qu'elle a laissé sur la
     frontière.** `99-my ticket.md` devient deux intrus (`99-my`, `ticket`), le
     renumber refuse les deux par leur nom, `tracker_mark_escalated` échoue
     derrière son `|| true`, et le journal écrit
     `quarantined 99-my ticket` — les deux fantômes recollés — pendant que le
     fichier reste `ready-for-agent` avec le `Write-surface: *` que la session
     s'est accordé. C'est un **faux livré** au sens de [35], obtenu sans rien
     d'hostile de plus qu'une espace dans un nom de fichier.
  2. **Le registre de [13]/[42] exempte par mot.** La boucle réclame
     `99-my ticket` (un nom qu'un humain a parfaitement le droit d'écrire), la
     clôture rend ` 99-my ticket `, et un intrus nommé `99-my` matche
     `*" 99-my "*` : la quarantaine est **contournée**, pas seulement bruyante.
     Sondé (s2b) : `rc=0`, rien mis en quarantaine, `99-my` reste
     `ready-for-agent`.
  3. **`gate__surface_owner` ne trouve plus le propriétaire.** Les ids découpés ne
     résolvent rien, `gate_write_surface` rend vide, donc un débordement dans la
     surface déclarée d'un autre ticket revient classé **intrus retryable** au
     lieu de `contract`. Le seul travail de cette fonction est de dire que ce
     n'est pas retryable.
  4. **Une réclamation sur un tel ticket n'est jamais balayée.** `claim_reclaim_stale`
     interroge `tracker_field` sur deux ids inexistants, les deux lectures
     échouent, `continue`, et le ticket réellement réclamé par un run mort reste
     `claimed` **définitivement** — le défaut que [12] a fermé, rouvert pour tout
     tracker dont les noms de fichiers ne sont pas un seul mot.

  Le côté glob est la même expansion et pas la même panne : `99-a[0]` est
  **remplacé** par ce que le répertoire courant contient (sondé, s1c : l'intrus
  rapporté est `99-a0`). D'où deux tests et deux entrées de mutation, jamais une.

- **Ce que le ticket a changé au-delà de ses sept boucles, et pourquoi.** Le
  ticket nommait sept `for id in $(tracker_ids)` et le format d'échange de
  `failures_tracker_snapshot`. Trois autres listes du **même espace de noms**
  voyageaient en mots et ont été converties, parce que les laisser aurait gardé le
  défaut ouvert derrière une correction qui a l'air complète :
  - le **registre** (`tracker_writes_since` → une ligne par id, lu par
    `failures__in_list`) — c'est la trouvaille 2 ci-dessus, et c'est la plus
    grave : un contournement de quarantaine, pas un affichage ;
  - les **ids en vol** (`loop__inflight_ids`, dans `loop.sh`), consommés par
    `claim_reclaim_stale` ;
  - les accumulateurs de la quarantaine (`kept`, `renamed`) et leur rendu
    (`failures__join`), qui recollaient deux ids dans la note qu'un humain lit
    pour aller trouver le fichier.
  **Write-surface élargie en conséquence** : `.claude/loop.sh`, `test/claim.bats`,
  `test/gate.bats`, `test/receipt.bats` (ce dernier assertait la clôture d'espaces
  du registre, `register=[ 01-alpha ]`).

- **La décision sur `Blocked by:`, écrite et pas supposée.** Le champ reste de la
  prose à virgules, convertie à la lecture — la réponse que [33] a donnée aux
  formats rédigés. Ce qui rend la réponse *identique* et pas seulement analogue :
  une dépendance est un **numéro nu** ([27]), la boucle jette déjà tout mot qui ne
  commence pas par un chiffre, et une dépendance qui ne résout rien bloque déjà en
  fail-safe. Donc `Blocked by: 99-my ticket` tient le ticket hors de la frontière,
  ce qui est le verdict sûr et celui qu'un humain peut lire. Écrit dans
  `tracker_preflight` au-dessus de la boucle, là où le prochain lecteur le
  cherchera.

- **Ce que le piège attendu a donné.** Le ticket craignait la renumérotation et la
  quarantaine, qui manipulent le nom de fichier. Rien à faire : tout y était déjà
  cité (`tracker_local__path` protège même son glob, `"$dir/$id"-*.md` — les
  métacaractères de `$id` sont entre guillemets, seul le `-*` final est un motif).
  Le vrai piège était ailleurs, en trois exemplaires, et c'est la trouvaille 2 :
  **les clôtures de mots**, qui ne cassent pas sur un id à espace — elles
  répondent *oui* pour chacun de ses mots.

- **La contrainte héritée de [34], sondée.** `gate_tree_snapshot` dans sa branche
  à pathspecs refuse sans `|| true`. Rien ici ne la traverse : la protection du
  tracker passe le **répertoire** `.scratch/<feature>/issues`, jamais un id. Un id
  à espace ne devient jamais un pathspec, donc le refus tombe toujours quand il
  doit et jamais autrement.

- **La limite qui reste, et elle est structurelle.** La convention du pack est
  *une entrée par ligne* ; un nom de fichier unix peut contenir un **saut de
  ligne**. Un ticket nommé `99-a<LF>b.md` est donc toujours coupé en deux, et le
  correctif de ce ticket ne l'atteint pas — il déplace la frontière de « tout
  caractère de séparation de mots ou de glob » à « le seul saut de ligne ». Ce
  n'est plus silencieux (`failures__gap` dit `could not give 99-a a number of its
  own`), mais le ticket reste sur la frontière avec la surface qu'il s'est
  accordée. Le refermer demanderait des listes délimitées par NUL, ce qu'un
  heredoc ne peut pas porter — c'est une réécriture du transport, pas une ligne.
  Consigné dans `docs/frontiere-de-confiance.md` et ouvert comme [48].

- **Ce que le ticket suivant hérite.** L'espace d'ids voyage désormais partout à
  raison d'un id par ligne, comparé **ligne entière** (`failures__in_list`,
  `claim__among`, `tracker__holds_exactly`). Pour [18] (backends distants) : un
  adaptateur doit rendre `ids` et `frontier` **un id par ligne** — c'est écrit
  dans l'en-tête de `lib/tracker.sh`, et un backend qui rendrait une ligne de mots
  rouvrirait les quatre pannes ci-dessus d'un coup. Pour [47]
  (`tracker_open_ticket` sans verrou) : la réparation qui allouera les numéros
  travaille sur cette liste-là, et elle est maintenant sûre à lire.

- **Nouvelle baseline des deux gates.** `bash test/run.sh` = **514 tests, 0 failures,
  6 skips opt-in** (505 + 9 : quatre dans `failures.bats`, deux dans
  `tracker-local.bats`, deux dans `claim.bats`, un dans `gate.bats`).
  `bash test/mutate.sh` = **485 mutations, 0 not ok** (477 + 8). Mesuré d'un coup sur
  une seule passe, aucun nom toléré — comme depuis [38], tout rouge est une régression.

- **Une entrée d'un autre ticket a dérivé, et c'est la bonne nouvelle.** La première
  passe a rendu `DRIFTED 13 the sweep reclaims the claims this run is holding` :
  l'exemption des ids en vol était un `case "$held" in *" $id "*` inline, elle est
  maintenant un appel à `claim__among`. La garantie est **toujours portée** —
  vérifié avant de bouger l'ancre, en relançant l'entrée recalée (`ok`, le test de
  `concurrency.bats` rougit sans la ligne). Aucune des 485 entrées ne cible
  `test/mutate.sh`, donc l'éditer ne peut pas décaler les ancres des autres ; les
  deux gates ont quand même été relancés en entier plutôt qu'annoncés sur
  « 484 + une entrée rejouée ».

- **Le témoin appairé, vérifié et pas supposé.** Mutation `37 the strays are recut
  into words` appliquée à la main : `without the space` reste **vert**,
  `ghosts` rougit sur `strays[99-my|ticket|]`. Le témoin n'est donc pas un doublon
  du cas à espace — c'est ce que l'AC 4 demandait.
