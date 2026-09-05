# Sondes de la passe transversale du 05/09/2026

Des **instruments**, pas des tests. Chacune se termine par un `set -e; false`
volontaire : elle rougit toujours, et ce qu'on lit est ce qu'elle imprime avant.
Elles ne sont pas dans `test/` et `test/run.sh` sans argument ne les ramasse pas —
elles ne doivent jamais compter dans le verdict des deux gates.

Les faire tourner, une par une ou par nom :

    bash test/run.sh .scratch/ralph-pack/sondes/passe-05-09/q2-le-retro-consulte-le-budget-avant-le-verdict.bats
    bash test/run.sh -f Q1a .scratch/ralph-pack/sondes/passe-05-09/q1-le-balayage-de-tmpdir-a-une-liste-plus-etroite-que-son-critere.bats

Elles pilotent le pack tel qu'il est livré ; aucune n'édite `.claude/` ni `test/`,
et aucune n'a besoin d'une mutation appliquée à la main. La passe qui les a
écrites est dans `../../passe-transversale-05-09.md`.

| Sonde | Ce qu'elle demande | Verdict, mesuré le 05/09/2026 |
|---|---|---|
| `q1` Q1a | les **dix-huit** noms que le pack `mktemp` au premier niveau de `$TMPDIR`, vieillis de 25 h, un par un | **6 vus, 12 non**. Muets : `ralph-receipt`, `ralph-retro`, `ralph-playthrough`, `ralph-spec`, `ralph-tracker`, `ralph-failed`, `ralph-durable`, `ralph-reslice`, `ralph-index`, `ralph-restore`, `ralph-fold`, `ralph-refresh` |
| `q1` Q1b | un run réel **tué au `KILL`** pendant le gate | **9 entrées laissées, 6 comptées**. Les trois muettes : `ralph-receipt.*`, `ralph-retro.*` (des répertoires) et `ralph-spec.*` ([11]) |
| `q1` Q1c | témoin appairé : un run qui finit normalement | **0** entrée — ce qui reste en Q1b est bien ce que le critère décrit |
| `q2` Q2a | le rétro répond `LESSON`+`WHY`+`ADR`+`DECISION`+`BECAUSE`+`ESCALATE`, **et** son flux porte `blocked` (`seven_day`) pour la fenêtre suivante | **rien n'est enregistré** : pas de `LEARNINGS.md`, `docs/adr/` vide, aucun ticket d'escalade, `capability_review` jamais atteint. Le reçu dit « the API refused the retro session » — c'est faux. Et `RALPH_RETRO_QUOTA` écrase `$slot/posture` : **le run s'arrête**, `02-beta` jamais tenté, `rc=6` |
| `q2` Q2b | témoin appairé : le **même** rétro, l'événement dit `allowed` | leçon `LR-0001`, `docs/adr/0001-…md`, ticket `03-retro-…` sur le puits humain, run qui continue jusqu'au bout de la file |
| `q3` Q3a | un run AFK avec `50-a<LF>b.md` posé **avant** le run | la ligne de [48] dite **8 fois** sur la console, **0 fois** dans `run.log`, **0** dans le reçu, **0** dans `docs/playthroughs/` |
| `q3` Q3b | le même fichier, le **drain humain** | dite **6 fois**, console seulement |
| `q3` Q3c | le drain qui ouvre une session routée (`router_protect_tracker` + le pin de [55]) | dite **7 fois**, console seulement — le pin et le garde de [55] filtrent le nom sans jamais le dire eux-mêmes |
| `q3` Q3d | `playthrough__injected` au module | **0** : `$(tracker_ids 2>/dev/null)` avale la ligne. `tracker_ids` nu la dit |
| `q3` Q3e | une session de livraison dépose trois `NN-playthrough-wiring-forged.md` dans `issues/` | la quarantaine de [07] les **nomme** et leur **laisse leur nom** ; `playthrough__injected` rend **3**, donc `PLAYTHROUGH_REINJECT_MAX=2` est franchi : cette feature ne rouvrira plus jamais un ticket de câblage |

## Pièges rencontrés en les écrivant

**Le harnais ne sait pas exprimer « une session subalterne qui répond ET porte un
événement `blocked` » pour le rétro.** `retro_refused` émet l'événement *et*
`exit 1` sans réponse ; `claude_rate_limit` est **global** et toucherait aussi la
session de livraison, dont le posture est justement ce que le pilote lit. [11] a
ajouté `playthrough_rate_limit` pour son propre palier et n'a pas fait le
pendant. La seule façon d'écrire le cas est un `script_claude` qui reconnaît le
rétro à `RALPH-RETRO-NOTHING` dans le prompt — comme le shim lui-même — et émet
son propre flux NDJSON. Le gate de valeur, lui, est court-circuité **avant** le
`script_claude`, donc il répond `pass` tout seul et ne gêne pas.

**Un `script_claude` installé fait taire `retro_call_count` et
`playthrough_call_count`** : le shim n'écrit `claude.retros/calls` qu'**après** le
`exec` vers le script. Une sonde qui a besoin de savoir que le rétro a tourné pose
son propre témoin (ici `: >"$state/retro-was-called"`).

**`$FEATURE` n'est pas dans l'environnement du faux `claude`.** Une sonde qui
veut écrire dans `issues/` depuis une session prend le répertoire par un glob
(`ls -d "$root"/.scratch/*/issues`), jamais par `$FEATURE`.

**`kill -TERM` ne reproduit pas « un run tué ».** Les traps tournent et le pack
range tout : la sonde `q1` Q1b doit envoyer `KILL` à l'itération **et** au pilote,
et laisser une seconde aux enfants du gate.

**`-mtime +0` veut dire strictement plus de 24 h.** Un résidu fraîchement posé
n'est compté par personne ; il faut `touch -t` à 25 h.

**Un `pack_run` écrase `$status` et `$output`.** Une sonde qui veut imprimer la
sortie d'un `run_loop` *après* un `pack_run` doit la copier d'abord.
