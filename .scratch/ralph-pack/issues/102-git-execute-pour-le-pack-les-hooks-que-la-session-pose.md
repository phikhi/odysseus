# 102 — Git exécute pour le pack les hooks que la session pose

**What to build:** Que les appels git du pack ne lancent aucun programme qu'une session a pu écrire dans le répertoire git commun, ou que chacun de ces appels dise ce qu'il lance. Aujourd'hui `$(git rev-parse --git-common-dir)/hooks/` est atteignable depuis n'importe quelle session, rien ne le regarde, et git y exécute des hooks **dans l'arbre de process du pilote et des itérations**, avec leurs descripteurs.

**Blocked by:** None

**Write-surface:** `.claude/lib/gate.sh`, `.claude/lib/concurrency.sh`, `.claude/lib/failures.sh`, `.claude/lib/forge.sh`, `.claude/lib/state.sh`, `.claude/loop.sh`, `test/gate.bats`, `test/concurrency.bats`, `test/failures.bats`, `test/canary.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** needs-triage

- [ ] **Le recensement des hooks que les appels git du pack déclenchent est mesuré, pas raisonné**, verbe par verbe (la règle de [51] : « sonder le verbe, pas la famille »). Déjà mesuré au 29/09 sur git 2.54 : `update-ref` lance `reference-transaction` (commit durable, ref `failed/<ticket>`, fold — `failures.sh`, `concurrency.sh`) ; `git worktree add` lance `post-checkout` (`concurrency_worktree_add`, **dans le pilote**, à chaque itération) ; `git add` **même sous `GIT_INDEX_FILE`**, `write-tree` et `update-index` lancent `post-index-change` (tous les instantanés d'arbre : `gate_tree_snapshot`, les gardes du tracker) ; `git push` lance `pre-push` (`forge.sh`, reçu d'un backend forge). À compléter, et à dériver des appels du pack plutôt que de cette liste.
- [ ] **Ces appels n'exécutent plus un hook posé dans le répertoire commun**, ou chaque exception est écrite avec ce qui la tient. Sortie candidate mesurée : `-c core.hooksPath=/dev/null` éteint `reference-transaction` sur un `update-ref`. À trancher : une option par appel, un `GIT_CONFIG_*` d'environnement (qui atteindrait aussi le git de la session et de la commande de test du projet — ce n'est pas le même geste), ou un témoin sur le répertoire.
- [ ] **La phrase de `gate.sh` qui dit le contraire est corrigée** (`gate_config_keys`) : « `core.hooksPath` does nothing today because `failures_make_durable` commits with plumbing on purpose ». La plomberie ne protège pas : `update-ref` en est, et lance `reference-transaction`. [46] a regardé la **clé** `core.hooksPath` et pas le **répertoire par défaut**, qui n'a pas besoin de clé.
- [ ] La ligne du tableau est écrite. Ce qu'un hook achète n'est pas « exécuter du code » — la session le peut déjà — mais **être un descendant** du pilote ou d'une itération : il tient leurs descripteurs (le canal du reçu de [96], celui de [98]), il échappe au balayage du groupe de la session ([92], [95]), et il survit au run.
- [ ] Témoin appairé (le même run sans hook posé) et survivant réel ; le canari reçoit le cas qui décide ; une entrée de mutation par garantie.

## Comments

- **Ouvert le 29/09/2026 en commençant [98]**, par la question 5 de la DoD posée au mécanisme que [98] devait reprendre. File revalidée par Philippe le même jour : **[101] → [102] → [98] → [99] → [100]**, arête **102 → 98** — sans ce ticket, la ligne du tableau de [98] s'écrirait avec un aveu que [102] réécrirait ensuite. Sondes : `../sondes/ticket-98/` (README).

- **Mesuré dans le vrai pack** (`f2-le-canal-herite.bats`, L3). La session du ticket 01 écrit `reference-transaction` et `post-checkout` dans `$(git rev-parse --git-common-dir)/hooks/` — un chemin qu'un worktree atteint sans rien faire, les refs et les hooks vivant dans le répertoire commun. Ce qui s'en suit, sur un run à deux tickets :
  - `reference-transaction` tourne à chaque `update-ref` du pack — `preparing`, `prepared`, `committed`, et `aborted` sur un fold refusé — avec le **fd 5 de l'itération ouvert** : le bout écrivain du canal du reçu ([96]) ;
  - il écrit `- FORGED-BY-A-HOOK-ON-FD-5` **six fois dans le reçu de 01 et trois fois dans celui de 02**, dont la session n'a rien posé : le hook survit à l'itération qui l'a écrit, et au run ;
  - `post-checkout` tourne au `git worktree add` du ticket 02, dans l'arbre de process du **pilote**.

- **Un fait de plomberie pour la sortie** : `post-index-change` tourne sur un `git add` sous `GIT_INDEX_FILE`, sur `write-tree` et sur `update-index` (mesuré hors du pack) — donc dans les branches du gate qui prennent un instantané, pas seulement dans l'itération. La surface est plus large que les trois appels qui écrivent une ref.

- **Pourquoi avant [98]** : le canal de [98] est tenu par l'itération pendant toute sa vie, et un hook que git lance pour elle en hérite. [101] fait fermer les descripteurs aux deux points où le pack lance un programme étranger ; git n'est pas un de ces deux points — il est lancé partout, par le pack lui-même — et c'est ce qui fait de ce ticket une autre classe et pas un troisième site de [101].
