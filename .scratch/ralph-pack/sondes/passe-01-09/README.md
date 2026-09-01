# Sondes de la passe transversale du 01/09/2026

Des **instruments**, pas des tests. Chacune se termine par un `set -e; false`
volontaire : elle rougit toujours, et ce qu'on lit est ce qu'elle imprime avant.
Elles ne sont pas dans `test/` et `test/run.sh` sans argument ne les ramasse pas —
elles ne doivent jamais compter dans le verdict des deux gates.

Les faire tourner, une par une ou par nom :

    bash test/run.sh .scratch/ralph-pack/sondes/passe-01-09/q2-l-arbre-juge-est-vide-quand-un-fichier-est-illisible.bats
    bash test/run.sh -f Q1b .scratch/ralph-pack/sondes/passe-01-09/q1-le-chemin-approuve-que-le-commit-durable-na-pas-pu-stager.bats

Elles pilotent le pack tel qu'il est livré ; aucune n'édite `.claude/` ni
`test/`, et aucune n'a besoin d'une mutation appliquée à la main. La passe qui
les a écrites est dans `../../passe-transversale-01-09.md`.

| Sonde | Ce qu'elle demande | Verdict, mesuré le 01/09/2026 |
|---|---|---|
| `q2` Q2a | `gate_tree_snapshot` sur un arbre portant un fichier illisible | l'arbre jugé rendu **rc=0** avec 24 entrées, **toutes sous `.claude/`**, contre 26 sur HEAD — tout le reste a l'air supprimé |
| `q2` Q2b | témoin appairé, tout lisible | 27 entrées |
| `q2` Q2f | `gate_tree_snapshot "no/such/path"`, la branche dont le commentaire décrit le refus | **l'arbre vide** (`4b825dc…`) avec **rc=0** : le refus documenté n'existe pas |
| `q2` Q2g | un fichier de ticket illisible, vu par `failures_tracker_tree` | arbre vide, et `diff-tree` marque **`D` sur les deux** tickets — la panne de [49] par l'autre bout |
| `q2` Q2c | run réel, write-surface étroite | 3 itérations `scope=red` accusant `wrote CONTEXT.md`, budget brûlé, `failed-impl` ; livraison réelle jamais jugée ; **0 ligne nomme la cause** |
| `q2` Q2d | témoin appairé, sans le `chmod` | vert, `resolved`, HEAD bouge |
| `q2` Q2e | le même défaut sous une surface qui couvre tout | **`resolved`, HEAD n'a pas bougé, la livraison n'est nulle part** — le faux livré de [35] par une autre porte |
| `q1` Q1a | un commit humain sur la branche pendant l'itération, `MAX_PARALLEL=1` | `folded onto the branch over a sibling's commit` — le rejeu est atteint au défaut, et il n'y a aucun frère |
| `q1` Q1b | plus le chemin livré rendu illisible après l'arbre jugé | `could not be staged`, puis `src/shared.txt` **absent de `HEAD`** et **absent de l'arbre** : le commit de l'humain détruit par le fold |
| `q1` Q1c | témoin appairé, sans le refus de staging | le fichier survit sur `HEAD` |
| `q3` Q3a | `Failures: 9` écrit sur un ticket **voisin** de la frontière | 0 mention au drain ; run AFK : **1** itération et escalade immédiate |
| `q3` Q3b | témoin appairé | **3** itérations, budget complet |
| `q3` Q3c | `Failures:` écrit sur **son propre** ticket | la session suivante sur le même ticket est ouverte au guichet **`triage-host`** au lieu d'`admit` ; 0 mention |
| `q3` Q3d | le **corps** d'un ticket voisin | la ligne injectée arrive **verbatim dans le prompt** de la session suivante ; 0 mention |
| `q3` Q4 | un `needs-triage` tiré vers le puits avec `Escalation: sign-off` | nommé au drain 1 ; le **drain 2** épingle la raison depuis le fichier, offre `desk: approve`, `s` → **`resolved`** |
| `q3` Q5 | un `claimed` d'un run mort résolu par une session | nommé une fois, puis run AFK `exit 5` : le balayage de [12] ne relit pas un résolu |
| `q7` Q7a | ce que la session routée reçoit du paragraphe de [58] | « took every ticket's **_ and _** before this session started » — les deux noms de champ manquent, et deux `command not found` à l'écran de l'humain |
| `q7` Q7b | le **corps** passe-t-il par cette même expansion ? | **non** — `` `id -u` ``, `$(id -u)` et `$HOME` arrivent verbatim. **Angle disculpé** : pas d'injection de commande depuis un ticket |
| `q8` Q8a | la session routée éteint le gate, l'humain **quitte**, run à la main | un **autre** ticket sort `resolved` à la première itération, gate vert ; le drain nomme le fichier, **le run non** |
| `q8` Q8b | témoin appairé | 3 rouges, run stérile |

## Pièges rencontrés en les écrivant

**Une session qui n'écrit rien mesure `delivery=red` et pas le budget de
retries.** Le `script_claude` d'une phase de drain **survit** à la phase suivante :
il faut `rm -f "$SHIM_STATE/claude.script"` avant le `run_loop` pour retrouver le
faux qui **livre**, sans quoi le run sort `nothing-delivered` et ne mesure rien de
ce qu'on croit ([35]).

**Un répertoire en mode 000 n'est pas la même panne qu'un fichier en mode 000.**
Le fichier fait échouer `git add -A` **entier** (rc=128, index vide) ; le
répertoire rend **rc=0** avec un simple `warning: could not open directory` et les
chemins dessous manquent silencieusement. Deux modes de panne, un seul attrapable
par un code de retour.

**Une backtick dans un heredoc non cité est une substitution de commande**, y
compris dans un paragraphe de prose destiné à un modèle — et le résultat d'une
substitution, lui, n'est **pas** re-analysé. Les deux moitiés de cette phrase
décident si une trouvaille est une faute de frappe ou une injection.

**Le rôle d'un `TEST_CMD` / `TYPECHECK_CMD` dans une sonde est un rôle.** Les
deux tournent dans le fan, donc **après** que [29] a figé l'arbre jugé et
**avant** le commit durable : c'est la seule fenêtre où une sonde peut jouer « la
suite du projet touche un fichier » et « l'humain commite dans un autre
terminal » sans aucune concurrence à monter.

## Les sondes conservées d'avant, rejouées le 01/09

- `../passe-31-08/p1` et `p4` : les réparations de [55] et [57] **tiennent**
  (`Escalation: sign-off` écrit mais ticket laissé `ready-for-human` ; drain
  arrêté `rc=4`).
- `../passe-31-08/p2` : **périmée** depuis [56], comme son ticket l'annonçait —
  le `r` est refusé, le run sort `exit 5` des deux côtés.
- `../passe-31-08/p3` : **périmée elle aussi**, et par un effet que personne
  n'avait écrit : la réécriture de `.claude/ralph.config.sh` salit l'arbre, donc
  le refus de [56] tombe dessus et la réinjection n'a plus lieu. La question
  qu'elle posait est reprise par `q8`, dans le seul ordre qui existe encore
  (l'humain **quitte** le drain).
- `../ticket-55/s1` : **la question est répondue** — [58] restaure, `21-second`
  ressort `ready-for-human` et est nommé quatre fois. Le tableau de son README
  décrit l'état d'avant [58].
- `../ticket-56/s1`, `s2`, `s3` : inchangées, `s3` montre toujours le trou
  résiduel écrit au tableau.
