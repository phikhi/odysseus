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
# Two of those are worth knowing before writing anything here:
#
#   - every `run` overwrites $output, so a negative assertion aimed at the wrong
#     one can never fail. Keep the output you mean to assert on in a variable.
#   - this file lied too. Twelve entries carried an unescaped `$var` in their
#     replacement half, which perl interpolates to nothing: they broke the file
#     instead of removing the guarantee, reported `ok`, and hid three vacuous
#     tests underneath. A gate that checks tests is a test. Hence BROKEN below.
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

  if printf '%s' "$out" | grep -qE '(^| )0 failures'; then
    printf 'VACUOUS  %s\n         %s -f "%s" stayed green without it\n' \
      "$label" "$testfile" "$filter"
    BAD=$((BAD + 1))
    return 0
  fi
  if printf '%s' "$out" | grep -qE '^0 tests|(^| )0 tests,'; then
    printf 'DRIFTED  %s\n         no test matches -f "%s" in %s\n' "$label" "$filter" "$testfile"
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
TRACKER=".claude/lib/tracker-local.sh"
STATE=".claude/lib/state.sh"
FAILURES=".claude/lib/failures.sh"
HARNESS="test/helpers/harness.bash"
SHIM="test/helpers/shims/claude"
CONTRACT="test/helpers/claude-contract.bash"

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

mutation "03 the session decides whether it succeeded" "$LOOP" \
  's/    if \[ "\$rc" -eq 0 \] && \[ "\$\{RALPH_SOFT_LIMIT_HIT:-0\}" = 0 \]; then/    if true; then/' \
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

mutation "04 crossing the soft limit does not kill the session" "$MONITOR" \
  's/        kill -TERM "\$pid" 2>\/dev\/null\n//' \
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

mutation "04 a partial stream line is dropped" "$MONITOR" \
  's/\{ partial="\$partial\$line"; false; \}/{ partial=""; false; }/' \
  test/smart-zone.bats "split across two writes"

mutation "04 the threshold is hard-coded" "$SESSION" \
  's/  monitor_watch "\$outfile" "\$pid" "\$SOFT_LIMIT_TOKENS"/  monitor_watch "\$outfile" "\$pid" 150000/' \
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

mutation "05 the loop's own writes trip the scope-guard" "$GATE" \
  's/ \| gate__drop_bookkeeping//' \
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

mutation "05 the tree is not re-read after the session" "$GATE" \
  's/  now="\$\(gate_tree_snapshot\)" \|\| now=""/  now="\$base"/' \
  test/gate.bats "new file outside"

mutation "05 the snapshot ignores untracked files" "$GATE" \
  's/  GIT_INDEX_FILE="\$index" git add -A >\/dev\/null 2>&1/  GIT_INDEX_FILE="\$index" git read-tree HEAD >\/dev\/null 2>\&1; GIT_INDEX_FILE="\$index" git add -u >\/dev\/null 2>\&1/' \
  test/gate.bats "new file outside"

mutation "05 the tree diff is not recursive" "$GATE" \
  's/git diff-tree -r --name-only/git diff-tree --name-only/' \
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

# Not at the process seam: the loop's post-session snapshot is taken before the
# retry counter is written, so the tracker is identical on both sides of the
# rollback's diff and no full-loop test can see the exclusion work. The test that
# holds it drives the rollback directly, with the counter written in between.
mutation "07 the rollback rewrites the loop's own bookkeeping" "$FAILURES" \
  's/    if gate_is_bookkeeping "\$path"; then continue; fi\n//' \
  test/failures.bats "never restores the tracker"

mutation "07 a file the session added is not removed" "$FAILURES" \
  's/        rm -f "\$path"\n/        :\n/' \
  test/failures.bats "stray write is undone"

mutation "07 a file the session deleted is not restored" "$FAILURES" \
  's/        GIT_INDEX_FILE="\$idx" git checkout-index -f -- "\$path" 2>\/dev\/null \|\|\n          failures__log "could not restore \$path"/        :/' \
  test/failures.bats "session deleted comes back"

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
  's/  if \[ -n "\$reason" \]; then\n    failures_preserve_attempt "\$ticket" "\$pre" "\$tree" \|\| true\n  fi\n//' \
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

mutation "07 a quarantined ticket is only logged, not taken off the frontier" "$FAILURES" \
  's/    tracker_mark_escalated "\$stray" decision \|\| true\n/    :\n/' \
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

mutation "21 the tracker snapshot obeys the project's ignore rules" "$GATE" \
  's/    GIT_INDEX_FILE="\$index" git add -A --force -- "\$@" >\/dev\/null 2>&1/    GIT_INDEX_FILE="\$index" git add -A -- "\$@" >\/dev\/null 2>\&1/' \
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

mutation "22 a run killed without releasing wedges the tree for good" "$STATE" \
  's/^  rm -rf "\$guard"\n  mkdir "\$guard" 2>\/dev\/null \|\| return 1/  return 1/m' \
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

# ── the canary ───────────────────────────────────────────────────────────────

mutation "canary a hostile world still has to come out green" "$GATE" \
  's/^gate_write_surface\(\) \{/gate_write_surface() { printf "nothing\\\\n"; return 0;/m' \
  test/canary.bats "all resolved"

if [ "$LIST_ONLY" = 1 ]; then
  exit 0
fi

printf '\n%s mutations, %s not ok\n' "$TOTAL" "$BAD"
[ "$BAD" -eq 0 ]
