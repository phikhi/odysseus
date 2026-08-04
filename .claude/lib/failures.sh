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
#   timeout    the session hung, or ran past the wall clock ([23]). Retried like
#              a red gate — a fresh session is exactly what a hung one needs —
#              and never re-sliced: nothing here measured the slice. Escalated
#              under a name of its own, because no gate ever judged it.
#
# A session that wrote the tracker is reported apart (`tracker-write`) and
# handled as a red gate: it is the same kind of failure — something in the
# repository is not what the loop asked for — and a fresh session can still
# deliver the ticket.
#
# The budget pause is the fifth kind and it is not here yet: a non-zero exit has
# to be tested "budget?" before it counts as a failure at all, which is the
# budget ticket's classifier. It plugs into failures_classify.
#
# Every path through here rolls the repository back and every escalation leaves
# a reason behind, because the two failures this pack cannot afford are a dirty
# tree the next session inherits as its own, and a ticket in the human sink with
# nothing saying why.
#
# What the loop reads back:
#   RALPH_ROLLBACK_FAILED   1 when a rollback refused to act — no baseline, or a
#                           working tree it could not read. The iteration is over
#                           either way; the run is not, and the loop stops on it
#                           rather than let the next iteration adopt whatever is
#                           lying in the tree as the state it started from ([34]).

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
    # Deliberately not too-big. The two look alike from outside — a session the
    # loop cut short — and they say opposite things: crossing the soft limit is
    # evidence about the size of the slice, hanging is evidence about nothing.
    # Re-slicing on a timeout would carve a ticket up on a measurement nobody
    # took, and spend a second session doing it.
    session-stalled | session-timeout)
      printf 'timeout\n'
      ;;
    gate-red | tracker-write)
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

  # Cleared here and raised only by failures_rollback, so it accumulates across the
  # two rollbacks one iteration can run — the policy's own, and the one a re-slice
  # does after its planning session — instead of the second quietly clearing the
  # first. The loop reads it once, at the end of the iteration ([34]).
  RALPH_ROLLBACK_FAILED=0

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
        # Routed apart at the ceiling, for the reason [26] had to learn about
        # `Failures:`: a name that promises something has to hold it. Nothing
        # judged a session that hung — the gate never ran — so `failed-impl`
        # would send a human to read a verdict that was never returned. The
        # `failed/<ticket>` branch is written either way, and on this path it is
        # the only thing there is to read.
        [ "$class" != timeout ] || reason=session-timeout
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

# A ticket whose claim nobody can prove alive, and what the tracker owes it.
#
# Called with the ticket, the kind of owner the claim named (`claim_owner_kind`,
# lib/claim.sh) and the record itself, for the note. It gets the tracker half of
# the crash policy and not the git half: there is nothing to roll back to — the
# pre-spawn snapshots were shell variables in a process that no longer exists, and
# whatever that session left in the working tree is still there. See [12] for what
# that means for the next run.
#
# Whether it costs a retry depends on who held the claim, and only on that:
#
#   run       a run of this pack whose pid is gone (or whose claim outlived the
#             TTL, a recycled pid). A crash nobody was alive to classify: the run
#             that would have called failures_handle is the run that died. Counted
#             — and that is a trade. A hard kill (SIGKILL, power cut, OOM) burns a
#             retry on a ticket that may be perfectly fine, but the alternative is
#             worse and this pack has met it: a ticket whose session reliably kills
#             the run gets reclaimed, re-ground and killed again every night, for
#             ever, with nothing anywhere saying so.
#   anything  an owner this pack decided not to ping — an assignee, a human, another
#   else      tool — or a record it cannot read at all. Not counted. `claim.sh`
#             writes that stealing a human's ticket would be worse than waiting out
#             the backstop, and then the backstop falls and the ticket is taken
#             anyway: fail-open is deliberate, but billing an implementation failure
#             for it is not. Probed on 29/07/2026 with `owner=alice`: three runs,
#             three green deliveries, `Failures: 3`, escalated `failed-impl` on the
#             third. Nothing had ever been judged.
#
# It is also why the ceiling here does not escalate as `failed-impl`: nothing in
# this function has judged an attempt, and a human sent to read a `failed/<ticket>`
# branch that was never written has been misrouted. `decision` is the honest
# routing — somebody has to decide whether the ticket kills its run or the host was
# the problem — and the note says which. Counting is the bound, not the diagnosis.
#
# A graceful stop (TERM/INT) does not come through here at all: the loop finishes
# its iteration and marks the ticket ([25]).
#
# The disposition goes to stdout — `retry`, `returned` or `escalated` — and nothing
# else does. This is the one decision here that does not announce itself: its
# caller has to journal the reclaim anyway, and failures__log writes to stdout, so
# a line printed here would come back inside the disposition.
failures_after_dead_owner() {
  local ticket="$1" kind="${2:-foreign}" record="${3:-}" count=""

  # Defaults to the free path when the caller says nothing: a forgetful caller then
  # under-bounds the re-grinding of a toxic ticket, which is visible in the tracker,
  # rather than charging retries to owners it never pinged, which is not.
  if [ "$kind" != run ]; then
    tracker_unclaim "$ticket"
    printf 'The claim on this ticket was not taken by a run of this pack (%s), so nothing here could ping it. It outlived CLAIM_TTL, and this pack fails open on a claim it cannot prove alive: the ticket went back to the frontier, and the loop may be grinding it now. No retry was charged for it — no session was ever judged on this ticket, and a claim that was waited out is not a failed attempt.\n' \
      "${record:-no readable claim record}" | tracker_append_note "$ticket" || true
    printf 'returned\n'
    return 0
  fi

  count="$(tracker_bump_failures "$ticket")" || count=""
  if [ -z "$count" ] || [ "$count" -gt "${RETRY_N:-2}" ]; then
    tracker_mark_escalated "$ticket" decision
    printf 'The retry budget of this ticket (%s of %s) ran out on a reclaim, not on a verdict: the run holding it (%s) died before anything judged its session, so there is no `failed/%s` branch to read and no red gate to look at. Earlier attempts may have been judged — `Failures:` counts both causes and `run.log` tells them apart, a `reclaimed-*` line against a gate outcome. Somebody has to decide whether this ticket kills the run that takes it or the host was the problem.\n' \
      "${count:-unknown}" "${RETRY_N:-2}" "${record:-no readable claim record}" "$ticket" |
      tracker_append_note "$ticket" || true
    printf 'escalated\n'
    return 0
  fi

  tracker_unclaim "$ticket"
  printf 'retry\n'
  return 0
}

# ── the tracker a session must not write ─────────────────────────────────────
#
# Both prompts forbid a session from writing the tracker, and for a while that was
# the whole of the enforcement. Nothing else could see it: the scope-guard drops
# `.scratch/<feature>/` as the loop's own bookkeeping, and the rollback leaves it
# alone on purpose. Two shapes of write came out of that, and they need different
# answers:
#
#   a ticket created   it joined the frontier carrying whatever write-surface the
#                      session had granted itself, and a run would then grind
#                      work nobody asked for inside a surface nobody checked.
#                      Quarantined — a created ticket cannot be un-created, and
#                      only a human may decide it was legitimate.
#   a ticket edited    the scope-guard reads the write-surface off the disk at
#                      gate time, which is *after* the session. Rewrite that one
#                      line to `*` and every write passes. Restored from the
#                      pre-session snapshot, before the gate reads anything.
#
# So: two snapshots around the spawn, a set of ids for the first and a tree
# object of the tickets for the second. The window is clean either way — between
# the snapshots and the session returning, the loop writes nothing under
# `issues/`: the liveness sweep and the claim came before, and the marking, the
# retry counter and the journal all come after.

# The ids the tracker holds right now, space-delimited and space-fenced so that a
# `case` can ask whether one is in it.
failures_tracker_snapshot() {
  printf ' %s' "$(tracker_ids | tr '\n' ' ')"
}

# Ids that were not there before. Not "tickets the loop created": the loop's own
# creations happen after this check, on purpose.
failures__strays() {
  local seen="$1 " id
  for id in $(tracker_ids); do
    case "$seen" in
      *" $id "*) continue ;;
    esac
    printf '%s\n' "$id"
  done
  return 0
}

# Anything the session added to the tracker goes to the human sink rather than to
# the frontier: it has been through none of the checks a ticket owes the loop —
# no write-surface validated, no acceptance criteria, no discovery. Returns
# non-zero when there was something to quarantine, so a caller that was reading
# the session's output can stop reading it.
failures_quarantine_strays() {
  local ticket="$1" seen="$2" strays stray final renamed_to kept='' renamed=''
  strays="$(failures__strays "$seen")"
  [ -n "$strays" ] || return 0

  # Renumbered before it is escalated, and that ordering is the whole of [27]:
  # what a session adds may carry a number another ticket already has — a renamed
  # ticket file is a deletion restored plus an addition kept, two correct
  # decisions whose composition leaves one `NN` on two files. From that moment a
  # bare number resolves to nothing, and every ticket holding `Blocked by: NN`
  # leaves the frontier permanently, whatever this iteration did. The addition is
  # what moves, never the ticket that was already there: the pre-existing id is
  # the one other tickets point at.
  while IFS= read -r stray; do
    [ -n "$stray" ] || continue
    final="$stray"
    # A refusal is said, never swallowed. Rendering the unchanged id when the
    # renumber could not run would hand back exactly the state being repaired,
    # in silence — a fix whose failure mode is the defect it fixes.
    if ! renamed_to="$(tracker_renumber "$stray")" || [ -z "$renamed_to" ]; then
      failures__log "$ticket: could not give $stray a number of its own — if another ticket already carries it, no bare number will resolve until a human renames one"
    else
      final="$renamed_to"
    fi
    if [ "$final" != "$stray" ]; then
      renamed="$renamed $stray -> $final"
      printf 'This ticket reached the tracker as `%s`, written by the %s session, and carried a number another ticket already had. It was renumbered to `%s` rather than deleted or left in place: nothing a session wrote is destroyed, and a duplicate number takes every ticket that points at it out of the frontier for good. The body below is exactly as the session wrote it, heading included.\n' \
        "$stray" "$ticket" "$final" | tracker_append_note "$final" || true
    fi
    tracker_mark_escalated "$final" decision || true
    kept="$kept $final"
  done <<STRAYS
$strays
STRAYS

  printf 'The %s session wrote these tickets into the tracker itself: %s. Nothing validated their write-surface or their acceptance criteria, so they are waiting for a human instead of sitting on the frontier.%s\n' \
    "$ticket" "$(failures__join "$kept")" \
    "$(if [ -n "$renamed" ]; then
      printf ' Renumbered on the way in, to keep a bare number resolvable:%s.' "$renamed"
    fi)" |
    tracker_append_note "$ticket" || true
  failures__log "$ticket: the session wrote the tracker itself — quarantined${kept}"
  [ -z "$renamed" ] ||
    failures__log "$ticket: a ticket the session added took a number another ticket already had — renumbered${renamed}"
  return 1
}

failures__join() {
  printf '%s' "$1" | tr -s ' ' '\n' | sed '/^$/d' | tr '\n' ' ' | sed 's/ *$//; s/ /, /g'
}

# Where the tickets live, relative to the repository root. Same assumption
# gate_is_bookkeeping makes: the project root is the repository root, and a pack
# installed below it is out of scope for now.
failures__issues_path() {
  printf '.scratch/%s/issues\n' "${FEATURE:?ralph: FEATURE is not set}"
}

# The tickets as a git tree object. Taken twice, around the spawn: two identical
# hashes is the whole of the normal case, and it costs one plumbing call.
failures_tracker_tree() {
  gate_tree_snapshot "$(failures__issues_path)"
}

# Undo what the session wrote inside the tracker, and say that it did.
#
# Called before the gate, and that ordering is the guarantee: the write-surface
# the scope-guard is about to judge against is a field in a file the session
# could have just rewritten, so restoring first is what makes the guard measure
# the contract as it stood at spawn time. Restoring the whole directory rather
# than the one ticket also covers the variant where a session marks somebody
# *else*'s ticket resolved, which would take it out of the frontier for good.
#
# Non-zero means the session edited the tracker, or that nothing can vouch that
# it did not. The loop reads that as an outcome of its own: a restored edit still
# costs the attempt, because a session left free to try again would be starting
# from a contract it partly authored. A guard that cannot see does not pass.
failures_protect_tracker() {
  local ticket="$1" before="$2"
  local dir after idx status path restored=0

  if [ -z "$before" ]; then
    failures__log "$ticket: no pre-session tracker snapshot — the tracker cannot be vouched for"
    return 1
  fi
  after="$(failures_tracker_tree)" || after=""
  if [ -z "$after" ]; then
    failures__log "$ticket: cannot read the tracker — refusing to pass it"
    return 1
  fi
  [ "$after" != "$before" ] || return 0

  dir="$(failures__issues_path)"
  idx="$(mktemp "${TMPDIR:-/tmp}/ralph-tracker.XXXXXX")" || return 1
  rm -f "$idx"
  if ! GIT_INDEX_FILE="$idx" git read-tree "$before" 2>/dev/null; then
    rm -f "$idx"
    failures__log "$ticket: cannot read the pre-session tracker — nothing was restored"
    return 1
  fi

  # The pathspec is redundant with a snapshot already scoped to the tickets, and
  # it stays: this loop overwrites files, so it may never be one bad snapshot
  # away from restoring something outside the tracker.
  while IFS="$(printf '\t')" read -r status path; do
    [ -n "$path" ] || continue
    case "$status" in
      A)
        # Left where it is: a created ticket belongs to the quarantine, which
        # hands it to a human. Deleting it here would destroy the only copy of
        # what it asked for.
        ;;
      *)
        GIT_INDEX_FILE="$idx" git checkout-index -f -- "$path" 2>/dev/null ||
          failures__log "$ticket: could not restore $path"
        restored=$((restored + 1))
        ;;
    esac
  done <<TRACKER
$(git diff-tree -r --name-status "$before" "$after" -- "$dir" 2>/dev/null)
TRACKER

  rm -f "$idx"
  # Staged is not work in progress either, and the tracker has no business in the
  # target project's index. Scoped to the tickets, so nothing staged elsewhere
  # moves; a human who had staged a tracker edit before the run loses that much.
  git reset -q -- "$dir" 2>/dev/null || true

  # Additions only: that is the quarantine's business and not a failure of its own.
  [ "$restored" -gt 0 ] || return 0

  printf 'The %s session edited the tracker itself (%s ticket file(s)). The edits were restored from the snapshot taken when the session started, and the iteration was not allowed to be green: the write-surface a session grants itself is exactly what the scope-guard would otherwise read back from it.\n' \
    "$ticket" "$restored" | tracker_append_note "$ticket" || true
  failures__log "$ticket: the session edited the tracker — restored $restored ticket file(s), the iteration cannot be green"
  return 1
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
#
# And it says what it did not put back. The diff it acts on is a diff of git
# trees, so two sets of paths are outside it: what a project's `.gitignore` covers
# — the guarded ones aside, which the snapshot takes by force — and what the gate's
# own branches wrote after the tree was taken ([29]). Announcing "rolled back N
# paths" while an unenumerated set of paths is exempt is the half-truth [24] was
# opened for, so both zones are named here every time they are not empty.
#
# Its three refusals raise RALPH_ROLLBACK_FAILED, which the loop reads and stops
# on ([34]). Saying "nothing was rolled back" honestly is not enough on its own:
# the session's writes are still in the tree, and the *next* iteration snapshots
# that tree as its own pre-session baseline — after which they belong to nobody
# and are green by construction. The fail-closed of [30] bought a retry and the
# retry laundered it, which is a two-step whitewash; a probe delivered a ticket
# with an out-of-surface `lib/rogue.sh` still sitting in the tree.
#
# A flag rather than a return value because the return value is already taken:
# every caller here treats a failed rollback as non-fatal to the *iteration*,
# which is right — the ticket still has to be marked and escalated. What is not
# survivable is the iteration *after*.
failures_rollback() {
  local pre="$1" base="$2" tree="${3:-}"
  local head restored path paths='' undone=0

  if [ -z "$base" ]; then
    failures__log "no pre-session snapshot — refusing to guess what to roll back"
    RALPH_ROLLBACK_FAILED=1
    return 1
  fi
  [ -n "$tree" ] || tree="$(gate_tree_snapshot)" || tree=""
  if [ -z "$tree" ]; then
    failures__log "cannot read the working tree — nothing was rolled back"
    RALPH_ROLLBACK_FAILED=1
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

  # The restore itself belongs to whoever owns tree objects, and it has a second
  # caller now — the containment of what a review lens wrote ([06]). What stays
  # here is the part that is policy rather than plumbing: moving HEAD, above;
  # unstaging and counting, below; and saying what could not be reached at all.
  if ! restored="$(gate_restore_tree "$base" "$tree")"; then
    failures__log "cannot read the pre-session snapshot — nothing was rolled back"
    RALPH_ROLLBACK_FAILED=1
    return 1
  fi

  while IFS= read -r path; do
    [ -n "$path" ] || continue
    paths="$paths $path"
    undone=$((undone + 1))
  done <<ROLLBACK
$restored
ROLLBACK

  # What the session staged is not work in progress either. Unstaging is scoped
  # to the same paths, so an index a human left half-prepared elsewhere stands.
  if [ -n "$paths" ]; then
    # shellcheck disable=SC2086
    git reset -q -- $paths 2>/dev/null || true
    failures__log "rolled back $undone path(s) the session touched"
  fi

  # Unconditionally, and not only when something was rolled back: a rollback that
  # found nothing to undo is exactly the case where "the tree is back where the
  # session found it" reads as a complete statement.
  failures__report_unrolled "$tree" "$paths"
  return 0
}

# The two sets of paths this rollback structurally cannot reach, named rather than
# alluded to.
#
# The ignored zone comes from gate_ignored_zone, which has two readers: the gate
# says it judged none of them, this says it undid none of them, and both are true
# of one list. What the gate wrote is the same arrangement one ticket later ([29]),
# with one difference — it is netted against what this rollback did put back. A
# path the gate rewrote *and* the session had touched is restored from the
# pre-session snapshot like any other, so listing it here would be the same
# half-truth in the other direction.
#
# The netting is also why this may be read after the restores rather than before
# them: putting a path back does make it differ from the judged tree, and that path
# is in the list of what was undone by construction.
# And a measurement it could not take is said as such rather than printed as an
# empty zone ([34]). Same choice as `gate__report_changed` and for the same reason:
# this is a line about a rollback that has already happened, so reddening here
# would change nothing that is still changeable — what it owes is the difference
# between "there was nothing left" and "nobody knows what was left".
failures__report_unrolled() {
  local tree="${1:-}" undone="${2:-}" zone changed
  if zone="$(gate_ignored_zone)"; then
    failures__log "this rollback could not undo $zone"
  fi
  if ! changed="$(gate_unjudged_changes "$tree")"; then
    failures__log "this rollback could not check what the gate itself changed after the tree it judged — nothing here vouches for that zone"
    return 0
  fi
  if zone="$(gate_zone_line "$(failures__minus "$changed" "$undone")" \
    'path(s) the gate itself changed after the tree it judged')"; then
    failures__log "this rollback could not undo $zone"
  fi
  return 0
}

# A list minus a space-delimited set. Same assumption the unstaging above makes:
# a path with a space in it is not one this loop can carry.
failures__minus() {
  local fence=" ${2:-} " item
  while IFS= read -r item; do
    [ -n "$item" ] || continue
    case "$fence" in
      *" $item "*) continue ;;
    esac
    printf '%s\n' "$item"
  done <<LIST
${1:-}
LIST
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
#
# A session that committed its own work is undone first, on this path exactly as
# on the failing one. Left alone, its commit is the target project's history
# saying something that was never true: `git add -A` takes the tracker mid-claim
# with it, along with the run journal and a session stream that can run to tens
# of megabytes.
failures_make_durable() {
  local ticket="$1" pre="$2" base="$3" tree="${4:-}"
  local changed idx head newtree commit

  if [ -z "$base" ]; then
    failures__log "$ticket: no pre-session snapshot — nothing made durable"
    return 1
  fi
  changed="$(gate_changed_files "$base" "$tree")" || changed=""
  if [ -z "$changed" ]; then
    return 0
  fi

  # Mixed, not soft: the index has to start from the pre-spawn commit too, or what
  # the session staged would still be sitting there waiting for the next commit.
  # Same assumed loss as the rollback — an index a human had prepared on one of
  # these paths goes, the content of their working tree does not.
  head="$(git rev-parse HEAD 2>/dev/null)" || head=""
  if [ -n "$pre" ] && [ -n "$head" ] && [ "$head" != "$pre" ]; then
    if git reset -q --mixed "$pre" 2>/dev/null; then
      failures__log "$ticket: the session committed its own work — rebuilding it from what the gate approved"
      head="$pre"
    else
      failures__log "$ticket: could not move HEAD back to $pre — the session's own commit stands"
    fi
  fi

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
  # Nothing to record: everything the gate approved is already in HEAD. Reached
  # when a session committed its work and HEAD could not be moved back, and when
  # the paths it touched came back to the contents they already had.
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
  # The old value is passed, so this is a compare-and-swap rather than a write:
  # git refuses the move if HEAD is no longer where it was read. Without it, two
  # runs on one repository silently overwrite each other's green iterations — and
  # a second run is one `rm -rf` on the run lock away, since the lock lives in the
  # tracker. An empty `$head` means "must not exist yet", which is the right
  # statement for a repository with no commit. Reported as any refused commit is:
  # the work is in the tree, and this run is not the one that should decide what
  # to do about a HEAD it does not recognise.
  if [ -z "$commit" ] ||
    ! git update-ref -m "ralph: $ticket" HEAD "$commit" "$head" 2>/dev/null; then
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
  local plan out base head seen issues prev_soft prev_timeout moved rc=0
  local headers lines start end header slug title body surface children='' child
  local total incomplete=''

  surface="$(gate_write_surface "$ticket")"
  plan="$(mktemp "${TMPDIR:-/tmp}/ralph-reslice.XXXXXX")" || return 1
  out="$plan.stream"
  : >"$plan"

  base="$(gate_tree_snapshot)" || base=""
  head="$(git rev-parse HEAD 2>/dev/null)" || head=""
  seen="$(failures_tracker_snapshot)"
  issues="$(failures_tracker_tree)" || issues=""
  prev_soft="${RALPH_SOFT_LIMIT_HIT:-0}"
  prev_timeout="${RALPH_SESSION_TIMEOUT:-}"

  failures__reslice_prompt "$ticket" "$plan" >"$plan.prompt"
  session_spawn "$plan.prompt" "$out" || rc=$?
  if [ "${RALPH_SOFT_LIMIT_HIT:-0}" = 1 ]; then
    rc=1
    failures__log "$ticket: the re-slice session crossed the soft limit too"
  fi
  # The same refusal for the two deadlines of [23], and it carries more here than
  # it looks. A planning session the monitor cut short comes back a *success* —
  # `claude` traps TERM and exits 0 — carrying whatever it had written so far, and
  # half a plan that happens to parse is a plan: it would create tickets, drop the
  # acceptance criteria the missing half was carrying, and nothing could take that
  # back, the tracker being outside the rollback's reach on purpose.
  if [ -n "${RALPH_SESSION_TIMEOUT:-}" ]; then
    rc=1
    failures__log "$ticket: the re-slice session ran out of time too (${RALPH_SESSION_TIMEOUT})"
  fi
  RALPH_SOFT_LIMIT_HIT="$prev_soft"
  RALPH_SESSION_TIMEOUT="$prev_timeout"

  # A planning session has no write-surface, so nothing it left in the
  # repository is wanted — including the plan, if it ignored the instructions.
  #
  # Quiet when it works and loud when it does not ([34]). The success line here is
  # noise — a planning session that wrote is the expected case — but a refusal is
  # the same finding as anywhere else, and it was the one place in the pack where a
  # rollback could refuse into `2>&1`. The unreadable-baseline case is reached from
  # inside this function: `base` above is a snapshot that may have been refused, and
  # `|| base=""` is exactly what the rollback's first refusal is written for.
  if ! failures_rollback "$head" "$base" '' >/dev/null 2>&1; then
    failures__log "$ticket: the re-slice session's writes could not be rolled back — they are still in the tree"
  fi

  # And the frontier of what any of that can see, which no rollback reaches:
  # `.git/info/exclude` is in no tree ([30]). The second caller of this, and it is
  # the same argument as the second caller of gate_restore_tree — a planning
  # session is a session, it is never gated, so nothing else here would ever put
  # the rules back and the *next* iteration would pin the widened ones. Said out
  # loud rather than quietly undone: there is no gate on this path to carry a
  # finding, so the log line is the only trace a human gets.
  moved="$(gate_ignore_frontier)" || failures__log \
    "$ticket: the re-slice session moved the ignore frontier — $(printf '%s' "$moved" | tr '\n' ';')"

  # And the plan is refused whole if it wrote the tracker instead of returning
  # one. A session that writes the tracker has stepped past the only check that
  # cannot be redone afterwards, so the rest of what it produced is not worth
  # reading — whether it edited a ticket or created one.
  if ! failures_protect_tracker "$ticket" "$issues"; then
    rm -f "$plan" "$plan.prompt" "$out" "$out.tokens"
    return 1
  fi
  if ! failures_quarantine_strays "$ticket" "$seen"; then
    rm -f "$plan" "$plan.prompt" "$out" "$out.tokens"
    return 1
  fi

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
