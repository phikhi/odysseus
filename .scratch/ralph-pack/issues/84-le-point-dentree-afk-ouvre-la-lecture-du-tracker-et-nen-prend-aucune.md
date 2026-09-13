# 84 — Le point d'entrée AFK ouvre la lecture du tracker et n'en prend aucune

**What to build:** Que le point d'entrée qui tourne toute la nuit prenne la lecture partagée de [75] aux moments où elle est juste, au lieu de payer le registre qui l'invalide sans jamais l'avoir prise.

**Blocked by:** None

**Write-surface:** `.claude/loop.sh`, `.claude/lib/tracker.sh`, `.claude/lib/forge.sh`, `test/tracker-remote.bats`, `test/loop-happy-path.bats`, `test/mutate.sh`

**Status:** resolved

- [x] `loop.sh` prend une lecture du tracker aux moments du run AFK où une lecture prise plus tôt serait fausse, et le ticket **nomme ces moments** — ce ne sont pas ceux du drain, parce que le run a des forks concurrents ([13]) que le drain n'a pas.
- [x] La clause que [75] a écrite dans `tracker.sh` — « *neither call is one an entry point may skip on a hunch* » — cesse d'être tenue par un commentaire : quelque chose refuse, ou dit, qu'un point d'entrée ouvre `cache_open` sans jamais appeler `cache_prime`.
- [x] La mesure est faite des deux côtés du même scénario, comme [75] l'a faite pour le drain : le nombre de listings d'un run AFK avec et sans la lecture, sur le même tracker, jamais contre un nombre écrit une fois.
- [x] Ce que la lecture partagée devient dans un fork concurrent est écrit : `MAX_PARALLEL > 1` fait travailler plusieurs itérations sur le même tracker, et une lecture héritée par un fork n'est pas invalidée par ce qu'un **frère** écrit.

## Comments

- **Trouvé à la passe transversale du 13/09/2026**
  (`../passe-transversale-13-09.md`, §2). Sonde :
  `../sondes/passe-13-09/q4-le-chemin-afk-ne-prend-aucune-lecture.bats`
  (Q4a, Q4b). Écrit une première fois en une phrase dans [73] le 12/09 (« un run
  AFK sur backend distant paie encore une lecture par question »), jamais mesuré
  avant.

- **Compté sur la source livrée :**

  | | `tracker_cache_open` | `tracker_cache_prime` |
  |---|---|---|
  | `human-loop.sh` (le drain) | 1 | **3** |
  | `loop.sh` (le run AFK) | 1 | **0** |

  Le run AFK prend le répertoire — donc le registre d'invalidation
  `tracker.writes`, donc le travail de l'alimenter à chaque écriture de ticket —
  et ne prend **jamais** la lecture que ce registre sert à invalider.

- **Mesuré** (Q4), même tracker de douze issues, même faux forge, listings
  comptés comme `test/tracker-remote.bats` les compte
  (`forge_calls | grep -c '^GET .*/issues?state='`) :

  | Point d'entrée | `FORGE_CACHE_TTL` par défaut | `FORGE_CACHE_TTL=0` | Ce que la lecture achète |
  |---|---|---|---|
  | `loop.sh`, 3 itérations (`ITER_CAP 3`) | **93** | 96 | **3 %** |
  | `human-loop.sh`, le même puits | **2** | 15 | **87 %** |

  31 listings par itération sur le chemin qui tourne toute la nuit. C'est le
  chemin que [75] décrivait comme celui où « a caller that asks six questions
  about forty tickets asks the service two hundred and forty times ».

- **La clause à respecter, mot pour mot** (`lib/tracker.sh`) :

  > *« And neither call is one an entry point may skip on a hunch: the two
  > moments `cache_prime` is called are the two where a reading taken earlier
  > would be wrong — the top of a ticket, and the return of a session that may
  > have written the tracker where nothing of this pack can see it. »*

  Elle est écrite pour le drain, qui est séquentiel. **Les deux moments du run
  AFK ne sont pas ceux-là**, et c'est le travail du ticket de le dire plutôt que
  de recopier : le run choisit un ticket dans la frontière (pas « le haut d'un
  ticket »), il repart de `loop__reap` quand une itération revient, et il peut en
  avoir plusieurs en vol.

- **Le piège de la concurrence, à traiter avant d'écrire.** La lecture de [75]
  vit dans **une variable du shell appelant**, servie aux substitutions que ce
  shell fork. Une itération est `loop__iterate … &` : si le pilote prime avant de
  forker, chaque itération hérite d'une copie, et ce qu'un **frère** écrit au
  tracker n'invalide **rien** dans les autres copies — le registre
  `tracker.writes` est relu par le shell qui interroge, mais la variable qu'il
  porte est la sienne. Le défaut inter-process que [75] a fermé est celui-là ; il
  faut vérifier qu'on ne le rouvre pas d'un cran en donnant la lecture au pilote.
  Lire la mémoire du ticket [75] avant d'écrire une ligne.

- **Ce que ça ne doit pas devenir.** Un refus de `cache_prime` n'est jamais une
  raison de s'arrêter, et les deux refus qu'un appelant ne peut pas distinguer —
  un backend qui ne tient pas de lecture, un tracker qui ne répond pas — sont la
  même instruction : continuer. La lecture qui suit redemande et dit ce qu'elle
  n'a pas pu faire, dans la phrase qui lui appartient ([64] : un refus dit deux
  fois est un refus qu'un humain apprend à sauter).

- **Piège de harnais.** Le compteur de requêtes du faux forge se grepe sur
  `'^GET .*/issues?state='` : le dépôt arrive percent-encodé et l'URL porte
  `/api`, donc un motif qui nomme le dépôt ne matche rien. `run_loop` sur douze
  issues avec `ITER_CAP 3` rend `rc=4` — c'est le plafond d'itérations, pas un
  refus — et le drain quitté par `q` rend `rc=5`.

- **Contrainte écrite par [83], livré le 13/09/2026, et c'est la réponse que ce
  ticket attendait.** « Comment un fork rend-il quelque chose au pilote ? » a une
  réponse et c'est **non** : le pilote distribue (une variable non exportée est
  héritée par chaque fork) et rien ne remonte. [83] en a tiré la forme à
  reprendre ici — le pilote prend ce qu'il peut prendre avant le premier fork, et
  **chaque fork répond de sa propre fenêtre**, dans sa propre mémoire. Ce que ça
  vaut pour la lecture partagée de [75], qui vit elle aussi dans une variable du
  pilote : une lecture prise par `loop.sh` est héritée par chaque itération et
  **aucune itération ne peut la rafraîchir pour les autres** — donc la dernière AC
  de ce ticket (« ce que la lecture devient dans un fork concurrent ») n'est pas
  un cas limite à documenter en passant, c'est la contrainte qui décide *où*
  `cache_prime` peut être appelé. Voir `lib/retro.sh`, bloc « what this run makes
  after the seal was taken », et la ligne « pour s'en servir de témoin » du
  tableau.

## Place dans la file

Ouvert par la passe du 13/09/2026. **Ordre validé par Philippe le 13/09/2026,
après la passe transversale du même jour :**
**[83] → [84] → [85] → [73] → [19]**. Derrière [83] parce que les deux posent la
même question — comment un fork et le pilote se passent quelque chose que la
session ne doit pas atteindre — et que [83] la pose sur un objet plus petit.

Arêtes réelles : [75], [13], [76], [64].

**Contrainte écrite dans [73] le 13/09/2026** : la note que [75] y avait laissée
(« le chemin AFK n'a aucun `tracker_cache_prime` ») est maintenant ce ticket-ci.
[73] restaure le tracker d'un backend distant ; s'il est livré après [84], il
hérite d'une lecture partagée sur le chemin AFK et doit dire ce qu'une
restauration en fait — une restauration **est** une écriture du tracker, donc une
invalidation.

## Livré le 13/09/2026

Branche `ticket-84-la-lecture-du-run-afk`.

### Les deux moments, nommés

Ce ne sont pas ceux du drain, et la raison n'est pas une nuance : le drain est
séquentiel, le run a des itérations en vol.

1. **Le pilote, en tête de chaque passe** (`loop_main`, première instruction du
   `while`). « Le haut d'un ticket » n'est pas un moment que ce fichier a : la
   frontière de ce pack est un scan **sans mémoire** ([04]), redérivée à chaque
   tour, et tout ce que la passe lit du tracker part d'une substitution forkée de
   ce shell — les ids en vol, le balayage de liveness sur chaque claim, la
   frontière, et la write-surface contre laquelle chaque candidat est comparé.
   **Devant `loop__reap`**, et c'est la place et non l'ordre d'écriture :
   `loop__finish` tourne dans *ce* shell (il écrit les compteurs du run, donc il
   ne peut pas être un sous-shell) et lit le `Status:` d'un ticket dont la session
   vient de revenir. Une lecture prise après le reap laisserait le premier lecteur
   de la passe servi par la passe précédente.

2. **L'itération, au retour de sa session** (`loop__iterate`, après la garde
   d'orphelin, avant `failures_protect_tracker`). C'est la contrainte de [83]
   appliquée : **un fork ne rend rien au pilote**, donc le pilote ne peut pas
   prendre cette lecture-là pour une itération — la session qui a pu écrire le
   tracker par le réseau est celle de *ce* shell, elle est revenue longtemps après
   le fork, et rien de ce qui est pris ici n'atteint le pilote ni un frère. Chaque
   itération répond de sa propre fenêtre. Ce que ça achète est l'essentiel de ce
   que paie une nuit : la restauration, le `Failures:` sur lequel la tentative est
   comptée, la quarantaine de ce que la session a écrit dans le tracker, et la
   marche du scope-guard sur chaque id pour la write-surface qu'il juge.

### Mesuré des deux côtés du même scénario

Faux forge, douze tickets, `ITER_CAP 3`, listings comptés comme
`test/tracker-remote.bats` les compte. Le second bras est le même scénario avec
`FORGE_CACHE_TTL=0`, donc le chiffre ne peut pas périmer en silence.

| | avec la lecture | sans | ce qu'elle achète |
|---|---|---|---|
| avant ce ticket (sonde q4 de la passe) | 93 | 96 | **3 %** |
| après | **23** | 103 | **78 %** |

Le bras « sans » passe de 96 à 103 parce que la session du test écrit désormais
son propre pid : les deux bras font du vrai travail, ce que la sonde ne
garantissait pas (une seconde session qui écrit les mêmes octets ne change rien,
et une itération qui n'a rien changé n'a pas broyé son ticket, [35]).

Sondé aussi à `MAX_PARALLEL=3`, `ITER_CAP 6`, même forge : 6 itérations, 6
`resolved`, **65** listings (≈ 11 par itération contre 31), aucun claim refusé,
aucune quarantine parasite. Et sur le backend local, où les deux opérations
refusent : nuit inchangée, **aucune** phrase nouvelle sur la console.

### La clause de [75] n'est plus un commentaire

`test/tracker-remote.bats` — « *an entry point that opens this reading and never
takes one is refused* » — **dérive** les points d'entrée du pack (`"$PACK_DIR"/*.sh`,
le même glob que `test/layering.bats`, pour la même raison : un troisième point
d'entrée est un fichier) et rougit sur celui qui ouvre sans jamais primer. Les
commentaires sont retirés d'abord : un paragraphe qui nomme l'appel est de la
documentation, pas un appel. Le recensement vide est un échec, pas un vert : un
run où *personne* n'ouvre ne recense rien.

Le paragraphe de `lib/tracker.sh` a été réécrit en conséquence : chaque point
d'entrée a **ses** deux moments, et il doit les nommer.

### Ce que la lecture devient dans un fork concurrent

Écrit dans les deux commentaires et dans `docs/frontiere-de-confiance.md`, avec
son témoin (`a reading the pilot hands to an iteration is one no sibling can
refresh`) :

- La lecture vit dans une variable du shell qui l'a prise. `MAX_PARALLEL > 1`
  donne donc à chaque itération une **copie**, et **rien ne remonte** : aucune
  itération ne peut rafraîchir celle d'un frère ni celle du pilote.
- Ce qui traverse est le **registre** — `tracker.writes`, un fichier, une ligne
  par écriture de ce run — et il ne traverse que dans un sens : il peut **arrêter**
  de servir une lecture, jamais en renouveler une. L'écriture d'un frère est donc
  lue comme « relis le tracker », qui est le sens sûr.
- Ce que ni le registre ni ces deux lignes ne couvrent — une écriture qu'aucun
  process de ce run n'a faite : un humain sur le forge, une session par le réseau
  — est borné par `FORGE_CACHE_TTL` (60 s), et fermé pour la session par le prime
  n° 2.

### Frontière de confiance

La ligne de [75] a été prolongée plutôt que doublée. Ce que [84] y change : la
forgerie du registre (le tronquer à la longueur exacte qu'une lecture vivante
porte) n'achetait presque rien sur le chemin AFK, qui ne prenait aucune lecture ;
il en prend deux maintenant. Trois clauses la bornent : un `prime` **relit
toujours**, donc tronquer ne peut pas périmer la lecture prise *après* la session
— celle dont le scope-guard tire la write-surface ; le registre ne se forge que
**plus court** (l'allonger fait relire) et ce que le raccourcissement achète est
de cacher à une itération l'écriture d'un **frère** pendant ce qu'il reste du TTL,
ce qui n'existe pas au `MAX_PARALLEL=1` livré ; et ce raccourcissement est
**nommé**, parce que sur le chemin AFK le registre est dans le sceau de [81] en
mode `grows` et que `gate_witness_note` parle au retour de la session, avant la
lecture que l'itération prend.

### Pièges payés

- **Le même scénario deux fois sur un seul arbre n'est pas le même scénario.**
  Une session qui écrit un contenu fixe ne change rien au deuxième run : le gate
  ne voit aucun fichier bougé et l'itération ne résout pas. La session du test
  écrit son propre pid, et les deux bras asserent `-> resolved` **avant** qu'un
  compte soit pris.
- `run_loop` sur douze issues avec `ITER_CAP 3` rend `rc=4` — plafond
  d'itérations, pas un refus.
- Le témoin de fork concurrent attend son frère avec une **borne** (400 × 0,05 s) :
  sans elle, un frère mort est une suite qui pend au lieu d'une assertion rouge.

### Entrées de mutation

Quatre, `bash test/mutate.sh -f "84 "` vert :

| entrée | ce qu'elle retire | test qui rougit |
|---|---|---|
| `84 the pilot pays the register and takes no reading of its own` | le prime n° 1 | la mesure |
| `84 the iteration reads the tracker without a reading of its own` | le prime n° 2 | la mesure |
| `84 the iteration takes its reading before its session, not after` | déplace le prime n° 2 **au-dessus** de la session | la sonde de quarantaine |
| `84 an entry point opens this reading and takes none` | les deux primes | le recensement |

La troisième est la seule qui tient la **place** : le prime relit toujours, donc
le retirer ne périme rien — le déplacer au-dessus de la session, si.

### Ce que le ticket suivant hérite

- **[73]** — une restauration du tracker d'un backend distant **est** une écriture
  du tracker, donc une invalidation : si elle passe par `forge__update` /
  `forge__create` elle appende au registre toute seule ; si elle écrit autrement,
  elle doit appeler ce qui appende, sans quoi la lecture que le chemin AFK tient
  maintenant survivra à ce que la restauration a remis.
- **[19]** — l'installeur balaie ce que `gate_leftovers` nomme ; ce ticket
  n'ajoute **aucun** nom dans `$TMPDIR` (les deux primes n'écrivent rien, le
  registre est celui de [75]).
