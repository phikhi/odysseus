# 73 — Rien ne restaure le tracker d'un backend distant

**What to build:** Une protection du tracker qui ne suppose pas que les tickets sont des fichiers de cet arbre — soit une opération d'adaptateur snapshot/restore, soit un refus qui ne coûte pas la nuit.

**Blocked by:** None

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
