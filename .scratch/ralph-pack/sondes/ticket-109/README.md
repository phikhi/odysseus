# Sondes du ticket [109] — un dépôt-témoin détruit, et la frontière remise quand même

Instruments, pas tests : chaque cas finit par un `false` volontaire pour imprimer
ce qu'il a vu. Lancer avec `bash test/run.sh <fichier> </dev/null`.

La sonde d'ouverture est celle de [100] : `../ticket-100/p2-le-temoin-detruit.bats`
(élargir `.git/info/exclude`, écrire derrière, détruire le témoin d'itération).

| Sonde | Ce qu'elle met en scène | Sur `main` (`ffb5fc7`) | Sur la branche de [109] |
|---|---|---|---|
| `p2` ([100]) | élargir, écrire derrière, **détruire** le pin | exit 4, nuit arrêtée sur `…/attributes is gone` ; **la règle survit** ; seule trace : la ligne de zone de [24] (`nothing in this gate judged 1 ignored path(s): src/backdoor.txt`) | exit 4, même refus nommé ; **la règle ne survit pas** ; le refus du scope-guard porte `moved the ignore frontier in .git/info/exclude … (put back)` |
| `q1` Q1 | deux itérations à `MAX_PARALLEL=1` : la 1re élargit (pin intact), la reprise élargit **et détruit** | exit 4 ; la 2e règle (`src/second.txt`) **survit** ; le refus ne dit rien de la frontière, seule trace la ligne de zone | exit 4, les deux règles remises ; le refus porte les deux findings et **la phrase neuve** (« every movement this run recorded… ») — avant la correction de la phrase : « while more than one iteration was in flight », **faux** à la valeur livrée |
| `q1` Q2 | chemin **crash** (`exit 1`), `.gitignore` suivi par le projet, élargir, détruire | exit 4 ; la règle **survit** et la nuit ne dit **rien** de la frontière — pas même la ligne de zone | exit 4, `01-alpha: moved the ignore frontier in .git/info/exclude … (put back)`, **aucune** règle d'arbre nommée, règle remise |
| `q1` Q3 | pin détruit **et** manifeste du témoin du run remis au digest courant | exit 4, la nuit nomme `ralph-frontier.*/manifest` ; la règle survit | exit 4, la nuit nomme `ralph-frontier.*/manifest is rewritten` et `…/attributes is gone` ; **rien n'est remis, rien n'est prétendu** ; la règle survit (aveu écrit, le même que pour « deux témoins réécrits ») |
| `q1` Q6 | pin **et** témoin du run **détruits** | exit 4, la nuit nomme chaque témoin du run disparu ; la règle survit, seule trace la ligne de zone | identique à `main` : rien ne se porte garant d'une cible, rien n'est remis ni prétendu (aveu écrit, comme Q3) |
| `q4` Q4 | clé `cfg` du dépôt (`diff.evil.textconv`), `.git/info/attributes` et `exclude`, pin détruit | exit 4 ; les **trois** survivent (`exclude`, `* diff=evil`, `diff.evil.textconv=cat`) | exit 4, les **trois** remises et nommées dans le refus |
| `q4` Q5 | `MAX_PARALLEL=2`, une session élargit et détruit **tous** les pins | exit 4 ; la règle survit ; aucune ligne de frontière dans les deux refus | exit 4, remis ; `02-beta` (marque perdue aussi) reçoit la phrase neuve — vraie là aussi : rien ne dit si le mouvement est venu pendant son vol |

Ce que ces sondes ont appris :

- La remise avait déjà tout ce qu'il lui fallait depuis [100] (`gate__frontier_pinned_manifest`,
  `gate__frontier_held_copy`) : seule la ligne `[ -f "$pin/manifest" ] || return 1` de
  `gate_frontier_moved` l'empêchait de servir.
- Remettre en silence enlevait la seule trace qu'avait la nuit arrêtée : la ligne de zone de [24]
  ne nommait `src/backdoor.txt` que parce que la règle était encore en place. Le refus du
  scope-guard porte donc les findings de frontière, comme le chemin « rien de livré ».
- Les imprimer a fait voir une phrase fausse cachée jusque-là derrière le refus : la marque d'un
  témoin détruit se lit comme le début du run (prix de [100]), et la reprise se faisait dire
  « while more than one iteration was in flight » à propos de sa propre première tentative.
