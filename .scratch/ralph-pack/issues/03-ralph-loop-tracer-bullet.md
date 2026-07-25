# 03 — Ralph loop tracer-bullet (happy-path)

**What to build:** Le walking skeleton de la ralph loop. À partir d'une frontière peuplée, elle broie chaque ticket via une **session fraîche** et le marque `resolved`, jusqu'à frontière vide = exit succès. Le gate est stubbé vert à ce stade (les vraies branches arrivent en [05]). C'est la tracer bullet bout-en-bout : elle prouve la chaîne scan → session → marquage → journal sur de vrais process.

**Blocked by:** 02

**Write-surface:** `.claude/loop.sh`, `test/loop-happy-path.bats`

**Status:** ready-for-agent

- [ ] `loop.sh` acquiert le verrou de run, puis boucle : scan frontière → spawn session fraîche (`claude -p`, `--output-format stream-json`, `--dangerously-skip-permissions`) → gate (stub vert) → `mark_resolved` → append `run.log`.
- [ ] Sur N tickets fixtures indépendants, un fake `claude` « succès » les fait tous passer `resolved`, puis la boucle sort en succès sur frontière vide.
- [ ] Le marquage `resolved` est fait **par la boucle après le gate**, jamais par la session.
- [ ] Les gardes anti-emballement coupent le run : kill gracieux (SIGTERM), cap `ITER_CAP`, détecteur de run stérile `STERILE_K`.
- [ ] Le prompt de la session injecte le ticket + des pointeurs (CONTEXT / ADRs / index LEARNINGS) — vérifié par le contenu passé au fake `claude`.
