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
# The three that follow arrived by the same route in [36], and they answer one
# question the two above cannot: *is there still anyone who wants this*. `wait`
# takes no timeout on bash 3.2, so both deadlines of the pack are processes, and a
# process outlives whoever armed it — the gate's watchdog was found writing its
# marker and walking a process tree half an hour after a `kill -9` on the run.

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
# the gate-private version this replaces. The gate reads its verdicts off the `.rc`
# files and does not care, but `session_spawn` returns the session's exit code to
# the loop, and a primitive that answered 0 for every child would turn a crashed
# session into a resolved ticket.
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
# of the night, and `kill -- -PID` needs a process group this shell never made.
# `ps` is POSIX; the pack still needs nothing installed.
#
# The signal is an argument because the two callers ask for different things at
# different moments, and the second one only exists because the first is a
# request. The gate's deadline and a session deadline both start with TERM, which
# is what lets `claude` shut down cleanly and a test suite remove its lock file;
# what follows a TERM nobody honoured is the caller's business, not this walk's —
# see monitor__reaper for the session's answer, and for why the gate does not need
# the same one.
proc_kill_tree() {
  local pid="$1" signal="${2:-TERM}" child
  for child in $(ps -A -o pid= -o ppid= 2>/dev/null | awk -v p="$pid" '$2 == p { print $1 }'); do
    proc_kill_tree "$child" "$signal"
  done
  kill -"$signal" "$pid" 2>/dev/null || true
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
# The extra pids are the caller's own targets, checked with `kill -0` because
# giving up early on them is an optimisation and not a guarantee — the guarantee is
# the parent link above, and what the caller does before firing is its business.
proc_countdown() {
  local limit="$1" waited=0 pid self owner
  shift

  proc_self
  self="$PROC_SELF"
  owner="$(proc_parent_of "$self")"
  [ -n "$owner" ] || return 1

  while [ "$waited" -lt "$limit" ]; do
    sleep 1
    [ "$(proc_parent_of "$self")" = "$owner" ] || return 1
    for pid in "$@"; do
      kill -0 "$pid" 2>/dev/null || return 1
    done
    waited=$((waited + 1))
  done
  return 0
}
