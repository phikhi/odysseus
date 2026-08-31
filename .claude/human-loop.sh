#!/usr/bin/env bash
# human-loop.sh — the human sink, drained.
#
# The second loop, and the sister of the ralph loop rather than a tool beside it.
# The AFK loop escalates: a gate that stayed red, a session that hung, a scoping
# conflict, a ticket a session wrote into the tracker. Every one of those lands
# on `Status: ready-for-human` and nothing has ever taken it off again. This is
# what takes it off: it walks the sink in the order that unblocks the most work,
# puts the right question in front of a human with the evidence that exists,
# opens the routed session when the human asks for one, and re-injects the result
# on the frontier where a fresh session and the whole gate will judge it.
#
# **Nothing here ever marks a ticket resolved except a sign-off.** That is the
# anti-false-green criterion of [16] and the reason this file exists at all: code
# a human fixed is code no gate has seen, and a sink that could resolve would be a
# way around the gate that took thirty tickets to build. `router_sign_off` is the
# one path to `resolved`, and it refuses any ticket the loop escalated for any
# other reason.
#
# **And nothing here ever arms a successor** ([09]). `SCHEDULER` and
# `WEEKLY_RESUME` belong to the AFK path and to it alone: a successor queued while
# a human is working this tree would wake a run under their hands, which is the
# mutual destruction [22] refuses, reached through a door nobody watches. Until
# now what held that was a fact of structure — `loop__arm_successor` lives in
# `loop.sh` and nothing else calls it. It is now also a refusal: this file names
# no scheduler function, and `test/human-loop.bats` says so.
#
# Exit codes
#   0  the sink is empty: everything in it was drained
#   1  could not start — a run, or another human, holds this feature's tracker or
#      this working tree
#   2  cannot run: no config, a PATH nothing here can witness, or no tracker
#   3  stopped with tickets still in the sink — the human quit, or stdin ended
#   4  stopped by a guard: one of the two locks this drain took is gone, or is
#      not ours any more ([57])
#   5  nothing to drain: the sink was empty when this started
#
# 0 and 5 are different for the reason they are different in `loop.sh`: a drain
# that found nothing because `FEATURE` points at the wrong tracker must not be
# reported as a sink emptied.
#
# 4 is 4 for the same reason, from the other end: it is the number `loop.sh`
# gives a guard that stopped a run, a lost lock included, and the two entry
# points lose a lock for the same reasons and owe an operator the same word for
# it. It is deliberately not 3. A human who quit and a drain that stopped because
# something took its lock out from under it leave the sink looking identical, and
# the second is the one nobody may read as "they will come back to it".
#
# Kept bash 3.2 compatible, like the rest of the pack.
set -euo pipefail

# Parameter expansion and not `dirname`, for the reason `loop.sh` spells out at
# the same place ([52]): `gate_path_preflight` refuses a `PATH` this pack cannot
# witness *before* the pack runs a single program by name, and a `dirname` here
# would be that program — resolved through the very PATH being refused, before
# anything could say so. This file is the pack's second entry point, so it is the
# second place that question is asked, and it has the same answer. `cd` and `pwd`
# are builtins.
_ralph_src="${BASH_SOURCE[0]}"
case "$_ralph_src" in
  */*) _ralph_src="${_ralph_src%/*}" ;;
  *) _ralph_src='.' ;;
esac
RALPH_DIR="$(cd "$_ralph_src" && pwd)"
unset _ralph_src
RALPH_CONFIG="${RALPH_CONFIG:-$RALPH_DIR/ralph.config.sh}"
export RALPH_DIR

if [ ! -f "$RALPH_CONFIG" ]; then
  printf 'ralph: no config at %s — copy ralph.config.sh.example and edit it\n' \
    "$RALPH_CONFIG" >&2
  exit 2
fi

# shellcheck source=/dev/null
. "$RALPH_CONFIG"

for _ralph_lib in "$RALPH_DIR"/lib/*.sh; do
  [ -e "$_ralph_lib" ] || continue
  # shellcheck source=/dev/null
  . "$_ralph_lib"
done
unset _ralph_lib

human_loop_log() {
  printf 'ralph: %s\n' "$*"
}

# ── signals ──────────────────────────────────────────────────────────────────
#
# Both locks install these when they are taken; they are re-installed by hand
# after every session, and that is not tidiness.
#
# A routed session runs in the foreground of this terminal, so a Ctrl-C meant for
# it is delivered to the whole foreground process group — this shell included.
# With the locks' own handler in place, the human who wanted to end a
# conversation would end the drain instead, halfway through a sink.
#
# So the handler is swapped for `:` around a session, and `:` rather than `''` is
# the whole of it: bash resets a *handled* signal to its default in a child and
# leaves an *ignored* one ignored. `trap '' INT` would have made `claude` itself
# deaf to Ctrl-C, which is worse than the defect it was fixing.
human_loop__arm_signals() {
  trap 'state_locks_release; exit 130' INT
  trap 'state_locks_release; exit 143' TERM
}

# ── preflight ────────────────────────────────────────────────────────────────

# What a drain cannot run without, and deliberately nothing else.
#
# It does not call `gate_preflight`, `budget_preflight`, `concurrency_preflight`
# or the four that follow them in `loop_preflight`, and that is a decision rather
# than a shortcut. Those refuse a run whose *gate* would prove nothing, whose
# subscription cannot be read, whose worktrees cannot be made — none of which
# this loop does. Refusing to let a human empty their sink because `TEST_CMD` is
# empty would be a refusal that protects nothing: the code a human writes here is
# judged by the AFK run that grinds it afterwards, under those very checks.
#
# `MODEL` is not checked either, for the same reason from the other end: reading
# the sink, re-injecting and closing need no model at all. It is checked at the
# one point that needs it, which is opening a session.
human_loop_preflight() {
  local rc=0 dir

  if [ -z "${FEATURE:-}" ]; then
    printf 'ralph: FEATURE is empty — there is no sink to drain (see %s)\n' \
      "$RALPH_CONFIG" >&2
    rc=1
  else
    dir="$(ralph_feature_dir)"
    if [ ! -d "$dir" ]; then
      printf 'ralph: no tracker at %s — check FEATURE, or create the directory\n' "$dir" >&2
      rc=1
    fi
  fi

  [ "$rc" = 0 ] || return "$rc"

  # The duplicate-id scan, and this loop is the one component that can act on it
  # ([27], [47]): two tickets carrying one number take every ticket that names it
  # out of the frontier for good, a session can no longer create the collision,
  # and renaming one of them is a thing only a human — or this drain — may do. The
  # sentence shown is the one `tracker_preflight` produces, never a second
  # rendering of the same finding.
  human_loop__report_tracker_findings
  return 0
}

human_loop__report_tracker_findings() {
  local subject outcome message
  while IFS="$(printf '\t')" read -r subject outcome message; do
    [ -n "$subject" ] || continue
    human_loop_log "$message"
    router_journal "$subject" "$outcome" drain
  done <<FINDINGS
$(tracker_preflight)
FINDINGS
}

# ── the locks, re-asked ──────────────────────────────────────────────────────

# Do we still hold what we took? Asked again before every ticket and before every
# decision taken on one, and never assumed to have stayed true since the start
# ([57]).
#
# `loop.sh` asks these two at the top of every iteration and stops loudly when
# either answer is no. This loop took both locks and asked once — while being the
# entry point that puts an *unjudged* `claude` in the operator's own working
# tree, so the one where losing a lock costs the most. `state.sh` even wrote the
# guarantee down as a fact of the pack ("re-checked for ownership on every
# iteration"); it was a fact about one caller.
#
# Two questions and not one, because the two answers can differ and each names a
# different loss. The run lock lives under `.scratch/<feature>/`, which the
# scope-guard drops as bookkeeping and the rollback leaves alone, and [12] showed
# a session can delete it. The tree lock lives in `.git/`, out of reach of a
# `git add -A`, a `git clean` and an `rm -rf .scratch` — not of a session that
# deletes the directory outright. A routed session is a `claude` with a human in
# it and no gate, no worktree and no scope-guard behind it: it can do either.
#
# A lock that was deleted is not a lock that was stolen, and the question is the
# same either way: `*_is_ours` compares this process against the recorded owner,
# so a guard a rival took over after `state_guard_take` found ours stale answers
# no exactly as an erased one does.
human_loop__locks_are_ours() {
  if ! run_lock_is_ours; then
    human_loop_log "the run lock is gone or not ours any more — stopping rather than draining beside another run"
    return 1
  fi
  if ! tree_lock_is_ours; then
    human_loop_log "the working-tree lock is gone or not ours any more — stopping rather than opening a session in a tree another run may now claim"
    return 1
  fi
  return 0
}

# What a lost lock costs the rest of the sink. Separate from the question that
# found it, because the two live in different scopes: `human_loop__drain_one` is
# where the lock is noticed and the counters are `human_loop_main`'s, so the
# refusal travels back as a return code and the tally is printed here.
#
# The tally first: a sink that stopped short is exactly when what has already been
# drained stops being obvious. Then the ticket it stopped on, which is the one an
# operator has to start from once they have worked out who took the lock.
human_loop__stop_lost_lock() {
  human_loop_log "drained $1 ticket(s), left $2 where they were"
  human_loop_log "stopped with $3 and everything after it still in the sink"
  exit 4
}

# ── one ticket ───────────────────────────────────────────────────────────────

# The routed session: `claude` with a human in it, and the only external program
# this loop runs besides `git`.
#
# Never fatal. A session the human ended with Ctrl-C, a `claude` that is not
# installed, a model that refused — none of those is a reason to abandon a drain
# and leave the rest of the sink where it was. What it costs is a line saying so,
# and the ticket stays exactly where it was: this function marks nothing.
human_loop__session() {
  local id="$1" desk rc=0
  if [ -z "${MODEL:-}" ]; then
    human_loop_log "$id: MODEL is empty, so there is nothing to open a session with — set it in $RALPH_CONFIG"
    return 1
  fi
  desk="$(router_desk "$id")"
  human_loop_log "$id: opening a $(router_treatment "$desk") session ($desk)"

  trap ':' INT
  session_spawn_interactive "$(router_prompt "$id" "$desk")" || rc=$?
  human_loop__arm_signals

  if [ "$rc" != 0 ]; then
    human_loop_log "$id: that session ended with status $rc — nothing was marked, the ticket is where it was"
  fi
  router_journal "$id" drain-session "$desk"
  return 0
}

# One ticket, until the human is done with it.
#
#   0  it left the sink
#   1  it is still in the sink and the drain moves on
#   3  the human is done with the whole drain
#   4  a lock this drain took is gone: the whole drain stops
#
# The menu is re-offered after a session rather than assumed to have been
# resolved by it: a grilling that ends in "this ticket should never have existed"
# and one that ends in a patch have the same exit status, and only the human
# knows which happened.
human_loop__drain_one() {
  local id="$1" answer
  router_dossier "$id"

  while :; do
    # Do we still hold what we took? Here, and here only, because this is the one
    # place both moments meet: the first pass round this loop is the ticket
    # boundary the criterion asks for, and every later one is a decision already
    # taken on this ticket — a routed session most of all ([57]).
    #
    # A check at the ticket boundary alone would have been the smaller half. The
    # menu is re-offered after a session, so a session that deleted a lock comes
    # back to a prompt offering `o` again: a second unjudged `claude` in a tree a
    # run may now claim, on the same ticket, without ever crossing a boundary. And
    # a boundary check placed in `human_loop_main` would be dead code behind this
    # one — nothing runs between this loop's last pass and the next ticket's
    # first, so no mutation could tell the two apart, and a guarantee no mutation
    # can remove is a sentence and not a check.
    #
    # `r`, `s` and `c` get the same question for the other half of the reason:
    # they write `issues/` from outside any iteration, which is a thing only the
    # run lock entitles this loop to do.
    human_loop__locks_are_ours || return 4

    printf '\n  [o]pen a session  [r]e-inject  [s]ign off  [c]lose  [n]ext  [q]uit > '
    if ! IFS= read -r answer; then
      # Not a human, or a human who closed the pipe. Looping here would spin
      # forever on an EOF that never stops arriving.
      printf '\n'
      human_loop_log "stdin ended — stopping with $id where it was"
      return 3
    fi
    case "$answer" in
      o | open)
        human_loop__session "$id" || true
        ;;
      r | reinject | re-inject)
        if router_reinject "$id"; then
          human_loop_log "$id: back on the frontier, retry budget cleared — a fresh session and the whole gate decide now"
          router_journal "$id" drained reinjected
          return 0
        fi
        ;;
      s | sign | sign-off)
        if router_sign_off "$id"; then
          human_loop_log "$id: signed off — resolved without going through the gate, which only a sign-off may be"
          router_journal "$id" drained signed-off
          return 0
        fi
        ;;
      c | close | wontfix)
        if router_close "$id"; then
          human_loop_log "$id: closed"
          router_journal "$id" drained closed
          return 0
        fi
        ;;
      n | next | '')
        human_loop_log "$id: left in the sink"
        return 1
        ;;
      q | quit)
        return 3
        ;;
      *)
        human_loop_log "not one of o, r, s, c, n, q"
        ;;
    esac
  done
}

# ── the drain ────────────────────────────────────────────────────────────────

human_loop_main() {
  # First, and the position is the guarantee ([52]). `PATH` decides which `git`
  # and which `claude` everything below runs, and this loop runs a `claude` in
  # the operator's own working tree with no gate behind it — so a PATH nothing
  # here can witness is refused before a single name is resolved through it.
  # `ralph_project_root` on the next line is already a `git`. Nothing above this
  # point in this file runs a program by name.
  gate_path_preflight || exit 2

  cd "$(ralph_project_root)"

  human_loop_preflight || exit 2

  # Both locks, and the coarser one first, exactly as `loop_main` takes them.
  #
  # The run lock is what the acceptance criterion asks for — you grind or you
  # drain, one writer in this tracker — and it is also what settles the question
  # the 06/08 pass left open: this loop writes in `issues/` from outside any
  # iteration, where the two guards over that directory cannot tell it from a
  # session's own writing. Holding the lock means there is no run to be told
  # apart from.
  #
  # The tree lock is not in the criterion and is taken anyway, because this loop
  # puts an unjudged `claude` in the main working tree. The run lock is per
  # feature; an AFK run grinding a *different* feature of this repository holds a
  # different one and still folds its commits here, moves HEAD here, and stages
  # and unstages paths here. That is [22]'s mutual destruction reached through the
  # door the per-feature lock never closed — and the price is deliberate: a
  # successor that wakes up mid-drain is refused, which is precisely what [09]
  # wants to happen.
  tree_lock_acquire || exit 1
  run_lock_acquire "a human draining this feature's sink" || exit 1
  human_loop__arm_signals

  human_loop_log "draining ready-for-human (feature=$FEATURE backend=$TRACKER_BACKEND)"

  # The run-level words a reader gets wrong, said once before any ticket. Not a
  # summary of the journal — a human has the file — only the handful of outcomes
  # whose obvious reading is the wrong one ([52], [53]).
  local notes
  if notes="$(router_run_notes)"; then
    printf '%s\n' "$notes" | sed 's/^/ralph: /'
  fi

  local sink id rc=0 drained=0 left=0 quit=0
  if ! sink="$(router_sink)" || [ -z "$sink" ]; then
    human_loop_log "nothing to drain: the human sink was empty from the start (feature=$FEATURE backend=$TRACKER_BACKEND)"
    exit 5
  fi

  # The order is taken once, before anything moves, and that is correct rather
  # than lazy: unblocking impact is a property of who names whom in `Blocked by:`,
  # and nothing a drain does to one ticket changes what another ticket is waiting
  # for. A heredoc and never a pipe, so the counters below live in this shell.
  #
  # **On a descriptor of its own, and that is the whole of it.** A `while read id`
  # fed by a heredoc on stdin hands *that* stdin to everything it calls, so the
  # first question put to a human was answered by the end of the work-list: the
  # drain printed one dossier, read EOF, and stopped saying "stdin ended" — with
  # the sink untouched and an exit code that reads exactly like a human who
  # quit. The list travels on fd 3, stdin stays the human's, and the routed
  # session gets the terminal the same way.
  while IFS= read -r id <&3; do
    [ -n "$id" ] || continue
    # Re-read rather than trusted: the list was taken before the first decision,
    # and a human with two terminals open is not a race this loop is entitled to
    # lose loudly.
    [ "$(tracker_field "$id" Status 2>/dev/null)" = ready-for-human ] || continue

    rc=0
    human_loop__drain_one "$id" || rc=$?
    case "$rc" in
      0) drained=$((drained + 1)) ;;
      3)
        quit=1
        break
        ;;
      # The one code that ends the drain rather than the ticket. Falling through
      # to `*)` would count a lost lock as "left where it was" and carry on to the
      # next ticket — which is the whole of what this stops. Exits ([57]); the
      # `exit` is this process's, since the loop is fed by a heredoc and not a
      # pipe and nothing here is a subshell ([47]).
      4) human_loop__stop_lost_lock "$drained" "$left" "$id" ;;
      *) left=$((left + 1)) ;;
    esac
  done 3<<SINK
$sink
SINK

  human_loop_log "drained $drained ticket(s), left $left where they were"

  if ! sink="$(router_sink)" || [ -z "$sink" ]; then
    human_loop_log "the human sink is empty"
    exit 0
  fi
  if [ "$quit" = 1 ]; then
    human_loop_log "stopped before the end of the sink"
  fi
  human_loop_log "still waiting for a human: $(printf '%s' "$sink" | awk 'length { n++ } END { print n + 0 }') ticket(s)"
  exit 3
}

human_loop_main "$@"
