# 74 — La boucle avale les refus de l'adaptateur

**What to build:** Faire lire à `loop.sh` les deux refus de l'adaptateur qu'il jette aujourd'hui — celui de `tracker_mark_resolved` et celui de `tracker_frontier` — sans que la boucle apprenne quoi que ce soit d'un backend.

**Blocked by:** None

**Write-surface:** `.claude/loop.sh`, `.claude/lib/select.sh`, `test/loop-happy-path.bats`, `test/tracker-remote.bats`

**Status:** ready-for-agent

- [ ] Un `tracker_mark_resolved` refusé ne produit pas une ligne de journal `resolved`.
- [ ] Une frontière que l'adaptateur a **refusé** de lire ne déclenche pas le gate de valeur terminal.
- [ ] Aucune des deux corrections n'apprend à la boucle ce qu'est un backend : ce sont deux codes de retour de l'interface, lus.
- [ ] Le chemin `local` garde exactement le comportement qu'il a aujourd'hui, `run.log` compris.

## Comments

- **Ouvert par [18], livré le 08/09/2026 : deux endroits, une seule forme.** La
  boucle lit l'interface de l'adaptateur à travers des constructions qui **jettent
  un statut**, et ça ne s'était jamais vu parce que le seul backend qui existait ne
  refusait presque jamais.

  1. **`tracker_mark_resolved`.** `loop.sh` l'appelle et pose `outcome=resolved`
     derrière, sans lire son code. Sur un backend distant avec `WAIT_CI` — le
     défaut — un pipeline rouge fait escalader le ticket par l'adaptateur, qui rend
     non zéro : le tracker dit `ready-for-human` et **`run.log` dit `resolved`**.
     Le tracker a raison ; la ligne de journal enregistre le verdict du gate de ce
     run, et le verdict de la forge arrive après lui. C'est vrai, et c'est illisible
     pour un humain au matin.
  2. **`tracker_frontier`.** `loop__next_ticket` lit `select_frontier` dans une
     substitution de commande en heredoc, qui avale le statut. Un listing refusé —
     une coupure réseau, un jeton expiré — arrive donc au pilote comme une
     **frontière vide**, et une frontière vide est ce qui déclenche le gate de
     valeur terminal, c'est-à-dire une session qui peut fermer la feature. C'est la
     règle de [59] à l'endroit où elle coûte le plus cher, et `select_next_ticket`
     — qui, lui, lit le statut — n'est appelé par personne dans le pack.

- **Pourquoi [18] ne les a pas prises** : son AC 1 dit « la boucle reste agnostique
  (aucun changement de control-flow) », ce qui est la bonne contrainte pour un
  ticket qui ajoute deux backends et la mauvaise pour ces deux lignes-là. Ce que
  [18] a fait de son côté de l'interface : les deux opérations **refusent
  correctement** (code de retour, jamais une sortie de shell, [71]), et
  `forge__api` redemande une lecture avant d'abandonner — trois essais — de sorte
  qu'un aléa réseau ne soit pas une nuit. Le reste est ici.

- **Le piège, mesuré en écrivant [18]** : `outcome` n'est pas une chaîne de
  journal, c'est ce que lisent la politique d'échec, le reçu et le compteur de
  stérilité. Une valeur de plus (`not-marked`, ou autre) touche ces trois-là, et
  `resolved` est la seule valeur que [35] autorise à sortir un ticket de la
  frontière. La sortie la moins chère est probablement de ne pas inventer d'issue :
  lire le refus, journaliser ce que le tracker dit **vraiment** après l'appel, et
  laisser la politique d'échec en dehors.
