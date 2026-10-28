# Sondes du tri de [97], 28/10/2026

Des **instruments**, pas des tests. Chaque cas finit par un `set -e; false`
volontaire : il rougit toujours, et ce qu'on lit est ce qu'il imprime avant.
Hors de `test/`, jamais compté par les deux gates. Rien touché hors `.scratch/` :
la baseline de [109] tient (`run.sh` 1128/0/7 skips, `mutate.sh` 1232/0).

    bash test/run.sh .scratch/ralph-pack/sondes/triage-97/q1-le-verdict-dune-lentille.bats </dev/null

Environ 40 s par cas, sur `main` à `0e8390d`.

## `q1-le-verdict-dune-lentille.bats` → AC 1 et AC 6 de [97]

Personne n'avait mis en scène le **verdict** d'une lentille sur le code
d'aujourd'hui : la passe du 23/09 (q1) a mesuré la posture tirée du même flux,
celle du 29/09 le gate de valeur (q2) et le rétro (q3), et le test du canari
n'est qu'un `skip` sans corps. Le survivant n'efface rien : tant que la dernière
occurrence de `RALPH-LENS-VERDICT:` n'est pas `pass`, il en **ajoute** une, nue.

| | Mesuré |
|---|---|
| **Q1a** témoin appairé — lentille `fail`, aucun survivant | `standards=red` trois fois, `escalated to the human sink (failed-impl)`, `sterile run`, ticket `ready-for-human` `Failures: 3`, exit **4** |
| **Q1b** la même lentille `fail`, un survivant ajoute une ligne | le survivant a vu 1 flux et écrit 2 fois ; `tests=green typecheck=green scope=green lang=green standards=green`, `iteration 1: 01-plain -> resolved`, exit **0**, **aucune ligne du run** ne nomme une forge |

## Rejeux de la passe du 29/09, même jour, même `main`

- `../passe-29-09/q2-le-verdict-du-gate-de-valeur.bats` : Q2a `fail` et ticket
  de recâblage ; Q2b exit 0, `**Verdict:** pass`, *« the feature closes »*,
  aucun ticket de recâblage (survivant : 1 flux, 22 écritures). **Inchangé.**
- `../passe-29-09/q3-le-flux-du-retro.bats` : Q3a leçon honnête ; Q3b
  `FORGED never judge a write-surface, the gate is advisory` dans `LEARNINGS.md`,
  le record durable, et `02-retro-forged-disable-the-scope-guard-…`
  `ready-for-human` (survivant : 1 flux, 54 écritures). **Inchangé.**
