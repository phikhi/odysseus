# Sondes de la passe transversale du 23/09/2026

Des **instruments**, pas des tests. Chaque cas finit par un `set -e; false`
volontaire : ils rougissent toujours, et ce qu'on lit est ce qu'ils impriment
avant. Ils ne sont pas dans `test/` et `test/run.sh` sans argument ne les
ramasse pas — ils ne doivent jamais compter dans le verdict des deux gates.

    bash test/run.sh .scratch/ralph-pack/sondes/passe-23-09/q1-le-flux-dune-lentille.bats
    bash test/run.sh -f Q2d .scratch/ralph-pack/sondes/passe-23-09/q2-ce-que-la-commande-de-test-laisse.bats
    bash test/run.sh .scratch/ralph-pack/sondes/passe-23-09/q3-lenvironnement-de-la-commande-du-projet.bats
    bash test/run.sh .scratch/ralph-pack/sondes/passe-23-09/q4-le-recu-daudit.bats
    bash test/run.sh .scratch/ralph-pack/sondes/passe-23-09/q5-la-classe-dechec.bats

Toutes tournent en 40 s environ par cas. Aucune ne touche `.claude/`, `test/`
ni `init.sh` : **les deux gates n'ont pas été rejoués et la baseline de [93]
tient telle quelle** (`run.sh` 997/0/6 skips, `mutate.sh` 1049/0).

**La mise en scène commune** : un `nohup bash -c '…' &` planté par la session
(via `script_claude`, qui se désarme ensuite — `chmod -x`, `exec claude "$@"`)
ou par `TEST_CMD`, avec `trap "" TERM`. Le `trap` n'est pas une astuce : c'est
**le prix que [92] a écrit** pour `session__sweep` — *« un survivant qui ignore
le signal reste, et il n'y a pas de faucheuse ici »*. La sonde Q2 n'en a pas
besoin du tout : ce qu'elle plante n'est dans le groupe de personne.

---

## `q1-le-flux-dune-lentille.bats` → §1, ticket [94]

Le contrôle de refus de quota d'une lentille (`lenses_refused_posture`) lit
`$dir/lens-<nom>.jsonl`, dans le répertoire `mktemp` du gate. [92] a retiré de
ce répertoire les deux objets qui portaient un verdict — le `.rc` par branche
et le marqueur `timed-out` — et son propre commentaire dit pourquoi le second
comptait : *« a survivor … that dropped a `timed-out` into the gate's directory
would silence the refusal check for the whole fan »*. L'interrupteur a été
fermé ; **la source d'où la réponse est tirée est restée**.

| | Ce que le run fait |
|---|---|
| **Q1a** témoin appairé — lentille `fail`, aucun survivant | 3 tentatives, `Failures: 3`, `ready-for-human`, `escalated:failed-impl`, exit 4 |
| **Q1b** la même lentille `fail`, un survivant réécrit son flux | `Failures:` **vide**, ticket `ready-for-agent`, *« given back with no retry consumed »* à chaque tour |
| **Q1c** lentille **`pass`** (gate vert), le même survivant | *« rolled back 1 path(s) »*, `budget-pause`, **le pilote pause le run**, `sterile run: 3 iterations resolved nothing — stopping`, exit 4 |

Q1c est le cas qui décide du ticket : l'itération était **verte**, son travail est
détruit, le ticket n'est jamais facturé, le pilote croit l'abonnement épuisé, et
la nuit s'arrête. Aucune ligne du run ne nomme quoi que ce soit d'anormal.

## `q2-ce-que-la-commande-de-test-laisse.bats` → §2, ticket [95]

Le porteur. Rien d'hostile : un `&` et un `nohup`, ce que fait tout script qui
monte un serveur avant ses tests.

| | Mesuré |
|---|---|
| **Q2a** `TEST_CMD` laisse un `sleep` | run **vert** (exit 0), ticket `resolved`, process **vivant** à la fin, `ppid 1`, `pgid` = celui du pilote, **aucune ligne** |
| **Q2b** le même, qui liste le répertoire du gate | il voit `tests.out scope.out typecheck.out lang.out` |
| **Q2c** témoin appairé — lentille `pass`, rien de laissé | vert, `resolved`, exit 0 |
| **Q2d** le même run, mais `TEST_CMD` laisse le survivant de Q1 | ticket jamais résolu, travail roulé en arrière trois fois, `sterile run`, exit 4 |

Q2d est Q1c **sans session hostile** : le canal de [94] se joue avec la commande
de test du projet.

## `q3-lenvironnement-de-la-commande-du-projet.bats` → **disculpe**

Ce que `bash -c "$TEST_CMD"` hérite du pilote : 70 variables, dont deux
`RALPH_*` (`RALPH_DIR`, plus `RALPH_SHIM_STATE` qui est du harnais), **aucune
clé de configuration du pack**, et **pas `RALPH_WITNESS_SEAL`**. Le sceau de
[81] tient face à la commande du projet exactement comme face à une session.
C'est aussi ce qui rend une réparation possible pour [94] : une variable non
exportée du shell qui forke est héritée par un sous-shell et jamais par un
`exec`.

## `q4-le-recu-daudit.bats` → §3, ticket [96]

Le reçu se vante, dans son propre texte, de ne pas lire `run.log` *« so the
session this receipt is about can rewrite it »*. Il est assemblé dans un
`mktemp -d "$TMPDIR/ralph-receipt.XXXXXX"` — `facts`, `notes`, `gaps`,
`branch.<nom>` — et `receipt__fact` lit la **dernière** occurrence, donc un
`>>` suffit.

| | Le reçu déposé dans `receipts/<feature>/01-alpha.md` |
|---|---|
| **Q4a** témoin appairé — suite rouge, aucun survivant | `tests=red`, findings `FAIL: 3 of 12 tests failed`, outcome `gate-red` |
| **Q4b** la même suite rouge, un survivant | `tests=green typecheck=green scope=green lang=green`, findings *« the suite passed cleanly on the first attempt »*, outcome **`resolved`** |

Le seul résidu qui trahit en Q4b est `what the loop then did:
escalated:failed-impl`, écrit après la dernière forge — un survivant qui
couvrirait aussi ce fait ne laisserait rien.

## `q5-la-classe-dechec.bats` → §1, ticket [94]

Le troisième objet du répertoire du gate, que la ligne 35 du tableau nomme
depuis [92] sans que personne l'ait mesuré. Témoin appairé : Q4a (même suite
rouge, 3 tentatives, `Failures: 3`, `escalated:failed-impl`, exit 4).

Avec un survivant qui écrit `contract` dans `$dir/scope.class` : **une seule
itération**, `Failures:` vide, `escalated to the human sink (decision)`, run
**exit 0**. Et le journal se contredit sans que personne le remarque :

    ralph: gate: 01-alpha: tests=red typecheck=green scope=green lang=green
    ralph: scope overflow on 01-alpha: contract

`scope=green` et « scope overflow » sur deux lignes voisines.
