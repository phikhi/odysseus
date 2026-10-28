# Rejeux de la passe du 28/10/2026

Sur `main` à `e95e885` (merge de [109]), en série, par `rejouer.sh` (chemins du
scratchpad de la session à adapter) : `bash test/run.sh <sonde> </dev/null`, une
par ligne. Instruments, pas tests : chaque cas finit par un `false` volontaire,
donc `rc=1` partout est attendu. Durée totale : ~2 min 20.

| Sonde | Colonne « branche » de son README | Rejoué sur `e95e885` |
|---|---|---|
| `ticket-108/s1` | aucun fichier ne porte la liste ; 15 heredocs de prose vus, 0 liste | **identique** : `vendor/rogue` nommé et repris, 15 heredocs ouverts, 0 liste réécrite |
| `ticket-110/s1` | 82 appels, 0 ligne, fd 0 = `/dev/null` | **identique** : 82 appels, 0 ligne, 82 fois `tCHR` |
| `ticket-110/s2` S2 | 279 appels, 0/40 | **identique** : 279 appels, 0/40 |
| `ticket-110/s2` S3 | 0 ligne lue, « left 2 where they were » | **identique** |
| `ticket-110/h1` | 11 verbes lancent le fsmonitor | **identique** (git 2.54.0 Apple Git-157) |
| `ticket-110/h2` | `--no-index` : programme non lancé, réponse du témoin propre | **identique** |
| `ticket-100/p2` | exit 4, règle remise, refus du scope-guard porte le finding | **identique** : règle absente (`0`), `moved the ignore frontier in .git/info/exclude … (put back)` dans le refus |
| `ticket-109/q1` Q1 | les deux règles remises, phrase neuve | **identique** (« every movement this run recorded ») |
| `ticket-109/q1` Q2 | chemin crash : finding nommé, règle remise, aucune règle d'arbre | **identique** |
| `ticket-109/q1` Q3 | `manifest is rewritten` + `attributes is gone`, rien remis, règle survit (aveu) | **identique** |
| `ticket-109/q1` Q6 | chaque témoin du run disparu nommé, règle survit (aveu) | **identique** |
| `ticket-109/q4` Q4 | les trois sources remises et nommées | **identique** (`exclude`, `.git/info/attributes`, `diff.evil.textconv`) |
| `ticket-109/q4` Q5 | remis ; `02-beta` reçoit la phrase neuve | **identique** |
| `passe-16-10/g1` | (sur l'ancien `main` : 136 lancements, 166 lignes drainées) | 291 lancements, **0 ligne** |
| `passe-16-10/g4` | (sur l'ancien `main` : `vendor/rogue` non nommé avec le plant) | témoin et plant : `vendor/rogue` **nommé et repris**, 0 ligne drainée |

Défauts d'instrument relevés, pas du pack :

- `ticket-108/s1`, cas témoin `S1t` : sans espion, la sonde lit `spy.seen` quand même
  (`No such file or directory`) et imprime une liste vide. Le verdict du témoin est lisible
  au-dessus.
- `ticket-110/s1` et `s2` impriment `0` deux fois : le `grep -c … || echo 0` du piège de
  [110] (grep imprime 0 **et** sort en 1).
