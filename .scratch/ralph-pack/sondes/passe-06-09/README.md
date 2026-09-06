# Sondes de la passe transversale du 06/09/2026

Des **instruments**, pas des tests. Chacune se termine par un `set -e; false`
volontaire : elle rougit toujours, et ce qu'on lit est ce qu'elle imprime avant.
Elles ne sont pas dans `test/` et `test/run.sh` sans argument ne les ramasse pas —
elles ne doivent jamais compter dans le verdict des deux gates.

Les faire tourner, une par une ou par nom :

    bash test/run.sh .scratch/ralph-pack/sondes/passe-06-09/q1-le-desk-du-puits-est-choisi-par-une-ref-git-quune-session-ecrit.bats
    bash test/run.sh -f Q2b .scratch/ralph-pack/sondes/passe-06-09/q2-les-quatre-mots-du-drain-sont-lus-dans-un-fichier-quune-session-ecrit.bats

Elles pilotent le pack tel qu'il est livré ; aucune n'édite `.claude/` ni `test/`,
et aucune n'a besoin d'une mutation appliquée à la main. La passe qui les a
écrites est dans `../../passe-transversale-06-09.md`.

| Sonde | Ce qu'elle demande | Verdict, mesuré le 06/09/2026 |
|---|---|---|
| `q1` Q1a | une session routée fait `git update-ref refs/heads/failed/<id> HEAD` et rien d'autre | desk **`admit` → `arbitrate`**. Le dossier du drain suivant envoie l'humain lire `git log -p failed/20-decision`. Le drain a nommé **0 chemin** |
| `q1` Q1b | témoin appairé : la même session, sans la ref | desk **`admit`**, « branch there is none. nothing ever ran on this ticket » |
| `q1` Q1c | l'autre sens : la session efface la ref d'une tentative **réellement jugée** | desk **`arbitrate` → `admit`**, et le dossier affirme « there is none. nothing ever ran on this ticket ». **0 chemin nommé** |
| `q2` Q2a | un `run.log` portant `budget-wall` seul | la note est dite : « that run was killed while it was draining. Nothing in this pack writes that end down as a state » |
| `q2` Q2b | une session routée ajoute une ligne portant `successor-armed` | `router_run_notes` **rc=1**, la note **disparaît**. **0 chemin nommé** |
| `q2` Q2c | témoin appairé : la même session, sans la ligne | la note est dite |
| `q2` Q2d | une session routée fabrique `claim-refused` sur un `run.log` vierge | le drain suivant dit « the frontier is short of a ticket nothing else would have mentioned » — sur un run qui n'a jamais refusé de claim |
| `q2` Q2e | un run AFK complet passe ensuite sur la ligne fabriquée | run **vert rc=0**, `loop_journal_verify` se tait (**0**), la note est toujours dite après |
| `q3` Q3a | l'humain ferme un ticket, puis une session routée sur le ticket suivant écrase `run.log` | le ticket est `wontfix` et **sa ligne `drained` n'existe plus**. Le drain ne se plaint **0** fois, ne nomme **0** chemin |
| `q3` Q3b | témoin appairé : le même écrasement, côté AFK | « the run journal does not hold exactly the 2 line(s) this run wrote… » + la copie du run imprimée dessous |
| `q3` Q3c | témoin appairé : le même drain, sans l'écrasement | les deux lignes sont là |
| `q4` Q4a | un drainage démarré après un run réel tué au `KILL` pendant le gate | décor : **9** entrées `$TMPDIR`, un marqueur de successeur, **1** worktree enregistré. Le drain en nomme **0** |
| `q4` Q4b | témoin appairé : un run AFK sur le même décor | il en nomme **3**, et les 9 entrées sont comptées **9** ([62] tient) |
| `q5` Q5a | une session routée réécrit `spec.md`, puis un run AFK tourne | le prompt du gate de valeur porte le flux **forgé**. Drain : **0** chemin nommé ; run : **0** mot du flux |
| `q5` Q5b | témoin appairé : le même run sans le drain | le prompt porte le vrai `spec.md` |
| `q5` Q5c | la **même** réécriture par une session AFK **pendant** le run | le prompt porte **0** ligne forgée — le témoin de [11] tient pour le cas qu'il vise |

## Pièges rencontrés en les écrivant

**Un ticket `ready-for-human` ne fait pas démarrer un gate.** La sonde `q4` doit
semer un ticket `ready-for-agent` (`use_tickets 01-alpha`) *en plus* du ticket du
puits, sinon le run AFK sort sur une frontière vide et le `KILL` ne tombe sur
rien : la première version a mesuré « 0 entrée dans `$TMPDIR` » et disait que le
run tué ne laissait rien.

**Un run tué garde ses verrous.** Une sonde qui veut faire démarrer quoi que ce
soit derrière lui doit `rm -rf "$(run_lock_dir)" "$(tree_lock_dir)"` — le trap qui
les relâche ne tourne pas sur un `KILL`.

**`router__tree_dirt` saute `gate_is_bookkeeping`.** Toute sonde qui attend du
drain qu'il nomme une écriture dans `.scratch/<feature>/` mesure zéro, et ce zéro
est la trouvaille, pas un bug de la sonde.

**Le drain rend 3 (« stdin ended ») dès que le script de réponses est épuisé.**
Ce n'est pas un refus : `printf "o\nn\n"` finit toujours ainsi quand la sonde ne
tape pas `q`. Ne pas asserter sur ce code.

**Une session routée n'a pas `$FEATURE` dans son environnement** (piège déjà
connu de la passe du 05/09) : prendre le répertoire par
`ls -d "$root"/.scratch/*/`, jamais par `$FEATURE`.

**`grep -c 'journal'` sur la sortie d'un drain compte le libellé du dossier.**
La ligne `journal  its own lines in run.log, below.` est toujours là ; pour
mesurer une plainte il faut chercher `does not hold exactly`.
