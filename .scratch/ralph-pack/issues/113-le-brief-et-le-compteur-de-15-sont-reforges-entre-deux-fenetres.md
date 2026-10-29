# 113 — Le brief et le compteur de [15] sont reforgés entre deux fenêtres

**What to build:** Que les deux objets que le run crée dans son atelier de leçons **après** le sceau de [81] ne soient plus des fichiers qu'un process peut réécrire entre deux sessions : `brief.<id>`, ce que le gate a dit de la tentative précédente, inliné dans le prompt de la suivante ([14]), et `capability.seen`, le compteur qui décide qu'une capacité est récurrente ([15]). Aujourd'hui [83] les tient par la **fenêtre** d'une session : un recensement pris avant le spawn, comparé juste après. Ce qu'un survivant d'une session précédente écrit **entre** deux fenêtres, aucun recensement ne le voit, et l'itération suivante prend sa forge pour la ligne de base.

**Blocked by:** 112

**Write-surface:** à fixer au tri. Pressentie : `.claude/lib/retro.sh`, `.claude/lib/capability.sh`, `.claude/loop.sh`, `test/retro.bats`, `test/capability.bats`, `test/canary.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** needs-triage

- [ ] À écrire au tri. Ce que la mesure exige déjà : le prompt d'une livraison ne porte pas le brief d'un survivant qui l'**écrit après la fenêtre** de la session qui l'a planté, à `MAX_PARALLEL=1`, témoin appairé compris.

## Comments

- **Ouvert le 29/10/2026 au tri de [112]**, décision de Philippe (« index seul + [113] », plutôt qu'élargir [112] à tout l'atelier ou n'écrire le brief qu'au tableau). [112] ferme l'index ; ce ticket a la même forme, sur les deux objets que [83] tient.

- **Mesuré** (`../sondes/triage-112/q3-le-brief-apres-la-fenetre.bats`, cas P6, `main` à `9731780`). Deux tickets, `RETRO=on`, le rétro répond une leçon. Le survivant, planté par la première livraison, crée `ralph-retro.*/brief.02-beta` une fois `LEARNINGS.md` écrit, donc pendant le rétro de l'itération 1, **après** `retro_state_note` et avant le recensement de l'itération 2. Le prompt de la livraison de 02-beta (appel 4) porte sa ligne sous *« What the gate said about the previous attempt at this ticket »*, alors que ce ticket n'a jamais été tenté. **Aucune ligne au run**, `rc=0`.

- **Ce que [83] écrit, et où c'est faux.** « Rien dans ce pack n'écrit au premier niveau de `ralph-retro.*` entre le premier et le dernier jeton d'une session, donc ce qui y bouge pendant une session a été écrit par elle. » C'est vrai d'une session. Un survivant n'est pas tenu par la fenêtre de qui que ce soit : il écrit **entre** deux fenêtres, là où le pack écrit aussi (le brief est gardé, le compteur appendé, après le gate). La ligne de base de l'itération suivante le prend pour un fait du run. C'est la même faute que l'index de [112] (une comparaison à un instant), sur un objet que [83] a retiré au lieu de remettre.

- **Non mesuré, même forme** : `capability.seen`. Un survivant qui appende une observation après la fenêtre ferait ouvrir par la branche `recurrent` de [15] une proposition sur le puits humain, ce que le témoin appairé de [83] appelait *« counted, not proposed: 1/2 sighting(s) »*.

- **Piste, à trancher au tri et pas avant** : le mécanisme de [112], réutilisé et non refait. L'état est dans une variable du pilote, héritée au fork, et une itération rend ce qu'elle a produit par la réponse de [98]. Deux différences avec l'index, à mesurer : le brief est **multi-ligne** (ce que chaque branche rouge a dit) alors que `loop__record` aplatit les sauts de ligne ; et le brief vise **une autre tentative du même ticket**, pas toutes les sessions. Si les deux objets quittent les fichiers, `retro_hold_state`/`retro_state_note` n'ont plus d'objet : le recensement de [83] se retire avec sa raison, et ses aveux au tableau (l. 59/64/65 au 13/09) avec lui.

- **Ce qu'il hérite de [112]** : la fonction qui applique une réponse d'itération chez le pilote, la clé `lesson` du protocole de [98], et la règle « une clé, une fois ». Une clé de plus suit la même règle.

- **Ce que [112] laisse ici (livré le 29/10/2026)**, à relire au tri :
  - **Le mécanisme** : l'état dans une variable du pilote (`RETRO__INDEX`), lu une fois à `retro_open`, hérité au fork ; ce qu'une itération produit remonte par `RALPH_RETRO_LESSON` → `loop__answer` (9ᵉ argument) → enregistrement `lesson` de la réponse de [98] → `loop__finish` → `retro_land` (appliquer, publier) ou `retro_strand` (dire ce qui n'est pas appliqué). La fonction qui applique est **pure** (`retro__apply`), appelée par l'itération sur sa copie et par le pilote sur la sienne ; c'est la forme à réutiliser pour `brief.<id>` et `capability.seen`.
  - **La règle « une clé, une fois » a une seconde moitié** : la clé est écrite **à chaque réponse** (`lesson none` quand il n'y a rien). `loop__finish` ne refuse que ce qui est en double ; une clé écrite seulement quand il y a quelque chose à dire est une clé dont un étranger peut être le seul auteur. Mesuré et tenu par `test/retro.bats` (« a lesson a stranger wrote into an answer that had none is refused too ») et par une entrée de mutation. Une clé `brief` ou `capability` suit la même règle.
  - **`loop__record` aplatit** tabulations et sauts de ligne de chaque valeur : le brief, multi-ligne, ne peut pas y passer tel quel. Le champ libre va **en dernier**, et aucun champ ne doit être vide (`proc_split` fusionne deux séparateurs : [112] met `-` pour `supersedes` absent).
  - **Le recensement de [83]** (`retro_hold_state`/`retro_state_note`) tient toujours ces deux objets ; [112] n'y a rien changé, sauf que le sceau de `ralph-retro.*` ne contient plus que `capability.witness` (l'index n'y est plus). Le test « the iteration answers for what the run's seal cannot cover, and for nothing else » scelle désormais un fichier à lui (`kept`). Si ce ticket retire le recensement, cette ligne et les entrées « 83 … » de `test/mutate.sh` le suivent.
  - **Le garde du répertoire** s'appelle `records.guard` (`retro__records_guard`) : il sérialise la numérotation des records et rien d'autre.
  - **Le coût à mesurer pour le brief** : un frère en vol ne voit plus ce que l'autre a publié après son fork ([112] l'écrit au tableau pour l'index). Pour le brief, qui vise une autre tentative **du même ticket**, un même ticket n'est jamais en vol deux fois : à vérifier, pas à supposer.
