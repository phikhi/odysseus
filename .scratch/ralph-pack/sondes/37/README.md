# Sondes de [37] — les ids du tracker sont une ligne de mots

Des **instruments**, pas des tests. Chacune se termine par un `false` volontaire : elle
rougit toujours, et ce qu'on lit est ce qu'elle imprime avant. Elles ne sont pas dans
`test/` et `test/run.sh` sans argument ne les ramasse pas — elles ne doivent jamais
compter dans le verdict des deux gates.

Les faire tourner, une par une :

    bash test/run.sh .scratch/ralph-pack/sondes/37/s1-espace.bats

Elles pilotent le pack tel qu'il est livré, au niveau lib, et n'éditent ni `.claude/`
ni `test/`. Aucune n'a besoin d'une mutation appliquée à la main.

`s1` et `s2` ont été écrites **avant** le correctif et rejouées après ; `s3` a été
écrite **après**, et ce qu'elle mesure est ce qui reste ouvert ([48]).

| Sonde | Ce qu'elle demande | Avant [37] | Après |
|---|---|---|---|
| `s1` S1a | un ticket `99-my ticket.md` déposé par une session | **deux intrus fantômes, `quarantined 99-my ticket` annoncé sur un ticket resté `ready-for-agent` avec `Write-surface: *`** | un intrus, `ready-for-human`, `Escalation: decision` |
| `s1` S1b | témoin appairé, le même sans espace | conforme | conforme |
| `s1` S1c | un id `99-a[0]` avec un `99-a0` dans le répertoire courant | **l'intrus rapporté est `99-a0` — le glob a remplacé l'id** | `99-a[0]`, littéral |
| `s2` S2a | qui `tracker__carriers` nomme pour le numéro 99 | **`99-my`**, un ticket qui n'existe pas | `99-my ticket` |
| `s2` S2b | registre de [13]/[42] : la boucle a écrit `99-my ticket` | **`99-my` écrit par la session est exempté, `rc=0`, rien en quarantaine** | renuméroté et escaladé |
| `s2` S2c | `gate__surface_owner src/beta.txt` | **aucun propriétaire → débordement classé intrus retryable** | `99-my ticket` |
| `s2` S2d | balayage de claim sur un propriétaire mort | **rien : le ticket n'est jamais regardé, `claimed` définitivement** | `99-my ticket retry` |
| `s3` S3a | un nom de fichier qui contient un **saut de ligne** | — | **toujours deux fantômes ; `quarantined 99-a, b` alors que rien n'est escaladé → [48]** |

Ordre à respecter dans S2d : la reprise *rend* le ticket
(`failures_after_dead_owner` → `tracker_unclaim`), donc le cas exempté passe en
premier — sinon le second appel n'a plus rien de réclamé à regarder.
