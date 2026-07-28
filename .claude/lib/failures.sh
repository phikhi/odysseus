# shellcheck shell=bash
# Typed failures, rollback, and the commit that makes a green iteration durable.
#
# An iteration that did not deliver is not one thing, and treating it as one is
# how an AFK run wastes a night. Four kinds, four answers:
#
#   too-big    the session ran out of context before finishing. The slice, not
#              the attempt, is what failed — so the loop cuts it into smaller
#              tickets itself and puts those on the frontier.
#   contract   the session wrote inside another ticket's declared write-surface.
#              Two tickets were drawn over one file; retrying cannot settle it,
#              so it goes straight to the human sink without burning a retry.
#   gate-red   tests, type check or a stray write. Retryable: up to RETRY_N
#              fresh sessions, then the human sink with `Failures:` to show it.
#   crash      the session died. Same policy as a red gate.
#
# The budget pause is the fifth kind and it is not here yet: a non-zero exit has
# to be tested "budget?" before it counts as a failure at all, which is the
# budget ticket's classifier. It plugs into failures_classify.
#
# Every path through here rolls the repository back and every escalation leaves
# a reason behind, because the two failures this pack cannot afford are a dirty
# tree the next session inherits as its own, and a ticket in the human sink with
# nothing saying why.

failures__log() {
  printf 'ralph: %s\n' "$*"
}

# ── what kind of failure this was ────────────────────────────────────────────

# The loop knows three things: whether the session was cut short for context,
# whether the gate went red, and how the scope-guard classified an overflow.
# The budget classifier goes in front of the last case.
failures_classify() {
  local outcome="$1" scope_class="${2:-}"
  case "$outcome" in
    over-soft-limit)
      printf 'too-big\n'
      ;;
    gate-red)
      if [ "$scope_class" = contract ]; then
        printf 'contract\n'
      else
        printf 'gate-red\n'
      fi
      ;;
    *)
      printf 'crash\n'
      ;;
  esac
}

# ── the policy ───────────────────────────────────────────────────────────────

# One failed iteration, from classification to a ticket somebody can act on.
# Called with the two pre-spawn snapshots — the commit HEAD pointed at and the
# tree of the working directory — plus the post-session tree when the gate
# already computed one.
failures_handle() {
  local ticket="$1" outcome="$2" pre="$3" base="$4" tree="${5:-}"
  local class count="" reason=""

  class="$(failures_classify "$outcome" "${RALPH_GATE_SCOPE_CLASS:-}")"
  [ -n "$tree" ] || tree="$(gate_tree_snapshot)" || tree=""

  case "$class" in
    contract)
      # Not a bad attempt: a scoping conflict. Retrying it would only break the
      # disjunction the parallel scheduler relies on, so it does not consume a
      # retry — the discovery has to redraw the two surfaces.
      reason=decision
      ;;
    too-big)
      # Decided after the re-slice: only a split that cannot preserve the
      # acceptance criteria needs a human.
      ;;
    *)
      count="$(tracker_bump_failures "$ticket")" || count=""
      if [ -z "$count" ] || [ "$count" -gt "${RETRY_N:-2}" ]; then
        reason=failed-impl
      fi
      ;;
  esac

  # Before the tree is put back, not after: the branch is the only copy of what
  # the session actually did once the rollback has run. Never fatal — a git that
  # refuses to write a forensic branch (a ref named `failed` already in the way,
  # a lock a crashed git left behind) must not take the run down with it.
  if [ -n "$reason" ]; then
    failures_preserve_attempt "$ticket" "$pre" "$tree" || true
  fi

  failures_rollback "$pre" "$base" "$tree" || true

  if [ "$class" = too-big ]; then
    if failures_reslice "$ticket"; then
      return 0
    fi
    reason=too-big
    failures_preserve_attempt "$ticket" "$pre" "$tree" || true
  fi

  if [ -n "$reason" ]; then
    tracker_mark_escalated "$ticket" "$reason"
    failures__log "$ticket: escalated to the human sink ($reason)"
  else
    tracker_unclaim "$ticket"
    failures__log "$ticket: $class -> fresh retry ($count of ${RETRY_N:-2})"
  fi
  return 0
}

# ── rollback ─────────────────────────────────────────────────────────────────

# Put the repository back where the session found it, and no further.
#
# `git reset --hard` plus `git clean -fd` is the obvious rollback and it is the
# wrong one: a run started on a tree that already had uncommitted work would
# take the human's work down with the failed attempt, and the clean would delete
# files nobody in this run ever touched. So the rollback is exactly as wide as
# the session's own diff — paths it added are removed, everything else is
# restored from the pre-session snapshot — and a commit the session made is
# undone by moving HEAD back, leaving the worktree to that same restore.
#
# The tracker is left alone. The claim, the journal and the session stream all
# live there, and restoring them would rewrite the only authority on state this
# system has — including, on a session that committed mid-claim, back to a state
# that was never true.
failures_rollback() {
  local pre="$1" base="$2" tree="${3:-}"
  local head idx status path paths='' undone=0

  if [ -z "$base" ]; then
    failures__log "no pre-session snapshot — refusing to guess what to roll back"
    return 1
  fi
  [ -n "$tree" ] || tree="$(gate_tree_snapshot)" || tree=""
  if [ -z "$tree" ]; then
    failures__log "cannot read the working tree — nothing was rolled back"
    return 1
  fi

  head="$(git rev-parse HEAD 2>/dev/null)" || head=""
  if [ -n "$pre" ] && [ -n "$head" ] && [ "$head" != "$pre" ]; then
    if git reset -q --mixed "$pre" 2>/dev/null; then
      failures__log "rolled back the commit the session made"
    else
      failures__log "could not move HEAD back to $pre"
    fi
  fi

  idx="$(mktemp "${TMPDIR:-/tmp}/ralph-rollback.XXXXXX")" || return 1
  rm -f "$idx"
  if ! GIT_INDEX_FILE="$idx" git read-tree "$base" 2>/dev/null; then
    rm -f "$idx"
    failures__log "cannot read the pre-session snapshot — nothing was rolled back"
    return 1
  fi

  while IFS="$(printf '\t')" read -r status path; do
    [ -n "$path" ] || continue
    if gate_is_bookkeeping "$path"; then continue; fi
    paths="$paths $path"
    undone=$((undone + 1))
    case "$status" in
      A)
        rm -f "$path"
        # Stops at the first directory that is not empty, so a directory the
        # session did not create survives.
        rmdir -p "$(dirname "$path")" 2>/dev/null || true
        ;;
      *)
        GIT_INDEX_FILE="$idx" git checkout-index -f -- "$path" 2>/dev/null ||
          failures__log "could not restore $path"
        ;;
    esac
  done <<ROLLBACK
$(git diff-tree -r --name-status "$base" "$tree" 2>/dev/null)
ROLLBACK

  rm -f "$idx"

  # What the session staged is not work in progress either. Unstaging is scoped
  # to the same paths, so an index a human left half-prepared elsewhere stands.
  if [ -n "$paths" ]; then
    # shellcheck disable=SC2086
    git reset -q -- $paths 2>/dev/null || true
    failures__log "rolled back $undone path(s) the session touched"
  fi
  return 0
}

# ── keeping the attempt ──────────────────────────────────────────────────────

# `failed/<ticket>`: what the session produced, kept as a commit before the
# rollback undoes it. The human the ticket lands on gets to read the attempt
# instead of a description of it.
#
# The tracker is stripped out of the tree first — the branch is a forensic
# artefact, and the run lock, the journal and a session stream that can run to
# tens of megabytes have no business in the target project's history.
failures_preserve_attempt() {
  local ticket="$1" pre="$2" tree="$3"
  local idx clean commit branch="failed/$1"

  if [ -z "$tree" ]; then
    failures__log "$ticket: nothing readable to keep on $branch"
    return 1
  fi

  idx="$(mktemp "${TMPDIR:-/tmp}/ralph-failed.XXXXXX")" || return 1
  rm -f "$idx"
  if ! GIT_INDEX_FILE="$idx" git read-tree "$tree" 2>/dev/null; then
    rm -f "$idx"
    failures__log "$ticket: could not read the attempt — $branch not written"
    return 1
  fi
  # -f because the tracker on disk has moved on since this tree was taken — the
  # retry counter was just written. Nothing is at risk: --cached only ever edits
  # the throwaway index.
  GIT_INDEX_FILE="$idx" git rm -r -f -q --cached --ignore-unmatch -- \
    ".scratch/${FEATURE}" >/dev/null 2>&1 || true
  clean="$(GIT_INDEX_FILE="$idx" git write-tree 2>/dev/null)" || clean=""
  rm -f "$idx"
  [ -n "$clean" ] || {
    failures__log "$ticket: could not write the attempt — $branch not written"
    return 1
  }

  if [ -n "$pre" ]; then
    commit="$(git commit-tree "$clean" -p "$pre" \
      -m "ralph: failed attempt on $ticket" 2>/dev/null)" || commit=""
  else
    commit="$(git commit-tree "$clean" \
      -m "ralph: failed attempt on $ticket" 2>/dev/null)" || commit=""
  fi
  [ -n "$commit" ] || {
    failures__log "$ticket: could not commit the attempt — $branch not written"
    return 1
  }

  if git update-ref "refs/heads/$branch" "$commit" 2>/dev/null; then
    failures__log "$ticket: the attempt is kept on branch $branch"
  else
    failures__log "$ticket: could not write branch $branch"
    return 1
  fi
  return 0
}

# ── making a green iteration durable ─────────────────────────────────────────

# The commit that turns a green gate into something a rollback cannot take away.
#
# Only the paths the scope-guard just approved go in, taken from the tree it
# judged: a build artefact the test suite dropped after that snapshot is not the
# iteration's work, and the tracker never belongs in the target project's
# history at all. Plumbing rather than `git commit`, so the target project's
# hooks, signing config and commit template have no say in the loop's own
# bookkeeping — and so a path the session deleted is recorded as deleted.
failures_make_durable() {
  local ticket="$1" base="$2" tree="${3:-}"
  local changed idx head newtree commit

  if [ -z "$base" ]; then
    failures__log "$ticket: no pre-session snapshot — nothing made durable"
    return 1
  fi
  changed="$(gate__changed_files "$base" "$tree")" || changed=""
  if [ -z "$changed" ]; then
    return 0
  fi

  head="$(git rev-parse HEAD 2>/dev/null)" || head=""
  idx="$(mktemp "${TMPDIR:-/tmp}/ralph-durable.XXXXXX")" || return 1
  rm -f "$idx"
  if [ -n "$head" ]; then
    GIT_INDEX_FILE="$idx" git read-tree "$head" >/dev/null 2>&1 || true
  fi
  # shellcheck disable=SC2086
  GIT_INDEX_FILE="$idx" git add -A -- $changed >/dev/null 2>&1 || true
  newtree="$(GIT_INDEX_FILE="$idx" git write-tree 2>/dev/null)" || newtree=""
  rm -f "$idx"

  if [ -z "$newtree" ]; then
    failures__log "$ticket: could not stage the iteration — it is not committed"
    return 1
  fi
  # A session that committed its own work leaves nothing to add.
  if [ -n "$head" ] && [ "$newtree" = "$(git rev-parse "$head^{tree}" 2>/dev/null)" ]; then
    return 0
  fi

  if [ -n "$head" ]; then
    commit="$(git commit-tree "$newtree" -p "$head" \
      -m "$ticket: iteration delivered (gate green)" 2>/dev/null)" || commit=""
  else
    commit="$(git commit-tree "$newtree" \
      -m "$ticket: iteration delivered (gate green)" 2>/dev/null)" || commit=""
  fi
  if [ -z "$commit" ] || ! git update-ref -m "ralph: $ticket" HEAD "$commit" 2>/dev/null; then
    failures__log "$ticket: could not commit the iteration — it is not durable"
    return 1
  fi

  # The real index still describes the state before the commit, which would show
  # up as a staged deletion. Same paths, so nothing else staged is disturbed.
  # shellcheck disable=SC2086
  git add -A -- $changed >/dev/null 2>&1 || true
  failures__log "$ticket: committed $(printf '%s\n' "$changed" | awk 'END { print NR }') path(s)"
  return 0
}

# ── re-slicing a ticket that was too big ─────────────────────────────────────

# A session that ran out of context did not fail at implementing; the slice
# failed at being a slice. The loop can fix that itself: one fresh session
# produces a split, the loop checks the split preserves the contract, and the
# smaller tickets go on the frontier.
#
# The plan is written to a file outside the repository and the tickets are
# created by the loop. Same rule as marking: a session that writes the tracker
# can freeze a state that was never true, and here it would also let a planning
# session grant itself a write-surface nobody checked.
#
# Returns 0 when the ticket was re-sliced, non-zero when it needs a human.
failures_reslice() {
  local ticket="$1"
  local plan out base head prev_soft rc=0
  local headers lines start end header slug title body surface children='' child
  local total incomplete=''

  surface="$(gate_write_surface "$ticket")"
  plan="$(mktemp "${TMPDIR:-/tmp}/ralph-reslice.XXXXXX")" || return 1
  out="$plan.stream"
  : >"$plan"

  base="$(gate_tree_snapshot)" || base=""
  head="$(git rev-parse HEAD 2>/dev/null)" || head=""
  prev_soft="${RALPH_SOFT_LIMIT_HIT:-0}"

  failures__reslice_prompt "$ticket" "$plan" >"$plan.prompt"
  loop_spawn "$plan.prompt" "$out" || rc=$?
  if [ "${RALPH_SOFT_LIMIT_HIT:-0}" = 1 ]; then
    rc=1
    failures__log "$ticket: the re-slice session crossed the soft limit too"
  fi
  RALPH_SOFT_LIMIT_HIT="$prev_soft"

  # A planning session has no write-surface, so nothing it left in the
  # repository is wanted — including the plan, if it ignored the instructions.
  failures_rollback "$head" "$base" '' >/dev/null 2>&1 || true

  if [ "$rc" != 0 ] || [ ! -s "$plan" ]; then
    failures__log "$ticket: no re-slice plan came back"
    rm -f "$plan" "$plan.prompt" "$out" "$out.tokens"
    return 1
  fi

  headers="$(grep -n '^--- ticket:' "$plan" || true)"
  total="$(printf '%s' "$headers" | grep -c . || true)"
  if [ "${total:-0}" -lt 2 ]; then
    failures__log "$ticket: the plan does not split anything ($total ticket(s))"
    rm -f "$plan" "$plan.prompt" "$out" "$out.tokens"
    return 1
  fi

  lines="$(printf '%s\n' "$headers" | cut -d: -f1)"
  end="$(awk 'END { print NR }' "$plan")"

  # Validated whole before a single ticket is created: half a split is worse
  # than none, and nothing here can be undone by a rollback — the tracker is
  # deliberately outside its reach.
  if ! failures__plan_is_sound "$ticket" "$plan" "$surface" "$lines" "$end"; then
    rm -f "$plan" "$plan.prompt" "$out" "$out.tokens"
    return 1
  fi

  set -- $lines
  while [ "$#" -gt 0 ]; do
    start="$1"
    shift
    body="$(failures__plan_body "$plan" "$start" "${1:-}" "$end")"
    header="$(sed -n "${start}p" "$plan")"
    slug="$(failures__plan_slug "$header")"
    title="$(failures__plan_title "$header")"
    child="$(printf '%s\n' "$body" | tracker_open_ticket "$slug" "$title")" || child=""
    if [ -z "$child" ]; then
      failures__log "$ticket: could not create the ticket for '$slug'"
      incomplete=1
      continue
    fi
    printf 'Re-sliced out of %s: the session ran out of context on the whole slice.\n' \
      "$ticket" | tracker_append_note "$child" || true
    children="$children $child"
  done
  rm -f "$plan" "$plan.prompt" "$out" "$out.tokens"

  children="${children# }"
  if [ -z "$children" ]; then
    failures__log "$ticket: the re-slice created nothing"
    return 1
  fi

  # A split missing one of its pieces has lost the acceptance criteria that piece
  # carried, and nothing can put them back — the tracker is outside the
  # rollback's reach on purpose. So the parent keeps its own criteria and goes to
  # a human, who can see from the note what did get created.
  if [ -n "$incomplete" ]; then
    printf 'Re-slice incomplete: only %s could be created out of the planned split. This ticket keeps its acceptance criteria.\n' \
      "$children" | tracker_append_note "$ticket" || true
    failures__log "$ticket: the split is incomplete — leaving it to a human"
    return 1
  fi

  # The parent waits for its own children and comes back to the frontier once
  # they are resolved. Marking it resolved here would be a green nobody earned,
  # and would unblock whatever depends on it before the work exists; dropping it
  # would block those dependents forever, silently.
  tracker_block_on "$ticket" "$children" || true
  tracker_mark_ready "$ticket"
  printf 'Too big for one session. Re-sliced into: %s. This ticket stays blocked on them and is re-attempted, and gated, once they are resolved.\n' \
    "$(printf '%s' "$children" | tr ' ' ',' | sed 's/,/, /g')" |
    tracker_append_note "$ticket" || true
  failures__log "$ticket: too big -> re-sliced into $children"
  return 0
}

# Whether the split may be created: two tickets or more, each one nameable, each
# one carrying acceptance criteria, and none of them claiming a write-surface
# the parent never had. A split that widens the contract is a different ticket,
# not a smaller one — and the write-surface is what the scope-guard judges every
# session on, so a plan that invents one has to be refused rather than fixed.
failures__plan_is_sound() {
  local ticket="$1" plan="$2" surface="$3" lines="$4" last="$5"
  local start header slug title body pattern child_surface

  set -- $lines
  while [ "$#" -gt 0 ]; do
    start="$1"
    shift
    header="$(sed -n "${start}p" "$plan")"
    body="$(failures__plan_body "$plan" "$start" "${1:-}" "$last")"
    slug="$(failures__plan_slug "$header")"
    title="$(failures__plan_title "$header")"

    if [ -z "$slug" ] || [ -z "$title" ]; then
      failures__log "$ticket: a planned ticket has no slug or no title"
      return 1
    fi
    case "$body" in
      *'- [ ]'*) ;;
      *)
        failures__log "$ticket: planned ticket '$slug' carries no acceptance criteria"
        return 1
        ;;
    esac

    child_surface="$(printf '%s\n' "$body" |
      sed -n 's/^\*\*Write-surface:\*\*[[:space:]]*//p; s/^Write-surface:[[:space:]]*//p' |
      head -1 | tr -d '`,' | awk '{ $1 = $1; print }')"
    if [ -z "$child_surface" ]; then
      failures__log "$ticket: planned ticket '$slug' declares no write-surface"
      return 1
    fi
    for pattern in $child_surface; do
      if ! gate_in_surface "${pattern%/}" "$surface"; then
        failures__log "$ticket: planned ticket '$slug' would write $pattern, outside the write-surface being split"
        return 1
      fi
    done
  done
  return 0
}

# One block's body: everything between its header line and the next one. Read by
# the check and by the creation, so a block cannot be validated as one thing and
# created as another.
failures__plan_body() {
  local plan="$1" start="$2" next="${3:-}" last="$4"
  if [ -n "$next" ]; then
    sed -n "$((start + 1)),$((next - 1))p" "$plan"
  else
    sed -n "$((start + 1)),${last}p" "$plan"
  fi
}

# `--- ticket: <slug> | <title> ---`, read tolerantly. The slug names a file, so
# it is reduced to what a file name may contain rather than trusted.
failures__plan_slug() {
  printf '%s' "$1" |
    sed -n 's/^--- ticket:[[:space:]]*\([^|]*\)|.*/\1/p' |
    tr 'A-Z' 'a-z' | tr -c 'a-z0-9-' ' ' | awk '{ $1 = $1; print $1 }'
}

failures__plan_title() {
  printf '%s' "$1" |
    sed -n 's/^--- ticket:[^|]*|[[:space:]]*\(.*\)$/\1/p' |
    sed 's/[[:space:]]*-*[[:space:]]*$//'
}

# Everything the planning session gets. It inherits no conversation either, and
# it is told where the plan goes and that the repository is not it.
failures__reslice_prompt() {
  local ticket="$1" plan="$2"
  cat <<PROMPT
You are re-slicing one ticket of an autonomous delivery loop. A session just ran
out of context trying to deliver it in one go, which means the slice is too big.
You have exactly one task: split it into smaller tickets, and stop.

## The ticket that was too big: $ticket

$(tracker_read_ticket "$ticket")

## Where the rest of the context lives

- Domain language and constraints: CONTEXT.md
- Architecture decisions already taken: docs/adr/
- Lessons from earlier iterations: LEARNINGS.md
- Tracker conventions: docs/agents/

## What to write

Write the plan to $plan, and write nothing anywhere else. Do not touch the
repository and do not touch the tracker: the loop creates the tickets, and
anything you leave in the working tree is discarded.

One block per new ticket, in this exact shape:

--- ticket: <slug> | <title> ---
**What to build:** what this ticket delivers, in ${LANG_ARTIFACT:-en}.

**Blocked by:** None

**Write-surface:** \`path/one\`, \`path/two\`

**Status:** ready-for-agent

- [ ] one acceptance criterion
- [ ] another

## Rules

- Two to four tickets. Each one has to be deliverable by a single session that
  starts from nothing.
- Every acceptance criterion of the original must be carried by exactly one of
  them. The split may not drop, weaken or merge any of them.
- Every write-surface must be inside the original's declared write-surface. A
  plan that widens it is refused whole.
- The tickets are ground in the order you write them, so write them in
  dependency order and leave \`Blocked by:\` as None.
- If no split preserves the acceptance criteria, write nothing to the file and
  say why on stdout. A human will pick it up.
PROMPT
}
