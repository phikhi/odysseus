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

  local iteration=0 sterile=0 ticket outfile base pre seen issues tree rc
  local turns cost tokens outcome tracker_written reclaimed rid rdisposition
  local RALPH_IGNORE_PIN='' RALPH_ROLLBACK_FAILED=0

  while :; do
    if [ "$RALPH_STOP" = 1 ]; then
      loop_log "stopped on request after $iteration iterations"
      exit 4
    fi
    if [ "$iteration" -ge "$ITER_CAP" ]; then
      loop_log "iteration cap reached ($ITER_CAP) — stopping"
      exit 4
    fi
    if [ "$sterile" -ge "$STERILE_K" ]; then
      loop_log "sterile run: $sterile iterations resolved nothing — stopping"
      exit 4
    fi
    # The lock is taken once, at the start, and it lives in the tracker — the one
    # part of the loop's state a session can reach. Losing it is not a nuisance: a
    # second run starts alongside this one, and two runs grinding one repository
    # roll back and commit over each other. Stopping loudly is the only honest
    # answer; carrying on would report a night of work another run may have
    # overwritten. The compare-and-swap on the durable commit is what makes that
    # overwrite impossible in the window this check cannot cover.
    if ! run_lock_is_ours; then
      loop_log "the run lock is gone or not ours any more after $iteration iterations — stopping rather than grinding beside another run"
      exit 4
    fi
    # And the same question for the tree, asked separately because the answer can
    # differ. `.git/` is out of reach of a `git add -A`, a `git clean` and an
    # `rm -rf .scratch` — not of a session that deletes the lock outright. Losing
    # it means a second run can start on this tree, which is exactly what the
    # per-feature lock above does not prevent.
    if ! tree_lock_is_ours; then
      loop_log "the working-tree lock is gone or not ours any more after $iteration iterations — stopping rather than grinding beside another run"
      exit 4
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
    reclaimed="$(claim_reclaim_stale)"
    if [ -n "$reclaimed" ]; then
      printf '%s\n' "$reclaimed" | while read -r rid rdisposition; do
        [ -n "$rid" ] || continue
        loop_log "reclaimed $rid from an owner that is gone -> $rdisposition"
        loop_journal_append "$rid" "reclaimed-$rdisposition" 0 0 0
      done
    fi

    ticket="$(select_next_ticket)"
    if [ -z "$ticket" ]; then
      if [ "$iteration" -eq 0 ]; then
        loop_log "nothing to grind: the frontier was empty from the start (feature=$FEATURE backend=$TRACKER_BACKEND)"
        exit 5
      fi
      loop_log "frontier empty after $iteration iterations"
      exit 0
    fi

    iteration=$((iteration + 1))

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
    if ! RALPH_IGNORE_PIN="$(gate_ignore_pin)"; then
      loop_log "cannot pin this project's ignore rules — refusing to grind a frontier whose visibility nothing can vouch for"
      exit 4
    fi

    if ! tracker_claim "$ticket" "pid:$$"; then
      loop_log "could not claim $ticket — someone else has it"
      rm -rf "$RALPH_IGNORE_PIN"
      RALPH_IGNORE_PIN=''
      sterile=$((sterile + 1))
      continue
    fi

    loop_log "iteration $iteration: $ticket"
    outfile="$(ralph_feature_dir)/.session.$$.jsonl"
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
    issues="$(failures_tracker_tree)" || issues=""
    rc=0
    loop_spawn_session "$ticket" "$outfile" || rc=$?

    turns="$(session_result_field "$outfile" num_turns)"
    cost="$(session_result_field "$outfile" total_cost_usd)"
    tokens="$(monitor_peak_tokens "$outfile")"

    # Before the gate reads a single field out of the tracker: the write-surface
    # it is about to judge against is a line in a file the session could just have
    # rewritten to `*`. Putting the tickets back first is what makes the guard
    # measure the contract as it stood when the session was spawned.
    tracker_written=0
    failures_protect_tracker "$ticket" "$issues" || tracker_written=1

    # Tickets the session gave itself never reach the frontier. Separate from the
    # gate's verdict on purpose: the gate judges the code, and this judges an
    # entry in the loop's own state that no check downstream would question.
    failures_quarantine_strays "$ticket" "$seen" || true

    outcome=""
    tree=""
    if [ "$rc" -eq 0 ] && [ "${RALPH_SOFT_LIMIT_HIT:-0}" = 0 ] &&
      [ -z "${RALPH_SESSION_TIMEOUT:-}" ]; then
      # An edited tracker takes the green away whatever the branches said. The
      # restore is what let the scope-guard read the right contract at all, so a
      # session that edited it has to pay for the attempt — otherwise it retries
      # from a contract it partly wrote, which is the hole being closed.
      if gate_run "$ticket" "$base" && [ "$tracker_written" = 0 ]; then
        # Durable before the next iteration starts: everything the gate just
        # approved gets committed, so the pre-session commit a later iteration
        # rolls back to is really the state before that iteration.
        #
        # A git that refuses the commit says so and the run carries on: the work
        # is in the tree either way, and the precise rollback does not touch what
        # it did not put there. Stopping the run here would trade a warning for a
        # night of no work at all.
        failures_make_durable "$ticket" "$pre" "$base" "${RALPH_GATE_TREE:-}" || true
        tracker_mark_resolved "$ticket"
        outcome=resolved
        sterile=0
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
        tree="${RALPH_GATE_TREE:-}"
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

    if [ "$outcome" != resolved ]; then
      # Typed failures: the tree goes back to where the session found it, and
      # what happens to the ticket depends on what kind of failure this was —
      # re-slice, fresh retry, or straight to the human sink. The budget pause
      # is the one type still missing, and it belongs to the budget ticket:
      # a non-zero exit has to be tested "budget?" before it counts as failure.
      failures_handle "$ticket" "$outcome" "$pre" "$base" "$tree"
      sterile=$((sterile + 1))
    fi

    loop_journal_append "$ticket" "$outcome" "$turns" "$cost" "$tokens"
    rm -f "$outfile" "$outfile.tokens"
    # The pin dies with the iteration: the next one is entitled to the rules it is
    # handed, including a rule this iteration legitimately delivered. Leaked on a
    # kill, like the gate's own temporary directory — a witness repository holds
    # copies of ignore rules and nothing else.
    rm -rf "$RALPH_IGNORE_PIN"
    RALPH_IGNORE_PIN=''
    loop_log "iteration $iteration: $ticket -> $outcome"

    # A rollback that could not put the tree back ends the run, and this is the
    # decision [34] was opened to take. Everything upstream of it worked: the
    # snapshot refused rather than guess, the scope-guard refused to pass a tree it
    # could not read, the rollback said out loud that it undid nothing. What none
    # of them can do is stop the *next* iteration from snapshotting that tree as
    # its own pre-session baseline — after which what the session left is no longer
    # anybody's change, and the ticket that inherits it goes green carrying it.
    # One retry is the price [30] wrote down as acceptable; a laundered write is
    # not, and it is exactly the false green this pack exists to refuse.
    #
    # Stopping rather than carrying the finding forward, and the reason is
    # structural rather than a preference: nothing is inherited between iterations
    # here on purpose, so a crashed run and a cold start behave identically. A flag
    # saying "the tree is dirty in a way nobody can describe" would have to survive
    # in the tracker to mean anything, and it would be lost in the one case that
    # matters. The cost is written down and accepted: a session that closes the
    # instrument takes the run down with it, which is what `exit 4` already does
    # for a pin that cannot be taken. The ticket has been marked or given back
    # before we get here, so a human reads one line and starts from a known state.
    if [ "${RALPH_ROLLBACK_FAILED:-0}" = 1 ]; then
      loop_log "the rollback could not put the working tree back — stopping rather than letting the next iteration inherit a tree nothing here can describe"
      exit 4
    fi
  done
}

loop_main "$@"
