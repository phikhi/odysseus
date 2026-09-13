# 84 — Le point d'entrée AFK ouvre la lecture du tracker et n'en prend aucune

**What to build:** Que le point d'entrée qui tourne toute la nuit prenne la lecture partagée de [75] aux moments où elle est juste, au lieu de payer le registre qui l'invalide sans jamais l'avoir prise.

**Blocked by:** None

**Write-surface:** `.claude/loop.sh`, `.claude/lib/tracker.sh`, `.claude/lib/forge.sh`, `test/tracker-remote.bats`, `test/loop-happy-path.bats`, `test/mutate.sh`

**Status:** ready-for-agent

- [ ] `loop.sh` prend une lecture du tracker aux moments du run AFK où une lecture prise plus tôt serait fausse, et le ticket **nomme ces moments** — ce ne sont pas ceux du drain, parce que le run a des forks concurrents ([13]) que le drain n'a pas.
- [ ] La clause que [75] a écrite dans `tracker.sh` — « *neither call is one an entry point may skip on a hunch* » — cesse d'être tenue par un commentaire : quelque chose refuse, ou dit, qu'un point d'entrée ouvre `cache_open` sans jamais appeler `cache_prime`.
- [ ] La mesure est faite des deux côtés du même scénario, comme [75] l'a faite pour le drain : le nombre de listings d'un run AFK avec et sans la lecture, sur le même tracker, jamais contre un nombre écrit une fois.
- [ ] Ce que la lecture partagée devient dans un fork concurrent est écrit : `MAX_PARALLEL > 1` fait travailler plusieurs itérations sur le même tracker, et une lecture héritée par un fork n'est pas invalidée par ce qu'un **frère** écrit.

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

## Place dans la file

Ouvert par la passe du 13/09/2026. **Ordre proposé, à valider par Philippe :**
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
