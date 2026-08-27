# Passe transversale du 27/08/2026

Faite sur `main` à `fcf45e1` (merge de [47]), avant [39]. Trois tickets la
précédaient depuis la passe du 26/08 : [38], [37], [47]. Arbre propre au départ,
**rien édité dans `.claude/` ni dans `test/`** — les sondes sont des `.bats` qui
pilotent le pack tel qu'il est livré, conservées dans `sondes/passe-27-08/`.

Les sondes se terminent par un `false` volontaire : ce sont des instruments, pas
des tests. Elles rougissent toujours ; ce qu'on lit est ce qu'elles impriment
avant.

Seuil déclenché plus tôt que 4-5 tickets, et pour la raison écrite dans le
prompt de reprise : les trois livraisons ont touché le même organe (les listes
d'ids, le tracker, la création de tickets) et [47] a ajouté un **garde**,
c'est-à-dire un objet qui n'existait pas quand les tickets antérieurs ont été
sondés.

---

## La racine commune, et c'est elle le ticket

**Le pack range ses propres objets d'exécution dans des répertoires dont les
gardes sont écrits contre une autre forme** — `issues/` est traité comme « un
répertoire de fichiers de ticket », `.scratch/<feature>/` comme « une zone que
rien ne juge et qui ne vaut qu'un verrou de run ». [47] a posé un quatrième objet
dans la seconde, après avoir **nommé précisément** le danger de la première :

> « `issues/` est l'arbre que `failures_protect_tracker` compare autour de chaque
> session, donc un garde pris là arriverait comme un chemin `A`/`D` que la
> restauration tenterait de `checkout-index`. »

Le diagnostic est juste et il a servi à écarter *son* garde. Personne n'est
retourné voir ce qui était déjà là — ni ce que la seconde zone vaut maintenant
qu'un garde y vit.

Les trouvailles 1 et 2 en découlent. Les autres angles ouverts par [47] ont été
sondés et sont **disculpés**, la vérification est écrite plus bas.

---

## 1. `issues/` porte trois sortes d'objets transitoires du pack, et la restauration les ressuscite

`failures_protect_tracker` prend un tree object de `issues/` avant le spawn, un
autre après, et restaure ce qui a bougé. L'exemption de [13]/[42] est indexée par
**id** (`failures__in_list "$(basename "$path" .md)" "$ours"`).

Or `issues/` ne contient pas que des tickets. Trois producteurs, tous dans le
pack lui-même :

| Chemin | Qui l'écrit | Durée mesurée |
|---|---|---|
| `<id>.md.guard/{pid,since}` | `tracker_local_claim` (le garde de [12]) | une prise de claim |
| `<id>.md.tmp.XXXXXX` | `state_atomic_write` | un `cat` + un `mv` |
| `<id>.md.work.XXXXXX` et `.work.XXXXXX.p` | `tracker_local__set_fields` | **15 ms** par édition de champ |

Aucun de ces noms n'est un id : `basename ".../02-beta.md.guard/pid" .md` rend
`pid`, `basename "02-beta.md.work.IDdYXp" .md` rend le nom entier. Le registre ne
peut donc **structurellement** pas les exempter — sondé plutôt que déduit
(`q5` Q5e, registre correctement rempli avec `02-beta`, `restored 3 ticket
file(s)` quand même).

### Ce que ça coûte, reproduit

Un transitoire présent dans le snapshot d'**avant** et absent de celui d'**après**
tombe dans la branche `*)` — `checkout-index -f` — et incrémente `restored` :

    ralph: 01-alpha: the session edited the tracker — restored 2 ticket file(s), the iteration cannot be green
    protect_tracker rc=1
    === is the guard back?
    yes: pid=52958 (this pilot is 52958)
    === what 01-alpha was told
    The 01-alpha session edited the tracker itself (2 ticket file(s)). …
    === can 02-beta ever be claimed again in this run?
    REFUSED

Trois conséquences, la troisième est la mauvaise :

1. **Un contrôle accuse la session de ce qu'elle n'a pas fait.** La note écrite
   sur le ticket dit « The 01-alpha session edited the tracker itself » alors que
   la session n'a rien écrit dans le tracker. C'est la famille que ce dépôt
   connaît par cœur ([30] sur `core.excludesFile`, [37] sur la quarantaine) : un
   contrôle qui rapporte son intention au lieu de son résultat.
2. **L'itération innocente ne peut pas être verte** (`rc=1` → l'itération est
   traitée comme une session qui a écrit le tracker).
3. **Le garde de claim ressuscité porte le pid du pilote, qui est vivant.** Plus
   rien ne le relâche — `state_guard_release` ne suit qu'une prise réussie — donc
   le ticket est **inréclamable pour le reste du run**. Sondé bout en bout
   (`q5` Q5d) :

       === 01-alpha=resolved 02-beta=ready-for-agent
       ralph: could not claim 02-beta — someone else has it
       ralph: could not claim 02-beta — someone else has it
       ralph: sterile run: 2 iterations resolved nothing — stopping
       === run.log
       2026-08-27T…	01-alpha	resolved	…
       === is 02-beta still on the frontier?
       02-beta

   Le ticket reste `ready-for-agent`, **sur la frontière**, et le run s'arrête
   stérile. `run.log` n'a **aucune ligne** pour lui. La console dit « someone
   else has it » en désignant un propriétaire qui n'existe pas.

### Largeur de la fenêtre, mesurée et pas supposée

    === failures_tracker_tree (the pre-session snapshot): 35 ms
    === one claim + one unclaim (what loop__start does per iteration): 64 ms
    === one set_fields (the .work + .work.p transient): 15 ms

Ce n'est pas une microseconde. Le snapshot est un `git add -A` de 35 ms sur
`issues/`, et chaque écriture d'une sœur expose un transitoire pendant ~15 ms.
Avec une sœur qui écrit **en continu**, 52 snapshots sur 60 capturent un
transitoire (`q6` Q6a) — ce chiffre-là mesure le pire cas et il faut le dire :
en exploitation une sœur écrit le tracker quelques fois par itération, pas en
boucle. L'ordre de grandeur honnête est donc « rare par itération, certain sur un
run assez long », et à `MAX_PARALLEL>1` sur une nuit de centaines d'itérations
c'est une loterie qu'on finit par gagner. Ce qu'elle paie quand elle tombe est la
liste ci-dessus.

**Le cas miroir est sain, vérifié** (`q5` Q5b) : un transitoire qui **apparaît**
dans la fenêtre est un `A`, la branche `A` ne fait rien, `restored` reste à zéro,
aucune note. Et `tracker_ids` ne glob que `*.md`, donc aucun de ces chemins ne
devient un intrus pour la quarantaine.

## 2. Une session peut *poser* le garde d'ouverture, et ça n'achète pas une collision

Le tableau de confiance dit du garde de [47] :

> « le garde hérite de l'exposition du verrou de run — une session peut le
> supprimer ([12]) — et ce que ça lui rachèterait n'est qu'une collision entre
> deux écrivains de la boucle »

La **suppression** est nommée. La **pose** ne l'est pas, et son prix n'est pas du
tout le même. Sondé (`q2`), depuis une itération verte :

    === 01-alpha=resolved 07=ready-for-human escalation=too-big
    ralph: gate: 01-alpha: tests=green typecheck=green scope=green lang=green
    (no gate line names the guard)
    tracker: could not take the ticket-open guard — refusing to allocate a number nothing serialises
    ralph: 07-overlaps-alpha: could not create the ticket for 'alpha-half'
    …
    ralph: 07-overlaps-alpha: the re-slice created nothing
    === is the plant still there, and did the rollback reach it?
    still there, pid=47100

La session lit `git worktree list` pour trouver l'arbre principal — la porte que
la passe du 26/08 avait déjà mesurée — crée
`<arbre>/.scratch/<feature>/.open.guard/pid` avec le pid d'un `sleep` qu'elle
forke, et livre normalement. Le scope-guard est vert : le garde vit dans l'arbre
**principal**, hors du worktree que les branches du gate jugent. Le rollback ne
l'atteint pas. Le plant survit au run.

Ce que ça éteint pour le reste de la nuit, et sur tous les runs suivants tant que
le propriétaire vit : les trois producteurs de tickets (`failures_reslice`,
l'escalade du retro, `capability_propose`) **et** `tracker_renumber`,
c'est-à-dire la réparation de [27]. Une session qui pose le garde *et* écrit un
ticket au numéro d'un autre s'achète la collision que la quarantaine sait
normalement défaire.

**Et la cause n'atteint aucun document durable.** Le reçu porte bien les trois
`gap` — `could not create the ticket for 'alpha-half'`, `the re-slice created
nothing` — mais jamais le garde : les deux lignes qui le nomment sont un
`printf … >&2` de `tracker_local__open`, sur la console. `run.log` enregistre
`action=escalated:too-big`, ce qui est la mauvaise cause. Un humain lit le matin
un ticket que la boucle a jugé trop gros, pas un espace de numéros mort.

**Et personne ne compte ni ne balaye un `.open.guard` laissé** (`q1` Q1a) : un
garde périmé par un `kill -9` traverse un run vert entier sans un mot,
`gate_leftovers` ne regardant que `$TMPDIR`. Il est repris silencieusement à la
première allocation suivante, ce qui est le bon comportement — mais le verrou de
run, lui, est relâché par son trap `EXIT` ; ce garde-ci ne l'est par rien.

---

## Les angles disculpés, et il ne faut pas les resonder

- **`state_guard_release` avec deux sœurs en vol** (angle 2 de [47]). Vérifié et
  pas supposé (`q4` Q4c) : une sœur refusée ne relâche pas le garde de sa
  jumelle, ne laisse pas de ticket derrière elle, et les deux refus parlent. Tous
  les `state_guard_release` du pack suivent une prise réussie dans la même
  fonction ; les deux relâches de verrou sont gardées par une variable que seule
  une prise réussie fixe ; et un sous-shell n'hérite **pas** du trap `EXIT`
  (mesuré sur le bash 3.2 de cette machine), donc une itération ne peut pas
  relâcher les verrous du pilote en mourant.
- **La double reprise d'un garde périmé.** Mise en scène avec une barrière
  d'attente active pour que deux sous-shells d'un même pilote entrent vraiment
  ensemble dans `state_guard_take` (`q4` Q4a, 145/155 — la concurrence est
  réelle) : **`both=0` sur 300 tours**, et zéro collision de numéro sur 60 tours
  (`q4` Q4b). La course que `state.sh` décrit est stagée, pas gagnée. Elle est
  déjà écrite comme une limite non réparée dans la ligne [47] du tableau. *Un
  seul point à corriger, une ligne et pas un ticket* : le commentaire de
  `state.sh` énumère ce qui couvre cette course en aval — « les verrous
  revérifiés à chaque itération, le claim qui est un test-and-set sur le
  `Status:` » — et [47] a ajouté un consommateur dont la correction **est**
  l'exclusion mutuelle, sans rien en aval. La liste est devenue fausse par
  omission.
- **Le garde d'ouverture face aux gates et à l'énumération de la zone ignorée**
  (angle 1 de [47]). Sondé (`q1` Q1b, projet qui ignore `.scratch/`) : aucune
  ligne de zone, aucun verdict, `scope=green`. La raison est structurelle et elle
  vaut pour tout ce répertoire — les branches du gate jugent le **worktree**, et
  `ralph_feature_dir` résout dans l'arbre **principal** via `RALPH_DIR`. Le garde
  a exactement le statut de `.run.lock` et de `run.log`. Ce n'est pas une
  exposition neuve ; ce que cette zone *achète* maintenant est la trouvaille 2.
- **Le refus bout en bout du re-slice** (angle 3 de [47]). Les deux régimes
  tournent et se disent (`q3`). Garde tenu toute la nuit : parent
  `ready-for-human`, `Escalation: too-big`, reçu portant les trois gaps. Garde
  relâché en cours de split : `Re-slice incomplete: only 08-eta-half could be
  created out of the planned split`, sur le ticket, sur la console et sur le
  reçu. *Deux observations mineures, pas des tickets* : (a) le chemin « créé
  aucun » n'écrit **rien sur le ticket**, alors que le chemin « incomplet » y
  écrit une note — un humain qui trie le matin ne distingue pas une allocation
  refusée d'un plan inutilisable sans ouvrir le reçu ; (b) la borne annoncée est
  de 6 s et la mesure donne **8 s** (120 × 0,05 s plus le coût de la boucle), et
  `tracker_renumber` la paie **par intrus**, donc une session qui dépose dix
  fichiers coûte 80 s d'itération immobile.
- **Le slug d'un plan de re-slice comme nom de fichier.** `failures__plan_slug`
  fait `tr -c 'a-z0-9-' ' '` puis prend le premier mot : ni `/`, ni espace, ni
  saut de ligne ne survivent. Pas de porte ici, vérifié par lecture — ne pas le
  remettre dans une liste.
- **Les sondes conservées de [37] et de la passe du 26/08, rejouées sur
  `fcf45e1`.** `p4` P4a rend maintenant `03-second` / `04-first` — [47] tient.
  `p4` P4b, `s2` a/b/c/d rendent leur état d'après-correctif. Aucune dérive.

---

## Recommandation d'ordre

**Un seul ticket neuf, [49]**, portant les deux trouvailles. Elles ont une racine
(ci-dessus), elles éditent **le même paragraphe** du tableau de confiance — la
ligne « Un ticket est identifiable par son `NN` » et la ligne « Ne pas changer le
`Status:` du ticket » — et elles partagent leurs sondes. Les séparer coûterait
deux passes de mutation sur les mêmes fichiers et deux réécritures du même
paragraphe. Si Philippe préfère deux tickets, la coupure naturelle est
`issues/` (trouvaille 1) contre `.scratch/<feature>/` (trouvaille 2).

**Avant [16] et [18]**, pour la raison de reprise : [16] est la boucle humaine,
c'est-à-dire exactement le lecteur d'une frontière dont un ticket a disparu sans
qu'aucun journal le dise ; et [18] doit implémenter un backend de tracker
distant, donc hériter de la clause « le répertoire du tracker ne contient pas que
des tickets, et un garde autour d'une session ne doit pas prendre le reste pour
une édition » plutôt que la redécouvrir. Disjoint de [39], de [46] et de [09].

Ordre proposé : **[39] → [49] → [46] → [09] → [16] → [11] → [18] → [19]**.
[49] est placé après [39] parce que [39] est déjà en tête et disjoint, et avant
[46] parce que les deux touchent le tableau de confiance et qu'il vaut mieux que
le paragraphe de [47] soit corrigé avant que [46] n'en ajoute un.

Voir [[ralph-pack-ordre-livraison]] et [[ralph-pack-pieges-de-harnais]].
