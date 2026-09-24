# shellcheck shell=bash
# The processes this run started: how it waits for them, and how it takes them
# down.
#
# Two functions, and the module exists because the pack has already paid twice for
# the first of them. `wait` was written out by hand in the gate's fan and again in
# `session_spawn`, separately, with the same fault in both — and the second copy
# sat on a longer window. A primitive of the loop is a defect repeated as many
# times as it is called ([25], [28]), so the third caller has to find it here
# instead of writing a fourth one.
#
# Layering is what settled where it lives. `gate__collect` was private to the gate,
# and `test/layering.bats` refuses a lib that reaches into a neighbour's `__`
# internals: a second caller means the function is public, so it gets renamed and
# placed rather than copied. Neither `session.sh` nor `gate.sh` could own it — each
# would be reaching into the other — and `state.sh` is about run state, not about
# child processes.
#
# `proc_kill_tree` arrived here the same way and one ticket later. [28] left it
# private to the gate on purpose — the rule is "a second caller makes it public",
# not "anticipate one" — and [23] is that second caller: a session deadline has to
# kill a `claude` and the tool processes under it, which is the same walk the
# gate's deadline does over a hung test suite.
#
# The rest arrived by the same route in [36] and [44], and they answer one
# question the two above cannot: *is there still anyone who wants this*. `wait`
# takes no timeout on bash 3.2, so both deadlines of the pack are processes, and a
# process outlives whoever armed it — the gate's watchdog was found writing its
# marker and walking a process tree half an hour after a `kill -9` on the run.
#
# [44] is the same question asked of something bigger than a deadline. Since [13]
# an *iteration* is a subshell too, it traps TERM and INT on purpose ([25], [28]),
# and it carries everything that decides: the durable commit, the fold onto the
# branch, the marking of the ticket. So a `kill -KILL` on the pilot no longer stops
# the part of the pack that writes — probed, twenty seconds after the run died the
# ticket was `resolved`, the branch had moved and `run.log` was empty. The
# instrument is the one below and deliberately not a second one; what differs is
# only *when* it is asked. A countdown asks every second, an iteration asks at each
# point it is about to do something nobody could take back.

# Wait for a child all the way to its exit status, and hand that status back.
#
# `wait` is not a call the graceful stop can be trusted to survive. Bash defers a
# trap until an external command returns, but documents the opposite for the
# builtin: "the reception of a signal for which a trap has been set will cause the
# wait builtin to return immediately with an exit status greater than 128,
# immediately after which the trap is executed". The loop traps TERM and INT
# precisely so that a kill lets the current iteration finish — so a bare `wait`
# abandoned whatever it was waiting for the moment a stop was requested.
#
# What that cost, in both places it was written:
#
#   - in the gate's fan, the aggregation read `.rc` files nobody had written yet.
#     Live branches came back "no verdict", which counts red: an unearned
#     `Failures:`, a rollback undoing the session's work while the very test suite
#     judging it was still running, an orphaned branch outliving the run, and
#     `rm -rf` on a directory processes were still writing to ([25]).
#   - in `session_spawn`, the loop took the iteration back while `claude` was still
#     shutting down: it judged, rolled back, `rm -f`ed the stream and exited the run
#     with a live session still writing into a deleted file and still spending
#     quota — on a subscription, capacity taken from the next night ([28]).
#
# So wait again. Nothing is lost by doing so: the trap has already run by the time
# we are back here, `RALPH_STOP` is set, and the loop stops after this iteration —
# which is the whole promise. Disarming the trap around the wait would collect the
# child and drop the stop, which is the opposite trade.
#
# `kill -0` is what separates the two ways a status over 128 arrives, since the
# code alone cannot: an interrupted `wait` leaves the child running and still
# answering, whereas a child that died *from* a signal — the watchdog's doing — has
# been reaped and no longer answers.
#
# It is the loop's only exit, and not a readability flourish. The tempting
# assumption is that a second `wait` on a pid bash has already reaped comes back
# 127, "not a child of this shell", which would end the loop by itself. Probed on
# bash 3.2: it does not. A pid that exited normally answers 0, but a pid that was
# *killed* answers 143 again, and again, without blocking — so dropping the
# liveness check turns the watchdog path into a busy spin that never returns.
# Which is why the test that covers this line carries its own deadline: removing it
# hangs the run rather than failing an assertion.
#
# The status is returned rather than swallowed, which is the one difference from
# the gate-private version this replaces. `session_spawn` returns the session's
# exit code to the loop, and a primitive that answered 0 for every child would
# turn a crashed session into a resolved ticket.
#
# The gate did not care when this was written — it read its verdicts off a `.rc`
# file per branch — and it is the only caller that cares now. Those files were a
# `mktemp` under `$TMPDIR`, so every verdict of every gate was writable by
# whatever the judged session had left running; since [92] a branch's verdict is
# the status this function hands back, and the file is gone. Which makes the
# sentence above the whole of the module's reason to exist: the value both
# callers depend on is the one a bare `wait` drops on a graceful stop.
#
# One window stays open, and it is the same one a bare `wait` had: a child that
# dies in the instant a trapped signal arrives is indistinguable from one the
# signal killed, so its real status is lost and 143 is reported instead. That is
# microseconds wide — on the normal path the monitor has already seen the process
# gone before we get here, so no signal is pending — and no test can pin it down,
# which is why nothing here pretends to close it. What it would cost is a green
# session retried, not a red one passed.
proc_collect() {
  local pid="$1" rc
  while :; do
    rc=0
    wait "$pid" 2>/dev/null || rc=$?
    [ "$rc" -gt 128 ] || return "$rc"
    kill -0 "$pid" 2>/dev/null || return "$rc"
  done
}

# Every descendant, deepest first, then the process itself. Killing the process
# alone would leave whatever it started — a hung test suite holding a port or a
# database, a dev server a session's Bash tool brought up — running for the rest
# of the night. `ps` is POSIX; the pack still needs nothing installed.
#
# The signal is an argument because the callers ask for different things at
# different moments, and the second one only exists because the first is a
# request. The gate's deadline and a session deadline both start with TERM, which
# is what lets `claude` shut down cleanly and a test suite remove its lock file;
# what follows a TERM nobody honoured is the caller's business, not this walk's —
# see monitor__reaper for the session's answer, and for why the gate does not need
# the same one.
#
# All four of them are deadlines — `monitor__terminate`, `monitor__reaper`, the
# gate's watchdog, the playthrough's — and that is the shape [92] had to answer.
# A ppid walk only reaches what is still under the process it starts from, so it
# is an instrument for killing something that is *still there*, and there is
# exactly one moment it cannot serve: the ordinary one, a session that finished
# by itself. By the time `proc_collect` comes back the session is reaped — bash
# collects a background child in its own SIGCHLD handler, so it is already out of
# the process table before anyone waits on it, probed on 3.2.57 — and whatever it
# left is init's child, not its own. "`proc_kill_tree` on the pid afterwards" is
# not an option there; it is a walk from a pid that no longer exists.
#
# So the other handle, and it is the one this comment used to say this shell
# never makes: a process group. `session_spawn` makes one for the session and
# `proc_group_fork` makes one for every command line a project handed this pack
# ([95]); `proc_group_members` below reads it and `proc_sweep` acts on it, and what
# that does and does not buy is written there and in
# `docs/frontiere-de-confiance.md`.
proc_kill_tree() {
  local pid="$1" signal="${2:-TERM}" child
  for child in $(ps -A -o pid= -o ppid= 2>/dev/null | awk -v p="$pid" '$2 == p { print $1 }'); do
    proc_kill_tree "$child" "$signal"
  done
  kill -"$signal" "$pid" 2>/dev/null || true
  return 0
}

# What is still running in the process group whose leader was <pid>, one pid per
# line, the leader itself excluded. The answer to "what did this session start
# that is still going", asked once the session itself is gone.
#
# A group is the one handle on a descendance that outlives the process at the top
# of it. The ppid chain does not: a child reparents to init the moment its parent
# exits, and the walk above then finds nothing. A group number, by contrast, is
# held for as long as the group has a member — so at the instant a session is
# collected, either it left something and the number still names exactly that, or
# it left nothing and there is nothing to find.
#
# Which is also the whole of why this enumerates rather than signalling the group
# directly. `kill -- -PGID` at this moment would be a signal aimed at a number the
# system is free to reissue the instant the last member goes, which is the fault
# [36] paid for one layer up; listing the members and letting the caller signal
# each one costs a `ps` and can only ever reach processes that exist.
#
# It refuses its own group outright, and that refusal is not defensive tidiness.
# A shell without job control puts a background child in the shell's *own* group,
# so a caller that asked this about a session spawned without `set -m` would be
# handed its own siblings — the run, the harness, the terminal's other children —
# and would TERM them. The failure it turns into is "the sweep found nothing",
# which is the direction a guard about killing has to fail in.
proc_group_members() {
  local leader="$1" mine members
  local PROC_SELF=''
  [ -n "$leader" ] || return 0
  proc_self
  mine="$(ps -o pgid= -p "${PROC_SELF:-0}" 2>/dev/null | awk 'NR == 1 { print $1 + 0 }')"
  [ -n "$mine" ] && [ "$mine" != 0 ] && [ "$leader" != "$mine" ] || return 0
  members="$(ps -A -o pid= -o pgid= 2>/dev/null |
    awk -v g="$leader" '$2 == g && $1 != g { print $1 }' || true)"
  [ -n "$members" ] || return 0
  printf '%s\n' "$members"
  return 0
}

# What is still running in a process group, asked to stop, and said out loud.
#
# [92] wrote this for a session, as `session__sweep`; [95] gave it three more
# callers and that is what makes it public. This pack runs four programs it did
# not write — `claude`, and the project's own `TEST_CMD`, `TYPECHECK_CMD` and
# `RUN_CMD`/`VISUAL_CMD` — and every one of them can hand the shell back with work
# of its own still going. Until [95] only the session was taken back: a `sleep`
# left by the project's test command was measured still alive when the run had
# finished, reparented to init, on a green run with the ticket marked `resolved`
# and not one line naming it.
#
# Which mattered for more than tidiness, and the measurement is the ticket: what
# one of those commands leaves runs *while the gate that launched it runs*, with
# `$TMPDIR` in front of it. A process left by `TEST_CMD` sees `tests.out
# scope.out typecheck.out lang.out` in the gate's own directory, and it was enough
# on its own — with no hostile session anywhere — to play the whole of [92]'s
# scenario back.
#
# The subject is a phrase rather than a name because it is printed: "this
# session", "the project's test command". A human reading the morning log acts on
# which of the four it was, and never on a pid.
#
# The price, and it is a real one rather than a formality:
#
#   - TERM and nothing after it. A survivor that ignores the signal stays, and
#     there is no reaper here: the caller has to get on with the run, and a grace
#     of its own would put a KILL in flight against the processes of something
#     that is already over. The request is made and the line is printed whether or
#     not it is honoured.
#   - A descendant that leaves the group is out of reach, exactly as it is out of
#     reach of the ppid walk. Anything that calls `setsid` — a daemon that
#     daemonises properly, which is precisely the dev server `RUN_CMD` starts — is
#     gone from both. The pack does not promise that nothing survives; it promises
#     to take back what stayed in the group and to name what it found.
#   - It is the *group* that is sound here, not the pid: see `proc_group_members`,
#     which enumerates the members instead of signalling the number, and refuses
#     its own group rather than guess. A caller that forked without `set -m` is
#     handed nothing at all, which is the direction this has to fail in.
#
# Said on stderr, where `monitor_watch`'s own refusal goes: a lib may not reach up
# into the loop for its reporting channel, and the one line this prints belongs in
# the morning log beside the iteration it came from. From a gate branch that is
# also the only channel out: `proc_group_fork` redirects the command and nothing
# else, so this leaves on the branch's own stderr instead of landing in
# `$dir/<name>.out` — a file `gate_run` deletes and nobody reads on a green branch.
proc_sweep() {
  local leader="$1" subject="$2" left pid n=0
  left="$(proc_group_members "$leader" | tr '\n' ' ')"
  left="${left% }"
  [ -n "$left" ] || return 0
  for pid in $left; do
    kill -TERM "$pid" 2>/dev/null || true
    n=$((n + 1))
  done
  printf 'ralph: %s left %s process(es) of its own running (%s): TERM sent to each, and nothing here follows it up\n' \
    "$subject" "$n" "$left" >&2
  return 0
}

# Start a command line this pack did not write, in a process group of its own, in
# the background. Sets PROC_GROUP_PID — the leader of that group — for the caller
# to wait on and to sweep.
#
# The one place in this pack where a shell is handed a command string a *project*
# supplied, the way `session.sh` is the one place it runs `claude`, and for the
# same reason. Before [95] three sites forked `bash -c "$SOMETHING"` on their own
# — the gate's test branch, its type-check branch, and `playthrough__bounded` for
# `RUN_CMD` and `VISUAL_CMD` — and not one of them gave what it launched a name,
# so nothing could be taken back when the command returned. A fourth site written
# tomorrow would have inherited that silence; the census in `test/gate.bats` is
# what turns "somebody should have noticed" into a red test on the day it lands.
#
# Job control for exactly one fork, and turned straight off again — the shape
# `session_spawn` takes, for the same purpose. Without it the child sits in the
# shell's own process group, `proc_group_members` refuses that group by design,
# and a sweep finds nothing at all: the group has to be made before there is
# anything to sweep, which the tests show rather than assume.
#
# `cd` before `exec` rather than a flag on the command: the gate's fan runs the
# project's commands in the worktree an iteration was given ([13]) and the
# playthrough runs them in the main working tree ([11]), because `RUN_CMD` plays
# the feature through on the project's own assets. The directory is the caller's
# to name, and empty means "here".
#
# Where the transcript goes is the caller's too, and that is not a detail of
# style: the background child inherits whatever this call was given, so the gate's
# branch hands it the redirection it is already running under and the playthrough
# redirects this call itself. A file argument here would have made this function
# the one that decides where a command's output lands, which is a decision two
# callers make differently — and in the gate's case it is the difference between a
# sweep that reaches the morning log and one that lands in a file nobody reads.
#
# stdin is `/dev/null`, and that one is the group's price rather than tidiness: a
# process in a background process group that reads the terminal is stopped with
# SIGTTIN instead of being served, and a stopped `TEST_CMD` would hang its branch
# until the gate's deadline — half an hour at the shipped value. EOF is what the
# same command gets from every CI that ever ran it.
proc_group_fork() {
  local cwd="$1" cmd="$2"
  PROC_GROUP_PID=''
  set -m
  (
    [ -z "$cwd" ] || cd "$cwd"
    exec bash -c "$cmd"
  ) </dev/null &
  PROC_GROUP_PID=$!
  set +m
  return 0
}

# The pid of the shell running this, which bash 3.2 has no variable for — there is
# no BASHPID before 4.0, `$$` is not updated in a subshell, and `$PPID` is not
# either. Probed on 3.2.57 inside a `( … ) &` of a run: `$$` answers the run and
# `$PPID` answers the terminal that started the run, so from a deadline process
# neither of them means "me" and the one that looks right is the wrong one.
#
# What does work costs a fork: a command substitution forks from the current shell,
# so the `$PPID` reported by the `sh` it execs is this shell.
#
# It answers through PROC_SELF instead of stdout, and that is load-bearing rather
# than a style choice: `self="$(proc_self)"` would fork a subshell of its own and
# report that subshell's pid instead of the caller's.
proc_self() {
  PROC_SELF="$(exec sh -c 'echo $PPID')"
  return 0
}

# The parent a pid answers to right now; empty when there is no such process.
#
# This is the identity check the pack did not have. A pid is not an identity — the
# system is free to hand the number to somebody else as soon as the process behind
# it is reaped, and on macOS it wraps at 99999, which half an hour of a working
# machine goes through. A *parent link* is one, because a process is never
# reparented to anything except init: "still the same parent as when I was armed"
# cannot be inherited along with the number.
#
# It also answers where `kill -0` lies. A run killed by a parent that never reaps
# it stays a zombie, and a zombie answers `kill -0` exactly like a live process —
# probed on 04/08/2026 with a parent that never waits: `kill -0` succeeds, `ps`
# says state Z. A deadline that decided by the number alone would have gone on
# believing in a run that had been dead for minutes.
proc_parent_of() {
  ps -o ppid= -p "$1" 2>/dev/null | awk 'NR == 1 { print $1 + 0 }'
  return 0
}

# Remember which shell this one answers to, so that a piece of work long enough to
# outlive it can ask later whether it is still there. Sets PROC_OWNER, the pid, and
# PROC_OWNED, this shell's own — non-zero when neither can be read, which is a
# caller that has to refuse rather than assume.
#
# The owner may be **handed in**, and the difference between the two forms is the
# difference between the two callers. A deadline is forked by whoever wants the
# kill and can only *discover* it, there being no other name for that shell. An
# iteration knows one: `$$` is the pilot in every subshell of a run — bash 3.2 has
# no BASHPID — so it can say which shell it expects to answer to, and a pilot that
# died between the fork and this line is then refused instead of being replaced,
# silently, by init. Discovery there would record the wrong owner and believe in it
# for the rest of the night.
proc_owner_take() {
  proc_self
  PROC_OWNED="$PROC_SELF"
  [ -n "$PROC_OWNED" ] || return 1
  PROC_OWNER="${1:-$(proc_parent_of "$PROC_OWNED")}"
  [ -n "$PROC_OWNER" ] && [ "$PROC_OWNER" != 0 ] || return 1
  if proc_owner_gone; then
    return 1
  fi
  return 0
}

# Whether that shell has gone. A changed parent link has exactly one meaning —
# nothing but init can become our parent — which is why this is a link and never a
# `kill -0` on a number: a zombie answers the number like a live process, and a
# reaped number is one the system may hand to somebody else.
#
# An owner nobody recorded is nobody to lose, so an unset PROC_OWNER answers "not
# gone": this pair is a question about a shell that took itself, and a caller that
# never took one is not being watched over. That is a door a correction could walk
# through — drop the `proc_owner_take` and every refusal built on this evaporates
# in silence — which is why the [44] mutations come in pairs, one removing the
# refusal and its twin removing the capacity to act.
# Written as an `if` rather than as `[ … ] && return 1`, and that is the loop's own
# lesson about errexit rather than a taste: an AND-list whose left half is false is
# a failing command, so the second form would take a caller down the day somebody
# calls this outside a condition. Every caller today is in one; the next one may
# not be.
proc_owner_gone() {
  [ -n "${PROC_OWNER:-}" ] || return 1
  if [ "$(proc_parent_of "${PROC_OWNED:-0}")" = "$PROC_OWNER" ]; then
    return 1
  fi
  return 0
}

# Serve a deadline: sleep up to <seconds>, and give up the moment there is nobody
# left to serve it for. Returns 0 only if the whole time was served.
#
# In one-second steps, which the two deadlines had already settled on for their own
# reason — killing a deadline that slept the whole span in one call would leave the
# `sleep` behind as an orphan for the rest of it. What is new is what happens
# between two steps.
#
# *Who* it serves is discovered rather than passed, and that is the point. The
# shell that forks a deadline is the shell that wants the kill, so the deadline
# watches its own parent link: unchanged means that shell is still there, and
# changed can only mean it is gone, since nothing else can become our parent. The
# alternative — being handed the run's pid and checking `kill -0` on it — fails in
# both directions here: it lies on a zombie run (above), and it names the wrong
# shell for a deadline armed from a gate branch, where `$$` is the run and the
# process that spawned the session is the branch.
#
# The pair above is where that lives since [44] gave it a second caller, and the
# two variables are declared `local` here rather than left global on purpose: this
# is always forked, so nothing would notice today, and a future caller that forgot
# to fork would otherwise overwrite the owner its own iteration recorded.
#
# The extra pids are the caller's own targets, checked with `kill -0` because
# giving up early on them is an optimisation and not a guarantee — the guarantee is
# the parent link above, and what the caller does before firing is its business.
proc_countdown() {
  local limit="$1" waited=0 pid
  local PROC_OWNER='' PROC_OWNED=''
  shift

  proc_owner_take || return 1

  while [ "$waited" -lt "$limit" ]; do
    sleep 1
    if proc_owner_gone; then return 1; fi
    for pid in "$@"; do
      kill -0 "$pid" 2>/dev/null || return 1
    done
    waited=$((waited + 1))
  done
  return 0
}
