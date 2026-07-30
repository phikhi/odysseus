# 15 — Revue de capacités au fil de l'eau

**What to build:** Le pas qui **repère sans créer** une capacité manquante (lentille / agent / skill) en delivery : le retro propose et escalade, jamais d'auto-création — une capacité change le contrat, donc toujours HITL.

**Blocked by:** 14

**Write-surface:** `.claude/lib/capability.sh`, `test/capability.bats`

**Status:** ready-for-agent

- [ ] Détecter ≠ créer : le retro qui repère une lentille/agent/skill manquant ouvre une proposition `ready-for-human`, sans jamais créer la capacité en AFK.
- [ ] La barre de déclenchement est respectée : récurrence **ou** classe non couverte.
- [ ] Réutiliser-avant-créer : la proposition privilégie étendre un brief > réutiliser un skill du substrat > créer neuf.
- [ ] Aucune capacité n'est créée automatiquement pendant un run AFK.

## Comments

- **Contrainte tenue par [31], livré le 30/07/2026 : la dernière AC n'est plus seulement une consigne.** `.claude/agents`, `.claude/commands`, `.claude/skills` et `.claude/hooks` sont scellés — ils entrent dans le snapshot quoi que dise `GUARDED_PATHS`, et **aucune write-surface ne peut les couvrir**. Une session qui créerait une capacité en AFK rougit donc l'itération et se fait rollbacker, au lieu de dépendre de la bonne volonté du modèle. C'était le coût nul de l'élargissement : ce ticket refusait déjà la création autonome, donc sceller ces chemins n'enlève rien à personne.

  Ce que ça change ici : l'AC devient **vérifiée** plutôt que demandée, et la ligne du tableau de `docs/frontiere-de-confiance.md` peut le dire. Ce que ça ne change pas : la *proposition* est un ticket `ready-for-human`, donc elle n'écrit rien sous ces chemins de toute façon.

  Une réserve à connaître, héritée telle quelle : ici `.claude/skills` est un jeu de liens symboliques vers `.agents/`. Écrire *à travers* un lien atterrit hors du chemin scellé — le scope-guard voit bien cette écriture pour ce qu'elle est, le scellement ne la voit pas du tout. Si ce ticket touche aux skills, c'est la distinction à garder en tête.
