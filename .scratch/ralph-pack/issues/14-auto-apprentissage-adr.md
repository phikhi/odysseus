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
