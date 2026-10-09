# Rejeux de la passe transversale du 09/10/2026

Aucune sonde neuve : la passe a **rejoué** sur `main` à `1907f9d` les sondes « run
réel » des cinq tickets livrés depuis celle du 29/09. Ce sont des instruments
(chaque cas finit par `set -e; false`), hors du verdict des deux gates. Les
commandes, dans l'ordre où elles ont tourné (environ 40 s par cas, une passe
complète ≈ 15 min) :

    bash test/run.sh .scratch/ralph-pack/sondes/ticket-98/f2-le-canal-herite.bats
    bash test/run.sh .scratch/ralph-pack/sondes/ticket-98/f3-la-fenetre-de-creation.bats
    bash test/run.sh .scratch/ralph-pack/sondes/ticket-98/f4-le-curlrc.bats
    bash test/run.sh -f 'C2b|C3|C4' .scratch/ralph-pack/sondes/ticket-102/h4-le-hook-configure.bats
    bash test/run.sh .scratch/ralph-pack/sondes/ticket-104/g1-qui-tient-encore.bats
    bash test/run.sh .scratch/ralph-pack/sondes/ticket-105/t1-la-commande-du-jeton.bats

## Verdicts

| Sonde | Garantie | Rendu sur `main` | Verdict |
|---|---|---|---|
| `f2` L1 | [101] la session jugée ne tient rien au-dessus de 2 | 3 sondages, aucun descripteur écrivable, aucune ligne forgée, `rc=0` | tient |
| `f2` L2 | [101] la `TEST_CMD` du projet non plus | idem | tient |
| `f2` L3 | [102] un hook du répertoire commun ne tourne pas pour le pack | `hook runs: none` | tient |
| `f3` W1 | [103] un canal ouvert pendant qu'il a un nom n'est jamais servi | 12 fenêtres gagnées, **0 ligne forgée**, `rc=4` | tient — et le `4` est le reste écrit de [103] (un déni, pid dit), hérité par [98] |
| `f4` C1/C0 | [105] un `~/.curlrc` de session ne fait rien écrire au curl du pack | 36 appels, 0 ligne forgée, `resolved` ; témoin identique | tient |
| `h4` C2b | [104] hook configuré planté pendant le gate d'une sœur | 14 exécutions, 0 descripteur, 0 ligne forgée, `rc=0` | tient |
| `h4` C3 | [104] hook configuré dans `~/.gitconfig` | 160 exécutions, 0 descripteur, 0 ligne forgée, `rc=4` (clé non remise, nommée) | tient |
| `h4` C4 | [104] `core.fsmonitor` dans `~/.gitconfig` | 958 exécutions, 0 descripteur, 0 ligne forgée | tient |
| `g1` | [104] qui lance git en tenant 3 et 5 | 958 exécutions, aucune avec un descripteur ouvert | tient |
| `t1` C1 | — (la commande de jeton, non fermée) | 6 exécutions, fd 5 écrit 5 fois, **4 lignes forgées**, `rc=0`, `resolved` | **ouvert → [106]** |
| `t1` C0 | témoin appairé | aucune | — |

Le `rc=4` de `h4` C3/C4 et de `g1` est celui que [104] a mesuré sur la même mise
en scène (deux tickets, une clé de `~/.gitconfig` que rien ici ne remet) ; il ne
dit rien de la garantie rejouée, qui porte sur les descripteurs.
