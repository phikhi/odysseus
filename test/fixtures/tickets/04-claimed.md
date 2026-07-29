# 04 — Claimed

**What to build:** Claimed by an iteration that is still running, so it must be
out of the frontier for a concurrent picker — and must survive the liveness
sweep, which reclaims a claim only once its owner is gone. The placeholders are
substituted at seed time by the harness: a static fixture cannot name a process
that is really alive.

**Blocked by:** None

**Write-surface:** `src/delta.txt`

**Status:** claimed

**Claimed:** owner=pid:@LIVE_PID@ at=@NOW@

- [ ] `src/delta.txt` exists.
