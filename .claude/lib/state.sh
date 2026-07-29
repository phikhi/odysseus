# shellcheck shell=bash
# Run state: where the project is, what time it is, how a file is published,
# and the two locks that keep runs from standing on each other — one per tracker,
# one per working tree. They answer different questions; see each section.
#
# Every durable write goes through state_atomic_write. The tracker is the only
# authority on state, so a half-written ticket is a corrupted database — and a
# run that dies mid-write is the normal case here, not an edge case.

ralph_project_root() {
  if [ -n "${RALPH_PROJECT_ROOT:-}" ]; then
    printf '%s\n' "$RALPH_PROJECT_ROOT"
    return 0
  fi
  (cd "$RALPH_DIR/.." && pwd)
}

ralph_feature_dir() {
  printf '%s/.scratch/%s\n' "$(ralph_project_root)" "${FEATURE:?ralph: FEATURE is not set}"
}

ralph_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# Publish stdin to $1 in one step: write beside the target, then rename.
# The temp name never ends in .md, so a concurrent frontier scan cannot mistake
# it for a ticket.
state_atomic_write() {
  local dest="$1" tmp
  tmp="$(mktemp "${dest}.tmp.XXXXXX")" || return 1
  if ! cat >"$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  mv -f "$tmp" "$dest"
}

# ── exclusion guards ─────────────────────────────────────────────────────────
#
# mkdir is the atomic primitive available to a pure-bash pack: it succeeds for
# exactly one caller, with no read-then-write window. Everything that needs
# mutual exclusion — the run lock, a claim's test-and-set — takes a guard
# directory holding its owner's pid.
#
# A holder that dies without releasing is recovered rather than left to wedge
# an AFK run forever. Liveness is pid-based and therefore single-machine, and it
# is deliberately the shorter of the two policies in the pack: a guard is held
# for the length of one read-modify-write or one run, so a pid is enough. What a
# claim needs on top — a TTL backstop against a recycled pid, because a claim
# outlives the process that took it — lives in lib/claim.sh.
#
# The optional note is whatever the caller wants a refused rival to be told —
# a pid alone says which process, never which run. It is written just after the
# mkdir rather than with it, because mkdir is the only atomic test-and-set a
# pure-bash pack has: a rival that reads the guard inside that window sees the
# pid and no note, so every reader treats a missing note as unknown.

state_guard_take() {
  local guard="$1" label="${2:-guard}" note="${3:-}" owner moved
  mkdir -p "$(dirname "$guard")"

  if mkdir "$guard" 2>/dev/null; then
    state__guard_stamp "$guard" "$note"
    return 0
  fi

  owner="$(cat "$guard/pid" 2>/dev/null || echo '')"
  if [ -n "$owner" ] && kill -0 "$owner" 2>/dev/null; then
    return 1
  fi

  # Taking over a dead owner's guard displaces it by rename, not by `rm -rf`.
  # A rename is exclusive — the directory moves once and the loser gets ENOENT —
  # so two runs that both found the same dead owner cannot both clear the way and
  # then create their own guard over the other's. Whoever loses the rename falls
  # through to the same mkdir below, which is what settles it. Nothing wedges if
  # the winner dies in between: the guard is simply gone and the next caller
  # creates it.
  #
  # What this does *not* close, so that nobody reads more into it: a run still
  # deciding "the owner is dead" while another run finishes its takeover will
  # displace a guard that is now live, rename or not, because neither step checks
  # that the guard is still the one it inspected. The filesystem has no
  # compare-and-swap to express that in bash. What covers it is downstream — the
  # run and tree locks are re-checked for ownership on every iteration
  # (`*_is_ours`), and a claim is a test-and-set on the ticket's own status.
  moved="$guard.stale.$$"
  if mv "$guard" "$moved" 2>/dev/null; then
    rm -rf "$moved"
    printf 'ralph: taking over a stale %s (pid %s)\n' "$label" "${owner:-unknown}" >&2
  fi
  mkdir "$guard" 2>/dev/null || return 1
  state__guard_stamp "$guard" "$note"
  return 0
}

# Who holds it, since when, and on whose behalf. One place, because the take and
# the stale takeover both have to leave exactly the same thing behind.
state__guard_stamp() {
  local guard="$1" note="$2"
  printf '%s\n' "$$" >"$guard/pid"
  ralph_now >"$guard/since"
  if [ -n "$note" ]; then
    printf '%s\n' "$note" >"$guard/note"
  fi
}

state_guard_holder() {
  [ -d "$1" ] || return 1
  cat "$1/pid" 2>/dev/null
}

# Empty rather than absent when the guard carries no note: a caller formatting a
# refusal message needs a string, and "unknown" is its business, not ours.
state_guard_note() {
  [ -d "$1" ] || return 1
  cat "$1/note" 2>/dev/null
}

# Only ever drops a guard this process owns.
state_guard_release() {
  local guard="$1"
  [ -d "$guard" ] || return 0
  if [ "$(cat "$guard/pid" 2>/dev/null || echo '')" = "$$" ]; then
    rm -rf "$guard"
  fi
  return 0
}

# ── run lock ─────────────────────────────────────────────────────────────────
#
# One lock per feature, covering both loops: you grind or you drain, never both.
# It guards the *tracker*, and only the tracker. What guards the working tree is
# the second lock below — a distinction that cost this pack a live fault.

ralph_run_lock_path() {
  printf '%s/.run.lock\n' "$(ralph_feature_dir)"
}

run_lock_acquire() {
  local lock owner
  lock="$(ralph_run_lock_path)"

  if ! state_guard_take "$lock" "run lock"; then
    owner="$(state_guard_holder "$lock" || echo unknown)"
    printf 'ralph: another run already holds %s (pid %s)\n' "$lock" "$owner" >&2
    return 1
  fi

  RALPH_RUN_LOCK="$lock"
  # Released on any ordinary exit, including a graceful kill. Both locks come off
  # through the same handler on purpose — see state_locks_release.
  trap 'state_locks_release' EXIT
  trap 'state_locks_release; exit 130' INT
  trap 'state_locks_release; exit 143' TERM
  return 0
}

run_lock_release() {
  local lock="${RALPH_RUN_LOCK:-}"
  [ -n "$lock" ] || return 0
  state_guard_release "$lock"
  RALPH_RUN_LOCK=""
  return 0
}

run_lock_held_by() {
  state_guard_holder "$(ralph_run_lock_path)"
}

# Whether this process still holds the lock it took.
#
# Worth asking more than once, because the lock is the one piece of the loop's
# state a session can reach: it lives under `.scratch/<feature>/`, which the
# scope-guard drops as bookkeeping and the rollback leaves alone. A session that
# deletes it — a stray `rm -rf`, a zealous clean-up — costs nothing visible, and
# then a second run starts alongside this one.
#
# No lock recorded means there is nothing to hold, not a lock that was lost: the
# libs are drivable outside a run, and that case is not a failure.
run_lock_is_ours() {
  local lock="${RALPH_RUN_LOCK:-}"
  [ -n "$lock" ] || return 0
  [ "$(state_guard_holder "$lock" 2>/dev/null || echo '')" = "$$" ]
}

# ── working-tree lock ────────────────────────────────────────────────────────
#
# One lock per working tree, on top of the per-feature one, for a different
# reason. The run lock protects the tracker — one run per frontier, grind or
# drain. This protects the tree, and nothing else does: the scope-guard's
# snapshot, the rollback, the commit on green and HEAD are all repository-wide.
#
# Two runs on two features of one repository — an arrangement the spec allows and
# the per-feature lock happily permits — therefore destroy each other, and it
# takes no concurrency option and no dishonest session to do it. Two honest ones
# were enough ([22]): each read the other's writes as its own overflow and
# collected a failure it had not earned, each rolled the other's work back, the
# rollback's `rmdir -p` pulled a directory out from under a live session that
# then failed to write with no idea why, and a ticket restored to its pre-claim
# state broke the claim's mutual exclusion outright.
#
# Refusing to start is the answer rather than teaching the gate to tolerate it.
# Widening what counts as the loop's own bookkeeping to all of `.scratch/` would
# reopen, in the neighbouring tracker, the hole [21] just closed; and narrowing
# the rollback to the write-surface is impossible, since undoing writes made
# *outside* that surface is its entire job. Isolation — a worktree per run — is
# the real fix and it belongs to [13]. Until then the pack declines what it
# cannot do safely, exactly as it declines to start on an empty TEST_CMD.
#
# It lives in the git directory for two reasons. The run lock sits under
# `.scratch/<feature>/`, inside the tree a session writes to, and [12] showed a
# session can delete it; `.git/` is out of reach of a `git add -A`, a `git clean`
# and an `rm -rf .scratch`. And a linked worktree has its own git directory, so
# this is already per working tree rather than per repository: the day [13] gives
# each run its own worktree, several features become possible again with nothing
# here to change.
ralph_tree_lock_path() {
  local root gitdir
  root="$(ralph_project_root)"
  gitdir="$(cd "$root" 2>/dev/null && git rev-parse --git-dir 2>/dev/null)" || return 1
  [ -n "$gitdir" ] || return 1
  # Relative to the directory we asked from when the run is at the top of a
  # repository, absolute inside a linked worktree.
  case "$gitdir" in
    /*) ;;
    *) gitdir="$root/$gitdir" ;;
  esac
  printf '%s/ralph.tree.lock\n' "$gitdir"
}

tree_lock_acquire() {
  local lock owner feature
  if ! lock="$(ralph_tree_lock_path)"; then
    printf 'ralph: not a git repository — no way to tell which working tree this run would own\n' >&2
    return 1
  fi

  if ! state_guard_take "$lock" "working-tree lock" "${FEATURE:-unknown}"; then
    owner="$(state_guard_holder "$lock" 2>/dev/null || echo '')"
    feature="$(state_guard_note "$lock" 2>/dev/null || echo '')"
    printf 'ralph: another run already holds this working tree (pid %s, feature %s)\n' \
      "${owner:-unknown}" "${feature:-unknown}" >&2
    printf 'ralph: refusing to start — the tree snapshot, the rollback, the commit on green and HEAD are repository-wide, so two runs here undo and overwrite each other whatever features they grind\n' >&2
    return 1
  fi

  RALPH_TREE_LOCK="$lock"
  trap 'state_locks_release' EXIT
  trap 'state_locks_release; exit 130' INT
  trap 'state_locks_release; exit 143' TERM
  return 0
}

tree_lock_release() {
  local lock="${RALPH_TREE_LOCK:-}"
  [ -n "$lock" ] || return 0
  state_guard_release "$lock"
  RALPH_TREE_LOCK=""
  return 0
}

# Same question as run_lock_is_ours, and it has to be asked separately. `.git/`
# is out of reach of a stray `git clean`, not of a session that deletes the
# directory outright — and a tree lock that vanished means a second run can start
# here, which is the whole destruction this lock exists to prevent.
tree_lock_is_ours() {
  local lock="${RALPH_TREE_LOCK:-}"
  [ -n "$lock" ] || return 0
  [ "$(state_guard_holder "$lock" 2>/dev/null || echo '')" = "$$" ]
}

# Both locks, one handler, one trap. Bash traps do not stack: two acquires each
# installing their own EXIT trap would leave whichever ran second holding the
# only handler, and leak the other lock on exit. Each release is a no-op for a
# lock this process never took, so the shared handler is safe wherever it fires.
state_locks_release() {
  run_lock_release
  tree_lock_release
  return 0
}
