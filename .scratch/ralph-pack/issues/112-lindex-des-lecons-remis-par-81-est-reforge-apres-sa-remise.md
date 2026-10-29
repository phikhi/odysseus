# 112 — L'index des leçons remis par [81] est reforgé après sa remise, jusqu'à `LEARNINGS.md`

**What to build:** Que l'index des leçons du run (`$RALPH_RETRO_STATE/index`) — inliné dans le prompt de toute session fraîche et du rétro, et recopié dans `LEARNINGS.md` à chaque leçon publiée — ne puisse plus être réécrit par un process extérieur à la descendance du pilote **après** la remise de [81], ou que le run dise que ce qu'il sert et publie n'est pas ce qu'il a remis. Aujourd'hui la remise est un instant : `retro_index_note` compare et remet une fois, au retour de la session de livraison, et tout ce qui suit lit le fichier nommé.

**Blocked by:** None

**Write-surface:** à fixer au tri. Pressentie : `.claude/lib/retro.sh`, `.claude/loop.sh`, `test/retro.bats`, `test/canary.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** needs-triage

- [ ] À écrire au tri. Ce que la mesure exige déjà : le prompt du rétro, celui de la livraison suivante et `LEARNINGS.md` ne portent pas l'entrée d'un survivant qui l'**ajoute à l'index tant qu'elle manque**, à `MAX_PARALLEL=1`, témoin appairé compris.

## Comments

- **Ouvert le 29/10/2026 au tri de [111]**, décision de Philippe (« ouvrir [112] needs-triage », plutôt que le plier dans [111] ou l'écrire seulement au tableau). [111] ferme le **fichier** du prompt ; l'index est une **source** que ces prompts inlinent, et un objet d'une autre forme : un état que le run **republie** et partage entre forks, pas une entrée écrite une fois et lue une fois.

- **Mesuré** (`../sondes/triage-111/q1-ce-que-lisent-les-juges.bats`, cas Q2, `main` à `7c25302`) : deux tickets, `RETRO=on`, le rétro répond une leçon. Le survivant, planté par la première livraison, ignore `TERM` et ajoute sous `## Working set` une entrée `- LR-0999 x1 learning-records/0999-forged.md — FORGED-INDEX …` tant qu'elle manque. Résultat :
  - le run dit une fois, à l'itération 1, *« the lesson index … is not the copy this iteration was handed — put back »* ;
  - le survivant rajoute sa ligne aussitôt après ;
  - l'entrée forgée arrive au **rétro 1**, à la **livraison 2** et au **rétro 2** (stdin des appels 3, 4 et 5) ;
  - elle finit dans **`LEARNINGS.md`** du projet. `retro__record_lesson` lit les entrées de l'index, et `retro__publish` le réécrit puis le recopie : **aucun modèle n'a eu à obéir à quoi que ce soit** ;
  - l'itération 2 prend la copie forgée pour la sienne (`retro_hold_index`), donc rien d'autre n'est dit. Run sorti `0`.

- **Ce que le tableau dit, et ce qu'il ne dit pas.** La ligne « Une leçon injectée dans le prompt d'une session vient de cette boucle » écrit deux limites à la remise de [81]. Au-dessus de `MAX_PARALLEL=1`, l'index est nommé et jamais remis. Une itération tuée entre sa session et la comparaison le laisse tel quel. Celle-ci n'y est pas : à `MAX_PARALLEL=1`, une réécriture **après** la remise. La phrase *« put back »* est même ce qui la cache : un humain qui la lit au matin conclut que l'index a été tenu.

- **Pourquoi ce n'est pas [111]** : `LEARNINGS.md` est la sortie la plus durable du pack (lue par toute session de tout run suivant, sans commit, ligne « Un artefact que le pack écrit lui-même… »), et ici aucun modèle n'est dans la chaîne. Le pack recopie lui-même ce qu'il lit. La réparation touche au partage entre itérations : un frère qui publie une leçon pendant qu'une autre itération tourne déplace l'index **légalement** ([81], [13]). Ce n'est pas un canal écrit une fois et lu une fois.

- **Pistes, à trancher au tri et pas avant** :
  - la copie servie dans une **variable du pilote**, que les itérations héritent au fork. Une leçon publiée remonterait au pilote par le canal de réponse de [98]. Qu'est-ce qu'un frère déjà lancé voit alors ? Il ne voit pas la leçon de l'autre, et c'est déjà le cas d'un prompt écrit avant elle ;
  - un **canal délié tenu par le pilote** et hérité par les forks. Il faut des numéros dans **tous** les shells du run, alors que 3–10 sont pris et 11–254 sont au pilote (recensement au-dessus de `LOOP_SLOT_FD`) ;
  - **comparer** à chaque lecture et non une seule fois. C'est le même TOCTOU que la spec de [111] tant que la lecture et la comparaison sont deux instants.

- **Ce qu'il hérite de [111] s'il est livré après** : le prompt de chaque session sans nom au spawn, et un recensement des descripteurs déjà mis à jour. Si [112] prend un descripteur, c'est là qu'il s'écrit.
