#!/usr/bin/env bash
# PROTOTYPE — bootstrap JETABLE. "rien" -> "prêt à discovery" en une commande.
# Usage: cd <projet-cible> && bash init.sh   (idempotent)
set -euo pipefail

PACK_URL="${RALPH_PACK_URL:-https://example/ralph-pack.tar.gz}"  # ou git subtree pinné
echo "▸ Déploiement du pack ralph…"

# 1. Repo git ? (rollback [08] + branches failed/<ticket> l'exigent)
[ -d .git ] || { echo "  git init"; : git init; }

# 2. Poser le pack (COPIE self-contained — pas de symlink, la sandbox doit être autonome)
echo "  .claude/{loop.sh,lib/,skills/,settings.json}  (copie, version pinnée)"
: # tar xzf pack -> .claude/  (skills du substrat COPIÉS)
echo "  docs/agents/{issue-tracker,triage-labels}.md"
mkdir -p .scratch && : touch .scratch/.gitkeep

# 3. CLAUDE.md : MERGE si présent, sinon créer (ne jamais écraser le CLAUDE.md du projet)
if [ -f CLAUDE.md ]; then echo "  CLAUDE.md existant -> append d'un bloc @ralph"; else echo "  CLAUDE.md créé"; fi

# 4. Config de départ, éditable, si absente (le SEUL fichier que l'humain règle)
if [ ! -f .claude/ralph.config.sh ]; then
  echo "  .claude/ralph.config.sh  (valeurs de départ à éditer)"
  : cp .claude/ralph.config.sh.example .claude/ralph.config.sh
fi

cat <<'NEXT'

✓ Prêt à DISCOVERY (HITL). Ensuite, dans l'ordre :
   1) /grilling + /domain-modeling  -> cadrer
   2) /to-spec                      -> spec.md (vérif seams)
   3) /to-tickets                   -> tickets ready-for-agent (approbation = porte [05])
   4) éditer .claude/ralph.config.sh (commandes test/typecheck, modèle, budget)
   5) bash .claude/loop.sh          -> DELIVERY autonome (dans une sandbox !)

(init.sh peut s'auto-supprimer ici — c'est un one-shot de bootstrap.)
NEXT
