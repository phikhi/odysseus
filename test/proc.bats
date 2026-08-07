#!/usr/bin/env bats
#
# The one primitive for waiting on a child this run started.
#
# It has a file of its own because it has a module of its own, and it has a module
# of its own because the line it replaces was written by hand twice — in the gate's
# fan and in `session_spawn` — with the same fault in both ([25], [28]). What is
# checked here is what neither caller's own tests can see: the status a collection
# answers with once a trapped signal has interrupted it.

load helpers/harness
load helpers/assert

setup() {
  harness_setup
}

teardown() {
  # A collection that never returns is one of the failures this file covers, so a
  # test here can leave a spinning process behind. Killed before the tmpdir goes.
  if [ -n "${PACK_BG_PID:-}" ]; then
    kill -KILL "$PACK_BG_PID" 2>/dev/null || true
  fi
  harness_teardown
}

@test "an interrupted wait still answers the status the child really exited with" {
  # The half of the fix no end-to-end test can reach. Both of those — the gate's
  # stop test and the soft-limit one — prove the *waiting*: the branch and the
  # session are given time to finish. Neither proves the *status*, because on the
  # soft-limit path RALPH_SOFT_LIMIT_HIT decides the outcome whatever `wait`
  # returned, and on the normal path the window is microseconds wide.
  #
  # It matters all the same: a bare `wait` hands back 143 when a trap cut it short,
  # and `session_spawn` returns that to the loop as the session's own exit code. A
  # human pressing Ctrl-C would turn a session that went on to succeed into a crash,
  # rollback and all.
  pack_run_bg '
    trap "true" TERM
    ( sleep 1; exit 7 ) &
    victim=$!
    ( sleep 0.3; kill -TERM $$ ) &
    rc=0
    proc_collect "$victim" || rc=$?
    printf "%s\n" "$rc" >"$RALPH_SHIM_STATE/status"
  '

  wait_for_file "$SHIM_STATE/status" 200 ||
    fail "proc_collect never came back after the signal"
  # 7, not 143: the trap fired mid-wait, and the child was waited for again.
  assert_equal "$(cat "$SHIM_STATE/status")" "7"
}

@test "collecting a child a signal killed ends instead of spinning" {
  # The collection re-waits for as long as `wait` answers over 128, because that is
  # what a trapped signal looks like — see proc_collect. A child a signal killed
  # answers over 128 as well, and on bash 3.2 it keeps answering 143 on every later
  # wait instead of "not a child of this shell": probed. The liveness check is
  # therefore the only thing that ends the loop, and taking it out hangs the run
  # rather than failing an assertion — so the deadline for this one lives in the
  # test, which is what lets its mutation be run at all.
  pack_run_bg '
    sleep 30 &
    victim=$!
    kill -TERM "$victim"
    rc=0
    proc_collect "$victim" || rc=$?
    printf "%s\n" "$rc" >"$RALPH_SHIM_STATE/collected"
  '

  wait_for_file "$SHIM_STATE/collected" 100 ||
    fail "proc_collect never came back on a child that had been killed"
  # And it says what happened rather than swallowing it. The gate drops this status
  # — its verdicts are the `.rc` files — but the loop reads it as the session's own.
  assert_equal "$(cat "$SHIM_STATE/collected")" "143"
}

@test "a deadline gives up the moment the shell that armed it is gone" {
  # The primitive under both deadlines of the pack ([36]). `wait` takes no timeout
  # on bash 3.2, so a deadline is a process — and a process outlives whoever wanted
  # it. The gate's watchdog was found writing its marker and walking a process tree
  # after a `kill -9` on the run, on numbers the system reissues.
  #
  # What it watches is a parent link and not a pid, and this test is the reason that
  # distinction is not academic: the stand-in run below is killed outright, and a
  # run killed by a parent that never reaps it stays a zombie that answers `kill -0`
  # exactly like a live process (probed 04/08/2026). Only the link tells the truth,
  # because nothing can become our parent except init.
  pack_run_bg '
    ( rc=0
      proc_countdown 60 || rc=$?
      printf "%s\n" "$rc" >"$RALPH_SHIM_STATE/countdown.rc" ) &
    : >"$RALPH_SHIM_STATE/armed"
    wait
  '

  wait_for_file "$SHIM_STATE/armed" 200 || fail "the stand-in run never armed a deadline"
  kill -9 "$PACK_BG_PID"
  wait "$PACK_BG_PID" 2>/dev/null || true
  PACK_BG_PID=""

  # Sixty seconds of deadline against a run that has just been killed: a countdown
  # that comes back at all comes back because it noticed, not because it finished.
  wait_for_file "$SHIM_STATE/countdown.rc" 200 ||
    fail "the deadline was still counting for a run that no longer exists"
  # 1 and not 0: "I did not serve my time" is what the callers read to mean "do not
  # fire". A countdown that reported success here would arm the very kill it exists
  # to withhold.
  assert_equal "$(cat "$SHIM_STATE/countdown.rc")" "1"
}

@test "a deadline that cannot read a parent link refuses to serve its time" {
  # The fail-closed half of the pair, and a deadline is the only caller that can
  # reach it. A deadline *discovers* its owner — there is no other name for the
  # shell that armed it — so a `ps` that answers nothing leaves it with no owner to
  # watch, and a countdown that served its time on that would arm the very kill the
  # link exists to withhold. An iteration cannot get here: it hands `$$` in, so a
  # `ps` that says nothing is caught one line lower, by the link check itself.
  mkdir -p "$SHIM_STATE/nops"
  printf '#!/usr/bin/env bash\nexit 1\n' >"$SHIM_STATE/nops/ps"
  chmod +x "$SHIM_STATE/nops/ps"

  pack_run_bg '
    PATH="$RALPH_SHIM_STATE/nops:$PATH"
    rc=0
    proc_countdown 60 || rc=$?
    printf "%s\n" "$rc" >"$RALPH_SHIM_STATE/nops.rc"
  '

  # Sixty seconds of deadline against ten of patience: an answer at all is an
  # answer that refused rather than one that finished.
  wait_for_file "$SHIM_STATE/nops.rc" 200 ||
    fail "the deadline served its time with no owner to serve it for"
  assert_equal "$(cat "$SHIM_STATE/nops.rc")" "1"
}

@test "an owner handed in is refused the moment the link no longer leads to it" {
  # The same instrument asked by something bigger than a deadline ([44]). An
  # iteration is a subshell of its pilot, and it has to keep asking "is the run
  # that forked me still there" for as long as it holds anything durable.
  #
  # What is checked here is the half a deadline never needs: the owner is **handed
  # in** rather than discovered. A deadline can only discover — there is no other
  # name for the shell that armed it — but an iteration knows one, `$$` being the
  # pilot in every subshell of a run. Discovery there would put init in the
  # pilot's place for a pilot that died between the fork and the child's first
  # line, and every refusal built on the link would then be armed against a shell
  # that never dies.
  #
  # Both directions in one test on purpose: a refusal that also refused a live
  # owner would pass a one-sided assertion and stop every iteration of every run.
  pack_run_bg '
    (
      rc=0
      proc_owner_take "$$" || rc=$?
      printf "%s\n" "$rc" >"$RALPH_SHIM_STATE/take.alive"
      tries=600
      while [ ! -e "$RALPH_SHIM_STATE/go" ] && [ "$tries" -gt 0 ]; do
        tries=$((tries - 1))
        sleep 0.1
      done
      rc=0
      proc_owner_take "$$" || rc=$?
      printf "%s\n" "$rc" >"$RALPH_SHIM_STATE/take.dead"
    ) &
    : >"$RALPH_SHIM_STATE/forked"
    wait
  '

  wait_for_file "$SHIM_STATE/take.alive" 200 ||
    fail "the child never answered while its forker was alive"
  assert_equal "$(cat "$SHIM_STATE/take.alive")" "0"

  kill -9 "$PACK_BG_PID"
  wait "$PACK_BG_PID" 2>/dev/null || true
  # Cleared so the teardown does not aim at a number the system may have reissued;
  # the child below ends on its own once it has answered.
  PACK_BG_PID=""
  : >"$SHIM_STATE/go"

  wait_for_file "$SHIM_STATE/take.dead" 200 ||
    fail "the child never answered after its forker was killed"
  # 1 and not 0: the pid it was told to expect is no longer the parent it answers
  # to, and nothing but init can have taken that place.
  assert_equal "$(cat "$SHIM_STATE/take.dead")" "1"
}
