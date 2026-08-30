#!/usr/bin/env bash
# Break one guarantee at a time, and check that the test claiming to cover it
# turns red.
#
# A green suite proves nothing on its own. On this pack, sixteen tests have passed
# while the property they claimed to cover was deleted — a test that raced a few
# microseconds of a truncation window, a test that asserted a log line the loop
# prints anyway, a test that read an environment variable coming from the
# developer's shell rather than from the code, a test that renamed a file in a way
# that changed the answer for the wrong reason, two refutations in the canary that
# were reading the output of the previous `run`, and a threshold test comparing
# against a value on the same side of the line as the constant it was meant to
# rule out. Every one of them was a false green in a pack whose entire job is to
# refuse false greens.
#
# Three of those are worth knowing before writing anything here:
#
#   - every `run` overwrites $output, so a negative assertion aimed at the wrong
#     one can never fail. Keep the output you mean to assert on in a variable.
#   - this file lied too. Twelve entries carried an unescaped `$var` in their
#     replacement half, which perl interpolates to nothing: they broke the file
#     instead of removing the guarantee, reported `ok`, and hid three vacuous
#     tests underneath. A gate that checks tests is a test. Hence BROKEN below.
#   - a substitution without /g edits the **first** match, so an anchor that is
#     not unique is a latent lie. Two entries here aimed at `| gate__drop_bookkeeping`
#     and at `git diff-tree -r`, both unique when written; [29] added a second
#     caller of each *above* them, and from then on the mutation applied cleanly to
#     the wrong function while the test it named kept its guarantee. The symptom is
#     VACUOUS on a healthy test — which reads as the exact opposite of what happened,
#     and would have been "fixed" by rewriting a test that was fine. Anchor on enough
#     context to name one line, not on the interesting token.
#
# So the mutations are not a habit, they are an artefact. Each entry below names
# a guarantee, the edit that removes it, and the test that must fail once it is
# gone. Three outcomes:
#
#   ok        the mutation applied and the test went red — the test is real
#   VACUOUS   the mutation applied and the test stayed green — the test is a lie
#   DRIFTED   the mutation no longer matches the code — the entry needs updating
#   BROKEN    the mutation is not a mutation: it does not compile, or it left a
#             file that no longer parses. An `ok` earned that way proves the suite
#             notices a broken script, not that it covers anything. Escape every
#             `$` in both halves of the expression — `\$idx`, never `$idx`.
#
# DRIFTED is not a false alarm to be silenced: it means the line that carried a
# guarantee moved or disappeared, and nobody re-checked that the guarantee is
# still carried by something.
#
# One shape of guarantee cannot be mutated the way the others can: a termination
# condition. Take it out and the loop it bounded spins instead of failing, so the
# mutated run never comes back, and this script sits blocked with a planted defect
# in the working tree. The test covering such a line has to carry its own deadline
# rather than assert on a run that would never return — see the [25] entries.
#
# Usage
#   bash test/mutate.sh                 every mutation
#   bash test/mutate.sh -f scope        only those whose label matches
#   bash test/mutate.sh -l              list them without running anything
#   bash test/mutate.sh -n              apply each edit and restore it, without
#                                       running the suite: reports DRIFTED and
#                                       BROKEN in seconds instead of hours, and
#                                       says nothing at all about VACUOUS
#
# Adding one, whenever a ticket delivers a guarantee: pick the single line that
# carries it, write the edit that removes it, name the test that must notice.
# If no test notices, the guarantee is not covered — that is the finding.
#
# Runs the real files in place and restores them from a backup, on INT and TERM
# included — but a trap only runs between commands, and this script spends most
# of its time blocked inside `bash test/run.sh`. A TERM arriving there is handled
# minutes later, and a KILL never is: the working tree is then left holding a
# planted defect, in a file nobody edited. Check `git status` after interrupting
# this, and never edit a file while it is running.
#
# Sequential on purpose: the mutations touch the same files.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

BACKUP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ralph-mutate.XXXXXX")"
FILTER=""
LIST_ONLY=0
DRY_RUN=0
TOTAL=0
BAD=0

mutate__restore_all() {
  local saved base
  for saved in "$BACKUP_DIR"/*.bak; do
    [ -e "$saved" ] || continue
    base="$(basename "$saved" .bak)"
    cp "$saved" "$(cat "$BACKUP_DIR/$base.path")"
  done
}

mutate__cleanup() {
  mutate__restore_all
  rm -rf "$BACKUP_DIR"
}
trap 'mutate__cleanup' EXIT
trap 'mutate__cleanup; exit 130' INT TERM

# mutation <label> <file> <perl-expression> <test-file> <test-filter>
mutation() {
  local label="$1" file="$2" expr="$3" testfile="$4" filter="$5"
  local key out

  case "$label" in
    *"$FILTER"*) ;;
    *) return 0 ;;
  esac

  if [ "$LIST_ONLY" = 1 ]; then
    printf '%-46s %s\n' "$label" "$file"
    return 0
  fi

  TOTAL=$((TOTAL + 1))
  key="$(printf '%s' "$file" | tr '/' '_')"
  cp "$file" "$BACKUP_DIR/$key.bak"
  printf '%s' "$file" >"$BACKUP_DIR/$key.path"

  # -Mstrict is load-bearing, not tidiness. A `$var` left unescaped in the
  # replacement half is a perl variable, and perl interpolates it to nothing —
  # silently. The mutation then *breaks* the script instead of removing the
  # guarantee, every test rushes red, and the entry reads `ok` while proving only
  # that the suite notices a broken file. One of these shipped and was caught by
  # the one case where a blanked variable happened to be harmless. Under strict,
  # perl refuses to compile and writes nothing.
  if ! perl -Mstrict -0pi -e "$expr" "$file" 2>"$BACKUP_DIR/$key.perl"; then
    printf 'BROKEN   %s\n         the edit is not a valid mutation: %s\n' \
      "$label" "$(head -1 "$BACKUP_DIR/$key.perl")"
    BAD=$((BAD + 1))
    cp "$BACKUP_DIR/$key.bak" "$file"
    return 0
  fi
  if diff -q "$BACKUP_DIR/$key.bak" "$file" >/dev/null; then
    printf 'DRIFTED  %s\n         the edit no longer matches %s\n' "$label" "$file"
    BAD=$((BAD + 1))
    return 0
  fi

  # And what strict cannot see: perl's special variables ($(, $1, $&) are legal
  # under strict and interpolate to nonsense. A mutation is supposed to remove a
  # guarantee, never to produce a file that no longer parses — that would make any
  # test go red for the wrong reason.
  # The shims have no extension and are bash all the same. A mutation that broke
  # one would turn every test in the file red and read as `ok` — the exact shape
  # of the twelve entries that lied.
  case "$file" in
    *.sh | *.bash | test/helpers/shims/*)
      if ! bash -n "$file" 2>"$BACKUP_DIR/$key.syntax"; then
        printf 'BROKEN   %s\n         the mutated %s no longer parses: %s\n' \
          "$label" "$file" "$(head -1 "$BACKUP_DIR/$key.syntax")"
        BAD=$((BAD + 1))
        cp "$BACKUP_DIR/$key.bak" "$file"
        return 0
      fi
      ;;
  esac

  # The edit applied and the file still parses. Under `-n` that is the whole
  # answer: DRIFTED and BROKEN are questions about *this* file, and only VACUOUS
  # needs the suite. It exists because a ticket that moves code moves anchors, and
  # finding that out costs three hours the other way round — a delay long enough
  # that the honest thing to do at the end of a ticket stops being the cheap thing.
  # It proves nothing about coverage and must never be reported as a green gate:
  # what it rules out is an entry that would have reported DRIFTED anyway.
  if [ "$DRY_RUN" = 1 ]; then
    cp "$BACKUP_DIR/$key.bak" "$file"
    printf 'applies  %s\n' "$label"
    return 0
  fi

  out="$(bash test/run.sh "$testfile" -f "$filter" 2>&1)"
  cp "$BACKUP_DIR/$key.bak" "$file"

  # "No test ran" is asked *before* "no test failed", and the order is the whole
  # difference between a diagnosis and a lie. A run that matched nothing prints
  # `0 tests, 0 failures`, so with the other order a mistyped filter came back
  # VACUOUS — which reads as "this test is a lie" about a test that never ran, and
  # would be "fixed" by rewriting something that was fine. This file has already
  # cost the pack three vacuous tests by being wrong about its own verdicts ([30]).
  if printf '%s' "$out" | grep -qE '^0 tests|(^| )0 tests,'; then
    printf 'DRIFTED  %s\n         no test matches -f "%s" in %s\n' "$label" "$filter" "$testfile"
    BAD=$((BAD + 1))
    return 0
  fi
  if printf '%s' "$out" | grep -qE '(^| )0 failures'; then
    printf 'VACUOUS  %s\n         %s -f "%s" stayed green without it\n' \
      "$label" "$testfile" "$filter"
    BAD=$((BAD + 1))
    return 0
  fi
  printf 'ok       %s\n' "$label"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -f | --filter)
      shift
      FILTER="${1:-}"
      ;;
    -l | --list) LIST_ONLY=1 ;;
    -n | --dry-run) DRY_RUN=1 ;;
    -h | --help)
      sed -n '2,57p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      printf 'mutate.sh: unknown option %s\n' "$1" >&2
      exit 2
      ;;
  esac
  shift
done

LOOP=".claude/loop.sh"
GATE=".claude/lib/gate.sh"
MONITOR=".claude/lib/monitor.sh"
SESSION=".claude/lib/session.sh"
PROC=".claude/lib/proc.sh"
TRACKER=".claude/lib/tracker-local.sh"
TRACKER_IFACE=".claude/lib/tracker.sh"
CLAIM=".claude/lib/claim.sh"
STATE=".claude/lib/state.sh"
FAILURES=".claude/lib/failures.sh"
LENSES_LIB=".claude/lib/lenses.sh"
RECEIPT=".claude/lib/receipt.sh"
RETRO=".claude/lib/retro.sh"
CAPABILITY=".claude/lib/capability.sh"
# Not `LANG`: that one is the locale every command in this script reads.
LANGLIB=".claude/lib/lang.sh"
BUDGET=".claude/lib/budget.sh"
CONCURRENCY=".claude/lib/concurrency.sh"
# Not `SCHEDULER`: that one is a configuration key this pack reads, and a file
# path under its name would read like one here.
SCHEDULER_LIB=".claude/lib/scheduler.sh"
HARNESS="test/helpers/harness.bash"
SHIM="test/helpers/shims/claude"
CONTRACT="test/helpers/claude-contract.bash"
EXAMPLE=".claude/ralph.config.sh.example"

# ── [01] foundation & harness ────────────────────────────────────────────────

mutation "01 template key ignores file names" "$HARNESS" \
  's/    printf .%s\\n. "\$files"\n//' \
  test/smoke.bats "keyed by names"

mutation "01 config keys leak in from the shell" "$HARNESS" \
  's/^harness__clear_env\(\) \{/harness__clear_env() { return 0;/m' \
  test/smoke.bats "hermetic"

# ── [02] tracker adapter & state model ───────────────────────────────────────

mutation "02 field values keep their trailing blanks" "$TRACKER" \
  's/sub\(\/\[\[:space:\]\]\+\$\/, ""\); //' \
  test/tracker-local.bats "CRLF line endings"

mutation "02 a trailing space is not trimmed either" "$TRACKER" \
  's/sub\(\/\[\[:space:\]\]\+\$\/, ""\); //' \
  test/tracker-local.bats "trailing space"

mutation "02 an ambiguous ticket id is guessed" "$TRACKER" \
  's/  if \[ "\$matches" -gt 1 \]; then/  if false; then/' \
  test/tracker-local.bats "matching two tickets"

mutation "02 an unambiguous id is refused too" "$TRACKER" \
  's/  if \[ "\$matches" -gt 1 \]; then/  if [ "\$matches" -ge 1 ]; then/' \
  test/tracker-local.bats "exactly one ticket"

mutation "02 a missing issues directory is silent" "$TRACKER" \
  's/    printf .tracker: no issues directory[^\n]*\n//' \
  test/loop-happy-path.bats "no issues"

mutation "02 a blocker that points at nothing is ignored" "$TRACKER" \
  's/(depfile="[^\n]*)\|\| return 1/$1|| continue/' \
  test/tracker-local.bats "pointing at nothing"

mutation "02 only the first blocker has to be resolved" "$TRACKER" \
  's/    \[ "\$\(tracker_local__field_of_file "\$depfile" Status\)" = "resolved" \] \|\| return 1/    [ "\$(tracker_local__field_of_file "\$depfile" Status)" = "resolved" ] || return 0/' \
  test/tracker-local.bats "not just the first"

mutation "02 claiming is not a test-and-set" "$TRACKER" \
  's/  state_guard_take "\$guard" "claim guard" \|\| return 1/  :/' \
  test/tracker-local.bats "being taken by a live picker"

mutation "02 marking rewrites the ticket in place" "$TRACKER" \
  's/mv -f "\$work" "\$file"/cat "\$work" >"\$file"; rm -f "\$work"/' \
  test/tracker-local.bats "publishes by rename"

mutation "02 an atomic write is not atomic" "$STATE" \
  's/mv -f "\$tmp" "\$dest"/cat "\$tmp" >"\$dest"; rm -f "\$tmp"/' \
  test/state.bats "publish in one step"

mutation "02 a live lock holder is stolen from" "$STATE" \
  's/  if \[ -n "\$owner" \] && kill -0 "\$owner" 2>\/dev\/null; then/  if false; then/' \
  test/state.bats "not stolen"

mutation "02 the lock is never released" "$STATE" \
  's/^run_lock_release\(\) \{/run_lock_release() { return 0;/m' \
  test/state.bats "released when the run exits"

# ── [03] the loop ────────────────────────────────────────────────────────────

mutation "03 an empty frontier at the start looks like work done" "$LOOP" \
  's/      if \[ "\$iteration" -eq 0 \]; then/      if false; then/' \
  test/loop-happy-path.bats "empty from the start"

mutation "03 a drained frontier looks like nothing to do" "$LOOP" \
  's/      if \[ "\$iteration" -eq 0 \]; then/      if true; then/' \
  test/loop-happy-path.bats "this run drained"

mutation "03 FEATURE is not checked before starting" "$LOOP" \
  's/  if \[ -z "\$\{FEATURE:-\}" \]; then/  if false; then/' \
  test/loop-happy-path.bats "empty FEATURE"

mutation "03 a tracker that does not exist is not checked" "$LOOP" \
  's/    if \[ ! -d "\$dir" \]; then/    if false; then/' \
  test/loop-happy-path.bats "does not exist"

# The condition gained a third term in [23], so the anchor spans two lines now.
# Re-checked rather than path-substituted: what this removes is still the whole of
# "the session's own exit code decides", which is what the test names.
mutation "03 the session decides whether it succeeded" "$LOOP" \
  's/  if \[ "\$rc" -eq 0 \] && \[ "\$\{RALPH_SOFT_LIMIT_HIT:-0\}" = 0 \] &&\n    \[ -z "\$\{RALPH_SESSION_TIMEOUT:-\}" \]; then/  if true; then/' \
  test/loop-happy-path.bats "a session that fails resolves nothing"

mutation "03 the sterile counter never resets" "$LOOP" \
  's/    sterile=0\n  else\n    sterile=\$\(\(sterile \+ 1\)\)/    :\n  else\n    sterile=\$((sterile + 1))/' \
  test/loop-happy-path.bats "sterile counts consecutive"

mutation "03 the iteration cap does not stop the run" "$LOOP" \
  's/if \[ -z "\$stop_code" \] && \[ "\$iteration" -ge "\$ITER_CAP" \]; then/if false; then/' \
  test/loop-happy-path.bats "iteration cap"

mutation "03 a stop request tears the iteration down" "$LOOP" \
  's/  trap .loop_request_stop. TERM INT\n//' \
  test/loop-happy-path.bats "graceful kill"

# Anchored on the `else` above it since [08], and the reason is written at the top
# of this file: a substitution without /g edits the *first* match. [08] added a
# second `tracker_unclaim` — the budget class gives its ticket back too — three
# lines higher, so this entry started removing that one instead and came back
# VACUOUS against a test that was fine. Its own entry is with the [08] block.
mutation "03 the ticket is not given back after a failure" "$FAILURES" \
  's/  else\n    tracker_unclaim "\$ticket"\n/  else\n/' \
  test/loop-happy-path.bats "a session that fails resolves nothing"

mutation "03 sessions are resumed instead of fresh" "$SESSION" \
  's/claude -p /claude -p --continue /' \
  test/loop-happy-path.bats "no --continue"

# ── [04] the smart-zone net ──────────────────────────────────────────────────

mutation "04 auto-compact is not turned off for the session" "$SESSION" \
  's/DISABLE_AUTO_COMPACT=1 claude/claude/' \
  test/smart-zone.bats "auto-compact is off"

# Aimed at the whole termination and not at the TERM inside it, since [23]: the
# TERM alone no longer ends a session, a reaper follows it, and a mutation that
# removed only the signal would be racing that reaper rather than removing a
# guarantee. What the soft limit promises is that the session is *terminated*.
mutation "04 crossing the soft limit does not kill the session" "$MONITOR" \
  's/      monitor__terminate "\$pid"\n//' \
  test/smart-zone.bats "is terminated"

mutation "04 a session that survives its SIGTERM counts as resolved" "$LOOP" \
  's/ && \[ "\$\{RALPH_SOFT_LIMIT_HIT:-0\}" = 0 \]//' \
  test/smart-zone.bats "survives its SIGTERM"

mutation "04 cached tokens do not count toward the window" "$MONITOR" \
  's/  for key in input_tokens cache_creation_input_tokens cache_read_input_tokens output_tokens; do/  for key in input_tokens output_tokens; do/' \
  test/smart-zone.bats "counts cached tokens"

mutation "04 a key matches a longer key" "$MONITOR" \
  's/\{line##\*\\"\$2\\":\}/{line##*\$2\\":}/' \
  test/smart-zone.bats "counts cached tokens"

# Only the carry-over, since [23] put a second statement on that line: what is
# removed here is that the half-line is *kept*, not that it counts as writing —
# the entry below covers the other half of the same line.
mutation "04 a partial stream line is dropped" "$MONITOR" \
  's/\{ partial="\$partial\$line";/{ partial="";/' \
  test/smart-zone.bats "split across two writes"

mutation "04 the threshold is hard-coded" "$SESSION" \
  's/! monitor_watch "\$outfile" "\$pid" "\$SOFT_LIMIT_TOKENS"/! monitor_watch "\$outfile" "\$pid" 150000/' \
  test/smart-zone.bats "not a hard-coded"

# ── [05] the objective gate ──────────────────────────────────────────────────

mutation "05 the gate branches run in sequence" "$GATE" \
  's/  \(gate__branch "\$dir" "\$name" "\$\@"\) &/  (gate__branch "\$dir" "\$name" "\$\@") \& wait \$!/' \
  test/gate.bats "concurrently"

mutation "05 a branch with no verdict counts green" "$GATE" \
  's/if \[ "\$brc" = 0 \]; then/if [ "\$brc" = 0 ] || [ -z "\$brc" ]; then/' \
  test/gate.bats "no verdict"

mutation "05 only the tests branch is aggregated" "$GATE" \
  's/  for name in \$names; do/  for name in tests; do/' \
  test/gate.bats "type check resolves nothing"

mutation "05 an empty TEST_CMD is accepted" "$GATE" \
  's/    printf .ralph: TEST_CMD is empty[^\n]*\n    rc=1/    :/' \
  test/gate.bats "empty TEST_CMD"

mutation "05 an empty TYPECHECK_CMD is accepted" "$GATE" \
  's/    printf .ralph: TYPECHECK_CMD is empty[^\n]*\n    rc=1/    :/' \
  test/gate.bats "empty TYPECHECK_CMD"

mutation "05 a project outside git is accepted" "$GATE" \
  's/  if ! git rev-parse --git-dir/  if false \&\& ! git rev-parse --git-dir/' \
  test/gate.bats "no git repository"

mutation "05 'none' is treated as a command to run" "$GATE" \
  's/ && \[ "\$TYPECHECK_CMD" != none \]//' \
  test/gate.bats "genuinely has no type check"

# Anchored on the whole line, not on the pipe alone, and that is the fix for a
# VACUOUS this file reported the day [29] added a second caller of
# gate__drop_bookkeeping *above* this one. A perl substitution without /g edits the
# **first** match: the mutation went on applying cleanly, to the wrong function, and
# the test it named stayed green while having lost nothing. An anchor that is not
# unique is a latent lie — and the symptom is VACUOUS on a healthy test, which reads
# like the opposite of what happened.
mutation "05 the loop's own writes trip the scope-guard" "$GATE" \
  's/"\$base" "\$now" 2>\/dev\/null \|\n    gate__drop_bookkeeping/"\$base" "\$now" 2>\/dev\/null/' \
  test/gate.bats "stays inside its write-surface"

mutation "05 drift is not told apart from a stray write" "$GATE" \
  's/^gate__surface_owner\(\) \{/gate__surface_owner() { return 1;/m' \
  test/gate.bats "named as drift"

mutation "05 an undeclared write-surface allows everything" "$GATE" \
  's/^gate_write_surface\(\) \{/gate_write_surface() { printf "*\\\\n"; return 0;/m' \
  test/gate.bats "no write-surface may not write"

mutation "05 the scope-guard baseline is the last commit" "$LOOP" \
  's/  base="\$\(gate_tree_snapshot\)" \|\| base=""/  base="$(git rev-parse HEAD)"/' \
  test/gate.bats "previous one left in the tree"

mutation "05 a tree dirty before the run is charged to the ticket" "$LOOP" \
  's/  base="\$\(gate_tree_snapshot\)" \|\| base=""/  base="$(git rev-parse HEAD)"/' \
  test/gate.bats "already dirty when the run started"

# Aimed at the function and not at its guard line, deliberately. Blanking the
# `[ -n "$base" ] && [ -n "$now" ] || return 1` line leaves the test green,
# because the guarantee is carried twice: that line, and `pipefail` plus a git
# that refuses an empty tree argument. No mutation can isolate the line while the
# second mechanism stands, so the entry names the guarantee — a scope-guard that
# cannot see must not pass — rather than the line.
mutation "05 a blind scope-guard passes the ticket" "$GATE" \
  's/^gate_changed_files\(\) \{/gate_changed_files() { return 0;/m' \
  test/gate.bats "cannot read the tree"

# Drifted when [29] hoisted the snapshot out of the scope-guard's branch and into
# gate_run: the line that re-read the tree after the session moved, it did not
# disappear. Same guarantee, planted one layer up — a gate that judges the tree the
# session started from sees no session write at all.
mutation "05 the tree is not re-read after the session" "$GATE" \
  's/  RALPH_GATE_TREE="\$\(gate_tree_snapshot\)" \|\| RALPH_GATE_TREE=""/  RALPH_GATE_TREE="\$base"/' \
  test/gate.bats "new file outside"

mutation "05 the snapshot ignores untracked files" "$GATE" \
  's/  GIT_INDEX_FILE="\$index" git add -A >\/dev\/null 2>&1/  GIT_INDEX_FILE="\$index" git read-tree HEAD >\/dev\/null 2>\&1; GIT_INDEX_FILE="\$index" git add -u >\/dev\/null 2>\&1/' \
  test/gate.bats "new file outside"

# Same story as the entry above: `-r` appears twice since [29], and the first
# occurrence is the other diff. Anchored on the trees it takes.
mutation "05 the tree diff is not recursive" "$GATE" \
  's/diff-tree -r --name-only "\$base" "\$now"/diff-tree --name-only "\$base" "\$now"/' \
  test/gate.bats "new file outside"

mutation "05 the gate verdict does not decide the marking" "$LOOP" \
  's/    if gate_run "\$ticket" "\$base" && /    if { gate_run "\$ticket" "\$base" || true; } \&\& /' \
  test/gate.bats "red test suite resolves nothing"

mutation "05 a red gate is journalled as a plain failure" "$LOOP" \
  's/      outcome=gate-red\n/      outcome=failed\n/' \
  test/gate.bats "journalled as such"

mutation "05 the scope class is never said out loud" "$LOOP" \
  's/        loop_log "scope overflow on \$ticket: \$RALPH_GATE_SCOPE_CLASS"/        :/' \
  test/gate.bats "named as drift"

# ── [07] typed failures, rollback, durable green ─────────────────────────────

# No entry for "nothing puts the tree back after a red gate" any more, and the
# reason is worth reading rather than skipping. The canary still asserts the
# property — three attempts, three red scope-guards, never a green bought by
# having failed once — but since [13] it is held **twice**: the rollback undoes
# the attempt, *and* the next attempt gets a worktree made from the branch tip
# that never had it. Removing either line alone leaves the property standing, so
# no single-line mutation can make that test red. A guarantee held redundantly is
# not an uncovered one; what would be dishonest is an entry pretending otherwise.

# The next three moved file in [06]: the restore loop they aim at is now
# `gate_restore_tree` in gate.sh, because the containment of what a review lens
# wrote needs the same twelve lines and a second copy of them would drift. The
# guarantees are unchanged and so are the tests that hold them — what changed is
# which file carries the line, which is exactly what DRIFTED exists to make
# somebody re-check.
#
# Not at the process seam: the loop's post-session snapshot is taken before the
# retry counter is written, so the tracker is identical on both sides of the
# rollback's diff and no full-loop test can see the exclusion work. The test that
# holds it drives the rollback directly, with the counter written in between.
#
# Anchored on `"$path"` and not on `gate_is_bookkeeping`: gate.sh has three callers
# of that rule now, and the other two ask about `"$file"`.
mutation "07 the rollback rewrites the loop's own bookkeeping" "$GATE" \
  's/    if gate_is_bookkeeping "\$path"; then continue; fi\n//' \
  test/failures.bats "never restores the tracker"

mutation "07 a file the session added is not removed" "$GATE" \
  's/        rm -f "\$path"\n/        :\n/' \
  test/failures.bats "removes what the session added"

mutation "07 a file the session deleted is not restored" "$GATE" \
  's/        if ! GIT_INDEX_FILE="\$idx" git checkout-index -f -- "\$path" 2>\/dev\/null; then\n          gate__gap "could not restore \$path" >&2\n          continue\n        fi/        :/' \
  test/failures.bats "brings back what it deleted"

# The seam [06] introduced between the two: the rollback learns what it undid from
# what the primitive printed, and it needs that list for the unstaging and for the
# netting of the "could not undo" line. Emptied rather than removed — a caller that
# gets an empty list is the failure mode, a caller that does not compile is not.
mutation "06 the rollback never learns what it put back" "$FAILURES" \
  's/^\$restored\nROLLBACK/\nROLLBACK/m' \
  test/failures.bats "stray write is undone"

mutation "07 what the session staged stays staged" "$FAILURES" \
  's/    git reset -q -- ":\(literal\)\$path" 2>\/dev\/null \|\| true/    :/' \
  test/failures.bats "unstages what it put back"

mutation "07 the commit a session made is left in the history" "$FAILURES" \
  's/    if git reset -q --mixed "\$pre" 2>\/dev\/null; then/    if false; then/' \
  test/failures.bats "commit the session made"

# Aimed at the *restore* and no longer at the commit half: the collateral a
# blanket reset causes is a human's uncommitted work, and since [13] that work is
# not in the tree an iteration touches at all. What is still exactly as wide as
# the session's diff is `gate_restore_tree`, driven as a lib.
mutation "07 the rollback is a blanket reset --hard" "$GATE" \
  's/^gate_restore_tree\(\) \{/gate_restore_tree() { git reset -q --hard HEAD >\/dev\/null 2>\&1; git clean -qfd >\/dev\/null 2>\&1; printf "%s\\n" "reset"; return 0;/m' \
  test/failures.bats "work nobody in this run made stands"

mutation "07 a failure is not counted, so nothing is ever escalated" "$FAILURES" \
  's/      if \[ -z "\$count" \] \|\| \[ "\$count" -gt "\$\{RETRY_N:-2\}" \]; then/      if false; then/' \
  test/failures.bats "buys fresh retries"

mutation "07 the retry budget is hard-coded" "$FAILURES" \
  's/\[ "\$count" -gt "\$\{RETRY_N:-2\}" \]/[ "\$count" -gt 2 ]/' \
  test/failures.bats "retry budget is the configured one"

mutation "07 a contractual overflow is retried like any other failure" "$FAILURES" \
  's/      reason=decision\n//' \
  test/failures.bats "without spending a retry"

mutation "07 the attempt is not kept before the rollback undoes it" "$FAILURES" \
  's/  if \[ -n "\$reason" \] && \[ "\$class" != nothing-delivered \]; then\n    if failures_preserve_attempt "\$ticket" "\$pre" "\$tree"; then\n      RALPH_FAILURE_BRANCH="failed\/\$ticket"\n    fi\n  fi\n//' \
  test/failures.bats "keeps the attempt"

mutation "07 the failed branch carries the loop's own bookkeeping" "$FAILURES" \
  's/  GIT_INDEX_FILE="\$idx" git rm -r -f -q --cached --ignore-unmatch -- \\\n    "\.scratch\/\$\{FEATURE\}" >\/dev\/null 2>&1 \|\| true\n//' \
  test/failures.bats "keeps the attempt"

mutation "07 a slice too big is retried instead of re-sliced" "$FAILURES" \
  's/  if \[ "\$class" = too-big \]; then/  if false; then/' \
  test/failures.bats "is cut up"

mutation "07 a re-slice nobody could produce is retried forever" "$FAILURES" \
  's/    reason=too-big\n//' \
  test/failures.bats "nobody can split"

mutation "07 a plan that widens the write-surface is accepted" "$FAILURES" \
  's/^failures__plan_is_sound\(\) \{/failures__plan_is_sound() { return 0;/m' \
  test/failures.bats "widens the write-surface"

mutation "07 a plan of one ticket counts as a split" "$FAILURES" \
  's/  if \[ "\$\{total:-0\}" -lt 2 \]; then/  if [ "\${total:-0}" -lt 1 ]; then/' \
  test/failures.bats "splits nothing"

mutation "07 the parent of a re-slice goes straight back to the frontier" "$FAILURES" \
  's/  tracker_block_on "\$ticket" "\$children" \|\| true\n//' \
  test/failures.bats "is cut up"

mutation "07 a green iteration is not made durable" "$LOOP" \
  's/      if failures_make_durable "\$ticket" "\$pre" "\$base" "\$\{RALPH_GATE_TREE:-\}"; then/      if true; then/' \
  test/failures.bats "never takes away what an earlier gate"

mutation "07 the durable commit takes the whole tree, not what the gate approved" "$FAILURES" \
  's/    GIT_INDEX_FILE="\$idx" git add -A -- ":\(literal\)\$path" >\/dev\/null 2>&1 \|\| true/    GIT_INDEX_FILE="\$idx" git add -A >\/dev\/null 2>\&1 || true/' \
  test/failures.bats "nothing else is"

mutation "07 the durable commit does not move the branch" "$FAILURES" \
  's/ \|\|\n    ! git update-ref -m "ralph: \$ticket" HEAD "\$commit" "\$head" 2>\/dev\/null//' \
  test/failures.bats "nothing else is"

mutation "07 the durable commit is a write, not a compare-and-swap" "$FAILURES" \
  's/HEAD "\$commit" "\$head" 2>\/dev\/null/HEAD "\$commit" 2>\/dev\/null/' \
  test/failures.bats "never overwrites a HEAD"

mutation "07 a session's own tickets reach the frontier" "$LOOP" \
  's/  failures_quarantine_strays "\$ticket" "\$seen" "\$mark" \|\| true\n//' \
  test/failures.bats "own tickets"

# The escalated id is `$final` and not `$stray` since [27]: what a session adds
# is renumbered before it is quarantined, so the id that leaves the frontier is
# the one the ticket ends up carrying. The guarantee is unchanged — a ticket the
# session wrote itself must not sit on the frontier — the line moved under it.
mutation "07 a quarantined ticket is only logged, not taken off the frontier" "$FAILURES" \
  's/    tracker_mark_escalated "\$final" decision \|\| true\n/    :\n/' \
  test/failures.bats "own tickets"

mutation "07 a plan is read even from a session that wrote the tracker" "$FAILURES" \
  's/  if ! failures_quarantine_strays "\$ticket" "\$seen" "\$mark"; then\n    rm -f "\$plan" "\$plan.prompt" "\$out" "\$out.tokens"\n    return 1\n  fi\n//' \
  test/failures.bats "whole plan refused"

# Turned round by [13], and the label with it. [07] wrote "a git that refuses the
# commit is a warning, not the end of the run: the work is in the tree either
# way" — true while the iteration ran in the tree the run was started in, false
# the moment it runs in one about to be destroyed. So the mutation is now the old
# behaviour, swallowing the refusal, and what must go red is the test that used
# to assert it: without the stop, every ticket is marked `resolved` with nothing
# at all behind it.
#
# Pointed at the compare-and-swap race and not at the `main.lock` test, which is
# the one that reads the wrong way round now: a lock on `refs/heads/main` does not
# stop an iteration committing its own detached HEAD, so there the durable commit
# succeeds and it is the *fold* that refuses. Where this line really fails is the
# race, and that test is where it belongs.
mutation "07 a commit git refuses is swallowed and the ticket resolved anyway" "$LOOP" \
  's/      if failures_make_durable "\$ticket" "\$pre" "\$base" "\$\{RALPH_GATE_TREE:-\}"; then/      if failures_make_durable "\$ticket" "\$pre" "\$base" "\${RALPH_GATE_TREE:-}" || true; then/' \
  test/failures.bats "never overwrites a HEAD"

mutation "07 a git that refuses the branch takes the run down" "$FAILURES" \
  's/    if failures_preserve_attempt "\$ticket" "\$pre" "\$tree"; then\n      RALPH_FAILURE_BRANCH="failed\/\$ticket"\n    fi\n  fi/    failures_preserve_attempt "\$ticket" "\$pre" "\$tree"\n  fi/' \
  test/failures.bats "branch git cannot name"

# The entry above tests a *pair*, and there is deliberately no second entry for
# the other half. An iteration runs with errexit on — restored in loop__iterate
# after [13] switched it off by accident, through the `||` of a caller three
# frames up — and that posture is what makes the `|| true` above mean anything.
# Remove the `|| true` and the iteration dies at the refused branch: red, as
# above. Remove the posture instead and the `|| true` catches it: green, for a
# reason that is correct. One line covers both, and an entry attacking the other
# half would report VACUOUS about a guarantee that is held twice.

mutation "07 a gate branch that hangs is left to hang" "$GATE" \
  's/      gate__watchdog "\$GATE_TIMEOUT" "\$dir\/timed-out" \$pids &\n//' \
  test/failures.bats "hangs is red"

mutation "07 the deadline is hard-coded" "$GATE" \
  's/      gate__watchdog "\$GATE_TIMEOUT"/      gate__watchdog 1800/' \
  test/failures.bats "hangs is red"

# Re-anchored by [45], which moved this arm from `gate__log` to `gate__say` and
# gave it a sentence: the guarantee is unchanged — a branch the deadline killed has
# to be reported as one and not as a bare missing verdict — so the edit now takes
# the question away instead of the line, and the arm falls through to `no verdict`.
mutation "07 a timed-out branch is not reported as one" "$GATE" \
  's/^    elif \[ -f "\$dir\/timed-out" \]; then$/    elif false; then/m' \
  test/failures.bats "hangs is red"

# ── [21] the tracker a session must not write ────────────────────────────────

mutation "21 nothing guards the tracker from a session" "$FAILURES" \
  's/^failures_protect_tracker\(\) \{/failures_protect_tracker() { return 0;/m' \
  test/canary.bats "widen its own write-surface"

mutation "21 the tracker is only watched through its ids" "$LOOP" \
  's/  failures_protect_tracker "\$ticket" "\$issues" "\$mark" \|\| tracker_written=1\n//' \
  test/failures.bats "not given"

mutation "21 an edit to a ticket is not put back" "$FAILURES" \
  's/        GIT_INDEX_FILE="\$idx" git -C "\$root" checkout-index -f -- "\$path" 2>\/dev\/null \|\|\n          failures__gap "\$ticket: could not restore \$path"/        :/' \
  test/canary.bats "widen its own write-surface"

mutation "21 the write-surface is read after the session, not at spawn" "$LOOP" \
  's/  issues="\$\(failures_tracker_tree\)" \|\| issues=""\n  rc=0\n  loop_spawn_session "\$ticket" "\$outfile" \|\| rc=\$\?/  rc=0\n  loop_spawn_session "\$ticket" "\$outfile" || rc=\$?\n  issues="\$(failures_tracker_tree)" || issues=""/' \
  test/canary.bats "widen its own write-surface"

mutation "21 an edited tracker still buys a green iteration" "$LOOP" \
  's/ && \[ "\$tracker_written" = 0 \]//' \
  test/failures.bats "pays for the edit"

mutation "21 an edited tracker is journalled as a plain red gate" "$LOOP" \
  's/      \[ "\$tracker_written" = 0 \] \|\| outcome=tracker-write\n//' \
  test/failures.bats "pays for the edit"

mutation "21 a ticket the session created is restored away, not quarantined" "$FAILURES" \
  's/      A\)\n        # Left where it is/      A-never)\n        # Left where it is/' \
  test/failures.bats "quietly restored away"

mutation "21 a ticket the session deleted counts as one it created" "$FAILURES" \
  's/      A\)\n        # Left where it is/      A | D)\n        # Left where it is/' \
  test/failures.bats "deletes the whole tracker"

# Re-aimed by [34], which turned the single `git add` of this branch into a loop
# passing `:(literal)`. The guarantee is unchanged and still carried — `--force` is
# what makes the tracker snapshot ignore the project's ignore rules — so the entry
# follows the line rather than being retired. Anchored on `\n    done` so it cannot
# match the other branch, whose line ends in `|| true`.
mutation "21 the tracker snapshot obeys the project's ignore rules" "$GATE" \
  's/      GIT_INDEX_FILE="\$index" git add -A --force -- ":\(literal\)\$path" >\/dev\/null 2>&1\n    done/      GIT_INDEX_FILE="\$index" git add -A -- ":(literal)\$path" >\/dev\/null 2>\&1\n    done/' \
  test/failures.bats "scratch out of git"

mutation "21 a tracker nothing can vouch for passes" "$FAILURES" \
  's/    failures__gap "\$ticket: no pre-session tracker snapshot — the tracker cannot be vouched for"\n    return 1/    return 0/' \
  test/failures.bats "vouch for"

mutation "21 the tracker the session staged stays staged" "$FAILURES" \
  's/  git -C "\$root" reset -q -- "\$dir" 2>\/dev\/null \|\| true\n//' \
  test/failures.bats "stay staged"

mutation "21 a plan is read from a session that edited the tracker" "$FAILURES" \
  's/  if ! failures_protect_tracker "\$ticket" "\$issues" "\$mark"; then\n    rm -f "\$plan" "\$plan.prompt" "\$out" "\$out.tokens"\n    return 1\n  fi\n//' \
  test/failures.bats "edits the tracker has its whole plan"

mutation "21 a session's own commit survives its green gate" "$FAILURES" \
  's/    if git reset -q --mixed "\$pre" 2>\/dev\/null; then\n      failures__log "\$ticket: the session committed/    if false; then\n      failures__log "\$ticket: the session committed/' \
  test/failures.bats "green gate either"

# ── [12] claim liveness ──────────────────────────────────────────────────────

mutation "12 a claim outliving its owner is never reclaimed" "$CLAIM" \
  's/^claim_reclaim_stale\(\) \{/claim_reclaim_stale() { return 0;/m' \
  test/claim.bats "comes back to the frontier and is ground"

# Emptied rather than deleted. Removing the line would leave the `if` below
# reading a declared-but-unset local, which `set -u` turns into a dead loop — red
# for the wrong reason, and neither `bash -n` nor this file's own guards can see
# the difference. The point is a run that never sweeps, not a run that crashes.
mutation "12 the loop never sweeps the claims it inherited" "$LOOP" \
  's/    reclaimed="\$\(claim_reclaim_stale "\$\(loop__inflight_ids\)"\)"/    reclaimed=""/' \
  test/claim.bats "does not report an empty frontier"

mutation "12 a dead owner still answers for its claim" "$CLAIM" \
  's/      kill -0 "\$\{owner#pid:\}" 2>\/dev\/null \|\| return 1/      :/' \
  test/claim.bats "whose owner is gone is reclaimable"

mutation "12 nothing backstops a recycled pid" "$CLAIM" \
  's/    \*\) \[ "\$age" -le "\$CLAIM_TTL" \] \|\| return 1 ;;/    *) ;;/' \
  test/claim.bats "the TTL comes from the config"

# The lesson from [04]'s vacuous threshold test: a test that only asserts the
# claim is reclaimed cannot tell a configured TTL from a hard-coded one, so the
# entry has to be able to plant the constant.
mutation "12 the claim TTL is a constant, not the configured one" "$CLAIM" \
  's/\[ "\$age" -le "\$CLAIM_TTL" \]/[ "\$age" -le 5400 ]/' \
  test/claim.bats "the TTL comes from the config"

mutation "12 an unreadable claim counts as held" "$CLAIM" \
  's/  age="\$\(claim_age_seconds "\$record"\)" \|\| return 1/  age="\$(claim_age_seconds "\$record")" || age=0/' \
  test/claim.bats "uncertain counts as reclaimable"

mutation "12 a claim stamped in the future holds for ever" "$CLAIM" \
  's/  \[ "\$age" -ge 0 \] \|\| return 1\n//' \
  test/claim.bats "uncertain counts as reclaimable"

# Drifted when [26] moved the shape of an owner into claim_owner_kind, so that the
# liveness sweep and the retry policy could not draw the line in two places. Same
# guarantee, one indirection further: an owner read as unreadable is reclaimed on
# sight instead of being waited out.
mutation "12 an owner this pack cannot ping is reclaimed on sight" "$CLAIM" \
  's/    \*\) printf .foreign\\n. ;;/    *) printf "unreadable\\n" ;;/' \
  test/claim.bats "cannot ping waits out the TTL"

# A one-day shift: the conversion is arithmetic, so the way to remove its
# guarantee is to make it wrong rather than to delete it.
mutation "12 the epoch conversion is off by a day" "$CLAIM" \
  's/days=\$\(\(era \* 146097 \+ doe - 719468\)\)/days=\$((era * 146097 + doe - 719469))/' \
  test/claim.bats "without asking date to parse anything"

mutation "12 a reclaim costs nothing and never runs out" "$FAILURES" \
  's/^failures_after_dead_owner\(\) \{/failures_after_dead_owner() { tracker_unclaim "\$1"; printf "retry\\n"; return 0;/m' \
  test/claim.bats "runs out of them goes to the human sink"

mutation "12 a ticket that changed hands is missing from the journal" "$LOOP" \
  's/        loop_journal_append "\$rid" "reclaimed-\$rdisposition" 0 0 0\n//' \
  test/claim.bats "in the run journal"

# The suite's own witness for the other half. The fixture used to stand for
# "someone else's claim" while naming a pid that had never existed, so three
# tests asserting the loop left it alone were asserting that nothing looked.
mutation "12 the fixture's live claim is dead again" "$HARNESS" \
  's/^harness__stamp_live_claims\(\) \{/harness__stamp_live_claims() { return 0;/m' \
  test/claim.bats "left alone by the sweep"

# ── [12] the run lock a session can delete ───────────────────────────────────

mutation "12 a run lock this run no longer holds goes unnoticed" "$LOOP" \
  's/    if \[ -z "\$stop_code" \] && ! run_lock_is_ours; then\n      loop_log "the run lock is gone or not ours any more after \$iteration iterations — stopping rather than grinding beside another run"\n      stop_code=4\n    fi\n//' \
  test/failures.bats "lost its lock"

mutation "12 a lock that was deleted still counts as ours" "$STATE" \
  's/^run_lock_is_ours\(\) \{/run_lock_is_ours() { return 0;/m' \
  test/state.bats "tells a lock we hold"

# ── [22] one run per working tree ────────────────────────────────────────────

mutation "22 the loop takes no lock on the tree it grinds" "$LOOP" \
  's/  tree_lock_acquire \|\| exit 1\n//' \
  test/state.bats "refuses the second run anyway"

mutation "22 the tree lock is per feature after all" "$STATE" \
  's/printf .%s\/ralph\.tree\.lock\\n. "\$gitdir"/printf "%s\/ralph.tree.\${FEATURE:-}.lock\\n" "\$gitdir"/' \
  test/state.bats "whatever feature it grinds"

mutation "22 the tree lock is per repository, not per working tree" "$STATE" \
  's/git rev-parse --git-dir 2>\/dev\/null/git rev-parse --git-common-dir 2>\/dev\/null/' \
  test/state.bats "per working tree"

mutation "22 the tree lock lives inside the tree it guards" "$STATE" \
  's/^ralph_tree_lock_path\(\) \{/ralph_tree_lock_path() { printf "%s\/.tree.lock\\n" "\$(ralph_feature_dir)"; return 0;/m' \
  test/state.bats "out of reach of the tree it guards"

mutation "22 the refusal does not say which run holds the tree" "$STATE" \
  's/ "working-tree lock" "\$\{FEATURE:-unknown\}"/ "working-tree lock"/' \
  test/state.bats "whatever feature it grinds"

mutation "22 the refusal never says why it refuses" "$STATE" \
  's/    printf .ralph: refusing to start[^\n]*\n//' \
  test/state.bats "whatever feature it grinds"

mutation "22 only the last lock taken is released" "$STATE" \
  's/^state_locks_release\(\) \{\n  run_lock_release\n  tree_lock_release/state_locks_release() {\n  run_lock_release/m' \
  test/state.bats "both locks come off together"

# Drifted when [12] made the takeover displace the dead guard by rename instead
# of `rm -rf`. Same guarantee, one line earlier: cutting the takeover off before
# it starts. It is carried by three guards now — the run lock, the tree lock and
# a claim's test-and-set — so this one entry breaks more than the tree lock's test.
mutation "22 a run killed without releasing wedges the tree for good" "$STATE" \
  's/^  moved="\$guard\.stale\.\$\$"/  return 1/m' \
  test/state.bats "working-tree lock whose holder died"

mutation "22 a tree lock this run no longer holds goes unnoticed" "$LOOP" \
  's/    if \[ -z "\$stop_code" \] && ! tree_lock_is_ours; then\n      loop_log "the working-tree lock is gone or not ours any more after \$iteration iterations — stopping rather than grinding beside another run"\n      stop_code=4\n    fi\n//' \
  test/failures.bats "lost the tree lock"

mutation "22 a tree lock that was deleted still counts as ours" "$STATE" \
  's/^tree_lock_is_ours\(\) \{/tree_lock_is_ours() { return 0;/m' \
  test/state.bats "tells a tree lock we hold"

# The risk this ticket created: a second, coarser lock taken first can stand in
# for the per-feature one in almost every test, and then nothing notices if the
# tracker's own lock stops being taken. Both statements have to keep a test.
mutation "22 the tree lock stands in for the feature lock" "$LOOP" \
  's/  run_lock_acquire \|\| exit 1\n//' \
  test/loop-happy-path.bats "refuses to start while another run holds the lock"

# ── [20] the contract against the real binary ────────────────────────────────
#
# Two directions to keep alive, and they need different mutations. The fake
# drifting from the real format is caught by breaking the shim; the contract
# going blind is caught by breaking a check and watching the teeth test notice.
# A contract nobody mutates is a list of assertions that all pass.

mutation "20 the fake's assistant events carry no usage" "$SHIM" \
  's/"usage":\{"input_tokens":1000,"cache_creation_input_tokens"/"no_usage":{"input_tokens":1000,"cache_creation_input_tokens"/g' \
  test/contract-claude.bats "honours the contract"

mutation "20 the fake answers without reading the prompt it was given" "$SHIM" \
  's/^\[ -n "\$answer" \] \|\| answer=done/answer=done/m' \
  test/contract-claude.bats "honours the contract"

mutation "20 the fake hard-codes the permission bypass" "$SHIM" \
  's/^permission_mode="default"/permission_mode="bypassPermissions"/m' \
  test/contract-claude.bats "earns its bypass"

# The whole point of deriving permissionMode from argv rather than hard-coding
# it: the pack dropping the flag has to turn the contract red, on the fake, in
# the hermetic suite.
mutation "20 the pack stops bypassing permissions" "$SESSION" \
  's/    --dangerously-skip-permissions \\\n//' \
  test/contract-claude.bats "honours the contract"

mutation "20 the contract does not read the result with the pack's extractor" "$SESSION" \
  's/^session_result_field\(\) \{/session_result_field() { return 0;/m' \
  test/contract-claude.bats "honours the contract"

mutation "20 the contract ignores usage while the session runs" "$CONTRACT" \
  's/^contract__check_usage_while_running\(\) \{/contract__check_usage_while_running() { return 0;/m' \
  test/contract-claude.bats "has teeth"

mutation "20 the contract ignores the in-band budget signal" "$CONTRACT" \
  's/^contract__check_rate_limit_event\(\) \{/contract__check_rate_limit_event() { return 0;/m' \
  test/contract-claude.bats "has teeth"

mutation "20 the contract accepts two events on one line" "$CONTRACT" \
  's/^contract__check_ndjson\(\) \{/contract__check_ndjson() { return 0;/m' \
  test/contract-claude.bats "sharing one line"

mutation "20 a red contract does not say which side to repair" "$CONTRACT" \
  's/^contract__verdict\(\) \{/contract__verdict() { return 0;/m' \
  test/contract-claude.bats "which side to repair"

mutation "20 an unguarded real spawn is not noticed" "$CONTRACT" \
  's/^contract_unguarded_real_spawns\(\) \{/contract_unguarded_real_spawns() { return 0;/m' \
  test/contract-claude.bats "unguarded real spawn is caught"

# ── [25] the graceful stop, during the gate ──────────────────────────────────
#
# The collection itself moved to lib/proc.sh in [28] — `session_spawn` needed the
# same primitive — so the three entries that used to aim at `gate__collect` aim at
# `proc_collect` now. Re-checked line by line rather than path-substituted: the
# same lines still carry the same guarantees, and the two that end a collection now
# hand the child's status back instead of a blanket 0.

mutation "25 a stop request abandons the branch it interrupted" "$PROC" \
  's/    \[ "\$rc" -gt 128 \] \|\| return "\$rc"/    return "\$rc"/' \
  test/loop-happy-path.bats "during the gate waits"

mutation "25 the branches are collected with a bare wait again" "$GATE" \
  's/    proc_collect "\$brc" \|\| true/    wait "\$brc" 2>\/dev\/null || true/' \
  test/loop-happy-path.bats "during the gate waits"

# The one guarantee here whose absence is a hang and not a red: without the
# liveness check the collection spins for ever on a branch the deadline killed.
# Runnable only because the test that covers it brings its own deadline instead of
# asserting on a run that would never come back.
mutation "25 a branch the deadline killed is waited for for ever" "$PROC" \
  's/    kill -0 "\$pid" 2>\/dev\/null \|\| return "\$rc"\n//' \
  test/proc.bats "spinning"

mutation "25 a stopped run has no deadline left on a hung branch" "$GATE" \
  's/      gate__watchdog "\$GATE_TIMEOUT" "\$dir\/timed-out" \$pids &\n//' \
  test/loop-happy-path.bats "bounded by the deadline"

# ── [28] the graceful stop, during a session's shutdown ──────────────────────
#
# The second copy of the same defect, on the longer window. The first two entries
# below are the two windows of one line: the gate entry above names it from
# `loop-happy-path`, this one from the session's own shutdown, and neither test
# would notice the other's window.

mutation "28 the session is collected with a bare wait again" "$SESSION" \
  's/  proc_collect "\$pid" \|\| rc=\$\?/  wait "\$pid" || rc=\$?/' \
  test/smart-zone.bats "shutdown waits"

mutation "28 an interrupted collection gives up on the session" "$PROC" \
  's/    \[ "\$rc" -gt 128 \] \|\| return "\$rc"/    return "\$rc"/' \
  test/proc.bats "really exited with"

# The other half of the same line, and a different guarantee: the status has to
# come back, because it is the session's own exit code as far as the loop is
# concerned. A primitive answering 0 for every child turns a crashed session into a
# resolved ticket.
mutation "28 the collection swallows the status the child exited with" "$PROC" \
  's/    \[ "\$rc" -gt 128 \] \|\| return "\$rc"/    [ "\$rc" -gt 128 ] || return 0/' \
  test/failures.bats "a dead session is retried too"

# The lens half of "no claude survives the run", and a different mechanism: a
# branch is a subshell, so it never inherits the stop trap and is never exposed to
# the window above. What holds there is that the watchdog walks *down* the process
# tree — a lens is a grandchild of the loop.
#
# The walk moved to lib/proc.sh in [23], which gave it its second caller; the
# entry follows it and the test that notices does not change, because what it
# covers is the gate's deadline and not the primitive.
mutation "28 the deadline kills the branch but not the lens under it" "$PROC" \
  's/  for child in \$\(ps -A -o pid= -o ppid= 2>\/dev\/null \| awk -v p="\$pid" .\$2 == p \{ print \$1 \}.\); do\n    proc_kill_tree "\$child" "\$signal"\n  done\n//' \
  test/lenses.bats "deadline of its own"

# ── [23] the session that hangs, and the run behind it ───────────────────────
#
# Every entry here removes a *termination*, which is the shape mutate.sh cannot
# handle the ordinary way: take the guarantee out and the mutated run does not
# fail, it never comes back. Two answers, and each entry says which it uses. Most
# of these are bounded by the fake — a quiet session gives up after thirty seconds
# on its own, so the test fails on its assertion instead of hanging, slowly. The
# grace entries are not: a session that ignores its TERM is not bounded by
# anything the pack can see, so that test carries its own deadline.

mutation "23 a session that stops writing is never noticed" "$MONITOR" \
  's/      MONITOR_STOPPED=stall\n/      :\n/' \
  test/smart-zone.bats "stops writing"

mutation "23 the stall deadline is hard-coded" "$MONITOR" \
  's/monitor__deadline "\$\{SESSION_STALL_TIMEOUT:-0\}"/monitor__deadline 1800/' \
  test/smart-zone.bats "stops writing"

mutation "23 a session that emits for ever is never bounded" "$MONITOR" \
  's/      MONITOR_STOPPED=wall\n/      :\n/' \
  test/smart-zone.bats "bounded by the wall clock"

mutation "23 the wall deadline is hard-coded" "$MONITOR" \
  's/monitor__deadline "\$\{SESSION_TIMEOUT:-0\}"/monitor__deadline 10800/' \
  test/smart-zone.bats "bounded by the wall clock"

# The wall clock is measured from the spawn and not from the last write, and that
# is not a detail of implementation: the stream is a file in `.scratch/` that the
# session itself can append to, so a deadline reading it is a deadline a session
# can push back. This is the one nothing it writes can move.
mutation "23 the wall clock restarts whenever the session writes" "$MONITOR" \
  's/\[ "\$\(\(SECONDS - started\)\)" -ge "\$wall" \]/[ "\$((SECONDS - idle))" -ge "\$wall" ]/' \
  test/smart-zone.bats "bounded by the wall clock"

mutation "23 half a line does not count as the session writing" "$MONITOR" \
  's/ \[ -z "\$line" \] \|\| idle=\$SECONDS;//' \
  test/smart-zone.bats "slow halves"

mutation "23 a deadline of nonsense is a deadline" "$MONITOR" \
  "s/'' \\| \\*\\[!0-9\\]\\*\\) printf '0/'' | *[!0-9]*) printf '1/" \
  test/smart-zone.bats "no deadline at all"

mutation "23 a deadline of zero is a deadline" "$MONITOR" \
  's/\[ "\$stall" -gt 0 \]/[ "\$stall" -ge 0 ]/' \
  test/smart-zone.bats "no deadline at all"

# A TERM is a request. Without the reaper the run never comes back at all, which
# is why the test this names brings its own deadline rather than asserting on a
# run that would never return.
mutation "23 a TERM nobody answers hangs the run for ever" "$MONITOR" \
  's/  monitor__reaper "\$pid" "\$grace" &\n  MONITOR_REAPER=\$!\n//' \
  test/smart-zone.bats "killed after the grace"

mutation "23 the grace is hard-coded" "$MONITOR" \
  's/monitor__deadline "\$\{SESSION_KILL_GRACE:-30\}"/monitor__deadline 30/' \
  test/smart-zone.bats "killed after the grace"

# And the other half of the same act: the deadline asks before it takes. A
# `claude` killed outright loses whatever it was in the middle of writing, and
# the pack would never see the result event a real one emits on its way out.
mutation "23 the deadline goes straight to KILL" "$MONITOR" \
  's/  proc_kill_tree "\$pid"\n/  proc_kill_tree "\$pid" KILL\n/' \
  test/smart-zone.bats "exiting cleanly"

mutation "23 the loop reads a terminated session as a finished one" "$LOOP" \
  's/ &&\n    \[ -z "\$\{RALPH_SESSION_TIMEOUT:-\}" \]//' \
  test/smart-zone.bats "exiting cleanly"

# A hang is not evidence about the size of the slice. Classified as one, the loop
# spends a second session producing a split nobody measured — which is what the
# session count in this test is there to catch.
mutation "23 a session that hung is re-sliced as a slice too big" "$FAILURES" \
  "s/    session-stalled \\| session-timeout\\)\\n      printf 'timeout/    session-stalled | session-timeout)\\n      printf 'too-big/" \
  test/smart-zone.bats "stops writing"

# A planning session cut short answers 0, so nothing but this refusal stands
# between half a plan and tickets nobody can delete.
mutation "23 a plan written by a session that hung is acted on" "$FAILURES" \
  's/  if \[ -n "\$\{RALPH_SESSION_TIMEOUT:-\}" \]; then\n    rc=1\n/  if false; then\n    rc=1\n/' \
  test/failures.bats "cut short is refused whole"

mutation "23 a hung ticket is escalated as a failed implementation" "$FAILURES" \
  's/        \[ "\$class" != timeout \] \|\| reason=session-timeout\n//' \
  test/smart-zone.bats "human sink under its own name"

# The default is part of the guarantee: a deadline nobody sets is a deadline
# nobody has, and an AFK pack that shipped these switched off would ship the hole.
mutation "23 the shipped configuration leaves a session unbounded" "$EXAMPLE" \
  's/SESSION_STALL_TIMEOUT:-1800/SESSION_STALL_TIMEOUT:-0/' \
  test/smart-zone.bats "shipped configuration bounds"

# ── [26] what the retry counter counts, and what clears it ───────────────────

mutation "26 a resolution leaves the retry counter standing" "$TRACKER" \
  's/ Status resolved Claimed --drop Failures --drop/ Status resolved Claimed --drop/' \
  test/failures.bats "clears the retry counter"

mutation "26 every reclaim is charged, whoever held the claim" "$FAILURES" \
  's/  if \[ "\$kind" != run \]; then/  if false; then/' \
  test/claim.bats "never pinged costs the ticket nothing"

# The other half of the same guarantee, one module lower: if the pack cannot tell
# its own runs from an owner it never pinged, the policy above has nothing to act
# on. Planted as "everything is one of our runs", which is the direction that costs
# a human their retry budget. Aimed at the reproduction of the original probe, which
# nothing else can redden: the defect it came from needed both halves, so removing
# either one closes the scenario the other opened — what the journal says about each
# night is what carries it.
mutation "26 the pack reads every owner as one of its own runs" "$CLAIM" \
  's/^claim_owner_kind\(\) \{/claim_owner_kind() { printf "run\\n"; return 0;/m' \
  test/claim.bats "three claims taken back"

mutation "26 a reclaim at the ceiling escalates as a failed implementation" "$FAILURES" \
  's/    tracker_mark_escalated "\$ticket" decision/    tracker_mark_escalated "\$ticket" failed-impl/' \
  test/claim.bats "runs out of them goes to the human sink"

# The two notes are guarantees of their own: the ticket is the only place the person
# who lost the claim, or the person draining the human sink, will look. Both notes
# are prose, so the way to remove what they promise is to take the promise out of
# the sentence — the assertion reading it has to be reading the ticket and not the
# run's stdout, which is a mistake this suite has made before.
mutation "26 the ticket never says the claim was taken and not billed" "$FAILURES" \
  's/No retry was charged for it/The retry was charged/' \
  test/claim.bats "never pinged costs the ticket nothing"

mutation "26 the escalated ticket does not say no verdict was involved" "$FAILURES" \
  's/ran out on a reclaim, not on a verdict/ran out/' \
  test/claim.bats "runs out of them goes to the human sink"

# ── [24] the zone git does not show ──────────────────────────────────────────

mutation "24 the snapshot obeys the ignore rules on a guarded path" "$GATE" \
  's/      GIT_INDEX_FILE="\$index" git add -A --force -- ":\(literal\)\$path" >\/dev\/null 2>&1 \|\| true/      :/' \
  test/gate.bats "guarded path is caught"

mutation "24 the guarded paths are a constant, not the configured ones" "$GATE" \
  's/\$\{GUARDED_PATHS-\.claude\}/.claude/' \
  test/gate.bats "configured ones"

mutation "24 the harness's own configuration is not sealed" "$GATE" \
  's/^gate_is_sealed\(\) \{/gate_is_sealed() { return 1;/m' \
  test/gate.bats "configure the harness"

# The other half of the seal, and the one a reader is likelier to undo by
# accident: asking the write-surface first turns the seal into an ordinary check a
# ticket can declare its way past, which is exactly the armed case.
mutation "24 a write-surface may declare the sealed configuration after all" "$GATE" \
  's/    if gate_is_sealed "\$file"; then/    if gate_is_sealed "\$file" \&\& ! gate_in_surface "\$file" "\$surface"; then/' \
  test/gate.bats "configure the harness"

mutation "24 the zone nothing judged is never named" "$GATE" \
  's/^gate__report_unguarded\(\) \{/gate__report_unguarded() { return 0;/m' \
  test/gate.bats "not judged, and the gate says so"

# Both filters moved into gate__ignored_walk with [30], which gave the listing a
# third exclusion and a descent. The entries follow the lines rather than the
# function: DRIFTED here would mean the guarantee is no longer carried anywhere.
mutation "24 the loop's own bookkeeping counts as an unjudged write" "$GATE" \
  's/  if gate_is_bookkeeping "\$file"; then return 0; fi\n  if gate_under_path/  if gate_under_path/' \
  test/gate.bats "own bookkeeping"

# The lie in the other direction: naming a path the gate *did* judge. Held by the
# two refutations in the same test, which is the shape this suite has got wrong
# before — so the guarded case had to be a project whose only ignored path is a
# guarded one, or the refutation would pass on the strength of another path.
mutation "24 a guarded path is reported as unjudged too" "$GATE" \
  's/  if gate_under_path "\$\{file%\/\}" "\$guarded"; then return 0; fi\n//' \
  test/gate.bats "guarded path is caught"

mutation "24 the rollback says nothing about what it left behind" "$FAILURES" \
  's/^failures__report_unrolled\(\) \{/failures__report_unrolled() { return 0;/m' \
  test/failures.bats "could not undo"

# Tied to having undone something, which silences it in the one case where the
# tree is genuinely not back where the session found it: a session whose only
# write was an ignored file. The call it plants gained two arguments with [29].
mutation "24 the rollback only reports when it undid something" "$FAILURES" \
  's/\n  failures__report_unrolled "\$tree" "\$paths"\n/\n  if [ -n "\$paths" ]; then failures__report_unrolled "\$tree" "\$paths"; fi\n/' \
  test/failures.bats "nothing to undo"

# ── [30] who moves the frontier of that zone ─────────────────────────────────

# The control itself: the snapshot stops obeying the rules of the spawn and goes
# back to obeying whatever the session left behind.
#
# Not aimed at the `.git/info/exclude` test, and that is worth writing down rather
# than discovering twice: there the frontier is *put back* before the tree is taken,
# so the file behind the rule is caught by the ordinary `git add -A` and this entry
# comes back VACUOUS against a healthy test. It is the evidence for the claim in
# gate_run that the verdict does not rest on that ordering. The two tests below are
# the ones where the forcing is the only thing standing: a rule in the working tree,
# which is legitimate and therefore never put back, and a rule this run could not
# put back at all.
mutation "30 the snapshot obeys the rules the session left behind" "$GATE" \
  's/\$\(gate_guarded_paths\)\n\$hidden\nFORCED/\$(gate_guarded_paths)\nFORCED/' \
  test/gate.bats "does not hide what it wrote behind it"

mutation "30 the same, where the frontier could not be put back" "$GATE" \
  's/\$\(gate_guarded_paths\)\n\$hidden\nFORCED/\$(gate_guarded_paths)\nFORCED/' \
  test/gate.bats "could not put back"

# The pin records no working-tree rule, so *every* ignored path reads as newly
# hidden: the lie in the other direction, and the one that would make a real
# project red on its own build cache from the first iteration.
mutation "30 the pin records none of the working tree's rules" "$GATE" \
  's/    cp "\$file" "\$rules\/\$file" 2>\/dev\/null \|\| true/    :/' \
  test/gate.bats "does not hide what it wrote behind it"

# And the same for the source that needs no write-surface. Separate entry because
# separate copy: a pin that recorded the tree and not the git directory would red
# every project whose human keeps local excludes.
#
# The anchor moved with [41], which routed that copy through the run's own witness
# — the copy is still the guarantee, the line that carries it is a call now.
mutation "30 the pin records nothing of .git/info/exclude" "$GATE" \
  's/  gate__frontier_common_copy exclude "\$rules\/\.git\/info\/exclude" \\\n    "\$\(gate__ignore_exclude_path\)"/  :/' \
  test/gate.bats "does not hide what it wrote behind it"

# The half that keeps one red iteration from buying a whole night: without the
# restore, the *next* pin records the widened frontier as the project's own.
mutation "30 the frontier of the git directory is not put back" "$GATE" \
  's/^gate__frontier_restore\(\) \{/gate__frontier_restore() { return 1;/m' \
  test/gate.bats "widen the blind zone"

# Reporting the intention instead of the result. `git config --unset` writes the
# repository config, so a key a session put in the user's config survives it — and
# the message said "(put back)" all the same.
#
# Anchored on the `esac` above it since [46], and that is the trap this file
# documents rather than a flourish: `gate__config_restore` ends with the same
# comparison and sits *earlier* in the file, so the bare line would have applied
# cleanly to the wrong function while this test kept its guarantee.
mutation "30 a restore that was only attempted reports success" "$GATE" \
  's/    \*\) return 1 ;;\n  esac\n  \[ "\$\(gate__frontier_current "\$name"\)" = "\$pinned" \]/    *) return 1 ;;\n  esac\n  return 0/' \
  test/gate.bats "could not put back"

# The verdict, as opposed to the visibility: the frontier moves, the file behind it
# is still judged through the pin, and nothing says who moved it.
mutation "30 moving the frontier is not a finding" "$GATE" \
  's/^gate_frontier\(\) \{/gate_frontier() { return 0;/m' \
  test/gate.bats "widen the blind zone"

mutation "30 the scope-guard drops the frontier findings" "$GATE" \
  's/  if \[ -n "\$\{RALPH_GATE_FRONTIER:-\}" \]; then/  if [ -n "" ]; then/' \
  test/gate.bats "outside the repository is named"

# The cause behind [24]'s consequence, which is the one line a human gets when the
# rule is legitimate work.
mutation "30 nothing says the session moved the frontier" "$GATE" \
  's/^gate__report_frontier\(\) \{/gate__report_frontier() { return 0;/m' \
  test/gate.bats "does not hide what it wrote behind it"

# Fail-closed. A pin that is set and unreadable must not read as "no pin at all",
# which is the fail-open the whole mechanism would collapse into.
mutation "30 a broken pin snapshots anyway" "$GATE" \
  's/  if gate__frontier_pin_broken; then return 1; fi/  :/' \
  test/gate.bats "pin that cannot be read"

# The folding, which is what keeps a node_modules out of the morning log: descend
# into every folded directory instead of only those holding something judged.
mutation "30 every folded directory is walked, not only the ones that need it" "$GATE" \
  's/^gate__ignored_holds_judged\(\) \{/gate__ignored_holds_judged() { return 0;/m' \
  test/gate.bats "were already there cost nothing"

# And the descent itself, without which the tracker of a project that has not
# committed it is announced as a path nobody judged.
mutation "30 a folded directory holding a judged path is reported whole" "$GATE" \
  's/^gate__ignored_holds_judged\(\) \{/gate__ignored_holds_judged() { return 1;/m' \
  test/gate.bats "tracker is not named"

# The second caller, and the reason it exists: a planning session is never gated,
# so nothing else on that path would put the rules back.
mutation "30 the re-slice session's frontier is left where it put it" "$FAILURES" \
  's/moved="\$\(gate_frontier\)"/moved=""/' \
  test/failures.bats "re-slice session cannot leave"

# The fixture's own world: `.git/info/exclude` is created by every real `git init`,
# and the empty template took it away — which is how the source that needs no
# write-surface stayed unexercisable for thirty tickets.
mutation "30 the fixture project has no local excludes, as before" "$HARNESS" \
  's/  mkdir -p "\$PROJECT_DIR\/\.git\/info"\n/  /' \
  test/gate.bats "widen the blind zone"

# ── [33] a list of paths is not a line of words ──────────────────────────────
#
# Each entry aims at the *passing* of the paths and never at the content of a
# list — replacing what `gate_guarded_paths` returns would prove that removing a
# guarded path removes its guard, which nobody doubted.

# The forcing, cut back into words. Both halves of the old defect come back with
# it: a space makes two pathspecs out of one path, and a glob character makes
# whichever path happens to exist.
mutation "33 the forced paths are split on whitespace again" "$GATE" \
  's/    while IFS= read -r path; do\n      \[ -n "\$path" \] \|\| continue\n      GIT_INDEX_FILE="\$index" git add -A --force -- ":\(literal\)\$path" >\/dev\/null 2>&1 \|\| true\n    done <<FORCED\n\$\(gate_guarded_paths\)\n\$hidden\nFORCED/    for path in \$(gate_guarded_paths) \$hidden; do\n      GIT_INDEX_FILE="\$index" git add -A --force -- "\$path" >\/dev\/null 2>&1 \|\| true\n    done/' \
  test/gate.bats "name has a space is a guard"

# The same edit, judged by the other producer's test: the guarded paths and what
# a rule hid during the iteration travel through one loop, so one entry per list
# rather than one entry for the loop.
mutation "33 the same, on a path a rule hid during the iteration" "$GATE" \
  's/    while IFS= read -r path; do\n      \[ -n "\$path" \] \|\| continue\n      GIT_INDEX_FILE="\$index" git add -A --force -- ":\(literal\)\$path" >\/dev\/null 2>&1 \|\| true\n    done <<FORCED\n\$\(gate_guarded_paths\)\n\$hidden\nFORCED/    for path in \$(gate_guarded_paths) \$hidden; do\n      GIT_INDEX_FILE="\$index" git add -A --force -- "\$path" >\/dev\/null 2>&1 \|\| true\n    done/' \
  test/gate.bats "name has a space does not buy it"

# The pathspec half. A git pathspec is a pattern too, and it falls back to
# wildmatch when nothing carries the name literally — so the guard lands on a
# directory nobody named and the zone line goes quiet about the one it should
# have named.
mutation "33 the forcing hands git a pattern instead of a path" "$GATE" \
  's/ -- ":\(literal\)\$path" >\/dev\/null 2>&1 \|\| true/ -- "\$path" >\/dev\/null 2>&1 || true/' \
  test/gate.bats "written as a glob guards nothing"

# The reading half, which has to agree with the forcing: a list of paths read as a
# list of globs makes `zone[1]` mean `zone1` on one side of the mechanism and not
# on the other.
mutation "33 the guarded paths are read as globs again" "$GATE" \
  's/^gate_under_path\(\) \{\n  local file="\$1" path/gate_under_path() {\n  gate_in_surface "\$1" "\$2"; return;\n  local file="\$1" path/m' \
  test/gate.bats "glob character guards itself"

# And the surface, whose list was expanded against the working tree before it was
# matched against anything.
mutation "33 a surface is cut into words by the shell again" "$GATE" \
  's/  while IFS= read -r pattern; do\n    pattern="\$\{pattern%\/\}"\n    \[ -n "\$pattern" \] \|\| continue\n    case "\$file" in\n      \$pattern \| \$pattern\/\*\) return 0 ;;\n    esac\n  done <<SURFACE\n\$2\nSURFACE/  for pattern in \$2; do\n    pattern="\${pattern%\/}"\n    [ -n "\$pattern" ] || continue\n    case "\$file" in\n      \$pattern | \$pattern\/*) return 0 ;;\n    esac\n  done/' \
  test/gate.bats "covers what it should"

# ── [34] a refusal is not an empty measurement ───────────────────────────────
#
# Every entry here aims at the *status* of a measurement and never at what it
# measures. Replacing a list with an empty one would prove that a gate which finds
# nothing says nothing, which nobody doubts; what has to redden is the case where
# nothing could be looked at in the first place.

# The primitive itself, both halves. Answering a refusal with zero is the whole of
# the defect: four readers were written against "empty list means nothing to say".
mutation "34 the primitive answers a refused snapshot with an empty list" "$GATE" \
  's/  now="\$\(gate_tree_snapshot\)" \|\| return 1/  now="\$(gate_tree_snapshot)" || return 0/' \
  test/lenses.bats "closes the measurement"

mutation "34 the primitive answers a missing baseline with an empty list" "$GATE" \
  's/  \[ -n "\$judged" \] \|\| return 1/  [ -n "\$judged" ] || return 0/' \
  test/failures.bats "stops the run instead of laundering"

# The reader that produced the false green: the one half of [06] that is a
# guarantee rather than a hope, passing green without having measured.
mutation "34 the containment reads a refusal as nothing to undo" "$GATE" \
  's/  if ! changed="\$\(gate_unjudged_changes "\$pre"\)"; then\n[^\n]*\n    return 1\n  fi/  changed="\$(gate_unjudged_changes "\$pre")" || changed=""/' \
  test/lenses.bats "cannot be read after the lenses"

# And the second measurement of the same function: putting a write back is a claim
# about a result, so a restore nobody could check is not a restore.
mutation "34 the containment does not check its own restore" "$GATE" \
  's/  if ! left="\$\(gate_unjudged_changes "\$pre"\)"; then\n[^\n]*\n    return 1\n  fi/  left="\$(gate_unjudged_changes "\$pre")" || left=""/' \
  test/lenses.bats "cannot check its own restore"

# The two readers that announce rather than judge. Neither may go red — this is a
# line printed on green iterations — so what must redden is the announcement
# itself becoming silence.
mutation "34 the gate's own zone line reads a refusal as an empty zone" "$GATE" \
  's/  if ! changed="\$\(gate_unjudged_changes "\$2"\)"; then\n[^\n]*\n    return 0\n  fi/  changed="\$(gate_unjudged_changes "\$2")" || changed=""/' \
  test/failures.bats "stops the run instead of laundering"

mutation "34 the rollback's zone line reads a refusal as an empty zone" "$FAILURES" \
  's/  if ! changed="\$\(gate_unjudged_changes "\$tree"\)"; then\n[^\n]*\n    return 0\n  fi/  changed="\$(gate_unjudged_changes "\$tree")" || changed=""/' \
  test/failures.bats "cannot measure what the gate left"

# The other half of the ticket: a rollback that could not act says so, and the run
# stops instead of letting the next iteration adopt the tree as its own baseline.
# Two entries, because raising the flag and reading it are two places to lose it.
mutation "34 a rollback that read no tree does not say so to the loop" "$FAILURES" \
  's/    failures__gap "cannot read the working tree — nothing was rolled back"\n    RALPH_ROLLBACK_FAILED=1\n/    failures__gap "cannot read the working tree — nothing was rolled back"\n/' \
  test/failures.bats "stops the run instead of laundering"

mutation "34 the loop grinds on after a rollback that could not act" "$LOOP" \
  's/  if \[ "\$\(cat "\$slot\/rollback-failed" 2>\/dev\/null \|\| echo 0\)" = 1 \]; then/  if false; then/' \
  test/failures.bats "stops the run instead of laundering"

# The [33] reading, on the branch [33] had no caller to decide for. The tracker's
# own guard is that caller: a feature directory named with a glob character would
# be snapshotted as a different directory altogether.
mutation "34 the snapshot's pathspec branch hands git a pattern" "$GATE" \
  's/    for path in "\$\@"; do\n      GIT_INDEX_FILE="\$index" git add -A --force -- ":\(literal\)\$path"/    for path in "\$\@"; do\n      GIT_INDEX_FILE="\$index" git add -A --force -- "\$path"/' \
  test/gate.bats "taken literally, not as a pattern"

# ── [29] the tree the gate judges, taken before the gate runs ────────────────

# The defect itself, planted back. `sleep 1` is what makes it deterministic in the
# direction the probe found: the old code snapshotted from inside the scope-guard's
# branch, so a suite that writes at once always won the race and the artefact was
# charged to the session. Without the sleep this entry would be a draw, which is
# the whole complaint about the code it plants.
mutation "29 the scope-guard snapshots the tree from inside its branch again" "$GATE" \
  's/^gate__scope_guard\(\) \{/gate__scope_guard() { set -- "\$1" "\$2" "\$(sleep 1; gate_tree_snapshot)" "\$4";/m' \
  test/gate.bats "writes at once is not charged"

# The other half of the hoist, and the one [06] needs: the tree is still taken once
# and before the fan, but it only reaches RALPH_GATE_TREE after the collection —
# which is the state a branch was probed in on 29/07/2026, reading `tree=[]`.
mutation "29 a branch cannot see the tree it is judged on" "$GATE" \
  's/  RALPH_GATE_TREE="\$\(gate_tree_snapshot\)" \|\| RALPH_GATE_TREE=""/  gate_judged="\$(gate_tree_snapshot)" || gate_judged=""/; s/"\$base" "\$RALPH_GATE_TREE" "\$dir\/scope.class"/"\$base" "\$gate_judged" "\$dir\/scope.class"/; s/^  gate__log "\$ticket: \$RALPH_GATE_VERDICTS"/  RALPH_GATE_TREE="\$gate_judged"\n  gate__log "\$ticket: \$RALPH_GATE_VERDICTS"/m' \
  test/gate.bats "branch of this gate can read"

# A guard handed nothing falls back to reading the tree itself, which is not a
# fallback but the race coming back in through gate_changed_files.
#
# Anchored on the `local` line above it since [35], and the reason is the one this
# file opens with: that refusal is now written twice — `gate__nothing_delivered`
# refuses an empty `now` for exactly the same reason and is defined *above* this
# one. A substitution without /g edits the first match, so the entry went on
# applying cleanly to the wrong function and came back VACUOUS about a guard that
# had lost nothing. Caught by the gate; the lesson is unchanged and now has a
# third instance.
mutation "29 a scope-guard handed no tree recomputes one instead of refusing" "$GATE" \
  's/  local surface changed file owner class=.. rc=0\n\n  if \[ -z "\$now" \] \|\| ! changed="\$\(gate_changed_files "\$base" "\$now"\)"; then/  local surface changed file owner class=\x27\x27 rc=0\n\n  if ! changed="\$(gate_changed_files "\$base" "\$now")"; then/' \
  test/gate.bats "cannot read the tree"

mutation "29 the gate never says what it wrote while it judged" "$GATE" \
  's/^gate__report_changed\(\) \{/gate__report_changed() { return 0;/m' \
  test/gate.bats "goes with the worktree"

# The two halves of this diff that the entries for [05] cover on the other one, and
# they are here because that diff has its own callers now. A build writes into a
# directory, which is why the tests name `build/coverage.xml` and not a path at the
# root: a non-recursive diff would report `build` and read as covered.
mutation "29 the diff of what the gate changed is not recursive" "$GATE" \
  's/diff-tree -r --name-only "\$judged" "\$now"/diff-tree --name-only "\$judged" "\$now"/' \
  test/gate.bats "goes with the worktree"

mutation "29 the loop's own bookkeeping counts as a gate write" "$GATE" \
  's/"\$judged" "\$now" 2>\/dev\/null \|\n    gate__drop_bookkeeping/"\$judged" "\$now" 2>\/dev\/null/' \
  test/failures.bats "leaves it standing"

# Emptied rather than removed: the block that names the zone spans four lines, and
# a list that arrives empty silences it through the same path a gate that wrote
# nothing does. The ignored-zone line above it is untouched, so this entry cannot
# pass on the strength of [24]'s.
mutation "29 the rollback says nothing about what the gate changed" "$FAILURES" \
  's/"\$\(failures__minus "\$changed" "\$undone"\)"/""/' \
  test/failures.bats "leaves it standing"

# And the lie in the other direction: a filter that matches nothing filters nothing,
# so a path the rollback did put back is announced as one it could not. Recalibrated
# by [39], which replaced the word fence this used to blank with a whole-line
# membership test — same guarantee, and the edit that removes it is now the line that
# consults the list at all.
mutation "29 a path the rollback put back is named as one it could not" "$FAILURES" \
  's/    ! failures__in_list "\$item" "\$\{2:-\}" \|\| continue\n//' \
  test/failures.bats "did put back"

# ── [06] the review lens registry ────────────────────────────────────────────

# ── which lenses answer which ticket

mutation "06 an always-on lens is not always on" "$LENSES_LIB" \
  's/^lenses_want_standards\(\) \{/lenses_want_standards() { return 1;/m' \
  test/lenses.bats "answer every ticket"

# The other direction, and the one a table of predicates exists for: a gated lens
# that fires on everything is five sessions an iteration instead of two.
mutation "06 a gated lens fires on every ticket" "$LENSES_LIB" \
  's/^lenses__triggered_by\(\) \{/lenses__triggered_by() { return 0;/m' \
  test/lenses.bats "only looks like a sensitive one"

mutation "06 a tag on the ticket triggers nothing" "$LENSES_LIB" \
  's/  lenses_has_tag "\$ticket" "\$tag" \&\& return 0\n//' \
  test/lenses.bats "tagged ticket, and a sensitive surface"

mutation "06 a configured path triggers nothing, only the tag does" "$LENSES_LIB" \
  's/  \[ -n "\$paths" \] \|\| return 1/  return 1/' \
  test/lenses.bats "meeting VISIBLE_PATHS"

# Both sides of the intersection are globs, so `src` against `src/auth/*` matches
# one way round only. Removing the second direction narrows the predicate silently.
mutation "06 the surface intersection is tried one way only" "$LENSES_LIB" \
  's/    gate_in_surface "\$paths" "\$entry" \&\& return 0\n//' \
  test/lenses.bats "directory a sensitive glob is under"

# The boundary [33] put here: the key is authored whitespace-separated and every
# list inside the pack travels one entry per line. Skip the conversion and the key
# arrives as one pattern carrying a space, matching nothing.
mutation "33 the lens path key is not converted where it is read" "$LENSES_LIB" \
  's/  paths="\$\(gate_authored_list "\$paths"\)"\n//' \
  test/lenses.bats "naming several globs"

# ── the registry is a registry

mutation "06 a lens LENSES names but nothing can run is let through" "$GATE" \
  's/  if unknown="\$\(lenses_unknown\)"; then/  if false; then/' \
  test/lenses.bats "stops the run at the door"

mutation "06 switching the judgement tier off is silent" "$GATE" \
  's/      gate__say "\$ticket: no review lens ran \(LENSES is empty\)[^\n]*\n/      :\n/' \
  test/lenses.bats "said out loud"

# ── what a lens is judged on

# The correction [29] left this ticket, planted the way the defect would come back:
# a lens that takes its own snapshot reviews files the session never wrote.
mutation "06 a lens snapshots its own tree instead of the judged one" "$LENSES_LIB" \
  's/  if \[ -z "\$tree" \] \|\| \[ -z "\$base" \]; then/  tree="\$(gate_tree_snapshot)"\n  if [ -z "\$base" ]; then/' \
  test/lenses.bats "not one of its own"

# Re-aimed by [35], which moved the guarantee this used to cover into the gate:
# the loop cannot reach a lens with an empty diff any more, so the test that holds
# the local half calls `lenses_review` directly. The line is still here and still
# load-bearing — a public function handed a base equal to its tree must refuse
# rather than spend a model — and the entry follows it.
mutation "06 an iteration that changed nothing is reviewed anyway" "$LENSES_LIB" \
  's/  \[ -n "\$files" \] \|\| return 1\n//' \
  test/lenses.bats "diff of nothing refuses"

mutation "06 the lens is shown the file names and not the diff" "$LENSES_LIB" \
  's/  lenses__patch "\$base" "\$tree" "\$max" \|\| truncated=1/  :/' \
  test/lenses.bats "not just the names"

# ── the verdict

mutation "06 a lens that said nothing counts green" "$LENSES_LIB" \
  's/^lenses__verdict\(\) \{/lenses__verdict() { printf "pass\\\\n"; return 0;/m' \
  test/lenses.bats "never said what it decided"

# A model quotes the instruction it was given on its way to an answer, and the diff
# under review can carry the token too — this repository's own does.
mutation "06 the first verdict in the stream decides, not the last" "$LENSES_LIB" \
  's/    tail -1 \| sed/    head -1 | sed/' \
  test/lenses.bats "last one in the stream"

mutation "06 a red lens does not redden the gate" "$GATE" \
  's/  gate__aggregate "\$dir" "\$lenses" \|\| agg=1/  gate__aggregate "\$dir" "\$lenses" || true/' \
  test/lenses.bats "red lens makes the gate red"

# ── the lens cannot write, prevention half

# Re-aimed by [31]: the spawn used to pass `--tools "$(lenses_tools)"` inline, and
# it now passes the whole posture. The guarantee is unchanged and still carried —
# emptying the tool set out of the posture leaves the lens with the built-in set,
# writes included — so the entry follows the line rather than being retired.
mutation "06 the lens is spawned with the tools that write" "$LENSES_LIB" \
  's/"--tools \$\(lenses_tools\) --strict-mcp-config --setting-sources user"/"--strict-mcp-config --setting-sources user"/' \
  test/lenses.bats "without the tools that write"

mutation "06 the read-only tool set is widened by one" "$LENSES_LIB" \
  's/Read,Grep,Glob/Read,Grep,Glob,Edit/' \
  test/lenses.bats "without the tools that write"

# ── the lens cannot write, verification half

mutation "06 what a lens wrote is named and left standing" "$GATE" \
  's/^gate__contain_lens_writes\(\) \{/gate__contain_lens_writes() { return 0;/m' \
  test/lenses.bats "is put back"

# The other half of the same function: undoing is not enough if a write that
# survived the undo still passes. Returning early rather than blanking the log, so
# the entry cannot pass on the strength of the message being gone.
mutation "06 a lens write that survived the undo passes anyway" "$GATE" \
  's/  \[ -n "\$left" \] \|\| return 0/  return 0/' \
  test/lenses.bats "cannot be undone refuses to pass"

mutation "06 a containment that cannot see the tree shrugs" "$GATE" \
  's/    gate__say "\$ticket: could not read the tree before the review lenses[^\n]*\n    return 1/    return 0/' \
  test/lenses.bats "cannot be read before the lenses"

# The stream is the mechanism's own write, and it lives under TMPDIR so that the
# mechanism puts nothing in the repository. Moved into the tree, the containment
# above notices it — which is what makes these two guarantees one story.
# The path moved into `lenses__stream` with [43], which gave the stream a second
# reader. Same guarantee, same test: the containment measures what a lens left in
# the tree it was judging, and the mechanism's own file must not be in it.
mutation "06 the lens stream is written into the tree it judges" "$LENSES_LIB" \
  's/  printf '"'"'%s\/lens-%s.jsonl\\n'"'"' "\$1" "\$2"/  printf '"'"'lens-%s.jsonl\\n'"'"' "\$2"/' \
  test/lenses.bats "wrote nothing says nothing"

# ── the phase, and what it costs

mutation "06 the lenses are spawned on an already-red gate" "$GATE" \
  's/  if \[ "\$objective_rc" != 0 \]; then/  if false; then/' \
  test/lenses.bats "already red"

# A termination guarantee: taken out, the lens phase waits for a session that never
# returns, so the mutated run does not come back at all. The test that holds it
# carries its own deadline — see the [25] entries for why that is the only shape
# that works here.
mutation "06 a lens that never returns is left to hang" "$GATE" \
  's/^gate__await\(\) \{\n  local dir="\$1" pids="\$2" watchdog='"''"' brc\n/gate__await() {\n  local dir="\$1" pids="\$2" watchdog='"''"' brc\n  GATE_TIMEOUT=0\n/m' \
  test/lenses.bats "deadline of its own"

# ── the fake that drives all of the above

# A fake whose call slots race is a fake that cannot count concurrent sessions, and
# [06] is the first ticket that spawns any. The non-atomic version reported one call
# where three had happened and handed a test whichever prompt won.
mutation "06 the fake allocates its call slots without a test-and-set" "$SHIM" \
  's/  if mkdir "\$state\/claude.calls\/\$n" 2>\/dev\/null; then\n    break\n  fi/  if [ ! -d "\$state\/claude.calls\/\$n" ]; then\n    mkdir -p "\$state\/claude.calls\/\$n"\n    break\n  fi/' \
  test/lenses.bats "tagged ticket, and a sensitive surface"

# ── [31] the seal against its own criterion, and the lens posture ────────────

# The list is one printf per group, which is what makes each group mutable on its
# own: emptying one has to red the test that names that group's paths. The paths
# became one argument each with [33] — one path per line, so that a path carrying
# a space is one path — hence one quoted word per group member below.
mutation "31 what a fresh claude reads is not sealed" "$GATE" \
  's/  printf .%s.n. .CLAUDE.md. .CLAUDE.local.md.\n/  :\n/' \
  test/gate.bats "fresh claude reads"

mutation "31 a project MCP config is not sealed" "$GATE" \
  's/  printf .%s.n. ..mcp.json.\n/  :\n/' \
  test/gate.bats "fresh claude reads"

mutation "31 the capabilities a spawn picks up are not sealed" "$GATE" \
  's/  printf .%s.n. ..claude\/agents. ..claude\/commands. ..claude\/skills. ..claude\/hooks.\n/  :\n/' \
  test/gate.bats "fresh claude reads"

# The config the *next run* sources, under the name it actually carries. Reverting
# to the literal is precisely the defect [31] found: `RALPH_CONFIG` is an
# environment variable, and a run started with another value left its real
# configuration coverable by a write-surface.
mutation "31 the sourced config is sealed under a hard-coded name only" "$GATE" \
  's/^gate__sealed_config\(\) \{\n  local config="\$\{RALPH_CONFIG:-\}" root dir/gate__sealed_config() {\n  local config="" root dir/m' \
  test/gate.bats "under the name it carries"

# The path-shape trap, and it fails *open*: `$PWD` is logical, git answers the
# physical path, so a literal prefix test seals nothing and says nothing about it.
# Aimed at the config side because that is the side that carries it — git normalises
# its own answer, so a `pwd -P` on the root was a line nothing could make red, and
# it is gone rather than sitting here as an entry that always says ok.
mutation "31 the sourced config is compared without resolving its own path" "$GATE" \
  's/  dir="\$\(cd "\$\(dirname "\$config"\)" 2>\/dev\/null \&\& pwd -P\)" \|\| return 0/  dir="\$(dirname "\$config")"/' \
  test/gate.bats "under the name it carries"

# The two channels `--tools` does not govern. Both were probed against the real
# binary on 30/07/2026: an MCP server's command is launched and its tools reach the
# model, and a hook in the project's settings runs on the judge's first tool call.
mutation "31 a lens loads the MCP servers of the tree it judges" "$LENSES_LIB" \
  's/ --strict-mcp-config//' \
  test/lenses.bats "starts sterile"

mutation "31 a lens loads the settings of the tree it judges" "$LENSES_LIB" \
  's/ --setting-sources user//' \
  test/lenses.bats "starts sterile"

# And the fake that holds both. It reports what it would have loaded; a fake that
# always answered "nothing" would make the two entries above pass with the flags
# gone, which is the exact failure mode this file was written for.
mutation "31 the fake reports no MCP server whatever it was called with" "$SHIM" \
  's/if \[ "\$strict_mcp" = 0 \] \&\& \[ -f "\$PWD\/.mcp.json" \]; then/if false; then/' \
  test/lenses.bats "starts sterile"

mutation "31 the fake reports no project config whatever it was called with" "$SHIM" \
  's/  \*,project,\*\) record_config .claude\/settings.json CLAUDE.md ;;/  *,nothing,*) : ;;/' \
  test/lenses.bats "starts sterile"

# ── [27] two tickets, one number ─────────────────────────────────────────────

mutation "27 a stray keeps the number another ticket has" "$FAILURES" \
  's/    if ! renamed_to="\$\(tracker_renumber "\$stray"\)" \|\| \[ -z "\$renamed_to" \]; then/    if true; then/' \
  test/failures.bats "one number"

mutation "27 the renumber moves a ticket nothing collides with" "$TRACKER" \
  's/  if \[ "\$carriers" -le 1 \]; then/  if false; then/' \
  test/tracker-local.bats "nobody shares"

mutation "27 a ticket named after the number alone counts as a collision" "$TRACKER" \
  's/  if \[ ! -f "\$dir\/\$nn.md" \]; then/  if true; then/' \
  test/tracker-local.bats "number alone"

mutation "27 nothing looks at the tracker before the run starts" "$TRACKER_IFACE" \
  's/^tracker_preflight\(\) \{/tracker_preflight() { return 0;/m' \
  test/loop-happy-path.bats "duplicate number is named"

mutation "27 the duplicate is named without saying what it blocks" "$TRACKER_IFACE" \
  's/      tracker__is_ambiguous "\$ids" "\$dep" \|\| continue\n/      continue\n/' \
  test/tracker-local.bats "takes out of the frontier"

mutation "27 the next number is deduced from a session's filenames" "$TRACKER" \
  's/awk .BEGIN \{ m = 0 \} length\(\$1\) <= 15 \{/awk \x27BEGIN { m = 0 } {/' \
  test/tracker-local.bats "too wide to be arithmetic"

mutation "27 the next number is never checked against the directory" "$TRACKER" \
  's/  while tracker_local__number_taken "\$dir" "\$\(printf .%02d. "\$nn"\)"; do\n    nn=\$\(\(nn \+ 1\)\)\n  done\n//' \
  test/tracker-local.bats "checked against the directory"

mutation "27 the finding is printed but never journalled" "$LOOP" \
  's/    loop_journal_append "\$subject" "\$outcome" 0 0 0\n//' \
  test/loop-happy-path.bats "duplicate number is named"

# ── [35] an iteration that delivered nothing ─────────────────────────────────

mutation "35 an iteration that changed no file is resolved" "$GATE" \
  's/^gate__nothing_delivered\(\) \{/gate__nothing_delivered() { return 1;/m' \
  test/gate.bats "answered and wrote nothing resolves nothing"

# The other direction, and it is the one [34] paid for: `nothing changed` and
# `nobody could look` are the same silence, and reading the second as the first
# turns a fail-closed into the very false delivered this ticket exists to refuse.
mutation "35 a measurement it could not take is read as nothing delivered" "$GATE" \
  's/  if \[ -z "\$now" \] \|\| ! changed="\$\(gate_changed_files "\$base" "\$now"\)"; then\n    return 1\n  fi/  changed="\$(gate_changed_files "\$base" "\$now")" || changed=""/' \
  test/gate.bats "could not read is not read as nothing to deliver"

# The findings of `gate_frontier` ride on the scope-guard's output, and the
# scope-guard is not started on this path. Without this loop a session that moved
# an ignore rule and wrote nothing would have its move put back in silence ([30]).
mutation "35 a frontier moved on this path is put back without a word" "$GATE" \
  's/      gate__say "\$ticket: \$finding"/      :/' \
  test/gate.bats "moved the ignore frontier is still told so"

mutation "35 the loop journals it as an ordinary red gate" "$LOOP" \
  's/      \[ "\$\{RALPH_GATE_NOTHING_DELIVERED:-0\}" = 0 \] \|\| outcome=nothing-delivered\n//' \
  test/gate.bats "answered and wrote nothing resolves nothing"

# Renamed rather than deleted: the outcome then falls through to the `*)` arm and
# is classified `crash`, which is what a classifier that does not know about this
# route would make of it.
mutation "35 nothing delivered is classified as something else entirely" "$FAILURES" \
  's/    nothing-delivered\)/    never-happens)/' \
  test/failures.bats "nothing ever delivers"

mutation "35 a ticket nothing delivered is escalated as a failed implementation" "$FAILURES" \
  's/          reason=nothing-delivered\n//' \
  test/failures.bats "nothing ever delivers"

# The note is the whole of the routing on this path — there is no verdict and no
# branch to read — so the way to remove what it promises is to take the question
# out of the sentence.
mutation "35 the escalated ticket does not say what to ask about it" "$FAILURES" \
  's/so the question is why this ticket makes a session do nothing/so somebody should look at it/' \
  test/failures.bats "nothing ever delivers"

mutation "35 a forensic branch is written for an attempt that wrote nothing" "$FAILURES" \
  's/  if \[ -n "\$reason" \] && \[ "\$class" != nothing-delivered \]; then/  if [ -n "\$reason" ]; then/' \
  test/failures.bats "nothing ever delivers"

# And the fake that makes the whole suite mean something now. A session that
# delivers is the cooperative case since [35], so a fake that writes nothing puts
# every green in this suite on the failure path — which is exactly the world the
# defect lived in for thirty-five tickets.
mutation "35 the fake session delivers nothing by default" "$SHIM" \
  's/elif \[ ! -f "\$state\/session.silent" \]; then/elif false; then/' \
  test/gate.bats "green on every branch is what resolves a ticket"

# ── [32] the frontier put back where no gate judged ──────────────────────────
#
# Each entry aims at the *class* that reaches the restore and never at the restore
# itself, which is [30]'s and already has its entries: what this ticket delivers is
# that the two classes nothing gated get there at all.

mutation "32 an iteration no gate judged keeps its widened frontier" "$FAILURES" \
  's/      \[ "\$\{RALPH_GATE_FRONTIER_READ:-0\}" = 1 \] \|\| failures__frontier "\$ticket"/      :/' \
  test/failures.bats "crashed cannot leave the ignore frontier widened"

# The correction placed on the path that happened to be probed — which is exactly
# what [30] shipped, and why every class is named by a test of its own.
mutation "32 only the class the probe used gets its frontier back" "$FAILURES" \
  's/^    crash \| timeout \| budget\)$/    crash)/m' \
  test/failures.bats "cut short cannot leave it widened either"

# And the other way the correction goes wrong: bolted on unconditionally, so the
# paths a gate already handled speak twice about one movement.
#
# The edit takes the whole `case` away and not just its class list, and that is
# [43] rather than convenience: from that ticket on, "one caller per iteration" is
# held by two things — the class list *and* the flag the gate raises once it has
# read the frontier. Widening the list alone leaves the flag holding it, so the
# mutation would apply cleanly and this test would stay green while nothing had
# been removed. Diagnosed rather than rewritten: the guarantee has two owners now,
# so the edit has to remove both.
mutation "32 the restore is bolted onto every class, gated or not" "$FAILURES" \
  's/  case "\$class" in\n    crash \| timeout \| budget\)\n      \[ "\$\{RALPH_GATE_FRONTIER_READ:-0\}" = 1 \] \|\| failures__frontier "\$ticket"\n      ;;\n  esac/  failures__frontier "\$ticket"/' \
  test/failures.bats "once, not twice"

# The cause line behind [24]'s consequence, on the path where `gate__report_frontier`
# never runs: without it a human reads "this rollback could not undo … lib/" with
# nothing saying a session had just decided to hide it.
mutation "32 nothing names the tree rules a crashed session wrote" "$FAILURES" \
  's/  if moved="\$\(gate_moved_tree_rules\)"; then/  if false; then/' \
  test/failures.bats "named before it goes"

# ── [36] a deadline that fires for a run that is gone ────────────────────────
#
# Every entry here has a twin that points the other way, and that is the shape of
# the ticket rather than a habit: two of the three guarantees are ways of *not*
# firing, so a correction that disarmed the deadline outright would satisfy them
# both — and leave the suite green with the deadline gone, which is the false green
# [28] paid for on a fake's sleep.

mutation "36 a deadline fires for a run that is gone" "$GATE" \
  's/  proc_countdown "\$limit" \|\| return 0\n//' \
  test/gate.bats "run that armed it is gone"

mutation "36 a countdown serves out a run that is gone" "$PROC" \
  's/    if proc_owner_gone; then return 1; fi\n//' \
  test/proc.bats "shell that armed it is gone"

mutation "36 a deadline fires at a pid that changed hands" "$GATE" \
  's/    \[ "\$\(proc_parent_of "\$pid"\)" = "\$parent" \] \|\| continue\n//' \
  test/gate.bats "changed hands"

# The other half of the same line, and the piège the ticket wrote down: a deadline
# that gives up as soon as there is nothing left to kill loses the *cause*.
# `gate__aggregate` reads this marker to say "red (timed out)" rather than "red (no
# verdict)", and a branch that overran is where both are true at once.
mutation "36 a deadline that fires at nobody loses the cause" "$GATE" \
  's/  : >"\$marker"\n  for pid in \$aimed; do/  for pid in \$aimed; do/' \
  test/gate.bats "changed hands"

# And the disarming one. It has to name the test that proves the deadline still
# *works*, because every other test of the pack is satisfied by a deadline that
# never fires.
mutation "36 no deadline ever serves its time" "$PROC" \
  's/^proc_countdown\(\) \{/proc_countdown() { return 1;/m' \
  test/gate.bats "run that armed it is there"

mutation "36 the session's grace fires at a pid that changed hands" "$MONITOR" \
  's/  \[ "\$\(proc_parent_of "\$pid"\)" = "\$parent" \] \|\| return 0\n//' \
  test/smart-zone.bats "changed hands"

# What the pack leaves outside the repository. The age condition is the entry that
# would have been vacuous without a fresh directory in the fixture: the run reports
# before it makes any temporary directory of its own, so with only stale ones
# staged the count reads the same either way.
mutation "36 nothing names what earlier runs left in TMPDIR" "$LOOP" \
  's/  while IFS= read -r leftovers; do\n    \[ -n "\$leftovers" \] \|\| continue\n    loop_log "\$leftovers"\n  done <<LEFTOVERS\n\$\(gate_leftovers \|\| true\)\nLEFTOVERS\n//' \
  test/gate.bats "left behind in TMPDIR"

mutation "36 a run beside this one is counted as a leak" "$GATE" \
  's/ -mtime \+0 2>\/dev\/null/ 2>\/dev\/null/' \
  test/gate.bats "left behind in TMPDIR"

# ── [17] languages ───────────────────────────────────────────────────────────
#
# The rule "durable prose is written in LANG_ARTIFACT" lived in the session
# prompt for thirty tickets with nothing keeping it, so almost every entry here
# names a guarantee that used to be a sentence. Two shapes need care.
#
# The refusals — the three in the preflight and the fail-closed in the branch —
# are ways of *not* passing, and a language gate that refused everything would
# satisfy every one of them. Each has a twin below that removes the ability to
# pass and names a green test, the rule [36] wrote down.
#
# And one guarantee is an **absence**: no session this loop spawns is told
# LANG_INTERACT. There is no line to delete, so that mutation *inserts* the key
# into the prompt and the test that must notice is a refutation.

mutation "17 no branch of the gate looks at the language" "$GATE" \
  's/    if lang_enabled; then\n      gate__start "\$dir" lang \\\n        lang_check "\$ticket" "\$base" "\$RALPH_GATE_TREE" "\$dir\/lang.zone"\n      names="\$names lang"\n      pids="\$pids \$!"\n    fi\n\n//' \
  test/lang.bats "another language than LANG_ARTIFACT is red"

mutation "17 the share of the expected language is not compared" "$LANGLIB" \
  's/    \[ \$\(\(hits \* 100\)\) -lt \$\(\(pct \* total\)\) \] \|\| continue/    [ 1 = 0 ] || continue/' \
  test/lang.bats "another language than LANG_ARTIFACT is red"

mutation "17 nothing counts as a prose file" "$LANGLIB" \
  's/  prose="\$\(lang_prose_paths\)"/  prose=""/' \
  test/lang.bats "another language than LANG_ARTIFACT is red"

# The twin of the three above: a branch that refuses everything satisfies them
# all, so this one has to make a green iteration go red.
mutation "17 the language branch refuses every iteration" "$LANGLIB" \
  's/^lang_check\(\) \{/lang_check() { return 1;/m' \
  test/lang.bats "quoted foreign terms and all"

# An edit matches the file, not the config — the half a share against a config
# key cannot express.
mutation "17 an edit is judged against LANG_ARTIFACT, not against the file" "$LANGLIB" \
  's/^lang__expected\(\) \{\n  local base="\$1" file="\$2" total hits dominant dhits/lang__expected() {\n  printf "%s artifact\\\\n" "\${LANG_ARTIFACT:-en}"; return 0;\n  local base="\$1" file="\$2" total hits dominant dhits/m' \
  test/lang.bats "matches the language of the file"

# And where that language is read from. A control whose input the controlled
# writes is not a control: off the working tree, every file matches itself.
#
# The first shape of this entry read `HEAD:$file` and came back VACUOUS, which is
# the finding rather than a mutation to fix: a session does not commit, so at gate
# time HEAD carries exactly what the base tree does. What the controlled writes is
# the *working tree*, and that is the only baseline that is not a baseline.
mutation "17 the language of a file is read after the session, not before" "$LANGLIB" \
  's/\$\(git cat-file -p "\$base:\$file" 2>\/dev\/null \| lang_measure/\$(cat "\$file" 2>\/dev\/null | lang_measure/' \
  test/lang.bats "read from before the session"

# [29] one branch further along: the suite is writing in the working tree while
# this runs, so reading a file off disk returns a verdict nobody else is judging.
mutation "17 the branch reads the working tree instead of the tree it judges" "$LANGLIB" \
  's/\$\(git cat-file -p "\$now:\$file" 2>\/dev\/null \| lang_measure "\$expected"\)/\$(cat "\$file" 2>\/dev\/null | lang_measure "\$expected")/' \
  test/lang.bats "not what the suite writes beside it"

mutation "17 a file with too little prose is judged anyway" "$LANGLIB" \
  's/    if \[ "\$\{total:-0\}" -lt "\$min" \]; then\n      undecided=\$\(\(undecided \+ 1\)\)\n      continue\n    fi\n//' \
  test/lang.bats "too little prose is not judged"

mutation "17 a word two languages claim votes for both" "$LANGLIB" \
  's/          if \(f\[j\] in claim\) \{ if \(claim\[f\[j\]\] != f\[1\]\) claim\[f\[j\]\] = "" \}\n          else claim\[f\[j\]\] = f\[1\]/          claim[f[j]] = f[1]/' \
  test/lang.bats "claim votes for neither"

# The exemption, and the count that keeps it from being a silent off switch.
mutation "17 the pack's own prose is judged against the project's language" "$LANGLIB" \
  's/    if gate_under_path "\$file" "\$exempt"; then/    if false; then/' \
  test/lang.bats "own files are exempt"

mutation "17 what the exemption took out is not counted" "$LANGLIB" \
  's/      skipped=\$\(\(skipped \+ 1\)\)\n//' \
  test/lang.bats "own files are exempt"

# A name git prints quoted is dropped by the prose glob as well, so removing the
# count is enough to make it vanish in silence — which is the whole point of
# counting it ([39]).
mutation "17 a name nothing can address vanishes in silence" "$LANGLIB" \
  's/      unaddressable=\$\(\(unaddressable \+ 1\)\)\n//' \
  test/lang.bats "prints quoted is counted"

mutation "17 the coverage line is never printed" "$GATE" \
  's/^gate__report_lang\(\) \{/gate__report_lang() { return 0;/m' \
  test/lang.bats "too little prose is not judged"

mutation "17 a run with the gate off looks like a run that was checked" "$GATE" \
  's/    gate__say "\$ticket: the language gate is off \(LANG_CHECK=off\): nothing here checked what language this iteration wrote its prose in"\n//' \
  test/lang.bats "switch the gate off"

# The fail-closed, and it is deliberately not the scope-guard's.
mutation "17 a tree this branch cannot read is read as having no prose" "$LANGLIB" \
  's/    printf .the language gate could not read the working tree — refusing to pass it\\n.\n    return 1/    return 0/' \
  test/lang.bats "cannot read refuses to pass"

# The preflight's three, each the switched-off-by-typo shape.
mutation "17 a LANG_ARTIFACT with no word list starts the run anyway" "$LANGLIB" \
  's/  if ! lang_known "\$\{LANG_ARTIFACT:-\}"; then/  if false; then/' \
  test/lang.bats "no words for is refused"

mutation "17 a LANG_CHECK that is neither on nor off is read as off" "$LANGLIB" \
  's/  case "\$\{LANG_CHECK:-on\}" in\n    on \| off\) ;;/  case "on" in\n    on | off) ;;/' \
  test/lang.bats "neither on nor off is refused"

mutation "17 a threshold that is not a fraction is taken as it stands" "$LANGLIB" \
  's/exit \(t ~ \/\^\(0\(\\\.\[0-9\]\+\)\?\|1\(\\\.0\+\)\?\|\\\.\[0-9\]\+\)\$\/ && t \+ 0 > 0\) \? 0 : 1/exit 0/' \
  test/lang.bats "not a fraction is refused"

mutation "17 an empty prose list leaves nothing to judge, in silence" "$LANGLIB" \
  's/  if \[ -z "\$\(lang_prose_paths\)" \]; then/  if false; then/' \
  test/lang.bats "silently leave nothing to judge"

mutation "17 a floor of zero words divides by zero instead of judging" "$LANGLIB" \
  's/    .. \| \*\[!0-9\]\* \| 0\)\n      printf .ralph: LANG_CHECK_MIN_HITS/    '"''"' | *[!0-9]*)\n      printf '"'"'ralph: LANG_CHECK_MIN_HITS/' \
  test/lang.bats "silently leave nothing to judge"

# And their twin: a preflight that refuses everything satisfies all five.
mutation "17 the preflight refuses every project" "$LANGLIB" \
  's/^lang_preflight\(\) \{/lang_preflight() { return 1;/m' \
  test/lang.bats "quoted foreign terms and all"

mutation "17 the preflight is never asked" "$GATE" \
  's/  lang_preflight \|\| rc=1\n//' \
  test/lang.bats "no words for is refused"

# The rule handed to the session, and the wiring that hands it over.
mutation "17 the session is told nothing about the language" "$LANGLIB" \
  's/^lang_session_rules\(\) \{/lang_session_rules() { return 0;/m' \
  test/lang.bats "prompt carries LANG_ARTIFACT"

mutation "17 the loop stops asking for the rule" "$LOOP" \
  's/^\$\(lang_session_rules\)\n//m' \
  test/lang.bats "prompt carries LANG_ARTIFACT"

# It says "checked" only where it is. A prompt that claims a guarantee nothing
# keeps is the exact confusion this ticket was opened to remove.
mutation "17 the prompt claims the rule is checked with the gate off" "$LANGLIB" \
  's/  lang_enabled \|\| return 0\n  cat <<RULES\n  This one is checked/  cat <<RULES\n  This one is checked/' \
  test/lang.bats "prompt carries LANG_ARTIFACT"

# The absence. There is no line to remove, so this one puts the key in — and the
# test that has to notice is a refutation.
mutation "17 an AFK session is handed LANG_INTERACT" "$LANGLIB" \
  's/  local artifact="\$\{LANG_ARTIFACT:-en\}"/  local artifact="\${LANG_ARTIFACT:-en} (speaking \${LANG_INTERACT:-en})"/' \
  test/lang.bats "never told LANG_INTERACT"

# ── [08] the usage budget ────────────────────────────────────────────────────
#
# Two shapes need care, and both were written down before the entries.
#
# The refusals — six in the preflight, the cap on a pause, the stop on a weekly
# wall — are ways of *not* spawning, and a budget module that blocked everything
# would satisfy every one of them. Each has a twin here that removes the ability
# to block and names a test that has to stay green ([36]).
#
# And three guarantees are terminations: the cap on a pause, the rule that two
# pauses in a row stop the run, and the stepped sleep a stop can interrupt.
# Removed, they do not fail — they sleep. The tests that carry them bound
# themselves, either by running the loop in the background with a deadline of
# their own or by naming a span the mutated path has to sit through, so a
# mutation that took the bound away comes back red instead of leaving this
# script blocked on a planted defect ([25]).

mutation "08 the budget never blocks a spawn" "$BUDGET" \
  's/^budget_check\(\) \{/budget_check() { return 0;/m' \
  test/budget.bats "a spent session window is waited out"

mutation "08 the budget blocks every spawn" "$BUDGET" \
  's/^budget_check\(\) \{/budget_check() { RALPH_BUDGET_STATE=blocked; RALPH_BUDGET_WINDOW=five_hour; RALPH_BUDGET_RESET=0; RALPH_BUDGET_SOURCE=endpoint; return 1;/m' \
  test/budget.bats "under the thresholds"

mutation "08 a window nothing could read counts as nothing used" "$BUDGET" \
  's/  \[ -n "\$object" \] \|\| return 1/  [ -n "\$object" ] || { printf "0 0\\n"; return 0; }/' \
  test/budget.bats "not read as zero"

mutation "08 the utilisation is never compared to the threshold" "$BUDGET" \
  's/      \[ "\$pct" -ge "\$thresh" \] \|\| continue/      [ 1 = 0 ] || continue/' \
  test/budget.bats "a spent session window is waited out"

mutation "08 the weekly limit is waited out like a session window" "$LOOP" \
  's/      if \[ "\$\{RALPH_BUDGET_WINDOW:-\}" != five_hour \]; then/      if false; then/' \
  test/budget.bats "a weekly limit stops the run"

mutation "08 a reset beyond the cap is slept to anyway" "$BUDGET" \
  's/  \[ "\$span" -le "\$\{BUDGET_MAX_PAUSE:-21600\}" \] \|\| return 1\n//' \
  test/budget.bats "further out than the cap"

mutation "08 a window still blocked after its reset is waited out again" "$LOOP" \
  's/      if \[ "\$budget_paused" = 1 \]; then/      if false; then/' \
  test/budget.bats "still blocked after its own reset"

mutation "08 a pause holds the stop until the reset" "$BUDGET" \
  's/    \[ "\$\{RALPH_STOP:-0\}" = 0 \] \|\| return 1\n//' \
  test/budget.bats "honoured now, not at the reset"

mutation "08 the cached answer survives the pause it preceded" "$BUDGET" \
  's/      BUDGET__CACHE_BODY=..\n      BUDGET__CACHE_AT=0\n//' \
  test/budget.bats "a spent session window is waited out"

mutation "08 the endpoint is asked without a User-Agent" "$BUDGET" \
  's/  else\n    curl -sS --max-time 10 \\\n      -H "User-Agent: \$\{USAGE_UA:-\}" \\\n/  else\n    curl -sS --max-time 10 \\\n/' \
  test/budget.bats "with its User-Agent"

mutation "08 the answer is never cached" "$BUDGET" \
  's/"\$\{USAGE_CACHE_TTL:-180\}"/0/' \
  test/budget.bats "two iterations, one question"

mutation "08 the cache never expires" "$BUDGET" \
  's/"\$\{USAGE_CACHE_TTL:-180\}"/999999/' \
  test/budget.bats "a cache that expires"

mutation "08 the classifier is never asked" "$LOOP" \
  's/    failed \| nothing-delivered\)/    never-a-real-outcome)/' \
  test/budget.bats "not an attempt at the ticket"

mutation "08 a red gate is forgiven for being hungry" "$LOOP" \
  's/    failed \| nothing-delivered\)/    failed | nothing-delivered | gate-red)/' \
  test/budget.bats "not forgiven for being hungry"

mutation "08 a session a deadline cut is read as a budget pause" "$LOOP" \
  's/    failed \| nothing-delivered\)/    failed | nothing-delivered | session-stalled)/' \
  test/budget.bats "whatever its stream says about quota"

mutation "08 a refused session is billed a retry" "$FAILURES" \
  's/^    budget\)\n      # No count/    budget-never-matches)\n      # No count/m' \
  test/budget.bats "not an attempt at the ticket"

mutation "08 a refused ticket is left claimed" "$FAILURES" \
  's/    tracker_unclaim "\$ticket"\n    RALPH_FAILURE_ACTION=given-back\n    failures__log "\$ticket: given back with no retry/    RALPH_FAILURE_ACTION=given-back\n    failures__log "\$ticket: given back with no retry/' \
  test/budget.bats "not an attempt at the ticket"

mutation "08 the disposition line says a retry was spent" "$FAILURES" \
  's/  elif \[ "\$class" = budget \]; then/  elif false; then/' \
  test/budget.bats "not an attempt at the ticket"

mutation "08 a refused session keeps its writes for the next iteration to adopt" "$FAILURES" \
  's/  failures_rollback "\$pre" "\$base" "\$tree" \|\| true/  [ "\$class" = budget ] || failures_rollback "\$pre" "\$base" "\$tree" || true/' \
  test/budget.bats "does not leave half a file"

mutation "08 a refused session keeps the ignore frontier it widened" "$FAILURES" \
  's/^    crash \| timeout \| budget\)$/    crash | timeout)/m' \
  test/budget.bats "widened by a refused session"

mutation "08 the in-band signal is never believed" "$BUDGET" \
  's/^budget_refused\(\) \{/budget_refused() { return 1;/m' \
  test/budget.bats "when the endpoint says nothing"

mutation "08 every session looks refused" "$BUDGET" \
  's/^budget_refused\(\) \{/budget_refused() { return 0;/m' \
  test/budget.bats "still a crash"

mutation "08 the opus limit gates a run that does not spend it" "$BUDGET" \
  's/      if \[ "\$name" = seven_day_opus \] && ! budget__spends_opus; then/      if false; then/' \
  test/budget.bats "only by a run that spends it"

mutation "08 the opus limit is never watched" "$BUDGET" \
  's/^budget__spends_opus\(\) \{/budget__spends_opus() { return 1;/m' \
  test/budget.bats "stops a run that does spend it"

mutation "08 a budget that is off is asked anyway" "$BUDGET" \
  's/^budget_enabled\(\) \{/budget_enabled() { return 0;/m' \
  test/budget.bats "run without a usage budget"

mutation "08 the budget is off for every project" "$BUDGET" \
  's/^budget_enabled\(\) \{/budget_enabled() { return 1;/m' \
  test/budget.bats "a spent session window is waited out"

mutation "08 what nobody watched is never said" "$BUDGET" \
  's/^budget__say_once\(\) \{/budget__say_once() { return 0;/m' \
  test/budget.bats "run without a usage budget"

mutation "08 the preflight is never asked" "$LOOP" \
  's/  budget_preflight \|\| rc=1\n//' \
  test/budget.bats "neither on nor off is refused"

mutation "08 the preflight refuses every project" "$BUDGET" \
  's/^budget_preflight\(\) \{/budget_preflight() { return 1;/m' \
  test/budget.bats "under the thresholds"

mutation "08 a BUDGET_CHECK that is neither on nor off is read as off" "$BUDGET" \
  's/  case "\$\{BUDGET_CHECK:-on\}" in\n    on \| off\) ;;/  case "on" in\n    on | off) ;;/' \
  test/budget.bats "neither on nor off is refused"

mutation "08 a threshold that is not a fraction is taken as it stands" "$BUDGET" \
  's/  if ! budget__is_fraction "\$\{THRESH_5H:-\}"; then/  if false; then/' \
  test/budget.bats "not a fraction is refused"

mutation "08 an empty User-Agent starts a run that can only collect 429s" "$BUDGET" \
  's/  if \[ -z "\$\{USAGE_UA:-\}" \]; then/  if false; then/' \
  test/budget.bats "unmeasured in silence"

mutation "08 an endpoint nobody named is asked anyway" "$BUDGET" \
  's/  if \[ -z "\$\{USAGE_URL:-\}" \]; then/  if false; then/' \
  test/budget.bats "unmeasured in silence"

mutation "08 a cap of zero turns every window into a stopped run, in silence" "$BUDGET" \
  's/  case "\$\{BUDGET_MAX_PAUSE:-\}" in/  case "21600" in/' \
  test/budget.bats "unmeasured in silence"

mutation "08 a cache TTL nobody can read is taken as it stands" "$BUDGET" \
  's/  case "\$\{USAGE_CACHE_TTL:-\}" in/  case "180" in/' \
  test/budget.bats "unmeasured in silence"

# Not a guarantee of the pack but of the suite, and it is the finding this ticket
# tripped over: the surface list only ever checked one of its two directions, so
# three keys [17] added were missing from it and nothing noticed.
mutation "08 a config key nobody listed goes unnoticed" "$EXAMPLE" \
  's/^BUDGET_CHECK=/BUDGET_UNLISTED="x"\nBUDGET_CHECK=/m' \
  test/smoke.bats "configuration surface"

# ── [13] per-ticket concurrency ──────────────────────────────────────────────

mutation "13 an iteration runs in the tree the run was started in" "$LOOP" \
  's/^loop__iterate\(\) \{/loop__iterate() { set -- "\$1" "\$2" "\$(ralph_project_root)" "\$4";/m' \
  test/loop-happy-path.bats "isolated worktree"

# Anchored on the line above it, and that is the header's own warning read the
# hard way: `  concurrency_worktree_drop "$tree"` also matches *inside* the
# four-space copy on the error path, which comes first in the file — so the
# mutation applied cleanly to a branch nothing takes and reported VACUOUS about
# a test that was fine.
mutation "13 the worktree is never given back" "$LOOP" \
  's/  rm -rf "\$pin"\n  concurrency_worktree_drop "\$tree"\n/  rm -rf "\$pin"\n/' \
  test/concurrency.bats "gives it back"

mutation "13 the parallelism cap is ignored" "$LOOP" \
  's/    if \[ "\$\(loop__inflight_count\)" -ge "\$CONCURRENCY_CAP" \]; then/    if false; then/' \
  test/concurrency.bats "one after the other"

mutation "13 MAX_PARALLEL means nothing" "$CONCURRENCY" \
  's/^concurrency_cap\(\) \{/concurrency_cap() { CONCURRENCY_CAP=1; return 0;/m' \
  test/concurrency.bats "ground at the same time"

mutation "13 a nearly spent window buys the whole cap" "$CONCURRENCY" \
  's/  slots=\$\(\(\(want \* head \+ 99\) \/ 100\)\)/  slots="\$want"/' \
  test/concurrency.bats "buys fewer slots"

mutation "13 nothing says the subscription is unmeasured" "$CONCURRENCY" \
  's/    concurrency__say_once headroom \\\n      "no usage window was measured[^\n]*\n/    :\n/' \
  test/concurrency.bats "buys fewer slots"

mutation "13 two tickets never clash" "$CONCURRENCY" \
  's/^concurrency_clashes\(\) \{/concurrency_clashes() { return 1;/m' \
  test/concurrency.bats "sequenced, whatever MAX_PARALLEL"

mutation "13 a ticket with no write-surface runs beside anything" "$CONCURRENCY" \
  's/  mine="\$\(gate_write_surface "\$ticket"\)"\n  \[ -n "\$mine" \] \|\| return 0/  mine="\$(gate_write_surface "\$ticket")"/' \
  test/concurrency.bats "in both directions"

mutation "13 the surfaces are matched one way round only" "$CONCURRENCY" \
  's/      gate_in_surface "\$theirs" "\$entry" && return 0\n//' \
  test/concurrency.bats "in both directions"

mutation "13 the fold is a write, not a compare-and-swap" "$CONCURRENCY" \
  's/git update-ref -m "ralph: \$ticket" HEAD "\$commit" "\$tip" 2>\/dev\/null/git update-ref -m "ralph: \$ticket" HEAD "\$commit" 2>\/dev\/null/' \
  test/concurrency.bats "never overwrites a branch tip"

mutation "13 a fold nobody serialized" "$CONCURRENCY" \
  's/^concurrency__wait_for_guard\(\) \{/concurrency__wait_for_guard() { return 1;/m' \
  test/concurrency.bats "one commit each"

mutation "13 a sibling's commit is replayed over instead of onto" "$CONCURRENCY" \
  's/  if \[ "\$tip" = "\$start" \]; then/  if true; then/' \
  test/concurrency.bats "one commit each"

mutation "13 every fold rebuilds the commit instead of fast-forwarding" "$CONCURRENCY" \
  's/  if \[ "\$tip" = "\$start" \]; then/  if false; then/' \
  test/concurrency.bats "fast-forward onto the very commit"

mutation "13 the tree the run was started in is left behind the branch" "$CONCURRENCY" \
  's/  \[ "\$rc" = 0 \] && concurrency__refresh "\$changed"\n//' \
  test/concurrency.bats "follows the branch"

mutation "13 a green iteration that never reached the branch is resolved anyway" "$LOOP" \
  's/      if \[ -n "\$commit" \] &&\n        concurrency_integrate "\$ticket" "\$start" "\$commit" "\$changed"; then/      if true; then/' \
  test/concurrency.bats "never overwrites a branch tip"

mutation "13 a fold that could not reach the branch does not stop the run" "$LOOP" \
  's/  if \[ "\$outcome" = not-integrated \]; then\n    loop_log "\$ticket: the gate was green and the work did not reach the branch — stopping"\n    stop_code=4\n  fi\n//' \
  test/failures.bats "stops the run rather than resolving nothing"

# DRIFTED when [37] made this list travel one id per line: the exemption used to be
# an inline `case "$held" in *" $id "*`, and it is now one call to `claim__among`,
# which compares whole lines. The guarantee is the same one and it is still carried
# — checked before this anchor was moved, not after — so what changed here is the
# line that carries it and nothing else. The entry two below still removes the
# *comparison*; this one still removes the exemption.
mutation "13 the sweep reclaims the claims this run is holding" "$CLAIM" \
  's/    claim__among "\$id" "\$held" && continue\n//' \
  test/concurrency.bats "does not reclaim a claim this run is holding"

mutation "13 the sweep is not told what is in flight" "$LOOP" \
  's/claim_reclaim_stale "\$\(loop__inflight_ids\)"/claim_reclaim_stale/' \
  test/concurrency.bats "does not reclaim a claim this run is holding"

# The assignment moved into the shared reader when [42] gave the same definition
# to the quarantine, so the anchor carries the line *after* it: the same
# assignment now appears in both guards, and an anchor matching both would edit
# the first and report VACUOUS about a healthy test.
mutation "13 the tracker guard does not know what the loop wrote" "$FAILURES" \
  's/  ours="\$\(failures__register_since "\$mark"\)"\n  idx=/  ours=" "\n  idx=/' \
  test/failures.bats "the loop wrote itself is left alone"

# Both entries name the lib-level test and not the parallel run, and that is a
# lesson rather than a preference. Through the loop, the defect only shows when
# the pilot claims the sibling *after* the first iteration has snapshotted the
# tickets — a few command substitutions apart, and under the load of a full pass
# the order flips. The property itself has nothing to do with timing: it is "a
# path the loop wrote is not the session's doing", and it is stated where it can
# be staged exactly.
mutation "13 the loop records none of its own tracker writes" "$TRACKER_IFACE" \
  's/^tracker__note_write\(\) \{/tracker__note_write() { return 0;/m' \
  test/failures.bats "the loop wrote itself is left alone"

# No entry for the *order* of those two lines (`mark` taken before the tickets are
# snapshotted), and it is a deliberate hole rather than an oversight. Swapping
# them only matters when the pilot claims a sibling in the microseconds between
# them: over-excluding leaves a ticket alone, under-excluding destroys a claim.
# Nothing can stand in that window on purpose — the same shape as the race
# `proc_collect` documents and declines to close — so an entry here would be a
# coin toss reported as coverage. The margin is written where it is taken.

mutation "13 an iteration that died without a verdict keeps its ticket" "$LOOP" \
  's/      tracker_unclaim "\$ticket"\n    fi\n    loop_log "\$ticket: the iteration died without a verdict/      :\n    fi\n    loop_log "\$ticket: the iteration died without a verdict/' \
  test/concurrency.bats "dies without a verdict"

mutation "13 a child that died hard is waited for for ever" "$LOOP" \
  's/      if \[ -e "\$slot\/done" \] \|\| ! kill -0 "\$pid" 2>\/dev\/null; then/      if [ -e "\$slot\/done" ]; then/' \
  test/concurrency.bats "dies without a verdict"

# Aimed at the whole block and not at its `break`, and the difference is a lesson
# about what this block does. While any iteration is in flight the pilot is inside
# a blocking collection, so it never *reaches* here — what keeps the iterations is
# `loop__reap 1`, and a mutation on the `break` is invisible by construction. What
# this block decides is the other half: with a stop pending, nothing new is
# scheduled. Removed, the run goes on claiming whatever became eligible and comes
# back reporting a drained frontier.
mutation "13 a stop schedules new work anyway" "$LOOP" \
  's/    if \[ -n "\$stop_code" \]; then\n      \[ -n "\$LOOP_SLOTS" \] \|\| break\n      loop__reap 1\n      continue\n    fi/    if false; then\n      break\n    fi/' \
  test/concurrency.bats "iterations in flight finish"

mutation "13 nothing is provisioned into the worktree" "$CONCURRENCY" \
  's/    cp -R "\$root\/\$path" "\$dir\/\$path" 2>\/dev\/null \|\| \{/    true || {/' \
  test/concurrency.bats "copies what the project names"

mutation "13 what the pilot provisioned is never said" "$LOOP" \
  's/    loop_log "\$ticket: \$provisioned path\(s\) provisioned into this iteration.s worktree[^\n]*"\n/    :\n/' \
  test/concurrency.bats "copies what the project names"

mutation "13 a repository with no commit is ground anyway" "$CONCURRENCY" \
  's/^concurrency_preflight\(\) \{/concurrency_preflight() { return 0;/m' \
  test/concurrency.bats "no commit is refused"

mutation "13 a MAX_PARALLEL nobody can read is read as one" "$CONCURRENCY" \
  's/  case "\$\{MAX_PARALLEL:-1\}" in\n    .. \| \*\[!0-9\]\* \| 0\)/  case "\${MAX_PARALLEL:-1}" in\n    never-a-real-value)/' \
  test/concurrency.bats "refused rather than read as 1"

mutation "13 the local excludes are read from the worktree's private git dir" "$GATE" \
  's/  gitdir="\$\(git rev-parse --git-common-dir 2>\/dev\/null\)" \|\| gitdir=""/  gitdir="$(git rev-parse --git-dir 2>\/dev\/null)" || gitdir=""/' \
  test/gate.bats "widen the blind zone through .git/info/exclude"

mutation "13 the sealed config is resolved against the worktree, not the project" "$GATE" \
  's/  root="\$\(cd "\$\(ralph_project_root\)" 2>\/dev\/null && pwd -P\)" \|\| return 0/  root="$(git rev-parse --show-toplevel 2>\/dev\/null)" || return 0/' \
  test/gate.bats "sealed under the name it carries"

# ── [40] the register of the loop's own tracker writes ───────────────────────

# `export VAR` before the assignment is the same thing as after it, and it is the
# form that gives this entry a unique anchor: `RALPH_TRACKER_LOG=''` carries a
# quote the expression would have to fight, and the bare name appears in the
# comment above it.
#
# Aimed at a test that asserts on the **tracker and the branch** — the ticket's
# write-surface put back, `rogue/backdoor` absent from HEAD — and not at the one
# that lists the environment. Both go red, and only one of them says what the
# export costs: a session told this path buys itself a surface of `*`, and the
# iteration commits and folds a file the ticket never declared. An entry aimed at
# the environment listing would report `ok` for a fix that hid the name somewhere
# else and left the delivery open.
mutation "40 the register is handed to the session in its environment" "$LOOP" \
  's/  RALPH_TRACKER_LOG="\$\(mktemp/  export RALPH_TRACKER_LOG\n  RALPH_TRACKER_LOG="\$(mktemp/' \
  test/failures.bats "switch the guard off"

# ── [42] the two guards over the tracker read that register ──────────────────

# One entry per guard, because that is exactly what went wrong: the register had
# one producer and one consumer, and each of the two unwired call sites breaks a
# different scenario. An entry aimed at "the register exists" would have reported
# `ok` for the state this ticket found.
#
# Both are aimed at a **defeated ticket** and never at a log line. The sibling's
# marking undone is what the run pays for — a ticket delivered, committed, folded,
# and then put back `claimed` under a pid nobody will release — while the line
# saying the tracker was edited is a symptom the fix could route around.
mutation "42 the re-slice hands its guard the register" "$FAILURES" \
  's/  if ! failures_protect_tracker "\$ticket" "\$issues" "\$mark"; then/  if ! failures_protect_tracker "\$ticket" "\$issues"; then/' \
  test/concurrency.bats "a re-slice beside a marking"

# Anchored on the line *after* it: the same assignment appears in
# `failures_protect_tracker`, and an anchor matching both would mutate the first
# one and report VACUOUS about a test that is fine — the shape this file's header
# warns about twice.
mutation "42 the quarantine reads the register" "$FAILURES" \
  's/  ours="\$\(failures__register_since "\$mark"\)"\n\n  # Renumbered before it is escalated/  ours=" "\n\n  # Renumbered before it is escalated/' \
  test/concurrency.bats "children of a sibling's re-slice"

# And the half of it that is not a call site: a creation is noted under the id it
# produced rather than the slug it was handed. Note the slug and every reader is
# comparing against a name no ticket carries — the guards go on reading a register
# and go on being wrong, which is the failure mode this ticket is about.
mutation "42 a creation is noted under the id it produced" "$TRACKER_IFACE" \
  's/      \[ -z "\$out" \] \|\| printf .%s\\n. "\$out"\n      tracker__note_write "\$out"/      [ -z "\$out" ] || printf "%s\\n" "\$out"\n      tracker__note_write "\${1:-}"/' \
  test/failures.bats "left alone by the quarantine"

# ── [44] a run that is gone, and an iteration that goes on delivering ────────
#
# Every entry here comes in a pair, the way [36]'s do and for a sharper reason.
# What this ticket adds is a *refusal*, and a correction that refused everything
# would satisfy every entry aimed at the refusal while taking back exactly what
# [25] and [28] paid for — "the current iteration finishes". So each entry that
# removes the refusal has a twin that removes the capacity to act, and every twin
# names a test that proves an iteration still finishes when its run is merely
# *asked* to stop.
#
# The four aimed at `loop.sh` past the first pair are about **where** the question
# is asked, which is the ticket rather than a detail: one check at the entry leaves
# the whole window of the session and of the gate, and each of the four sites below
# is the far end of a window nothing else covers.

mutation "44 an iteration never records which run forked it" "$LOOP" \
  's/  if ! proc_owner_take "\$\$"; then/  if ! true; then/' \
  test/concurrency.bats "run was killed"

mutation "44 an iteration stands down whatever its run is doing" "$LOOP" \
  's/  if ! proc_owner_take "\$\$"; then/  if ! false; then/' \
  test/concurrency.bats "grinds two disjoint tickets"

mutation "44 the orphan question always answers no" "$LOOP" \
  's/  proc_owner_gone \|\| return 1\n  loop__stand_down/  return 1\n  loop__stand_down/' \
  test/concurrency.bats "run was killed"

mutation "44 the orphan question always answers yes" "$LOOP" \
  's/  proc_owner_gone \|\| return 1\n  loop__stand_down/  :\n  loop__stand_down/' \
  test/concurrency.bats "iterations in flight finish"

# Anchored on the line that follows each one: the four call sites are the same
# three lines, so an anchor on the interesting token would edit the first of them
# and report VACUOUS about a test that is fine — the shape this file's header warns
# about twice.
mutation "44 nothing is asked between the session and the gate" "$LOOP" \
  's/  if loop__orphaned "\$ticket" "\$slot"; then\n    return 0\n  fi\n\n  # Before anything below reads/  # Before anything below reads/' \
  test/concurrency.bats "run was killed"

mutation "44 nothing is asked between the gate and the commit" "$LOOP" \
  's/      if loop__orphaned "\$ticket" "\$slot"; then\n        return 0\n      fi\n      # Durable inside this worktree first/      # Durable inside this worktree first/' \
  test/concurrency.bats "dies during the gate"

mutation "44 nothing is asked between the gate and the failure policy" "$LOOP" \
  's/      if loop__orphaned "\$ticket" "\$slot"; then\n        return 0\n      fi\n      failures_handle/      failures_handle/' \
  test/concurrency.bats "bills the ticket nothing"

mutation "44 an orphan gives back a claim it no longer owns" "$LOOP" \
  's/        if loop__orphaned "\$ticket" "\$slot"; then\n          return 0\n        fi\n        tracker_unclaim/        tracker_unclaim/' \
  test/concurrency.bats "refuses on its own account"

# And the one refusal that is not the caller's to make: the fold waits on a guard
# `state_guard_take` would hand to an orphan, in the name of a run that is gone.
mutation "44 the fold takes the guard for a run that is gone" "$CONCURRENCY" \
  's/  if proc_owner_gone; then\n/  if false; then\n/' \
  test/concurrency.bats "refuses on its own account"

mutation "44 the fold refuses whatever the run is doing" "$CONCURRENCY" \
  's/  if proc_owner_gone; then\n/  if true; then\n/' \
  test/concurrency.bats "fast-forward onto the very commit"

# The primitive under all of it. The first is the fail-closed half, and its test
# is a *deadline* rather than an iteration — an iteration hands `$$` in, so an
# unreadable link is caught one line lower by the link check itself, and this entry
# reported VACUOUS against the iteration test that looked like the obvious one. The
# second is the half that makes an owner handed in worth handing in: without it, a
# pilot that died between the fork and the child's first line is accepted as owner.
mutation "44 an owner nobody can read is taken all the same" "$PROC" \
  's/  \[ -n "\$PROC_OWNER" \] && \[ "\$PROC_OWNER" != 0 \] \|\| return 1\n//' \
  test/proc.bats "cannot read a parent link"

mutation "44 no shell can ever take an owner" "$PROC" \
  's/^proc_owner_take\(\) \{/proc_owner_take() { return 1;/m' \
  test/concurrency.bats "grinds two disjoint tickets"

mutation "44 an owner that is already gone is taken all the same" "$PROC" \
  's/  if proc_owner_gone; then\n    return 1\n  fi\n  return 0\n\}/  return 0\n}/' \
  test/proc.bats "owner handed in is refused"

# ── [41] the ignore frontier is billed to whoever looked first ───────────────
#
# Every entry here aims at the **attribution** and never at the restore. [30]
# already covers "the file goes back" from four angles, and a fix that put the
# file back while leaving the author green is exactly the fix this ticket refuses
# — so a mutation that only broke the restore would report `ok` about a guarantee
# nobody delivered here.

# The register itself: the movement recorded by whichever gate looked first is
# what every iteration behind it reads. Without it, an iteration is charged for
# what it saw with its own eyes — which is the pack before this ticket, and the
# author of the widening walks.
mutation "41 a movement is not recorded for the iterations in flight" "$GATE" \
  's/^gate__frontier_record\(\) \{/gate__frontier_record() { return 0;/m' \
  test/concurrency.bats "charged to every iteration in flight"

# The same hole from the reading side, and it is a separate entry because it is a
# separate half: a run that records faithfully and then only ever reports what it
# detected itself is the same false green.
mutation "41 an iteration reads only what it saw itself" "$GATE" \
  's/^gate__frontier_share\(\) \{/gate__frontier_share() { printf "%s\\\\n" "\$1"; return 0;/m' \
  test/concurrency.bats "charged to every iteration in flight"

# The mark. Reading the whole register instead of what landed after this
# iteration's spawn bills every iteration of the night for a movement that was
# over before it started — the overcharge in the other direction, and the witness
# at MAX_PARALLEL=1 is where it shows.
#
# Aimed at the definition and not at either reader, and that is not a shortcut:
# the first version of this entry anchored on the line that reads the mark, which
# by then existed twice — it edited `gate__frontier_pin_broken` and reported VACUOUS
# about a test that was fine. The two readers now share one definition, so the
# anchor is unique by construction.
mutation "41 the register is read from the beginning of the run" "$GATE" \
  's/^gate__frontier_mark\(\) \{/gate__frontier_mark() { printf "0\\\\n"; return 0;/m' \
  test/concurrency.bats "sequenced bills the session that wrote"

# What nobody can be charged for, said out loud. A bill that cannot be contested
# and is not explained is the half-truth this pack refuses everywhere else.
mutation "41 nothing names what cannot be attributed" "$GATE" \
  's/  \[ "\$foreign" = 0 \] \|\| printf/  [ 1 = 0 ] \&\& printf/' \
  test/concurrency.bats "charged to every iteration in flight"

# And that the line is a *consequence of concurrency* rather than decoration:
# printed unconditionally it appears at MAX_PARALLEL=1, where the iteration that
# looked is the only one that could have written.
mutation "41 the unattributable line is printed whatever the run does" "$GATE" \
  's/  \[ "\$foreign" = 0 \] \|\| printf/  [ 0 = 0 ] \&\& printf/' \
  test/concurrency.bats "sequenced bills the session that wrote"

# The run-level witness of the sources every worktree shares. Without it the pin
# takes its baseline from disk, so an iteration that spawns mid-widening pins the
# widening — and its own restore puts it back over its sibling's witness.
mutation "41 the shared frontier is witnessed once per iteration again" "$GATE" \
  's/^gate__frontier_common_copy\(\) \{\n  local slot="\$1" dest="\$2" live="\$3" common="\$\{RALPH_FRONTIER_COMMON:-\}"/gate__frontier_common_copy() {\n  local slot="\$1" dest="\$2" live="\$3" common=""/m' \
  test/gate.bats "while the frontier was widened"

mutation "41 the pin's manifest reads the shared sources from disk" "$GATE" \
  's/^gate__frontier_pin_manifest\(\) \{\n  local common="\$\{RALPH_FRONTIER_COMMON:-\}"/gate__frontier_pin_manifest() {\n  local common=""/m' \
  test/gate.bats "while the frontier was widened"

# And the loop refusing to start without it, which is what keeps the fallback in
# the library from being the shipped behaviour.
mutation "41 a run with no witness of the shared frontier starts anyway" "$LOOP" \
  's/  if ! RALPH_FRONTIER_COMMON="\$\(gate_frontier_common\)"; then/  RALPH_FRONTIER_COMMON="\$(gate_frontier_common)" || RALPH_FRONTIER_COMMON=""\n  if false; then/' \
  test/gate.bats "witness of the shared frontier"

# The guard that orders the restore. Two iterations detecting and restoring at
# once record one widening twice, so the same movement is billed twice to whoever
# was in flight.
mutation "41 the restore is not ordered between worktrees" "$GATE" \
  's/  if concurrency_frontier_take; then took=1; fi/  :/' \
  test/gate.bats "restore is taken under a guard"

# And the guard released only when it was taken: `state_guard_release` matches on
# `$$`, which every subshell of the pilot shares, so an iteration that timed out
# waiting would take the guard away from the one holding it.
mutation "41 a guard that was never taken is released all the same" "$GATE" \
  's/  if \[ "\$took" = 1 \]; then concurrency_frontier_release \|\| true; fi/  concurrency_frontier_release || true/' \
  test/gate.bats "released only by the iteration that took it"

# What [41] delivers on a path no gate judged is that the movement reaches the
# **siblings**, and this entry has moved once, for the reason [43]'s note three
# entries up gives. It used to be [32]'s own edit — take `failures__frontier` off
# the crash path and nothing recorded the widening — judged by this other
# producer's test. [46] gave that guarantee a second and **earlier** owner:
# `loop__iterate` puts the frontier back the moment its session returns, so the
# crash path records through that instead, and the old edit came back VACUOUS
# about a test that was fine. Diagnosed rather than rewritten. Both owners write
# the register through this one line, so this is the line that removes the
# guarantee on every path; [32]'s entry keeps the old edit, which still removes
# what only `failures__frontier` does — the sentence on the crashed iteration's
# own document.
mutation "41 a crashed iteration's movement never reaches its siblings" "$GATE" \
  's/    printf \x27%s\\t%s\\n\x27 "\$tag" "\$line" >>"\$common\/ledger"/    :/' \
  test/concurrency.bats "no gate judges is still charged"

# Fail-closed on the two things [41] added to `$TMPDIR`. Both had a fallback that
# reads the live sources, so a session that destroyed either would have bought back
# the pack before this ticket — quietly, where destroying the pin stops the night.
mutation "41 a destroyed run witness reads as no witness at all" "$GATE" \
  's/  \[ -f "\$common\/manifest" \] && \[ -f "\$common\/exclude" \] &&\n    \[ -f "\$common\/attributes" \] && \[ -f "\$common\/ledger" \] \|\| return 0\n//' \
  test/gate.bats "closes the control, like a destroyed pin"

mutation "41 a register that got shorter is nobody's business" "$GATE" \
  's/  \[ "\$total" -lt "\$seen" \] && return 0\n//' \
  test/gate.bats "register of movements that got shorter"

# ── [43] the other half of the iteration, priced ─────────────────────────────
#
# An iteration is `1 + n` sessions, and [08]'s classifier was wired to the one.
# Everything here is about the *difference* a missing verdict can have as its
# reason, so every entry below either makes the pack blind to a refusal or makes
# it credulous about one — and the second direction is the dangerous one: this
# signal comes out of a file a concurrent session can write, so what it may buy is
# a give-back and never a green.

mutation "43 a refused lens is never noticed" "$LENSES_LIB" \
  's/^lenses_refused_posture\(\) \{/lenses_refused_posture() { return 1;/m' \
  test/budget.bats "costs the ticket what a refused delivery session costs"

mutation "43 a lens that answered is read as refused all the same" "$LENSES_LIB" \
  's/  \[ "\$\(lenses__verdict "\$stream"\)" = none \] \|\| return 1\n//' \
  test/lenses.bats "told apart from every other way"

mutation "43 a stream that says nothing about quota is read as a refusal" "$LENSES_LIB" \
  's/  budget_refused "\$posture" \|\| return 1\n//' \
  test/budget.bats "without being refused is still an attempt"

# The measurement the pack takes itself, against the claim it reads. Without the
# marker, anything able to hang a lens past `GATE_TIMEOUT` with one blocked line in
# its stream buys the give-back a real refusal buys.
mutation "43 a lens the watchdog killed speaks through its last event" "$GATE" \
  's/  if \[ ! -f "\$dir\/timed-out" \]; then/  if true; then/' \
  test/budget.bats "deadline killed is not read as a refusal"

mutation "43 a refused lens cancels the red of a lens that judged" "$GATE" \
  's/    gate__all_in "\$RALPH_GATE_FAILED" "\$refused"; then/    true; then/' \
  test/budget.bats "does not cancel the red of a lens that judged"

mutation "43 a tree the gate could not put back is forgiven for being hungry" "$GATE" \
  's/  if \[ "\$agg" = 1 \] && \[ "\$contained" = 0 \] && \[ -n "\$refused" \] &&/  if [ "\$agg" = 1 ] \&\& [ -n "\$refused" ] \&\&/' \
  test/budget.bats "could not be put back"

# The signal has to leave the iteration. It is read in a worktree that is about to
# be destroyed, and the only process entitled to decline a spawn is the pilot.
mutation "43 the pilot is never told a lens was refused" "$LOOP" \
  's/  if \[ -n "\$\{RALPH_GATE_QUOTA:-\}" \] &&/  if false \&\&/' \
  test/budget.bats "stops on the budget instead of grinding the frontier"

# And the correction [43] had to make to a table that was already wrong for one
# combination: `budget` is a reason, not a kind of session, so "who put the ignore
# rules back" cannot be answered by its name.
mutation "43 a widening a gate already read is charged again" "$FAILURES" \
  's/      \[ "\$\{RALPH_GATE_FRONTIER_READ:-0\}" = 1 \] \|\| failures__frontier "\$ticket"/      failures__frontier "\$ticket"/' \
  test/budget.bats "not charged to the run twice"

# ── [10] the audit receipt, and a journal worth reading ──────────────────────
#
# Two artefacts with two different standings, and most of these entries are about
# the difference. The receipt is built from what the loop measured; the journal is
# a file the judged session can rewrite, so what it earns is detection and never
# authority. An entry that made the receipt read the journal is therefore a
# mutation like any other here — it removes the guarantee by changing where a
# number comes from, not by deleting a line.

mutation "10 no receipt is written at all" "$RECEIPT" \
  's/^receipt_emit\(\) \{/receipt_emit() { return 0;/m' \
  test/receipt.bats "leaves an audit receipt naming its verdicts"

mutation "10 every iteration writes one, superseded or not" "$LOOP" \
  's/^  \[ "\$outcome" != resolved \] \|\| emit=1$/  emit=1/m' \
  test/receipt.bats "only goes back to the frontier"

mutation "10 an escalation ends the ticket without a document" "$LOOP" \
  's/^  case "\$\{RALPH_FAILURE_ACTION:-none\}" in escalated:\*\) emit=1 ;; esac\n//m' \
  test/receipt.bats "a fresh retry does not"

# What the gate collected dies with the gate's own directory unless something
# copies it out in time ([06]). The first entry removes the copy; the second
# shrinks it back to what already scrolled past on stdout, which is the version
# that looks like it works.
mutation "10 a red branch's output dies with the gate" "$GATE" \
  's/^    receipt_keep_branch "\$name" "\$dir\/\$name.out"\n//m' \
  test/receipt.bats "survive the gate"

mutation "10 the receipt keeps only what already scrolled past" "$RECEIPT" \
  's/^    tail -"\$RECEIPT_MAX_LINES" "\$file"$/    tail -20 "\$file"/m' \
  test/receipt.bats "outlives the gate that collected it"

mutation "10 a truncated branch is quoted as if it were whole" "$RECEIPT" \
  's/^    if \[ "\$total" -gt "\$RECEIPT_MAX_LINES" \]; then$/    if false; then/m' \
  test/receipt.bats "counted rather than silently cut"

# The zones nothing judged, said out loud during the night and kept only here.
mutation "10 what the gate did not judge is said and not kept" "$GATE" \
  's/^  receipt_note "\$@"\n//m' \
  test/receipt.bats "zone nothing in the gate judged"

# [43] where it can actually reach a document: a lens the API refused beside a
# lens that answered `fail` is a billable gate, so the verdict line says red for a
# branch that judged nothing.
mutation "10 a refused lens reaches the receipt as a plain red" "$GATE" \
  's/^        gate__say "\$ticket: the \$name lens judged nothing/        gate__log "\$ticket: the \$name lens judged nothing/m' \
  test/receipt.bats "merely refused is named as such"

mutation "10 the verdicts never reach the receipt" "$LOOP" \
  's/^  receipt_fact verdicts "\$\{RALPH_GATE_VERDICTS:-\}"$/  receipt_fact verdicts ""/m' \
  test/receipt.bats "naming its verdicts"

mutation "10 an empty verdict line passes for a clean one" "$RECEIPT" \
  's/^    printf .No gate ran on this iteration, so there is no verdict here\. An empty verdict line is not a green one\.\\n.$/    printf "\\n"/m' \
  test/receipt.bats "instead of showing an empty verdict line"

mutation "10 an absent branch reads as a passing one" "$RECEIPT" \
  's/A branch that is \*\*absent\*\* above was not run/A branch above was run/' \
  test/receipt.bats "naming its verdicts"

mutation "10 the work is not even referenced" "$LOOP" \
  's/receipt_fact commit "\$commit"/receipt_fact commit ""/' \
  test/receipt.bats "references the work and never inlines it"

# The decision this ticket exists to take ([21]). There is no line that implements
# "does not read `run.log`", so the mutation is the one that makes it read it: the
# receipt's numbers stop being what this process measured and become what the file
# says — which, in the test named here, is what the session wrote into it.
mutation "10 the receipt takes its numbers from the journal" "$LOOP" \
  's/^  receipt_fact turns "\$turns"$/  receipt_fact turns "\$(tr "\\t" "\\n" < "\$(ralph_feature_dir)\/run.log" | sed -n s\/^turns=\/\/p | tail -1)"/m' \
  test/receipt.bats "not built out of the run journal"

# The key this ticket introduced, and the one value of it that empties the audit
# surface without a word.
mutation "10 a receipt that keeps no lines is accepted" "$LOOP" \
  's/^  receipt_preflight \|\| rc=1\n//m' \
  test/receipt.bats "keep no lines is refused at the door"

mutation "10 a workspace shared by every iteration in flight" "$RECEIPT" \
  's/^  dir="\$\(mktemp -d "\$\{TMPDIR:-\/tmp\}\/ralph-receipt.XXXXXX"\)" \|\| return 1$/  dir="\$\{TMPDIR:-\/tmp\}\/ralph-receipt.shared"; mkdir -p "\$dir" || return 1/m' \
  test/receipt.bats "two receipts, each about its own ticket"

mutation "10 the context figure is presented as a total" "$RECEIPT" \
  's/the peak observed in the session/the total for the session/' \
  test/receipt.bats "peak and never a total"

mutation "10 the attempt is always the first one" "$LOOP" \
  's/^  receipt_fact attempt "\$\(\(attempt \+ 1\)\)"$/  receipt_fact attempt 1/m' \
  test/receipt.bats "survives the counter that gets cleared"

mutation "10 writing a receipt counts as writing the ticket" "$TRACKER_IFACE" \
  's/^    frontier \| ids \| read_ticket \| field \| emit_receipt\)$/    frontier | ids | read_ticket | field)/m' \
  test/receipt.bats "not a write in the tracker"

# The journal's own two halves. A rewritten one has to be named; an honest one has
# to be left alone — and the second is not decoration, it is the trap the first
# walked into. The reclaim lines were written from the right-hand side of a
# pipeline, so the run's copy of them died in a subshell and every run that
# reclaimed anything ended by accusing itself.
mutation "10 a rewritten journal is never noticed" "$LOOP" \
  's/^loop_journal_verify\(\) \{/loop_journal_verify() { return 0;/m' \
  test/receipt.bats "rewritten under the run is named"

mutation "10 the run's own lines are counted in a subshell" "$LOOP" \
  's/^      while read -r rid rdisposition; do$/      printf "%s\\n" "\$reclaimed" | while read -r rid rdisposition; do/m' \
  test/receipt.bats "does not accuse itself"

# [07]'s open question, answered in one word: the outcome says what happened to the
# iteration, this says what happened to the ticket.
mutation "10 an escalation is not distinguishable from a retry" "$FAILURES" \
  's/^    RALPH_FAILURE_ACTION="escalated:\$reason"\n//m' \
  test/receipt.bats "what the loop then did about the ticket"

mutation "10 a retry is not distinguishable from an escalation" "$FAILURES" \
  's/^    RALPH_FAILURE_ACTION="retry:\$\{count:-\?\}\/\$\{RETRY_N:-2\}"\n//m' \
  test/receipt.bats "what the loop then did about the ticket"

# A `failed/<ticket>` ref a receipt promises has to be one git really wrote: the
# call is `|| true`, so an escalation can land with nothing behind it.
mutation "10 the forensic branch is promised rather than checked" "$FAILURES" \
  's/^    if failures_preserve_attempt "\$ticket" "\$pre" "\$tree"; then\n      RALPH_FAILURE_BRANCH="failed\/\$ticket"\n    fi$/    failures_preserve_attempt "\$ticket" "\$pre" "\$tree" || true\n    RALPH_FAILURE_BRANCH="failed\/\$ticket"/m' \
  test/receipt.bats "forensic branch git refused"

# ── [45] the receipt's producers, read against its criterion ─────────────────
#
# [10] wired the sentences it had in front of it. The criterion in receipt.sh is
# wider than that set — "what nothing judged, plus the admissions that are not
# zeroes" — and four families answered yes to it with no channel at all. Each
# entry below removes one channel rather than one sentence: that is the shape of
# this ticket, and a mutation that deleted a phrase would be testing the phrase.

# The route [10] named in an acceptance criterion and could not reach: it skips
# `failures_handle`, so the action stays `none` and the escalation clause never
# fires. The second entry is the other half of the same line — a ticket really was
# given back, and the journal said nobody did anything.
mutation "45 a green gate whose work vanished leaves no document" "$LOOP" \
  's/^  \[ "\$outcome" != not-integrated \] \|\| emit=1\n//m' \
  test/receipt.bats "never reached the branch leaves a document"

mutation "45 an iteration that gave a ticket back says nobody did" "$LOOP" \
  's/^        RALPH_FAILURE_ACTION=given-back\n//m' \
  test/receipt.bats "never reached the branch leaves a document"

# [43] one door down. Only an exit code is a verdict; the other two arms are the
# branch saying nothing at all, and the receipt is the only place that can last —
# a killed branch's output file is empty, so the findings cannot carry it either.
mutation "45 the deadline that killed a branch is stdout only" "$GATE" \
  's/^      gate__say "\$name red \(timed out after/      gate__log "\$name red (timed out after/m' \
  test/receipt.bats "deadline killed says nothing ran"

mutation "45 a branch that left no verdict is stdout only" "$GATE" \
  's/^      gate__say "\$name red \(no verdict\)/      gate__log "\$name red (no verdict)/m' \
  test/receipt.bats "left no verdict at all"

# The refusal `receipt__verdicts` makes two functions up, made where it was
# missing: a section that vanishes reads as an empty zone on exactly the routes
# where nobody walked one.
mutation "45 an unwalked zone is rendered as an empty one" "$RECEIPT" \
  's/^  if \[ ! -s "\$RALPH_RECEIPT\/notes" \] && \[ -z "\$provisioned" \]; then$/  if false; then/m' \
  test/receipt.bats "walked no zone"

# The second channel, from both ends. The producer first — half of failures.sh
# admitted things no document ever saw — then the renderer, without which the
# admissions accumulate in the workspace and are thrown away with it.
mutation "45 what the policy could not do never reaches the document" "$FAILURES" \
  's/^  receipt_gap "\$@"\n//m' \
  test/receipt.bats "rollback that could not act"

mutation "45 the admissions are collected and never rendered" "$RECEIPT" \
  's/^  receipt__gaps\n//m' \
  test/receipt.bats "rollback that could not act"

# And the trigger that gets a document written on the one route where the
# admissions matter most: the run stops over this rollback, so the fresh retry the
# policy just decided is one nothing will ever spend.
mutation "45 a rollback that could not act ends the run with no document" "$LOOP" \
  's/^  \[ "\$\{RALPH_ROLLBACK_FAILED:-0\}" != 1 \] \|\| emit=1\n//m' \
  test/receipt.bats "rollback that could not act"

mutation "45 a retry nothing will spend is presented as a plan" "$RECEIPT" \
  's/^  stopped="\$\(receipt__fact run-stopped\)"$/  stopped=""/m' \
  test/receipt.bats "rollback that could not act"

# ── [14] auto-learning & ADR ─────────────────────────────────────────────────
#
# The layer that is read by a *model* rather than by a human, which is what makes
# its mutations different in kind: most of the entries below remove something that
# would let text nobody vouched for reach the prompt of the next session.

# The guarantee the whole module rests on. Without the posture the retro is an
# ordinary session with Edit, Write and Bash, standing in the tree of the very
# iteration it is reviewing.
mutation "14 the retro subagent is spawned able to write" "$RETRO" \
  's/  session_spawn "\$dir\/prompt" "\$stream" \$\(lenses_posture\) \|\| true/  session_spawn "\$dir\/prompt" "\$stream" || true/m' \
  test/retro.bats "no tool that can write"

mutation "14 the retro runs on the delivery tier" "$RETRO" \
  's/^  MODEL="\$\{RETRO_MODEL:-\$saved_model\}"$/  MODEL="\$saved_model"/m' \
  test/retro.bats "no tool that can write"

# Self-suppression: nothing is written unless there is a lesson.
mutation "14 a retro that found nothing writes a record anyway" "$RETRO" \
  's/^  if \[ -n "\$gist" \]; then$/  if true; then/m' \
  test/retro.bats "finds nothing writes nothing"

# And the other half of the same sentence: a session that said nothing is not a
# session that found nothing ([06] on a missing verdict).
mutation "14 a retro that answered nothing reads as one that found nothing" "$RETRO" \
  's/^  if \[ "\$answered" = 0 \]; then$/  if false; then/m' \
  test/retro.bats "answers nothing at all"

# The anti-noise half of the index: dedup, supersession, drain-by-promotion, and
# the bound. Each of them keeps a working set from becoming a log.
mutation "14 the same lesson is written twice" "$RETRO" \
  's/^    \[ "\$\(retro__norm "\$g"\)" = "\$\(retro__norm "\$gist"\)" \] \|\| continue$/    [ x = y ] || continue/m' \
  test/retro.bats "counted, not written twice"

mutation "14 a recurrent lesson never leaves the working set" "$RETRO" \
  "s/'\\\$2 \\+ 0 >= at \\+ 0 \\{ print \\}' \"\\\$work\" \\\\/'0 { print }' \"\\\$work\" \\\\/m" \
  test/retro.bats "promoted out of the working set"

mutation "14 a promotion happens without a word on the document" "$RETRO" \
  's/^      receipt_note "a lesson this loop recorded was promoted/      : "a lesson this loop recorded was promoted/m' \
  test/retro.bats "promoted out of the working set"

mutation "14 the index grows past its bound" "$RETRO" \
  's/^    awk -v keep="\$\{LEARNINGS_INDEX_MAX:-40\}" .NR <= keep. "\$work"/    awk -v keep="\${LEARNINGS_INDEX_MAX:-40}" "1" "\$work"/m' \
  test/retro.bats "drops its oldest line"

mutation "14 what fell off the index is not counted out loud" "$RETRO" \
  's/^    receipt_note "\$dropped lesson line\(s\) left the injected index/    : "\$dropped lesson line(s) left the injected index/m' \
  test/retro.bats "drops its oldest line"

mutation "14 a superseded record does not say what replaced it" "$RETRO" \
  's/^retro__supersede_record\(\) \{/retro__supersede_record() { return 0;/m' \
  test/retro.bats "superseded lesson leaves the index"

# What reaches a prompt, and in what shape.
mutation "14 the lesson index reaches no session" "$LOOP" \
  's/^\$\(loop__prompt_lessons\)\n//m' \
  test/retro.bats "reaches the next session"

mutation "14 a lesson line is injected unquoted" "$RETRO" \
  's/^    printf .> %s\\n. "\$line"$/    printf "%s\\n" "\$line"/m' \
  test/retro.bats "markdown arrives as text"

mutation "14 the index a prompt is served comes from the working tree" "$RETRO" \
  's!^retro_index\(\) \{$!retro_index() { cat "\$(retro__index_path)" >"\$RALPH_RETRO_STATE/index" 2>/dev/null || true;!m' \
  test/retro.bats "reaches no prompt at all"

mutation "14 an index edited under the run is overwritten in silence" "$RETRO" \
  's/^    retro__log "LEARNINGS.md is not what this run last wrote/    : "LEARNINGS.md is not what this run last wrote/m' \
  test/retro.bats "never reaches a prompt, and the run says so"

# The channel between two attempts at one ticket ([10] left it open).
mutation "14 a retried session is told nothing about the attempt before it" "$LOOP" \
  's/^\$\(loop__prompt_brief "\$ticket"\)\n//m' \
  test/retro.bats "reaches the next attempt"

mutation "14 nothing is kept from a red gate for the next attempt" "$LOOP" \
  's/^    retry:\*\) retro_keep_brief "\$ticket" ;;$/    retry:*) : ;;/m' \
  test/retro.bats "reaches the next attempt"

mutation "14 a brief is carried past its bound in silence" "$RETRO" \
  's/^  local max="\$\{1:-0\}" line n=0$/  local max=0 line n=0/m' \
  test/retro.bats "brief longer than its bound"

mutation "14 a gist is written at whatever length it came back" "$RETRO" \
  's/^    cut -c1-240$/    cat/m' \
  test/retro.bats "gist longer than one line"

mutation "14 the brief is not keyed by ticket" "$RETRO" \
  's/^  printf .%s\/brief.%s\\n. "\$RALPH_RETRO_STATE" "\$\(printf .%s. "\$1" \| tr -c .A-Za-z0-9._-. ._.\)"$/  printf "%s\/brief.any\\n" "\$RALPH_RETRO_STATE"/m' \
  test/retro.bats "belongs to one ticket"

# Which iterations are lesson material: the criterion, not the outcomes that
# happen to exist ([31], [45]).
mutation "14 an iteration nothing judged is lesson material too" "$RETRO" \
  's/^retro_wanted\(\) \{/retro_wanted() { return 0;/m' \
  test/retro.bats "nothing judged the code distils nothing"

# The two promotions, and the line between them ([15]: detecting a missing
# capability is not creating one).
#
# Both edits moved file, and neither moved test: [15] took the decision the
# comment on this ticket asked for and made `capability_propose` the one writer of
# a human-sink ticket, so that its own proposals and this escalation cannot be two
# formats. The guarantee is unchanged and it is still retro.bats that must notice
# — the anchor is simply in the module that owns the shape now.
mutation "14 an escalated rule lands on the frontier instead of the human sink" "$CAPABILITY" \
  's/^\*\*Status:\*\* ready-for-human$/**Status:** ready-for-agent/m' \
  test/retro.bats "ticket on the human sink"

# Moved file again, and not test: [47] took the deduplication out of
# `capability_propose` and made it an adapter operation, because a caller that
# reads `tracker_ids` and then opens has the whole write between its question and
# its answer. The guarantee is unchanged and retro.bats still owns it — the arm
# that answers "one is already waiting" is simply in the backend now.
mutation "14 an escalation waiting for a human is opened again every night" "$TRACKER" \
  's/^      \*"-\$slug"\) return 0 ;;$/      *"-\$slug") : ;;/m' \
  test/retro.bats "not opened twice"

mutation "14 an internal decision is never recorded" "$RETRO" \
  's/^retro__write_adr\(\) \{/retro__write_adr() { return 1;/m' \
  test/retro.bats "recorded as an ADR"

mutation "14 an ADR is written without a word on the document" "$RETRO" \
  's/^      receipt_note "an architecture decision taken during this iteration/      : "an architecture decision taken during this iteration/m' \
  test/retro.bats "recorded as an ADR"

# The seal, on the criterion [31] wrote and the trap it named for this ticket.
mutation "14 the lesson index is not sealed" "$GATE" \
  "s/^  printf '%s\\\\n' 'LEARNINGS.md' 'learning-records'\\n//m" \
  test/retro.bats "writes the lesson index cannot be green"

# And the values that would switch the layer off without saying so.
mutation "14 a RETRO that is neither on nor off is read as off" "$RETRO" \
  's/^    on \| off\) ;;$/    on | off | maybe) ;;/m' \
  test/retro.bats "neither on nor off"

mutation "14 an index that keeps nothing is accepted" "$RETRO" \
  's/^  case "\$\{LEARNINGS_INDEX_MAX:-\}" in\n    .. \| 0 \| \*\[!0-9\]\*\)/  case "\${LEARNINGS_INDEX_MAX:-}" in\n    XX)/m' \
  test/retro.bats "promotion at zero and an empty brief"

# The index is one file and two iterations can be in flight ([13]). Without the
# guard a lesson is written on top of a sibling's, and the test's live holder
# stops mattering.
mutation "14 the index is published without taking the guard" "$RETRO" \
  's/^retro__guard_take\(\) \{/retro__guard_take() { return 0;/m' \
  test/retro.bats "holds the index"

# And the one route this module has to be silent on. Found by [45]'s own test
# going red: a line here would be the only sentence in a section whose job is to
# confess that nobody walked anything. Named against retro.bats, so the guarantee
# has an owner in the file that created the risk — [45]'s entry still removes the
# confession itself, one function away.
mutation "14 a module line masks the confession of an unwalked zone" "$RETRO" \
  's/^  \[ -n "\$verdicts" \] \|\| return 0\n//m' \
  test/retro.bats "no gate reached gets no line"

mutation "14 the tier switched off says nothing" "$RETRO" \
  's/^    receipt_note "the retro tier is off/    : "the retro tier is off/m' \
  test/retro.bats "tier switched off says so"

mutation "14 a retro the API refused is a lesson that was not there" "$RETRO" \
  's/^  if budget_refused "\$posture"; then$/  if false; then/m' \
  test/retro.bats "API refused distils nothing"

# ── [15] detecting a capability, and never building one ──────────────────────
#
# The refusal itself is not mutated here and it has an owner: `.claude/agents`,
# `.claude/commands`, `.claude/skills` and `.claude/hooks` are in
# `gate_sealed_paths`, and the entry that removes them from that list is [31]'s,
# against test/gate.bats. What is mutated here is everything the seal cannot
# reach: the bar, the ordering, the two roots outside every judged tree, and the
# channel that carries the whole thing.

# The bar, both arms. An uncovered class that had to wait for a recurrence would
# never get one — nothing else in a run raises the same name twice by itself.
mutation "15 an uncovered class waits for a recurrence it will not get" "$CAPABILITY" \
  "s/^    printf 'uncovered\\\\n'\$/    printf 'below-bar 0\\/9\\\\n'/m" \
  test/capability.bats "uncovered class does not wait"

mutation "15 a refinement of what exists is proposed on first sight" "$CAPABILITY" \
  's/^  if \[ "\$n" -ge "\$at" \]; then$/  if true; then/m' \
  test/capability.bats "already has is counted"

mutation "15 the bar counts sightings of anything rather than of one name" "$CAPABILITY" \
  's/grep -c "\^\$kind\/\$name\\\$"/grep -c "^"/' \
  test/capability.bats "not the model"

# Reuse before create, one step at a time: a lens that exists must beat building
# one, and a skill that exists must beat it too.
mutation "15 what already exists is never looked for" "$CAPABILITY" \
  's/^    for kind in lens skill agent command; do$/    for kind in ; do/m' \
  test/capability.bats "lens beats a skill"

mutation "15 only a lens counts as something to reuse" "$CAPABILITY" \
  's/^    for kind in lens skill agent command; do$/    for kind in lens; do/m' \
  test/capability.bats "kind does not decide the route"

mutation "15 the proposal does not say what already exists" "$CAPABILITY" \
  's/^\$\(capability__cheapest "\$decision" "\$candidate" "\$where" "\$name"\)$/(nothing)/m' \
  test/capability.bats "cheapest answer"

# The channel: without either of these two lines the whole tier is off and no
# test of it can tell that from a subagent that had nothing to say.
mutation "15 the capability review never runs" "$RETRO" \
  's/^  capability_review "\$RETRO_TOKEN" "\$ticket" "\$stream" "\$RALPH_RETRO_STATE"$/  :/m' \
  test/capability.bats "ticket on the human sink"

mutation "15 the subagent is never told it may name one" "$RETRO" \
  's/^\$\(capability_prompt "\$RETRO_TOKEN"\)$/(nothing)/m' \
  test/capability.bats "told what already exists"

mutation "15 a retro that only named a capability reads as one that said nothing" "$RETRO" \
  's/ \|\|\n    \[ -n "\$capability" \]; then$/; then/m' \
  test/capability.bats "not a retro that said nothing"

# What an answer that is not one costs: a kind this pack cannot act on must not
# become a ticket nobody can read.
mutation "15 an answer this pack cannot read becomes a proposal anyway" "$CAPABILITY" \
  's/^  if ! capability_is_kind "\$kind" \|\| \[ -z "\$name" \]; then$/  if false; then/m' \
  test/capability.bats "cannot read"

# And the `F`, which is the control and not a flourish: without it the kind is a
# regex, `.*` matches `lens`, and the loop writes a file name a session chose with
# a glob character in it.
#
# `\$1` on both halves, and this entry is why the warning at the top of this file
# names `$1` next to `$(` and `$&`: written bare it is perl's first capture group,
# it interpolates to the empty string, and `grep -qx ""` refuses **every** kind —
# which reads as VACUOUS on a test that was doing its job. `-Mstrict` cannot see
# it and neither can `bash -n`: both halves are legal.
mutation "15 the kind a model answered is read as a pattern" "$CAPABILITY" \
  's/  capability_kinds \| grep -qxF "\$1"/  capability_kinds | grep -qx "\$1"/' \
  test/capability.bats "kind that is a pattern"

# And the two silences. A proposal kept below the bar and a tier switched off are
# both iterations where nothing was asked for, and neither may be silent.
mutation "15 a capability kept below the bar is kept in silence" "$CAPABILITY" \
  's/^      receipt_note "the retro asked for a \$kind called/      : "the retro asked for a \$kind called/m' \
  test/capability.bats "counted out loud"

mutation "15 the capability review switched off says nothing" "$CAPABILITY" \
  's/^    receipt_note "the capability review is off/    : "the capability review is off/m' \
  test/capability.bats "switched off says so"

# ── what the seal does not cover ─────────────────────────────────────────────
#
# Two roots reach a later spawn without entering any tree the scope-guard
# compares: the main working tree an iteration is not judged in, and the
# operator's home a lens is deliberately spawned to read.
mutation "15 what a fresh session loads is never witnessed" "$CAPABILITY" \
  's/^capability_witness\(\) \{/capability_witness() { return 1;/m' \
  test/capability.bats "operator's home"

mutation "15 the operator's home is not a place a capability can appear" "$CAPABILITY" \
  's/^  \[ -z "\$\{HOME:-\}" \] \|\| \[ "\$HOME" = "\$root" \] \|\| printf .%s\\n. "\$HOME"$/  :/m' \
  test/capability.bats "operator's home"

mutation "15 a capability that appeared under the run is not said out loud" "$CAPABILITY" \
  's/^    receipt_gap "a capability surface changed while this run was in flight/    : "a capability surface changed while this run was in flight/m' \
  test/capability.bats "main tree"

mutation "15 the witness does not follow a symlinked skill" "$CAPABILITY" \
  's/find -L "\$path" -type f/find "\$path" -type f/' \
  test/capability.bats "symlinked skill"

mutation "15 nothing measures the surfaces again after the session" "$LOOP" \
  's/^\$\(capability_drift "\$\{RALPH_RETRO_STATE:-\}"\)$//m' \
  test/capability.bats "operator's home"

# And the values that would switch the tier off without saying so.
mutation "15 a CAPABILITY that is neither on nor off is read as off" "$CAPABILITY" \
  's/^    on \| off\) ;;$/    on | off | maybe) ;;/m' \
  test/capability.bats "neither on nor off"

mutation "15 a bar of zero is accepted" "$CAPABILITY" \
  's/^  case "\$\{CAPABILITY_RECUR_AT:-\}" in\n    .. \| 0 \| \*\[!0-9\]\*\)$/  case "\${CAPABILITY_RECUR_AT:-}" in\n    XX)/m' \
  test/capability.bats "bar of zero is refused"

mutation "15 the preflight never asks about this tier" "$LOOP" \
  's/^  capability_preflight \|\| rc=1$/  :/m' \
  test/capability.bats "neither on nor off"

# ── [37] the ids of the tracker are a line of words ──────────────────────────
#
# The id namespace is file names a session — or a human — chooses, so each edit
# below is the code exactly as it stood before [37]: a list of ids handed over as
# words, or a membership test asking about words. They are separate entries and
# not one, because the two halves of the same expansion are not the same failure:
# a space cuts an id into ids nothing carries, a `[` replaces it by whatever the
# current directory holds, and a test covering one says nothing about the other.

mutation "37 the strays are recut into words" "$FAILURES" \
  's/  while IFS= read -r id; do\n    \[ -n "\$id" \] \|\| continue\n    ! failures__in_list/  for id in \$(tracker_ids); do\n    ! failures__in_list/; s/  done <<IDS\n\$\(tracker_ids\)\nIDS/  done/' \
  test/failures.bats "one stray, not two ghosts"

mutation "37 the register exempts every word of an id" "$FAILURES" \
  's/    if \[ "\$line" = "\$needle" \]; then return 0; fi/    case " \$line " in *" \$needle "*) return 0 ;; esac/' \
  test/failures.bats "shares a word with it"

mutation "37 the quarantine note runs two ids together" "$FAILURES" \
  's!^failures__join\(\) \{!failures__join() { printf "%s" "\$1" | tr -s " " "\\n" | sed "/^\$/d" | tr "\\n" " " | sed "s/ *\$//; s/ /, /g"; return 0;!m' \
  test/failures.bats "one stray, not two ghosts"

mutation "37 the claim sweep walks words" "$CLAIM" \
  's/  while IFS= read -r id; do\n    \[ -n "\$id" \] \|\| continue\n    status=/  for id in \$(tracker_ids); do\n    status=/; s/  done <<IDS\n\$\(tracker_ids\)\nIDS/  done/' \
  test/claim.bats "carries a space is still swept"

mutation "37 a sibling in flight exempts every word of its id" "$CLAIM" \
  's/    if \[ "\$line" = "\$needle" \]; then return 0; fi/    case " \$line " in *" \$needle "*) return 0 ;; esac/' \
  test/claim.bats "shares a word with it"

# The producer of that same list, one layer up, and it fails differently from the
# entry above: there the fence answers for a word, here the whole list arrives as
# one line and exempts nobody at all.
mutation "37 the ids in flight are handed over as a line of words" "$LOOP" \
  's/awk -F.\\t. .NF > 1 \{ print \$2 \}./awk -F\x27\\t\x27 \x27NF > 1 { printf "%s ", \$2 }\x27/' \
  test/concurrency.bats "does not reclaim a claim this run is holding"

mutation "37 the surface owner is looked up by words" "$GATE" \
  's/  while IFS= read -r id; do\n    \[ -n "\$id" \] \|\| continue\n    \[ "\$id" != "\$self" \]/  for id in \$(tracker_ids); do\n    [ "\$id" != "\$self" ]/; s/  done <<IDS\n\$\(tracker_ids\)\nIDS/  done/' \
  test/gate.bats "under a name with a space"

mutation "37 a carrier is named by its first word" "$TRACKER_IFACE" \
  's/      "\$nn"-\*\) printf \x27%s\\n\x27 "\$id" ;;/      "\$nn"-*) printf \x27%s\\n\x27 \$id ;;/' \
  test/tracker-local.bats "the name its file really has"

# ── [47] tracker_open_ticket has no lock ─────────────────────────────────────
#
# Allocating an `NN` is a read-modify-write on a directory with three producers,
# and a collision is permanent: a bare number stops resolving, so every ticket
# carrying `Blocked by: NN` leaves the frontier for good ([27]). Neither repair can
# reach the one the loop creates — the preflight ran at the start of the run, and
# the quarantine's renumber is disarmed by the register of the loop's own writes
# ([13]/[42]) precisely because it is the loop that wrote it.
#
# Each refusal below has its twin that removes the ability to act: a guard that let
# nobody in would satisfy every "it refused" assertion on its own.

mutation "47 the number is allocated with nothing serialising it" "$TRACKER" \
  's/  tracker_local__open_guard_take \|\| \{\n    tracker_local__open_refused [^\n]*refusing to allocate a number[^\n]*\n    return 1\n  \}\n/  true\n/' \
  test/tracker-local.bats "refuses a number it cannot allocate"

mutation "47 the renumber allocates beside an opening" "$TRACKER" \
  's/  tracker_local__open_guard_take \|\| \{\n    tracker_local__open_refused [^\n]*refusing to renumber[^\n]*\n    return 1\n  \}\n/  true\n/' \
  test/tracker-local.bats "renumber refuses rather than allocating"

mutation "47 the guard never lets anybody in" "$TRACKER" \
  's/^tracker_local__open_guard_take\(\) \{/tracker_local__open_guard_take() { return 1;/m' \
  test/tracker-local.bats "refuses a number it cannot allocate"

mutation "47 a finished opening keeps the guard" "$TRACKER" \
  's/^tracker_local__open_guard_release\(\) \{/tracker_local__open_guard_release() { return 0;/m' \
  test/tracker-local.bats "not left behind by an opening"

# The width of the window, and it is the ordering rather than the guard: the
# number used to be chosen before the body was read, so it was reserved and
# unwritten for as long as its caller took to produce one.
mutation "47 the number is chosen before the body arrives" "$TRACKER" \
  's/  mkdir -p "\$dir"\n  body="\$\(cat\)"\n\n/  mkdir -p "\$dir"\n\n/; s/  nn="\$\(tracker_local__next_nn\)"\n/  body="\$(cat)"\n  nn="\$(tracker_local__next_nn)"\n/' \
  test/tracker-local.bats "slow to arrive does not hold a number"

mutation "47 a slug already on the sink is opened again" "$TRACKER" \
  's/^tracker_local__slug_taken\(\) \{/tracker_local__slug_taken() { return 1;/m' \
  test/tracker-local.bats "opens a slug once"

# The same race by its other end: the question and the write on opposite sides of
# the guard, which is what `capability_propose` did when it read `tracker_ids`
# first. The edit puts the check back where the answer goes stale.
mutation "47 the slug is looked up before the body, outside the guard" "$TRACKER" \
  's/  if \[ -n "\$unique" \] && tracker_local__slug_taken "\$dir" "\$slug"; then\n    tracker_local__open_guard_release\n    return 0\n  fi\n\n//; s/  body="\$\(cat\)"\n/  if [ -n "\$unique" ] \&\& tracker_local__slug_taken "\$dir" "\$slug"; then return 0; fi\n  body="\$(cat)"\n/' \
  test/tracker-local.bats "does not open a slug a second one landed"

# The register wants the id the guards will meet in `issues/`, never the slug the
# caller passed: a line naming no ticket exempts nothing, and the proposal the loop
# just opened is quarantined as work a session gave itself ([42]).
mutation "47 a unique opening registers its slug instead of its id" "$TRACKER_IFACE" \
  's/^    open_ticket \| open_unique \| renumber\)$/    open_ticket | renumber)/m' \
  test/tracker-local.bats "the id it made, not the slug"

# And its twin: a line for a creation that did not happen hands both guards an id
# to skip for a ticket this run never touched.
mutation "47 an opening that opened nothing is registered all the same" "$TRACKER_IFACE" \
  's/^      tracker__note_write "\$out"$/      tracker__note_write "\${out:-\$1}"/m' \
  test/tracker-local.bats "opened nothing writes no line"

# ── [39] a name git does not print as itself ─────────────────────────────────
#
# `git diff-tree` C-quotes any name outside pure ASCII, so `docs/spécification.md`
# reached the four consumers of the changed-file list as `"docs/sp\303\251cification.md"`
# — a string `git cat-file`, `git add`, `rm` and `checkout-index` all refuse. Each
# edit below is the code exactly as it stood before [39], and they are separate
# entries for the reason [37] gives about its own family: the four consumers fail
# differently, and a test covering one says nothing about the others.

# The producer every consumer of a changed-file list reads through, so a single
# line carries the whole family. Named against the language gate's test, which is
# where the ticket's own exit criterion is asserted: the count [17] posted while
# waiting for this is zero, and the file is judged under the name it really has.
mutation "39 the changed-file list keeps git's quoting" "$GATE" \
  's/  git -c core\.quotePath=false diff-tree -r --name-only "\$base" "\$now" 2>\/dev\/null \|\n    gate__drop_bookkeeping/  git diff-tree -r --name-only "\$base" "\$now" 2>\/dev\/null | gate__drop_bookkeeping/' \
  test/lang.bats "name it really has"

# The third producer, and the one the ticket did not name: the diff between the
# judged tree and the tree as it is now, which the zone line and the containment of
# what a review lens wrote both read.
mutation "39 the gate's own after-diff keeps git's quoting" "$GATE" \
  's/  git -c core\.quotePath=false diff-tree -r --name-only "\$judged" "\$now" 2>\/dev\/null \|\n    gate__drop_bookkeeping/  git diff-tree -r --name-only "\$judged" "\$now" 2>\/dev\/null | gate__drop_bookkeeping/' \
  test/gate.bats "named readably too"

# The second producer, aimed at its own trees: the restore reads `--name-status`
# and would otherwise inherit the fix through nothing at all.
mutation "39 the restore's own list keeps git's quoting" "$GATE" \
  's/\$\(git -c core\.quotePath=false diff-tree -r --name-status "\$base" "\$now" 2>\/dev\/null\)/$(git diff-tree -r --name-status "\$base" "\$now" 2>\/dev\/null)/' \
  test/failures.bats "removes a name outside pure ASCII"

# What is left quoted whatever that setting says — a tab, a newline, a quote — is
# refused rather than compared to a surface it cannot be compared to. The test
# declares `*`, so a guard that merely stopped matching would still go green.
mutation "39 a name the gate cannot address is judged like any other" "$GATE" \
  's/    if gate_unaddressable "\$file"; then\n      rc=1\n      if \[ -z "\$class" \]; then class=internal; fi\n      printf .wrote %s, a name this gate cannot address[^\n]*\n      continue\n    fi\n//' \
  test/gate.bats "cannot address is red whatever"

# The same question at the other end of the same iteration: the restore must not
# print a name it could not act on as one it put back ([30]).
mutation "39 the restore claims it put back what it could not touch" "$GATE" \
  's/    if gate_unaddressable "\$path"; then\n      gate__gap "could not put back[^\n]*\n      continue\n    fi\n//' \
  test/failures.bats "not reported as one this rollback put back"

# And the channel that admission travels on. `gate_restore_tree` returns its list
# on stdout, both callers read it through a command substitution, so a gap printed
# there is counted as a path that was restored — a failure reported as a success.
mutation "39 the restore's admissions go into its own return value" "$GATE" \
  's/      gate__gap "could not put back \$path — git prints this name quoted and nothing here can address it" >&2/      gate__gap "could not put back \$path — git prints this name quoted and nothing here can address it"/' \
  test/failures.bats "not reported as one this rollback put back"

# The durable commit, as it stood: one call, the list cut into words and globbed.
#
# Named against the path with a *space* and not against the accented one, and the
# first draft of this entry came back VACUOUS for saying otherwise: once the
# producer no longer quotes, `docs/spécification.md` survives word splitting like
# any other name, so the accented test says nothing about this line. What this line
# carries is the [33] half — and it carries it whole, `git add` refusing the entire
# call on one bad pathspec, so the mutated iteration commits nothing at all.
mutation "39 the durable commit stages a line of words" "$FAILURES" \
  's/  while IFS= read -r path; do\n    \[ -n "\$path" \] \|\| continue\n    GIT_INDEX_FILE="\$idx" git add -A -- ":\(literal\)\$path" >\/dev\/null 2>&1 \|\| true\n  done <<CHANGED\n\$changed\nCHANGED/  GIT_INDEX_FILE="\$idx" git add -A -- \$changed >\/dev\/null 2>\&1 || true/' \
  test/failures.bats "commits a path whose name carries a space"

# Its twin at the other end of the same function: the caller's index is restaged
# from the same list, so a name that list could not carry left a staged deletion
# behind. Named against a test driven at the *module*, and that is the finding
# rather than a shortcut — since [13] this commit runs in a throwaway worktree, so
# the index it puts back goes with the worktree and no full-loop test can see this
# line. The first draft of this entry named the end-to-end test and came back
# VACUOUS: it was measuring `concurrency__refresh`, one module over.
mutation "39 the index is put back from a line of words" "$FAILURES" \
  's/  while IFS= read -r path; do\n    \[ -n "\$path" \] \|\| continue\n    git add -A -- ":\(literal\)\$path" >\/dev\/null 2>&1 \|\| true\n  done <<CHANGED\n\$changed\nCHANGED/  git add -A -- \$changed >\/dev\/null 2>\&1 || true/' \
  test/failures.bats "no staged reversal"

# What that `|| true` costs when it fires, which is the general form of the defect
# above: approved, absent from the commit, and silent.
mutation "39 a path git refused to stage is dropped without a word" "$FAILURES" \
  's/    failures__in_list "\$path" "\$changed" \|\| continue\n    failures__gap "\$ticket: \$path was approved by the gate and could not be staged — it is not in this commit"/    failures__in_list "\$path" "\$changed" || continue\n    :/' \
  test/failures.bats "git would not stage is named"

# The last caller [33] had missed: the rollback rejoined the restored paths into
# one whitespace word to unstage them.
mutation "39 the unstaging is handed a line of words" "$FAILURES" \
  's/    git reset -q -- ":\(literal\)\$path" 2>\/dev\/null \|\| true\n    undone=\$\(\(undone \+ 1\)\)/    undone=\$((undone + 1))/; s/  if \[ "\$undone" -gt 0 \]; then/  if [ -n "\$paths" ]; then\n    git reset -q -- \$paths 2>\/dev\/null || true/' \
  test/failures.bats "unstaging survives a path"

# The third place the same list was rejoined into a word, one module over: the
# refresh of the main working tree after a fold walks the list by line and then
# handed `git reset` all of it at once. What it costs is the state that function
# exists to prevent — a delivered path left staged as a deletion in the tree a
# human looks at in the morning.
mutation "39 the tree refresh unstages a line of words" "$CONCURRENCY" \
  's/  while IFS= read -r path; do\n    \[ -n "\$path" \] \|\| continue\n    \(cd "\$root" && git reset -q -- ":\(literal\)\$path" 2>\/dev\/null\) \|\| true\n  done <<PATHS\n\$changed\nPATHS/  (cd "\$root" \&\& git reset -q -- \$(printf \x27%s\x27 "\$changed" | tr \x27\\n\x27 \x27 \x27) 2>\/dev\/null) || true/' \
  test/failures.bats "commits a path whose name carries a space"

# The residue, at the one consumer that answers about it with a count rather than a
# verdict: a name git quotes whatever `core.quotePath` says is not prose this branch
# can read, and pretending to judge it drops it out of the count in silence.
mutation "39 the language gate judges a name it cannot read" "$LANGLIB" \
  's/    if gate_unaddressable "\$file"; then\n      unaddressable=\$\(\(unaddressable \+ 1\)\)\n      continue\n    fi\n//' \
  test/lang.bats "still prints quoted is counted"

# ── [49] the tracker directory holds the pack's own transients ───────────────
#
# `failures_protect_tracker` compared two tree objects of `issues/` as though that
# directory held nothing but tickets, and this pack puts three other kinds of
# object in there: a claim's guard directory, the temp file every atomic write
# leaves beside its target, the working copy `set_fields` publishes from. One held
# across the pre-session snapshot and released inside the window arrives as a `D`,
# and `checkout-index` put it back — a session that wrote nothing accused on its
# own ticket, an innocent iteration refused a green, and for a claim's guard a lock
# restored with the pilot's own live pid, which nothing releases and which takes
# that ticket off the frontier for the rest of the run.
#
# The predicate has two clauses answering for different producers, so they are
# separate entries: everything this pack leaves in there fails the suffix, and only
# a session can produce a `.md` one level down.

mutation "49 anything beside a ticket is a ticket" "$FAILURES" \
  's/    "\$dir"\/\*\.md\) ;;/    "\$dir"\/*) ;;/' \
  test/failures.bats "atomic write's temp file that vanished"

mutation "49 a .md below the tracker is a ticket" "$FAILURES" \
  's/  rest="\$\{path#"\$dir"\/\}"\n  case "\$rest" in\n    \*\/\*\) return 1 ;;\n  esac\n//' \
  test/failures.bats "is not a ticket is named"

mutation "49 the guard restores whatever moved in there" "$FAILURES" \
  's/    if ! failures__is_ticket_path "\$path" "\$dir"; then\n      others="\$\(failures__append_line "\$path" "\$others"\)"\n      others_n=\$\(\(others_n \+ 1\)\)\n      continue\n    fi\n//' \
  test/failures.bats "claim guard a sibling dropped"

# And the other half of the same decision: what it stops restoring, it names. A
# filter nobody is told about reads exactly like a directory in which nothing else
# ever moves ([24]).
mutation "49 what it leaves alone is left alone in silence" "$FAILURES" \
  's/  \[ "\$others_n" = 0 \] \|\|\n    failures__say [^\n]*\n//' \
  test/failures.bats "is not a ticket is named"

# The fourth reader of [39]'s question, and the only one that cannot tell whether
# what it is looking at is a ticket: without it a quoted name falls through the
# filter into the zone line, as though a ticket the session removed were a temp
# file this pack had left lying about.
mutation "49 a ticket it cannot address is passed over as bookkeeping" "$FAILURES" \
  's/    if gate_unaddressable "\$path"; then\n      failures__gap [^\n]*\n      unvouched=1\n      continue\n    fi\n//' \
  test/failures.bats "cannot address is not vouched"

# What a human sorting the human sink in the morning can tell apart without opening
# the receipt: a plan nothing could be made of, and a plan that was never written.
mutation "49 a split that created nothing says nothing on its ticket" "$FAILURES" \
  's/    printf \x27Re-slice refused[^\n]*\n      tracker_append_note "\$ticket" \|\| true\n//' \
  test/failures.bats "could create nothing"

# And why it created nothing, which only the backend knows: `run.log` records the
# ticket's own escalation (`too-big`), which is the wrong cause, and the two lines
# that name the guard are `printf … >&2`.
mutation "49 the cause of a refused allocation stays on the console" "$TRACKER" \
  's/^  receipt_gap "the ticket-open guard was held[^\n]*\n//m' \
  test/failures.bats "could create nothing"

# The guard [47] added is released by the call that took it and by nothing else —
# unlike the run lock, whose acquisition installs a trap — so a run killed while
# holding it crossed every later run in silence.
mutation "49 a guard a dead run left behind is counted by nobody" "$GATE" \
  's/^gate__stale_guards\(\) \{/gate__stale_guards() { return 1;/m' \
  test/gate.bats "left holding inside the feature"

# Its twin, and the reason the count is asserted rather than the sentence: a guard
# whose owner still answers belongs to something alive, and naming it would be the
# false alarm that makes a morning line unreadable.
mutation "49 a guard something alive is holding is counted as a leak" "$GATE" \
  's/    if \[ -n "\$owner" \] && kill -0 "\$owner" 2>\/dev\/null; then continue; fi\n//' \
  test/gate.bats "left holding inside the feature"

# A ticket no iteration could claim had no line in `run.log` at all: the run ended
# sterile against it, and the file a human opens in the morning never named it.
mutation "49 a ticket nobody could claim leaves no line in the journal" "$LOOP" \
  's/^  loop_journal_append "\$ticket" claim-refused 0 0 0\n//m' \
  test/loop-happy-path.bats "no iteration could claim"

# And the sentence itself, as it stood: one line for two causes, naming a holder
# that does not exist whenever the tracker's own exclusion is what refused.
mutation "49 the refusal names an owner nobody holds" "$LOOP" \
  's/^loop__claim_refused\(\) \{/loop__claim_refused() { loop_log "could not claim \$1 — someone else has it"; loop_journal_append "\$1" claim-refused 0 0 0; return 0;/m' \
  test/loop-happy-path.bats "no iteration could claim"

# ── [46] the configuration decides what git runs, too ────────────────────────
#
# Every entry aims at a guarantee and not at the contents of a list: replacing
# what `gate_config_keys` returns wholesale would prove that a key nobody watches
# is not watched, which nobody doubts. The one entry that does touch the list
# takes a *single* key out of it, which is the edit a later ticket tidying this up
# would really make.

# The whole fourth kind. Without it the frontier is [30]'s again — what a check
# can see — and says nothing at all about what git runs.
mutation "46 the configuration half of the frontier is never read" "$GATE" \
  's/^gate__config_manifest\(\) \{/gate__config_manifest() { return 0;/m' \
  test/gate.bats "run its own program through the repository config"

# One key off the derived list, which is what makes the list a list and not a
# decoration: the mechanism still works, and this one key goes unwatched.
mutation "46 core.fsmonitor is off the watched list" "$GATE" \
  's/    \x27core\\\.fsmonitor\x27 \\\n//' \
  test/gate.bats "run its own program through the repository config"

# The file that arms a filter on a path. Without it a `filter.<n>.smudge` is
# watched and inert, and `* filter=x` — or a bare `* text=auto` — is not watched
# at all.
mutation "46 the attributes file is not a source of its own" "$GATE" \
  's/^gate__config_attributes_path\(\) \{/gate__config_attributes_path() { return 0;/m' \
  test/gate.bats "attributes file alone is a movement"

# The verdict. Detected, restored, and not a finding: the iteration goes green
# over a run that has just been executing a program a session chose.
mutation "46 moving what git runs is not a finding" "$GATE" \
  's/    \[ "\$kind" = cfg \] && \[ -n "\$name" \] \|\| continue/    continue/' \
  test/gate.bats "run its own program through the repository config"

# The restore reporting its intention instead of its result — the same lie [30]
# paid for one mechanism up, on the door [15] found open: `git config --unset`
# writes *this* repository's config, so a value in the operator's home survives it
# untouched and "(put back)" would be false.
mutation "46 a configuration restore that was only attempted claims success" "$GATE" \
  's/  git config --unset-all "\$name" >\/dev\/null 2>&1 \|\| true\n  \[ "\$\(gate__frontier_current "\$name"\)" = "\$pinned" \]/  return 0/' \
  test/gate.bats "cannot put back is named"

# Where the restore falls, which is the question [32] asked once and [46] had to
# ask again: put back only at the three gated sites, the tracker guard has already
# staged and checked out every ticket through the session's own filter.
mutation "46 the frontier is put back only once the tracker has been read" "$LOOP" \
  's/^  gate_frontier_put_back >\/dev\/null \|\| true$/  :/m' \
  test/gate.bats "put back before the tracker guard"

# And the register's own rule, which is what makes a second caller safe ([41]
# wrote it as a convention about call sites): a movement no restore can undo is
# re-detected by every look, so without this the iteration is billed twice for one
# widening and every sibling in flight with it.
mutation "46 one movement is recorded once per look instead of once per iteration" "$GATE" \
  's/      \*"\$nl\$tag\$tab\$line\$nl"\*\) continue ;;/      *"never matches this") continue ;;/' \
  test/gate.bats "cannot put back is named"

# ── [46] the witness of [15] reaches a document ──────────────────────────────

# The line itself. Without it the witness is back to a receipt that does not exist
# on this route and a stdout that has scrolled.
mutation "46 the capability witness says nothing a document can keep" "$CAPABILITY" \
  's/    printf \x27%s\\t%s\\t%s\\n\x27 "\$path" capability-drift \\\n      "a capability surface changed under this run: \$path"/    :/' \
  test/capability.bats "iteration a run stops on"

# The pilot's half: the iteration measured it and wrote it to its slot, and
# nothing carried it to the file a human opens in the morning.
mutation "46 the drift never reaches the run journal" "$LOOP" \
  's/      loop_journal_append "\$drift_subject" "\$\{drift_outcome:-capability-drift\}" 0 0 0/      :/' \
  test/capability.bats "iteration a run stops on"

# ── [09] the one-shot successor ──────────────────────────────────────────────
#
# Two halves, and they fail differently. The **chain** is about what a night
# survives — a reversed order still works every week nobody reboots. The
# **instant** is about arming on something nothing measured, which is [27]'s
# fallback that disarms itself, wearing a different hat.

# The ordering, which is the whole of the chain's guarantee. Reversed, the
# transient timer in tmpfs is tried first and a reboot during the wait takes the
# successor with it.
mutation "09 the chain is not ordered by reboot survival" "$SCHEDULER_LIB" \
  's#  printf \x27at\\n\x27\n  case "\$platform" in\n    Darwin\) ;;\n    \*\) printf \x27systemd-run\\n\x27 ;;\n  esac#  case "\$platform" in\n    Darwin) ;;\n    *) printf \x27systemd-run\\n\x27 ;;\n  esac\n  printf \x27at\\n\x27#' \
  test/scheduler.bats "survives a reboot"

# The platform half: a mac has no systemd, and trying one there is a mechanism
# that can only ever fail.
mutation "09 the chain offers systemd on a mac" "$SCHEDULER_LIB" \
  's#    Darwin\) ;;\n    \*\) printf \x27systemd-run\\n\x27 ;;#    *) printf \x27systemd-run\\n\x27 ;;#' \
  test/scheduler.bats "no systemd"

# `none` as a declaration. Without it a project that said it has no scheduler is
# handed one anyway.
mutation "09 SCHEDULER=none is not a declaration" "$SCHEDULER_LIB" \
  's#    none\) return 0 ;;#    none) ;;#' \
  test/scheduler.bats "is a declaration"

# And the other side of that key: a project that named one mechanism falls
# through to the next, so it is told its night survives a reboot when it does not.
mutation "09 naming one mechanism falls through to the next" "$SCHEDULER_LIB" \
  's#    at \| systemd-run\)\n      printf \x27%s\\n\x27 "\$\{SCHEDULER:-\}"\n      return 0\n      ;;#    at | systemd-run) ;;#' \
  test/scheduler.bats "never the next one down"

# The chain probing the machine at all. Without it every candidate is "available"
# and the first submission is where a missing binary is discovered.
mutation "09 the chain does not ask what this machine has" "$SCHEDULER_LIB" \
  's#    command -v "\$mech" >/dev/null 2>&1 \|\| continue\n##' \
  test/scheduler.bats "does not have is not in the chain"

# ── [09] the instant, and the four ways it is not one

# `exit 6` has two causes and only one carries an instant ([08]). Without this
# guard the empty field is arithmetic and the successor is armed at the epoch 0.
mutation "09 a reset nothing measured is armed anyway" "$SCHEDULER_LIB" \
  's#    \x27\x27 \| \*\[!0-9\]\*\)\n      RALPH_SUCCESSOR_WHY="not arming a successor: the reset of the window#    zzz-never-matches)\n      RALPH_SUCCESSOR_WHY="not arming a successor: the reset of the window#' \
  test/scheduler.bats "nothing measured"

# A reset already past. Arming on it wakes a run into the same wall, which arms
# again — an arming storm rather than a night.
mutation "09 a reset in the past is armed" "$SCHEDULER_LIB" \
  's#  if \[ "\$span" -le 0 \]; then#  if [ "\$span" -le -999999999 ]; then#' \
  test/scheduler.bats "in the past"

# "Never +7 days" is a ceiling the window carries. Without it a clock that is
# wrong buys a successor at any instant the endpoint cares to name.
mutation "09 a weekly window has no ceiling of its own" "$SCHEDULER_LIB" \
  's#  printf \x27seven_day\\t604800\\n\x27#  printf \x27seven_day\\t99999999\\n\x27#' \
  test/scheduler.bats "further out than its window"

# The paired witness one line down: with a single shared ceiling both windows
# would pass the entry above and a session window would be armable a week out.
mutation "09 a session window is priced like a weekly one" "$SCHEDULER_LIB" \
  's#  printf \x27five_hour\\t18000\\n\x27#  printf \x27five_hour\\t604800\\n\x27#' \
  test/scheduler.bats "held to five hours"

# A window name this pack does not know, given the widest ceiling instead of a
# refusal — which is the fail-open this whole module is written against.
mutation "09 an unknown window is priced at a week" "$SCHEDULER_LIB" \
  's#CEILINGS\n  return 1\n\}#CEILINGS\n  scheduler__ceiling_max\n}#' \
  test/scheduler.bats "cannot price"

# The instant from a session's own stream, held to what a pause costs. Without
# it a forged `rate_limit_event` buys a successor days out ([08], [23]).
mutation "09 an instant a session wrote is not capped" "$SCHEDULER_LIB" \
  's#  if \[ "\$source" = stream \] && \[ "\$span" -gt "\$\{BUDGET_MAX_PAUSE:-21600\}" \]; then#  if false; then#' \
  test/scheduler.bats "a session wrote"

# `at` takes whole minutes, so the rounding has a direction and only one of them
# is safe: down wakes the run *before* the wall lifts.
mutation "09 the deadline is rounded down to the minute" "$SCHEDULER_LIB" \
  's#\+ 59\) / 60 \* 60#+ 0) / 60 * 60#' \
  test/scheduler.bats "rounded up to the minute"

# ── [09] the singleton, and what a successor is handed

mutation "09 a second successor is armed over the first" "$SCHEDULER_LIB" \
  's#  if at="\$\(scheduler_armed_at\)"; then#  if false; then#' \
  test/scheduler.bats "already armed for this tree"

# The paired witness: a marker read as live for ever wedges every run after the
# first weekly wall, and passes the entry above.
mutation "09 a marker whose instant has passed still blocks" "$SCHEDULER_LIB" \
  's#  \[ "\$at" -gt "\$now" \] \|\| return 1#  [ -n "\$at" ] || return 1#' \
  test/scheduler.bats "instant has passed"

mutation "09 nothing records that a successor was armed" "$SCHEDULER_LIB" \
  's#  scheduler__mark "\$RALPH_SUCCESSOR_AT" "\$armed" \|\|\n    scheduler__log "armed a successor and could not record it[^\n]*"#  :#' \
  test/scheduler.bats "out of reach of a git add"

# What a successor runs. Anything but the loop is a job that takes neither lock.
mutation "09 the successor is not a run of this loop" "$SCHEDULER_LIB" \
  's#"\$\(scheduler__quote "\$root/\.claude/loop\.sh"\)"#"\$(scheduler__quote "\$root/.claude/lib/select.sh")"#' \
  test/scheduler.bats "takes the run lock"

# `at` mails a job's output, and a headless box has no MTA: without the redirect
# a successor that ran leaves nothing a human can read.
mutation "09 the queued job output goes nowhere" "$SCHEDULER_LIB" \
  's#\[ -z "\$out" \] \|\| exec >>"\$out" 2>&1;#:;#' \
  test/scheduler.bats "lands beside the run journal"

# The decision, mutated the way it would really be undone: by handing the
# successor one of this run's own workspaces ([40] — a queued command line is
# readable by anything running as this user).
mutation "09 the successor is handed one of this run own secrets" "$SCHEDULER_LIB" \
  's#  printf \x27 RALPH_CONFIG=%s\x27 "\$\(scheduler__quote "\$cfg"\)"#  printf \x27 RALPH_CONFIG=%s\x27 "\$(scheduler__quote "\$cfg")"\n  printf \x27 RALPH_RETRO_STATE=%s\x27 "\$(scheduler__quote "\$\{RALPH_RETRO_STATE:-\}")"#' \
  test/scheduler.bats "names nothing of this run"

# ── [09] the residue a fresh run would adopt, and the human fallback

mutation "09 the run-level residue is never read" "$GATE" \
  's/^gate_frontier_residue\(\) \{/gate_frontier_residue() { return 1;/m' \
  test/scheduler.bats "named as a residue"

mutation "09 the pilot does not hand the residue to the scheduler" "$LOOP" \
  's#  residue="\$\(gate_frontier_residue \|\| true\)"#  residue=""#' \
  test/scheduler.bats "queues nothing for the morning"

mutation "09 a residue does not stop the arming" "$SCHEDULER_LIB" \
  's#  if \[ -n "\$residue" \]; then#  if false; then#' \
  test/scheduler.bats "whatever the instant says"

mutation "09 a project that resumes by hand is scheduled for anyway" "$SCHEDULER_LIB" \
  's#  if \[ "\$\{WEEKLY_RESUME:-schedule\}" != schedule \]; then#  if false; then#' \
  test/scheduler.bats "by hand"

# Every mechanism refused and the run says it armed one: the false green of this
# module, and the only one that would let an AFK night end in silence.
mutation "09 a refused submission reads as an armed successor" "$SCHEDULER_LIB" \
  's#  if \[ -z "\$armed" \]; then#  if false; then#' \
  test/scheduler.bats "not a silent success"

# "Armed" read as "will run". `at` answers for its queue and never for the job.
mutation "09 arming claims more than a submission" "$SCHEDULER_LIB" \
  's/^scheduler_caveat\(\) \{/scheduler_caveat() { return 0;/m' \
  test/scheduler.bats "cannot promise"

# ── [09] the wiring, in the pilot

mutation "09 the wall arms nothing" "$LOOP" \
  's#  if \[ "\$\{stop_code:-0\}" = 6 \]; then\n    loop__arm_successor\n  fi#  :#' \
  test/scheduler.bats "arms exactly one successor"

# The journal word. A morning reader has to tell "something will pick this up"
# from "nothing will" without the console output of a process that ended hours ago.
mutation "09 the journal does not tell an armed run from a stopped one" "$SCHEDULER_LIB" \
  's#    0\) printf \x27successor-armed\\n\x27 ;;#    0) printf \x27weekly-pause\\n\x27 ;;#' \
  test/scheduler.bats "arms exactly one successor"

mutation "09 the scheduler keys are not refused at the door" "$LOOP" \
  's#  scheduler_preflight \|\| rc=1#  :#' \
  test/scheduler.bats "outside the set is refused, not read as no mechanism"

mutation "09 a SCHEDULER outside the set is read as no mechanism" "$SCHEDULER_LIB" \
  's#      rc=1\n      ;;\n  esac\n\n  case "\$\{WEEKLY_RESUME:-schedule\}" in#      ;;\n  esac\n\n  case "\$\{WEEKLY_RESUME:-schedule\}" in#' \
  test/scheduler.bats "outside the set is refused, not read as no mechanism"

mutation "09 the cloud skill is refused without its reason" "$SCHEDULER_LIB" \
  's#    schedule \| routines\)#    zzz-never-matches)#' \
  test/scheduler.bats "cloud skill by name"

mutation "09 a WEEKLY_RESUME outside the set is read as human" "$SCHEDULER_LIB" \
  's#      rc=1\n      ;;\n  esac\n\n  return "\$rc"#      ;;\n  esac\n\n  return "\$rc"#' \
  test/scheduler.bats "outside the set is refused, not read as human"

# ── [53] what the queued line carries, and what the job checks before it trusts it

# The guard the job runs before `loop.sh`. Without it the redirection is the
# first thing the job's shell does and it resolves a name a session writes: a
# directory there makes the job exit 1 and the successor never starts at all.
mutation "53 the successor writes through whatever name it was queued with" "$SCHEDULER_LIB" \
  's#usable=\x27ralph_wake_usable\(\) \{ \[ -n "\$1" \][^\n]*\x27#usable=\x27ralph_wake_usable() { [ -n "\$1" ]; };\x27#' \
  test/scheduler.bats "turned into a directory"

# And the other half of the same clause: a check with nowhere to fall back to
# refuses the log and takes the night with it.
mutation "53 a refused log has nothing to fall back to" "$SCHEDULER_LIB" \
  's# ralph_wake_usable "\$2" && out="\$2"; fi;\x27# fi;\x27#' \
  test/scheduler.bats "turned into a directory"

# The fallback lives in the git directory, where nobody looks, so the sentence
# has to reach the file a human opens. Without this line the successor wrote
# somewhere else all night and said so nowhere a reader goes.
mutation "53 the refused log is never named in the journal" "$LOOP" \
  's#    loop_journal_append - successor-log-refused 0 0 0#    :#' \
  test/scheduler.bats "reaches the file a human opens"

# The second selector the environment gives ([31] for the first). Without it a
# run pointed at its tracker by its environment arms a successor that wakes into
# `exit 2, FEATURE is empty` — and journals `successor-armed` doing it.
mutation "53 the queued line does not carry the tracker" "$SCHEDULER_LIB" \
  's#  printf \x27 FEATURE=%s\x27 "\$\(scheduler__quote "\$\{FEATURE:-\}"\)"\n##' \
  test/scheduler.bats "the tracker this run ground"

# The bound on what a marker may claim. Without it the instant a session writes
# into `.git/ralph.successor` decides how many nights are refused.
mutation "53 a marker may claim any instant at all" "$SCHEDULER_LIB" \
  's#  \[ "\$\(\(at - now\)\)" -le "\$\(scheduler__ceiling_max\)" \] \|\| return 1\n##' \
  test/scheduler.bats "could have produced"

# And the bound derived from the table rather than typed: read as zero, every
# marker is beyond it and the fence stops fencing.
mutation "53 the marker bound is not the widest ceiling of the table" "$SCHEDULER_LIB" \
  's#\$2 > max \{ max = \$2 \} END \{ print max \+ 0 \}#END { print 0 }#' \
  test/scheduler.bats "already armed for this tree"

# The word the journal gets. Every refusal said `weekly-pause` until [53], which
# is the exact word of a project that chose to resume by hand.
mutation "53 every refusal is journalled with the same word" "$SCHEDULER_LIB" \
  's#    4\) printf \x27successor-blocked-marker\\n\x27 ;;#    4) printf \x27weekly-pause\\n\x27 ;;#' \
  test/scheduler.bats "which refusal it was"

# A marker nobody woke — the ordinary outcome wherever `atrun` is disabled —
# counted at the start of the next run, the way the other two leftovers are.
mutation "53 a marker nobody woke is counted by nobody" "$GATE" \
  's/^gate__stale_successor\(\) \{/gate__stale_successor() { return 1;/m' \
  test/scheduler.bats "nobody woke is counted"

# The paired witness: counted on the instant and not on the file, or every night
# that armed something would report its own live marker as a leftover.
mutation "53 a marker still waiting for its instant is counted too" "$GATE" \
  's#  \[ "\$at" -le "\$now" \] \|\| return 1#  :#' \
  test/scheduler.bats "nobody woke is counted"

# ── the canary ───────────────────────────────────────────────────────────────

mutation "canary a hostile world still has to come out green" "$GATE" \
  's/^gate_write_surface\(\) \{/gate_write_surface() { printf "nothing\\\\n"; return 0;/m' \
  test/canary.bats "all resolved"

if [ "$LIST_ONLY" = 1 ]; then
  exit 0
fi

printf '\n%s mutations, %s not ok\n' "$TOTAL" "$BAD"
[ "$BAD" -eq 0 ]
