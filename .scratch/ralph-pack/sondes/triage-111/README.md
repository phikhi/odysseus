# Sondes du tri de [111], 29/10/2026

Des **instruments**, pas des tests. Chaque cas finit par un `set -e; false`
volontaire : il rougit toujours, et ce qu'on lit est ce qu'il imprime avant.
Hors de `test/`, jamais compté par les deux gates. Rien touché hors `.scratch/` :
la baseline de [97] tient (`run.sh` 1145/0/6 skips, `mutate.sh` 1246/0).

    bash test/run.sh .scratch/ralph-pack/sondes/triage-111/q1-ce-que-lisent-les-juges.bats </dev/null

Environ 12 s par cas, sur `main` à `7c25302`.

Le survivant est planté par la première session de livraison, ignore `TERM`, et
**ajoute** une ligne à chaque cible **tant que sa marque manque** (le pack — ou la
commande du projet, qui écrit à son propre offset — écrase un ajout fait avant la
fin de son écriture). Une marque par cible. Le faux `claude` ne suit aucune
instruction : on lit ce qu'il a **reçu** (`claude.calls/<n>/stdin`) et ce que le
pack a **écrit** ensuite. Les appels 1 et 2 sont la même session de livraison (le
script du survivant se relance en `exec claude`).

## Q1 — le gate de valeur, avec des commandes de projet qui écrivent

`stub-cmd run` / `stub-cmd visual` impriment deux et une ligne. Le survivant vise
`run.out`, `visual.out`, le prompt, et la copie de la spec (`ralph-spec.*`)
**seulement une fois `run.out` non vide** — c'est-à-dire après la vérification de
[81] (`gate_witness_intact`), qui précède le lancement des commandes.

| Cible | Dans le prompt reçu par le juge | Dans `docs/playthroughs/<f>.md` |
|---|---|---|
| prompt (`ralph-playthrough.*/prompt`) | **oui** | — |
| `run.out` | **oui** | **oui**, sous *« this loop ran them, no model did »* |
| `visual.out` | **oui** | **oui**, idem |
| copie de la spec, après sa vérification | **oui** | non (le document ne recopie pas la spec) |

Run sorti `0`, `**Verdict:** pass`, aucune ligne sur un témoin. La spec : la
vérification et la lecture sont deux instants séparés par `RUN_CMD` et
`VISUAL_CMD` — jusqu'à deux `GATE_TIMEOUT`, et un `RUN_CMD` est un serveur qui va
au bout du sien. Ici les commandes sont instantanées et la fenêtre a quand même
suffi. Les transcriptions sont relues **après** la session pour le document : la
fenêtre de `run.out` court de la fin de `RUN_CMD` à l'écriture du document, la
session du juge comprise.

## Q2 — hors du critère du ticket : la livraison suivante et l'index des leçons

Deux tickets, `RETRO=on`, le rétro répond une leçon. Le survivant vise
`.scratch/*/.session.*.jsonl.prompt` et `ralph-retro.*/index` (une entrée
`- LR-0999 x1 … — FORGED-INDEX …` sous `## Working set`).

| Appel | Rôle | Marques reçues |
|---|---|---|
| 1–2 | livraison 01-alpha | aucune |
| 3 | rétro 01-alpha | **FORGED-INDEX** |
| 4 | livraison 02-beta | **FORGED-DELIVERY, FORGED-INDEX** |
| 5 | rétro 02-beta | **FORGED-INDEX** |
| 6 | gate de valeur | aucune (non visé ici) |

- **Le prompt de la session de livraison suivante** reçoit la ligne d'un survivant
  de la précédente. La ligne « Le reste de `.scratch/<feature>/` » du tableau dit
  déjà *« Rien n'empêche l'écriture »* — pour la session elle-même ; ce qui est
  neuf est l'écrivain : un survivant d'une itération **précédente**.
- **L'index des leçons, remis par [81], est reforgé après sa remise.** Le run dit
  une fois *« the lesson index … — put back »* (itération 1), le survivant rajoute
  sa ligne aussitôt, et l'entrée forgée arrive au rétro 1, à la livraison 2, au
  rétro 2 — puis **dans `LEARNINGS.md`** du projet, que le pack rend depuis
  l'index (`retro__record_lesson` lit les entrées de l’index, `retro__publish` le réécrit et le recopie) sans qu'aucun modèle ait
  obéi à quoi que ce soit. L'itération 2 prend la copie forgée comme sa copie
  (`retro_hold_index`), donc rien d'autre n'est dit. La ligne « Une leçon
  injectée… » du tableau écrit deux limites (au-dessus de `MAX_PARALLEL=1`, une
  itération tuée) ; celle-ci n'y est pas. Run sorti `0`.

Ce que les deux mesures ne disent pas : ce qu'un **vrai** modèle fait d'une
question posée par un tiers. Pour les transcriptions dans le document et pour
`LEARNINGS.md`, il n'y a pas de modèle dans la chaîne.
