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
