# 103 — Un canal délié a une fenêtre de création, et un survivant qui boucle la gagne

**What to build:** Qu'aucun process extérieur à la descendance du shell qui ouvre un canal délié ne puisse obtenir un descripteur sur son fichier — y compris dans l'instant où ce fichier a encore un nom — ou que chaque canal refuse de servir quand quelqu'un d'autre le tient. Aujourd'hui un process laissé par la session, qui boucle sur `$TMPDIR` sans dormir, ouvre le fichier du reçu à chaque itération et y écrit ce qu'il veut.

**Blocked by:** None

**Write-surface:** `.claude/lib/receipt.sh`, `.claude/lib/gate.sh`, `.claude/lib/lenses.sh`, `.claude/lib/proc.sh`, `test/receipt.bats`, `test/gate.bats`, `test/lenses.bats`, `test/proc.bats`, `test/canary.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** needs-triage

- [ ] **Les trois canaux existants sont tenus** : le reçu (`receipt_open`, [96]), les notes du gate (`gate__notes_open`, [94]) et le prompt d'une lentille (`lenses__prompt_open`, [94]). Les trois font `mktemp` → `exec N>… M<…` → `rm -f`, et le nom existe pendant tout cet intervalle, dont un `rm` **externe** (fork + exec, une ou deux millisecondes).
- [ ] **Une seule forme pour les trois**, et pour le quatrième que [98] ouvrira : un ouvreur partagé (probablement dans `proc.sh`, à côté de `proc_exec_bare` de [101]), pas trois corrections parallèles.
- [ ] **La sortie est instruite et mesurée, pas supposée.** Pistes, dans l'ordre où elles ont été pesées en l'ouvrant :
  - un **contrôle après le délien** — le fichier est encore vide, et personne d'autre ne le tient (`lsof` sur darwin, `/proc/*/fd` sous Linux) — avec un refus et une réouverture, et une phrase quand ça arrive. Le contrôle est décisif au moment où il est posé : sans nom, plus personne ne peut ouvrir le fichier (hors `/proc`), donc l'ensemble des détenteurs est fixé. Coût : un `lsof` par ouverture, à mesurer ;
  - un **répertoire non listable** créé d'un coup (`mkdir -m 0300`) avec un nom de fichier imprévisible dedans : arrête le survivant générique (celui qui globbe et ouvre), **pas** celui qui connaît le pack — le même utilisateur peut `chmod u+r` et lister dans la fenêtre ;
  - raccourcir la fenêtre ne ferme rien : un survivant qui boucle la gagne dès qu'elle existe.
  Ce qui a été écarté en l'ouvrant, à ne pas re-sonder sans dire ce qui a changé : un **tuyau anonyme** (bash 3.2 n'a ni `coproc` ni `{fd}>`, un relais à deux tuyaux sans nom ne se câble pas, et un `read` sur un tuyau vide bloque là où les lecteurs actuels lisent jusqu'à la fin d'un fichier) ; un **mode de fichier** ou une **ACL** (le survivant est le même utilisateur).
- [ ] Le **`skip` du canari** posé par [101] est levé : `test/canary.bats`, « a process the judged session left behind cannot open a channel in the instant it has a name ». Son survivant est celui de la sonde `f3` : il boucle sans dormir et garde ce qu'il ouvre.
- [ ] Les **phrases** qui disent le contraire sont corrigées ou retirées : la phrase de provenance que le reçu imprime (« Assembled nowhere a name reaches », qui porte depuis [101] l'aveu de cette fenêtre), l'en-tête de `receipt.sh`, les commentaires de `gate__notes_open` et de `lenses__prompt_open` (« for the few microseconds the name exists »), et les lignes 35 et 65 du tableau.
- [ ] Témoin appairé ; une entrée de mutation par garantie livrée, dont une qui fait disparaître le contrôle en laissant l'ouverture intacte.

## Comments

- **Ouvert le 29/09/2026 en livrant [101]**, par le **second** `run.sh` complet de [101] : le test de [96] « a process the session left behind finds no workspace to forge » a rougi sur `refute_file_exists receipt.saw`, sur une ligne que [101] n'avait pas touchée. Le premier `run.sh` et les rejeux isolés étaient verts. **Un test instable qui mesure quelque chose que personne d'autre ne mesure** (pièges de harnais, [38]) : son survivant dormait 10 ms entre deux regards et tombait de temps en temps dans la fenêtre. File revalidée par Philippe le même jour : **[101] → [102] → [103] → [98] → [99] → [100]**, arête **103 → 98**.

- **Mesuré** (`../sondes/ticket-98/f3-la-fenetre-de-creation.bats`) : un survivant qui boucle **sans dormir** sur `"$TMPDIR"/ralph-receipt.*`, ouvre ce qu'il trouve par `exec 7>>"$d"` et écrit ensuite toutes les 50 ms sur ce descripteur. Sur les libs de `main` (`b6f9079`) : **12 fenêtres gagnées sur 12 ouvertures, 270 lignes forgées dans le reçu**. Sur la branche de [101] : 12 et 341. Le test de [96] ne mesurait qu'un échantillon de ce trou, au hasard.

- **Ce que [101] a fait du test de [96], pour que le gate soit déterministe sans cacher le trou** : son survivant ne compte plus un nom que s'il est encore là au regard suivant, une demi-seconde plus tard. C'est exactement ce que [96] a livré (aucun nom ne *persiste* : l'ancien espace de travail, ou un fichier jamais délié, le sont toujours ; une fenêtre de création ne l'est jamais), et l'entrée de mutation « 96 the evidence is in a place again » le fait toujours rougir. La fenêtre elle-même est tenue par le `skip` du canari, la phrase du reçu, l'en-tête de `receipt.sh` et le tableau — **jusqu'à ce ticket**.

- **Pourquoi avant [98]** : le canal du slot reprend le même motif — un fichier ouvert deux fois puis délié, par le pilote, avant le fork. Il aurait la même fenêtre, et un survivant d'une itération précédente (ou d'une nuit précédente : [92] écrit qu'un survivant qui ignore le signal reste) la gagnerait à chaque itération. Réparer l'ouvreur d'abord évite de le reprendre.

- **Ce que ce ticket ne ferme pas, et qui reste écrit ailleurs** : sous Linux, `/proc/<pid>/fd/N` rouvre un fichier délié pour tout process du même utilisateur, **après** le délien aussi — non mesuré ici (darwin), borne de plateforme écrite par [101] ; et un hook git lancé par le pack tient les descripteurs de qui l'a lancé → [102].
