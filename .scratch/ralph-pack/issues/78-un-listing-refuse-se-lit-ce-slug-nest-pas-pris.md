# 78 — Un listing refusé se lit « ce slug n'est pas pris »

**What to build:** Que `forge__slug_taken` cesse de lire un refus de listing comme une réponse, pour que `forge_open_unique` n'ouvre pas un doublon à chaque run d'un dépôt que le plafond de pages refuse.

**Blocked by:** None

**Write-surface:** `.claude/lib/forge.sh`, `test/tracker-remote.bats`, `test/mutate.sh`

**Status:** ready-for-agent

- [ ] Un listing que l'adaptateur a refusé ne fait pas répondre « ce slug est libre » : `forge_open_unique` refuse plutôt que d'ouvrir.
- [ ] Le refus se voit — un appelant qui ouvre un ticket unique sait que rien n'a été ouvert et pourquoi, sans lire un compteur.
- [ ] `open_unique` garde exactement son comportement quand le listing répond : ouvre si le slug est libre, n'ouvre rien s'il est pris, et n'écrit rien de plus au registre de [13].

## Comments

- **Trouvé en livrant [76] (08/09/2026), laissé de côté par [74] (09/09/2026),
  et c'est la même règle que les deux** : un refus n'est pas une réponse ([59]).
  `forge__slug_taken` lit `forge__records` dans un heredoc avec `|| printf ''`,
  donc la liste vide qu'un refus produit se lit « aucun ticket ne porte ce slug »
  et `forge_open_unique` ouvre. Le garde de [47] — la question et l'écriture du
  même côté d'un verrou — tient toujours ; ce qui ne tient pas est la question.

- **Pourquoi ça compte plus depuis [76]** : le refus n'a plus besoin d'une panne.
  `forge__listing` refuse quand il atteint son plafond (`FORGE_PAGES`, 20, sur des
  pages de `FORGE_PAGE`, 100), donc un dépôt de plus de 2 000 issues refuse
  **tous** les listings, à tous les coups. Chaque `retro-*` et chaque
  `capability-*` censé être ouvert une seule fois est alors rouvert à chaque run,
  sur le tracker d'un humain, sans qu'aucune ligne ne le dise.

- **Ce que [74] a livré et qui sert de précédent** : deux codes de retour de
  l'interface, lus, sans que rien n'apprenne ce qu'est un backend — le statut du
  listing sort du heredoc (`x="$(…)" || return 1`), et l'appelant décide. Ici
  l'appelant est dans l'adaptateur, donc la décision est locale : `open_unique`
  n'a pas de canal pour dire « je n'ai pas pu savoir », et sa signature dit
  qu'un id vide veut dire « déjà pris ». Ne pas confondre les deux est la
  question de conception du ticket, pas un détail d'implémentation.

- **Le piège du harnais**, mesuré par [74] : le faux forge sert de vraies pages, et
  `FORGE_PAGE`/`FORGE_PAGES` sont des clés déclarées, donc désarmées par
  `harness__clear_env`. `set_config FORGE_PAGE 2` + `set_config FORGE_PAGES 1` avec
  deux issues suffit à faire refuser **tous** les listings d'un run, ce qui est la
  façon la moins chère de mettre en scène ce défaut sans simuler de panne.

## Place dans la file

Pas dans l'ordre validé par Philippe le 08/09/2026 ([74] → [77] → [75] → [73] →
[19]) : ce ticket est né après. Il ne bloque personne et personne ne le bloque ;
il touche `forge.sh`, comme [77], donc le livrer près de lui économise une
relecture du même fichier. À ordonner par Philippe.
