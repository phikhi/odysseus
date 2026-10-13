# Sondes du ticket [100] — le dépôt-témoin des règles, tenu par son contenu

Instruments, pas tests : chaque cas finit par un `false` volontaire pour imprimer
ce qu'il a vu. Lancer avec `bash test/run.sh <fichier> </dev/null`.

La sonde d'ouverture est celle de la passe du 29/09 :
`../passe-29-09/q5-le-temoin-des-regles-recrit.bats`.

| Sonde | Ce qu'elle met en scène | Sur `main` (`93888fe`) | Sur la branche de [100] |
|---|---|---|---|
| `q5` (passe 29/09) Q5a | la session élargit le `.git/info/exclude` partagé et écrit derrière ; témoin intact | rouge, remis, retry, `resolved`, exit 0, règle **ne survit pas** | identique |
| `q5` Q5b | le même geste, plus la règle dans la copie du témoin et la ligne du manifeste remise au digest courant | **quatre verts, une itération, `resolved`, exit 0, la règle survit au run** | exit **4**, `…/manifest is rewritten`, ticket rendu, la règle **ne survit pas** (remise depuis le témoin du run) |
| `p1` P1a | la session élargit, rien d'autre | rouge, remis, retry, `resolved` | identique |
| `p1` P1b | la même session porte `ledger-seen` à la longueur que le registre aura après la remise | **un vert, une itération, aucun finding** — le mouvement est remis, personne n'est facturé | exit **4**, `…/ledger-seen is rewritten` |
| `p2` | élargir, écrire derrière, **détruire** le témoin | exit 4, nuit arrêtée — et **la règle survit** à la nuit arrêtée | identique, la ligne de refus nomme maintenant l'entrée disparue (`…/attributes is gone`) → **[109]** |

Ce que `p1` a appris : l'argument de [83] (« rien du pack n'écrit là pendant
qu'une session tourne ») ne valait pas pour le témoin d'itération — le partage du
registre y réécrivait sa marque à chaque lecture. Ce que `p2` a appris : le
contrôle d'existence ferme bien le contrôle, mais rien ne remet la frontière sur
ce chemin ; hors du périmètre de [100], ouvert en [109].
