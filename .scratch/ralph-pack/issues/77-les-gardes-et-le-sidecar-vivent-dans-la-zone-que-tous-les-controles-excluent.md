# 77 — Les gardes et le sidecar vivent dans la zone que tous les contrôles excluent

**What to build:** Que ce qu'une session écrit dans les objets d'exécution du pack — le sidecar d'un backend distant, les gardes d'exclusion des deux backends — soit remis ou nommé, jamais avalé ; et qu'un garde étranger n'arrête pas la nuit en accusant le tracker.

**Blocked by:** None

**Write-surface:** `.claude/lib/forge.sh`, `.claude/lib/tracker-local.sh`, `.claude/lib/forensic.sh`, `.claude/lib/gate.sh`, `.claude/lib/router.sh`, `test/tracker-remote.bats`, `test/forensic.bats`, `test/gate.bats`, `test/mutate.sh`

**Status:** ready-for-agent

- [ ] Ce qu'une session écrit dans `.forge-claims` est **remis** ou **nommé**, jamais avalé — et la ligne du tableau de confiance dit laquelle des deux.
- [ ] Un garde d'exclusion que ce run n'a pas pris n'arrête pas la nuit en accusant le tracker : la phrase imprimée dit ce qui a refusé, et elle est vraie.
- [ ] `gate__stale_guards` voit aussi le garde de claim du backend local (`issues/<id>.md.guard`, un niveau plus bas) et dit quelque chose d'un garde dont le propriétaire est vivant mais étranger à ce run.
- [ ] L'URL que `router_dossier` montre comme reçu d'un backend distant porte la réserve **exacte** : elle est lue dans un fichier de cet arbre, pas sur le réseau.
- [ ] Le backend local garde exactement ses garanties actuelles, et le drain les siennes.

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
