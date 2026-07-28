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
#   1  could not start — another run holds the lock
#   2  cannot run: no config, or a config that would make the gate meaningless
#   4  stopped by a guard: stop requested, iteration cap, or sterile run
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
- Durable prose (docs, comments, commits) is written in ${LANG_ARTIFACT:-en}.
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

# Pull one field out of the final `result` event. Deliberately not jq: the pack
# promises to run with nothing installed, and these fields are flat scalars.
#
# A session that dies without emitting anything — crash, OOM, kill — is a
# normal outcome here, so a missing result is empty, never an error.
loop_result_field() {
  local file="$1" key="$2" line
  line="$(grep '"type":"result"' "$file" 2>/dev/null | tail -1)" || line=""
  [ -n "$line" ] || return 0
  printf '%s' "$line" |
    sed -n "s/.*\"$key\":\"\{0,1\}\([^,\"}]*\)\"\{0,1\}.*/\1/p"
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

  gate_preflight || rc=1
  return "$rc"
}

loop_main() {
  cd "$(ralph_project_root)"

  loop_preflight || exit 2

  run_lock_acquire || exit 1
  # Replaces the lock's own signal traps: stopping is a decision the loop
  # makes between iterations, not an immediate teardown.
  trap 'loop_request_stop' TERM INT

  loop_log "run start (feature=$FEATURE backend=$TRACKER_BACKEND model=$MODEL)"

  local iteration=0 sterile=0 ticket outfile base pre seen issues tree rc
  local turns cost tokens outcome tracker_written

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

    if ! tracker_claim "$ticket" "pid:$$"; then
      loop_log "could not claim $ticket — someone else has it"
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

    turns="$(loop_result_field "$outfile" num_turns)"
    cost="$(loop_result_field "$outfile" total_cost_usd)"
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
    if [ "$rc" -eq 0 ] && [ "${RALPH_SOFT_LIMIT_HIT:-0}" = 0 ]; then
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
    loop_log "iteration $iteration: $ticket -> $outcome"
  done
}

loop_main "$@"
