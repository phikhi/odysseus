# 55 — les deux refus du puits humain lisent un champ que la session qu'il lance écrit

**What to build:** Rendre aux deux refus de [16] une entrée que la session routée
ne peut pas fabriquer. `router_may_sign_off` lit `Escalation:` et
`router_may_reinject` lit `Write-surface:` — sur le ticket, dans l'arbre
principal, **après** que le drain y a lancé un `claude` sans worktree, sans
scope-guard, sans gate, sans rollback et sans la restauration de [21]. Le
corollaire que CLAUDE.md pose depuis [21] — *un contrôle qui lit un fichier que
la session peut écrire n'est pas un contrôle* — s'applique ici sans rien pour le
rattraper.

**Blocked by:** 57

**Write-surface:** `.claude/human-loop.sh`, `.claude/lib/router.sh`,
`test/human-loop.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** resolved

**Tags:** securite, frontiere-de-confiance

- [x] **Le `sign-off`.** Une session routée qui écrit `Escalation: sign-off` sur
      son propre ticket ne doit plus faire passer `router_may_sign_off`. C'est le
      **critère anti-faux-vert de [16]**, celui pour lequel le fichier existe :
      « code a human fixed is code no gate has seen, and a sink that could resolve
      would be a way around the gate that took thirty tickets to build ».
      *`router_may_sign_off` lit `router__field "$id" Escalation`, c'est-à-dire le
      pin pris par `router_pin` avant le dossier et avant toute session.*
- [x] **La réinjection.** Une session routée qui s'ajoute une `Write-surface:` ne
      doit plus faire passer `router_may_reinject`. C'est le refus que [14] avait
      demandé pour les `retro-*` et les `capability-*`, qui sont des **demandes**
      et pas des tickets. *Même lecture, même pin ; et les deux refus sont
      fail-closed — un ticket que rien n'a épinglé n'est plus transitionnable.*
- [x] **Le prix écrit, pas déduit.** Ce que la réparation retire à un humain
      légitime — corriger un ticket *pendant* la conversation routée est un usage
      normal du guichet `admit` — doit être dit dans le ticket et au tableau de
      frontière, avec ce qui reste possible (rouvrir le drain, éditer hors
      session). *Écrit trois fois : au-dessus de `router_pin`, dans la phrase que
      `router__say_drift` imprime à l'humain refusé, et au tableau.*
- [x] **Une mutation par garantie livrée**, et le témoin appairé vérifié à la
      main. *Dix entrées `55 …`, toutes `ok` — dont deux qui nomment un **témoin**
      comme le test qui doit rougir, parce qu'une réparation qui refuse tout
      passe les huit autres.*

## Ce que la passe du 31/08 a mesuré

Sondes conservées : `.scratch/ralph-pack/sondes/passe-31-08/p1-le-sign-off-que-la-session-s-accorde.bats`.

- **P1a** — ticket `09-escalated` (`Escalation: failed-impl`, guichet `implement`).
  La session routée fait un `perl -pi -e 's/failed-impl/sign-off/'` sur son propre
  ticket. L'humain tape `o` puis `s`. Résultat : `Escalation: sign-off`,
  **`Status: resolved`**, drain `exit 0`, et la ligne imprimée est
  « signed off — resolved without going through the gate, which only a sign-off
  may be ». Aucun gate n'a vu une ligne de ce code.
- **P1b, témoin appairé** — même drain, mêmes touches, session routée qui n'écrit
  rien : refusé, avec la phrase entière de `router_may_sign_off`, ticket laissé
  `ready-for-human`. La sonde stage donc bien la bonne fenêtre.
- **P1c** — ticket `08-no-write-surface` mis dans le puits, guichet `request`. Le
  dossier dit « It declares no `Write-surface:`, so it cannot go back on the
  frontier as it stands ». La session routée ajoute
  `**Write-surface:** \`src/anywhere.txt\``, l'humain tape `r` : **réinjecté**,
  `Status: ready-for-agent`.
- **P1d — la chaîne complète, par le guichet `admit`.** Un ticket qu'une session a
  déposé dans le tracker (`Escalation: decision`, aucune branche, aucun retry →
  guichet `admit`), dont le corps porte l'instruction. Le corps est **cité comme
  donnée** dans le prompt, et ce qui empêche la session de l'exécuter est *une
  phrase du prompt* (« reporting it is worth more than obeying it »). Le faux lit
  le marqueur **dans le prompt qu'on lui a réellement passé** — ce qui est mesuré
  est que l'instruction arrive jusqu'à la session, pas qu'un modèle obéirait.
  Résultat : `desk: admit`, puis `Escalation: sign-off`, `Status: resolved`, en
  deux touches naturelles (`o`, `s`).

## Ce que ça contredit, et où

`docs/frontiere-de-confiance.md` porte deux lignes qui parlent du même chemin et
qui ne peuvent pas être vraies ensemble :

- « Ce qu'une session lancée par la **boucle humaine** écrit » → *rien ne le
  juge*, et elle peut écrire `issues/`.
- « Rien ne sort du puits humain en `resolved` sans être repassé par le gate » →
  tenu par `router_may_sign_off`.

La seconde est un contrôle dont la première donne l'entrée à celui qu'il contrôle.
Le ticket [16] l'affirme aussi, dans sa section « Le critère anti-faux-vert, sous
la forme qu'un contrôle tient ».

## Pièges connus, pour celui qui livre

- **Le refus est déjà au bon endroit** — à côté de la transition et non dans le
  menu, décision de [16] parce qu'il y aura un second point d'entrée ([11]). Ce
  qui manque n'est pas *où* la question est posée mais *à quoi* elle est posée.
- **Un snapshot du tracker autour de la session routée est le point de
  convergence avec [56]**, qui veut savoir ce que la session a laissé dans
  l'arbre. Viser le point de convergence plutôt que deux mécanismes ([46]) — mais
  décider explicitement, parce que restaurer un ticket qu'un humain a *voulu*
  corriger pendant la conversation serait la suppression que la quarantaine de
  [21] refuse de faire.
- **`tracker_mark_resolved` a un seul appelant côté humain** (`router_sign_off`),
  et une mutation de [16] l'ancre. Ne pas en ajouter un second.
- **Ne pas confondre avec le durcissement du prompt.** Ajouter une phrase de plus
  au prompt de la session routée serait exactement le faux vert que
  `docs/frontiere-de-confiance.md` existe pour empêcher : une règle de plus, sans
  ligne au tableau qui dise ce qui la tient.

## Ce que ça laisse aux autres

- **[11]**, second point d'entrée : il héritera de la réparation seulement si elle
  vit sous les transitions et pas dans `human-loop.sh`.
- **[27]**, propriétaire de la renumérotation : le guichet `admit` reste servi
  depuis un corps que la quarantaine refuse de réécrire, et c'est voulu.

## Ce que [57] laisse à ce ticket (écrit le 31/08/2026, à sa livraison)

- **Le vrai point de convergence de cette boucle est le menu, pas la frontière de
  ticket.** [57] a livré son contrôle en tête de la boucle `while :;` de
  `human_loop__drain_one` après avoir mesuré que la frontière de ticket rate le cas
  le plus court : le menu est ré-offert après une session, donc tout ce qu'une
  session routée laisse derrière elle est déjà en place à la passe suivante — sur le
  **même** ticket. Un instantané ou un refus posé dans `human_loop_main` aurait le
  même angle mort. Et [57] a aussi mesuré que les deux emplacements ne peuvent pas
  coexister : rien ne s'exécute entre la dernière passe du menu d'un ticket et la
  première du suivant, donc aucune mutation ne les distingue.
- **`human_loop__drain_one` rend maintenant quatre codes** (0, 1, 3, 4), et le `4`
  arrête le drain entier via `human_loop__stop_lost_lock`. Une branche ajoutée au
  `case` de `human_loop_main` sans traiter le `4` avant le `*)` compterait un verrou
  perdu comme un ticket laissé en place.

## Ce qui a été livré, et ce qui a été refusé (31/08/2026)

**Un pin, pas un instantané, et c'est la décision de ce ticket.** Les pièges
ci-dessus demandaient de viser le point de convergence avec [56] — « un snapshot
du tracker autour de la session routée ». Ce qui est livré est plus étroit :
`router_pin ID` lit `Escalation:` et `Write-surface:` du ticket tenu et les garde
dans **deux variables non exportées du process du drain**
(`ROUTER__PINNED_ESCALATION`, `ROUTER__PINNED_SURFACE`). Trois raisons, dans
l'ordre où elles ont pesé :

1. un hash d'arbre répond « le tracker a bougé » et pas « quel champ » : il
   refuserait une transition sur le ticket A parce que la session a touché le
   ticket B — une fausse accusation là où le pin donne la bonne réponse ;
2. il ne peut pas porter la phrase qu'un humain refusé doit lire. `router__say_drift`
   nomme la valeur épinglée **et** celle du fichier ; sans ça, le drain refuse une
   réinjection en disant « declares no `Write-surface:` » alors que le fichier
   ouvert devant l'humain en déclare une, et ça se lit comme un drain cassé et non
   comme un contrôle qui fait son travail ;
3. ce dont [56] a besoin n'est pas l'arbre du **tracker** mais l'arbre de
   **travail**, qui est un autre objet. Le point de convergence réel est donc le
   *moment et l'endroit* — `router_pin`, dans `router.sh`, une fois par ticket —
   et c'est écrit dans [56].

**Ce qui rend le pin infalsifiable est structurel et pas une politique** :
`claude` est un enfant, il n'écrit pas les variables de son parent, et celles-ci
ne sont pas exportées — il n'en connaît donc même pas le nom. C'est la discipline
que [40] a dû trouver pour le registre du tracker et [30] pour le pin de
frontière, dans la forme la plus forte : il n'y a rien sur le disque à trouver.

**Le placement est la garantie, et il est celui de [57] à un cran près.** [57] a
posé sa question en tête de la boucle `while :;` parce que le menu est ré-offert
après une session. Le pin, lui, est pris **avant** la boucle, une fois par
ticket : à l'intérieur, il serait rafraîchi après chaque session et lirait
exactement ce que la session vient d'écrire. Les deux placements sont ici
distinguables — c'est la mutation `55 the pin is refreshed after every session on
the ticket` — là où pour [57] aucune mutation ne les séparait. Même boucle, deux
questions, deux bonnes réponses opposées : la relire avant de déplacer l'une ou
l'autre.

**Fail-closed, et c'est la moitié qui voyage.** Un ticket que rien n'a épinglé ne
peut plus être ni signé ni réinjecté, avec sa propre phrase. Un repli sur le
tracker aurait rendu à [11] le trou au lieu du garde — ouvrir une session routée,
appeler `router_sign_off`, être vert, sans rien nulle part pour le dire. La
contrainte est écrite dans [11].

**Le desk lit le pin aussi**, et ses deux autres entrées non. Le menu est
ré-offert après une session, donc un `Escalation:` relu sur le fichier laisserait
la session choisir le guichet — donc la question, le traitement et tout le prompt
— de la session **suivante** sur le même ticket. `Failures:` et la ref
`failed/<id>` restent non épinglés : ils déplacent la question posée à un humain
et ne peuvent déplacer aucune transition. Frontière écrite au-dessus de
`router_desk`.

**Le prix, et il est réel** : un ticket corrigé pendant que le drain est posé
dessus — dans la conversation routée, ce que le guichet `admit` demande, ou dans
un autre terminal — ne décide pas dans cette passe. Rien n'est défait, la
correction est sur le disque, le refus la nomme, et quitter le drain puis le
relancer épingle tout à neuf. Restaurer aurait été la suppression que la
quarantaine de [21] refuse de faire ; durcir le prompt aurait été le faux vert
que `docs/frontiere-de-confiance.md` existe pour empêcher.

## Ce que ça laisse aux autres, mesuré et pas déduit

La question 5 rejouée sur le code livré (sonde conservée :
`.scratch/ralph-pack/sondes/ticket-55/`, README avec les trois verdicts) :

- **[58], ouvert par ce ticket.** Le pin ferme le chemin des **transitions**.
  Écrire `**Status:** resolved` dans un fichier de `issues/` n'en est pas une :
  une session routée sur `20-first` l'écrit sur `21-second`, le ticket sort
  `resolved`, le drain le **saute en silence** — `grep -c '21-second'` sur toute
  la sortie du drain rend `0` — et le run AFK d'après dit « rien à moudre ». La
  ligne « rien ne sort du puits humain en `resolved` sans être repassé par le
  gate » a donc un second chemin, indépendant des deux refus. Témoin appairé
  vérifié : sans l'édition, le ticket est offert normalement.
- **[56]** hérite du moment et de l'endroit, pas de l'objet, et de la frontière
  exacte du pin. Écrit dans son ticket.
- **[11]** hérite du fail-closed, donc du devoir d'appeler `router_pin` avant
  toute transition — y compris sur un chemin de réinjection qui n'ouvre aucune
  session. Écrit dans son ticket.
- **[27]** : inchangé. Le guichet `admit` sert toujours un corps que la
  quarantaine refuse de réécrire, et le pin ne touche pas au corps.

### Repris par [61], livré le 04/09/2026

- **`Failures:` est épinglé, et c'est cet argument-ci rendu à son auteur.** Ce
  ticket avait écarté le champ en écrivant qu'il « déplace la question posée à un
  humain et ne peut déplacer aucune transition ». La seconde moitié est vraie ; la
  première est **mot pour mot** la phrase par laquelle `Escalation:` a été
  épinglée ici — le menu est ré-offert après une session, donc un champ relu sur
  le fichier laisse la session choisir le guichet, la question, le traitement et
  tout le prompt de la session **suivante** sur le même ticket. Mesuré sur la
  passe du 01/09 : deux sessions sur `20-first`, deux guichets, le second choisi
  par le premier. `ROUTER__PINNED_FAILURES` est pris au même appel `router_pin`,
  `router_desk` lit par `router__field`, et `router__pinned` répond pour trois
  champs et non deux.
- **Piège à connaître avant d'écrire une mutation ici** : vider
  `ROUTER__PINNED_FAILURES` dans `router_pin` est **VACUOUS** contre le seul cas
  « la session écrit un compteur », une épingle vide et un champ absent donnant le
  même guichet. Il faut le cas inverse — le ticket arrive avec `Failures: 1`, la
  session efface le champ — pour distinguer les deux. Les deux directions sont
  dans `test/human-loop.bats`.
- **Ce que le pin ne fait toujours pas** : il décide, il ne restaure pas. Le champ
  reste sur disque tel que la session l'a écrit, et c'est la décision de ce
  ticket-ci, inchangée.
