# Sondes de la passe transversale du 26/08/2026

Des **instruments**, pas des tests. Chacune se termine par un `false` volontaire : elle
rougit toujours, et ce qu'on lit est ce qu'elle imprime avant. Elles ne sont pas dans
`test/` et `test/run.sh` sans argument ne les ramasse pas — elles ne doivent jamais
compter dans le verdict des deux gates.

Les faire tourner, une par une :

    bash test/run.sh .scratch/ralph-pack/sondes/passe-26-08/p7.bats

Elles pilotent le pack tel qu'il est livré ; aucune n'édite `.claude/` ni `test/`.
La passe qui les a écrites est dans `../../passe-transversale-26-08.md`, avec la sortie
de chacune et ce qu'elle a montré.

| Sonde | Ce qu'elle demande | Verdict |
|---|---|---|
| `p1-home` P1a | `core.hooksPath` dans `~/.gitconfig` fait-il tourner un `post-commit` ? | non — la plomberie de `failures_make_durable` |
| `p1b` P1d | `diff.external` ? | non |
| `p1b` P1e / `p2` | du texte quelconque dans `~/.gitconfig` ? | oui, mais bruyamment : `rc=4`, reçu émis |
| `p1c` | `core.fsmonitor` dans `~/.gitconfig` | **248 exécutions, run vert, silence** |
| `p3` P3a | le même par `<arbre>/.git/config` | **idem, sans avoir à trouver `$HOME`** |
| `p2` P2b | témoin de [15] sur une itération retryée puis suivie d'autres | arrive au reçu — conforme |
| `p2` P2c | … sur laquelle le run s'arrête | **aucun reçu, aucune ligne de journal** |
| `p3` P3b | … et au run suivant | **c'est la ligne de base : silence définitif** |
| `p4` P4a | deux ouvertures de ticket en vol | **même `NN`, bare number irrésolvable** |
| `p5` P5a | la renumérotation répare-t-elle celle de la boucle ? | **non — le registre de [13] la désarme** |
| `p5` P5b | la lentille de la même itération voit-elle le `$HOME` écrit ? | oui — limite 3 de [15], conforme |
| `p5` P5c | `CAPABILITY=off` éteint-il le témoin ? | non — AC 4 de [15] tient |
| `p6` | smudge et rollback | **inconcluante** : elle regarde l'arbre principal, le rollback agit dans le worktree. Remplacée par `p7` |
| `p7` | smudge et itération suivante | **`CONTEXT.md` réécrit pour la session 2, blob intact, silence** |
| `p8` | le smudge atteint-il le ticket et la `Write-surface:` ? | non — lus dans l'arbre principal |
