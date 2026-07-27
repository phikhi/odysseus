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
#
# What the loop reads back, for the failure policy and the audit receipt:
#   RALPH_GATE_VERDICTS     e.g. "tests=green typecheck=red scope=green"
#   RALPH_GATE_FAILED       the red branch names
#   RALPH_GATE_SCOPE_CLASS  internal | contract, when the scope-guard is red

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

# ── the diff an iteration is judged on ───────────────────────────────────────

# The commit the iteration starts from. Everything the session leaves behind is
# measured against it — including what it committed itself, which a plain
# working-tree diff would not see at all.
gate_snapshot() {
  git rev-parse HEAD 2>/dev/null || true
}

gate__changed_files() {
  local base="$1"
  {
    if [ -n "$base" ]; then
      git diff --name-only "$base" -- 2>/dev/null
    else
      git diff --name-only -- 2>/dev/null
    fi
    # Tracked changes only, above. A brand-new file is the common way to leave
    # the write-surface, so untracked paths count too.
    git ls-files --others --exclude-standard --full-name 2>/dev/null
  } | LC_ALL=C sort -u | gate__drop_bookkeeping
}

# The loop's own writes are not the session's doing: claiming a ticket rewrites
# it, and the journal, the run lock and the session stream all live in the
# feature directory. Paths are repo-root relative, which is the project root —
# a pack installed below the repo root is out of scope for now.
gate__drop_bookkeeping() {
  local prefix file
  prefix=".scratch/${FEATURE}/"
  while IFS= read -r file; do
    case "$file" in
      '') continue ;;
      "$prefix"*) continue ;;
    esac
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

# Runs as a gate branch: findings on stdout, the classification in a sidecar
# file because a branch runs in its own process and cannot set a variable here.
#
# A ticket with no declared write-surface is the fail-safe case: an unknown
# surface can never be assumed to contain anything.
gate__scope_guard() {
  local ticket="$1" base="$2" classfile="$3"
  local surface file owner class='' rc=0

  surface="$(gate_write_surface "$ticket")"

  while IFS= read -r file; do
    [ -n "$file" ] || continue
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
$(gate__changed_files "$base")
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
  local dir names='' pids='' name rc=0 brc

  dir="$(mktemp -d "${TMPDIR:-/tmp}/ralph-gate.XXXXXX")" || return 1
  RALPH_GATE_VERDICTS=""
  RALPH_GATE_FAILED=""
  RALPH_GATE_SCOPE_CLASS=""

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

  gate__start "$dir" scope gate__scope_guard "$ticket" "$base" "$dir/scope.class"
  names="$names scope"
  pids="$pids $!"

  for brc in $pids; do
    wait "$brc" 2>/dev/null || true
  done

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
  rm -rf "$dir"
  return "$rc"
}
