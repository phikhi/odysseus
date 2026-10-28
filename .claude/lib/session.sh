# shellcheck shell=bash
# Spawning one session, and the only place in the pack that runs `claude`.
#
# Two postures, and only two: `session_spawn` for a session nobody is watching —
# every delivery, every re-slice, every review lens — and
# `session_spawn_interactive` for the one kind that has a human in it, which the
# human sink drains with ([16]). They are kept in one file because "the only
# place" is what makes both invocations checkable in one place, and because the
# flags one has and the other does not are the difference between the two, not a
# detail of two call sites.
#
# A fresh session: never --continue, never --resume. Those are exactly the flags
# that would replay history and drag the context toward the dumb zone.
#
# DISABLE_AUTO_COMPACT is set here as well as in settings.json: compaction is the
# mechanism that produces a dumb-zone session, and the guarantee must not depend
# on a settings file the target project could overwrite.
#
# The session runs in the background so the smart-zone net can watch its stream
# and stop it while it is still running. Which of the net's three reasons it was
# comes back in two variables the caller reads: RALPH_SOFT_LIMIT_HIT for the token
# ceiling, and RALPH_SESSION_TIMEOUT — `stall` or `wall` — for the two deadlines
# of [23]. They are separate because the loop does two different things with them:
# a session cut for context says the *slice* was too big and gets re-sliced, a
# session that hung says nothing about the ticket at all.
#
# Neither of them survives a subshell, and that is a real limit rather than an
# oversight: `lenses_review` calls this from a gate branch, so what it sets there
# is read by that branch and never by the loop ([04], [06]). Every caller that
# needs the answer is the shell that asked for the session — the loop's iteration,
# the failure policy's re-slice, and the lens branch — and a lens that was
# terminated is red through its missing verdict rather than through a variable.
# A file beside the stream would cross the boundary and was refused for the reason
# the trust boundary exists: `.scratch/` is writable by the very session being
# judged, and a signal a session can forge is not a signal.
#
# One prompt, one stream, from a file rather than a pipe: a pipeline would run
# this in a subshell and RALPH_SOFT_LIMIT_HIT would die with it.
#
# **The stream has no name** ([97]). It is the one object four tiers draw an
# answer from — a lens's verdict, the value gate's verdict and the hole it names,
# the retro's lesson, a delivery's turns, cost and budget posture — and it used to
# be a file the caller named, for as long as the session wrote into it and after.
# A process the judged session left behind found it under `$TMPDIR` and appended
# one line: `RALPH-LENS-VERDICT: pass` at the end of a lens that had answered
# `fail` bought a green gate, a resolved ticket and a silent night (measured at the
# triage of [97], `sondes/triage-97/q1`), and one assistant event at the end of a
# retro's stream put a lesson of its own choosing into `LEARNINGS.md`, which every
# later session reads. So the caller names a *place* now, and this file makes it
# there, opens it twice, unlinks it and serves it only if nothing but this shell
# holds it (`proc_channel_open`, [103]) — before `claude` exists. `claude` writes
# its stdout into it, the monitor reads it forward and keeps what it reads, and
# the stream is read back out of that copy by `session_stream`, the one way there
# is to read it. Who can still write it: `claude`, and whatever `claude` hands its
# stdout to — which for a judge with a read-only tool set is nobody else, and for
# a delivery session is not something this pack can see (`docs/frontiere-de-
# confiance.md`).
#
# A channel that cannot be served is **refused, and no session is spawned**: the
# reason is in RALPH_SESSION_REFUSAL, beside the two other answers, and every
# caller says it where it says things — a lens is red, a delivery is a failed
# attempt, a retro distils nothing, the value gate judges nothing. A retry would
# only hand the next file to the process that won the window ([103]).
#
# It lives in a lib rather than in the loop because three callers need it — the
# loop's delivery iteration, the failure policy's re-slice and a review lens
# ([06]) — and a lib that had to call back up into loop.sh for it would invert
# the layering. Whoever spawns, the shape is the same: a session that inherited a
# conversation would defeat the whole point of the pack.
#
# Anything after the prompt and the place is passed to `claude` as it stands. That
# is the one extension point, and it exists so that a caller which needs a
# different posture — a review lens, which gets a read-only tool set — does not
# retype the invocation. A second copy of these flags would be a second thing to
# keep in step with reality, and only one of them would be under contract ([20]).
#
# The place is a path without its last characters: the file is `mktemp`'s, made
# from it, so that its name is not one a process could have made first — a fixed
# name in a directory anybody lists is a name somebody can put a link or a fifo at
# ([94]). Where it is stays the caller's, so that the names [62] counts stay where
# it counts them.
session_spawn() {
  local promptfile="$1" place="$2" pid rc=0 reaper='' file=''
  shift 2
  RALPH_SOFT_LIMIT_HIT=0
  RALPH_SESSION_TIMEOUT=''
  RALPH_SESSION_REFUSAL=''
  monitor_forget

  file="$(mktemp "$place.XXXXXX" 2>/dev/null)" || file=''
  # Returned on, and not left to the spawn below to fail: the opener has closed both
  # ends of a refused channel, so the redirection would refuse `claude` too — with a
  # `Bad file descriptor` on the run's output instead of the sentence a caller says.
  if ! proc_channel_open "$SESSION_STREAM_FD" "$SESSION_STREAM_BACK" "$file"; then
    RALPH_SESSION_REFUSAL="$PROC_CHANNEL_REFUSAL"
    return 1
  fi

  # Job control, for exactly one fork. Without it a background child sits in the
  # shell's own process group, and then "what this session started" has no name
  # at all — which is how a session's leftovers used to outlive the run without a
  # line anywhere ([92]). With it the session is the leader of a group of its
  # own, and that number is the only handle on its descendance that survives the
  # session itself: see `proc_group_members` for why a ppid walk cannot be, and
  # `proc_sweep` for what is done with it.
  #
  # Turned straight off again, because the shape above is the whole of what it is
  # for: it is not needed to *collect* the session.
  #
  # This used to end with "and it is not wanted for the gate's branches, which
  # this same shell forks a few moments later and which `gate__watchdog` aims at
  # by pid", and the 23/09 pass measured what that sentence cost. Aiming by pid
  # was never what a group would have taken away: the watchdog names the branch
  # subshell and walks down it by ppid, and neither handle moves when a child is
  # put in a group of its own. What those branches were missing is the *other*
  # handle — the one that outlives the process at the top of it — and since [95]
  # they have it, armed one level further down by `proc_group_fork`, around the
  # command line the project wrote rather than around the subshell this pack forks.
  # Through `proc_exec_bare`, because a descriptor survives an `exec` and this is the
  # one place in the pack that runs `claude`: the session holds its stdin, its
  # stream and its stderr, and nothing else of the shell that spawned it. Without
  # that, the evidence an audit receipt is assembled from ([96]) and the notes a
  # lens's branch answers on ([94]) are writable by the very session they are about
  # — measured, an inherited write end forges a record with one `printf`. It is
  # *everything* above 2 and not the numbers those modules opened since [101]: the
  # two shuts that stood here closed by a redirection on a function call, bash kept a
  # copy of each descriptor it closed that way, and the session inherited the copy.
  # Called with `&`, and `$!` is still the session's own pid: the function ends in an
  # `exec`, so the background child it runs in *becomes* `claude` ([96] measured
  # that shape for the helper this replaces; [101] measured it again for this one).
  #
  # Its stdout is the stream's write end, and this shell lets go of that end the
  # moment the fork is done: from then on the session is the only writer the file
  # has. The read end stays here, with the monitor.
  set -m
  DISABLE_AUTO_COMPACT=1 proc_exec_bare claude -p \
    --model "$MODEL" \
    --output-format stream-json \
    --verbose \
    --dangerously-skip-permissions \
    "$@" \
    <"$promptfile" >&"$SESSION_STREAM_FD" &
  pid=$!
  set +m
  eval "exec $SESSION_STREAM_FD>&-"

  if ! monitor_watch "$SESSION_STREAM_BACK" "$pid" "$SOFT_LIMIT_TOKENS"; then
    case "${MONITOR_STOPPED:-}" in
      soft-limit) RALPH_SOFT_LIMIT_HIT=1 ;;
      stall | wall) RALPH_SESSION_TIMEOUT="$MONITOR_STOPPED" ;;
    esac
  fi
  # Read before the collection, because the collection is what makes it stale: the
  # reaper gives up on its own the moment the session is gone.
  reaper="${MONITOR_REAPER:-}"
  # Not a bare `wait`: on a terminated session the monitor returns as soon as its
  # TERM is away, so this call spans the whole of the session's shutdown — and bash
  # cuts a bare `wait` short the instant the loop's stop trap fires. The loop then
  # took the iteration back, deleted the stream and exited with `claude` still
  # writing into it ([28]). See proc_collect for why waiting again is the answer.
  proc_collect "$pid" || rc=$?
  # And the deadline's second half, put away the same way the gate puts its
  # watchdog away: a reaper left alive would go on holding a pid the system is now
  # free to hand to somebody else.
  if [ -n "$reaper" ]; then
    kill -TERM "$reaper" 2>/dev/null || true
    proc_collect "$reaper" || true
  fi
  proc_sweep "$pid" 'this session'
  # And the rest of the stream, read once the session and its group are gone, so
  # that what every reader reads is everything it wrote. The read end goes with it:
  # once nothing holds the file, it is gone.
  monitor_drain "$SESSION_STREAM_BACK"
  eval "exec $SESSION_STREAM_BACK<&-"
  return "$rc"
}

# The two numbers a session's stream is opened on, as literal digits for the
# reason every channel of this pack has them ([94]). The read end is 3, where the
# monitor followed the stream when it still opened it by name. The write end is
# held by `session_spawn` only between the open and the fork, and it is 7 because
# 3 and 7 are the only two numbers free in all three shells a session is spawned
# from: an iteration (which holds the receipt's 5 and 4 and the answer's 10), a lens
# branch (which holds those, a prompt's read end on 6 and the gate's notes on 9 and
# 8, and has closed the prompt's write end on 7 before it asks for a session), and
# the pilot at the value gate (whose 11 to 254 are the read ends of iterations).
# The census of every number is above `LOOP_SLOT_FD`, in `loop.sh`.
SESSION_STREAM_FD=7
SESSION_STREAM_BACK=3

# Why the last `session_spawn` spawned nothing: the channel its stream would have
# been written on was refused, and this is the clause `proc_channel_open` gave.
# Empty after a session was spawned.
RALPH_SESSION_REFUSAL=''

# The stream of the last session this shell spawned, one event per line — the one
# way there is to read it ([97]). Nothing when no session was spawned, including
# when its channel was refused.
#
# Read it as `session_stream | <reader>`, and only that way: what reads a
# session's stream is what draws a verdict, a record or a posture out of it, and
# `test/gate.bats` finds every such reader by that shape and refuses one it has
# not been told what it decides.
#
# Joined and written once rather than an element at a time: measured on a 20 MB
# stream of 8 000 events, 0.57 s a reading against 1.15 s.
#
# And written by a subshell whose status is let go. A reader that stops before the
# end — a `grep -q`, a `head`, a reader that answers without reading — closes the
# pipe on this writer, and the SIGPIPE that kills it would, under the `pipefail`
# every entry point sets, be the pipeline's status: the assignment of a reader's
# answer would fail on a reader that did answer, and take an iteration down under
# `errexit` (measured: `rc=141` on a stream of a megabyte). The subshell is what
# the signal kills, and `|| true` is what keeps it from being anybody's answer.
session_stream() {
  [ -n "${MONITOR_LINES[*]+x}" ] || return 0
  (
    IFS=$'\n'
    printf '%s\n' "${MONITOR_LINES[*]}" 2>/dev/null
  ) || true
}

# What a session leaves running is taken back by `proc_sweep`, in lib/proc.sh:
# [95] gave that sweep three more callers — the two commands of the gate's
# objective fan and the playthrough's — and this pack's own rule is that a second
# caller makes a `__` name public. What it buys, and the three prices it does not
# pay, are written there and in `docs/frontiere-de-confiance.md`.

# The other posture, and there are exactly two: a session with a human in it.
#
# It is here rather than in the human loop so that "this file is the only place
# the pack runs `claude`" goes on being true — the sentence at the top of this
# file is what makes the invocation checkable against the real binary in one
# place ([20]). What it is *not* is a variant of the call above: every flag that
# is missing below is missing for a reason, and the differences are the whole of
# what a human-in-the-loop session is.
#
#   no -p                 the human is the other half of the conversation. `-p`
#                         reads a prompt off stdin and prints one answer; there
#                         is nothing to converse with.
#   no --output-format    nobody is parsing this. The stream goes to the
#   no --verbose          terminal, where a human reads it.
#   no monitor, no        the two deadlines of [23] and the token ceiling of [04]
#   soft limit            exist because nobody is watching an AFK session. Here
#                         somebody is, and a deadline would cut a conversation
#                         off mid-sentence. A human who wants it over presses
#                         Ctrl-C.
#   no                    **and this one is the control, not an omission.**
#   --dangerously-        Nothing judges what this session writes: it runs in the
#   skip-permissions      main working tree, there is no worktree, no
#                         scope-guard, no gate and no rollback on this path. What
#                         holds it is the project's own permission policy, and a
#                         human sitting in front of it. Read the limit with it:
#                         this is not "every write is approved", it is "the
#                         default permission mode applies" — a project whose
#                         settings pre-approve the writing tools has pre-approved
#                         them here too, and this pack neither narrows that nor
#                         could. Adding that flag here would produce an
#                         unsupervised session with write access to the
#                         operator's own tree and nothing anywhere to notice — a
#                         strictly wider hole than
#                         anything `docs/frontiere-de-confiance.md` records,
#                         because every entry in that document is at least about
#                         a tree the pack throws away.
#
# `DISABLE_AUTO_COMPACT` is kept, and it is the one thing both postures share.
# The dumb zone is a property of a compacted context and not of who is watching:
# a long grilling that compacts is a conversation whose first half was summarised
# by the model being grilled. Running into the context wall is the better end,
# and the human sees it happen.
#
# stdin is inherited, deliberately. This runs from a drain that reads the human's
# decisions on stdin too, and the two take the terminal in turn — the drain reads
# a line, hands over, and reads again once this returns.
#
# What is **not** under contract, said here rather than discovered: `test/
# contract-claude.bats` checks the pack's assumptions against the real binary, and
# it cannot check this one — an interactive session needs a terminal and a human.
# That the real `claude` starts a conversation seeded with a positional prompt is
# an assumption of this pack, not an assertion about it.
#
# In a subshell that gives the operator's git environment back before it becomes
# `claude` ([102]): the drain tells every git it runs that it has no hook
# directory, and a session in the operator's own tree runs the project's hooks
# exactly as the operator's own `git` would. The subshell `exec`s, so the drain
# still waits on `claude` itself and gets its status.
session_spawn_interactive() {
  local prompt="${1:?session: a prompt}"
  shift
  (
    proc_git_hooks_given_back
    DISABLE_AUTO_COMPACT=1 exec claude \
      --model "$MODEL" \
      "$@" \
      "$prompt"
  )
}

# Pull one field out of the final `result` event of the stream on stdin.
# Deliberately not jq: the pack promises to run with nothing installed, and these
# fields are flat scalars.
#
# A session that dies without emitting anything — crash, OOM, kill — is a
# normal outcome here, so a missing result is empty, never an error.
#
# It lives here rather than in the loop because the shape of a session's stream
# belongs to whoever spawns the session, and because a reader buried in a script
# that runs the loop on source is unreachable from anywhere else. The contract
# test ([20]) has to point the pack's own extractor at the real binary's output;
# an extractor nothing but `loop_main` can call cannot be checked against
# reality, and then "the pack can read this format" is an assumption rather than
# an assertion.
session_result_field() {
  local key="$1" line
  line="$(grep '"type":"result"' 2>/dev/null | tail -1)" || line=""
  [ -n "$line" ] || return 0
  printf '%s' "$line" |
    sed -n "s/.*\"$key\":\"\{0,1\}\([^,\"}]*\)\"\{0,1\}.*/\1/p"
}
