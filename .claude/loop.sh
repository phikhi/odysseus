#!/usr/bin/env bash
# loop.sh — the ralph loop.
#
# One iteration is one task: scan the frontier, claim the lowest NN, spawn a
# fresh session for it, gate the result, mark it, journal it. Nothing is
# inherited between iterations — the tracker is re-read from scratch every
# time, so a crashed run and a cold start behave identically.
#
# Exit codes
#   0  the frontier was drained: this run ground everything it could
#   1  could not start — another run holds this feature's tracker, or this
#      working tree
#   2  cannot run: no config, or a config that would make the gate meaningless
#   4  stopped by a guard: stop requested, iteration cap, sterile run, a lock
#      this run no longer holds, or a rollback that could not put the tree back
#   5  nothing to grind: the frontier was already empty when the run started
#   6  the usage budget blocks this run: a weekly limit, or a session window
#      whose reset this run must not sleep to ([08])
#
# 6 is deliberately not 4. Every other guard is a decision this run took about
# itself; this one is a wall that lifts on its own at a known instant, which is
# the difference a one-shot successor is scheduled on ([09]).
#
# 0 and 5 are deliberately different. An AFK run that ground nothing because
# FEATURE points at the wrong tracker, or because every ticket is still in
# triage, must never be reported the same way as a night of finished work.
#
# Kept bash 3.2 compatible: the pack must run on a stock macOS shell.
set -euo pipefail

RALPH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RALPH_CONFIG="${RALPH_CONFIG:-$RALPH_DIR/ralph.config.sh}"
export RALPH_DIR

if [ ! -f "$RALPH_CONFIG" ]; then
  printf 'ralph: no config at %s — copy ralph.config.sh.example and edit it\n' \
    "$RALPH_CONFIG" >&2
  exit 2
fi

# shellcheck source=/dev/null
. "$RALPH_CONFIG"

# Libs are sourced in lexical order. An empty lib/ is not an error: the pack
# is usable before every module exists.
for _ralph_lib in "$RALPH_DIR"/lib/*.sh; do
  [ -e "$_ralph_lib" ] || continue
  # shellcheck source=/dev/null
  . "$_ralph_lib"
done
unset _ralph_lib

loop_log() {
  printf 'ralph: %s\n' "$*"
}

# ── graceful stop ────────────────────────────────────────────────────────────
#
# A kill asks the run to stop, it does not tear it down: the current iteration
# finishes, the ticket gets marked or given back, and the lock is released.
# Anything else would leave a claimed ticket nobody owns.

RALPH_STOP=0

loop_request_stop() {
  RALPH_STOP=1
  loop_log "stop requested — finishing the current iteration"
}

# ── the session ──────────────────────────────────────────────────────────────

# Everything the session gets. It inherits no conversation, so the prompt has
# to carry the task and say where to find the rest — the session rebuilds its
# own context by reading the repository.
#
# The language rules come from lib/lang.sh rather than being typed here, and that
# is the shape [17] wanted: the sentence a session is asked to follow and the
# check that keeps it live in one file, so the prompt cannot go on promising a
# guarantee the day the check moves. It says "checked" only where it is.
loop_session_prompt() {
  local ticket="$1"
  cat <<PROMPT
You are running one iteration of an autonomous delivery loop. You have exactly
one task: implement the ticket below, completely, and stop.

## Ticket: $ticket

$(tracker_read_ticket "$ticket")

## Where the rest of the context lives

- Domain language and constraints: CONTEXT.md
- Architecture decisions already taken: docs/adr/
- Lessons from earlier iterations: LEARNINGS.md
- Tracker conventions: docs/agents/

Read what you need. Nothing was inherited from a previous session.

## Rules

- Stay inside the ticket's declared write-surface.
$(lang_session_rules)
- Do not change the ticket's status, and do not edit any ticket at all.
  The loop marks them, after the gate. Both are checked, not just asked: the
  tickets are snapshotted before this session starts, any edit is restored from
  that snapshot, and an iteration that edited one cannot be green.
- Never stage or commit the tracker (\`.scratch/\`). It is the loop's own state,
  and a commit taken mid-iteration freezes it in a state that was never true.
- Finish the task in this session; there is no follow-up conversation.
PROMPT
}

# One iteration's session: the ticket prompt on a file, then the spawn every
# caller shares (see lib/session.sh — the failure policy re-slices through the
# same one, so neither can quietly become the less fresh of the two).
loop_spawn_session() {
  local ticket="$1" outfile="$2" promptfile="$2.prompt" rc=0
  loop_session_prompt "$ticket" >"$promptfile"
  session_spawn "$promptfile" "$outfile" || rc=$?
  rm -f "$promptfile"
  return "$rc"
}

# ── the run journal ──────────────────────────────────────────────────────────

# Append-only, one line per iteration, never read back to decide anything. The
# tracker stays the only authority; a line lost to a crash costs nothing.
loop_journal_append() {
  local ticket="$1" outcome="$2" turns="$3" cost="$4" tokens="$5"
  printf '%s\t%s\t%s\tturns=%s\tcost=%s\ttokens=%s\n' \
    "$(ralph_now)" "$ticket" "$outcome" "${turns:-0}" "${cost:-0}" "${tokens:-0}" \
    >>"$(ralph_feature_dir)/run.log"
}

# ── the loop ─────────────────────────────────────────────────────────────────

# Refuses to start rather than run on a configuration that cannot produce work.
# Everything here is checked before the lock is taken and before a single
# session is spawned: a gate that cannot prove anything turns the whole run into
# a stream of false greens, and a tracker that does not exist turns it into a
# night of silence reported as success.
loop_preflight() {
  local rc=0 dir

  if [ -z "${FEATURE:-}" ]; then
    printf 'ralph: FEATURE is empty — the run has no tracker to grind (see %s)\n' \
      "$RALPH_CONFIG" >&2
    rc=1
  else
    dir="$(ralph_feature_dir)"
    if [ ! -d "$dir" ]; then
      printf 'ralph: no tracker at %s — check FEATURE, or create the directory\n' "$dir" >&2
      rc=1
    fi
  fi

  if [ "$rc" = 0 ]; then
    loop__report_tracker_findings
  fi

  gate_preflight || rc=1
  # And the budget's own, here rather than inside the gate's: this one decides
  # whether a session is spawned at all, so a value that switches it off in
  # silence costs a subscription rather than a verdict ([08]).
  budget_preflight || rc=1
  # And what an isolated iteration needs before a ticket is claimed ([13]): a
  # commit to make a worktree from, and a MAX_PARALLEL that means something.
  concurrency_preflight || rc=1
  return "$rc"
}

# What is wrong with the tracker itself, said once at the start rather than
# discovered ticket by ticket in the middle of a night ([27]). Two tickets
# carrying one number do not break the tickets that carry it — they break every
# ticket whose `Blocked by:` names it, which drops out of a frontier that is a
# memoryless scan and never comes back, with nothing anywhere to say why.
#
# Said in `run.log` and not only on the console, because that is the file a human
# reads in the morning and the only one a receipt ([10]) will be able to read.
# The lines land before the locks are taken, so a run refused by another run's
# lock still records what it saw — one honest duplicate rather than a silence.
#
# It does not refuse the run: a duplicate number costs the tickets that point at
# it and nothing else, so stopping here would trade a whole night's work for a
# warning that reads the same in the morning either way.
loop__report_tracker_findings() {
  local subject outcome message
  while IFS="$(printf '\t')" read -r subject outcome message; do
    [ -n "$subject" ] || continue
    loop_log "$message"
    loop_journal_append "$subject" "$outcome" 0 0 0
  done <<FINDINGS
$(tracker_preflight)
FINDINGS
}

# ── one iteration ────────────────────────────────────────────────────────────

# Everything between a claimed ticket and a marked one, run as a process of its
# own with its working directory inside a worktree of its own ([13]).
#
# **A process and not a function call**, and that is the box [23] left this ticket
# to tick. Three of this pack's signals are shell variables a lib sets in its
# caller's shell — `RALPH_SOFT_LIMIT_HIT` ([04]), `RALPH_SESSION_TIMEOUT` ([23])
# and `RALPH_ROLLBACK_FAILED` ([34]) — so an iteration split across two shells
# would lose all three in silence: the pilot would read `rc=0` on a session a
# deadline cut, and gate work that had been interrupted. Keeping the *whole*
# iteration inside one shell is what keeps them readable exactly where they are
# read today, instead of replacing three variables with three channels that cross
# a process boundary and then keeping them in step.
#
# It is also what [36] needs. Both deadlines of this pack discover who armed them
# through their own parent link rather than being handed a pid, so the shell that
# forks a gate branch has to be the shell that wants the kill. Here that shell is
# this one for the session's deadline and for the gate's alike — an ordering that
# would break silently, and whose symptom would be a deadline that never fires.
#
# What crosses back to the pilot is bookkeeping and never a decision: the ticket is
# marked *here*, by the process that measured it. A pilot that marked on the
# strength of a file would be resolving tickets on a file a concurrent session can
# write — see the MAX_PARALLEL line in docs/frontiere-de-confiance.md.
#
# The pinned ignore rules, the worktree and the slot all belong to the pilot and
# are handed over: the pin has to be taken before the claim so that a machine which
# cannot give one refuses with nothing to unwind ([30]), and a worktree the pilot
# did not create is one it could not clean up after a child that died hard.
loop__iterate() {
  local ticket="$1" slot="$2" tree="$3" start="$4"
  local outfile base pre seen issues rc turns cost tokens outcome
  local tracker_written changed commit mark
  local RALPH_ROLLBACK_FAILED=0

  # **An iteration runs with errexit on, and it says so here rather than trusting
  # that it inherited it.** That is the posture the loop had before [13] — every
  # `|| true` in the failure policy is written against it, and each of them says in
  # its comment what it is buying — and this ticket switched it off by accident:
  # the pilot calls `loop__start` in an `|| stop_code=4` list, and bash suspends
  # errexit for the whole *dynamic extent* of a function invoked that way, the
  # iteration it forks included. Found by the mutation gate rather than by reading:
  # removing a `|| true` from `failures_handle` changed nothing at all, so an [07]
  # entry that had covered a real guarantee for a month reported VACUOUS.
  #
  # Restored rather than declared the new normal, and the choice is the pack's own
  # doctrine: an unguarded lib that returns non-zero is the case nobody knows
  # anything about, and the safe answer there is to cost the iteration — the ticket
  # comes back and the pilot says the iteration died without a verdict — not to
  # carry on and mark something. Every failure that decides anything is tested
  # explicitly below, so this only ever fires where nobody wrote a guard.
  #
  # `loop__start` therefore hands its refusal back through a variable instead of a
  # return status: a caller that tests the status is a caller that switches this
  # off again, three frames away from where it matters.
  set -e

  # And the other half of the posture: a signal must not tear an iteration down.
  # It finishes, marks its ticket and writes its outcome — [25]'s promise, read
  # where it now lives — while the pilot's own trap decides that nothing new
  # starts. Trapped here rather than inherited, because a subshell resets the
  # traps it caught and the default disposition of TERM is death: without this
  # line, a `kill -TERM` addressed to the process group (or any signal that
  # reaches a child rather than the pilot) takes the session and the gate branches
  # down mid-iteration, which is exactly the teardown [25] and [28] exist to
  # refuse. It is also what puts `proc_collect` back in the path it was written
  # for: bash cuts `wait` short the instant a *trapped* signal arrives, so without
  # a trap here the primitive is never the thing holding anything.
  trap 'loop_log "$1: stop requested — finishing this iteration"' TERM INT

  # Not `cd || exit`: this is a subshell, and the pilot reads the outcome file.
  cd "$tree" || {
    printf '%s\n' iteration-lost >"$slot/outcome"
    : >"$slot/done"
    return 0
  }

  outfile="$(ralph_feature_dir)/.session.$$.$(basename "$slot").jsonl"
  # `$$` is the pilot in every one of these shells — bash 3.2 has no BASHPID — so
  # the slot's name is what makes two concurrent streams two files. A single name
  # would have both sessions writing one stream, and the smart-zone net reading
  # the other one's tokens.
  # Both taken before the spawn, and they are not the same snapshot. The tree
  # is the state this session inherited, and what the scope-guard measures it
  # against. The commit is where the rollback puts HEAD back: a tree object is
  # not a commit, and a session that commits its work moves the branch.
  base="$(gate_tree_snapshot)" || base=""
  pre="$(git rev-parse HEAD 2>/dev/null)" || pre=""
  # The tracker as it stands before the session. Neither the scope-guard nor
  # the rollback can see it — both hold it as the loop's own state — so what a
  # session writes there is the one write nothing else would catch. Two shapes,
  # two snapshots: an id that appears is a ticket the session granted itself,
  # and a ticket file that moves is a session editing the very contract it is
  # about to be judged on.
  seen="$(failures_tracker_snapshot)"
  # Where the loop's own register of tracker writes stands, taken *before* the
  # snapshot below and not after: anything the pilot appends between the two is
  # then excluded from the guard rather than missed, and over-excluding costs a
  # ticket left alone where under-excluding costs a sibling's claim ([13]).
  mark="$(tracker_write_mark)"
  issues="$(failures_tracker_tree)" || issues=""
  rc=0
  loop_spawn_session "$ticket" "$outfile" || rc=$?

  turns="$(session_result_field "$outfile" num_turns)"
  cost="$(session_result_field "$outfile" total_cost_usd)"
  tokens="$(monitor_peak_tokens "$outfile")"
  # Read here because the stream is deleted at the end of this iteration, and
  # kept as three words rather than a file: what this says about the budget is
  # read twice — once below to classify this iteration, once by the pilot before
  # it schedules the next one ([08]).
  budget_stream_posture "$outfile" >"$slot/posture"

  # Before the gate reads a single field out of the tracker: the write-surface
  # it is about to judge against is a line in a file the session could just have
  # rewritten to `*`. Putting the tickets back first is what makes the guard
  # measure the contract as it stood when the session was spawned.
  tracker_written=0
  failures_protect_tracker "$ticket" "$issues" "$mark" || tracker_written=1

  # Tickets the session gave itself never reach the frontier. Separate from the
  # gate's verdict on purpose: the gate judges the code, and this judges an
  # entry in the loop's own state that no check downstream would question.
  failures_quarantine_strays "$ticket" "$seen" || true

  outcome=""
  if [ "$rc" -eq 0 ] && [ "${RALPH_SOFT_LIMIT_HIT:-0}" = 0 ] &&
    [ -z "${RALPH_SESSION_TIMEOUT:-}" ]; then
    # An edited tracker takes the green away whatever the branches said. The
    # restore is what let the scope-guard read the right contract at all, so a
    # session that edited it has to pay for the attempt — otherwise it retries
    # from a contract it partly wrote, which is the hole being closed.
    if gate_run "$ticket" "$base" && [ "$tracker_written" = 0 ]; then
      # Durable inside this worktree first, then folded onto the branch under a
      # guard nobody else holds. Two steps and not one, and the split is what
      # keeps a sequential run's history exactly what it was: at MAX_PARALLEL=1
      # the branch has not moved, so the fold is a fast-forward onto the very
      # commit this line wrote ([13]).
      #
      # **Neither step may fail quietly, and that is what [13] had to change
      # about [07].** The old comment here read "a git that refuses the commit
      # says so and the run carries on: the work is in the tree either way" —
      # true when the iteration ran in the tree the run was started in, and false
      # the moment it runs in a tree about to be destroyed. Left as it was, a
      # `main.lock` a crashed git forgot would have every ticket marked
      # `resolved` with nothing whatsoever behind it, which is this pack's own
      # definition of a false delivered ([35]). Found by the suite, not by
      # reasoning: `a commit git refuses is a warning, not the end of the run`
      # went red and said why.
      changed="$(gate_changed_files "$base" "${RALPH_GATE_TREE:-}")" || changed=""
      commit=""
      if failures_make_durable "$ticket" "$pre" "$base" "${RALPH_GATE_TREE:-}"; then
        commit="$(git rev-parse HEAD 2>/dev/null)" || commit=""
      fi
      if [ -n "$commit" ] &&
        concurrency_integrate "$ticket" "$start" "$commit" "$changed"; then
        tracker_mark_resolved "$ticket"
        outcome=resolved
      else
        # Green, and nowhere: this worktree is about to be thrown away, so work
        # that did not reach the branch is work that never happened. The ticket
        # goes back without a retry consumed — nothing about it was wrong — and
        # the pilot stops, because a git that refused this commit will refuse the
        # next one too and every iteration costs a session ([07] on a HEAD this
        # run does not recognise).
        outcome=not-integrated
        tracker_unclaim "$ticket"
      fi
    else
      outcome=gate-red
      # A gate that refused before judging anything is not a red check, and the
      # journal is where that difference has to survive the night ([35]): a
      # session answered, cost quota, and left the repository exactly as it
      # found it. Kept under `tracker-write` on purpose — a session that wrote
      # only the tracker delivered nothing *and* stepped past the one rule that
      # cannot be undone afterwards, and that is the one a human has to see.
      [ "${RALPH_GATE_NOTHING_DELIVERED:-0}" = 0 ] || outcome=nothing-delivered
      [ "$tracker_written" = 0 ] || outcome=tracker-write
      # Which kind of overflow it was decides what happens next: a stray
      # write into a neutral file is a too-narrow declaration and can be
      # retried, an overflow into another ticket's surface is a scoping
      # conflict only the discovery can settle. The failure policy consumes
      # this; the run says it out loud in the meantime.
      if [ -n "${RALPH_GATE_SCOPE_CLASS:-}" ]; then
        loop_log "scope overflow on $ticket: $RALPH_GATE_SCOPE_CLASS"
      fi
    fi
  elif [ "${RALPH_SOFT_LIMIT_HIT:-0}" = 1 ]; then
    outcome=over-soft-limit
    loop_log "session crossed the ${SOFT_LIMIT_TOKENS}-token soft limit (peak $tokens) — terminated"
  # Two outcomes and not one, because they are two different things to read in
  # the morning — and neither of them is over-soft-limit. A session cut for
  # context says the slice was too big, which is why that one is re-sliced; a
  # session that hung says nothing whatsoever about the ticket ([23]).
  elif [ "${RALPH_SESSION_TIMEOUT:-}" = stall ]; then
    outcome=session-stalled
    loop_log "session wrote nothing for ${SESSION_STALL_TIMEOUT}s — hung, terminated"
  elif [ "${RALPH_SESSION_TIMEOUT:-}" = wall ]; then
    outcome=session-timeout
    loop_log "session ran past the ${SESSION_TIMEOUT}s wall clock without finishing — terminated"
  else
    outcome=failed
  fi

  # "Budget?" before "failure", which is [08]'s classifier. Asked of the two
  # outcomes where **nothing was judged**, and of no other:
  #
  #   - a red gate is evidence that something was looked at and found wrong,
  #     and a subscription running out afterwards does not take that evidence
  #     away. Forgiving it would make a red gate free for any session willing
  #     to write one line into its own stream.
  #   - the soft limit and the two deadlines are facts this pack measured
  #     itself. A reason read out of the session's own stream is a claim, and a
  #     claim must not overwrite a measurement ([23]).
  #
  # It is asked of `nothing-delivered` as well as of a non-zero exit, which is
  # wider than the acceptance criterion and deliberately so: a session refused
  # for quota writes nothing, and [35] would bill that ticket a retry and send
  # a human to work out "why does this ticket make a session do nothing". The
  # answer would have been "the subscription was empty".
  case "$outcome" in
    failed | nothing-delivered)
      if budget_refused "$(cat "$slot/posture" 2>/dev/null || true)"; then
        outcome=budget-pause
        loop_log "$ticket: the session was refused for quota ($(awk '{ print $2 }' "$slot/posture" 2>/dev/null)) — not an attempt at this ticket"
      fi
      ;;
  esac

  case "$outcome" in
    resolved | not-integrated) ;;
    *)
      # Typed failures: the tree goes back to where the session found it, and
      # what happens to the ticket depends on what kind of failure this was —
      # re-slice, fresh retry, straight to the human sink, or, since [08], a
      # budget pause that gives the ticket back without spending one of its
      # retries. The rollback happens on that path too, and that is a decision
      # rather than an oversight: see failures_handle.
      #
      # It still runs in a worktree the pilot is about to destroy, and that is
      # not redundant: `failures_preserve_attempt` reads the tree it rolls back,
      # the re-slice needs a tree its planning session can work in, and a
      # rollback that refuses is what raises the flag below.
      failures_handle "$ticket" "$outcome" "$pre" "$base" "${RALPH_GATE_TREE:-}"
      ;;
  esac

  rm -f "$outfile" "$outfile.tokens"
  printf '%s\n' "${turns:-0}" >"$slot/turns"
  printf '%s\n' "${cost:-0}" >"$slot/cost"
  printf '%s\n' "${tokens:-0}" >"$slot/tokens"
  printf '%s\n' "${RALPH_ROLLBACK_FAILED:-0}" >"$slot/rollback-failed"
  printf '%s\n' "$outcome" >"$slot/outcome"
  # Last, and it is the pilot's proof that this iteration answered rather than
  # died. A pid alone cannot say it: bash reaps a background child on its own, so
  # the number can be handed to somebody else between the exit and the poll —
  # which is [36]'s lesson about identities, one layer up.
  : >"$slot/done"
  return 0
}

# ── the pilot ────────────────────────────────────────────────────────────────

# The lowest-numbered ticket on the frontier that may run beside what is already
# in flight, or nothing when every candidate would have to wait.
#
# Nothing is not the same as an empty frontier, and the caller has to tell them
# apart: a frontier full of tickets that all clash is a run with work left to do.
loop__next_ticket() {
  local inflight="$1" candidate
  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    concurrency_clashes "$candidate" "$inflight" && continue
    printf '%s\n' "$candidate"
    return 0
  done <<FRONTIER
$(select_frontier)
FRONTIER
  return 0
}

# The ids in flight, space-delimited, for the disjunction test and for the
# liveness sweep — which must not reclaim a sibling's claim ([12] via [13]).
loop__inflight_ids() {
  printf '%s' "${LOOP_SLOTS:-}" | awk -F'\t' 'NF > 1 { printf "%s ", $2 }'
}

loop__inflight_count() {
  printf '%s' "${LOOP_SLOTS:-}" | awk -F'\t' 'NF > 1 { n++ } END { print n + 0 }'
}

# Claim a ticket, give it a tree of its own, and fork the iteration into it.
#
# The refusal comes back in `LOOP_START_REFUSED` and never as a return status, and
# that is load-bearing rather than a style: a caller writing `loop__start … ||
# stop_code=4` suspends errexit for this function's whole dynamic extent — the
# iteration forked below included — and an iteration without errexit is one where
# every `|| true` in the failure policy has quietly stopped meaning anything. The
# ticket is given back here when there is anything to give back.
loop__start() {
  local ticket="$1" pin="$2" slot tree tip provisioned
  LOOP_START_REFUSED=0

  if ! tracker_claim "$ticket" "pid:$$"; then
    loop_log "could not claim $ticket — someone else has it"
    rm -rf "$pin"
    sterile=$((sterile + 1))
    return 0
  fi

  tree="$(concurrency_worktree_path)" || tree=""
  if [ -z "$tree" ] || ! tip="$(concurrency_worktree_add "$tree")"; then
    # Refused rather than run in the tree the run was started in. That fallback
    # is what this ticket exists to remove: the scope-guard, the rollback and the
    # durable commit are all repository-wide, so one iteration in the shared tree
    # beside another is the mutual destruction [22] refuses a second run over.
    loop_log "no isolated worktree for $ticket — stopping rather than grinding in the tree this run was started in"
    tracker_unclaim "$ticket"
    rm -rf "$pin" "$tree"
    LOOP_START_REFUSED=1
    return 0
  fi

  provisioned="$(concurrency_provision "$tree")"
  if [ "${provisioned:-0}" != 0 ]; then
    # A zone no check in this pack will ever see, named on every iteration rather
    # than once in a document ([24]).
    loop_log "$ticket: $provisioned path(s) provisioned into this iteration's worktree, which nothing here judges and no rollback undoes"
  fi

  slot="$(mktemp -d "${TMPDIR:-/tmp}/ralph-slot.XXXXXX")" || {
    loop_log "no slot for $ticket — stopping rather than running an iteration whose outcome nothing could read"
    concurrency_worktree_drop "$tree"
    tracker_unclaim "$ticket"
    rm -rf "$pin"
    LOOP_START_REFUSED=1
    return 0
  }

  iteration=$((iteration + 1))
  # Kept in the slot rather than read off the counter when the iteration comes
  # back: the pilot's counter says how many have been *started*, and with more
  # than one in flight that is no longer the number of the one that just
  # finished. A morning log whose "iteration 3 started" and "iteration 3 -> …"
  # named two different tickets would be worse than no number at all.
  printf '%s\n' "$iteration" >"$slot/n"
  loop_log "iteration $iteration: $ticket"
  # A session is about to run, so the budget's "twice in a row" is over.
  budget_paused=0
  RALPH_IGNORE_PIN="$pin"
  loop__iterate "$ticket" "$slot" "$tree" "$tip" &
  LOOP_SLOTS="$LOOP_SLOTS$!	$ticket	$slot	$tree	$pin
"
  return 0
}

# Collect whatever has finished. With a 1 it waits until something does, which is
# what the pilot does when it has no free slot and nothing it may schedule.
#
# Finished is two questions and not one, and the second is [36]'s. The marker file
# is the child's own last act, so it is definitive; `kill -0` covers the child that
# died before writing one. Neither alone is enough — a pid bash has already reaped
# can be handed to another process, and a child killed outright never writes a
# marker.
loop__reap() {
  local block="$1" kept found pid ticket slot tree pin
  while :; do
    kept=''
    found=0
    while IFS="$(printf '\t')" read -r pid ticket slot tree pin; do
      [ -n "$pid" ] || continue
      if [ -e "$slot/done" ] || ! kill -0 "$pid" 2>/dev/null; then
        proc_collect "$pid" || true
        loop__finish "$ticket" "$slot" "$tree" "$pin"
        found=1
        continue
      fi
      kept="$kept$pid	$ticket	$slot	$tree	$pin
"
    done <<SLOTS
$LOOP_SLOTS
SLOTS
    LOOP_SLOTS="$kept"
    [ "$block" = 1 ] || return 0
    [ "$found" = 0 ] || return 0
    [ -n "$LOOP_SLOTS" ] || return 0
    # Guarded, and not out of habit: this shell runs with errexit on, so a `sleep`
    # that comes back non-zero — a signal delivered to it rather than to the run —
    # would take the pilot down here, in the one place it is holding iterations it
    # has not collected yet. Probed while writing the stop test, which killed this
    # very `sleep` by accident and got a run that exited 143 with two sessions
    # still writing.
    sleep 0.2 || true
  done
}

# One finished iteration, read back into the run's own bookkeeping.
#
# It writes `sterile`, `budget_posture` and `stop_code`, which are locals of
# `loop_main` — the same arrangement `gate__aggregate` documents for the gate's
# verdicts, and for the same reason: these have to be the run's counters and not a
# copy, so this may never be called from a subshell or a pipeline.
loop__finish() {
  local ticket="$1" slot="$2" tree="$3" pin="$4" outcome posture

  outcome="$(cat "$slot/outcome" 2>/dev/null || true)"
  if [ -z "$outcome" ]; then
    # The child died without answering — killed, out of memory, a machine that
    # went away. Nothing judged this ticket and nothing marked it, so it is given
    # back rather than left claimed by a pid that is still alive: the liveness
    # sweep exempts this run's own ids ([13]), so nobody else would ever free it.
    outcome=iteration-lost
    if [ "$(tracker_field "$ticket" Status 2>/dev/null || true)" = claimed ]; then
      tracker_unclaim "$ticket"
    fi
    loop_log "$ticket: the iteration died without a verdict — given back to the frontier"
  fi

  posture="$(cat "$slot/posture" 2>/dev/null || true)"
  [ -z "$posture" ] || budget_posture="$posture"

  if [ "$outcome" = resolved ]; then
    sterile=0
  else
    sterile=$((sterile + 1))
  fi

  loop_journal_append "$ticket" "$outcome" \
    "$(cat "$slot/turns" 2>/dev/null || true)" \
    "$(cat "$slot/cost" 2>/dev/null || true)" \
    "$(cat "$slot/tokens" 2>/dev/null || true)"
  loop_log "iteration $(cat "$slot/n" 2>/dev/null || printf '?'): $ticket -> $outcome"

  # The pin dies with the iteration: the next one is entitled to the rules it is
  # handed, including a rule this iteration legitimately delivered. Leaked on a
  # kill, like the gate's own temporary directory — a witness repository holds
  # copies of ignore rules and nothing else.
  rm -rf "$pin"
  concurrency_worktree_drop "$tree"

  # A rollback that could not put the tree back ends the run, and this is the
  # decision [34] was opened to take — re-taken here rather than inherited, which
  # is what that ticket asked for. Isolation *does* close the laundering it was
  # opened for: this worktree is thrown away, so nothing of it becomes the next
  # iteration's baseline. It is kept all the same, because a rollback fails for
  # reasons that are not local to one tree — a `$TMPDIR` swept from under the run,
  # a pin destroyed, a snapshot that refuses — and every one of those is about to
  # be true for the sibling running beside it. Stopping costs a run where
  # isolation would have sufficed; carrying on spends a night of sessions on an
  # instrument that is already closed.
  if [ "$(cat "$slot/rollback-failed" 2>/dev/null || echo 0)" = 1 ]; then
    loop_log "the rollback could not put this iteration's tree back — stopping rather than grinding on an instrument that is already closed"
    stop_code=4
  fi
  # And the fold that could not reach the branch, for the reason written where it
  # is decided: green work that stayed in a throwaway tree is work that did not
  # happen, and the next iteration would spend a session to find that out again.
  if [ "$outcome" = not-integrated ]; then
    loop_log "$ticket: the gate was green and the work did not reach the branch — stopping"
    stop_code=4
  fi
  rm -rf "$slot"
  return 0
}

loop_main() {
  cd "$(ralph_project_root)"

  loop_preflight || exit 2

  # The coarser lock first: this run is refused whatever feature it was pointed
  # at, because what a second run destroys here is not the tracker but the tree.
  # Taken after the preflight, which is what guarantees there is a git directory
  # to put it in.
  tree_lock_acquire || exit 1
  run_lock_acquire || exit 1
  # Replaces the locks' own signal traps: stopping is a decision the loop
  # makes between iterations, not an immediate teardown. The EXIT trap they
  # installed survives, and it is what releases both.
  trap 'loop_request_stop' TERM INT

  loop_log "run start (feature=$FEATURE backend=$TRACKER_BACKEND model=$MODEL)"

  # What the runs before this one left outside the repository. Said here rather
  # than in a document, for the reason every zone nobody guards is said out loud
  # ([24]): a human reading the log in the morning sees it instead of having to
  # remember it exists. Nothing here removes anything — see gate_leftovers.
  local leftovers
  if leftovers="$(gate_leftovers)"; then loop_log "$leftovers"; fi
  # And what they left *inside* it: a worktree a killed run never removed stays
  # registered in the common git directory, where every later `git worktree` call
  # carries it. Counted and not pruned, for the reason above — this pack locks a
  # working tree and not a machine, so a registration a second old belongs to a run
  # that is very much alive ([13]).
  if leftovers="$(concurrency_leftovers)"; then loop_log "$leftovers"; fi

  # The register of what this loop writes in the tracker itself ([13]). It has to
  # be a file rather than a variable because its writers are different processes —
  # the pilot claims, an iteration marks — and it lives in `$TMPDIR` for the reason
  # the ignore pin does: out of the tree, so no write-surface reaches it. Leaked on
  # a kill like the pin and the gate's directory; `gate_leftovers` counts it.
  #
  # Never exported, and that one keyword is the whole of [40]. Every writer of this
  # register is a *subshell of this shell* — an iteration is `loop__iterate … &`, a
  # gate branch and a re-slice are subshells under it — and a subshell inherits a
  # variable that was never exported. The only three processes this pack starts
  # outside a subshell are `claude` and the project's own `TEST_CMD` and
  # `TYPECHECK_CMD`, and none of them has any business with this file. So the
  # export served no caller here, and it served the session: a name in `$TMPDIR`
  # handed to `claude` in its environment is exactly as writable as a file in the
  # tree, and it does not even have a write-surface to cross. One `printf` of its
  # own id and `failures_protect_tracker` skips the ticket the session just
  # rewrote — it restores nothing, says nothing, and the gate then reads the
  # write-surface the session gave itself. Out of the tree was never the property
  # that mattered; **who knows the name** is. Same treatment as `RALPH_IGNORE_PIN`
  # ([30]), which is the same secret in the same directory, for the same reason.
  RALPH_TRACKER_LOG="$(mktemp "${TMPDIR:-/tmp}/ralph-slot.writes.XXXXXX")" ||
    RALPH_TRACKER_LOG=''

  local iteration=0 sterile=0 ticket reclaimed rid rdisposition
  local budget_posture='' budget_paused=0 span pin
  local stop_code=''
  local RALPH_IGNORE_PIN=''
  LOOP_SLOTS=''

  while :; do
    # Whatever finished since the last pass, read back into this run's counters
    # before a single decision is taken on them. Non-blocking: the pilot has
    # scheduling to do, and blocking is what it does when it cannot.
    loop__reap 0

    if [ -z "$stop_code" ] && [ "$RALPH_STOP" = 1 ]; then
      loop_log "stopped on request after $iteration iterations"
      stop_code=4
    fi
    if [ -z "$stop_code" ] && [ "$iteration" -ge "$ITER_CAP" ]; then
      loop_log "iteration cap reached ($ITER_CAP) — stopping"
      stop_code=4
    fi
    if [ -z "$stop_code" ] && [ "$sterile" -ge "$STERILE_K" ]; then
      loop_log "sterile run: $sterile iterations resolved nothing — stopping"
      stop_code=4
    fi
    # The lock is taken once, at the start, and it lives in the tracker — the one
    # part of the loop's state a session can reach. Losing it is not a nuisance: a
    # second run starts alongside this one, and two runs grinding one repository
    # roll back and commit over each other. Stopping loudly is the only honest
    # answer; carrying on would report a night of work another run may have
    # overwritten. The compare-and-swap on the durable commit is what makes that
    # overwrite impossible in the window this check cannot cover.
    if [ -z "$stop_code" ] && ! run_lock_is_ours; then
      loop_log "the run lock is gone or not ours any more after $iteration iterations — stopping rather than grinding beside another run"
      stop_code=4
    fi
    # And the same question for the tree, asked separately because the answer can
    # differ. `.git/` is out of reach of a `git add -A`, a `git clean` and an
    # `rm -rf .scratch` — not of a session that deletes the lock outright. Losing
    # it means a second run can start on this tree, which is exactly what the
    # per-feature lock above does not prevent.
    if [ -z "$stop_code" ] && ! tree_lock_is_ours; then
      loop_log "the working-tree lock is gone or not ours any more after $iteration iterations — stopping rather than grinding beside another run"
      stop_code=4
    fi

    # Stopping is a decision about what to *start*, never a teardown: the
    # iterations already in flight are finished and marked first. That is [25]'s
    # promise — "the current iteration finishes" — read at the only place it can
    # still mean something once there is more than one of them. Exiting here would
    # leave a `claude` per slot writing into a stream this process is about to
    # delete, and spending quota until morning ([28]).
    if [ -n "$stop_code" ]; then
      [ -n "$LOOP_SLOTS" ] || break
      loop__reap 1
      continue
    fi

    # A claim whose owner is gone is not a ticket somebody is working on. Swept
    # before the frontier is read, and on every iteration rather than once at
    # startup, because the frontier is a memoryless scan and this is part of
    # deriving it. Without it a run killed mid-session took its ticket out of the
    # frontier for good and the next run reported `exit 0` — "this run ground
    # everything it could" — which was true and told nobody that a ticket had
    # quietly left the board. The disposition is journalled: a reclaim that
    # consumed a retry, or one that ran out of them, has to be visible in the
    # morning without reading the tracker ticket by ticket.
    #
    # The ids in flight go with it, and that is what makes the sweep safe here
    # ([13]): a sibling's claim is indistinguishable from anybody else's from the
    # outside, and `CLAIM_TTL` would otherwise become a ceiling on how long a
    # session may run — the backstop reclaims a claim older than the TTL even when
    # its owner answers, which is its job against a recycled pid and a theft when
    # the owner is this very run.
    reclaimed="$(claim_reclaim_stale "$(loop__inflight_ids)")"
    if [ -n "$reclaimed" ]; then
      printf '%s\n' "$reclaimed" | while read -r rid rdisposition; do
        [ -n "$rid" ] || continue
        loop_log "reclaimed $rid from an owner that is gone -> $rdisposition"
        loop_journal_append "$rid" "reclaimed-$rdisposition" 0 0 0
      done
    fi

    # No free slot: there is nothing to decide until one of them comes back.
    concurrency_cap
    if [ "$(loop__inflight_count)" -ge "$CONCURRENCY_CAP" ]; then
      loop__reap 1
      continue
    fi

    # What is left of the subscription, asked before a ticket is claimed and
    # never after ([08]). Before, because a run that paused holding a claim would
    # sit on it past CLAIM_TTL and have it reclaimed from under itself — five
    # hours of window against a ninety-minute backstop ([12]) — and because the
    # only honest way to not spend a session is to not spawn it.
    #
    # It is asked with the last session's in-band posture, which is the cheapest
    # correction there is: the event arrives in every stream, and a session that
    # was told it is blocked is a reason to ask the endpoint again rather than
    # believe a cache from before the wall.
    #
    # Still in the pilot's own shell, which is what keeps the 180 s cache alive:
    # it is a variable of this process and never a file, because a file would be
    # one the judged session can write ([08]). An iteration in a worktree does not
    # share it, and does not have to — nothing below the pilot decides to spawn.
    if ! budget_check "$budget_posture"; then
      if [ "${RALPH_BUDGET_WINDOW:-}" != five_hour ]; then
        # A weekly limit is days out. Sleeping in-process for days is what the
        # one-shot successor of [09] exists to replace, and until it lands the
        # honest answer is a stop a human can read in the morning.
        loop_log "the weekly usage limit blocks this run (${RALPH_BUDGET_WINDOW:-unknown}, said by the ${RALPH_BUDGET_SOURCE:-endpoint}) — stopping rather than holding a process open for days; a one-shot successor at the reset belongs to [09]"
        loop_journal_append - budget-wall 0 0 0
        stop_code=6
        continue
      fi
      if [ "$budget_paused" = 1 ]; then
        # Twice in a row with no session in between: this run already slept to
        # the reset this same signal named. Sleeping again on a signal that is
        # not moving is how an AFK night is spent without a line to show for it.
        loop_log "the session window still says blocked after a pause that ran all the way to its reset — stopping rather than waiting again on a signal that is not moving"
        loop_journal_append - budget-wall 0 0 0
        stop_code=4
        continue
      fi
      if ! span="$(budget_span "${RALPH_BUDGET_RESET:-}")"; then
        loop_log "the session window is blocked and its reset is not an instant this run can wait for (${RALPH_BUDGET_RESET:-none}, cap ${BUDGET_MAX_PAUSE}s) — stopping rather than sleeping a span nobody measured"
        loop_journal_append - budget-wall 0 0 0
        stop_code=6
        continue
      fi
      loop_log "the session window is spent — pausing ${span}s until it resets, then carrying on"
      loop_journal_append - budget-pause 0 0 0
      budget_paused=1
      # Spent with the pause: kept, it would answer "blocked" for the rest of the
      # night every time the endpoint has nothing to say.
      budget_posture=''
      if ! budget_pause "$span"; then
        loop_log "stopped on request during a budget pause after $iteration iterations"
        stop_code=4
      fi
      continue
    fi

    # The lowest-numbered ticket that may run beside what is in flight. Nothing
    # here is not the same as an empty frontier: a frontier whose every ticket
    # shares a write-surface with a running one is a run with work left to do, and
    # it waits instead of reporting a night finished.
    ticket="$(loop__next_ticket "$(loop__inflight_ids)")"
    if [ -z "$ticket" ]; then
      if [ -n "$LOOP_SLOTS" ]; then
        loop__reap 1
        continue
      fi
      rm -f "${RALPH_TRACKER_LOG:-}"
      if [ "$iteration" -eq 0 ]; then
        loop_log "nothing to grind: the frontier was empty from the start (feature=$FEATURE backend=$TRACKER_BACKEND)"
        exit 5
      fi
      loop_log "frontier empty after $iteration iterations"
      exit 0
    fi

    # The project's ignore rules as they stand, pinned for the length of this
    # iteration: every snapshot below is taken through *these* and not through
    # whatever the session leaves behind, so a session cannot widen the blind spot
    # it is judged through ([30]). A ticket may still add an ignore rule — the rule
    # simply counts from the next iteration, the way its write-surface has counted
    # from the spawn since [21].
    #
    # Taken before the claim rather than beside the other three snapshots, so that
    # a machine which cannot give the run a pin refuses the iteration with nothing
    # to unwind. Refusing is the point: the pin is what the visibility of every
    # check rests on, and a guard that cannot see must not pass.
    #
    # One per iteration and not one per run, which is what gives a ticket the right
    # to deliver an ignore rule for the *next* one ([30]). Two iterations in flight
    # therefore hold two witnesses taken at two instants, and each is judged through
    # the rules its own spawn was handed — which is the intended answer and not a
    # coincidence: it is the same statement the write-surface has made since [21].
    # It is taken here, in the pilot, and handed to the iteration by inheritance:
    # a shell variable and never a file, because a file beside the tracker would be
    # one the judged session can write.
    if ! RALPH_IGNORE_PIN="$(gate_ignore_pin)"; then
      loop_log "cannot pin this project's ignore rules — refusing to grind a frontier whose visibility nothing can vouch for"
      stop_code=4
      continue
    fi
    pin="$RALPH_IGNORE_PIN"

    # Not `loop__start … || stop_code=4`: testing the status here would switch
    # errexit off inside the iteration this call forks. See loop__start.
    loop__start "$ticket" "$pin"
    [ "${LOOP_START_REFUSED:-0}" = 0 ] || stop_code=4
  done

  rm -f "${RALPH_TRACKER_LOG:-}"
  exit "${stop_code:-0}"
}

loop_main "$@"
