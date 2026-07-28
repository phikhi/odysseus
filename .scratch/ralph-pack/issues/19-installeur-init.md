# 19 — Installeur `init.sh` + wizard `npx`

**What to build:** Le dépôt du pack **en une commande** dans n'importe quel repo (vierge ou existant) : validation des préconditions, merge du `CLAUDE.md`, copie du substrat pinné, provisionnement des dossiers durables — le dépôt passe de « rien » à « prêt à discovery ».

**Blocked by:** 01

**Write-surface:** `init.sh`, `package.json`, `bin/**`, `test/install.bats`

**Status:** ready-for-agent

- [ ] `init.sh` (déclenché par un wizard `npx`) est **idempotent** et fonctionne dans un repo vierge comme existant ; il s'auto-supprime après bootstrap.
- [ ] Il pose l'arborescence du pack, provisionne `.scratch/` et les dossiers durables (`docs/adr`, `docs/playthroughs`, `receipts`), et écrit un `ralph.config.sh` de départ si absent.
- [ ] Un `CLAUDE.md` existant est **mergé** (append d'un bloc), jamais écrasé ; absent → créé.
- [ ] Le substrat est **copié** (vendoré, pinné à une version), self-contained pour la sandbox.
- [ ] La validation des préconditions (projet git, endpoint d'usage, commandes test/typecheck) rapporte clairement si le projet est broyable ; le moteur reste **bash pur** (fallback sans node).

## Comments

- **Contrainte posée par [05] et par la revue de [01]–[04] : ce que l'installeur doit désormais garantir pour qu'un premier run démarre.** La boucle refuse maintenant de démarrer (exit 2) sur `FEATURE` vide, sur un `FEATURE` qui ne désigne aucun tracker, sur `TEST_CMD` vide, sur `TYPECHECK_CMD` vide (`none` est la façon explicite de déclarer qu'il n'y en a pas) et hors dépôt git. C'est exactement la liste que la validation des préconditions doit couvrir — et la confirmation forcée doit porter sur le *contenu* des commandes, pas seulement sur leur présence : `TEST_CMD="true"` passe tous les contrôles automatiques du pack et rend le gate vert sans rien prouver. Aucun code de retour ne peut attraper ça ; seul l'humain, au moment de l'install, le peut.
- L'installeur doit provisionner `.scratch/<feature>/` : la boucle ne le crée plus toute seule (une faute de frappe créait un tracker fantôme et le run sortait en succès).
- À ajouter au `.gitignore` du projet cible : `.scratch/*/run.log`, `.scratch/*/.run.lock/`, `.scratch/*/.session.*.jsonl`. Sans ça, le commit-sur-vert de [07] embarquera le journal et le flux de session dans l'historique du projet.
- **Contrainte posée par [07] : le `.gitignore` du projet cible n'est plus cosmétique.** La boucle **commite** maintenant chaque itération verte et déplace `HEAD`. Le commit ne contient que les chemins approuvés par le scope-guard (le `.scratch/` en est exclu par construction), donc le journal et le flux de session n'entrent pas dans l'historique — mais `gate_tree_snapshot` fait un `git add -A` dans un index jetable **deux fois par itération**, ce qui écrit un blob pour chaque fichier non suivi et non ignoré, flux de session de plusieurs Mo compris. Sans les entrées `.gitignore` (`.scratch/*/run.log`, `.scratch/*/.run.lock/`, `.scratch/*/.session.*.jsonl`), un run AFK grossit la base d'objets du projet à chaque itération.
- Nouvelle clé de config à provisionner : `GATE_TIMEOUT` (défaut 1800 s, `0` = pas de délai). Pas de confirmation forcée — un délai absent ne produit pas de faux vert, il fait pendre le run.
- Un run laisse maintenant des branches `failed/<ticket>` dans le dépôt cible. À mentionner à l'installation : ce sont des artefacts de la boucle, pas des branches de travail.
- **Constat vérifié en livrant [07] : l'installation documentée dans le README dépose 22 liens symboliques cassés.** `cp -R .claude .` — la marche à suivre actuelle, faute d'installeur — copie `.claude/skills/`, dont les 22 entrées sont des liens vers `../../.agents/skills/…`, qui n'existe pas chez l'hôte. Vérifié : le lien ne résout pas après copie. Deux décisions à prendre ici : ce qui constitue le pack déposé (aujourd'hui le harnais de test copie `loop.sh`, `ralph.config.sh.example`, `settings.json`, `human-loop.sh` et `lib/*.sh` — rien d'autre, et c'est la définition de fait), et si les skills du dépôt doivent être déposés, auquel cas il faut copier les cibles et non les liens (`cp -RL`).
- **Contrainte posée par [21], et une confirmation forcée de plus.** Ce n'est plus seulement la base d'objets qui grossit : sonde du 28/07/2026, une session qui fait `git add -A` laisse `.run.lock/pid`, `.run.lock/since`, `.session.<pid>.jsonl` (jusqu'à des dizaines de Mo), son `.prompt` et son `.tokens` **dans l'index du projet cible**, prêts à partir avec le prochain commit d'un humain. La protection du tracker de [21] désindexe `issues/` seulement, et ne peut pas faire plus : le flux de session s'écrit *pendant* la fenêtre qu'elle surveille. Les entrées `.gitignore` sont donc le seul mécanisme qui ferme ça, et l'installeur est le seul endroit qui peut les poser. Le test `a tracker the session staged does not stay staged` (`test/failures.bats`) pin l'état actuel des **deux** côtés — le ticket désindexé, le flux encore stagé — précisément pour qu'il rougisse le jour où ce ticket provisionne le `.gitignore` : le faire passer au vert *en changeant l'assertion* fait partie des AC d'ici.
