# Sondes de [110] — le stdin que `proc_git` gardait pour git

Deux familles. **Hors du pack** (`h1`, `h2` : `bash fichier.sh </dev/null`, git 2.54
Apple, darwin) : ce que git fait du stdin quand il lance un `core.fsmonitor`. **Dans
un vrai run** (`s1`, `s2` : `bash test/run.sh <fichier> </dev/null`, ~30–60 s
chacune) : ce que le programme lancé lit d'un run. Instruments, pas tests : chaque cas
finit sur un `false` volontaire.

## Hors du pack

| Sonde | Mesure | Rendu |
|---|---|---|
| `h1` | quels verbes lancent un `core.fsmonitor` global, et lit-il le stdin de git ? | **11 verbes** : `status`, `add`, `rm`, `reset`, `write-tree`, `checkout-index`, `update-index`, `diff`, `diff-tree`, `ls-files`, `check-ignore` — chacun lui donne le stdin de l'appelant, il lit tout (3/3). Pas lancé : `rev-parse`, `cat-file`, `ls-tree`, `config`, `read-tree`. Le ticket en nommait six (« ops d'index ») : une liste de verbes était déjà fausse. |
| `h1` (fin) | `check-ignore --stdin` dans un dépôt **sans index** (la forme du témoin `$pin/rules`) | le programme est lancé quand même, draine les 3 lignes, `check-ignore` répond **vide** |
| `h2` | le même avec `--no-index`, plus un `filter.x.clean/process` global sur `*` | sans le drapeau : 7/7 lignes volées, réponse vide (rc 1) ; **avec** : programme non lancé, réponse identique au témoin propre (`vendor/ a.log sub/deep "caf\303\251.log"`) ; sans plant, avec ou sans drapeau : mêmes réponses |

## Dans le run

| Sonde | Met en scène | `main` (`1f7f1fd`, code de [108]) | Branche de [110] |
|---|---|---|---|
| `s1` | la `g4` de la passe : `GUARDED_PATHS` à 3 répertoires, `core.fsmonitor` planté par la session ; l'espion note le git parent et la nature de son fd 0 | 87 appels, **3 lignes lues — toutes par `git check-ignore --stdin`** (`gate_newly_hidden`, le seul appelant qui pipe), `vendor/` chaque fois ; les 84 autres : fd 0 = `/dev/null` du test (dans un vrai run, le terminal) | 82 appels, **0 ligne**, `vendor/rogue` nommé et repris, tous les fd 0 = `/dev/null` |
| `s2` S2 | une nuit AFK lancée avec **40 lignes** en stdin, `core.fsmonitor` planté par la session | 279 appels, **40/40 lues**, par le `git ls-files --cached --others` d'un pin de frontière | 279 appels, **0/40** |
| `s2` S3 | le **drain** : deux tickets à l'évier, les réponses de l'humain (`n`, `n`, une ligne de plus) en stdin, `core.fsmonitor` déjà dans `~/.gitconfig` | **les 3 lignes de l'humain lues** par un `git -c core.quotePath=false diff…` du dossier ; le drain : « stdin ended — stopping with 20-one where it was », 0 ticket traité | **0 ligne lue** ; le drain reçoit ses deux `n`, « left 2 where they were » |

La réponse à la première question du ticket (« d'où viennent les 3 lignes de `g4`
après [108] ? ») : du **seul git que le pack nourrit**, `check-ignore --stdin` dans
le témoin des règles épinglées — le programme lancé par git lit le même tuyau que
git. Sens mesuré (`h2`, et le test du gate muté sans `--no-index`) : un vol vide la
réponse du témoin, donc **plus** de chemins sont forcés dans le snapshot
(`cache/payload` nommé hors surface) — un rouge, jamais un chemin laissé passer.
