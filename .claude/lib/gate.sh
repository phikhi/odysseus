# shellcheck shell=bash
# The objective gate.
#
# Three deterministic checks decide whether an iteration delivered: the
# project's test suite, its type check, and the scope-guard. The loop runs them
# itself, so no model is ever asked whether its own work is good enough —
# complaisance is not a failure mode a return code has. The review lenses, the
# tier that does involve judgement, are separate and arrive with the registry.
#
# Two properties are load-bearing and easy to lose:
#
#   - Green has to be earned. A branch that is unconfigured, whose command does
#     not exist, or that left no verdict at all counts red. Otherwise a gate
#     nobody wired up is indistinguishable from a gate everything passes, which
#     is the one failure this whole framework exists to prevent.
#   - The branches do not short-circuit each other. They are backgrounded and
#     then collected, so a red suite still tells you whether the types are also
#     broken, and the wall-clock is the slowest branch rather than their sum.
#     Collecting them is the fragile half: a branch that was started and not
#     waited for is read as having no verdict, which counts red — see
#     `gate__collect` for why a bare `wait` does not survive a graceful stop.
#
# What the loop reads back, for the failure policy and the audit receipt:
#   RALPH_GATE_VERDICTS     e.g. "tests=green typecheck=red scope=green"
#   RALPH_GATE_FAILED       the red branch names
#   RALPH_GATE_SCOPE_CLASS  internal | contract, when the scope-guard is red
#   RALPH_GATE_TREE         the tree every branch is judged on, so the rollback and
#                           the durable commit act on exactly what was approved.
#                           Taken before the fan and filled in before it, so a
#                           branch — a subshell — inherits it ([29]).

gate__log() {
  printf 'ralph: gate: %s\n' "$*"
}

# ── preflight ────────────────────────────────────────────────────────────────

# Refuse to start rather than grind a whole frontier behind a gate that proves
# nothing. Called by the loop from the project root, before it takes the lock.
gate_preflight() {
  local rc=0

  if [ -z "${TEST_CMD:-}" ]; then
    printf 'ralph: TEST_CMD is empty — a gate with no test suite is green for the wrong reason\n' >&2
    rc=1
  fi

  # Empty is not the same statement as "this project has no type check": one is
  # a config nobody filled in, the other is a decision. Only the decision passes.
  if [ -z "${TYPECHECK_CMD:-}" ]; then
    printf 'ralph: TYPECHECK_CMD is empty — set it, or set it to "none" to declare this project has no type check\n' >&2
    rc=1
  fi

  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    printf 'ralph: not a git repository — the scope-guard has nothing to diff against\n' >&2
    rc=1
  fi

  return "$rc"
}

# ── the zone git does not show ───────────────────────────────────────────────
#
# Every check in this pack is built on a git tree object, so every check inherits
# git's own blind spot: what the *target project's* `.gitignore` covers is not in
# the tree, and a control that delegates its visibility to a file the project
# writes has to say how far it sees. Probed on 29/07/2026, three times over: a
# session wrote an ignored file off its write-surface and the verdict was
# `scope=green`; a red gate rolled the tree back and left the ignored file
# standing; and a ticket went green because of an ignored file the *previous*
# ticket's session had left behind, which no review of either ticket alone could
# have caught ([24]).

# The pack's own configuration: what a fresh `claude` process reads when it
# starts, and what the next run sources. No write-surface may cover these, and
# the snapshot takes them by force whatever GUARDED_PATHS says — emptying a
# config key must not be a way to unseal the harness.
#
# `.claude/settings.local.json` is the armed case and the reason this list
# exists: it is ignored by convention in every Claude Code project, so nothing in
# this pack could see it, and hooks, permissions and env in it take effect on the
# very next spawn. A session that wrote it would be configuring the harness that
# judges its successors. `ralph.config.sh` carries TEST_CMD, so a session that
# set it to `true` would make every later gate green while proving nothing.
#
# The pack's *code* is deliberately not sealed. A run has sourced its libs before
# the first session starts, so editing them cannot change the judgement of the
# run in progress; and a ticket that rewrites `gate.sh` is exactly what this
# repository does with itself. What a fresh `claude` reads is the different
# question, because it lands on the next spawn and nothing looks at it.
gate_sealed_paths() {
  printf '%s\n' '.claude/settings.local.json .claude/settings.json .claude/ralph.config.sh'
}

# Matched the same way a write-surface is, so a sealed directory would cover what
# is under it. See gate_in_surface, below.
gate_is_sealed() {
  gate_in_surface "$1" "$(gate_sealed_paths)"
}

# The paths the whole-tree snapshot takes by force. `.claude` by default — the
# pack itself, and the settings a session reads. GUARDED_PATHS is the project's
# to widen or narrow: a project whose own tooling writes under a guarded path
# while a session runs would otherwise watch every iteration go red on it. The
# sealed configuration is added whatever the key says.
gate_guarded_paths() {
  printf '%s %s\n' "${GUARDED_PATHS-.claude}" "$(gate_sealed_paths)"
}

# The ignored paths nothing in this pack looks at, enumerated rather than
# alluded to. "The tree is back where the session found it, except for a set of
# paths nobody lists" is the half-truth [24] was opened for.
#
# Directories are collapsed, so a project's `node_modules/` is one line and not a
# hundred thousand. Two exclusions, and both are load-bearing: the guarded paths,
# because the snapshot takes those by force and they *are* judged; and the
# feature's own bookkeeping, because [19] gitignores the run journal, the run
# lock and the session stream, all of which are written *during* the window being
# watched. Without the second one, every iteration of every project would report
# its own journal as an unjudged write — which is the same reason the scope-guard
# drops it (gate_is_bookkeeping, one definition, now three readers).
gate_unguarded_ignored() {
  local listing guarded file
  listing="$(git ls-files --others --ignored --exclude-standard --directory 2>/dev/null)" ||
    listing=""
  guarded="$(gate_guarded_paths)"

  while IFS= read -r file; do
    [ -n "$file" ] || continue
    if gate_is_bookkeeping "$file"; then continue; fi
    if gate_in_surface "${file%/}" "$guarded"; then continue; fi
    printf '%s\n' "$file"
  done <<IGNORED
$listing
IGNORED
  return 0
}

# A zone as one line: how many paths, and the first ten of them. Non-zero when
# there is nothing to say, so a caller can ask and stay silent. Ten names and no
# more; the count says how many were left out.
#
# Public, and the noun is the caller's. There are two zones nothing in this pack
# reaches — what git hides and what the gate wrote while it judged — and each of
# them is read by two callers with different things to say about the same list:
# the gate did not judge it, the rollback could not undo it. Counting and
# truncating in four places would drift in four directions.
gate_zone_line() {
  local list="$1" noun="$2"
  [ -n "$list" ] || return 1
  printf '%s %s: %s\n' \
    "$(printf '%s\n' "$list" | awk 'END { print NR }')" "$noun" \
    "$(printf '%s\n' "$list" | head -10 | tr '\n' ' ' | sed 's/ *$//')"
}

gate_ignored_zone() {
  local left
  left="$(gate_unguarded_ignored)" || left=""
  gate_zone_line "$left" 'ignored path(s)'
}

# ── what the gate itself changed ─────────────────────────────────────────────
#
# The gate is not a passive observer of the tree it judges. `TEST_CMD` and
# `TYPECHECK_CMD` are the target project's own commands — a coverage report, an
# updated test snapshot, a compiler cache — and a review lens ([06]) will be a
# `claude`. Whatever they write lands *after* the tree was taken, so it sits in
# neither of the two trees the rollback diffs: it survives the rollback, and it is
# not ignored by git either, so the zone of [24] does not name it.
#
# Which makes it the rollback's second unenumerated exemption, and it gets the
# same answer as the first: name it every time rather than let "the tree is back
# where the session found it" pass for a complete statement. It is not a verdict
# and must not become one — a project whose suite writes an artefact on every run
# has done nothing wrong, and reddening that would refuse every project that has
# a build.
#
# Before [29] this set was not merely unnamed, it was undecidable: the scope-guard
# took its own snapshot from inside its branch, in parallel with the suite, so
# whether a given artefact was "what the gate wrote" or "what the session wrote"
# depended on which process got there first.
gate_unjudged_changes() {
  local judged="$1" now
  [ -n "$judged" ] || return 0
  now="$(gate_tree_snapshot)" || return 0
  [ "$now" != "$judged" ] || return 0
  git diff-tree -r --name-only "$judged" "$now" 2>/dev/null | gate__drop_bookkeeping
}

# ── the diff an iteration is judged on ───────────────────────────────────────

# Everything in the working tree right now, as a git tree object: tracked or
# not, committed or not, the guarded paths included whether the project ignores
# them or not. Built in a throwaway index, so the real one is untouched.
#
# The commit at HEAD would be the obvious baseline and it is the wrong one. A
# green iteration is not committed by anything today, so its files are still
# lying in the tree when the next session starts: judged against HEAD, the
# second iteration of a run inherits the first one's work as its own overflow —
# and, worse, gets it classified as drift into the ticket that produced it. The
# same goes for a run started on a tree that was already dirty. A tree object
# says what was there when this session began, which is the actual question.
#
# Given paths, only those are snapshotted, and they are taken by force —
# ignore rules included. A caller that names a path is watching it deliberately,
# and a target project that gitignores `.scratch/` must not thereby switch the
# tracker's own guard off.
#
# Without paths, the whole tree, and there the project's ignore rules are obeyed
# with one named exception. `git add -A --force` on everything is not the fix and
# never will be: a project's build output would land in the tree the scope-guard
# judges and the rollback acts on, so every iteration would look like an overflow
# and every rollback would delete a cache the run has no business touching. So
# the guarded paths are forced on top of an ordinary `git add -A` — a named list,
# which only sees what somebody thought to name. What is left is enumerated
# instead of judged: see gate_unguarded_ignored.
gate_tree_snapshot() {
  local index tree path
  index="$(mktemp "${TMPDIR:-/tmp}/ralph-index.XXXXXX")" || return 1
  rm -f "$index"
  if [ "$#" -gt 0 ]; then
    GIT_INDEX_FILE="$index" git add -A --force -- "$@" >/dev/null 2>&1
  else
    GIT_INDEX_FILE="$index" git add -A >/dev/null 2>&1
    # One `git add` per guarded path rather than one for all of them: a pathspec
    # that matches nothing makes git refuse the whole call, and a project is free
    # to name a path it does not have yet. A refused pathspec leaves the snapshot
    # exactly as the plain `git add -A` left it, which is the status quo.
    for path in $(gate_guarded_paths); do
      GIT_INDEX_FILE="$index" git add -A --force -- "$path" >/dev/null 2>&1 || true
    done
  fi
  tree="$(GIT_INDEX_FILE="$index" git write-tree 2>/dev/null)" || tree=""
  rm -f "$index"
  [ -n "$tree" ] || return 1
  printf '%s\n' "$tree"
}

# What this session changed, and only this session. The second argument is the
# post-session tree when the caller already has one — the failure policy and the
# durable commit both act on the very tree the scope-guard judged, rather than
# re-reading a tree the test suite may have touched since.
#
# A baseline that is missing is never read as "nothing changed": a guard that
# cannot see must not pass.
#
# Public, and named so: the failure policy commits through it and the review
# lenses will read the diff through it. It was `gate__changed_files` until the
# second caller appeared, which made a private name a lie.
gate_changed_files() {
  local base="$1" now="${2:-}"
  [ -n "$now" ] || now="$(gate_tree_snapshot)" || now=""
  [ -n "$base" ] && [ -n "$now" ] || return 1
  git diff-tree -r --name-only "$base" "$now" 2>/dev/null | gate__drop_bookkeeping
}

# The loop's own writes are not the session's doing: claiming a ticket rewrites
# it, and the journal, the run lock and the session stream all live in the
# feature directory. Paths are repo-root relative, which is the project root —
# a pack installed below the repo root is out of scope for now.
#
# One definition, two readers: the scope-guard filters a list, the rollback asks
# path by path. A second copy of the rule would drift from this one and let the
# rollback rewrite the tracker — the only authority on state this system has.
gate_is_bookkeeping() {
  case "$1" in
    ".scratch/${FEATURE}/"*) return 0 ;;
  esac
  return 1
}

gate__drop_bookkeeping() {
  local file
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    if gate_is_bookkeeping "$file"; then continue; fi
    printf '%s\n' "$file"
  done
  return 0
}

# ── the scope-guard ──────────────────────────────────────────────────────────

# The declared write-surface as a plain list of globs. Backticks and commas are
# how a ticket writes it for a human; neither means anything here.
gate_write_surface() {
  tracker_field "$1" 'Write-surface' 2>/dev/null | tr -d '`,' | awk '{ $1 = $1; print }'
}

# Whether a path is covered by a surface. A pattern also covers what is under
# it, so a ticket can declare a directory instead of enumerating its files.
gate_in_surface() {
  local file="$1" pattern
  for pattern in $2; do
    pattern="${pattern%/}"
    [ -n "$pattern" ] || continue
    case "$file" in
      $pattern | $pattern/*) return 0 ;;
    esac
  done
  return 1
}

# Which other ticket declared this path. An overflow into another ticket's
# surface is a scoping conflict rather than a stray write: two tickets were
# drawn over one file, and retrying would only break the disjunction the
# parallel scheduler relies on. The failure policy tells them apart.
gate__surface_owner() {
  local file="$1" self="$2" id
  for id in $(tracker_ids); do
    [ "$id" != "$self" ] || continue
    if gate_in_surface "$file" "$(gate_write_surface "$id")"; then
      printf '%s\n' "$id"
      return 0
    fi
  done
  return 1
}

# Runs as a gate branch: findings on stdout, the classification in a sidecar file
# because a branch runs in its own process and cannot set a variable here.
#
# Both trees are given, and neither is read from the tree on disk. This function
# used to snapshot the working tree itself, from inside its own branch — which is
# to say while the test suite and the type check were already writing to it. The
# same session on the same ticket then got `scope=green` or `scope=red` depending
# on which process wrote first, and on one path that draw was final: an artefact
# landing in another ticket's write-surface is classified `contract`, deliberately
# not retryable, so the ticket went to the human sink without spending a retry for
# something no session had done. A control that freezes its input while other
# processes are still writing does not return a verdict, it returns a draw ([29]).
#
# An empty tree is refused rather than recomputed, and that matters more than it
# looks: `gate_changed_files` takes its own snapshot when it is not given one, so
# falling through to it would quietly restore the very race this argument exists
# to close. A guard that cannot see must not pass.
#
# A ticket with no declared write-surface is the fail-safe case: an unknown
# surface can never be assumed to contain anything.
gate__scope_guard() {
  local ticket="$1" base="$2" now="$3" classfile="$4"
  local surface changed file owner class='' rc=0

  if [ -z "$now" ] || ! changed="$(gate_changed_files "$base" "$now")"; then
    printf 'the scope-guard could not read the working tree — refusing to pass it\n'
    return 1
  fi

  surface="$(gate_write_surface "$ticket")"

  while IFS= read -r file; do
    [ -n "$file" ] || continue
    # Asked before the surface is consulted, and that ordering is the whole of
    # the guarantee: a ticket that declared the harness's own configuration would
    # otherwise buy a session the right to configure the sessions after it. Red,
    # and retryable — a fresh session starts from a tree the rollback has already
    # cleaned, so there is nothing here a retry cannot settle.
    if gate_is_sealed "$file"; then
      rc=1
      if [ -z "$class" ]; then class=internal; fi
      printf 'wrote %s, which configures the harness itself — no write-surface may cover it\n' "$file"
      continue
    fi
    if gate_in_surface "$file" "$surface"; then
      continue
    fi
    rc=1
    owner="$(gate__surface_owner "$file" "$ticket" || true)"
    if [ -n "$owner" ]; then
      class=contract
      printf 'wrote %s, inside the write-surface of %s (drift)\n' "$file" "$owner"
    else
      if [ -z "$class" ]; then class=internal; fi
      printf 'wrote %s, outside the declared write-surface\n' "$file"
    fi
  done <<SCOPE
$changed
SCOPE

  if [ -n "$class" ]; then
    printf '%s\n' "$class" >"$classfile"
  fi
  return "$rc"
}

# ── running the branches ─────────────────────────────────────────────────────

# One branch, in its own process: output to a file, exit code to another. The
# exit code file is the verdict, and its absence is a verdict too.
gate__branch() {
  local dir="$1" name="$2"
  shift 2
  local rc=0
  "$@" >"$dir/$name.out" 2>&1 || rc=$?
  printf '%s\n' "$rc" >"$dir/$name.rc"
}

gate__start() {
  local dir="$1" name="$2"
  shift 2
  (gate__branch "$dir" "$name" "$@") &
}

# Collect one branch, all the way to its exit code.
#
# `wait` is not a call the graceful stop can be trusted to survive. Bash defers a
# trap until an external command returns, but documents the opposite for the
# builtin: "the reception of a signal for which a trap has been set will cause the
# wait builtin to return immediately with an exit status greater than 128,
# immediately after which the trap is executed". The loop traps TERM and INT
# precisely so that a kill lets the current iteration finish — so a single `wait`
# per branch abandoned the fan the moment a stop was requested, and the
# aggregation below then read `.rc` files nobody had written yet. Live branches
# came back "no verdict", which counts red: an unearned `Failures:`, a rollback
# undoing the session's work while the very test suite judging it was still
# running, an orphaned branch outliving the run, and `rm -rf` on a directory
# processes were still writing to. Three of those on one ticket send it to a human
# as `failed-impl` without a single session having been judged.
#
# So wait again. Nothing is lost by doing so: the trap has already run by the time
# we are back here, `RALPH_STOP` is set, and the loop stops after this iteration —
# which is the whole promise. Disarming the trap around the fan would collect the
# branches and drop the stop, which is the opposite trade.
#
# `kill -0` is what separates the two ways a status over 128 arrives, since the
# code alone cannot: an interrupted `wait` leaves the branch running and still
# answering, whereas a branch that died *from* a signal — the watchdog's doing —
# has been reaped and no longer answers.
#
# It is the loop's only exit, and not a readability flourish. The tempting
# assumption is that a second `wait` on a pid bash has already reaped comes back
# 127, "not a child of this shell", which would end the loop by itself. Probed on
# bash 3.2: it does not. A pid that exited normally answers 0, but a pid that was
# *killed* answers 143 again, and again, without blocking — so dropping the
# liveness check turns the watchdog path into a busy spin that never returns.
# Which is why the test that covers this line carries its own deadline: removing
# it hangs the gate rather than failing an assertion.
gate__collect() {
  local pid="$1" rc
  while :; do
    rc=0
    wait "$pid" 2>/dev/null || rc=$?
    [ "$rc" -gt 128 ] || return 0
    kill -0 "$pid" 2>/dev/null || return 0
  done
}

# Every descendant, deepest first, then the process itself. Killing the branch
# alone would leave the command it started — a hung test suite holding a port or
# a database — running for the rest of the night, and `kill -- -PID` needs a
# process group this shell never made. `ps` is POSIX; the pack still needs
# nothing installed.
gate__kill_tree() {
  local pid="$1" child
  for child in $(ps -A -o pid= -o ppid= 2>/dev/null | awk -v p="$pid" '$2 == p { print $1 }'); do
    gate__kill_tree "$child"
  done
  kill -TERM "$pid" 2>/dev/null || true
  return 0
}

# The deadline. `wait` cannot take a timeout in bash 3.2, so the deadline is a
# process of its own: it sleeps in one-second steps — so that killing it leaves
# at most a one-second orphan behind — and then takes the branches down.
#
# A killed branch writes no exit code, and a branch with no verdict already
# counts red. The timeout needs no verdict of its own: it only has to stop a
# `TEST_CMD` that hangs from hanging the whole run, which the smart-zone net
# cannot do because it watches the session and not the gate.
gate__watchdog() {
  local limit="$1" marker="$2"
  shift 2
  local waited=0 pid
  while [ "$waited" -lt "$limit" ]; do
    sleep 1
    waited=$((waited + 1))
  done
  : >"$marker"
  for pid in "$@"; do
    gate__kill_tree "$pid"
  done
  return 0
}

# The zone this gate did not look at, named on every iteration rather than left
# to a document nobody reads at three in the morning. It is not a verdict and
# must not become one: the paths listed here are the project's own ignored files,
# and turning them red would mean refusing every project that has a build.
#
# What it buys is the one failure a per-ticket review cannot see. A file dropped
# in this zone survives the rollback and every later iteration, so a `TEST_CMD`
# that reads it — an `.env`, a fixture cache, a test database, `node_modules` —
# can be turned green by what an earlier session left behind. Probed: two
# tickets, the second green thanks to the first one's write, both marked
# resolved. Naming the zone is what makes that visible in the morning.
gate__report_unguarded() {
  local ticket="$1" zone
  if zone="$(gate_ignored_zone)"; then
    gate__log "$ticket: nothing in this gate judged $zone"
  fi
  return 0
}

# And the other zone nothing here reaches: what the gate's own branches wrote
# while they were judging. Same shape as the line above and for the same reason —
# it is not a verdict, it is the half of "the tree is back where the session found
# it" that would otherwise go unsaid. Said on every iteration, green included:
# a green one has no rollback at all, and the artefact is still there.
gate__report_changed() {
  local ticket="$1" zone
  if zone="$(gate_zone_line "$(gate_unjudged_changes "$2")" \
    'path(s) after the tree it judged')"; then
    gate__log "$ticket: this gate itself changed $zone"
  fi
  return 0
}

# Up to 20 lines of what a red branch had to say. Enough to see which test
# broke in the journal; the full picture belongs to the audit receipt.
gate__report() {
  [ -s "$1" ] || return 0
  tail -20 "$1" | sed 's/^/  /'
  return 0
}

# The gate. Green — return 0 — means every branch that was triggered came back
# green, and that is the only thing that resolves a ticket.
gate_run() {
  local ticket="$1" base="${2:-}"
  local dir names='' pids='' name rc=0 brc watchdog=''

  # Cleared before the first thing that can fail, so a gate that refuses to start
  # never leaves the previous iteration's tree standing for the rollback to act on.
  RALPH_GATE_VERDICTS=""
  RALPH_GATE_FAILED=""
  RALPH_GATE_SCOPE_CLASS=""
  RALPH_GATE_TREE=""
  dir="$(mktemp -d "${TMPDIR:-/tmp}/ralph-gate.XXXXXX")" || return 1

  # The tree every branch is judged on, taken once and before a single branch is
  # started. Both halves are load-bearing. *Once*, so that the scope-guard, the
  # rollback, the durable commit and — with [06] — a review lens all speak about
  # one state of the repository instead of four snapshots taken while the suite
  # ran. *Before the fan*, so that nothing the gate itself writes can be charged
  # to the session or, worse, to another ticket. Filled into RALPH_GATE_TREE here
  # rather than after the collection: a branch is a subshell, so it inherits what
  # is set before it starts and nothing that is set after.
  #
  # An unreadable tree is left empty on purpose. The scope-guard refuses to pass a
  # ticket it cannot see, which is what makes this branch red rather than absent —
  # and a branch that was never started leaves no verdict to count.
  RALPH_GATE_TREE="$(gate_tree_snapshot)" || RALPH_GATE_TREE=""

  gate__start "$dir" tests bash -c "$TEST_CMD"
  names="$names tests"
  pids="$pids $!"

  # "none" is a project declaring it has no type check. Not triggered, so not
  # part of the verdict — and never counted as a pass.
  if [ -n "${TYPECHECK_CMD:-}" ] && [ "$TYPECHECK_CMD" != none ]; then
    gate__start "$dir" typecheck bash -c "$TYPECHECK_CMD"
    names="$names typecheck"
    pids="$pids $!"
  fi

  gate__start "$dir" scope \
    gate__scope_guard "$ticket" "$base" "$RALPH_GATE_TREE" "$dir/scope.class"
  names="$names scope"
  pids="$pids $!"

  # An unset, zero or non-numeric GATE_TIMEOUT means no deadline. That is the
  # status quo and not a false green: a hung branch never comes back green.
  case "${GATE_TIMEOUT:-0}" in
    '' | 0 | *[!0-9]*) ;;
    *)
      gate__watchdog "$GATE_TIMEOUT" "$dir/timed-out" $pids &
      watchdog=$!
      ;;
  esac

  for brc in $pids; do
    gate__collect "$brc"
  done

  if [ -n "$watchdog" ]; then
    kill -TERM "$watchdog" 2>/dev/null || true
    gate__collect "$watchdog"
  fi

  for name in $names; do
    brc=""
    if [ -f "$dir/$name.rc" ]; then brc="$(cat "$dir/$name.rc")"; fi
    if [ "$brc" = 0 ]; then
      RALPH_GATE_VERDICTS="$RALPH_GATE_VERDICTS $name=green"
      continue
    fi
    RALPH_GATE_VERDICTS="$RALPH_GATE_VERDICTS $name=red"
    RALPH_GATE_FAILED="$RALPH_GATE_FAILED $name"
    rc=1
    if [ -n "$brc" ]; then
      gate__log "$name red (exit $brc)"
    elif [ -f "$dir/timed-out" ]; then
      gate__log "$name red (timed out after ${GATE_TIMEOUT}s)"
    else
      gate__log "$name red (no verdict)"
    fi
    gate__report "$dir/$name.out"
  done

  if [ -f "$dir/scope.class" ]; then
    RALPH_GATE_SCOPE_CLASS="$(cat "$dir/scope.class")"
  fi
  RALPH_GATE_VERDICTS="${RALPH_GATE_VERDICTS# }"
  RALPH_GATE_FAILED="${RALPH_GATE_FAILED# }"

  gate__log "$ticket: $RALPH_GATE_VERDICTS"
  gate__report_unguarded "$ticket"
  gate__report_changed "$ticket" "$RALPH_GATE_TREE"
  rm -rf "$dir"
  return "$rc"
}
