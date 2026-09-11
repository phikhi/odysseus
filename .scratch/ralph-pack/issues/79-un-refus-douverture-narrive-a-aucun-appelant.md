# 79 — Un refus d'ouverture n'arrive à aucun appelant

**What to build:** Que le refus qu'un adaptateur rend sur `open_unique` atteigne les deux appelants qui ouvrent des tickets — et que la branche que `playthrough_close` porte déjà pour ce cas cesse d'être du code mort.

**Blocked by:** None

**Write-surface:** `.claude/lib/playthrough.sh`, `.claude/lib/capability.sh`, `test/playthrough.bats`, `test/capability.bats`, `test/mutate.sh`

**Status:** resolved

- [x] Un `tracker_open_unique` qui **refuse** est distingué d'un `tracker_open_unique` qui n'a rien ouvert parce qu'un ticket portait déjà le slug : les deux appelants savent lequel des deux vient d'arriver.
- [x] La branche `openrc != 0` de `playthrough_close` est atteignable, et un test la fait passer — elle existe depuis [65] et n'a jamais pu s'exécuter.
- [x] La ligne de reçu de `capability__propose_from_retro` cesse de dire « soit une était déjà en attente, soit le tracker a refusé l'écriture » quand le pack sait laquelle des deux.
- [x] Rien ne change quand l'ouverture réussit ni quand le slug est déjà pris : c'est le troisième cas seul qui gagne un canal.

## Comments

- **Trouvé en livrant [78] (10/09/2026)**, en posant la question du run réel : le
  ticket a donné à `forge_open_unique` un statut non nul pour dire « je n'ai pas
  pu savoir », et ce statut traverse `tracker__dispatch` intact — puis meurt chez
  l'appelant.

- **Le mécanisme, sondé et pas déduit.** Les deux appelants finissent par
  `return 0` :

      capability_propose()   `tracker_open_unique … <<BODY … BODY` puis `return 0`
      playthrough__inject()  idem

  et `playthrough_close` les lit sous `id="$(playthrough__inject …)" || openrc=$?`.
  Sous `|| …`, errexit est suspendu **pour toute l'extension dynamique**, donc y
  compris à l'intérieur de la substitution de commande : un `return 7` dans la
  fonction appelée n'interrompt rien, `return 0` gagne, et `openrc` vaut 0 quoi
  qu'il arrive. Sonde minimale, à rejouer avant d'écrire :

      set -euo pipefail
      inner() { return 7; }
      wrapper() { inner; printf 'x\n'; return 0; }
      rc=0; id="$(wrapper)" || rc=$?
      printf 'id=[%s] rc=%s\n' "$id" "$rc"     # → id=[x] rc=0

- **Ce que ça coûte.** `playthrough_close` porte déjà quatre branches distinctes
  pour ce que « rien n'a été ouvert » peut vouloir dire, dont celle-ci :

      outcome="an internal wiring hole the tracker refused to open a ticket for
               — asking a human instead: $hole"

  écrite en toutes lettres avec son commentaire (« Not the same as *already
  there*, et distingué parce que les deux mènent un lecteur à deux endroits »).
  Elle n'a jamais pu s'exécuter. Un tracker qui refuse d'ouvrir fait donc dire au
  gate de valeur « un trou de câblage que le tracker porte déjà sous le slug que
  ce gate aurait utilisé, et ce run ne l'a pas ouvert » — c'est-à-dire la phrase
  qui accuse une contrefaçon, sur un tracker qui n'a simplement pas répondu.

- **`capability_propose` n'est pas le même cas, et c'est la décision du ticket.**
  Son contrat est écrit (« le caller lit le vide, jamais un code de sortie, parce
  que *déjà en attente* est un succès ») et trois appelants en dépendent
  (`capability__propose_from_retro`, `retro__escalate`, `playthrough__escalate`).
  Le rendre non nul sur un refus est un changement d'interface, pas une
  correction de fuite : soit un second canal (une variable de statut que
  l'appelant lit), soit assumer le changement et reprendre les trois appelants.
  `playthrough__inject`, lui, n'a pas de contrat écrit — son `return 0` est une
  habitude, et son unique appelant sait déjà quoi faire du refus.

- **Piège de harnais**, hérité de [78] : `set_config FORGE_PAGE 2` +
  `set_config FORGE_PAGES 1` avec deux issues fait refuser **tous** les listings
  d'un run sans simuler de panne, et c'est la façon la moins chère de faire
  refuser une ouverture. Sur le backend local, `state_guard_take` non obtenu est
  l'autre refus atteignable.

- **La ligne du tableau de confiance existe déjà** (`docs/frontiere-de-confiance.md`,
  ligne « Ce que `tracker_ids` et `tracker_frontier` rendent est **tout** le
  tracker », dernier paragraphe) : elle nomme ce résidu et désigne ce ticket. La
  mettre à jour fait partie des AC.

## Livré le 11/09/2026

- **La sonde du ticket a été rejouée avant d'écrire, et elle dit ce qu'elle
  annonçait** : `rc=0; id="$(wrapper)" || rc=$?` avec un `return 7` dans la
  fonction appelée rend `id=[x] rc=0`. La même forme avec le producteur qui
  propage (`cmd <<BODY || rc=$?` puis `return "$rc"`) rend `rc=7`, y compris à
  travers un pipeline (`printf … | wrapper`), qui est la façon dont
  `capability_review` lit `capability_propose`.

- **Décision prise : le changement d'interface, pas un second canal.** Le ticket
  laissait les deux ouvertes ; le second canal est **impossible** ici et c'est
  mesuré, pas préféré : les trois appelants de `capability_propose` la lisent
  tous à travers une substitution de commande, donc une variable de statut
  écrite dedans meurt au retour — c'est exactement [65] (`playthrough__note_opened`
  est appelé depuis `playthrough_close` pour cette raison). Le statut est le seul
  canal qui traverse un sous-shell.

- **Les trois appelants, repris un par un.**
  - `capability_review` (c'est son nom, pas `capability__propose_from_retro` —
    le ticket nommait une fonction qui n'existe plus) lit `|| prc=$?` au lieu de
    `|| id=''` : l'affectation laisse déjà `id` vide sur un refus. Le reçu a
    trois branches là où il en avait deux, et la phrase « soit… soit… » a
    disparu.
  - `playthrough__escalate` propage aussi, et `playthrough__asked` — nouvelle,
    trois appelants dans `playthrough_close` — en fait la clause que les phrases
    portent. **C'est ce que le ticket ne demandait pas et que le scénario de son
    propre test a rendu obligatoire** : dans un run où le garde d'ouverture est
    tenu, l'escalade est refusée elle aussi, et la ligne se serait arrêtée sur
    « asking a human instead » alors que le puits n'avait rien reçu. Les deux
    chemins qui marchaient n'ont pas bougé : la forme `(on <id>)` est inchangée.
  - `retro__escalate` garde son `return 0`, **délibérément** : `retro.sh` est
    hors de la write-surface de ce ticket, et sa phrase (« soit une était déjà en
    attente, soit le tracker a refusé ») reste *vraie* pour ce que cet appelant
    sait. Le canal existe maintenant ; le lire est une ligne dans `retro_close`
    pour qui voudra la prendre. C'est le seul résidu connu de [79].

- **Écart de write-surface, assumé et écrit ici.** La write-surface déclarée
  disait `playthrough.sh`, `capability.sh`, `test/playthrough.bats`,
  `test/capability.bats`, `test/mutate.sh`. Deux fichiers de plus ont été
  touchés, tous les deux côté test : `test/helpers/harness.bash` (la mise en
  scène `hold_open_guard`/`release_open_guard`) et `test/tracker-local.bats` (sa
  copie locale de la même mise en scène, retirée). Raison : la copie de
  `test/tracker-local.bats` tenait le garde avec `sleep 30 &`, ce qui est correct
  devant un `pack_run` et un **faux vert silencieux** devant un `run_loop` plus
  long que la devinette — le garde redevient récupérable et l'ouverture
  *réussit*. La version du harnais tient le garde avec le pid du test, qui
  survit par construction à tout ce qu'il lance. Une troisième copie aurait été
  la troisième version d'une mise en scène dont deux se comportent différemment.

- **Pourquoi le garde d'ouverture et pas le plafond de pages.** Le ticket
  proposait `FORGE_PAGE 2` + `FORGE_PAGES 1` comme refus le moins cher. Sondé :
  ce refus-là arrête le run **avant** le gate de valeur — depuis [74] une
  frontière illisible est un `exit 4` et `playthrough_call_count` vaut `0`
  (c'est l'assertion de `test/tracker-remote.bats`, « a listing the forge refused
  does not start the terminal value gate »). Il ne peut donc pas mettre en scène
  la branche `openrc != 0`. Le garde d'ouverture du backend local est le seul
  refus atteignable qui laisse le run arriver jusqu'au gate de valeur. Coût
  mesuré : ~6 s par ouverture refusée (120 essais × 0,05 s), deux par run dans le
  test de `playthrough.bats`.

- **Ce que le défaut disait vraiment, et pourquoi les deux refutations du test
  comptent autant que l'assertion.** Avant le correctif, un tracker qui refuse
  faisait tomber `playthrough_close` dans sa dernière branche — « the tracker
  already carries a ticket for under the slug this gate would have used, and this
  run did not open it » — c'est-à-dire la phrase qui **accuse** une session
  d'avoir forgé un ticket. Le test refuse les deux moitiés de cette phrase
  (`already carries a ticket for`, `did not open it`) en plus d'exiger celle du
  refus.

- **Piège de mutation rencontré** : l'entrée `11 the same hole opens a second
  ticket instead of asking a human` s'ancre sur la ligne `tracker_open_unique …
  <<BODY`, qui a gagné ` || rc=$?`. Elle aurait rendu DRIFTED ; elle est mise à
  jour dans le même commit. C'est le réflexe de [80]/[81] : greper `test/mutate.sh`
  pour les lignes qu'on touche avant de livrer.

## Place dans la file

**Validée par Philippe le 10/09/2026, à la passe transversale du même jour.** La
file devient **[80] → [81] → [79] → [82] → [75] → [73] → [19]**. Le critère est
celui du dépôt — minimiser la reprise, jamais l'urgence — avec la seule exception
que ce dépôt s'autorise et qu'il a déjà payée : **un faux vert livré passe
devant**, comme [76] l'a fait à la passe du 08/09.

1. **[80]** — le faux vert livré du lot ([40] rouvert par un glob). Il tranche
   aussi ce qui reste à [81] : la seule chose que « recenser et vérifier » ne peut
   pas attraper.
2. **[81]** — même zone (`$TMPDIR`), et il consomme la décision de [80]. Livrés
   voisins, ils s'écrivent contre une seule relecture de `loop.sh` et de
   `gate.sh`.
3. **[79]** — petit, indépendant, position libre. Placé ici parce qu'il ferme le
   résidu de [78] avant que la file ne reparte sur un autre chantier.
4. **[82]** — la famille des refus de lecture, et il touche `forge.sh` comme [75].
5. **[75]** — le cache, qui donne son budget à la remise de [73].
6. **[73]** — la remise, qui hérite de la clause de [82] autant que du cache de
   [75].
7. **[19]** — l'installeur lit ce que les six autres décident.

**`Blocked by:` reste `None` pour [79], [80], [81] et [82], et c'est une
décision** — le précédent est celui que [78] a écrit : la position dans la file
est un choix d'ordonnancement, pas une dépendance, et écrire une fausse arête
ferait sortir un ticket de la frontière si son voisin était mis de côté. Les
arêtes réelles ne bougent pas : `[75] 77`, `[73] 74, 75, 77`,
`[19] 73, 74, 75, 76, 77`.
