# 56 — un correctif humain non commité n'est jamais jugé, et la boucle l'accuse

**What to build:** Rendre vraie, ou cesser de dire, la promesse centrale du puits
humain. À la touche `r` le drain écrit « back on the frontier, retry budget
cleared — **a fresh session and the whole gate decide now** », et le prompt de la
session routée promet la même chose. Or la session routée écrit dans l'**arbre
principal**, rien ne commite, et depuis [13] une itération AFK tourne dans un
worktree créé au **tip de la branche** (`concurrency_worktree_add` :
`git worktree add --detach "$dir" "$(git rev-parse HEAD)"`). Ce qui n'est pas
commité n'est donc pas là. Le gate ne juge pas le correctif : il juge son
absence.

**Blocked by:** 55

**Write-surface:** `.claude/human-loop.sh`, `.claude/lib/router.sh`,
`test/human-loop.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** resolved

**Tags:** frontiere-de-confiance

- [x] **Le drain sait ce que la session routée a laissé dans l'arbre**, et il le
      dit. Un correctif non commité n'est pas un détail d'usage : c'est l'état
      **par défaut** à la sortie d'une conversation avec `claude`.
- [x] **La réinjection ne promet plus ce qu'elle ne fait pas.** Trois directions,
      en trancher une et écrire le prix : refuser `r` tant que l'arbre porte des
      modifications non commitées sur des chemins que le ticket nomme ; les
      commiter depuis le drain (et alors dire sous quel auteur, et ce que ça fait
      d'un arbre où l'humain travaillait *aussi* sur autre chose) ; ou garder la
      réinjection telle quelle et **changer la phrase**, en nommant le commit
      comme la condition qu'il est.
- [x] **Le retour ne ment plus sur ce qui s'est passé.** Un ticket qui revient
      avec `Failures: 3` et `Escalation: failed-impl` après un correctif jamais
      vu envoie l'humain au guichet `implement`, dont la question est « Why is the
      code wrong » — à propos d'un code que le gate n'a pas lu.
- [x] **Une mutation par garantie livrée**, témoin appairé vérifié à la main.

## Ce que la passe du 31/08 a mesuré

Sondes conservées :
`.scratch/ralph-pack/sondes/passe-31-08/p2-le-correctif-humain-que-le-gate-ne-voit-pas.bats`.
Le gate est réduit à une seule question, `TEST_CMD='test -f src/human-note.txt'`,
et la session routée écrit ce fichier **hors** de la write-surface du ticket pour
que la session AFK ne le fabrique pas elle-même.

- **P2a — le correctif n'est pas commité** (l'état par défaut). Après le drain :
  `Status: ready-for-agent`, le fichier est bien là, `git status --porcelain` dit
  `?? src/`. Puis le run AFK :

      ralph: gate: 09-escalated: tests=red typecheck=green scope=green lang=green
      ralph: 09-escalated: gate-red -> fresh retry (1 of 2)
      ralph: gate: 09-escalated: tests=red typecheck=green scope=green lang=green
      ralph: 09-escalated: gate-red -> fresh retry (2 of 2)
      ralph: gate: 09-escalated: tests=red typecheck=green scope=green lang=green

  **Trois itérations, tout le budget de retries brûlé**, et le ticket revient au
  puits en `Failures: 3`, `Escalation: failed-impl`. Le correctif est toujours
  dans l'arbre principal, non suivi, jamais lu par aucune des trois sessions, et
  **aucune ligne ne le nomme** — ni au journal, ni au reçu.
- **P2b, témoin appairé** — le même correctif, commité à la main entre le drain et
  le run : `tests=green typecheck=green scope=green lang=green`,
  **`Status: resolved`**, dès la première itération.

La seule différence entre les deux est un `git commit` que rien dans le pack ne
demande, ne mentionne, ni ne vérifie.

## Ce que ça aggrave

`router_reinject` remet `Failures:` à zéro — c'est la réparation de [16] sur la
décision que [26] avait laissée ouverte, et elle est correcte. Conséquence
inattendue ici : le compteur repart de zéro, le run le remonte à 3, et **rien ne
distingue « le gate a jugé ton correctif et l'a refusé » de « le gate n'a jamais
vu ton correctif »**. Le second drainage présente un ticket qui a l'air d'avoir
été jugé loyalement.

## Une contrainte que [16] avait reçue et n'a pas dépensée

[13] l'avait écrite dans le ticket [16], en toutes lettres : « ce qu'un humain a
de non commité n'est plus jamais jugé, rollbacké ni commité par la boucle AFK ».
Elle est dans la liste des contraintes de [16], elle n'est **ni dans ses
décisions, ni dans son code, ni au tableau de frontière**, et la phrase que le
drain imprime dit le contraire. C'est la question 4 de CLAUDE.md dans sa forme
pure — et le rappel que la liste des contraintes d'un ticket n'est pas une liste
de choses faites.

## Pièges connus, pour celui qui livre

- **Ne pas commiter aveuglément.** L'arbre principal est celui de l'opérateur : un
  `git add -A` depuis le drain emporterait ce sur quoi l'humain travaillait à
  côté. C'est la raison pour laquelle [21] désindexe et pour laquelle
  `failures_make_durable` ne commite que des chemins approuvés.
- **Point de convergence avec [55]** : les deux tickets veulent que le drain sache
  ce que la session routée a fait — [55] dans le tracker, celui-ci dans l'arbre.
  Un seul instantané autour de `human_loop__session` répond aux deux ([46] : viser
  le point de convergence, pas deux mécanismes).
- **Une assertion sur `assert_success` ne prouve rien ici** : asserter les
  verdicts du gate et le `Status:` final, comme les sondes le font.
- **`session_writes` du harnais écrit la write-surface du ticket** : un fichier
  témoin posé *dans* cette surface serait fabriqué par la session AFK elle-même et
  la sonde serait verte des deux côtés.

## Ce que [57] laisse à ce ticket (écrit le 31/08/2026, à sa livraison)

- **L'instantané autour de `human_loop__session` que ce ticket vise a un voisin
  immédiat** : [57] pose déjà une question en tête de la boucle `while :;` de
  `human_loop__drain_one`, c'est-à-dire exactement après le retour d'une session et
  avant que le menu ne soit ré-offert. C'est le point de convergence que ce ticket
  et [55] cherchent, et il est déjà occupé — regarder ce qui y est avant d'ouvrir un
  second endroit.
- **[57] a mesuré pourquoi ce n'est pas `human_loop_main`** : la frontière de ticket
  rate le cas où un humain répond `o` deux fois sur le même ticket, et un contrôle
  posé aux deux endroits est du code mort à un des deux — aucune mutation ne peut
  les distinguer.
- **`human_loop__drain_one` rend maintenant quatre codes** (0, 1, 3, 4). Le `4`
  arrête le drain entier ; le traiter avant le `*)` du `case` de `human_loop_main`.

## Ce que [55] laisse à ce ticket (écrit le 31/08/2026, à sa livraison)

- **L'instantané partagé n'a pas été posé, et c'est une décision écrite plutôt
  qu'un oubli.** [55] avait le point de convergence dans ses pièges ; ce qu'il a
  livré est un **pin** — deux variables non exportées du process du drain
  (`ROUTER__PINNED_ESCALATION`, `ROUTER__PINNED_SURFACE`), prises par
  `router_pin` en tête de `human_loop__drain_one`, avant le dossier et avant
  toute session. Trois raisons, à relire avant de bâtir dessus : un hash d'arbre
  aurait refusé une transition sur le ticket A parce que la session a touché le
  ticket B (fausse accusation) ; il ne dit pas *quel champ* a bougé, donc il ne
  peut pas porter la phrase qu'un humain refusé doit lire ; et ce que ce
  ticket-ci a besoin de savoir n'est pas l'arbre du tracker mais **l'arbre de
  travail**, qui est un autre objet. Ce qui est partagé est donc le **moment et
  l'endroit**, pas l'objet : `router_pin ID`, dans `router.sh`, une fois par
  ticket. Un témoin d'arbre de travail a sa place au même appel — et alors le
  point de convergence est vraiment un seul endroit.
- **La frontière du pin, pour ne pas la croire plus large qu'elle n'est.** Il
  couvre `Escalation:` et `Write-surface:` du **seul** ticket que le drain tient.
  `Failures:`, la ref `failed/<id>`, le corps du ticket et **tout autre ticket**
  restent écrits par une session que rien ne juge — mesuré, avec la sonde
  conservée, et donné à [58].
- **Les deux transitions sont fail-closed.** `router_may_sign_off` et
  `router_may_reinject` refusent désormais un ticket que rien n'a épinglé, avec
  leur propre phrase. Un chemin de réinjection ajouté ici sans `router_pin`
  devant s'arrêtera sur le premier ticket — bruyamment, ce qui est le but.
- **Et le prix que [55] a écrit est le voisin direct du tien** : une correction
  faite *pendant* la conversation routée ne décide pas dans cette passe du drain.
  Ce ticket-ci va découvrir le même mur d'un autre côté — un correctif de code
  fait pendant la conversation n'est pas jugé non plus tant que rien ne le
  commite. Les deux prix se disent dans la même phrase à l'humain ou ils se
  contrediront.

## Ce qui a été livré, et les décisions (01/09/2026)

### La direction choisie, et pourquoi les deux autres ont été refusées

**Refuser `r`**, et refuser sur **tout** l'écart entre l'arbre de travail et
`HEAD` — pas seulement sur les chemins que le ticket nomme, pas seulement sur ce
qui est apparu depuis que le drain tient ce ticket.

- *Commiter depuis le drain* est refusé pour la raison que le ticket portait
  déjà : l'arbre principal est celui de l'opérateur, et le seul commit honnête
  serait un `git add` de chemins choisis par quelqu'un. Le pack n'a aucune
  liste qui vaille ici — la write-surface du ticket ne couvre pas le cas mesuré
  (le correctif tombe souvent à côté, et c'est même le signal que la surface est
  fausse), et un auteur qui n'est ni l'humain ni la session serait un troisième
  écrivain dans l'historique de l'opérateur.
- *Changer seulement la phrase* est refusé pour la raison qu'`docs/frontiere-de-confiance.md`
  existe : une phrase n'est pas une garantie. La phrase a quand même été changée,
  mais comme conséquence du refus et pas à sa place.
- *Refuser sur les chemins que le ticket nomme* — la formulation du critère —
  a été mesurée et écartée : la sonde de la passe a délibérément écrit **hors**
  de la write-surface, et ce n'est pas un artefact de sonde. Un correctif humain
  qui tombe à côté de la surface déclarée est exactement le cas où il faut
  refuser le plus fort.
- *Refuser sur ce qui est apparu depuis le pin* a été écarté par l'argument qui
  décide tout ce ticket : **le drain ne sait pas distinguer une édition sans
  rapport du correctif**, et un humain qui répare le code *puis* lance le drain
  — un ordre normal, sans doute le plus courant — laisse un chemin qui ressemble
  exactement à du travail en cours. Un refus indexé sur la fenêtre du drain
  aurait laissé passer ce cas-là en silence.

### Ce qui a été écrit

- `router__tree_dirt` — un chemin par ligne, l'écart entre l'arbre et `HEAD`.
  Deux producteurs (`diff --name-only HEAD` pour le suivi, suppressions
  comprises ; `ls-files --others --exclude-standard` pour le reste),
  `core.quotePath=false` sur les deux ([39]).
- `router_pin` prend en plus `ROUTER__PINNED_TREE` — **une base de comparaison,
  pas une valeur sur laquelle un refus décide**. C'est la différence avec les
  deux champs de [55], et elle est délibérée : un champ est ce qu'une session
  réécrit pour tromper un contrôle, un arbre est ce qu'un humain est censé
  changer. Le refus lit donc toujours l'arbre **courant**, pour qu'un humain qui
  commite dans un autre terminal et retape `r` passe.
- `router_tree_note ID` — au retour de chaque session routée, ce qu'elle a
  laissé, séparé de ce qui était déjà là. Silencieux quand l'arbre égale `HEAD`.
- Le refus dans `router_may_reinject`, **après** celui de la surface, à côté de
  la transition et pas dans le menu — pour que [11] en hérite.
- La phrase de `r` nomme sa condition, et le prompt de la session routée dit la
  même chose dans le même paragraphe que le prix de [55].

### Le prix, écrit parce que c'est l'arbre de l'opérateur

Un humain avec du travail en cours **sans rapport** ne peut pas réinjecter avant
de l'avoir commité ou mis de côté. Ce qui le rend tenable : la question est
reposée à chaque appui, et [33] écrase déjà une édition non commitée sur un
chemin qu'une itération vient de livrer — un arbre sale au moment où l'on confie
du travail à un run n'est pas un état que ce pack ait jamais su protéger.

Ce qui n'est **pas** refusé : le sign-off. `s` résout un ticket dont aucun gate
n'a rien lu, ce qui est toute la définition d'un sign-off ([16]) ; lui emprunter
ce refus serait le mettre au service d'une promesse que personne n'a faite. Idem
pour `c`.

### Le troisième critère, tenu sans second mécanisme

Le retour ne peut plus mentir parce que le départ est refusé : un ticket ne peut
plus revenir en `Failures: 3` / `failed-impl` sur un correctif que le gate n'a
pas lu, puisqu'il ne peut plus partir dans cet état. Mesuré, sonde conservée
`.scratch/ralph-pack/sondes/ticket-56/` : le drain refuse, `ready-for-human`,
`Failures: 2`, et le run AFK suivant sort `exit 5` **sans dépenser une session**
— contre trois itérations rouges et tout le budget avant. Témoin appairé (`S2`,
correctif commité entre deux drainages) : `tests=green`, `resolved` à la première
itération.

### Ce que ça ne tient pas, mesuré

- **Le refus lit un arbre que la session routée écrit aussi.** Elle peut le
  rendre propre sans que le correctif soit sur la branche — sonde `S3` : elle
  écrit le fichier puis le reprend, `r` passe, le run rend trois rouges. Ce que
  ça coûte est le **rapport**, pas la **promesse** : ce qu'un worktree neuf porte
  est `HEAD`, et personne n'a besoin de le dire au drain. Ce n'est pas un contrôle
  contre un adversaire, c'est un contrôle contre l'**état par défaut**.
- **Le refus tombe à l'instant de la promesse et pas pour toujours.** Rien
  n'empêche un humain de salir l'arbre après avoir réinjecté puis de lancer un
  run à la main ; ce qui arrive alors est déjà au tableau, ligne [33]
  (l'itération écrase l'édition non commitée sur les chemins qu'elle livre). Pas
  de propriétaire ouvert : `loop.sh` est hors write-surface, et la croyance que
  ce cas exploitait est corrigée par la phrase que `r` imprime.
- **L'attribution du témoin est par chemin et pas par contenu.** Un chemin déjà
  modifié quand le drain a pris le ticket, et que la session modifie *encore*,
  est rapporté comme déjà-là. Ce qui décide n'est pas cette ligne mais le refus,
  qui tombe dessus dans les deux cas.
- **Le répertoire de la feature est hors du compte**, donc un « correctif » écrit
  dans `issues/` n'est pas vu — c'est un ticket et pas du code, il relève de [55]
  et de [58], et ce dernier a reçu la note pour ne pas croire l'inverse.

### Pièges rencontrés

- **`gate__drop_bookkeeping` est un privé de `gate`** : `router.sh` appelle
  `gate_is_bookkeeping` dans sa propre boucle. `test/layering.bats` refuse
  l'autre forme.
- **Le harnais commite tout** (`use_tickets`, `mk_ticket`, `set_config` passent
  par `harness__commit`), donc l'arbre de fixture est propre au départ et le
  refus ne casse aucun test existant. Mais le drain lui-même laisse
  `.scratch/<feature>/run.log` et `.run.lock/` non suivis dès la première
  écriture : sans l'exemption, **huit** tests de `human-loop.bats` rougissent, y
  compris « a re-injected ticket gets its whole retry budget back ». C'est ce qui
  fait de l'exemption une garantie livrée et pas un détail.
- **La sonde `P2b` du 31/08 est périmée par cette livraison** : elle commitait
  *après* le `r`, ce que le refus rend impossible, et elle rend maintenant
  `exit 5` des deux côtés. La question est reprise par `S2` dans le seul ordre
  qui existe encore. C'est le piège « une sonde conservée peut poser une question
  périmée et répondre *rien* », rencontré une seconde fois.

### Contraintes écrites ailleurs

- **[11]** : le refus est à côté de la transition, donc tout appelant de
  `router_reinject` l'a — et la question qu'il pose n'a de sens que là où un
  **humain** écrit. Une réinjection hybride déclenchée depuis le pilote doit
  d'abord mesurer ce que `router__tree_dirt` voit dans cet arbre-là.
- **[58]** : le témoin d'arbre **exclut** `issues/`, par construction et pour une
  raison qui ne peut pas être levée ici. Ne pas lire « le drain sait ce que la
  session a laissé dans l'arbre » comme couvrant le tracker.
