# 73 — Rien ne restaure le tracker d'un backend distant

**What to build:** Une protection du tracker qui ne suppose pas que les tickets sont des fichiers de cet arbre — soit une opération d'adaptateur snapshot/restore, soit un refus qui ne coûte pas la nuit.

**Blocked by:** 74, 75, 77

**Write-surface:** `.claude/lib/failures.sh`, `.claude/lib/tracker.sh`, `.claude/lib/tracker-local.sh`, `.claude/lib/forge.sh`, `test/failures.bats`, `test/tracker-remote.bats`

**Status:** ready-for-agent

- [ ] Ce qu'une session écrit dans un tracker distant est **remis** ou **refusé**, jamais avalé — et la ligne du tableau de confiance dit laquelle des deux.
- [ ] `failures_protect_tracker` cesse d'être écrit contre un tree object de git : le transport est demandé à l'adaptateur, comme le chemin l'est déjà (`tracker_tickets_dir`).
- [ ] Le backend `local` garde **exactement** ses garanties actuelles — les trois statuts `A`/`D`/`M`, l'exemption par le registre de [13]/[42], `failures__is_ticket_path`, le refus de vouloir garder un arbre qu'il n'a pas pu lire ([59]).
- [ ] Un backend distant qui refuse le snapshot n'est pas rouge à chaque itération.

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

### [82] est livré (11/09/2026) : ce ticket consomme la clause

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
