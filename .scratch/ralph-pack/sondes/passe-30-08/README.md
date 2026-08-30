# Sondes de la passe transversale du 30/08/2026

Des **instruments**, pas des tests. Chacune se termine par un `set -e; false`
volontaire : elle rougit toujours, et ce qu'on lit est ce qu'elle imprime avant.
Elles ne sont pas dans `test/` et `test/run.sh` sans argument ne les ramasse pas —
elles ne doivent jamais compter dans le verdict des deux gates.

Les faire tourner, une par une, ou par nom :

    bash test/run.sh .scratch/ralph-pack/sondes/passe-30-08/r5-le-path-du-pilote.bats
    bash test/run.sh -f R3d .scratch/ralph-pack/sondes/passe-30-08/r3-successor-log-en-zone-ecrivable.bats

Elles pilotent le pack tel qu'il est livré ; aucune n'édite `.claude/` ni `test/`,
et aucune n'a besoin d'une mutation appliquée à la main. La passe qui les a
écrites est dans `../../passe-transversale-30-08.md`, avec la sortie de chacune et
ce qu'elle a montré.

| Sonde | Ce qu'elle demande | Verdict |
|---|---|---|
| `r1` R1a | un run tué **entre** le mur budget et la queue de `loop_main` | rien n'est armé, `run.log` porte `budget-wall` **seul** — troisième état que rien ne nomme, et la phrase « un successeur est armé au reset » est stdout-only |
| `r1` R1b | le témoin appairé, même run non tué | `budget-wall successor-armed`, marqueur écrit — la sonde stage bien la bonne fenêtre |
| `r1` R1c | ce qu'un lecteur du matin distingue depuis `run.log` seul | armé = `budget-wall successor-armed` · choisi = `budget-wall weekly-pause` · tué = `budget-wall` seul |
| `r2` R2a | un marqueur laissé par un successeur qui ne s'est jamais réveillé | **personne ne le compte, personne ne le balaye** (`gate_leftovers` ne regarde que `$TMPDIR` et les `*.guard` de la feature) |
| `r2` R2b | un marqueur forgé : pour combien de nuits ? | **nuit 1 et nuit 2 refusées**, marqueur intact, et `run.log` enregistre `weekly-pause` — le mot d'un projet qui a choisi `WEEKLY_RESUME=human` |
| `r2` R2c | une session peut-elle atteindre `<gitdir>/ralph.successor` depuis son worktree ? | **oui, depuis une itération verte** (`scope=green`, `resolved`), par `git rev-parse --git-common-dir` |
| `r3` R3a | `successor.log` est un **répertoire** quand le successeur se réveille | `bash: … Is a directory`, job `exit 1`, **`loop.sh` ne démarre pas** (0 appel `claude`, 0 appel `curl`) — la nuit est perdue et la sortie part dans le mail d'`at` |
| `r3` R3b | `successor.log` est un **lien** vers un chemin scellé | le successeur **écrit dans `.claude/settings.json`** : 153 → 1240 octets, JSON cassé pour tout `claude` suivant |
| `r3` R3d | bout en bout : la session pose le lien depuis une itération verte | `tests=green typecheck=green scope=green lang=green`, `01-alpha resolved`, puis 153 → 1240 octets au réveil |
| `r3` R3c | qui apprend qu'un successeur n'a pas démarré | personne : `run.log` dit `successor-armed`, le marqueur dit l'instant, aucun run ultérieur ne relit le marqueur pour autre chose que refuser d'armer |
| `r4` R4a | un run dont `FEATURE` vient de l'**environnement** (forme livrée du config) | la ligne mise en file **ne porte pas `FEATURE`** : le successeur sort `exit 2`, « FEATURE is empty », alors que le run a annoncé « armed a one-shot successor » et journalisé `successor-armed` |
| `r4` R4b | deux runs, deux features, un arbre, en concurrence | refusé par le **verrou d'arbre** avant toute question de marqueur — angle disculpé |
| `r4` R4c | les mêmes, séquentiellement | le marqueur est **par arbre** : la première feature prend l'unique créneau, la seconde est refusée et son ticket reste `ready-for-agent` sans que rien ne le dise |
| `r5` R5a | une session pose un `git` dans un répertoire du `PATH` du pilote | le run courant ne le voit pas (bash a déjà *hashé* `git`), **le run suivant fait 204 appels git à travers lui** — dont `rev-parse --git-dir`, `worktree list`, `config --get core.excludesFile`. Aucune ligne, aucun reçu, aucune dérive de capacité |
| `r5` R5b | le successeur hérite-t-il de ce `PATH` ? | oui, **figé dans la ligne mise en file**, et `gate_frontier_residue` — la seule chose qui peut refuser d'armer — ne parle que de configuration git |
| `r5` R5c | ce que le pack regarde, et ce qu'il ne regarde pas | `PATH` n'est lu **qu'une fois** dans tout le pack, pour le recopier dans la file ; `gate_config_keys` a 53 entrées et aucune ne parle du `PATH` |

## Rejouées, et elles tiennent

- **`q1` Q1a du 27/08** (`gate__stale_guards`, livré par [49]) : `1 exclusion
  guard(s) left in … .open.guard — the owner is gone`. Le constat est bien émis.
- **`q5` Q5a du 27/08** (la restauration de `issues/`, livré par [49]) : le garde
  de la sœur **n'est plus ressuscité**, `rc=0`, aucune fausse accusation, et la
  confession nomme les deux chemins transitoires. La décision « filtrer, pas
  déplacer » tient au réel.

## Trois pièges rencontrés en les écrivant

**`set +e` dans un corps de sonde désarme le `false` final.** Bats juge le corps
sur son statut de sortie, mais `set +e` fait que la sonde rend `ok` avec un
`false` en dernière ligne — donc bats n'imprime rien et l'instrument est muet.
Le `set +e` reste nécessaire (une sonde qui lance un fond ne doit pas mourir sur
la première substitution vide, cf. le piège du 27/08) : il faut donc **`set -e`
juste avant le `false`**. Trois sondes ont rendu « 3 tests, 0 failures » avant
qu'on s'en aperçoive.

**`FEATURE="${FEATURE:-}"` posé *après* `FEATURE='demo'` ne stage rien.** La forme
livrée du config relit la variable de shell que la ligne précédente vient de
poser, donc `env -u FEATURE` rendait quand même `demo`. Pour stager « FEATURE ne
vient que de l'environnement », il faut **retirer** la ligne injectée par le
harnais (`perl -ni -e "print unless /^FEATURE='/"`), pas en ajouter une après.
Mesuré par une sonde jetable avant de conclure quoi que ce soit.

**Bash *hash* les commandes : un `git` posé sur le `PATH` n'atteint pas le shell
qui tourne déjà.** R5a rendait `0` appels et ça se lisait comme « le plant ne
marche pas ». Le pilote avait résolu `git` bien avant que la session existe. Ce
qui compte est le run **suivant** — un bash frais, comme le successeur — et là
c'est 204. Une sonde de `PATH` qui ne mesure que le run courant conclut l'inverse
de la vérité.
