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
