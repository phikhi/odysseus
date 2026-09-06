# 67 — Le drain raconte le run sur un fichier qu'une session écrit, et journalise sans témoin

**What to build:** Les deux moitiés d'un même fichier. `router_run_notes` tire quatre conclusions de `run.log` sans la réserve que son voisin `router_journal_lines` imprime deux fonctions plus haut, et l'une des quatre est une négation qu'une ligne suffit à faire taire. Et `router_journal` écrit dans le même fichier sans le témoin que `loop_journal_append` tient depuis [10] — alors que ses lignes sont la seule trace de ce qu'un **humain** a décidé.

**Blocked by:** 69

**Write-surface:** `.claude/lib/router.sh`, `.claude/human-loop.sh`, `test/human-loop.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

**Tags:** human-loop, observability, trust-boundary

- [ ] Les quatre conclusions de `router_run_notes` arrivent à l'humain avec la réserve que porte `router_journal_lines` — ou avec ce qui la rend inutile. Ne pas laisser une des deux lectures du même fichier réservée et l'autre affirmative.
- [ ] La **négation** (`budget-wall` sans `successor-armed`/`weekly-pause`/`successor-blocked-*`) cesse d'être un silence qu'une ligne suffit à acheter : soit elle est dite autrement, soit son absence est dite.
- [ ] Le drain tient un témoin de ce qu'il a écrit dans `run.log`, et le dit en fin de drainage quand le fichier ne le porte plus — comme `loop_journal_verify`, et pour la même raison : ces lignes-là sont ce qu'un **humain** a décidé.
- [ ] Le témoin est une variable du process du drain et **jamais un fichier** ([08], [10]) : un fichier serait un fichier que la session routée écrit.
- [ ] Le témoin est écrit en dehors de tout sous-shell — c'est le piège que [10] a payé (« les lignes de reclaim étaient écrites depuis la droite d'un pipeline ») et son test jumeau « un drain honnête ne s'accuse pas » fait partie des AC.
- [ ] Une entrée de mutation par garantie livrée, plus le témoin appairé.

## Comments

- **Trouvé par la passe transversale du 06/09/2026** (`../passe-transversale-06-09.md`, §2 et §3). Sondes : `../sondes/passe-06-09/q2-*.bats` et `q3-*.bats`.

- **Deux lecteurs du même fichier, à deux fonctions d'écart, et un seul porte la réserve.** `router_journal_lines` :

  > That file is under `.scratch/`, which nothing in this pack guards: the session these lines are about could have written them. **Read them, do not rely on them.**

  `router_run_notes` n'en dit rien et affirme quatre choses. L'une est :

  ```sh
  grep -q 'budget-wall' && ! grep -q 'successor-armed\|weekly-pause\|successor-blocked-'
  ```

  dont le commentaire dit *« Nothing in this pack writes that end down as a state »* — cette phrase est le **seul** endroit où cet état est jamais dit.

- **Mesuré** (`q2`), sessions routées réelles dans un drain réel :

  | | |
  |---|---|
  | Q2a — `run.log` portant `budget-wall` seul | la note est dite |
  | Q2b — une session routée ajoute une ligne portant `successor-armed` | `router_run_notes` **rc=1**, la note **disparaît** ; le drain a nommé **0 chemin** |
  | Q2c — témoin appairé, la même session sans la ligne | la note est dite |
  | Q2d — une session routée fabrique `claim-refused` sur un `run.log` **vierge** | le drain suivant dit « the frontier is short of a ticket nothing else would have mentioned » — sur un run qui n'a jamais refusé de claim |
  | Q2e — un run AFK complet passe ensuite sur la ligne fabriquée | run **vert rc=0**, `loop_journal_verify` se tait (**0**), la note est toujours dite après |

  **Q2e est ce qui rend la contrefaçon durable** : le témoin de [10] ne se prononce que sur le **bloc du run courant**, et une ligne écrite *avant* le run entre dans `RALPH_JOURNAL_BASE`. Une ligne posée par un drain est invisible à tous les runs qui suivent — ce n'est pas un défaut de [10], c'est une limite qu'il écrit lui-même (« les lignes des runs *précédents*, qui ne sont pas à ce run de garantir »).

- **Mesuré** (`q3`), la seconde moitié, deux tickets dans le puits :

  | | |
  |---|---|
  | Q3a — l'humain ferme `20-decision` (`c`), puis ouvre une session sur `21-second` qui écrase `run.log` | `20-decision` est **`wontfix`** et **sa ligne `drained` n'existe plus** ; le drain ne se plaint **0** fois, ne nomme **0** chemin |
  | Q3b — témoin appairé, le même écrasement côté AFK | « the run journal does not hold exactly the 2 line(s) this run wrote, where it wrote them: something rewrote … » **plus la copie du run imprimée dessous** |
  | Q3c — témoin appairé, le même drain sans l'écrasement | les deux lignes sont là |

  Les deux points d'entrée donnent des réponses opposées au même événement, et celui qui se tait est celui dont les lignes disent ce qu'un **humain** a voulu. C'est [57] à la lettre, sur un autre objet.

- **Pourquoi le drain n'a rien nommé, et c'est structurel.** `router__tree_dirt` saute `gate_is_bookkeeping`, c'est-à-dire `.scratch/${FEATURE}/`, c'est-à-dire exactement le répertoire de `run.log`. Le garde que le commentaire de `router_desk` nomme pour « ce qu'une session a laissé hors de `issues/` » est aveugle à cette zone par construction. Ce ticket répare le **journal** ; le garde est [66].

- **Ce que le tableau de frontière dit aujourd'hui reste littéralement vrai, et c'est ce qui l'a caché.** La ligne de [10] dit « rien ne le relit pour **choisir ou marquer** ». `router_run_notes` ne choisit rien et ne marque rien : il *raconte*, à l'humain qui va décider. La catégorie n'existait pas quand la phrase a été écrite ; [16] l'a créée. À élargir en livrant plutôt qu'à corriger comme une erreur.

- **Ce qu'il ne faut pas faire, et [10] l'a déjà refusé** : sortir `run.log` de la zone atteignable. C'est le fichier qu'un humain ouvre au matin ; un journal dans `$TMPDIR` est un journal que personne ne lit. Rendre **détectable**, pas inviolable.

- **Contrainte pour [16]** : `human_loop_preflight` est écrit comme *une liste et pas une délégation*. Un témoin ajouté ici ne doit pas devenir un appel à `loop_preflight` par la bande.

- **Piège de sonde.** `grep -c 'journal'` sur la sortie d'un drain compte le libellé du dossier (`journal  its own lines in run.log, below.`) : pour mesurer une plainte, chercher `does not hold exactly`.
