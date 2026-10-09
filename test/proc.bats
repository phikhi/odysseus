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
  # And it says what happened rather than swallowing it, which is what both of its
  # callers now depend on: the loop reads this as the session's own exit code, and
  # since [92] the gate reads it as a branch's verdict.
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

# ── what a session leaves in a group of its own ──────────────────────────────

@test "the processes a session's group still holds are the ones it left" {
  # [92]. The walk above answers "what is under this process", and once the
  # process is gone it answers nothing: its children are init's by then, and bash
  # has reaped it before anybody could wait on it. A process group outlives its
  # leader — the number is held for as long as the group has a member — so it is
  # the only handle left on what a session that returned *normally* started.
  #
  # Staged the way `session_spawn` does it: job control for exactly one fork, so
  # the child is a group leader, and the question asked once the leader has been
  # collected.
  printf '%s\n' '#!/usr/bin/env bash' \
    'nohup sleep 30 >/dev/null 2>&1 &' \
    'printf "%s\n" "$!" >"$RALPH_SHIM_STATE/left.pid"' >"$SHIM_STATE/leaver.sh"

  pack_run_bg '
    set -m
    bash "$RALPH_SHIM_STATE/leaver.sh" &
    leader=$!
    set +m
    printf "%s\n" "$leader" >"$RALPH_SHIM_STATE/leader.pid"
    proc_collect "$leader" || true
    proc_group_members "$leader" >"$RALPH_SHIM_STATE/members"
    : >"$RALPH_SHIM_STATE/asked"
  '

  wait_for_file "$SHIM_STATE/asked" 400 ||
    fail "the group was never enumerated"
  local left leader
  left="$(cat "$SHIM_STATE/left.pid")"
  leader="$(cat "$SHIM_STATE/leader.pid")"
  grep -qx "$left" "$SHIM_STATE/members" ||
    fail "the group did not name the process the leader left: $(cat "$SHIM_STATE/members")"
  # And not the leader itself, which is gone: a caller signalling what comes back
  # would be aiming at a pid the system is free to have reissued.
  if grep -qx "$leader" "$SHIM_STATE/members"; then
    fail "the group named its own dead leader"
  fi
  kill -KILL "$left" 2>/dev/null || true
}

@test "the group a shell is in is never the group it is handed back" {
  # The refusal, and it is the half that decides whether this is safe to signal.
  # A shell *without* job control puts a background child in its own group, so a
  # caller asking this about a session spawned without `set -m` would be handed
  # its own siblings — the run, the harness, whatever else the terminal started —
  # and `proc_sweep` would TERM them. What it turns into instead is "nothing
  # was left behind", which is the direction a guard about killing has to fail
  # in.
  pack_run_bg '
    proc_self
    mine="$(ps -o pgid= -p "$PROC_SELF" | tr -d " ")"
    printf "%s\n" "$mine" >"$RALPH_SHIM_STATE/mine"
    proc_group_members "$mine" >"$RALPH_SHIM_STATE/own"
    : >"$RALPH_SHIM_STATE/asked"
  '

  wait_for_file "$SHIM_STATE/asked" 200 || fail "the question was never asked"
  # The group is a real one with real members — this shell is in it — and the
  # answer is still nothing.
  [ -s "$SHIM_STATE/mine" ] || fail "the probe could not read its own group"
  assert_equal "$(cat "$SHIM_STATE/own")" ""
}

# ── the commands this pack did not write, and the group they get ─────────────

@test "a command line the pack was handed is the leader of a group of its own" {
  # [95]. The sweep below can only ever find what a group holds, and a group is
  # not a thing a shell makes by accident: without job control the child sits in
  # the *forking* shell's own group, which `proc_group_members` refuses by design
  # — so a sweep posted over a plain background fork finds nothing at all, and
  # says nothing, and reads exactly like a command that left nothing behind.
  #
  # That is why this is asserted and not assumed: the group is the precondition of
  # the whole ticket, and it is invisible at the surface the other tests watch.
  pack_run_bg '
    proc_self
    ps -o pgid= -p "$PROC_SELF" | tr -d " " >"$RALPH_SHIM_STATE/forker.pgid"
    proc_group_fork "" "sleep 30" >"$RALPH_SHIM_STATE/cmd.out" 2>&1
    printf "%s\n" "$PROC_GROUP_PID" >"$RALPH_SHIM_STATE/cmd.pid"
    ps -o pgid= -p "$PROC_GROUP_PID" | tr -d " " >"$RALPH_SHIM_STATE/cmd.pgid"
    : >"$RALPH_SHIM_STATE/asked"
    kill -KILL "$PROC_GROUP_PID" 2>/dev/null || true
  '

  wait_for_file "$SHIM_STATE/asked" 400 ||
    fail "the fork never came back with a pid to ask about"
  local pid forker group
  pid="$(cat "$SHIM_STATE/cmd.pid")"
  forker="$(cat "$SHIM_STATE/forker.pgid")"
  group="$(cat "$SHIM_STATE/cmd.pgid")"

  # A leader is a process whose group is its own pid, and that is the number the
  # sweep is handed. Reading it off `ps` rather than trusting the fork is the
  # point: this is the one assertion that fails the day somebody drops `set -m`.
  assert_equal "$group" "$pid"
  if [ "$group" = "$forker" ]; then
    fail "the command was left in the group of the shell that forked it ($forker), which is the group proc_group_members refuses"
  fi
  kill -KILL "$pid" 2>/dev/null || true
}

@test "what a command left in its group is asked to stop, and named" {
  # The other half, and it is a request rather than a guarantee: TERM and nothing
  # after it. Staged with nothing hostile — a `&` and a `nohup`, which is what any
  # script that brings a server up before its tests does.
  printf '%s\n' '#!/usr/bin/env bash' \
    'nohup sleep 120 >/dev/null 2>&1 &' \
    'printf "%s\n" "$!" >"$RALPH_SHIM_STATE/left.pid"' >"$SHIM_STATE/leaver.sh"

  pack_run_bg '
    proc_group_fork "" "bash $RALPH_SHIM_STATE/leaver.sh" >"$RALPH_SHIM_STATE/cmd.out" 2>&1
    proc_collect "$PROC_GROUP_PID" || true
    proc_sweep "$PROC_GROUP_PID" "the project of this test" 2>"$RALPH_SHIM_STATE/said"
    : >"$RALPH_SHIM_STATE/swept"
  '

  wait_for_file "$SHIM_STATE/swept" 400 || fail "the sweep never happened"
  local left waited=0
  left="$(cat "$SHIM_STATE/left.pid")"
  while kill -0 "$left" 2>/dev/null; do
    sleep 0.1
    waited=$((waited + 1))
    if [ "$waited" -ge 50 ]; then
      kill -KILL "$left" 2>/dev/null || true
      fail "the process the command left behind was never asked to stop"
    fi
  done

  # Said as well as done, on stderr, and naming the subject a human can act on
  # rather than the pid it cannot ([24]).
  grep -q "the project of this test left 1 process(es) of its own running" \
    "$SHIM_STATE/said" ||
    fail "nothing named what the command left behind: $(cat "$SHIM_STATE/said")"
}

# ── what a program the pack did not write is handed ([101]) ──────────────────
#
# The shape that leaked, reproduced around the primitive that replaces it. A caller
# that holds a channel on a low number and another on a high one, and closes the
# low one the way `receipt_shut`, `receipt_shut_exec` and `gate_notes_shut` did: a
# redirection written on a *function call*. Bash applies that by saving the
# descriptor first, onto the lowest free number from 10 up, so that it can give it
# back when the call returns — and on the bash 3.2 this pack runs under, the copy is
# not close-on-exec. The program at the bottom of the call held the copy.

channels_and_the_old_shut='
  work="$(mktemp -d "$RALPH_SHIM_STATE/chan.XXXXXX")"
  exec 5>"$work/low" 4<"$work/low" 11>"$work/high"
  rm -f "$work/low" "$work/high"
  shut() { eval "\"\$@\" 5>&- 4<&-"; }
'

@test "a program exec'd bare holds nothing above stderr, however its caller closed what it held" {
  fd_forger
  pack_run "$channels_and_the_old_shut"'
    shut proc_exec_bare "$RALPH_SHIM_STATE/fd-forger" program "$RALPH_SHIM_STATE/bare.log" &
    wait "$!"
  '
  assert_success
  assert_forger_found_nothing "$SHIM_STATE/bare.log" "a program exec'd bare"
}

@test "the paired witness: the same caller and the same close, without it" {
  # The half that says the probe sees what it is asked about, and that the leak the
  # primitive exists for is real on this bash rather than remembered. Two things are
  # held here, and they are not the same finding: the high channel, which nobody
  # closed, and a copy of the low one, which the call *did* close.
  fd_forger
  pack_run "$channels_and_the_old_shut"'
    run_forger() { "$RALPH_SHIM_STATE/fd-forger" program "$RALPH_SHIM_STATE/plain.log"; }
    shut run_forger &
    wait "$!"
  '
  assert_success
  grep -q '^probed$' "$SHIM_STATE/plain.log" || fail "the forger never ran"
  grep -q '^OPEN 11$' "$SHIM_STATE/plain.log" ||
    fail "the probe did not see a channel nobody closed: $(cat "$SHIM_STATE/plain.log")"
  local held
  held="$(grep '^OPEN ' "$SHIM_STATE/plain.log" | grep -vc '^OPEN 11$' || true)"
  [ "$held" -ge 1 ] ||
    fail "no copy of the closed channel reached the program — the premise of [101] no longer holds on this bash: $(cat "$SHIM_STATE/plain.log")"
}

@test "a program exec'd bare in the background is what \$! names" {
  # `session_spawn` hands `$!` to the monitor, the collection and the deadline, so
  # the number has to be the program's own and not a shell's around it ([96]
  # measured this for the helper [101] replaced). The function ends in an `exec`,
  # so the background child it runs in *becomes* the program.
  pack_run '
    proc_exec_bare sh -c "echo \$\$ >\"\$RALPH_SHIM_STATE/self.pid\"" &
    printf "%s\n" "$!" >"$RALPH_SHIM_STATE/bang.pid"
    wait "$!"
  '
  assert_success
  assert_equal "$(cat "$SHIM_STATE/self.pid")" "$(cat "$SHIM_STATE/bang.pid")"
}

@test "a command line the pack was handed holds nothing above stderr either" {
  # The other of the two points, reached the way `gate__command_branch` reached it
  # until [101]: through a shut written on the call.
  fd_forger
  pack_run_bg "$channels_and_the_old_shut"'
    shut proc_group_fork "" "$RALPH_SHIM_STATE/fd-forger command $RALPH_SHIM_STATE/group.log"
    proc_collect "$PROC_GROUP_PID" || true
    : >"$RALPH_SHIM_STATE/collected"
  '
  wait_for_file "$SHIM_STATE/collected" 400 || fail "the command was never collected"
  assert_forger_found_nothing "$SHIM_STATE/group.log" "a command line the pack was handed"
}

# ── [102] the hooks git runs for this pack ───────────────────────────────────

# A hook in the common git directory that writes down that it ran, and a git that
# always writes an index — `read-tree` into a scratch index, which fires
# `post-index-change` whatever the tree holds.
proc__plant_index_hook() {
  local hooks
  hooks="$(git -C "$PROJECT_DIR" rev-parse --git-common-dir)/hooks"
  case "$hooks" in /*) ;; *) hooks="$PROJECT_DIR/$hooks" ;; esac
  mkdir -p "$hooks"
  printf '#!/bin/sh\nprintf "ran\\n" >>"%s/hook.ran"\n' "$SHIM_STATE" >"$hooks/post-index-change"
  chmod +x "$hooks/post-index-change"
}

@test "a git started once the hooks are off runs no hook from the common git directory" {
  proc__plant_index_hook
  pack_run 'proc_git_hooks_off; GIT_INDEX_FILE="$RALPH_SHIM_STATE/idx" git read-tree HEAD'
  assert_success
  refute_file_exists "$SHIM_STATE/hook.ran"

  # The paired witness: the same git, the same hook, from a shell that turned
  # nothing off — or the line above is true because the hook never could run.
  pack_run 'GIT_INDEX_FILE="$RALPH_SHIM_STATE/idx2" git read-tree HEAD'
  assert_success
  assert_file_exists "$SHIM_STATE/hook.ran"
}

@test "turning the hooks off keeps what the operator had already told git" {
  # Appended, never substituted: a `GIT_CONFIG_PARAMETERS` the operator exported is
  # configuration they meant every git to read, the pack's own included.
  export GIT_CONFIG_PARAMETERS="'ralph.probe=operator'"
  pack_run 'proc_git_hooks_off
    printf "probe=%s\n" "$(git config ralph.probe)"
    printf "hooks=%s\n" "$(git config core.hooksPath)"'
  assert_success
  assert_output_contains "probe=operator"
  assert_output_contains "hooks=/dev/null"
}

@test "a program exec'd bare gets the operator's git environment back, set or not" {
  # `proc_exec_bare` is how every session and every project command starts, and
  # what they run git with is the operator's business: the project's own hooks run
  # for them as they always did.
  local show='proc_exec_bare sh -c "printf \"%s\\n\" \"\${GIT_CONFIG_PARAMETERS-<unset>}\""'

  export GIT_CONFIG_PARAMETERS="'ralph.probe=operator'"
  pack_run "proc_git_hooks_off; ( $show )"
  assert_success
  assert_equal "$output" "'ralph.probe=operator'"

  unset GIT_CONFIG_PARAMETERS
  pack_run "proc_git_hooks_off; ( $show )"
  assert_success
  assert_equal "$output" "<unset>"
}

@test "a shell that turned nothing off gives nothing back" {
  # A unit test driving a lib, or a fourth entry point: there is no operator value
  # on record, and "not set" would unset the one this shell was started with.
  export GIT_CONFIG_PARAMETERS="'ralph.probe=operator'"
  pack_run '( proc_exec_bare sh -c "printf \"%s\\n\" \"\${GIT_CONFIG_PARAMETERS-<unset>}\"" )'
  assert_success
  assert_equal "$output" "'ralph.probe=operator'"
}

# ── [104] what git runs for this pack holds nothing of it ────────────────────
#
# The two doors [102]'s token leaves, from the two places a session can write and
# no unset of the run reaches in time: a hook configured in the repository, which a
# sibling iteration runs before its own put-back, and a key of the operator's
# `~/.gitconfig`, here `core.fsmonitor`. Each program is the forger, so what it could
# reach is what it writes down, and each writes to a log of its own so that "it
# never ran" cannot pass for "it found nothing" ([80]).

proc__plant_git_programs() {
  fd_forger
  printf '#!/bin/sh\ncat >/dev/null 2>&1\n"%s/fd-forger" forged "%s/hook.log"\nexit 0\n' \
    "$SHIM_STATE" "$SHIM_STATE" >"$SHIM_STATE/configured-hook"
  printf '#!/bin/sh\n"%s/fd-forger" forged "%s/fsmonitor.log"\nexit 1\n' \
    "$SHIM_STATE" "$SHIM_STATE" >"$SHIM_STATE/fsmonitor"
  chmod +x "$SHIM_STATE/configured-hook" "$SHIM_STATE/fsmonitor"
  git -C "$PROJECT_DIR" config hook.planted.command "$SHIM_STATE/configured-hook"
  git -C "$PROJECT_DIR" config --add hook.planted.event post-index-change
  git -C "$PROJECT_DIR" config --add hook.planted.event reference-transaction
  git config --global core.fsmonitor "$SHIM_STATE/fsmonitor"
}

# The three gestures a run makes most — an index refresh, an index written into a
# scratch file, a ref moved — each written with a redirection on the call, which is
# how the pack writes them and what makes bash save a copy of fd 2 ([101]). `$1` is
# the word that runs git.
proc__git_gestures() {
  printf '%s\n' "$channels_and_the_old_shut"'
    proc_git_hooks_off
    '"$1"' status --porcelain >/dev/null 2>&1
    GIT_INDEX_FILE="$RALPH_SHIM_STATE/gesture.idx" '"$1"' read-tree HEAD 2>/dev/null
    '"$1"' update-ref refs/heads/ralph-probe HEAD 2>/dev/null
  '
}

@test "a program git runs out of configuration holds nothing of the shell that ran it" {
  proc__plant_git_programs
  pack_run "$(proc__git_gestures proc_git)"
  assert_success
  assert_forger_found_nothing "$SHIM_STATE/hook.log" "a hook configured in the repository"
  assert_forger_found_nothing "$SHIM_STATE/fsmonitor.log" "a core.fsmonitor of the operator's ~/.gitconfig"
}

@test "the paired witness: the same programs under a bare git hold the shell's channels" {
  # The token is on in both, so this is not the hook directory: it is the half
  # [102] could not reach, and the reason [104] exists. The channels the caller
  # holds on 5, 4 and 11 are what each program finds.
  proc__plant_git_programs
  pack_run "$(proc__git_gestures git)"
  assert_success
  local who
  for who in hook fsmonitor; do
    grep -q '^probed$' "$SHIM_STATE/$who.log" || fail "the $who never ran: the witness proves nothing"
    grep -q '^OPEN 5$' "$SHIM_STATE/$who.log" ||
      fail "the $who under a bare git did not hold the caller's channel: $(cat "$SHIM_STATE/$who.log")"
  done
}

@test "a git run that way keeps the token, its status, its streams and the assignment in front of it" {
  # What a caller writes around a git call is what it wrote around git itself, or
  # eighty-five call sites changed meaning when they changed name. And the one thing
  # `proc_exec_bare` does that this must not: hand the operator's environment back,
  # which would hand git the hook directory again.
  pack_run '
    proc_git_hooks_off
    printf "hooks=%s\n" "$(proc_git config core.hooksPath)"
    rc=0
    proc_git rev-parse --verify --quiet refs/heads/ralph-no-such >/dev/null || rc=$?
    printf "status=%s\n" "$rc"
    printf "stderr=%s\n" "$(proc_git rev-parse --verify refs/heads/ralph-no-such 2>&1 >/dev/null || true)"
    printf "stdin=%s\n" "$(printf "HEAD\n" | proc_git cat-file --batch-check | cut -d" " -f2)"
    GIT_INDEX_FILE="$RALPH_SHIM_STATE/own.idx" proc_git read-tree HEAD
    printf "after=[%s]\n" "${GIT_INDEX_FILE-unset}"
  '
  assert_success
  assert_output_contains "hooks=/dev/null"
  assert_output_contains "status=1"
  assert_output_contains "stderr=fatal: Needed a single revision"
  assert_output_contains "stdin=commit"
  assert_output_contains "after=[unset]"
  assert_file_exists "$SHIM_STATE/own.idx"
}

# ── [105] the curl this pack runs holds nothing and reads nothing ────────────
#
# Two halves, asked separately because each holds what the other cannot. The
# descriptors are asked of a forger standing where curl is resolved, so that what it
# could reach is what it writes down; the configuration is asked of the machine's
# real curl and a `~/.curlrc` in the test's `$HOME`, because the fake curl of this
# suite reads no file at all and would be green on both sides.

# A program named `curl`, first on the PATH a snippet sets, that is the forger.
proc__curl_is_a_forger() {
  fd_forger
  mkdir -p "$SHIM_STATE/forger-bin"
  printf '#!/bin/sh\nexec "%s/fd-forger" curl "%s/%s"\n' "$SHIM_STATE" "$SHIM_STATE" "$1" \
    >"$SHIM_STATE/forger-bin/curl"
  chmod +x "$SHIM_STATE/forger-bin/curl"
}

@test "a curl the pack runs holds nothing above stderr, however its caller wrote the call" {
  proc__curl_is_a_forger curl.log
  pack_run "$channels_and_the_old_shut"'
    PATH="$RALPH_SHIM_STATE/forger-bin:$PATH"
    shut proc_curl -sS https://endpoint.invalid/ 2>/dev/null
  '
  assert_success
  assert_forger_found_nothing "$SHIM_STATE/curl.log" "a curl the pack runs"
}

@test "the paired witness: the same call to a bare curl holds the caller's channels" {
  # What a `~/.curlrc` reached until [105]: the high channel nobody closed, and the
  # copy bash kept of the low one a shut *did* close.
  proc__curl_is_a_forger bare.log
  pack_run "$channels_and_the_old_shut"'
    PATH="$RALPH_SHIM_STATE/forger-bin:$PATH"
    shut curl -sS https://endpoint.invalid/ 2>/dev/null
  '
  assert_success
  grep -q '^probed$' "$SHIM_STATE/bare.log" || fail "the forger never ran: the witness proves nothing"
  grep -q '^OPEN 11$' "$SHIM_STATE/bare.log" ||
    fail "a bare curl did not hold the caller's channel: $(cat "$SHIM_STATE/bare.log")"
}

@test "a curl the pack runs reads no configuration a session could have written" {
  # The real curl of this machine, and a `~/.curlrc` of the shape `f5` measured: a
  # `url =` with no output, whose body lands in the stdout the caller parses even
  # though the request on the line fails (every request here is pointed at a
  # closed port). The paired witness is the same call from the same shell to a
  # curl started without the pack's function — the file is one curl reads, or the
  # first line would be empty for the wrong reason.
  local real
  real="$(PATH="${PATH#"$SHIM_BIN":}" command -v curl)" || fail "no curl on this machine"
  mkdir -p "$SHIM_STATE/real-bin"
  ln -s "$real" "$SHIM_STATE/real-bin/curl"
  printf 'FORGED-BY-CURLRC\n' >"$SHIM_STATE/forged.txt"
  printf 'url = "file://%s/forged.txt"\n' "$SHIM_STATE" >"$HOME/.curlrc"

  pack_run '
    PATH="$RALPH_SHIM_STATE/real-bin:$PATH"
    ask() { "$@" -sS --max-time 3 --connect-to ::127.0.0.1:9 https://endpoint.invalid/ 2>/dev/null || true; }
    printf "pack=[%s]\n" "$(ask proc_curl)"
    printf "bare=[%s]\n" "$(ask curl)"
  '
  assert_success
  assert_output_contains "pack=[]"
  assert_output_contains "bare=[FORGED-BY-CURLRC]"
}

@test "a curl run that way keeps its status, its streams and the arguments it was given" {
  # Two call sites changed name, and what they write around the call has to mean
  # what it meant around curl: the status is curl's, stdout is the body, stderr goes
  # where the caller sends it.
  local real
  real="$(PATH="${PATH#"$SHIM_BIN":}" command -v curl)" || fail "no curl on this machine"
  mkdir -p "$SHIM_STATE/real-bin"
  ln -s "$real" "$SHIM_STATE/real-bin/curl"
  printf 'the body\n' >"$SHIM_STATE/body.txt"

  pack_run '
    PATH="$RALPH_SHIM_STATE/real-bin:$PATH"
    rc=0
    proc_curl -sS --max-time 3 --connect-to ::127.0.0.1:9 https://endpoint.invalid/ >/dev/null 2>&1 || rc=$?
    printf "status=%s\n" "$rc"
    printf "stderr=%s\n" "$(proc_curl -sS --max-time 3 --connect-to ::127.0.0.1:9 https://endpoint.invalid/ 2>&1 >/dev/null || true)"
    printf "stdout=%s\n" "$(proc_curl -sS "file://$RALPH_SHIM_STATE/body.txt" 2>/dev/null)"
  '
  assert_success
  assert_output_contains "status=7"
  assert_output_contains "stderr=curl: (7)"
  assert_output_contains "stdout=the body"
}

# ── [106] a line of the configuration the pack evaluates ─────────────────────
#
# The two token commands are lines the operator wrote and the pack evaluates; what
# they run may be a script under a `HOME` the session shares. The line here is the
# forger, so what it could reach is what it writes down, and it prints a token
# after, as a token command does.

proc__token_line='
  line="\"\$RALPH_SHIM_STATE/fd-forger\" line \"\$RALPH_SHIM_STATE/eval.log\"; printf tok"
'

@test "a line of the configuration the pack evaluates holds nothing above stderr, however its caller wrote the call" {
  # The shape of the two call sites, and the same call under a shut written on it —
  # the redirection on a function call that makes bash keep a copy of what it
  # closes ([101]).
  fd_forger
  pack_run "$channels_and_the_old_shut$proc__token_line"'
    token="$(proc_eval_bare "$line" 2>/dev/null)"
    printf "token=%s\n" "$token"
    shut proc_eval_bare "$line" 2>/dev/null >/dev/null
  '
  assert_success
  assert_output_contains "token=tok"
  [ "$(grep -c '^probed$' "$SHIM_STATE/eval.log")" = 2 ] ||
    fail "the line did not run once per call: $(cat "$SHIM_STATE/eval.log")"
  assert_forger_found_nothing "$SHIM_STATE/eval.log" "a line the pack evaluates"
}

@test "the paired witness: the same line under the eval it replaced holds the caller's channels" {
  # `$( … )` redirects stdout and nothing else, which is what [105] measured four
  # lines of a receipt through. Both channels a caller holds open for writing are
  # found: the low one and the high one.
  fd_forger
  pack_run "$channels_and_the_old_shut$proc__token_line"'
    token="$(eval "$line" 2>/dev/null)"
    printf "token=%s\n" "$token"
  '
  assert_success
  assert_output_contains "token=tok"
  grep -q '^probed$' "$SHIM_STATE/eval.log" || fail "the forger never ran: the witness proves nothing"
  grep -q '^OPEN 5$' "$SHIM_STATE/eval.log" && grep -q '^OPEN 11$' "$SHIM_STATE/eval.log" ||
    fail "a bare eval did not hold the caller's channels: $(cat "$SHIM_STATE/eval.log")"
}

@test "a line evaluated that way keeps its status, its streams, the pack's variables and functions, and gets the operator's environment back" {
  # What an operator may write in the line is what they could write before: a key
  # of the sealed configuration it was read out of, which the pack does not export
  # (`bash -c` would hand the forge no token), and a function of the pack. What it
  # is handed of git's environment is the operator's — `gh auth token` runs git's
  # credential machinery the way it does from their shell — while the caller keeps
  # [102]'s token. And an assignment the line makes stays where it was made.
  export GIT_CONFIG_PARAMETERS="'ralph.probe=operator'"
  pack_run '
    proc_git_hooks_off
    SEALED_KEY=sealed
    pack_fn() { printf "from-the-pack"; }
    rc=0
    proc_eval_bare "exit 3" || rc=$?
    printf "status=%s\n" "$rc"
    printf "stdout=%s\n" "$(proc_eval_bare "printf \"%s\" \"\$SEALED_KEY\"")"
    printf "stderr=%s\n" "$(proc_eval_bare "printf oops >&2" 2>&1 >/dev/null)"
    printf "function=%s\n" "$(proc_eval_bare pack_fn)"
    printf "given=%s\n" "$(proc_eval_bare "printf \"%s\" \"\${GIT_CONFIG_PARAMETERS-<unset>}\"")"
    printf "kept=%s\n" "$GIT_CONFIG_PARAMETERS"
    proc_eval_bare "LEAKED=yes"
    printf "after=[%s]\n" "${LEAKED-unset}"
  '
  assert_success
  assert_output_contains "status=3"
  assert_output_contains "stdout=sealed"
  assert_output_contains "stderr=oops"
  assert_output_contains "function=from-the-pack"
  assert_output_contains "given='ralph.probe=operator'"
  refute_output_contains "given='ralph.probe=operator' 'core.hooksPath"
  assert_output_contains "kept='ralph.probe=operator' 'core.hooksPath=/dev/null'"
  assert_output_contains "after=[unset]"
}

@test "a line the pack evaluates reads none of its caller's stdin, in the loop that drains a list either" {
  # The shape of `failures_quarantine_strays` (`.scratch/ralph-pack/sondes/ticket-106/s1`):
  # a `while read` over a heredoc, one remote request — one evaluation of the token
  # command — per item. Under the eval it replaced, the line read the rest of the
  # list, and the loop never saw the second item: on a remote night, a stray the
  # session gave itself left `ready-for-agent` with no line naming it. The paired
  # witness is the same loop under that eval. And a pipe, the other stdin a caller
  # can have.
  pack_run '
    while read -r item; do
      printf "pack %s:[%s]\n" "$item" "$(proc_eval_bare cat)"
    done <<LIST
one
two
LIST
    while read -r item; do
      printf "bare %s:[%s]\n" "$item" "$(eval cat)"
    done <<LIST
one
two
LIST
    printf "pipe=[%s]\n" "$(printf "held\n" | proc_eval_bare cat)"
  '
  assert_success
  assert_output_contains "pack one:[]"
  assert_output_contains "pack two:[]"
  assert_output_contains "bare one:[two]"
  refute_output_contains "bare two"
  assert_output_contains "pipe=[]"
}

# ── a channel nobody else holds ([103]) ──────────────────────────────────────
#
# The instant a channel's file has a name — from the module's `mktemp` to the
# opener's `rm -f` — staged rather than raced. The opener calls `rm` by name, so a
# function of that name runs in its place, does what a process polling `$TMPDIR`
# would have done in that instant, and then unlinks the file for real. Every case
# below is the same staging with one gesture changed, and the first one is the
# witness that says the staging alone refuses nothing.

channel_staged='
  proc_channel_preflight
  work="$(mktemp -d "$RALPH_SHIM_STATE/chan.XXXXXX")"
  file="$(mktemp "$work/channel.XXXXXX")"
  last() { local a; for a in "$@"; do :; done; printf "%s\n" "$a"; }
'

channel_asked='
  rc=0
  proc_channel_open 5 4 "$file" || rc=$?
  printf "rc=%s\n" "$rc"
  printf "refusal=[%s]\n" "$PROC_CHANNEL_REFUSAL"
  printf "left=[%s]\n" "$(ls -A "$work" | tr "\n" " ")"
  if [ -e /dev/fd/5 ]; then printf "write=open\n"; else printf "write=shut\n"; fi
  if [ -e /dev/fd/4 ]; then printf "read=open\n"; else printf "read=shut\n"; fi
'

@test "a channel nothing else holds is served, with no name left" {
  pack_run "$channel_staged"'
    rm() { command rm "$@"; }
    '"$channel_asked"'
    printf "a record\n" >&5
    IFS= read -r back <&4
    printf "back=[%s]\n" "$back"'
  assert_success
  assert_output_contains "rc=0"
  assert_output_contains "refusal=[]"
  assert_output_contains "left=[]"
  assert_output_contains "write=open"
  assert_output_contains "read=open"
  # And it is a channel: what goes in one end comes out of the other.
  assert_output_contains "back=[a record]"
}

@test "a channel another process opened in the instant it had a name is refused, and names it" {
  # The case [103] exists for. The holder is not a descendant of the opener — its
  # copies of 5 and 4 are closed before it runs, as a process the session left
  # behind holds nothing of this shell — and it keeps the descriptor it opened by
  # name once the name is gone, which is what the survivor of `f3` did twelve times
  # out of twelve.
  pack_run "$channel_staged
    $(channel_window_held)
    $channel_asked"
  kill -KILL "$(cat "$SHIM_STATE/holder.pid" 2>/dev/null)" 2>/dev/null || true
  assert_success
  assert_file_exists "$SHIM_STATE/holder.ready"
  assert_output_contains "rc=1"
  assert_output_contains "process $(cat "$SHIM_STATE/holder.pid") on its descriptor 7"
  assert_output_contains "in the instant between its creation and its unlink"
  # Refused is both ends closed and no name: nothing of it is left to be used.
  assert_output_contains "left=[]"
  assert_output_contains "write=shut"
  assert_output_contains "read=shut"
}

@test "a byte written into a channel in that instant is refused, even once its writer let go" {
  # The holder that does not stay: it opens, writes and closes before anyone looks,
  # so no listing can find it. What it left is the byte.
  pack_run "$channel_staged"'
    rm() {
      printf "note\tFORGED\n" >>"$(last "$@")"
      command rm "$@"
    }
    '"$channel_asked"
  assert_success
  assert_output_contains "rc=1"
  assert_output_contains "byte(s) were in it before this shell wrote one"
  assert_output_contains "write=shut"
  assert_output_contains "read=shut"
}

@test "a channel whose file kept a name somewhere is refused" {
  # A second name made in that instant: the unlink takes the one the module chose
  # and leaves the file reachable by the other, for as long as anybody likes.
  pack_run "$channel_staged"'
    rm() {
      ln "$(last "$@")" "$RALPH_SHIM_STATE/kept"
      command rm "$@"
    }
    '"$channel_asked"
  assert_success
  assert_file_exists "$SHIM_STATE/kept"
  assert_output_contains "rc=1"
  assert_output_contains "still had a name once it was unlinked"
  assert_output_contains "write=shut"
}

@test "a fifo put in place of a channel's name neither hangs the opener nor is served" {
  # The denial half of the same instant: a write-only open of a fifo nobody reads
  # never returns. Run in the background with a deadline, because the failure this
  # covers is a call that does not come back.
  pack_run_bg "$channel_staged"'
    command rm -f "$file"
    mkfifo "$file"
    rm() { command rm "$@"; }
    '"$channel_asked"'
    : >"$RALPH_SHIM_STATE/returned"'
  wait_for_file "$SHIM_STATE/returned" 200 ||
    fail "the opener never came back from a fifo: $(cat "$RALPH_TEST_DIR/bg.out")"
  wait "$PACK_BG_PID" || true
  local out
  out="$(cat "$RALPH_TEST_DIR/bg.out")"
  printf '%s\n' "$out" | grep -q "rc=1" || fail "a fifo was served as a channel: $out"
  printf '%s\n' "$out" | grep -q "not a regular file but a FIFO" ||
    fail "the refusal does not say what stood in the file's place: $out"
}

@test "a check runs the lsof the pilot resolved, never the one PATH answers later" {
  # What a session can do between two iterations: put an `lsof` of its own in front
  # of the real one. This one answers nothing — which, read, refuses every channel —
  # and it leaves a trace if it ever runs.
  mkdir -p "$SHIM_STATE/planted"
  cat >"$SHIM_STATE/planted/lsof" <<PLANT
#!/bin/sh
: >"$SHIM_STATE/planted.ran"
PLANT
  chmod +x "$SHIM_STATE/planted/lsof"

  pack_run "$channel_staged"'
    PATH="$RALPH_SHIM_STATE/planted:$PATH"
    printf "resolved=[%s]\n" "$PROC_CHANNEL_LSOF"
    rm() { command rm "$@"; }
    '"$channel_asked"
  assert_success
  refute_file_exists "$SHIM_STATE/planted.ran"
  assert_output_contains "rc=0"
  refute_output_contains "resolved=[$SHIM_STATE/planted/lsof]"
  refute_output_contains "resolved=[]"
}

@test "a shell nobody resolved a lister in refuses every channel rather than reads it as checked" {
  # A unit test driving a lib, or an entry point that skipped the preflight: there
  # is no answer to who holds the channel, and no answer is not "nobody".
  pack_run '
    work="$(mktemp -d "$RALPH_SHIM_STATE/chan.XXXXXX")"
    file="$(mktemp "$work/channel.XXXXXX")"
    '"$channel_asked"
  assert_success
  assert_output_contains "rc=1"
  assert_output_contains "answered nothing, so nobody checked"
  assert_output_contains "left=[]"
  assert_output_contains "write=shut"
}

@test "a run on a machine with no lsof is refused before a session is spawned" {
  # Every channel of such a run would be refused — no receipt, no gate, no lens —
  # so it is refused at the door instead, where the operator reads why.
  local entry nolsof='' found=0
  local IFS=:
  for entry in $PATH; do
    if [ -x "$entry/lsof" ]; then
      found=1
      continue
    fi
    nolsof="${nolsof:+$nolsof:}$entry"
  done
  unset IFS
  [ "$found" = 1 ] || fail "no lsof on this test's PATH, so this test proves nothing: $PATH"

  local saved="$PATH"
  PATH="$nolsof"
  run_loop
  PATH="$saved"
  assert_failure 2
  assert_output_contains "lsof is on no PATH directory"
  assert_equal "$(claude_call_count)" "0"
}
