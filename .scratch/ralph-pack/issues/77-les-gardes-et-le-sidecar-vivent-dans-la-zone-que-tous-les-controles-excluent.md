# 77 — Les gardes et le sidecar vivent dans la zone que tous les contrôles excluent

**What to build:** Que ce qu'une session écrit dans les objets d'exécution du pack — le sidecar d'un backend distant, les gardes d'exclusion des deux backends — soit remis ou nommé, jamais avalé ; et qu'un garde étranger n'arrête pas la nuit en accusant le tracker.

**Blocked by:** None

**Write-surface:** `.claude/lib/forge.sh`, `.claude/lib/tracker-local.sh`, `.claude/lib/forensic.sh`, `.claude/lib/gate.sh`, `.claude/lib/router.sh`, `test/tracker-remote.bats`, `test/forensic.bats`, `test/gate.bats`, `test/mutate.sh` — plus `.claude/lib/tracker.sh`, `.claude/lib/tracker-github.sh`, `.claude/lib/tracker-gitlab.sh`, `.claude/loop.sh`, `test/human-loop.bats` et `docs/frontiere-de-confiance.md`, **écart déclaré** (voir les commentaires de livraison).

**Status:** resolved

- [x] Ce qu'une session écrit dans `.forge-claims` est **remis** ou **nommé**, jamais avalé — et la ligne du tableau de confiance dit laquelle des deux.
- [x] Un garde d'exclusion que ce run n'a pas pris n'arrête pas la nuit en accusant le tracker : la phrase imprimée dit ce qui a refusé, et elle est vraie.
- [x] `gate__stale_guards` voit aussi le garde de claim du backend local (`issues/<id>.md.guard`, un niveau plus bas) et dit quelque chose d'un garde dont le propriétaire est vivant mais étranger à ce run.
- [x] L'URL que `router_dossier` montre comme reçu d'un backend distant porte la réserve **exacte** : elle est lue dans un fichier de cet arbre, pas sur le réseau.
- [x] Le backend local garde exactement ses garanties actuelles, et le drain les siennes.

## Comments

- **Ouvert par la passe transversale du 08/09/2026** (`../passe-transversale-08-09.md`,
  §2 ; sondes `../sondes/passe-08-09/q2-*.bats`). Ce n'est **pas** un défaut de
  [18] : la moitié « garde de claim » est celle du backend local et elle est là
  depuis [47]/[49]. [18] l'a élargie d'un ticket à tout le tracker.

- **Ce qui vit là, et ce que ça décide.** Sur un backend distant, trois faits
  locaux sont dans `.scratch/<feature>/.forge-claims`, append-only, dernière
  ligne gagnante :

      claim    `owner=<qui> at=<iso>` — l'autorité de `tracker_field ID Claimed`,
               donc de toute la liveness de `lib/claim.sh`
      request  le numéro de la requête ouverte
      receipt  **l'URL que `router_dossier` montre comme le reçu d'audit**

  Et deux gardes : `.scratch/<feature>/.forge.guard` (le claim **et** la création
  de ticket, pour tout le tracker) et `issues/<id>.md.guard` (le claim d'un
  ticket, backend local). Les trois zones sont hors de tout : `gate_is_bookkeeping`
  exclut `.scratch/<FEATURE>/` du scope-guard, `failures__is_ticket_path` exclut
  les transitoires d'`issues/` de la restauration de [21] ([49]), et le témoin
  forensique de [70] ne connaît que les refs, les reçus-fichiers et le playthrough.

  [18] a écrit que le sidecar « a exactement l'exposition du verrou de run ».
  Vrai de l'exposition, faux du prix : le verrou de run décide qu'un second run
  refuse ; ces lignes-là décident *qui tient un ticket* et *quelle preuve un
  humain va lire*.

- **Mesuré, et les témoins appairés sont dans le README des sondes :**

  | Sonde | Ce qu'elle demande | Verdict |
  |---|---|---|
  | Q2a | une itération **verte** dont la session appende une ligne `receipt` pour le ticket du puits | run **rc=0**, **0** mot ; le dossier du drain montre `receipt https://forge.invalid/pull/9999 — verdicts, findings, and the zones nothing judged` |
  | Q2b | témoin : sans la ligne | « receipt none was kept for this ticket » |
  | Q2c | un claim de run **mort**, tel quel | reclaim : `2-alpha retry`, la forge repasse à `ready-for-agent` |
  | Q2d | le même, une ligne appendue derrière (pid vivant) | reclaim **silencieux**, ticket toujours `claimed`, **frontière vide** |
  | Q2e | `.scratch/<feature>/.forge.guard/pid` posé par une session, pid vivant | run **rc=4**, sterile, deux itérations qui n'ont rien réclamé |
  | Q2f | le même sur le backend **local**, `issues/01-alpha.md.guard/pid` | identique |

- **C'est [70] rouvert par une autre porte, et il ne manque pas un garde.** [70] a
  tranché la posture pour les zones que rien ne garde : on ne prévient pas, on
  **dit**. [18] a relu la réserve du dossier pour un reçu distant, correctement —
  la phrase imprimée parle du réseau. Ce que ni l'un ni l'autre n'a vu : **l'URL
  n'est pas lue sur le réseau, elle est lue dans un fichier de cet arbre.** La
  réserve envoie donc le lecteur regarder du côté où il n'y a rien à voir. Ce qui
  manque est une phrase exacte et une ligne au tableau — plus, si on veut, un
  témoin, et le mécanisme existe déjà : `forensic__manifest` prend un digest de
  trois zones **avant la première session** et `forensic_drift` nomme ce qui a
  bougé. Une quatrième zone y coûte trois lignes ; c'est la sortie que [70] a
  prise pour le reçu-fichier.

- **Le claim d'un backend distant est un fichier, et [12] est écrit contre un
  champ.** `claim.sh` dit de sa liste d'exemption : « an id the run is holding is
  a fact only the run knows, **it is written nowhere a session can reach** ». Vrai
  de la liste, faux du **record** que la même fonction lit juste au-dessus : champ
  de ticket restauré par [21] sur `local`, ligne appendable sur un backend
  distant. Une ligne, et le ticket sort de la frontière tant que le pid vit — que
  la session renouvelle à chaque itération. Borné par `CLAIM_TTL` (5400 s par
  défaut), **non borné** avec `CLAIM_TTL=0`, la lecture « pas de backstop » que
  [12] autorise explicitement.

- **Le garde arrête la nuit, et la phrase accuse le tracker.** `forge__guard_take`
  réessaie six secondes puis refuse ; `tracker_local_claim` refuse tout de suite ;
  dans les deux cas `loop.sh` imprime « could not claim X — its status is still
  ready-for-agent and **the tracker refused the write: nobody is named as holding
  it** ». Les deux moitiés sont fausses : le tracker n'a rien refusé, et ce qui
  tient le ticket est un répertoire. Après `STERILE_K` itérations, la nuit
  s'arrête. `gate__stale_guards` ne rattrape rien : il ne balaye que
  `<feature_dir>/*.guard` et `<feature_dir>/.*.guard` — donc pas
  `issues/<id>.md.guard` — et seulement des propriétaires **morts**, alors que le
  geste qui mord est un propriétaire vivant. Le tableau de confiance dit
  d'ailleurs de cette ligne qu'elle « compte, elle ne juge pas ».

- **Les sorties à peser, écrites pour qu'elles ne soient pas redécouvertes.**
  1. *Déplacer le sidecar hors de l'arbre.* Il doit survivre au run (c'est ce qui
     rend la liveness inter-run possible), donc pas `$TMPDIR` sous un `mktemp` que
     le pilote n'exporte pas. Le précédent du dépôt est `<gitdir>/` ([53] y range
     le log de repli du successeur), et il faut alors dire ce qui garde **cette**
     zone — la ligne « Ce qu'une session écrit dans `.git/` » du tableau existe
     déjà et il faudra la lire.
  2. *Le témoin plutôt que la remise*, ci-dessus : c'est la posture de [70] et
     c'est trois lignes. Ce que ça n'achète pas : la nuit s'arrête quand même
     dans le cas du garde, elle le dit seulement.
  3. *Refuser un garde étranger.* Tentant et dangereux : « étranger » n'est pas
     mesurable après coup — `state_guard_take` documente déjà qu'il n'y a pas de
     compare-and-swap en bash — et un run qui casserait un garde vivant volerait
     le ticket d'un run légitime que le verrou de run n'a pas vu (deux features,
     deux runs, un même dépôt). Ce qui *est* mesurable : ce run connaît ses
     propres pids, et un garde présent **avant** que le run démarre n'est le sien
     dans aucun cas.

- **Question transversale à poser en le livrant** : les objets d'exécution du pack
  (gardes, sidecars, registres) ont maintenant trois emplacements — `issues/`,
  le répertoire de feature, `$TMPDIR` — et trois régimes de garde différents.
  C'est la racine de la passe du 27/08 (« le pack range ses objets d'exécution
  dans des répertoires dont les gardes visent une autre forme »), qui n'avait
  été refermée que pour `issues/` ([49]).

## Note écrite par [74] (livré le 09/09/2026)

Un voisin dans le même fichier, ouvert le même jour : **[78]** — `forge__slug_taken`
lit le listing dans un heredoc avec `|| printf ''`, donc un refus s'y lit « ce slug
n'est pas pris » et `forge_open_unique` ouvre un doublon (certain, à chaque run,
dès que le plafond de pages de [76] refuse). Ce n'est pas de la famille de ce
ticket-ci — c'est [59] et non la zone comptable — mais il touche `forge.sh` et
`test/tracker-remote.bats`, donc les livrer voisins économise une relecture.
**Philippe l'a placé juste derrière ce ticket le 09/09/2026** : la file est
**[77] → [78] → [75] → [73] → [19]**. Sans arête entre les deux — ce qui est
livré ici ne conditionne rien de [78], et inversement.

## Place dans la file

Ordre validé par Philippe le 08/09/2026, après la passe transversale du même
jour : **[76] → [74] → [77] → [75] → [73] → [19]**. Critère du dépôt —
minimiser la reprise, jamais l'urgence.

1. **[76]** — le seul faux vert livré des six, la plus petite surface, et sa
   première AC est **le faux du harnais** : tout ticket distant qui suit mesure
   contre lui. Le précédent est [59], premier pour la même raison.
2. **[74]** — même famille que [76] (« une lecture qui rend moins qu'on lui
   demande, sans le dire »), deux lignes de `loop.sh`, et il tranche comment la
   boucle lit un refus d'adaptateur — ce que [73] ajoutera.
3. **[77]** — tranche **où vit l'état local** d'un backend distant. [75] loge un
   cache : livré derrière, il hérite du logement ; livré devant, il le choisit
   deux fois.
4. **[75]** — le cache, qui donne son budget à la remise de [73] (cinq champs
   plus le corps par ticket, par fenêtre).
5. **[73]** — la remise, avec le mécanisme que `router.sh` porte déjà et le
   budget que [75] vient de payer.
6. **[19]** — l'installeur lit ce que les cinq autres décident : le `.gitignore`
   de la zone comptable ([77]), les clés de config de [76] et [75].

`Blocked by:` écrit en conséquence : `[76] None`, `[74] None`, `[77] None`,
`[75] 77`, `[73] 74, 75, 77`, et `[19]` gagne `73, 74, 75, 76, 77`.

## Livraison (09/09/2026)

**Les deux moitiés n'ont pas la même réponse, et c'est la trouvaille du ticket.**
Le sidecar est lu **pour une réponse** — `tracker_field ID Claimed`, le numéro de
la requête à réécrire, l'URL du reçu — alors que les trois zones de [70] sont
seulement *montrées* à un humain. Un témoin seul y aurait donc nommé la
contrefaçon **et lui aurait obéi**. Le sidecar est donc **remis** (le run lit sa
propre copie) et nommé par-dessus ; les gardes, eux, restent la posture de [70] —
comptés et nommés, jamais cassés.

### Ce qui a été écrit

1. **Trois opérations de plus à l'interface d'adaptateur** (`tracker.sh`) :
   `sidecar_path` (où sont ces records, pour la phrase du dossier),
   `sidecar_witness DIR` (la copie du run), `sidecar_drift DIR`
   (`subject<TAB>outcome<TAB>message`, la forme que `capability_drift`,
   `gate_path_drift` et `forensic_drift` utilisent déjà). Les trois sont des
   **lectures** au sens du registre de [13] : aucune n'écrit un ticket, donc
   elles sont dans le bras des lectures de `tracker__dispatch`. Le backend local
   **refuse les trois**, et c'est une seule réponse : son claim est un champ du
   ticket que `failures_protect_tracker` remet ([21]), son reçu est un chemin
   composé d'un id. Refuser explicitement plutôt que ne pas implémenter, sinon le
   dispatcher imprime « does not implement » sur la console de chaque drain.

2. **`forge.sh`** : `forge_sidecar_witness` copie le fichier en deux exemplaires
   dans le répertoire témoin du run (`sidecar.base`, la photo de base, et
   `sidecar`, la photo plus tout ce que le run écrit ensuite) ; `forge__reading`
   fait passer toutes les lectures par la copie quand il y en a une ;
   `forge__record_local` écrit **la copie d'abord, le fichier ensuite**.

   *L'ordre est la garantie et pas un goût*, et l'inverse est un faux vert
   silencieux : écrit fichier-puis-copie, la fenêtre entre les deux est une
   fenêtre où un record légitime est sur le disque et pas encore dans la copie —
   une itération sœur qui compare à cet instant accuse le run de ce qu'il fait
   légalement. C'est la règle du registre de [70] (« entered before the write and
   never after ») un fichier plus loin. **Non mutable** : le défaut est une
   course de quelques microsecondes, donc aucune entrée de `test/mutate.sh` ne
   peut le faire rougir de façon déterministe. Écrit ici et dans le commentaire
   de la fonction faute de mieux.

   La comparaison est une **appartenance à l'ensemble** des valeurs que le run
   tient pour une clé, pas une égalité avec la dernière : deux itérations
   écrivent ce fichier, donc « la dernière valeur écrite » est une cible mobile
   et un record qu'une sœur vient de remplacer n'est pas une contrefaçon. Et la
   direction « disparu » n'est rendue que pour une clé de la **photo de base** —
   une clé que le run vient d'ajouter et que le fichier ne porte pas encore est
   exactement la fenêtre ci-dessus.

3. **`forensic.sh`** prend la quatrième zone au même instant que les trois
   siennes et fait voyager les lignes de l'adaptateur sur les deux mêmes canaux
   (`run.log` par le retour au pilote, le reçu par `receipt_gap`). La zone
   n'entre **pas** dans `forensic__manifest` et l'en-tête dit pourquoi : le
   critère de ce module est « ce que le pack écrit durablement, hors de tout arbre
   qu'il juge, pour qu'un humain le lise » — un fichier lu pour une réponse n'en
   est pas, et l'y mettre aurait été plus large que le critère qui le justifie
   ([31], [45], à l'envers).

   `forensic_uncovered` dit maintenant **deux** phrases sur un backend distant :
   la première (« nothing witnesses the receipts ») se lisait « rien de local
   n'est tenu », ce qui est précisément ce qui a rendu ce fichier invisible.

4. **`gate.sh`** : `gate_guards` énumère les gardes de **deux** répertoires — la
   feature, et celui que `tracker_tickets_dir` nomme, un niveau plus bas, où vit
   `issues/<id>.md.guard`. `gate__stale_guards` dit deux phrases : propriétaire
   mort (l'ancienne) et propriétaire **vivant** (neuve). Le chemin complet et
   plus le `basename` : avec deux répertoires, `01-alpha.md.guard` seul ne dit
   plus où aller regarder.

   *Ce que ça retire du dépôt* : le commentaire disait qu'un propriétaire vivant
   ici est « a sibling run of another feature, this very process » et que le
   nommer serait une fausse alerte. C'est faux là où ces gardes vivent — les deux
   répertoires sont ceux de **cette** feature, et le point d'entrée tient le
   verrou de run dessus. Les deux tests qui portaient cette lecture
   (`test/gate.bats`, `test/human-loop.bats`) asseraient
   `refute_output_contains ".busy.guard"` ; ils asserent maintenant que le garde
   vivant est sur **sa** ligne et pas sur celle des morts, et l'inverse.

5. **`gate_guard_witness` / `gate_guard_note`**, et c'est la seule chose qui rend
   « pas à ce run » mesurable : `state.sh` documente qu'il n'y a pas de
   compare-and-swap en bash, et « étranger » ne se décide pas après coup à partir
   d'un pid — mais un garde debout **avant** qu'un run ait démarré quoi que ce
   soit n'est tenu par aucune de ses itérations. Le recensement est pris après les
   verrous, avant la première itération, dans le même répertoire témoin que les
   trois autres.

6. **`loop__claim_refused`** dit ce qu'il a observé. Trois cas au lieu de deux :
   le statut a bougé (inchangé), un garde vivant est tenu (nommé, avec son pid,
   son heure, et s'il précédait ce run), et **aucun garde tenu** — où la phrase
   dit ce que ce run *ne peut pas* dire (l'exclusion du tracker, un garde relâché
   depuis, ou l'écriture elle-même) au lieu d'accuser le tracker. La lecture est
   faite **après** le refus, donc un garde relâché entre-temps est un garde que
   ceci ne peut pas nommer : c'est pour ça que la troisième phrase existe.

   **La nuit s'arrête toujours** — `STERILE_K` puis `rc=4` — et c'est le prix de
   la sortie 2 du ticket, écrit dans le ticket avant d'être livré. Ce qui change
   est qu'un humain qui ouvre `run.log` au matin est envoyé sur le bon objet.

7. **`router_dossier`** imprime la réserve exacte sous l'URL d'un reçu distant, et
   **jamais sous une ligne qui dit qu'il n'y en a pas** — la règle que la réserve
   de [70] suit déjà. Le chemin vient de l'adaptateur, comme l'emplacement du
   reçu.

### Écart de write-surface, déclaré

`.claude/lib/tracker.sh` (les trois opérations et leur documentation),
`.claude/lib/tracker-github.sh` et `.claude/lib/tracker-gitlab.sh` (le câblage,
trois lignes chacun), `.claude/loop.sh` (le recensement au démarrage et la phrase
du claim refusé), `test/human-loop.bats` (les deux assertions que le point 4
retire), `docs/frontiere-de-confiance.md` (lignes « Un ticket réclamé par un run
mort revient », « Le reste de `.scratch/<feature>/` » et « Un reçu d'audit dit ce
qui s'est vraiment passé »).

Aucune de ces cinq n'était évitable : la write-surface avait été écrite en
supposant que la réparation tiendrait dans `forensic.sh`, et elle n'y tient pas —
`forensic.sh` ne doit pas savoir ce qu'est un backend, donc la zone se demande à
l'adaptateur, donc l'interface bouge et les deux forges avec elle.

### Ce qui n'est pas tenu, écrit plutôt que découvert

- **Une ligne posée quand aucun run ne tourne** est dans la photo de base du run
  suivant, exactement comme pour le témoin de [70]. Rien ici ne peut la
  distinguer d'un record qu'un run précédent a écrit.
- **Le drain ne prend pas de copie.** `human-loop.sh` ne fait pas de répertoire
  témoin, donc `router_dossier` lit le fichier — c'est précisément pourquoi il
  nomme le fichier. Un drain qui prendrait une copie ne gagnerait rien : il n'a
  pas de « avant la première session » à opposer à quoi que ce soit.
- **Une troncature du sidecar** est nommée pour les clés de la photo de base et
  pas pour celles que le run a ajoutées depuis (§2). Une session qui vide le
  fichier fait donc dire une ligne au run, pas trois.
- **Le fichier reste la seule copie durable**, et il le faut : la liveness d'un
  claim est ce qu'un run dit au suivant, donc un sidecar rangé dans `$TMPDIR`
  donnerait à chaque run un tracker sans mémoire. Déplacer le fichier dans
  `<gitdir>/` (sortie 1 du ticket) a été refusé pour la raison que [53] écrit
  déjà de son log de repli : « le repli est dans `.git/`, que la même session
  atteint, donc il n'est pas un abri, il est un second essai ».
- **Casser un garde vivant** (sortie 3) reste refusé, pour les deux raisons du
  ticket.

### Contraintes écrites ailleurs

- **[19]** (installeur) hérite d'un nom de plus à provisionner ou à ignorer :
  `.scratch/<feature>/.forge-claims` est un fichier local qui ne doit pas entrer
  dans l'historique du projet cible, au même titre que `run.log`. Rien ici ne
  l'ajoute au `.gitignore` — c'est la zone comptable, que `gate_is_bookkeeping`
  exclut déjà du scope-guard, mais un `git add -A` d'un projet qui ne l'ignore pas
  le commiterait. Noté dans [19].
- **[75]** (le cache d'un backend distant) a maintenant son logement : le
  répertoire témoin du run, sous un nom que le pilote n'exporte pas, avec la
  discipline de `forge_sidecar_witness` — copie prise avant la première session,
  lue par le module, jamais un fichier que la session atteint. C'est la raison
  pour laquelle [77] passait devant lui dans la file.
- **[73]** (la remise du tracker d'un backend distant) hérite de deux choses :
  `tracker_sidecar_*` est le précédent d'une opération d'interface qui prend le
  répertoire témoin du run en argument, et `forge_sidecar_drift` est le précédent
  d'un adaptateur qui rend `subject<TAB>outcome<TAB>message` plutôt que
  d'imprimer.

### Ce que le gate de mutation a trouvé, et qui est la trouvaille du ticket

La première passe complète de `test/mutate.sh` a rendu **un `VACUOUS`** :
« 77 a record being written is a record somebody deleted ». L'entrée retirait la
garde qui ne signale une clé disparue que si elle était dans la **photo de base**,
et le test que je lui avais accroché (« a run that wrote its own records accuses
nobody of them ») restait vert.

Il restait vert pour une raison qui vaut d'être écrite : **la garantie est une
propriété de la fenêtre entre les deux écritures, et un test séquentiel ne la
traverse jamais**. Dans un run ordinaire, chaque record que le pack écrit est dans
la copie *et* dans le fichier au moment où la comparaison regarde — la garde ne
change donc rien, et le test ne pouvait pas la voir. C'est la forme exacte que
CLAUDE.md décrit : un test vert sur une propriété qui avait disparu.

La réparation n'est pas de raffiner le test de bout en bout mais de **mettre en
scène l'instant** au niveau du module : prendre le témoin, appender un record à la
copie **seule** — ce qui est littéralement l'état intermédiaire de
`forge__record_local` — et demander à `tracker_sidecar_drift` de se taire, avec
son témoin appairé (une clé de la photo de base que le fichier ne porte plus **est**
nommée). Une fenêtre de quelques microsecondes ne se course pas dans un test ; ce
qui se teste est **de quel côté de la fenêtre la comparaison se trompe**.

## Question transversale posée en le livrant

*Les objets d'exécution du pack ont maintenant trois emplacements — `issues/`, le
répertoire de feature, `$TMPDIR` — et trois régimes de garde différents.* La
réponse après ce ticket : `gate_guards` est le premier endroit du pack qui
énumère les gardes des **deux** répertoires de l'arbre au lieu d'un, et il le fait
en demandant le second à l'adaptateur — donc un quatrième emplacement (un backend
qui rangerait ses tickets ailleurs) est suivi sans édition. Ce qui reste ouvert et
qui n'est pas de ce ticket : rien n'énumère les gardes que le pack pose **hors**
de ces deux répertoires, et rien ne dit qu'il n'y en a pas — la liste est
`gate_guards`, et son critère est écrit dans son commentaire, pas vérifié par un
test qui lirait les `state_guard_take` du pack comme `test/gate.bats` lit ses
`mktemp`. C'est la forme exacte de ce que [62] a réparé pour `$TMPDIR`, un
répertoire plus loin.

## Réponse à la question transversale, par la passe du 10/09/2026

Ce ticket finissait sur : *« rien n'énumère les gardes que le pack pose **hors**
de ces deux répertoires, et rien ne dit qu'il n'y en a pas. »* Mesuré :
`gate_guards` couvre **trois** des six `state_guard_take` du pack.

| Garde | Où il vit | Dans `gate_guards` ? |
|---|---|---|
| `forge__guard` | `<feature_dir>/.forge.guard` | oui |
| `tracker_local__open_guard` | `<feature_dir>/.open.guard` | oui |
| claim guard | `<tickets_dir>/<id>.md.guard` | oui |
| `concurrency_frontier_guard` | `<gitdir commun>/ralph.frontier.lock` | **non** |
| `concurrency__integration_guard` | `<gitdir commun>/ralph.integrate.lock` | **non** |
| garde de l'index de leçons | `$TMPDIR/ralph-retro.*/index.guard` | **non** |

Le garde d'intégration est le plus cher : pris par un propriétaire vivant,
`concurrency__wait_for_guard` attend soixante secondes puis rend la main, et une
itération **verte** finit `not-integrated` — travail dans un worktree que le run
détruit, aucun commit, aucune ref, aucun changement au ticket, la nuit s'arrête.
La conséquence est bien traitée ([74] fait émettre un reçu et arrêter le run) ;
ce qui manque est que rien ne **nomme** l'objet, parce que rien ne l'énumère.
`.git/` est atteignable par une session ([22], et le tableau de confiance).

**Et le sidecar que ce ticket remet est lui-même dans une zone que rien ne
compte** : `sidecar` et `sidecar.base` sont dans le répertoire témoin du run, où
quatre fichiers sur neuf sont vérifiés. Une session qui les efface ou les réécrit
éteint la remise, sans un mot.

Les deux moitiés sont reprises par **[81]**.
