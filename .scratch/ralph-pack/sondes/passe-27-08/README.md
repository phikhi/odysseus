# Sondes de la passe transversale du 27/08/2026

Des **instruments**, pas des tests. Chacune se termine par un `false` volontaire :
elle rougit toujours, et ce qu'on lit est ce qu'elle imprime avant. Elles ne sont
pas dans `test/` et `test/run.sh` sans argument ne les ramasse pas — elles ne
doivent jamais compter dans le verdict des deux gates.

Les faire tourner, une par une, ou par nom :

    bash test/run.sh .scratch/ralph-pack/sondes/passe-27-08/q5-le-garde-du-claim.bats
    bash test/run.sh -f Q6b .scratch/ralph-pack/sondes/passe-27-08/q6-largeur-de-la-fenetre.bats

Elles pilotent le pack tel qu'il est livré ; aucune n'édite `.claude/` ni
`test/`, et aucune n'a besoin d'une mutation appliquée à la main. La passe qui
les a écrites est dans `../../passe-transversale-27-08.md`, avec la sortie de
chacune et ce qu'elle a montré.

| Sonde | Ce qu'elle demande | Verdict |
|---|---|---|
| `q1` Q1a | un `.open.guard` laissé par un run tué : qui le nomme, qui le balaye ? | **personne — il traverse un run vert en silence** (`gate_leftovers` ne regarde que `$TMPDIR`) |
| `q1` Q1b | avec `.scratch/` ignoré, la ligne de zone le nomme-t-elle ? | non — les gates jugent le worktree, le garde vit dans l'arbre principal. Même statut que `.run.lock` |
| `q2` Q2a | une session **pose** le garde d'ouverture | **`scope=green`, rollback aveugle, plus un numéro alloué de la nuit, cause absente de `run.log` et du reçu** |
| `q3` Q3a | garde tenu toute la nuit : le re-slice | `too-big` + reçu portant les trois gaps, mais **rien sur le ticket** |
| `q3` Q3b | garde relâché en cours de split | split incomplet, dit sur le ticket, la console et le reçu — conforme |
| `q4` Q4a | deux sous-shells d'un pilote sur un garde périmé, barrière d'attente active | **`both=0` sur 300 tours** — course stagée, pas gagnée |
| `q4` Q4b | ce que ça vaudrait sur l'espace des numéros | 0 collision sur 60 tours, avec et sans garde périmé |
| `q4` Q4c | `state_guard_release` quand deux sœurs sont en vol | **la sœur refusée ne relâche rien** — angle disculpé, mesuré à 8 s et non 6 |
| `q5` Q5a | un garde de claim de sœur pris dans le snapshot d'avant-session | **ressuscité avec le pid du pilote, fausse accusation, `02-beta` inréclamable** |
| `q5` Q5b | le cas miroir : un garde qui **apparaît** dans la fenêtre | sain — `A`, rien restauré, aucune note |
| `q5` Q5c | le temporaire de `state_atomic_write` | même résurrection, même fausse accusation |
| `q5` Q5d | bout en bout : ce que le run fait d'un ticket ainsi bloqué | **`ready-for-agent` sur la frontière, run stérile, `run.log` muet, « someone else has it » désigne personne** |
| `q5` Q5e | le registre de [13]/[42] peut-il exempter ces chemins ? | **non, structurellement** — `restored 3` avec le registre correctement rempli |
| `q6` Q6a | fréquence, une sœur écrivant en continu | 52 snapshots sur 60 capturent un transitoire (pire cas assumé) |
| `q6` Q6b | les deux durées dont la fenêtre est faite | snapshot **35 ms**, `set_fields` **15 ms**, claim+unclaim 64 ms |

## Deux pièges rencontrés en les écrivant

**Deux `&` nus ne mettent rien en concurrence.** Q4a rendait `both=0 a_only=3
b_only=297` : le coût du fork est bien plus large que la fenêtre demandée, donc
les deux sous-shells étaient sérialisés et la sonde mesurait le fork. Avec une
barrière d'attente active (`while [ ! -e "$go" ]; do :; done`) le partage devient
145/155 et la mesure veut dire quelque chose. Une sonde de concurrence sans
rendez-vous mesure l'ordonnanceur.

**`set -euo pipefail` + une affectation depuis une substitution qui échoue tue le
`pack_run`, et la sonde *pend* au lieu de rougir.** Q6a a tourné plus de deux
minutes sans écrire une ligne : `stray="$(… | grep -v … )"` avec un `grep` qui ne
trouve rien met fin au script, mais l'écrivain lancé en fond garde le tuyau de
stdout ouvert, donc le `run` de bats attend pour toujours. Mettre `set +e` dans
le corps d'une sonde qui lance un fond, et se méfier d'un `pack_run` dont la
sortie est vide : ce n'est pas « ça tourne encore ».
