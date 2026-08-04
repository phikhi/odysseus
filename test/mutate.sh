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
  's/    if \[ "\$rc" -eq 0 \] && \[ "\$\{RALPH_SOFT_LIMIT_HIT:-0\}" = 0 \] &&\n      \[ -z "\$\{RALPH_SESSION_TIMEOUT:-\}" \]; then/    if true; then/' \
  test/loop-happy-path.bats "a session that fails resolves nothing"

mutation "03 the sterile counter never resets" "$LOOP" \
  's/        sterile=0\n      else/        :\n      else/' \
  test/loop-happy-path.bats "sterile counts consecutive"

mutation "03 the iteration cap does not stop the run" "$LOOP" \
  's/    if \[ "\$iteration" -ge "\$ITER_CAP" \]; then/    if false; then/' \
  test/loop-happy-path.bats "iteration cap"

mutation "03 a stop request tears the iteration down" "$LOOP" \
  's/  trap .loop_request_stop. TERM INT\n//' \
  test/loop-happy-path.bats "graceful kill"

mutation "03 the ticket is not given back after a failure" "$FAILURES" \
  's/    tracker_unclaim "\$ticket"\n//' \
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
  's/"\$base" "\$now" 2>\/dev\/null \| gate__drop_bookkeeping/"\$base" "\$now" 2>\/dev\/null/' \
  test/gate.bats "stays inside its write-surface"

mutation "05 drift is not told apart from a stray write" "$GATE" \
  's/^gate__surface_owner\(\) \{/gate__surface_owner() { return 1;/m' \
  test/gate.bats "named as drift"

mutation "05 an undeclared write-surface allows everything" "$GATE" \
  's/^gate_write_surface\(\) \{/gate_write_surface() { printf "*\\\\n"; return 0;/m' \
  test/gate.bats "no write-surface may not write"

mutation "05 the scope-guard baseline is the last commit" "$LOOP" \
  's/    base="\$\(gate_tree_snapshot\)" \|\| base=""/    base="$(git rev-parse HEAD)"/' \
  test/gate.bats "previous one left in the tree"

mutation "05 a tree dirty before the run is charged to the ticket" "$LOOP" \
  's/    base="\$\(gate_tree_snapshot\)" \|\| base=""/    base="$(git rev-parse HEAD)"/' \
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
  's/git diff-tree -r --name-only "\$base" "\$now"/git diff-tree --name-only "\$base" "\$now"/' \
  test/gate.bats "new file outside"

mutation "05 the gate verdict does not decide the marking" "$LOOP" \
  's/      if gate_run "\$ticket" "\$base" && /      if { gate_run "\$ticket" "\$base" || true; } \&\& /' \
  test/gate.bats "red test suite resolves nothing"

mutation "05 a red gate is journalled as a plain failure" "$LOOP" \
  's/        outcome=gate-red/        outcome=failed/' \
  test/gate.bats "journalled as such"

mutation "05 the scope class is never said out loud" "$LOOP" \
  's/          loop_log "scope overflow on \$ticket: \$RALPH_GATE_SCOPE_CLASS"/          :/' \
  test/gate.bats "named as drift"

# ── [07] typed failures, rollback, durable green ─────────────────────────────

mutation "07 nothing puts the tree back after a red gate" "$FAILURES" \
  's/  failures_rollback "\$pre" "\$base" "\$tree" \|\| true\n//' \
  test/canary.bats "absolved"

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
  test/failures.bats "stray write is undone"

mutation "07 a file the session deleted is not restored" "$GATE" \
  's/        GIT_INDEX_FILE="\$idx" git checkout-index -f -- "\$path" 2>\/dev\/null \|\|\n          gate__log "could not restore \$path"/        :/' \
  test/failures.bats "session deleted comes back"

# The seam [06] introduced between the two: the rollback learns what it undid from
# what the primitive printed, and it needs that list for the unstaging and for the
# netting of the "could not undo" line. Emptied rather than removed — a caller that
# gets an empty list is the failure mode, a caller that does not compile is not.
mutation "06 the rollback never learns what it put back" "$FAILURES" \
  's/^\$restored\nROLLBACK/\nROLLBACK/m' \
  test/failures.bats "stray write is undone"

mutation "07 what the session staged stays staged" "$FAILURES" \
  's/    git reset -q -- \$paths 2>\/dev\/null \|\| true/    :/' \
  test/failures.bats "stray write is undone"

mutation "07 the commit a session made is left in the history" "$FAILURES" \
  's/    if git reset -q --mixed "\$pre" 2>\/dev\/null; then/    if false; then/' \
  test/failures.bats "commit the session made"

mutation "07 the rollback is a blanket reset --hard" "$FAILURES" \
  's/    if git reset -q --mixed "\$pre" 2>\/dev\/null; then/    if git reset -q --hard "\$pre" 2>\/dev\/null \&\& git clean -qfd; then/' \
  test/failures.bats "commit the session made"

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
  's/  if \[ -n "\$reason" \] && \[ "\$class" != nothing-delivered \]; then\n    failures_preserve_attempt "\$ticket" "\$pre" "\$tree" \|\| true\n  fi\n//' \
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
  's/        failures_make_durable "\$ticket" "\$pre" "\$base" "\$\{RALPH_GATE_TREE:-\}" \|\| true\n//' \
  test/failures.bats "never takes away what an earlier gate"

mutation "07 the durable commit takes the whole tree, not what the gate approved" "$FAILURES" \
  's/  GIT_INDEX_FILE="\$idx" git add -A -- \$changed >\/dev\/null 2>&1 \|\| true/  GIT_INDEX_FILE="\$idx" git add -A >\/dev\/null 2>\&1 || true/' \
  test/failures.bats "nothing else is"

mutation "07 the durable commit does not move the branch" "$FAILURES" \
  's/ \|\|\n    ! git update-ref -m "ralph: \$ticket" HEAD "\$commit" "\$head" 2>\/dev\/null//' \
  test/failures.bats "nothing else is"

mutation "07 the durable commit is a write, not a compare-and-swap" "$FAILURES" \
  's/HEAD "\$commit" "\$head" 2>\/dev\/null/HEAD "\$commit" 2>\/dev\/null/' \
  test/failures.bats "never overwrites a HEAD"

mutation "07 a session's own tickets reach the frontier" "$LOOP" \
  's/    failures_quarantine_strays "\$ticket" "\$seen" \|\| true\n//' \
  test/failures.bats "own tickets"

# The escalated id is `$final` and not `$stray` since [27]: what a session adds
# is renumbered before it is quarantined, so the id that leaves the frontier is
# the one the ticket ends up carrying. The guarantee is unchanged — a ticket the
# session wrote itself must not sit on the frontier — the line moved under it.
mutation "07 a quarantined ticket is only logged, not taken off the frontier" "$FAILURES" \
  's/    tracker_mark_escalated "\$final" decision \|\| true\n/    :\n/' \
  test/failures.bats "own tickets"

mutation "07 a plan is read even from a session that wrote the tracker" "$FAILURES" \
  's/  if ! failures_quarantine_strays "\$ticket" "\$seen"; then\n    rm -f "\$plan" "\$plan.prompt" "\$out" "\$out.tokens"\n    return 1\n  fi\n//' \
  test/failures.bats "whole plan refused"

mutation "07 a git that refuses the commit takes the run down" "$LOOP" \
  's/"\$\{RALPH_GATE_TREE:-\}" \|\| true/"\${RALPH_GATE_TREE:-}"/' \
  test/failures.bats "commit git refuses"

mutation "07 a git that refuses the branch takes the run down" "$FAILURES" \
  's/    failures_preserve_attempt "\$ticket" "\$pre" "\$tree" \|\| true\n  fi/    failures_preserve_attempt "\$ticket" "\$pre" "\$tree"\n  fi/' \
  test/failures.bats "branch git cannot name"

mutation "07 a gate branch that hangs is left to hang" "$GATE" \
  's/      gate__watchdog "\$GATE_TIMEOUT" "\$dir\/timed-out" \$pids &\n//' \
  test/failures.bats "hangs is red"

mutation "07 the deadline is hard-coded" "$GATE" \
  's/      gate__watchdog "\$GATE_TIMEOUT"/      gate__watchdog 1800/' \
  test/failures.bats "hangs is red"

mutation "07 a timed-out branch is not reported as one" "$GATE" \
  's/    elif \[ -f "\$dir\/timed-out" \]; then\n      gate__log "\$name red \(timed out after \$\{GATE_TIMEOUT\}s\)"\n//' \
  test/failures.bats "hangs is red"

# ── [21] the tracker a session must not write ────────────────────────────────

mutation "21 nothing guards the tracker from a session" "$FAILURES" \
  's/^failures_protect_tracker\(\) \{/failures_protect_tracker() { return 0;/m' \
  test/canary.bats "widen its own write-surface"

mutation "21 the tracker is only watched through its ids" "$LOOP" \
  's/    failures_protect_tracker "\$ticket" "\$issues" \|\| tracker_written=1\n//' \
  test/failures.bats "not given"

mutation "21 an edit to a ticket is not put back" "$FAILURES" \
  's/        GIT_INDEX_FILE="\$idx" git checkout-index -f -- "\$path" 2>\/dev\/null \|\|\n          failures__log "\$ticket: could not restore \$path"/        :/' \
  test/canary.bats "widen its own write-surface"

mutation "21 the write-surface is read after the session, not at spawn" "$LOOP" \
  's/    issues="\$\(failures_tracker_tree\)" \|\| issues=""\n    rc=0\n    loop_spawn_session "\$ticket" "\$outfile" \|\| rc=\$\?/    rc=0\n    loop_spawn_session "\$ticket" "\$outfile" || rc=\$?\n    issues="\$(failures_tracker_tree)" || issues=""/' \
  test/canary.bats "widen its own write-surface"

mutation "21 an edited tracker still buys a green iteration" "$LOOP" \
  's/ && \[ "\$tracker_written" = 0 \]//' \
  test/failures.bats "pays for the edit"

mutation "21 an edited tracker is journalled as a plain red gate" "$LOOP" \
  's/        \[ "\$tracker_written" = 0 \] \|\| outcome=tracker-write\n//' \
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
  's/    failures__log "\$ticket: no pre-session tracker snapshot — the tracker cannot be vouched for"\n    return 1/    return 0/' \
  test/failures.bats "vouch for"

mutation "21 the tracker the session staged stays staged" "$FAILURES" \
  's/  git reset -q -- "\$dir" 2>\/dev\/null \|\| true\n//' \
  test/failures.bats "stay staged"

mutation "21 a plan is read from a session that edited the tracker" "$FAILURES" \
  's/  if ! failures_protect_tracker "\$ticket" "\$issues"; then\n    rm -f "\$plan" "\$plan.prompt" "\$out" "\$out.tokens"\n    return 1\n  fi\n//' \
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
  's/    reclaimed="\$\(claim_reclaim_stale\)"/    reclaimed=""/' \
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
  's/    if ! run_lock_is_ours; then\n      loop_log "the run lock is gone or not ours any more after \$iteration iterations — stopping rather than grinding beside another run"\n      exit 4\n    fi\n//' \
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
  's/    if ! tree_lock_is_ours; then\n      loop_log "the working-tree lock is gone or not ours any more after \$iteration iterations — stopping rather than grinding beside another run"\n      exit 4\n    fi\n//' \
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
  's/ &&\n      \[ -z "\$\{RALPH_SESSION_TIMEOUT:-\}" \]//' \
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
  's/  if gate_is_bookkeeping "\$file"; then return 0; fi\n  if gate__under_path/  if gate__under_path/' \
  test/gate.bats "own bookkeeping"

# The lie in the other direction: naming a path the gate *did* judge. Held by the
# two refutations in the same test, which is the shape this suite has got wrong
# before — so the guarded case had to be a project whose only ignored path is a
# guarded one, or the refutation would pass on the strength of another path.
mutation "24 a guarded path is reported as unjudged too" "$GATE" \
  's/  if gate__under_path "\$\{file%\/\}" "\$guarded"; then return 0; fi\n//' \
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
mutation "30 the pin records nothing of .git/info/exclude" "$GATE" \
  's/  \[ -f "\$file" \] && cp "\$file" "\$rules\/\.git\/info\/exclude" 2>\/dev\/null/  :/' \
  test/gate.bats "does not hide what it wrote behind it"

# The half that keeps one red iteration from buying a whole night: without the
# restore, the *next* pin records the widened frontier as the project's own.
mutation "30 the frontier of the git directory is not put back" "$GATE" \
  's/^gate__ignore_restore\(\) \{/gate__ignore_restore() { return 1;/m' \
  test/gate.bats "widen the blind zone"

# Reporting the intention instead of the result. `git config --unset` writes the
# repository config, so a key a session put in the user's config survives it — and
# the message said "(put back)" all the same.
mutation "30 a restore that was only attempted reports success" "$GATE" \
  's/  \[ "\$\(gate__ignore_current "\$name"\)" = "\$pinned" \]/  return 0/' \
  test/gate.bats "could not put back"

# The verdict, as opposed to the visibility: the frontier moves, the file behind it
# is still judged through the pin, and nothing says who moved it.
mutation "30 moving the frontier is not a finding" "$GATE" \
  's/^gate_ignore_frontier\(\) \{/gate_ignore_frontier() { return 0;/m' \
  test/gate.bats "widen the blind zone"

mutation "30 the scope-guard drops the frontier findings" "$GATE" \
  's/  if \[ -n "\$\{RALPH_GATE_IGNORE:-\}" \]; then/  if [ -n "" ]; then/' \
  test/gate.bats "outside the repository is named"

# The cause behind [24]'s consequence, which is the one line a human gets when the
# rule is legitimate work.
mutation "30 nothing says the session moved the frontier" "$GATE" \
  's/^gate__report_frontier\(\) \{/gate__report_frontier() { return 0;/m' \
  test/gate.bats "does not hide what it wrote behind it"

# Fail-closed. A pin that is set and unreadable must not read as "no pin at all",
# which is the fail-open the whole mechanism would collapse into.
mutation "30 a broken pin snapshots anyway" "$GATE" \
  's/  if gate__ignore_pin_broken; then return 1; fi/  :/' \
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
  's/moved="\$\(gate_ignore_frontier\)"/moved=""/' \
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
  's/^gate__under_path\(\) \{\n  local file="\$1" path/gate__under_path() {\n  gate_in_surface "\$1" "\$2"; return;\n  local file="\$1" path/m' \
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
  's/    failures__log "cannot read the working tree — nothing was rolled back"\n    RALPH_ROLLBACK_FAILED=1\n/    failures__log "cannot read the working tree — nothing was rolled back"\n/' \
  test/failures.bats "stops the run instead of laundering"

mutation "34 the loop grinds on after a rollback that could not act" "$LOOP" \
  's/    if \[ "\$\{RALPH_ROLLBACK_FAILED:-0\}" = 1 \]; then/    if false; then/' \
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
  test/gate.bats "named, not left to be found"

# The two halves of this diff that the entries for [05] cover on the other one, and
# they are here because that diff has its own callers now. A build writes into a
# directory, which is why the tests name `build/coverage.xml` and not a path at the
# root: a non-recursive diff would report `build` and read as covered.
mutation "29 the diff of what the gate changed is not recursive" "$GATE" \
  's/git diff-tree -r --name-only "\$judged" "\$now"/git diff-tree --name-only "\$judged" "\$now"/' \
  test/gate.bats "named, not left to be found"

mutation "29 the loop's own bookkeeping counts as a gate write" "$GATE" \
  's/"\$judged" "\$now" 2>\/dev\/null \| gate__drop_bookkeeping/"\$judged" "\$now" 2>\/dev\/null/' \
  test/failures.bats "leaves it standing"

# Emptied rather than removed: the block that names the zone spans four lines, and
# a list that arrives empty silences it through the same path a gate that wrote
# nothing does. The ignored-zone line above it is untouched, so this entry cannot
# pass on the strength of [24]'s.
mutation "29 the rollback says nothing about what the gate changed" "$FAILURES" \
  's/"\$\(failures__minus "\$changed" "\$undone"\)"/""/' \
  test/failures.bats "leaves it standing"

# And the lie in the other direction: an empty fence filters nothing, so a path the
# rollback did put back is announced as one it could not.
mutation "29 a path the rollback put back is named as one it could not" "$FAILURES" \
  's/  local fence=" \$\{2:-\} " item/  local fence="" item/' \
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
  's/      gate__log "\$ticket: no review lens ran \(LENSES is empty\)[^\n]*\n/      :\n/' \
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
  's/  gate__aggregate "\$dir" "\$lenses" \|\| rc=1/  gate__aggregate "\$dir" "\$lenses" || true/' \
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
  's/    gate__log "\$ticket: could not read the tree before the review lenses[^\n]*\n    return 1/    return 0/' \
  test/lenses.bats "cannot be read before the lenses"

# The stream is the mechanism's own write, and it lives under TMPDIR so that the
# mechanism puts nothing in the repository. Moved into the tree, the containment
# above notices it — which is what makes these two guarantees one story.
mutation "06 the lens stream is written into the tree it judges" "$LENSES_LIB" \
  's/ stream="\$dir\/lens-\$name.jsonl"/ stream="lens-\$name.jsonl"/' \
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

# The findings of `gate_ignore_frontier` ride on the scope-guard's output, and the
# scope-guard is not started on this path. Without this loop a session that moved
# an ignore rule and wrote nothing would have its move put back in silence ([30]).
mutation "35 a frontier moved on this path is put back without a word" "$GATE" \
  's/      gate__log "\$ticket: \$finding"/      :/' \
  test/gate.bats "moved the ignore frontier is still told so"

mutation "35 the loop journals it as an ordinary red gate" "$LOOP" \
  's/        \[ "\$\{RALPH_GATE_NOTHING_DELIVERED:-0\}" = 0 \] \|\| outcome=nothing-delivered\n//' \
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
  's/    crash \| timeout\) failures__ignore_frontier "\$ticket" ;;/    crash | timeout) : ;;/' \
  test/failures.bats "crashed cannot leave the ignore frontier widened"

# The correction placed on the path that happened to be probed — which is exactly
# what [30] shipped, and why every class is named by a test of its own.
mutation "32 only the class the probe used gets its frontier back" "$FAILURES" \
  's/    crash \| timeout\) failures__ignore_frontier/    crash) failures__ignore_frontier/' \
  test/failures.bats "cut short cannot leave it widened either"

# And the other way the correction goes wrong: bolted onto every class, so the
# paths a gate already handled speak twice about one movement.
mutation "32 the restore is bolted onto every class, gated or not" "$FAILURES" \
  's/    crash \| timeout\) failures__ignore_frontier/    *) failures__ignore_frontier/' \
  test/failures.bats "once, not twice"

# The cause line behind [24]'s consequence, on the path where `gate__report_frontier`
# never runs: without it a human reads "this rollback could not undo … lib/" with
# nothing saying a session had just decided to hide it.
mutation "32 nothing names the tree rules a crashed session wrote" "$FAILURES" \
  's/  if moved="\$\(gate_moved_tree_rules\)"; then/  if false; then/' \
  test/failures.bats "named before it goes"

# ── the canary ───────────────────────────────────────────────────────────────

mutation "canary a hostile world still has to come out green" "$GATE" \
  's/^gate_write_surface\(\) \{/gate_write_surface() { printf "nothing\\\\n"; return 0;/m' \
  test/canary.bats "all resolved"

if [ "$LIST_ONLY" = 1 ]; then
  exit 0
fi

printf '\n%s mutations, %s not ok\n' "$TOTAL" "$BAD"
[ "$BAD" -eq 0 ]
