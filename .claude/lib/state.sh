# shellcheck shell=bash
# Run state: where the project is, what time it is, how a file is published,
# and the run lock that keeps two runs off one tracker.
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
# an AFK run forever. Liveness is pid-based and therefore single-machine; the
# TTL backstop belongs to the claim-liveness ticket.

state_guard_take() {
  local guard="$1" label="${2:-guard}" owner
  mkdir -p "$(dirname "$guard")"

  if mkdir "$guard" 2>/dev/null; then
    printf '%s\n' "$$" >"$guard/pid"
    ralph_now >"$guard/since"
    return 0
  fi

  owner="$(cat "$guard/pid" 2>/dev/null || echo '')"
  if [ -n "$owner" ] && kill -0 "$owner" 2>/dev/null; then
    return 1
  fi

  printf 'ralph: taking over a stale %s (pid %s)\n' "$label" "${owner:-unknown}" >&2
  rm -rf "$guard"
  mkdir "$guard" 2>/dev/null || return 1
  printf '%s\n' "$$" >"$guard/pid"
  ralph_now >"$guard/since"
  return 0
}

state_guard_holder() {
  [ -d "$1" ] || return 1
  cat "$1/pid" 2>/dev/null
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
  # Released on any ordinary exit, including a graceful kill.
  trap 'run_lock_release' EXIT
  trap 'run_lock_release; exit 130' INT
  trap 'run_lock_release; exit 143' TERM
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
