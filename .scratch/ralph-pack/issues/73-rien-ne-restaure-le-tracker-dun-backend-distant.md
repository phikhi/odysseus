# 73 — Rien ne restaure le tracker d'un backend distant

**What to build:** Une protection du tracker qui ne suppose pas que les tickets sont des fichiers de cet arbre — soit une opération d'adaptateur snapshot/restore, soit un refus qui ne coûte pas la nuit.

**Blocked by:** 74, 75, 77

**Write-surface:** `.claude/lib/failures.sh`, `.claude/lib/tracker.sh`, `.claude/lib/tracker-local.sh`, `.claude/lib/tracker-github.sh`, `.claude/lib/tracker-gitlab.sh`, `.claude/lib/forge.sh`, `.claude/lib/forensic.sh`, `.claude/loop.sh`, `test/failures.bats`, `test/tracker-remote.bats`, `test/mutate.sh`

**Status:** resolved

- [x] Ce qu'une session écrit dans un tracker distant est **remis** ou **refusé**, jamais avalé — et la ligne du tableau de confiance dit laquelle des deux.
- [x] `failures_protect_tracker` cesse d'être écrit contre un tree object de git : le transport est demandé à l'adaptateur, comme le chemin l'est déjà (`tracker_tickets_dir`).
- [x] Le backend `local` garde **exactement** ses garanties actuelles — les trois statuts `A`/`D`/`M`, l'exemption par le registre de [13]/[42], `failures__is_ticket_path`, le refus de vouloir garder un arbre qu'il n'a pas pu lire ([59]).
- [x] Un backend distant qui refuse le snapshot n'est pas rouge à chaque itération.

## Comments

- **Ouvert par [18], livré le 08/09/2026, et il porte la moitié que [18] n'a pas
  prise.** [21] restaure ce qu'une session écrit dans `issues/` en comparant deux
  tree objects pris autour du spawn, ce qui est **ce qui rend le scope-guard
  fiable** : la write-surface jugée est le contrat tel qu'il était au spawn et non
  celui que la session vient peut-être d'écrire. Sur `github` et `gitlab` il n'y a
  pas de répertoire : le pathspec ne correspondait à rien, les deux arbres étaient
  l'arbre vide, et `failures_protect_tracker` **rendait zéro sans un mot**.

  Ce que [18] a livré : le chemin est demandé à l'adaptateur
  (`tracker_tickets_dir`, symétrique de `tracker_receipt_dir` posée par [70]), un
  refus est une branche explicite, et `forensic_uncovered` porte la phrase **une
  fois** au démarrage du run et du drain. C'est un témoin, pas un contrôle — la
  posture que [70] a tranchée pour les zones que rien ne garde.

  Ce que ça laisse, et c'est l'objet de ce ticket : **une session qui édite son
  propre ticket par le réseau élargit sa write-surface, et le gate la juge sur la
  surface élargie.** Aucun scope-guard, aucun rollback, aucun témoin de fichier
  local ne le voit. C'est le pire des trous d'un backend distant, parce que c'est
  exactement le trou que [21] a été écrit pour fermer.

- **Pourquoi [18] ne l'a pas pris, écrit pour que ce ne soit pas redécouvert.**
  Les deux sorties que [21] avait nommées ont été pesées :

  1. *Un refus bruyant à chaque fenêtre.* Rejeté, mesuré : `failures_protect_tracker`
     non zéro fait payer l'itération, donc **toute** itération d'un backend distant
     serait rouge et le backend serait inutilisable. On échangerait un faux vert
     contre pas de vert.
  2. *Une opération d'adaptateur snapshot/restore.* C'est la bonne réponse et elle
     est faisable — un seul listing rend tous les corps, donc un instantané est
     `<id><TAB>digest` pour tout le tracker, et une remise est un `PATCH` par
     ticket qui a bougé et qui n'est pas dans le registre de [13]. Ce qu'elle
     demande est **hors de la write-surface de [18]** : `failures_protect_tracker`
     est écrite autour de `git read-tree` / `git diff-tree` / `checkout-index` et
     de trois statuts, donc la rendre agnostique du transport est une réécriture de
     ce garde-là, pas un ajout de backend.

- **Le piège de cette réécriture, nommé avant d'y entrer.** Le garde local ne fait
  pas que restaurer : il distingue `A` (laissé à la quarantaine, jamais détruit),
  `D` (remis) et `M` (remis), il saute les ids que la **boucle** a écrits pendant
  la fenêtre (`failures__register_since`, [13]/[42]), il refuse de vouloir garantir
  un arbre que git n'a pas pu lire ([59]) et il ne restaure que ce qui est un
  ticket (`failures__is_ticket_path`, [49]). Une interface générique qui perd un
  seul de ces quatre points rouvre un défaut que ce dépôt a déjà payé — et trois
  d'entre eux sont invisibles à un test qui ne fait tourner qu'un seul backend.

- **Question transversale à poser en le livrant** : le registre de [13] est indexé
  par **id**, et l'id d'un backend distant est `<numéro>-<slug>` où le slug vient
  du corps. Un slug qu'une session modifie change l'id du ticket sans changer le
  ticket. Personne n'a mesuré ce que ça fait aux deux gardes de [42].

- **Ce que la passe transversale du 08/09/2026 a mesuré, et qui change deux
  choses ici** (`../passe-transversale-08-09.md` §3, sondes
  `../sondes/passe-08-09/q3-*.bats`).

  1. **Le prix, sur un run réel.** Une session d'itération qui met le ticket
     **du puits humain** à `resolved` : run **rc=0**, itération **verte**, le
     ticket reste `resolved` et le run ne dit que sa phrase générique de
     démarrage (Q3b). Témoin appairé sur le backend local (Q3c) : « the session
     edited the tracker — restored 1 ticket file(s), the iteration cannot be
     green », outcome `tracker-write`. Ce n'est donc pas seulement « la
     write-surface est lue sur un ticket que la session peut écrire » : **un
     ticket qui attendait une décision humaine sort du puits, et l'itération est
     verte.** C'est l'écriture que [58] existe pour attraper côté drain.
  2. **La parade existe déjà, dans `router.sh`.** Mesuré (Q3a) : sur un backend
     distant, une session **routée** qui met un voisin à `resolved` est remise —
     `router_pin` prend l'état par `router__tracker_state`, `router__put_back`
     remet par `tracker_mark_ready`, donc deux opérations de l'interface et pas
     une ligne de git — et le drain redit la réserve de [61] sur les trois champs
     qu'il ne remet pas. C'est le mécanisme que ce ticket cherche, à l'endroit où
     il existe déjà : le rapprochement à faire est avec `router_protect_tracker`,
     pas avec une réécriture de `failures_protect_tracker` à partir de zéro.
     Ce qu'il coûte est chiffré et appartient à **[75]** — cinq champs plus le
     corps par ticket, par fenêtre — donc les deux tickets se rencontrent : la
     remise de ce ticket-ci est le consommateur qui rend le cache de [75]
     nécessaire, et pas l'inverse.

- **Et une seconde zone non restaurée que l'AC ne nomme pas** : le sidecar
  `.scratch/<feature>/.forge-claims` porte le claim, le numéro de requête et
  l'URL du reçu d'un backend distant, et rien ne le restaure non plus. Il a son
  ticket — **[77]** — parce que la moitié « garde de claim » du même défaut est
  celle du backend **local** et qu'elle est là depuis [47]/[49]. Les deux
  tickets se touchent sur une question : ce qui restaure le tracker d'un backend
  distant restaure-t-il aussi ce que ce backend garde en local ?

## Contrainte écrite par [74] (livré le 09/09/2026)

Ce ticket ajoute une opération d'adaptateur, donc un **refus** de plus que la
boucle devra lire ; [74] a tranché comment, et le précédent est à reprendre plutôt
qu'à réinventer.

1. **Un refus est un code de retour, lu à l'endroit où il existe.** La forme qui
   l'avale est la substitution de commande dans un heredoc (`<<X` sur `$(f)`) et le
   pipeline (qui répond pour son dernier maillon). Les deux ont coûté un défaut
   chacune ici. Écrire `x="$(f)" || …` et décider.
2. **La boucle a maintenant un mot pour « le tracker a refusé après un gate
   vert » : `not-marked`.** Il est exempté de `failures_handle` à côté de
   `resolved` et de `not-integrated` (`case "$outcome" in resolved | not-marked |
   not-integrated)`), il émet le reçu, il est demandé par `retro_wanted`, et il ne
   remet pas le compteur de stérilité à zéro. Si [73] a besoin d'un mot pour « le
   snapshot du tracker a refusé », c'est cette liste-là qu'il faut relire — trois
   endroits, plus `receipt__summary`, et aucun n'est déductible des autres.
3. **L'AC 4 de ce ticket (« un backend distant qui refuse le snapshot n'est pas
   rouge à chaque itération ») est exactement la tension que [74] a rencontrée à
   l'autre bout** : le pilote *s'arrête* sur un listing refusé parce qu'un listing
   refusé est reproductible depuis [76] et qu'il n'y a rien à moudre sans
   frontière. Un snapshot refusé n'a pas cette propriété — il reste des tickets à
   moudre — donc la même réponse serait une nuit perdue sur un garde. Ne pas
   recopier la posture, recopier la question : *qu'est-ce que ce refus rend
   impossible, et est-ce que la suite du run a encore un sens sans ça ?*
4. **Une itération dont l'adaptateur refuse une lecture au milieu meurt déjà**
   (`iteration-lost`, ticket rendu à la frontière) : le refus voyage sous `set -e`
   depuis la politique d'échec. Mesuré par [74], sans faux vert au bout. Un
   snapshot/restore qui refuse en plein milieu tombera sur le même chemin.

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

## Note écrite par [77] (livré le 09/09/2026)

Deux précédents à reprendre, tous deux mesurés sur le sidecar :

- **une opération d'interface qui prend le répertoire témoin du run en argument**
  (`tracker_sidecar_witness DIR` / `tracker_sidecar_drift DIR`), rangée dans le
  bras des **lectures** de `tracker__dispatch` : elle n'écrit aucun ticket, donc
  elle n'a rien à faire dans le registre de [13]. Un backend qui ne garde rien de
  ce genre refuse explicitement les trois, plutôt que de ne pas les implémenter —
  sinon le dispatcher imprime « does not implement » sur la console de chaque
  drain ;
- **un adaptateur qui rend `subject<TAB>outcome<TAB>message`** plutôt que
  d'imprimer, et que `forensic_drift` fait voyager sur les deux canaux de [70].
  La phrase est celle de l'adaptateur, parce que lui seul sait ce qu'un de ses
  records décide ; les canaux sont ceux du module, pour qu'une itération n'ait
  qu'une lecture.

Et une contrainte : la remise que [77] livre est **par run** et ne remet rien sur
le disque. Ce que ce ticket-ci ajoute — une restauration du tracker distant — doit
dire ce qu'il fait du sidecar, qui est ce qui décide *qui tient* les tickets
restaurés.

## Contrainte écrite par la passe transversale du 10/09/2026

**Un champ qu'on n'a pas pu lire devient ici une remise qui efface.** La remise
lit cinq champs plus le corps par ticket et par fenêtre ; `tracker_field` rend
**un seul** code non nul pour « ce ticket ne porte pas ce champ » et pour « je
n'ai pas pu savoir », et les vingt-huit sites du pack écrasent les deux en la
chaîne vide (mesuré, `../sondes/passe-10-09/q1-*.bats`, Q1a). Une remise qui lit
un refus comme un champ vide réécrit le ticket avec du vide.

C'est **[82]**, ouvert par la même passe. Si [82] est livré devant, ce ticket
consomme sa clause ; sinon, il doit la porter lui-même pour ses propres lectures
— et le dire.

### [82] est livré (12/09/2026) : ce ticket consomme la clause

Ce qui est disponible, et ce qu'il reste à faire ici :

1. **La clause est sur l'interface**, en tête de `lib/tracker.sh` (« what a
   refusal of a *read* means ») : `0` + valeur — un champ que le ticket ne porte
   pas y compris, qui arrive comme une valeur vide — `1` « il n'y a pas de tel
   ticket », `2` « je n'ai pas pu savoir », et tout autre code non nul lu comme
   `2`. **Les cinq lectures de la remise doivent lire `2` et refuser**, jamais
   réécrire le ticket avec ce qu'elles n'ont pas lu.
2. **Le backend distant a déjà les trois réponses** : `forge__record` rend `2` sur
   un listing refusé et `1` sur une issue absente, et `forge_field`,
   `forge_read_ticket` et `forge__claimed` propagent par `|| return $?`. Rien à
   ajouter côté adaptateur ; tout est côté lecteur.
3. **La forme du lecteur existe** : `router__now` dans `lib/router.sh` — un
   lecteur pour les douze sites d'un fichier dont la réponse est comparée à un
   pin, avec le refus ramené à un seul code. Une remise a exactement la même
   forme de question (*est-ce que c'est ce que ça disait quand la fenêtre s'est
   ouverte ?*), donc un `failures__now` de la même forme est le précédent à
   reprendre plutôt qu'un `2>/dev/null` par champ.
4. **Le piège du corps** : `tracker_read_ticket` refuse aussi, et un digest pris
   sur un refus est un corps qui a changé. `router__ticket_digest` s'était fait
   avoir par un pipeline (`tracker_read_ticket … | cksum`, dont le statut est
   celui de `cksum`) ; une remise qui compare des digests tombera sur le même
   piège.
5. **Ce que [82] n'a pas fermé et qui touche ce ticket** : rien du côté des
   lectures que la remise fera. Les trois résidus nommés par [82]
   (`router__field`, `router_unblocks`, `router_sink`) sont de la présentation et
   du tri, pas de l'écriture.

## Ce que [75] laisse (livré le 12/09/2026)

**Le budget est payé, et il est payé dans un shell précis.** `tracker_cache_prime`
prend **une** lecture du tracker dans le shell de l'appelant, et toutes les
substitutions de commande forkées sous lui sont servies depuis elle. Mesuré sur le
faux forge : un ticket drainé sur un tracker de douze tickets coûte **3** listings
au lieu de **132**. La remise de ce ticket-ci lit cinq champs plus le corps par
ticket et par fenêtre : elle est dans le budget **à condition d'être lancée sous
un shell qui a primé**, pas à condition d'exister.

Quatre choses à reprendre telles quelles :

1. **La lecture vit dans une variable, jamais dans un fichier** — c'est la
   décision de `budget__fetch` un module plus loin, et le magasin que [81] a
   mesuré comme hors de portée d'une session. Si ce ticket veut garder un
   **snapshot** du tracker distant (ce que `failures_protect_tracker` fait avec un
   tree object sur `local`), la question à poser en premier est *où il vit* : un
   fichier de `$TMPDIR` est énumérable par la session jugée (passe du 10/09), et
   un snapshot est exactement l'objet dont le contenu décide d'une **écriture**.
   Le précédent qui marche est la variable + `fork`, pas le fichier.
2. **L'invalidation traverse les process par un registre de longueur.**
   `forge__changed` (appelé par `forge__update` et `forge__create`, les deux seuls
   écrivains d'issue) ajoute une ligne à `tracker.writes`, et une lecture n'est
   servie que tant que la longueur est celle qu'elle portait. Une remise qui
   réécrit des tickets passe donc par là sans rien faire — mais si elle écrit
   **autrement** que par ces deux fonctions, elle doit appeler `forge__changed`
   elle-même, sinon le shell d'à côté lit l'état d'avant sa propre remise.
3. **Le drain a maintenant un répertoire de travail** : `HUMAN_LOOP__STATE`, un
   `mktemp -d` sous `ralph-tracker.*`, pris après les deux verrous et défait par le
   trap de sortie. C'est le logement disponible pour ce que ce ticket voudra garder
   côté drain — et c'est aussi la réponse à la phrase de [77] (« le drain ne prend
   pas de copie ») : il en a un maintenant, mais **rien ne le scelle**, parce que
   le drain ne prend pas de sceau ([81]). Sur le chemin AFK, le même objet vit dans
   le répertoire témoin du run et **est** scellé (`tracker.writes`, mode `grows`).
4. **Une lecture n'est fraîche que par les points de prime.** Le drain prime au
   début, à chaque ticket et **au retour de chaque session** — ce dernier n'est pas
   une optimisation : une session routée peut écrire le tracker par le réseau, ce
   que ni le registre, ni un snapshot, ni un témoin de ce pack ne voit ([18]), et
   c'est exactement la fenêtre que ce ticket doit remettre. Si la remise est
   appelée ailleurs qu'au retour de session, elle prime elle-même ou elle mesure
   contre une lecture qui a jusqu'à `FORGE_CACHE_TTL` secondes de retard.

Et une question que ce ticket hérite sans qu'elle soit à lui : **le chemin AFK ne
prime nulle part**. [75] y pose le registre (donc l'invalidation qui traverse un
fork, qui était fausse avant lui) mais aucun `tracker_cache_prime`, parce que son
AC parle d'un ticket *drainé*. Une remise appelée par `loop.sh` par itération paye
donc encore une lecture par question — le prime est disponible, il n'est pas
câblé.

## Contrainte écrite par la passe transversale du 13/09/2026

La note que [75] avait laissée ici — *« le chemin AFK garde le registre
d'invalidation et AUCUN `tracker_cache_prime` : un run AFK sur backend distant
paie encore une lecture par question »* — a été **mesurée** et est devenue un
ticket à elle seule : **[84]**. Les chiffres, sur le même tracker de douze issues
(`../sondes/passe-13-09/q4-*.bats`) : `loop.sh` demande **93** listings là où le
drain en demande **2**, et couper `FORGE_CACHE_TTL` ne change le premier que de
93 à 96 — la lecture partagée achète **3 %** sur le chemin AFK contre **87 %**
sur le drain.

Deux conséquences pour ce ticket-ci :

- **Si [84] est livré devant**, ce ticket hérite d'une lecture partagée sur le
  chemin AFK, et une restauration du tracker **est une écriture du tracker** :
  elle doit invalider la lecture par le registre de [75], comme n'importe quelle
  autre écriture. Le dire ici est plus sûr que de le déduire au moment de
  l'écrire — c'est exactement la classe de défaut que la question 4 de la
  definition of done cherche.
- **Si [84] est livré derrière**, ce ticket ne doit pas ajouter une lecture de
  plus au chemin AFK sans compter ce qu'elle coûte : une restauration qui relit
  le tracker ticket par ticket est le geste que [75] a retiré du drain.

**File validée par Philippe le 13/09/2026 : [83] → [84] → [85] → [73] → [19].**

### [84] est livré (13/09/2026) — c'est donc la première branche qui s'applique

Le chemin AFK prend maintenant **deux** lectures : une par passe du pilote (en
tête du `while` de `loop_main`, devant `loop__reap`) et une dans **l'itération**
au retour de sa session (`loop__iterate`, avant `failures_protect_tracker`). La
mesure est passée de 93/96 à **23/103** — 78 % au lieu de 3 %.

Ce que ce ticket-ci doit tenir, en clair :

- **Une restauration du tracker est une écriture du tracker.** Si elle passe par
  `forge__update` / `forge__create`, `forge__changed` appende au registre toute
  seule et il n'y a rien à faire. Si elle écrit par un autre chemin, elle doit
  appeler ce qui appende — sinon la lecture que l'itération vient de prendre
  survit à ce que la restauration a remis, pendant ce qu'il reste de
  `FORGE_CACHE_TTL`, et le scope-guard juge contre la write-surface d'avant.
- **Et la restauration tourne au même endroit que le prime n° 2** — juste après la
  session, dans le shell de l'itération. Un `forge__forget` y suffit pour ce
  shell ; ce qui traverse jusqu'aux frères est l'appende au registre, et rien
  d'autre. Un fork ne rend rien au pilote ([83]).
- Le recensement de `test/tracker-remote.bats` (« *an entry point that opens this
  reading and never takes one is refused* ») est dérivé de `"$PACK_DIR"/*.sh` : un
  troisième point d'entrée ajouté par ce ticket doit primer, ou rougir.

## Contrainte écrite par [85] (livré le 13/09/2026)

Ce ticket est le suivant de la file, et [85] lui laisse **un recensement dérivé
de plus** — celui des gardes d'exclusion, dans `test/gate.bats` :

1. **Le plancher est à huit `state_guard_take`.** Si ce ticket ajoute un garde
   côté distant — sérialiser une remise, un sidecar, un snapshot — il ajoute un
   neuvième preneur, et le test exige que son chemin soit couvert par une zone de
   `gate__guard_paths` (ou soit l'un des deux verrous que le point d'entrée tient
   lui-même). C'est voulu : un garde que rien ne recense est un garde que le
   journal du matin ne nomme pas, et le prix est chiffré dans [77]/[81].
2. **La zone des tickets d'un backend distant est vide, et « vide » n'est pas
   « non couvert ».** `gate__guard_paths` marche `tracker_tickets_dir`, qui ne
   répond rien sur `github`/`gitlab`. Le test le distingue explicitement (troisième
   cas, `RALPH_RETRO_STATE` vide). Donc un garde de claim distant ne peut **pas**
   compter sur la marche de cette zone : s'il vit ailleurs, il doit être **demandé
   au module qui le possède**, comme `concurrency_guards` et `retro_guards` le
   font — jamais recomposé dans `gate.sh`.
3. **Un nom en `.guard`/`.lock` composé hors d'un `state_guard_take` rougit
   aussi** (second test). Une remise qui poserait un répertoire témoin nommé
   ainsi sans passer par `state_guard_take` est refusée par le gate.

Et le rappel qui vient de [85] mais vaut pour toute écriture de ce ticket : un
chemin de garde n'est **pas** lisible sur la ligne d'appel, donc la couverture est
résolue **par exécution** — inutile d'essayer de la faire lire à un `grep`.

## Ce qui est livré (14/09/2026)

**La forme retenue : le transport est trois opérations d'adaptateur, la politique
reste entière dans `failures_protect_tracker`.** C'est la sortie n° 2 que [18]
avait nommée (« une opération d'adaptateur snapshot/restore »), découpée de façon
que le backend `local` ne perde rien.

1. **L'interface gagne une cinquième zone** (`lib/tracker.sh`), à côté de
   `receipt_*`, `tickets_dir`, `sidecar_*` et `cache_*` :

   - `snapshot` — le tracker tel qu'il est **maintenant**, sur stdout et **opaque
     à l'appelant** : un tree object ici, un listing là. Non nul = ce backend n'en
     prend aucun.
   - `snapshot_moved SNAP` — ce qui a bougé depuis, un `outcome<TAB>nom` par
     ligne, **trois réponses** (`0` + les enregistrements, `1` « je n'en prends
     pas », `2` « je n'ai pas pu savoir ») — la clause de [82] réutilisée telle
     quelle plutôt qu'un troisième vocabulaire.
   - `snapshot_restore ID SNAP` — un ticket remis à ce que l'instantané porte.
     **L'id en premier** et pas l'instantané : `tracker__dispatch` note `$1` dans
     le registre de [13], donc un instantané passé en premier y aurait écrit un
     listing entier à la place d'un id.

   Les deux premières sont des **lectures** au sens du registre, la troisième est
   une écriture et est notée comme telle.

2. **Quatre mots et pas les statuts d'un backend** : `edited`, `added`, `other`,
   `blind`. Les `A`/`D`/`M` de git, `tracker_local__is_ticket_path` et
   `gate_unaddressable` sont mappés dessus par l'adaptateur local ; ils ne
   traversent plus l'interface. Le distant n'en utilise que deux — une issue n'est
   pas un fichier, il n'y a rien à côté d'un ticket dans ce stockage.

3. **`failures_protect_tracker` ne porte plus une ligne de git.** Elle porte les
   décisions, et elles sont toutes restées : l'exemption par le registre de
   [13]/[42] (avec la clause de [80] — jamais le ticket de l'itération), un ajout
   qui appartient à la quarantaine et pas à la remise, un nom que personne ne peut
   adresser qui coûte le vert, ce qui n'est pas un ticket qui est nommé et laissé,
   le refus de vouloir garder un tracker qu'on n'a pas pu lire ([59]).

4. **Le backend `local` a gardé exactement ses garanties** — et c'est vérifié par
   les 87 tests de `test/failures.bats`, verts sans un seul changement d'assertion
   sauf un : la phrase du garde dit maintenant `restored N ticket(s)` et non
   `N ticket file(s)`, parce qu'une issue n'est pas un fichier.

### Ce que le backend distant fait exactement

- **L'instantané est le listing** (`forge__records`) : une requête rend tous les
  corps, donc le tracker entier est **une** photo. Il vit dans une variable du
  shell de l'itération, jamais dans un fichier — décision de [75]/[81], raison
  de la passe du 10/09 (un fichier de `$TMPDIR` est énumérable par la session
  jugée, et un instantané est exactement l'objet dont le contenu décide d'une
  **écriture**).
- **La comparaison est clé sur le NUMÉRO que la forge a alloué, jamais sur l'id.**
  C'est la réponse à la question transversale que ce ticket portait : un id
  distant est `<numéro>-<slug>` et le slug vient du **corps**, donc une session
  qui réécrit sa propre ligne `Slug:` change d'id sans changer de ticket. Clé sur
  l'id, la même issue se lit comme une disparue **plus** une apparue.
- **L'enregistrement est comparé entier** — corps, état, assigné — parce que les
  trois décident quelque chose. L'assigné est le plus vicieux : `forge__claimed`
  s'y rabat quand cette machine ne tient pas d'enregistrement local, et ce qu'il
  en rend est `foreign` — jamais pingé, jamais repris à vue, hors frontière tant
  que `CLAIM_TTL` le permet.
- **La remise écrit le corps, l'état, et l'assigné dans la seule direction où un
  verbe existe** : un assigné qu'une session a **ajouté** est retiré
  (`forge__unassign`) ; un assigné rendu à un login que ce pack n'a jamais
  tamponné est **refusé** — `forge__assign` n'écrit que `TRACKER_USER`, et une
  remise qui invente est pire que le silence qu'elle remplace (l'argument de
  `router__put_back`, repris et pas réinventé). Un refus est dit
  (`could not restore <id>`) et l'itération n'est pas verte.
- **Aucune écriture inconditionnelle** : une remise qui réécrirait un corps que
  personne n'a touché déplacerait le ticket de sa propre main et coûterait une
  requête par fenêtre sur le chemin ordinaire.

### AC 4, et pourquoi la posture de [18] survit

Un backend qui ne prend **aucun** instantané rend zéro et n'est pas rouge à chaque
fenêtre — refuser à chaque itération échangerait un faux vert contre pas de vert
du tout. Ce qui a changé, c'est **la question** : `forensic_uncovered` demandait
`tracker_tickets_dir` (« ce backend garde-t-il ses tickets dans un répertoire de
ce dépôt ») et dit maintenant la phrase sur `tracker_snapshot` (« ce backend
sait-il photographier son tracker »). Les deux faits étaient le même tant que le
seul transport était git ; ils se sont séparés le jour où une forge a gagné un
instantané. Coût : une photo par run au démarrage — un `git write-tree` en local,
un listing en distant que la lecture de [75] sert pour rien une fois le pilote
amorcé.

### Écarts de write-surface

Le ticket déclarait `.claude/lib/failures.sh`, `.claude/lib/tracker.sh`,
`.claude/lib/tracker-local.sh`, `.claude/lib/forge.sh`, `test/failures.bats`,
`test/tracker-remote.bats`. Quatre fichiers de plus ont été touchés, et chacun
pour une raison qui n'était pas devinable en écrivant la write-surface :

- **`.claude/lib/tracker-github.sh` et `.claude/lib/tracker-gitlab.sh`** — trois
  lignes chacun. Non négociable : le premier test de `test/tracker-remote.bats`
  **dérive** les opérations du dispatcher et exige que les trois backends les
  implémentent, précisément pour que `does not implement` n'atterrisse pas sur la
  console de chaque drain ([77]).
- **`.claude/lib/forensic.sh`** — la question ci-dessus. Laisser la phrase sur
  `tracker_tickets_dir` aurait fait dire au run, une fois par nuit, que rien ne
  restaure un tracker qui est maintenant gardé : un faux témoin.
- **`.claude/loop.sh`** — deux lignes : la prise de l'instantané
  (`tracker_pin="$(tracker_snapshot)"`, ex-`failures_tracker_tree`) et son
  passage au garde. `failures_tracker_tree` a disparu ; garder un alias aurait
  laissé `failures.sh` propriétaire d'un nom de transport qu'elle ne porte plus.

### Ce qui reste ouvert, et qui n'est pas à ce ticket

1. **La fenêtre est celle d'une session.** Ce qu'une session écrit puis remet
   elle-même avant de rendre la main n'est vu par personne — vrai des deux
   backends depuis [21], inchangé.
2. **L'exemption du registre de [13] est indexée par id, et l'id distant porte le
   slug.** Un frère qui écrit un ticket dont la session a changé le slug **dans la
   même fenêtre** n'est pas exempté : sa marque est remise en arrière. Atteignable
   seulement au-dessus de `MAX_PARALLEL=1` et seulement si les deux arrivent dans
   la même fenêtre. La remise nomme l'id **épinglé** (celui que la boucle
   connaissait), ce qui est le bon côté du compromis ; l'autre côté est écrit ici
   et dans le tableau de confiance plutôt que découvert.
3. **Une issue supprimée sur la forge** est rendue comme `edited` et la remise
   refuse : ce backend ne recrée pas une issue que quelqu'un a détruite. Le
   humain lit « could not restore », ce qui est exactement ce qui s'est passé.
