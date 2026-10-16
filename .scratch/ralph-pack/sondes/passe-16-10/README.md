# Sondes de la passe transversale du 16/10/2026

Deux familles. Les **rejeux** des cinq tickets livrés depuis la passe du 09/10
([106], [98], [99], [100], [107]) — instruments existants relancés sur `main` à
`5d4eab9` (code de [107]), chacun finit par `set -e; false`. Et les sondes
**neuves** `g1`–`g4`, qui mesurent la trouvaille (→ [110]).

Lancer : `bash test/run.sh <fichier> </dev/null`. `timeout` n'existe pas ici ;
les sondes neuves tournent ~15–40 s chacune.

## Rejeux — tous tiennent (sauf le résidu déjà ouvert en [109])

Relancés en série depuis le scratchpad. Verdicts :

| Sonde | Garantie | Rendu sur `main` (`5d4eab9`) | Verdict |
|---|---|---|---|
| `ticket-98/f2` L1/L2 | [101] la session jugée et `TEST_CMD` ne tiennent rien au-dessus de 2 | 3 sondages `probed`, 0 ligne forgée, rc 0 | tient |
| `ticket-98/f2` L3 | [102] un hook du répertoire commun ne tourne pas pour le pack | `hook runs: none` | tient |
| `ticket-98/f3` W1 | [103] un canal ouvert pendant qu'il a un nom n'est jamais servi | 12 fenêtres gagnées, **0 ligne forgée**, rc 4 (déni) | tient |
| `ticket-98/f4` C1/C0 | [105] un `~/.curlrc` de session ne fait rien écrire au curl du pack | 36 appels, 0 ligne forgée, `resolved` ; témoin idem | tient |
| `ticket-105/t1` C1/C0 | **[106]** une commande de jeton réécrite ne tient aucun descripteur | 6 sondages, **0 descripteur, 0 ligne forgée**, `resolved` (C0 : 0) | **la trouvaille de [105] est fermée** |
| `ticket-106/s1` C1 | [106] le stdin d'une commande de jeton est `/dev/null` | `drained` **vide**, tickets 9 et 10 `ready-for-human`, quarantaine nomme les deux | tient |
| `ticket-106/s1` C2b/C3 | [107] la commande de jeton est bornée | C2b 9 s (tuyau), C3 `sleep 20` < borne 30 s → 30 s (servie, sous la borne) | cohérent |
| `passe-29-09/q1` Q1a–Q1g | **[98]/[99]** plus de `$slot`, un run mort sort décidé | pas de `rm -rf "$slot"`, rc 0 ou 4, **0 forge**, 4 tickets résolus | tient |
| `passe-29-09/q5` Q5a/Q5b | **[100]** un manifeste/pin forgé ne fait pas survivre la règle | Q5a `resolved` règle 0 ; Q5b **exit 4**, `manifest is rewritten`, règle 0 | tient |
| `ticket-100/p1` P1a/P1b | [100] `ledger-seen` forgé n'efface pas la part | P1a `resolved` ; P1b **exit 4**, `ledger-seen is rewritten` | tient |
| `ticket-100/p2` P2 | — (témoin détruit, hors [100]) | exit 4, `attributes is gone`, **règle survit** | **déjà ouvert → [109]** |

## Sondes neuves — la trouvaille (→ [110])

Le stdin que `proc_git` garde pour git ([104] ferme 3..255, garde fd 0 car git le
lit) atteint le programme que git lance (un `core.fsmonitor` écrit par la session).
Dans une boucle `while read … <<LIST; do proc_git <op d'index>`, ce stdin est le
reste de LIST.

| Sonde | Met en scène | Rendu | Verdict |
|---|---|---|---|
| `g1` | `core.fsmonitor` global, une nuit | le programme tourne **136×**, **draine 166 lignes** du stdin de git (`.claude/settings.local.json`, `CLAUDE.md`, `learning-records`…) | le trou est **vif dans le pack** |
| `g2` | les 7 fichiers scellés + le plant | le sceau refuse **7/7** même avec 175 lignes drainées | le **sceau tient** (indépendant du force-staging ; lignes 1-2 toujours stagées) |
| `g3` | `GUARDED_PATHS` à 2 entrées, write sous la 2e | `vendor/rogue` repris (50 drainées) | la 2e ligne tient (le drain commence après la 2e) |
| `g4` | `GUARDED_PATHS` à **3** entrées, write sous la 3e | témoin : `vendor/rogue` **nommé** hors-surface ; plant : **plus nommé** — garde de portée **défaite** sur la 3e ligne | **la garde de portée saute** ; nuit rouge seulement parce que **[46]** attrape `core.fsmonitor` |

Le drain commence une itération après la 1re (le 1er `git add` établit le token
fsmonitor sans l'interroger, le 2e draine tout le reste d'un coup) : lignes 1-2 de
`<<FORCED` toujours force-stagées, 3+ sautées. Par défaut 3+ = chemins scellés
(couverts par le sceau) ; un projet qui garde ≥ 3 répertoires expose le 3e. La nuit
reste tenue par [46] (toutes les clés que git exécute sont dans `gate_config_keys`)
— le force-staging est tenu par une **liste**, pas par lui-même.

Hors pack : `scratchpad/fsmon/probe2.sh` (déterministe, `SENTINEL-line-b/c` avalés).
