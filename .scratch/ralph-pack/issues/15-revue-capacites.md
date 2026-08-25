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

- **Contrainte posée par [14], livré le 24/08/2026 : le canal d'escalade existe déjà, ne pas en bâtir un second.** Le subagent retro peut répondre `RALPH-RETRO-ESCALATE: <règle>` quand ce qu'il a vu demanderait un gate, un lint ou un hook. Le pack ouvre alors, **par l'adaptateur de tracker** (donc noté au registre de [13], donc à l'abri des deux gardes de [42]), un ticket `retro-<slug>` en `ready-for-human`, avec la règle demandée, la raison pour laquelle elle n'est pas une leçon, et le ticket d'où elle vient. Dédupliqué contre le tracker : une escalade qui attend déjà un humain n'est pas rouverte chaque nuit.

  Ce que ce ticket hérite : la frontière « détecter ≠ créer » est **tenue** de ce côté-là — la seule chose que la boucle écrit d'elle-même est une observation dans son propre index, jamais une capacité. Ce que ce ticket doit décider : si sa revue de capacités produit ses propres propositions, elle passe par le même canal (même forme de ticket, même dédup) ou elle dit pourquoi elle en veut un autre. Deux producteurs de propositions avec deux formats est exactement le genre de chose qu'un humain qui vide le puits ne voit qu'une fois qu'elle est là.
