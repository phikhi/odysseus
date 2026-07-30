# shellcheck shell=bash
# The processes this run started, and how it waits for them.
#
# One function, and it exists as a module rather than as a private helper because
# the pack has already paid twice for the line it replaces. `wait` was written out
# by hand in the gate's fan and again in `session_spawn`, separately, with the same
# fault in both — and the second copy sat on a longer window. A primitive of the
# loop is a defect repeated as many times as it is called ([25], [28]), so the
# third caller has to find it here instead of writing a fourth one.
#
# Layering is what settled where it lives. `gate__collect` was private to the gate,
# and `test/layering.bats` refuses a lib that reaches into a neighbour's `__`
# internals: a second caller means the function is public, so it gets renamed and
# placed rather than copied. Neither `session.sh` nor `gate.sh` could own it — each
# would be reaching into the other — and `state.sh` is about run state, not about
# child processes.

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
