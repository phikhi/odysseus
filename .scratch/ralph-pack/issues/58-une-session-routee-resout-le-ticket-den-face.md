# 58 — une session routée résout le ticket d'en face, et le drain le saute en silence

**What to build:** Fermer le second chemin de la ligne « rien ne sort du puits
humain en `resolved` sans être repassé par le gate ». [55] a rendu aux deux
refus une entrée que la session routée ne peut pas fabriquer — mais les deux
refus gardent des **transitions**, et écrire `**Status:** resolved` dans un
fichier de `issues/` n'en est pas une. Une session routée sur `20-first` écrit
sur `21-second` : le ticket quitte le puits **et** la frontière, aucun gate n'a
rien lu, et le drain le saute sans qu'une seule ligne le nomme.

**Blocked by:** 56

**Write-surface:** `.claude/human-loop.sh`, `.claude/lib/router.sh`,
`test/human-loop.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

**Tags:** securite, frontiere-de-confiance

- [ ] **Un `Status:` terminal écrit par une session routée ne vaut pas une
      livraison.** Trancher explicitement entre restaurer (le mécanisme de [21],
      qui est ce que le pack fait partout ailleurs) et refuser/annoncer, et
      écrire le prix : restaurer un ticket qu'un humain a *voulu* corriger
      pendant la conversation est la suppression que la quarantaine refuse de
      faire — mais l'argument de [55] pour ne pas restaurer portait sur **le
      ticket que le drain tient**, pas sur ses voisins, et la différence est
      exactement ce que ce ticket a à décider.
- [ ] **Le saut cesse d'être muet.** `human_loop_main` relit `Status:` avant
      chaque ticket et `continue` en silence — décision de [16], pour ne pas
      perdre bruyamment contre un humain à deux terminaux. Un ticket qui a changé
      d'état *pendant ce drain* n'est pas ce cas-là : il est sauté sans qu'aucune
      ligne, ni à l'écran ni au journal, ne le nomme.
- [ ] **Ce qui reste hors de portée est dit.** Le pin de [55] couvre deux champs
      d'un ticket ; ce ticket-ci couvre `Status:` ; `Failures:`, `Blocked by:` et
      le corps restent écrits par une session que rien ne juge. Dire qui garde
      quoi, ou avouer que personne.
- [ ] **Une mutation par garantie livrée**, témoin appairé vérifié à la main.

## Ce que [55] a mesuré, à sa livraison (31/08/2026)

Sonde conservée : `.scratch/ralph-pack/sondes/ticket-55/s1-le-ticket-voisin-que-la-session-resout.bats`,
rejouée sur le code livré de [55].

- **S1** — deux tickets dans le puits. La session routée sur `20-first` fait
  `perl -pi -e 's/^\*\*Status:\*\* .*$/**Status:** resolved/'` sur
  `21-second.md`. L'humain tape `o`, `n`, `n`. Résultat : `21-second` sort
  **`resolved`**, et `grep -c '21-second'` sur **toute** la sortie du drain rend
  **0** — pas de dossier, pas de ligne de journal, rien.
- **S1b, témoin appairé** — même drain, mêmes touches, session qui n'écrit rien :
  `21-second` est offert, `ready-for-human`.
- **S1c** — le run AFK lancé derrière sort **`exit 5`**, « rien à moudre ». Le
  ticket a quitté la frontière comme un ticket livré.

## Pourquoi ce n'est pas [55]

[55] ferme le chemin des **transitions** : `router_may_sign_off` et
`router_may_reinject` décident maintenant sur le pin — les champs du ticket tels
que le drain les a pris — et un ticket que rien n'a épinglé ne peut plus être
transitionné du tout. Le chemin d'ici ne passe par aucune des deux : la session
écrit l'état terminal elle-même, et le drain n'est même pas dans la boucle.

## Point de convergence

**L'instantané autour de `human_loop__session`**, que [56] posera pour l'arbre et
que [55] a délibérément choisi de ne pas poser pour le tracker (son pin est deux
variables du process, pas un instantané — les trois raisons sont écrites dans son
ticket). Les trois tickets veulent la même fenêtre ; la
poser une fois est la consigne de [46]. Et [57] a mesuré où elle est : en tête de
la boucle `while :;` de `human_loop__drain_one`, pas à la frontière de ticket —
le menu est ré-offert après une session, donc c'est le seul endroit qui voit *le
retour* d'une session.

## Pièges connus, pour celui qui livre

- **`failures_protect_tracker` ne se rappelle pas tel quel.** Il restaure depuis
  un tree git, exclut ce que la boucle a écrit via le registre de [13] — que ce
  drain n'alimente pas, écrivant `issues/` hors de toute itération — et rend son
  verdict à un appelant qui en fait un échec d'itération. Lire [49] avant : tout
  ce qui bouge sous `issues/` n'est pas un ticket.
- **Le ticket que le drain tient est un cas à part**, et c'est la décision de
  [55] : l'humain a le droit de le corriger pendant la conversation, le pin fait
  seulement que la correction ne décide pas *dans cette passe*. Restaurer celui-là
  serait un changement de politique, pas une réparation.
- **Ne pas confondre avec le durcissement du prompt** — même avertissement que
  [55] : une phrase de plus au prompt de la session routée est un faux vert en
  attente, pas une garantie.
