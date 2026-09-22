# Sondes de la passe transversale du 22/09/2026

Des **instruments**, pas des tests. Les deux `.bats` finissent par un
`set -e; false` volontaire : elles rougissent toujours, et ce qu'on lit est ce
qu'elles impriment avant. Elles ne sont pas dans `test/` et `test/run.sh` sans
argument ne les ramasse pas — elles ne doivent jamais compter dans le verdict
des deux gates.

    bash test/run.sh .scratch/ralph-pack/sondes/passe-22-09/q2-le-verdict-passe-par-un-nom-non-surveille.bats
    bash test/run.sh -f Q3c .scratch/ralph-pack/sondes/passe-22-09/q3-le-verdict-ecrit-par-un-survivant.bats
    bash .scratch/ralph-pack/sondes/passe-22-09/q1-le-cache-du-harnais.sh

---

## `q1-le-cache-du-harnais.sh` → §3, ticket [93]

**Pas un `.bats`, et c'est la sonde qui l'exige** : elle pilote `test/run.sh` de
l'extérieur, dans une copie de l'arbre et avec un `$TMPDIR` à elle, parce que ce
qu'elle mesure est le cache que le harnais résout **avant** que le premier test
n'existe. Une sonde chargée par le harnais aurait déjà consommé ce qu'elle veut
observer.

Elle joue la chaîne dans l'ordre où une session la joue : run propre (`fp0`),
garantie du pack retirée (`fp1`), gabarit **propre** déposé sous `fp1`, puis
`TEST_CMD`. Trois runs de contrôle : le forgé (D), le témoin appairé sans dépôt
(E), le contre-témoin pack restauré (F).

**Verdict : le canal existe et il est complet.** D vert sur un pack cassé, E
rouge, F vert. Mesuré en 3,5 s ; la mutation réutilisée est une entrée existante
de `test/mutate.sh` (`02 a live lock holder is stolen from`), donc la garantie
retirée est une vraie garantie et non une invention de la sonde.

*Piège trouvé en l'écrivant* : l'ordre compte. Déposer le gabarit forgé **après**
un run sous `fp1` ne mesure rien — le harnais en aurait déjà bâti un légitime et
posé son `.ready`. La sonde dépose avant le premier run de cette clé, ce qui est
aussi ce qu'une session fait.

---

## `q2-le-verdict-passe-par-un-nom-non-surveille.bats` → §1, ticket [91]

Trois cas. `Q2a` lit `gate_path_programs` et les invocations de `bash` par leur
nom nu dans le pack livré. `Q2b` fait écrire un manifeste par
`gate_path_witness` et cherche la ligne `bash`. `Q2c` plante un `bash`
enregistreur en tête de `PATH` et fait tourner **une itération réelle**.

**Verdict : 32 noms, 32 lignes, aucune ne dit `bash` ; 13 passages par le
planté, dont les 4 qui portent un verdict.**

*Piège* : l'enregistreur doit avoir un shebang **absolu** (`#!/bin/bash`). Avec
`#!/usr/bin/env bash`, `env` le re-résout par le `PATH` — où il est en tête — et
récurse à l'infini.

---

## `q3-le-verdict-ecrit-par-un-survivant.bats` → §2, ticket [92]

Trois cas, tous sous `run_loop_own_tmp` pour que le répertoire de gate observé
soit celui de ce test et jamais celui d'un runner voisin. `Q3a` est le témoin
appairé (suite rouge, aucun survivant). `Q3b` est la même suite rouge avec un
process laissé par la session. `Q3c` demande seulement si le process est encore
là quand le run a fini.

**Verdict : `ready-for-human`/`exit 4` sans survivant, `resolved`/`exit 0` dès la
première itération avec — et le survivant est vivant, reparenté à `init`, après
la fin du run.**

*Technique de mise en scène, réutilisable* : `script_claude` **remplace** le faux
`claude` (le shim fait `exec`), donc une session qui veut faire quelque chose
*puis* répondre normalement doit se désarmer elle-même :

    chmod -x "$state/claude.script"
    exec claude "$@"

Sans le `chmod -x`, le ré-`exec` reprend le script et boucle.

---

## Ce que ces sondes ne mesurent pas

- **Le `TMPDIR` partagé de la machine.** `q2` et `q3` tournent sous le `$TMPDIR`
  du harnais (`q3` sous `run_loop_own_tmp`), `q1` sous le sien. Aucune n'écrit
  dans l'espace de noms `ralph-*` de la machine, et aucune ne doit le faire : une
  sonde qui y toucherait trouverait le cache d'une suite qui tourne à côté.
- **Les deux gates.** Aucune n'a été jouée pendant un gate, et la passe n'a touché
  ni `.claude/`, ni `test/`, ni `init.sh` — la baseline de [89] tient telle quelle
  (`run.sh` 975/0/6, `mutate.sh` 1024/0).
