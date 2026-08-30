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
#   nothing-   the session answered, and the gate saw not one file change ([35]).
#   delivered  Retried like a red gate: a fresh session is the plausible answer,
#              and nothing here measured the slice either, so it is never
#              re-sliced. Escalated under a name of its own for the reason
#              `timeout` has one — nothing was judged — plus one this class alone
#              carries: there is nothing to *read*. The `failed/<ticket>` branch
#              is not written on this path, because it would hold a tree
#              identical to the one the session was handed.
#   budget     the subscription ran out under one of this iteration's sessions —
#              the delivery session ([08]) or a review lens ([43]). Not a failed
#              attempt at anything: the ticket goes back to the frontier with
#              **no retry consumed**, no escalation and no forensic branch. The
#              tree is still rolled back, and that half is the interesting one —
#              see the note in failures_handle. The one class here that is a
#              *reason* rather than a kind of session, which is why it is also the
#              one whose row in the ignore-frontier table below had to be read as
#              a fact instead of a name.
#
# A session that wrote the tracker is reported apart (`tracker-write`) and
# handled as a red gate: it is the same kind of failure — something in the
# repository is not what the loop asked for — and a fresh session can still
# deliver the ticket.
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
#   RALPH_FAILURE_ACTION    what this policy did about the ticket, as one word and
#                           its argument: `retry:2/3`, `escalated:failed-impl`,
#                           `re-sliced:03-x,04-y`, `given-back`. The outcome says
#                           what happened to the *iteration*; this says what
#                           happened to the *ticket*, and no reader could derive
#                           one from the other — a red gate retried and a red gate
#                           escalated are the same outcome ([07] left that to [10],
#                           which needs it twice: the journal carries it, and the
#                           receipt exists only on the paths that end a ticket).
#   RALPH_FAILURE_BRANCH    the `failed/<ticket>` ref, when one was really written.
#                           Named rather than assumed: the branch is skipped by
#                           design on `nothing-delivered` ([35]) and it can refuse
#                           to be written, and a receipt that told a human to go and
#                           read a ref that does not exist has misrouted them.

failures__log() {
  printf 'ralph: %s\n' "$*"
}

# Said out loud *and* kept for the receipt ([10]), for the same two kinds of
# sentence `gate__say` keeps one layer up: what this rollback could not reach, and
# where it could not measure at all ([34]). On the paths where no gate ran ([32])
# these lines are the only trace of the event there will ever be — there is no
# verdict beside them and no branch output to fall back on.
failures__say() {
  failures__log "$@"
  receipt_note "$@"
}

# The other half of the same idea, and it is a different kind of sentence ([45]):
# not a zone nobody looked at, but something this policy was going to do and did
# not. The rollback that refused, the `failed/<ticket>` git would not write, the
# ticket file that could not be restored, the split that never happened.
#
# Which of the two a line goes through is decided by the criterion and never by
# the list of lines that existed when the channel was written — that mistake is
# what [45] is: [10] wired the sentences it had in front of it, and half of this
# file's admissions had no way to the document at all. A receipt sends a human to
# read `failed/<ticket>`; the five reasons git may not have written it were on
# stdout and nowhere else.
#
# What stays on `failures__log` is everything that reports what *did* happen — the
# rollback that worked, the branch that was written, the escalation itself. Those
# are in the receipt already, as facts rather than as prose.
failures__gap() {
  failures__log "$@"
  receipt_gap "$@"
}

# ── what kind of failure this was ────────────────────────────────────────────

# The loop knows four things: whether the session was cut short for context,
# whether the subscription ran out under it, whether the gate went red, and how
# the scope-guard classified an overflow.
failures_classify() {
  local outcome="$1" scope_class="${2:-}"
  case "$outcome" in
    # In front of the default case, which is where this used to land ([08]): a
    # session refused for quota exits non-zero, and read off the exit code alone
    # that is indistinguishable from a crash. It is not one — nothing was
    # attempted — so it must not reach the counter below. Which question the loop
    # asks first is decided there, and it matters: a reason the monitor took
    # itself outranks one read out of the session's own stream ([23]).
    budget-pause)
      printf 'budget\n'
      ;;
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
    # Deliberately not gate-red either, and for the mirror of the reason above: a
    # red check is evidence that something was judged and found wrong, and this
    # says nothing was judged at all. The two would be told apart by nothing
    # downstream — same retry budget, same escalation reason — and a human sent to
    # read a verdict on a session that wrote nothing has been misrouted ([26]).
    nothing-delivered)
      printf 'nothing-delivered\n'
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

# ── the frontier: what any of this can see, and what git runs ────────────────

# The frontier put back, on an iteration no gate judged ([32]).
#
# `.git/info/exclude` and `core.excludesFile` are in no tree, so no rollback
# reaches them, and they decide what every check in this pack can see; since [46]
# the same list carries the configuration that decides what git *executes* and what
# it hands the next worktree, which is in no tree either. [30] made
# that a finding and put them back — inside `gate_run`, which is exactly where an
# iteration that crashed or was cut short never goes. Left alone, the *next*
# iteration pins the widened frontier as the project's own configuration and
# writes behind it at green: one non-zero exit, which a session controls, buys the
# rest of the night. Probed on both paths in [32].
#
# Said out loud rather than quietly undone, and for the reason the second caller
# in `failures_reslice` says it too: there is no scope-guard here to carry a
# finding, so the log line is the only trace a human gets in the morning. It is
# not a verdict and must not become one — the iteration is already failing, and
# what was missing was the restore and never a class of its own.
#
# The tree's own `.gitignore` files have nothing to put back — a ticket may add an
# ignore rule, that is project work ([30]) — but on this path nobody was naming
# them either, so a human read `this rollback could not undo … lib/` with no way
# to tell a build directory from a directory a session had just decided to hide.
# The sentence differs from the gated one because the fact does: here the rollback
# below takes the rule away with the rest of the session's writes, so the new rules
# apply to nothing. If that rollback refuses, it says so itself and the run stops
# ([34]) — a line that has been contradicted two lines later and loudly is not the
# half-truth [29] refused.
failures__frontier() {
  local ticket="$1" moved findings finding

  if moved="$(gate_moved_tree_rules)"; then
    failures__say "$ticket: this session moved the ignore frontier: $moved — no gate judged this iteration, and those rules go back with the rest of what it wrote"
  fi

  findings="$(gate_frontier)" || true
  while IFS= read -r finding; do
    [ -n "$finding" ] || continue
    failures__say "$ticket: $finding"
  done <<FRONTIER
$findings
FRONTIER
  return 0
}

# ── the policy ───────────────────────────────────────────────────────────────

# One failed iteration, from classification to a ticket somebody can act on.
# Called with the two pre-spawn snapshots — the commit HEAD pointed at and the
# tree of the working directory — plus the post-session tree when the gate
# already computed one.
failures_handle() {
  local ticket="$1" outcome="$2" pre="$3" base="$4" tree="${5:-}"
  local class count="" reason=""

  # Cleared before the first thing that can fail, like the rollback flag below: an
  # action left over from the previous iteration would be read by the journal and
  # by the receipt as this one's ([10]).
  RALPH_FAILURE_ACTION=none
  RALPH_FAILURE_BRANCH=""

  class="$(failures_classify "$outcome" "${RALPH_GATE_SCOPE_CLASS:-}")"

  # Which of the six classes reach here without their ignore rules having been put
  # back, read off the `case` above rather than remembered — that list is where
  # [30] went wrong, closing the one path without a gate it had in mind and
  # missing the two [23] had added two days earlier ([32]).
  #
  #   gate-red, contract, nothing-delivered  a gate ran: `gate_run` restored the
  #                                          rules before it took the tree, and
  #                                          printed the findings either on the
  #                                          scope-guard's output or, on the
  #                                          delivery refusal, by itself ([35]).
  #   too-big                                `failures_reslice` restores below,
  #                                          after the planning session it spawns
  #                                          — a session that is never gated
  #                                          either, and the restore has to fall
  #                                          after it to cover what *it* moved.
  #   crash, timeout, budget                 nobody. That is this ticket — and
  #                                          `budget` joined the list in [08] by
  #                                          reading it here rather than by
  #                                          remembering it, which is the whole
  #                                          method of [32].
  #
  # And the correction [43] had to make to that table, which was already wrong for
  # one combination before it: the list is by *class*, and `budget` is the one
  # class that is not a class of session. It is a reason, and the classifier puts
  # it in front of whatever the outcome was — `nothing-delivered` since [08]/[35],
  # and a review lens the API refused since [43]. Both of those come out of a gate
  # that ran and restored, so on those two the row above is `budget` and the truth
  # is "a gate did". Asking anyway re-detects the one source no restore can put
  # back — the global excludes file, outside the repository — announces it a second
  # time, records it in the run's register a second time, and charges every sibling
  # in flight for one widening twice ([41]). So the question asked is the fact
  # rather than the class: did anything already read this iteration's frontier.
  #
  # Conditioned on the class rather than made idempotent, and the choice is worth
  # writing down: what a second call would report twice is exactly what could not
  # be put back — the global excludes file, outside the repository — so an
  # unconditional call would announce one movement twice on the paths that already
  # restore. One caller per iteration, whichever path it takes.
  #
  # Before the tree snapshot below, so the rollback measures the repository
  # through the rules the run was handed rather than the ones the session left,
  # and before the rollback itself, so the line about the tree's rules names them
  # while they are still there.
  case "$class" in
    crash | timeout | budget)
      [ "${RALPH_GATE_FRONTIER_READ:-0}" = 1 ] || failures__frontier "$ticket"
      ;;
  esac

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
    budget)
      # No count, no reason, no forensic branch: nothing was attempted, so there
      # is nothing to bill and nothing to read. `Failures:` is the ticket's retry
      # budget since [26] and it has to keep meaning that — a night that ran out
      # of subscription would otherwise escalate a whole frontier as failed
      # implementations, each with a `failed/<ticket>` branch holding the tree
      # its session was handed.
      #
      # What still happens on this path is the rollback below, and that is a
      # decision this ticket took against its own comment ([07] wrote "a budget
      # pause must not roll back"). A session refused mid-flight leaves half a
      # file in the tree; leaving it there hands the *next* iteration a baseline
      # it did not write, which is the laundering [34] stopped the run over. The
      # ticket comes back to a frontier, not to a dirty tree.
      #
      # What bounds a session that forges this class — the in-band signal lives
      # in a file it can write ([23]) — is not here: it is `STERILE_K` in the
      # loop, which counts iterations that resolved nothing whatever they claimed
      # to be.
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
        # And the third one, which is the same statement with nothing left to
        # read at all ([35]). The note is the routing: the question to put to a
        # human here is not "why is this code wrong" — no code was written — but
        # "why does this ticket make a session do nothing".
        if [ "$class" = nothing-delivered ]; then
          reason=nothing-delivered
          printf 'Every attempt on this ticket (%s of %s) ended with a session that answered and changed no file the gate can see. Nothing was judged: there is no red check to read, no lens verdict, and no `failed/%s` branch — it would hold the tree the session was handed. What is left is `run.log` and the ticket itself, so the question is why this ticket makes a session do nothing: a criterion nothing can act on, work that is already done, a prompt that arrived truncated.\n' \
            "${count:-unknown}" "${RETRY_N:-2}" "$ticket" |
            tracker_append_note "$ticket" || true
        fi
      fi
      ;;
  esac

  # Before the tree is put back, not after: the branch is the only copy of what
  # the session actually did once the rollback has run. Never fatal — a git that
  # refuses to write a forensic branch (a ref named `failed` already in the way,
  # a lock a crashed git left behind) must not take the run down with it.
  #
  # Not written for a session that delivered nothing, and that is a decision
  # rather than an optimisation ([35]): the tree it would carry is the tree the
  # session started from, so the branch would be a forensic artefact of nothing,
  # offered to a human as the thing to go and read. The note above says where to
  # look instead.
  # Recorded on success only, and that is the point of naming it rather than
  # deriving it from `$reason` ([10]): the call is `|| true`, so a ref this git
  # refused to write — a `failed` ref already in the way, a lock a crashed git left
  # — leaves an escalation with nothing behind it, and a receipt that promised the
  # branch anyway would send a human to read something that is not there.
  if [ -n "$reason" ] && [ "$class" != nothing-delivered ]; then
    if failures_preserve_attempt "$ticket" "$pre" "$tree"; then
      RALPH_FAILURE_BRANCH="failed/$ticket"
    fi
  fi

  failures_rollback "$pre" "$base" "$tree" || true

  if [ "$class" = too-big ]; then
    if failures_reslice "$ticket"; then
      return 0
    fi
    reason=too-big
    if failures_preserve_attempt "$ticket" "$pre" "$tree"; then
      RALPH_FAILURE_BRANCH="failed/$ticket"
    fi
  fi

  if [ -n "$reason" ]; then
    tracker_mark_escalated "$ticket" "$reason"
    RALPH_FAILURE_ACTION="escalated:$reason"
    failures__log "$ticket: escalated to the human sink ($reason)"
  elif [ "$class" = budget ]; then
    # Given back, and said differently on purpose: "fresh retry (n of N)" would
    # be a sentence about a counter this path never touched, which is exactly the
    # kind of line a human reads in the morning and believes.
    tracker_unclaim "$ticket"
    RALPH_FAILURE_ACTION=given-back
    failures__log "$ticket: given back with no retry consumed — the subscription ran out under this session, which is not an attempt at this ticket"
  else
    tracker_unclaim "$ticket"
    RALPH_FAILURE_ACTION="retry:${count:-?}/${RETRY_N:-2}"
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

# The ids the tracker holds right now, one per line — the convention every list
# the pack hands itself has followed since [33], and the reason it has to reach the
# ids too is [37]: an id is the name of a file **the session chooses**, so a format
# that joins them with spaces asks the reader to guess where one ends. This used to
# render ` a b ` and the reader asked `case "$seen" in *" $id "*`, which is a
# comparison against words and not against ids.
failures_tracker_snapshot() {
  tracker_ids
}

# ── what the loop itself wrote, for every guard here ─────────────────────────
#
# One definition of "this is not the judged session's doing", read by both guards
# below and by whatever third guard comes after them. It is one call deep on
# purpose: the answer lives in the dispatcher's register ([13]), where every
# tracker write goes through, and a guard that kept its own list beside it would
# be the [25] defect again — wrong the first time somebody adds a writer.
#
# An empty mark means "no register was taken", which is a caller driving one
# iteration at a time: the shape these guards had before there was ever a sibling,
# and the answer is the empty list rather than a refusal.
failures__register_since() {
  local mark="${1:-}"
  [ -n "$mark" ] || return 0
  tracker_writes_since "$mark"
}

# Whether this id is one of the entries in a one-per-line list of ids. One
# function for the register and for the pre-session snapshot, because since [37]
# the two travel in the same shape and the question they ask is the same one —
# a second copy of the comparison is a second place to get it wrong.
#
# Whole lines, never `case "$list" in *" $id "*`: that pattern answered yes for
# every *word* of an id, so a register naming `99-my ticket` exempted a stray
# called `99-my`, and a snapshot holding `99-my ticket` hid a stray called
# `ticket`. An id is a file name a session chooses ([37]).
failures__in_list() {
  local needle="$1" line
  while IFS= read -r line; do
    if [ "$line" = "$needle" ]; then return 0; fi
  done <<LIST
$2
LIST
  return 1
}

# Ids that were not there before. Not "tickets the loop created": the loop's own
# creations happen after this check, on purpose.
failures__strays() {
  local seen="$1" id
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    ! failures__in_list "$id" "$seen" || continue
    printf '%s\n' "$id"
  done <<IDS
$(tracker_ids)
IDS
  return 0
}

# Anything the session added to the tracker goes to the human sink rather than to
# the frontier: it has been through none of the checks a ticket owes the loop —
# no write-surface validated, no acceptance criteria, no discovery. Returns
# non-zero when there was something to quarantine, so a caller that was reading
# the session's output can stop reading it.
failures_quarantine_strays() {
  local ticket="$1" seen="$2" mark="${3:-}"
  local strays stray final renamed_to kept='' renamed='' ours
  strays="$(failures__strays "$seen")"
  [ -n "$strays" ] || return 0

  # What the *loop* created in here while this session was running, which is not
  # the session's doing and must not be quarantined ([42]): a sibling's re-slice
  # puts its children on the frontier, and an id that was not there when this
  # session started looks exactly like a ticket a session gave itself.
  #
  # By id, and the reason it is enough is not that ids are a strong trace — they
  # are not, and [13] says so. It is which entries can reach this comparison at
  # all: a stray is an id the tracker did not hold at spawn, so a register entry
  # can only match one by naming a ticket the loop *created* inside the window.
  # Every other entry names a ticket that was already there, and a ticket that was
  # already there is never a stray. That equivalence is why the dispatcher had to
  # start noting the id `open_ticket` *returned* rather than the slug it was
  # handed: a slug names no ticket, so a session that created `alpha-one.md` would
  # have walked in behind the loop's own re-slice.
  #
  # Silent when it exempts, and that is a decision. The creation is already named
  # by the iteration that made it (`too big -> re-sliced into ...`); a second line
  # here would say "a sibling was busy" once per iteration in flight, on the
  # normal path, and this log has to stay readable at 3am.
  ours="$(failures__register_since "$mark")"

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
    ! failures__in_list "$stray" "$ours" || continue
    final="$stray"
    # A refusal is said, never swallowed. Rendering the unchanged id when the
    # renumber could not run would hand back exactly the state being repaired,
    # in silence — a fix whose failure mode is the defect it fixes.
    if ! renamed_to="$(tracker_renumber "$stray")" || [ -z "$renamed_to" ]; then
      failures__gap "$ticket: could not give $stray a number of its own — if another ticket already carries it, no bare number will resolve until a human renames one"
    else
      final="$renamed_to"
    fi
    if [ "$final" != "$stray" ]; then
      renamed="$(failures__append_line "$stray -> $final" "$renamed")"
      printf 'This ticket reached the tracker as `%s`, written by the %s session, and carried a number another ticket already had. It was renumbered to `%s` rather than deleted or left in place: nothing a session wrote is destroyed, and a duplicate number takes every ticket that points at it out of the frontier for good. The body below is exactly as the session wrote it, heading included.\n' \
        "$stray" "$ticket" "$final" | tracker_append_note "$final" || true
    fi
    tracker_mark_escalated "$final" decision || true
    kept="$(failures__append_line "$final" "$kept")"
  done <<STRAYS
$strays
STRAYS

  # Nothing left once the loop's own creations are out: there is no quarantine, no
  # note naming a session that wrote nothing, and no non-zero to make a caller
  # throw away what it was reading.
  [ -n "$kept" ] || return 0

  printf 'The %s session wrote these tickets into the tracker itself: %s. Nothing validated their write-surface or their acceptance criteria, so they are waiting for a human instead of sitting on the frontier.%s\n' \
    "$ticket" "$(failures__join "$kept")" \
    "$(if [ -n "$renamed" ]; then
      printf ' Renumbered on the way in, to keep a bare number resolvable: %s.' "$(failures__join "$renamed")"
    fi)" |
    tracker_append_note "$ticket" || true
  failures__log "$ticket: the session wrote the tracker itself — quarantined $(failures__join "$kept")"
  [ -z "$renamed" ] ||
    failures__log "$ticket: a ticket the session added took a number another ticket already had — renumbered $(failures__join "$renamed")"
  return 1
}

# Add one entry to a one-per-line list held in a variable. The accumulators above
# used to be `x="$x $entry"`, which is the [37] defect wearing the other hat: the
# separator was a space and the entries are ids a session names, so the note that
# tells a human *which* tickets were quarantined ran two of them together the
# moment one carried a space.
failures__append_line() {
  if [ -n "$2" ]; then
    printf '%s\n%s' "$2" "$1"
  else
    printf '%s' "$1"
  fi
}

# A one-per-line list rendered for a human, joined whole line by whole line.
failures__join() {
  awk 'length { if (n++) printf ", "; printf "%s", $0 } END { if (n) print "" }' <<LIST
$1
LIST
}

# Where the tickets live, relative to the repository root. Same assumption
# gate_is_bookkeeping makes: the project root is the repository root, and a pack
# installed below it is out of scope for now.
failures__issues_path() {
  printf '.scratch/%s/issues\n' "${FEATURE:?ralph: FEATURE is not set}"
}

# Whether a path that moved inside the tracker directory is a **ticket file**,
# which is the only thing the guard below restores.
#
# The definition is the tracker's own scan — `"$dir"/*.md`, that directory and no
# deeper — and writing it down is [49]. `issues/` holds more than tickets, and the
# rest of it is the *pack's own*: the guard directory a claim takes beside the
# ticket it is about to stamp (`<id>.md.guard/pid`), the temp file every atomic
# write leaves next to its target (`<id>.md.tmp.XXXXXX`), the working copy
# `set_fields` publishes from (`<id>.md.work.XXXXXX`, plus its own `.p`). Each of
# them exists for a few milliseconds inside a window this guard is 35 ms wide, so
# a sibling that writes the tracker while this session is judged leaves one in the
# *before* snapshot and not in the *after* one — a `D` this guard used to hand to
# `checkout-index`, putting a lock back and calling a session that wrote nothing
# an editor of the tracker.
#
# The register of [13]/[42] cannot help and it must not be asked to: it is indexed
# by **id**, and none of those names is one — `basename .../02-beta.md.guard/pid
# .md` is `pid`, `basename 02-beta.md.work.IDdYXp .md` is the whole name.
#
# Filtering here rather than moving the transients out of `issues/` is the
# decision, and it is not free: what a session drops in there under a name that is
# not `<id>.md` is now restored by nothing, and it was never quarantined either
# (`tracker_ids` globs `*.md`). That zone is named out loud on every window it
# moves in, below, rather than left to a document. The other exit — publishing
# every transient somewhere else — was refused because it is not available to the
# one that matters: `state_atomic_write` has to write beside its target for the
# rename to be atomic, and its targets are not all in `issues/`.
failures__is_ticket_path() {
  local path="$1" dir="$2" rest
  case "$path" in
    "$dir"/*.md) ;;
    *) return 1 ;;
  esac
  rest="${path#"$dir"/}"
  case "$rest" in
    */*) return 1 ;;
  esac
  return 0
}

# The tickets as a git tree object. Taken twice, around the spawn: two identical
# hashes is the whole of the normal case, and it costs one plumbing call.
#
# Read from the project root explicitly, because since [13] an iteration runs with
# its working directory inside a throwaway worktree and `gate_tree_snapshot` is
# relative to wherever it is called from. The tracker is the one piece of state
# every iteration shares — it is the authority they coordinate through — so it has
# to be the tree the run was started in and never the copy a worktree happens to
# carry. Getting this wrong is silent: the guard would snapshot a stale copy, find
# it unchanged, and vouch for a tracker nobody looked at.
failures_tracker_tree() {
  (cd "$(ralph_project_root)" && gate_tree_snapshot "$(failures__issues_path)")
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
#
# **Ticket files, and nothing else** ([49]). What moved under a name that is not
# `<id>.md` is left where it is and named out loud: `issues/` is also where this
# pack puts its own short-lived objects, and a `D` for one of those is a sibling's
# lock, not an edit — restoring it accused a session that had written nothing,
# refused a green to an innocent iteration and, when the `D` was a claim's guard,
# put the lock back stamped with the pilot's own live pid, which nothing releases
# and which takes that ticket out of the frontier for the rest of the run.
#
# Every git call here names the project root, for the reason failures_tracker_tree
# does: the caller's working directory is a throwaway worktree since [13], and the
# tracker lives in the tree the run was started in. A `checkout-index` run from the
# worktree would restore the tickets into the copy that is about to be thrown away
# and report that it had put them back.
failures_protect_tracker() {
  local ticket="$1" before="$2" mark="${3:-}"
  local dir after idx status path restored=0 root ours id
  local others='' others_n=0 unvouched=''

  if [ -z "$before" ]; then
    failures__gap "$ticket: no pre-session tracker snapshot — the tracker cannot be vouched for"
    return 1
  fi
  after="$(failures_tracker_tree)" || after=""
  if [ -z "$after" ]; then
    failures__gap "$ticket: cannot read the tracker — refusing to pass it"
    return 1
  fi
  [ "$after" != "$before" ] || return 0

  root="$(ralph_project_root)"
  dir="$(failures__issues_path)"
  # What the *loop* wrote in here while this session was running, which is not the
  # session's doing and must not be undone ([13] on [21]) — the same definition the
  # quarantine reads, from the same place ([42]).
  ours="$(failures__register_since "$mark")"
  idx="$(mktemp "${TMPDIR:-/tmp}/ralph-tracker.XXXXXX")" || return 1
  rm -f "$idx"
  if ! GIT_INDEX_FILE="$idx" git -C "$root" read-tree "$before" 2>/dev/null; then
    rm -f "$idx"
    failures__gap "$ticket: cannot read the pre-session tracker — nothing was restored"
    return 1
  fi

  # The pathspec is redundant with a snapshot already scoped to the tickets, and
  # it stays: this loop overwrites files, so it may never be one bad snapshot
  # away from restoring something outside the tracker.
  while IFS="$(printf '\t')" read -r status path; do
    [ -n "$path" ] || continue
    # A name git prints quoted whatever `core.quotePath` says — a tab, a newline,
    # a quote — is a name nothing here can hand to `checkout-index` ([39]). Named
    # and counted as a hole rather than restored, and it keeps the iteration from
    # being green: a guard that cannot see does not pass.
    if gate_unaddressable "$path"; then
      failures__gap "$ticket: $path moved in the tracker under a name this guard cannot address — nothing was put back for it"
      unvouched=1
      continue
    fi
    # Not everything under `issues/` is a ticket, and this guard restores tickets.
    # The pack's own transients live there too, and a sibling's lock put back by a
    # `checkout-index` is a ticket no iteration of this run can claim again.
    if ! failures__is_ticket_path "$path" "$dir"; then
      others="$(failures__append_line "$path" "$others")"
      others_n=$((others_n + 1))
      continue
    fi
    # A ticket this run wrote itself inside the window: a sibling's claim, its
    # retry counter, its marking. Skipped before the status is even looked at,
    # because restoring it is how two iterations in flight destroy each other.
    id="$(basename "$path" .md)"
    ! failures__in_list "$id" "$ours" || continue
    case "$status" in
      A)
        # Left where it is: a created ticket belongs to the quarantine, which
        # hands it to a human. Deleting it here would destroy the only copy of
        # what it asked for.
        ;;
      *)
        GIT_INDEX_FILE="$idx" git -C "$root" checkout-index -f -- "$path" 2>/dev/null ||
          failures__gap "$ticket: could not restore $path"
        restored=$((restored + 1))
        ;;
    esac
  done <<TRACKER
$(git -C "$root" -c core.quotePath=false diff-tree -r --name-status "$before" "$after" -- "$dir" 2>/dev/null)
TRACKER

  rm -f "$idx"
  # Staged is not work in progress either, and the tracker has no business in the
  # target project's index. Scoped to the tickets, so nothing staged elsewhere
  # moves; a human who had staged a tracker edit before the run loses that much.
  git -C "$root" reset -q -- "$dir" 2>/dev/null || true

  # What restoring tickets and only tickets leaves behind, said on the window it
  # is paid in rather than once in a document ([24]'s rule for a zone nobody
  # guards). Most of what lands here is this pack's own churn — a sibling
  # mid-claim, an atomic write in flight — so the sentence says that rather than
  # reading as an accusation, which is the whole point of the filter.
  [ "$others_n" = 0 ] ||
    failures__say "$ticket: $others_n path(s) under the tracker directory that are not ticket files moved in this window and were left exactly as they are ($(failures__join "$others")): the pack writes its own transients beside the tickets — a claim's guard, an atomic write's temp file — and anything else dropped in there is put back by nothing here and quarantined by nothing either, both looking only at a name shaped <id>.md"

  [ -z "$unvouched" ] ||
    failures__log "$ticket: a path in the tracker moved under a name this guard cannot address — nothing here can vouch for the tracker, so the iteration cannot be green"

  # Additions only: that is the quarantine's business and not a failure of its own.
  if [ "$restored" -gt 0 ]; then
    printf 'The %s session edited the tracker itself (%s ticket file(s)). The edits were restored from the snapshot taken when the session started, and the iteration was not allowed to be green: the write-surface a session grants itself is exactly what the scope-guard would otherwise read back from it.\n' \
      "$ticket" "$restored" | tracker_append_note "$ticket" || true
    failures__log "$ticket: the session edited the tracker — restored $restored ticket file(s), the iteration cannot be green"
    return 1
  fi
  [ -z "$unvouched" ] || return 1
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
    failures__gap "no pre-session snapshot — refusing to guess what to roll back"
    RALPH_ROLLBACK_FAILED=1
    return 1
  fi
  [ -n "$tree" ] || tree="$(gate_tree_snapshot)" || tree=""
  if [ -z "$tree" ]; then
    failures__gap "cannot read the working tree — nothing was rolled back"
    RALPH_ROLLBACK_FAILED=1
    return 1
  fi

  head="$(git rev-parse HEAD 2>/dev/null)" || head=""
  if [ -n "$pre" ] && [ -n "$head" ] && [ "$head" != "$pre" ]; then
    if git reset -q --mixed "$pre" 2>/dev/null; then
      failures__log "rolled back the commit the session made"
    else
      failures__gap "could not move HEAD back to $pre"
    fi
  fi

  # The restore itself belongs to whoever owns tree objects, and it has a second
  # caller now — the containment of what a review lens wrote ([06]). What stays
  # here is the part that is policy rather than plumbing: moving HEAD, above;
  # unstaging and counting, below; and saying what could not be reached at all.
  if ! restored="$(gate_restore_tree "$base" "$tree")"; then
    failures__gap "cannot read the pre-session snapshot — nothing was rolled back"
    RALPH_ROLLBACK_FAILED=1
    return 1
  fi

  # The list travels as it was printed — one path per line — instead of being
  # joined back into a single whitespace word ([33], and it was still joined here
  # when [39] came through). Both halves that read it were cutting it on spaces:
  # the unstaging below turned a name carrying one into pathspecs that matched
  # nothing, and `failures__minus` answered "already undone" for *each word* of
  # such a name, so an unrelated path whose name was one of those words dropped out
  # of the "could not undo" line. A word closure does not break on an entry with a
  # space in it, it answers yes for every word of it ([37]) — a false negative
  # nothing prints.
  paths="$restored"
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    # What the session staged is not work in progress either. Unstaging is scoped
    # to the paths this rollback put back, so an index a human left half-prepared
    # elsewhere stands. `:(literal)` for the third reason in that family: a path is
    # not a pattern, and `src/zone[1].txt` was unstaged as `src/zone1.txt`.
    #
    # One call per path is a consequence of reading the list by line, not a fix of
    # its own — probed, and worth knowing because the two git commands differ where
    # it matters: a pathspec matching nothing makes `git add` refuse the *whole*
    # call, while `git reset` leaves that one alone and does the rest. So the
    # defect here was local — `src/my file.txt` stayed staged and its neighbours
    # did not — and the one in the durable commit was total.
    git reset -q -- ":(literal)$path" 2>/dev/null || true
    undone=$((undone + 1))
  done <<ROLLBACK
$restored
ROLLBACK

  if [ "$undone" -gt 0 ]; then
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
    failures__say "this rollback could not undo $zone"
  fi
  if ! changed="$(gate_unjudged_changes "$tree")"; then
    failures__say "this rollback could not check what the gate itself changed after the tree it judged — nothing here vouches for that zone"
    return 0
  fi
  if zone="$(gate_zone_line "$(failures__minus "$changed" "$undone")" \
    'path(s) the gate itself changed after the tree it judged')"; then
    failures__say "this rollback could not undo $zone"
  fi
  return 0
}

# A list of paths minus another, both one entry per line, compared whole line
# against whole line.
#
# It was a space-fenced membership test until [39], carrying the assumption its own
# comment stated — "a path with a space in it is not one this loop can carry" — and
# the assumption was false in the direction nothing prints: a fence of words does
# not fail to match a name with a space, it matches *each of its words* ([37]), so
# `src/my file.md` having been rolled back was read as `src/my` and `file.md`
# having been, and any unrelated path called one of those two dropped out of the
# line that says what this rollback could not undo.
failures__minus() {
  local item
  while IFS= read -r item; do
    [ -n "$item" ] || continue
    ! failures__in_list "$item" "${2:-}" || continue
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
    failures__gap "$ticket: nothing readable to keep on $branch"
    return 1
  fi

  idx="$(mktemp "${TMPDIR:-/tmp}/ralph-failed.XXXXXX")" || return 1
  rm -f "$idx"
  if ! GIT_INDEX_FILE="$idx" git read-tree "$tree" 2>/dev/null; then
    rm -f "$idx"
    failures__gap "$ticket: could not read the attempt — $branch not written"
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
    failures__gap "$ticket: could not write the attempt — $branch not written"
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
    failures__gap "$ticket: could not commit the attempt — $branch not written"
    return 1
  }

  if git update-ref "refs/heads/$branch" "$commit" 2>/dev/null; then
    failures__log "$ticket: the attempt is kept on branch $branch"
  else
    failures__gap "$ticket: could not write branch $branch"
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
  local changed idx head newtree commit path refused=''

  if [ -z "$base" ]; then
    failures__gap "$ticket: no pre-session snapshot — nothing made durable"
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
      failures__gap "$ticket: could not move HEAD back to $pre — the session's own commit stands"
    fi
  fi

  idx="$(mktemp "${TMPDIR:-/tmp}/ralph-durable.XXXXXX")" || return 1
  rm -f "$idx"
  if [ -n "$head" ]; then
    GIT_INDEX_FILE="$idx" git read-tree "$head" >/dev/null 2>&1 || true
  fi
  # One path per line and one `git add` per path, for the three reasons the
  # snapshot carries at length ([33], then [39]). `git add -A -- $changed` word-split
  # a name with a space into pathspecs that matched nothing, and pathname-expanded
  # the list against the working tree on top of that; a single call fails *whole*,
  # so one path git refused took every other path out of the commit with it, under a
  # `|| true` written for the one that was refused; and a pathspec is a pattern, so a
  # file really named `zone[1].md` was staged as `zone1.md` or as nothing at all.
  #
  # `--force`, and it is the decision [50] was opened to take rather than a flag
  # ([39] found the case and deliberately left it). Staged through the same lens
  # the tree was *judged* through, which is the whole of the argument: an ignored
  # path can only be in this list because `gate_tree_snapshot` forced it in, and it
  # forces exactly two families — the project's own `GUARDED_PATHS` ([24]) and what
  # a rule written during this iteration took out of sight ([30]). Everything else
  # ignored was skipped by the plain `git add -A` at the top of that snapshot, so it
  # is in no tree here and cannot reach this line. Without the flag the gate judged
  # those two families, approved them, and rolled them back on red — and on green,
  # the one outcome where the work is supposed to survive, did nothing at all. What
  # it costs is written down in `docs/frontiere-de-confiance.md`; the short version
  # is that a sealed path can never be approved, so the file a project ignores
  # `.claude/` *for* is not reachable from here.
  # The status is kept rather than swallowed, and it is half of a verdict and not a
  # verdict ([39] is right that asserting it alone proves nothing): a refusal on a
  # path the session deleted out of a tree that was never committed loses nothing,
  # because there is nothing on either side. Paired further down with the result,
  # which is the other half. Written above the loop rather than inside it so that
  # the body stays one anchorable shape for `test/mutate.sh`.
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if ! GIT_INDEX_FILE="$idx" git add -A --force -- ":(literal)$path" >/dev/null 2>&1; then
      refused="$refused$path
"
    fi
  done <<CHANGED
$changed
CHANGED
  newtree="$(GIT_INDEX_FILE="$idx" git write-tree 2>/dev/null)" || newtree=""
  rm -f "$idx"

  if [ -z "$newtree" ]; then
    failures__gap "$ticket: could not stage the iteration — it is not committed"
    return 1
  fi

  # What the gate approved and this tree does not carry, named rather than dropped
  # ([39]). Neither half of this answers on its own, which is why both are asked.
  # The *status* alone accuses a path the session deleted out of a tree that was
  # never committed: git refuses the pathspec, nothing is lost, and the `|| true`
  # above exists for exactly that. The *result* alone accuses the project's own
  # test suite: `TEST_CMD` runs after the tree was judged, so a delivered file it
  # rewrote differs from the judged tree while sitting in this commit with newer
  # bytes — a finding, but somebody else's, and it is already named every iteration
  # by `gate_unjudged_changes`. Both together say the one thing this line is for:
  # git would not take this path, and the work is not in the commit. Before [39] it
  # was silent, and the loudest case was a name outside pure ASCII, refused for the
  # shape it arrived in.
  #
  # `refused` is built out of `changed`, so this is netted the way [39] netted it
  # and for the same reason: a run started on a tree that already had uncommitted
  # work has paths where `base` and `HEAD` differ that no session touched, and
  # accusing those would be this gap line saying something false on every dirty
  # repository.
  #
  # What used to be its loudest case is gone rather than quieter: since [50] the
  # staging above forces, so a guarded path the project ignores is committed
  # instead of named here.
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    failures__in_list "$path" "$refused" || continue
    failures__gap "$ticket: $path was approved by the gate and could not be staged — it is not in this commit"
  done <<MISSED
$(git -c core.quotePath=false diff-tree -r --name-only "$newtree" "$tree" 2>/dev/null)
MISSED

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
    failures__gap "$ticket: could not commit the iteration — it is not durable"
    return 1
  fi

  # The real index still describes the state before the commit, which would show
  # up as a staged deletion. Same paths, so nothing else staged is disturbed, and
  # one literal pathspec per line for the reason the staging above carries.
  #
  # `--force` here too, and the two are one decision and not two ([50]): the commit
  # above now carries a guarded path the project ignores, so an index that could
  # not take the same path would describe that very path as deleted — the exact
  # state this block exists to prevent, reintroduced by fixing the other half. The
  # two calls succeed and fail together, being the same call on the same conditions,
  # so the index still ends up agreeing with the commit either way.
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    git add -A --force -- ":(literal)$path" >/dev/null 2>&1 || true
  done <<CHANGED
$changed
CHANGED
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
  local plan out base head seen issues mark prev_soft prev_timeout moved rc=0
  local headers lines start end header slug title body surface children='' child
  local total incomplete=''

  surface="$(gate_write_surface "$ticket")"
  plan="$(mktemp "${TMPDIR:-/tmp}/ralph-reslice.XXXXXX")" || return 1
  out="$plan.stream"
  : >"$plan"

  base="$(gate_tree_snapshot)" || base=""
  head="$(git rev-parse HEAD 2>/dev/null)" || head=""
  # Where the loop's own register stands, taken *before* both snapshots below
  # ([42]). A planning session is a session and this window is a sibling's window
  # too: what the loop writes in `issues/` while the planner thinks — a claim, a
  # marking, the children of another re-slice — is not the planner's doing. First
  # of the three, in that order, because over-excluding leaves a ticket alone and
  # under-excluding destroys a sibling's marking: anything the loop appends
  # between the register and a snapshot must fall inside the exemption rather than
  # outside it.
  mark="$(tracker_write_mark)"
  seen="$(failures_tracker_snapshot)"
  issues="$(failures_tracker_tree)" || issues=""
  prev_soft="${RALPH_SOFT_LIMIT_HIT:-0}"
  prev_timeout="${RALPH_SESSION_TIMEOUT:-}"

  failures__reslice_prompt "$ticket" "$plan" >"$plan.prompt"
  session_spawn "$plan.prompt" "$out" || rc=$?
  if [ "${RALPH_SOFT_LIMIT_HIT:-0}" = 1 ]; then
    rc=1
    failures__gap "$ticket: the re-slice session crossed the soft limit too"
  fi
  # The same refusal for the two deadlines of [23], and it carries more here than
  # it looks. A planning session the monitor cut short comes back a *success* —
  # `claude` traps TERM and exits 0 — carrying whatever it had written so far, and
  # half a plan that happens to parse is a plan: it would create tickets, drop the
  # acceptance criteria the missing half was carrying, and nothing could take that
  # back, the tracker being outside the rollback's reach on purpose.
  if [ -n "${RALPH_SESSION_TIMEOUT:-}" ]; then
    rc=1
    failures__gap "$ticket: the re-slice session ran out of time too (${RALPH_SESSION_TIMEOUT})"
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
    failures__gap "$ticket: the re-slice session's writes could not be rolled back — they are still in the tree"
  fi

  # And the frontier of what any of that can see, which no rollback reaches:
  # `.git/info/exclude` is in no tree ([30]). The second caller of this, and it is
  # the same argument as the second caller of gate_restore_tree — a planning
  # session is a session, it is never gated, so nothing else here would ever put
  # the rules back and the *next* iteration would pin the widened ones. Said out
  # loud rather than quietly undone: there is no gate on this path to carry a
  # finding, so the log line is the only trace a human gets.
  moved="$(gate_frontier)" || failures__say \
    "$ticket: the re-slice session moved the ignore frontier — $(printf '%s' "$moved" | tr '\n' ';')"

  # And the plan is refused whole if it wrote the tracker instead of returning
  # one. A session that writes the tracker has stepped past the only check that
  # cannot be redone afterwards, so the rest of what it produced is not worth
  # reading — whether it edited a ticket or created one.
  if ! failures_protect_tracker "$ticket" "$issues" "$mark"; then
    rm -f "$plan" "$plan.prompt" "$out" "$out.tokens"
    return 1
  fi
  if ! failures_quarantine_strays "$ticket" "$seen" "$mark"; then
    rm -f "$plan" "$plan.prompt" "$out" "$out.tokens"
    return 1
  fi

  if [ "$rc" != 0 ] || [ ! -s "$plan" ]; then
    failures__gap "$ticket: no re-slice plan came back"
    rm -f "$plan" "$plan.prompt" "$out" "$out.tokens"
    return 1
  fi

  headers="$(grep -n '^--- ticket:' "$plan" || true)"
  total="$(printf '%s' "$headers" | grep -c . || true)"
  if [ "${total:-0}" -lt 2 ]; then
    failures__gap "$ticket: the plan does not split anything ($total ticket(s))"
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
      failures__gap "$ticket: could not create the ticket for '$slug'"
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
    # Said on the ticket and not only on the receipt ([49]): the split below writes
    # a note when it is *incomplete*, and a human sorting the sink in the morning
    # could not tell a plan nothing could be made of from a plan that was never
    # written without opening the receipt. Same shape as its neighbour, so the two
    # read as the two halves of one answer.
    printf 'Re-slice refused: the plan was sound and not one of its tickets could be created — every write the tracker was asked for was refused. This ticket keeps its acceptance criteria, and nothing was split off it.\n' |
      tracker_append_note "$ticket" || true
    failures__gap "$ticket: the re-slice created nothing"
    return 1
  fi

  # A split missing one of its pieces has lost the acceptance criteria that piece
  # carried, and nothing can put them back — the tracker is outside the
  # rollback's reach on purpose. So the parent keeps its own criteria and goes to
  # a human, who can see from the note what did get created.
  if [ -n "$incomplete" ]; then
    printf 'Re-slice incomplete: only %s could be created out of the planned split. This ticket keeps its acceptance criteria.\n' \
      "$children" | tracker_append_note "$ticket" || true
    failures__gap "$ticket: the split is incomplete — leaving it to a human"
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
  RALPH_FAILURE_ACTION="re-sliced:$(printf '%s' "$children" | tr ' ' ',')"
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
      failures__gap "$ticket: a planned ticket has no slug or no title"
      return 1
    fi
    case "$body" in
      *'- [ ]'*) ;;
      *)
        failures__gap "$ticket: planned ticket '$slug' carries no acceptance criteria"
        return 1
        ;;
    esac

    child_surface="$(printf '%s\n' "$body" |
      sed -n 's/^\*\*Write-surface:\*\*[[:space:]]*//p; s/^Write-surface:[[:space:]]*//p' |
      head -1 | tr -d '`,' | awk '{ $1 = $1; print }')"
    if [ -z "$child_surface" ]; then
      failures__gap "$ticket: planned ticket '$slug' declares no write-surface"
      return 1
    fi
    for pattern in $child_surface; do
      if ! gate_in_surface "${pattern%/}" "$surface"; then
        failures__gap "$ticket: planned ticket '$slug' would write $pattern, outside the write-surface being split"
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
