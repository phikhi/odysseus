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

**Status:** ready-for-agent

**Tags:** securite, frontiere-de-confiance

- [ ] **Le `sign-off`.** Une session routée qui écrit `Escalation: sign-off` sur
      son propre ticket ne doit plus faire passer `router_may_sign_off`. C'est le
      **critère anti-faux-vert de [16]**, celui pour lequel le fichier existe :
      « code a human fixed is code no gate has seen, and a sink that could resolve
      would be a way around the gate that took thirty tickets to build ».
- [ ] **La réinjection.** Une session routée qui s'ajoute une `Write-surface:` ne
      doit plus faire passer `router_may_reinject`. C'est le refus que [14] avait
      demandé pour les `retro-*` et les `capability-*`, qui sont des **demandes**
      et pas des tickets.
- [ ] **Le prix écrit, pas déduit.** Ce que la réparation retire à un humain
      légitime — corriger un ticket *pendant* la conversation routée est un usage
      normal du guichet `admit` — doit être dit dans le ticket et au tableau de
      frontière, avec ce qui reste possible (rouvrir le drain, éditer hors
      session).
- [ ] **Une mutation par garantie livrée**, et le témoin appairé vérifié à la
      main.

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
