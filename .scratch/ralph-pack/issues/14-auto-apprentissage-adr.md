# 14 — Auto-apprentissage + ADR en delivery

**What to build:** Le **subagent retro frais** post-gate (tier bon marché, auto-suppressif) qui capte la connaissance apprise : un record de leçon (+ index LEARNINGS injecté inline) et/ou un ADR interne, avec anti-bruit sur l'index et promotion jamais silencieuse.

**Blocked by:** 05, 10

**Write-surface:** `.claude/lib/retro.sh`, `test/retro.bats`

**Status:** ready-for-agent

- [ ] Après le gate, un subagent retro frais (auto-suppressif) n'écrit un record de leçon (`learning-records/NNNN`, format `teach`) **que** s'il y a une leçon ; sinon rien.
- [ ] L'index `LEARNINGS.md` reste un working set borné, injecté inline dans les sessions fraîches ; anti-bruit par dedup / supersession / drain-par-promotion.
- [ ] Une décision d'archi **interne** non-triviale est gravée en ADR (`docs/adr/`) ; une décision **contractuelle** escalade au lieu d'un ADR autonome.
- [ ] La promotion d'une leçon récurrente est soit **autonome** (guidance `CLAUDE.md`), soit **escaladée** (gate/lint/hook → `ready-for-human`) — jamais silencieuse.
- [ ] Écriture atomique (temp + `mv`) des records et de l'index.

## Comments

- **Contrainte posée par [31], livré le 30/07/2026 : `CLAUDE.md` est scellé, donc l'AC de promotion autonome ne peut pas s'écrire comme elle est rédigée.** Le scellement couvre désormais tout ce qu'un `claude` frais lit au démarrage, `CLAUDE.md` et `CLAUDE.local.md` compris, et **aucune write-surface ne peut couvrir un chemin scellé** : un ticket qui déclare `CLAUDE.md` est rouge à chaque tentative, définitivement. La décision a été prise en connaissance de ce coût — la boucle n'édite pas les règles qui la jugent — donc c'est ce ticket qui doit s'adapter, pas le scellement.

  Deux issues, à trancher ici et à écrire :

  1. **La promotion autonome va dans `LEARNINGS.md`**, qui est déjà le mécanisme de ce ticket (index borné, injecté inline dans les sessions fraîches). Une guidance promue y vit et atteint chaque session sans toucher un chemin scellé. C'est la voie qui préserve l'AC « jamais silencieuse » sans rien coûter.
  2. **Ou la promotion vers `CLAUDE.md` devient une escalade** — `ready-for-human`, un humain édite. Cohérent avec l'autre moitié de l'AC (« gate/lint/hook → escalade »), et cohérent avec [15], qui refuse déjà toute création de capacité en AFK.

  Le piège à ne pas rouvrir : contourner le scellement en écrivant la guidance dans un fichier *non* scellé que le prompt irait lire ensuite. Ce serait recréer exactement le canal que [31] vient de fermer, sous un autre nom — et cette fois sans qu'aucun contrôle le remarque.
