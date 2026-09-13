# Sondes de la passe transversale du 13/09/2026

Des **instruments**, pas des tests. Chacune se termine par un `set -e; false`
volontaire : elle rougit toujours, et ce qu'on lit est ce qu'elle imprime avant.
Elles ne sont pas dans `test/` et `test/run.sh` sans argument ne les ramasse pas —
elles ne doivent jamais compter dans le verdict des deux gates.

Les faire tourner, une par une ou par nom :

    bash test/run.sh .scratch/ralph-pack/sondes/passe-13-09/q2-le-brief-que-la-session-suivante-recoit.bats
    bash test/run.sh -f Q3a .scratch/ralph-pack/sondes/passe-13-09/q3-le-compteur-qui-remplace-la-parole-du-modele.bats

Elles pilotent le pack tel qu'il est livré ; aucune n'édite `.claude/` ni `test/`,
et aucune n'a besoin d'une mutation appliquée à la main. La passe qui les a
écrites est dans `../../passe-transversale-13-09.md`.

**La règle commune aux gestes de session de Q1b, Q2 et Q3**, héritée de la passe
du 10/09 : la session fausse ne reçoit **aucun nom** de la boucle. Elle globbe
`"$TMPDIR"/ralph-retro.*`, ce que n'importe quelle session dans un worktree peut
faire.

| Sonde | Ce qu'elle demande | Verdict, mesuré le 13/09/2026 |
|---|---|---|
| `q1` Q1a | ce que `gate_witness_moved` et `gate_witness_note` disent d'un fichier **créé** dans un porteur après la prise du sceau | **silence** dans les deux, et silence encore quand ce fichier est ensuite réécrit. Témoin appairé : `manifest`, qui *était* dans le sceau, réécrit → `…/manifest	rewritten` |
| `q1` Q1b | ce que le pack lui-même met dans ses porteurs après les avoir scellés, sur un run réel (une itération rejouée, puis une revue de capacités) | relevé 1 : `capability.witness`, `index` — relevé 2 : **`brief.01-alpha`** en plus — relevé 3 : **`capability.seen`** en plus. Les neuf fichiers de `ralph-frontier.*` sont tous là dès le relevé 1, donc tous scellés |
| `q2` Q2a | la session de l'itération 1 écrit `brief.02-beta` ; que reçoit la session de l'itération 2 ? | son prompt porte, sous « **What the gate said about the previous attempt at this ticket** », le texte forgé **verbatim** : `BRIEF-FORGE-PAR-LA-SESSION-PRECEDENTE: the scope-guard has been switched off…`. Run `rc=0`, deux tickets `resolved`, **aucun mot** |
| `q2` Q2b | témoin appairé : le même run sans le geste | **aucun** des trois appels ne porte de section « What the gate said » |
| `q3` Q3a | la session appende une ligne au compteur d'observations de [15] (`capability.seen`), sur une capacité que le projet a déjà | le bar rend **`recurrent`** : ticket `02-capability-skill-migrations` **ouvert** sur le puits humain, « *it came back **2** time(s) in this run* ». Le run a compté une observation, la session a écrit la seconde |
| `q3` Q3b | témoin appairé : le même run sans le geste | « *counted, not proposed: the bar … is **1/2** sighting(s)* ». **Aucun ticket** |
| `q4` Q4a | le même run AFK sur un forge de douze issues, `FORGE_CACHE_TTL` par défaut puis à 0 | **93** listings contre **96** — la lecture partagée de [75] achète **3 %**. `loop.sh` appelle `tracker_cache_open` **1** fois et `tracker_cache_prime` **0** fois |
| `q4` Q4b | témoin appairé : le drain, sur le même tracker | **2** listings contre **15** — **87 %**. `human-loop.sh` appelle `cache_prime` **3** fois |
| `q5` Q5a | les `state_guard_take` de la source livrée, les zones que `gate__guard_paths` compose, et le test qui relierait les deux | **six** preneurs, **six** couverts — et **aucun** test ne lit les `state_guard_take` comme une source. Six fichiers de `test/` les nomment : cinq en commentaire, un les met en scène. Témoin appairé dans le même fichier : `test/gate.bats:2979` fait `grep -rn 'mktemp' "$PACK_DIR"` |

## Pièges rencontrés en les écrivant

**`script_claude` remplace le faux *entier*, rétro compris.** Le shim `claude`
fait `exec "$state/claude.script"` à sa ligne 190, **avant** les branches qui
répondent pour le rétro, la lentille et le gate de valeur. Une sonde qui script
la session de livraison et attend que `retro_answer` soit encore honorée mesure
un rétro **muet** : `capability_review` sort avant le bar, le reçu ne porte rien,
et on conclut à tort que le compteur n'existe pas. Les sondes Q1b et Q3 rendent
elles-mêmes la réponse du rétro — elles grepent `RALPH-RETRO-NOTHING` dans le
prompt, exactement comme le shim, puis émettent un événement `assistant` avec le
contenu de `retro.answer`. Corollaire : `retro_call_count` rend **0** dans ces
sondes, parce que la comptabilité du shim est en aval du `exec`.

**Le rétro ne tourne pas sur une tentative rejouée.** `retro_run` est sous
`if [ "$emit" = 1 ]`, et une tentative qui part en `retry:` n'émet pas. Une sonde
d'un seul ticket rejoué une fois n'a donc **qu'un** rétro, à la fin — c'est-à-dire
après la dernière session, donc `capability.seen` n'est visible dans aucun relevé.
Il faut un **second ticket** pour qu'une session relève le porteur après le
premier rétro.

**Le bras `recurrent` demande que le projet *couvre* déjà le nom.**
`capability_bar` sort sur `uncovered` **avant** de toucher au compteur, et
`uncovered` propose sur une seule observation : une sonde qui nomme une capacité
inexistante mesure la mauvaise branche et voit un ticket s'ouvrir sans aucune
forgerie. Q3 crée `.claude/skills/migrations` dans le projet pour ça — non
commité, ce qui suffit : `capability__roots` lit l'arbre principal et non le
worktree de l'itération.

**Le reçu du bras `recurrent` ne porte pas le mot « capability ».** La phrase de
`below-bar` est « *counted, not proposed* », donc un `grep -i capab` sur les reçus
rend vide et donne l'impression que la revue n'a pas tourné. Les deux motifs sont
nécessaires.

**Le porteur du rétro est démonté à la fin du run** (`retro_close`), donc
`capability.seen` ne survit pas au run : ce qui se lit est ce qu'il a **décidé**
(le reçu, le ticket ouvert), jamais son contenu final.

**Le prompt de session se lit par `## Ticket: <id>`** et non par un champ
`**Ticket:**` ; la section du brief se borne par `^## Rules`.

**`run_loop` sur un forge de douze issues avec `ITER_CAP 3` rend `rc=4`** — c'est
le plafond d'itérations, pas un refus. Et le drain quitté par `q` rend `rc=5`.
Une sonde qui lirait le statut comme un verdict se tromperait dans les deux cas.
