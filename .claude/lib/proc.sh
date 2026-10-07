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
#
# And what the command holds is nothing but that stdin, its stdout and its stderr:
# it is exec'd through `proc_exec_bare`, below, for the reason written there.
proc_group_fork() {
  local cwd="$1" cmd="$2"
  PROC_GROUP_PID=''
  set -m
  (
    [ -z "$cwd" ] || cd "$cwd"
    proc_exec_bare bash -c "$cmd"
  ) </dev/null &
  PROC_GROUP_PID=$!
  set +m
  return 0
}

# Replace this shell by a program that holds nothing but stdin, stdout and stderr
# ([101]). The last thing a forked child does, and nothing else: called from a shell
# that means to go on, it would close that shell's own channels and then replace it.
#
# There are exactly four callers, and they are the four points where this pack
# hands a program it did not write the descriptors of the shell that forks it: the
# background child of `session_spawn`, which is every `claude` the pack runs, the
# child of `proc_group_fork` above, which is every command line a project wrote —
# `TEST_CMD`, `TYPECHECK_CMD`, `RUN_CMD`, `VISUAL_CMD` ([95]'s census) — the
# `lsof` that `proc__channel_alone` below asks who holds a channel ([103]), which
# would otherwise be a holder of the very channel it is asked about, and the
# subshell of `proc_curl` below, which is every curl the pack runs ([105]).
# What is *not* here is written down so that it reads as a decision: the
# `*_TOKEN_CMD` lines and the scheduler's submission are commands the operator
# wrote, not the project and not the session; and a program git runs for the pack
# — a hook, a `core.fsmonitor` — is exec'd by git and never passes through here.
# That one is answered twice, one level up: git is told by the environment of every
# shell of the run that it has no hook directory (`proc_git_hooks_off`, [102]), and
# git itself is started holding nothing above stderr (`proc_git`, [104]), so
# whatever configuration makes it run has nothing of the pack's to hand down. And
# the program exec'd here is handed that environment back the way the operator had
# it, which is the second thing this function does — for the same reason as the
# first: a program the pack did not write has no business with anything the pack
# set up for itself.
#
# **Why everything above 2 and not the numbers this pack opened, which is how it
# was done until this ticket and what made [94] and [96] green on a hole.** Each
# channel used to be closed by its own module, by a redirection written on a
# *function call* — `receipt_shut` was `eval "\"\$@\" 5>&- 4<&-"`, and
# `gate_notes_shut` and `receipt_shut_exec` were the same shape. Bash applies a
# redirection on a function call, or on an `exec` that carries a command, by first
# *saving* the descriptor, so that it can give it back when the call returns: it
# duplicates it onto the lowest free number from 10 up, and on the bash 3.2 this
# pack runs under that copy is not close-on-exec. So the program launched inside
# the call inherited the very descriptor the call was closing, under another
# number. Measured on 29/09/2026 in the pack: the judged session held the
# receipt's write end on fd 10 and put one line of its own in its own receipt
# through it, and the project's test command and every review lens held two write
# ends, on 12 and 14. Reproduced outside the pack with `lsof`, the copies are the
# closed descriptors themselves under new numbers, write ends included. The tests
# asked the programs about 5, 4, 9 and 8 — the numbers the pack derived — and those
# were closed.
#
# An `exec` with no command makes its redirections permanent and saves nothing, so
# this closes the numbers this pack opened *and* every copy bash made on the way
# down, in the child and after the fork, where nothing is left to give them back
# to. And it closes everything rather than a list, because the list is exactly what
# lied: a program the pack did not write has no business with any descriptor but
# the three it is handed, and a module that opens a channel tomorrow is covered
# without having to know that this line exists. Up to 255 because that is where
# bash keeps the script it is reading, and the copies it makes are allocated from
# 10 upwards at the lowest free number; nothing in this pack holds a descriptor
# above that. Measured at 0.8 ms a fork for the whole list when each call built it;
# since [104] it is built once (`PROC__ABOVE_STDERR`, below), because `proc_git`
# hands the same list to every git of a run.
proc_exec_bare() {
  eval "exec $PROC__ABOVE_STDERR"
  proc_git_hooks_given_back
  exec "$@"
}

# Every descriptor above stderr, as the redirections that close it: `3>&- 4>&- …
# 255>&-`. Built once, when this module is sourced, by builtins alone — `printf -v`
# and a brace range, no fork and no name resolved ([52]) — for the two functions
# that hand it to an `exec`: `proc_exec_bare` above, and `proc_git` below, which runs
# on every git of a run. One definition and not two loops, because the list is the
# thing that lied before [101], and a third caller should find it rather than retype
# it.
printf -v PROC__ABOVE_STDERR '%s>&- ' {3..255}

# Run git holding nothing above stderr of the shell that runs it ([104]). Every git
# this pack starts goes through here, and a census in `test/gate.bats` refuses a
# bare one anywhere else in the pack's code — a `$( … )` in an unquoted heredoc
# included, where five of them were — with one zone left out and its reason written
# there: `init.sh`, which a human runs outside any run and which may be driving a
# pack of another version, holds no descriptor of its own to hand down.
#
# **Why git, when it is not one of the programs above.** Git runs programs on its
# own, out of configuration, and every one of them is a descendant of the shell that
# ran git: until this function it held that shell's descriptors — an iteration's
# receipt ([96]), a gate's notes ([94]), the read end of a lens's prompt, the
# monitor's stream. [102] took away the hook *directory*. What was left is everything
# else configuration can name, and a session writes configuration: a hook it
# configures (`hook.<name>.command` and `.event`, git 2.5x), which [46] removes once
# the session is gone — too late for a sibling iteration already past its own
# put-back — and any key of the operator's `~/.gitconfig` that names a program,
# `core.fsmonitor` first, which no unset of this repository reaches. Measured on
# 01/10/2026 with a forger as each program (`.scratch/ralph-pack/sondes/ticket-102/h4`):
# a configured hook planted while a sibling was held in its gate put fourteen lines
# into the sibling's receipt; from `~/.gitconfig` at MAX_PARALLEL=1, a configured
# hook put twenty-four into its own iteration's, and a `core.fsmonitor` — 978 runs
# over two iterations — two hundred and four, through descriptors 3, 5, 6 and 9.
#
# So the property moved from what git runs, which configuration decides and a
# session writes, to what git holds, which this shell decides: nothing a program git
# starts could inherit, whatever named it, wherever the name came from, at any
# MAX_PARALLEL. Not a list of the verbs that launch something: `core.fsmonitor` runs
# on index refreshes no hook census sees ([51], `h1`), and a list is a thing that
# has to be right again tomorrow.
#
# The shape of `proc_exec_bare`, with one difference that is the point: the
# environment is **not** handed back — git keeps [102]'s token, or the hook directory
# would be read again. A subshell and an `exec` with no command rather than a
# redirection on the call, for the reason [101] measured: bash *saves* a descriptor
# it is asked to close on a function call, onto a number from 10 up, and the program
# inherits the copy. Closing everything in the subshell also closes the copies bash
# made for whatever the caller wrote on this very call, `2>/dev/null` included.
#
# What a caller writes keeps its meaning, measured on bash 3.2.57: the status is
# git's; stdin, stdout and stderr are the caller's; and an assignment in front —
# `GIT_INDEX_FILE="$idx" proc_git read-tree …` — is exported to git for that call
# and gone after it, as it was in front of git itself. The cost is no fork the bare
# call did not make already, and 253 closes: 0.3 to 0.7 ms on a 12 ms `rev-parse`.
#
# **What this does not take away**, written where it is claimed. A program git runs
# still gets the environment the pack exported, still runs at the instant the pack
# chose, and still answers what git asks it — a `core.fsmonitor` says which files
# changed, a filter hands back a content: [46] watches the keys that name one and
# charges whoever moved them, and that is where those are held. It can still make a
# transaction fail: a `reference-transaction` that exits non-zero on `prepared`
# aborts the `update-ref` (measured, status 128), which a session can already do with
# a `.lock` file beside the ref (measured, the same 128), and every caller here reads
# a refused `update-ref` as a refusal. What it writes goes where git's stderr goes —
# nowhere on every call but the three `git add` of the gate's index builds, where it
# can add words to the `git said:` of a refusal and make `gate__walk_incomplete`
# answer yes: a red, never a green. And on a system that names another process's
# descriptors by path, Linux's `/proc/<pid>/fd`, it can walk up to the shell that ran
# git and reopen what that shell holds — `proc_channel_open`'s bound, unchanged.
proc_git() {
  (
    eval "exec $PROC__ABOVE_STDERR"
    exec git "$@"
  )
}

# Run curl holding nothing above stderr, and reading no configuration ([105]).
# Every curl this pack starts goes through here — the usage endpoint the pilot
# asks (`budget__request`) and every request a remote tracker backend makes
# (`forge__http`), from the pilot and from an iteration — and a census of
# `proc_git`'s shape in `test/gate.bats` refuses a bare one anywhere else in the
# pack's code.
#
# **Why curl.** It is the one program on [91]'s list that reads a file of the
# user's every time it starts: `~/.curlrc`, `~/.config/curlrc`,
# `$CURL_HOME/.curlrc`. A session runs with the operator's `HOME` and writes all
# three, and a line of that file adds a URL and an output of the session's
# choosing to the pack's own call. Curl needs to launch nothing: it writes there
# itself, at the instant the pack chose, with the descriptors the pack held, and
# into the stdout the pack parses. Measured on 07/10/2026, curl 8.7.1 on darwin
# (`.scratch/ralph-pack/sondes/ticket-98/`, `f4` in the pack and `f5` outside it):
# `output = "/dev/fd/5"` beside a `file://` URL put four lines into the receipt of
# a remote backend through the iteration's channel — whatever `-o` the command
# line carried — run `0`, ticket `resolved`; a `url =` with no output put a body
# of the session's into what `$( curl … )` hands back, under the real request's
# own failure (status 7); and `data-binary = "@/dev/fd/N"` emptied a read end
# before its reader got to it. A file of such pairs over every number from 3 to
# 255 needs to know none of them: curl refuses the numbers that are not open and
# goes on to the next URL.
#
# So two halves, and each holds what the other cannot:
#
#   descriptors     `proc_exec_bare` in a subshell — the shape of `proc_git`, and
#                   the same list closed: nothing of the pack's to write to or to
#                   drain, whatever a configuration names. It costs the operator
#                   nothing.
#   configuration   `-q`, which curl honours as its **first** argument and only
#                   there (measured: `-sS -q` reads the file). It is the one half
#                   that holds the body added to stdout, which needs no
#                   descriptor at all; that is why it is written here, in the one
#                   function, and not at each call.
#
# **The price is the operator's, and it is written where it is paid.** `-q` turns
# off the operator's own `~/.curlrc` too: a proxy, a CA bundle, a `--resolve`, a
# client certificate. What curl takes from the environment it still takes —
# measured under `-q`: `HTTPS_PROXY` is used and `CURL_CA_BUNDLE` is read — and
# the environment is the shell that started the run, which no session writes.
# What only a curlrc can carry is lost, and a request that needed it fails the way
# any request fails here: a usage endpoint the run says it could not read, a
# backend operation refused by its return code. `ralph.config.sh.example` says so
# beside the URLs, where an operator who needs it will look. [102] wrote the price
# of its own switch the same way: the `pre-push` of git-lfs, which no push says.
#
# The environment is handed back by `proc_exec_bare`, as to every program the pack
# did not write; curl reads nothing of git's, so for it that changes nothing.
#
# **What this does not take away.** Curl still asks the URL the sealed
# configuration named, at the instant the pack chose, and what comes back is what
# the endpoint or the forge answered — a session that can reach the forge writes
# the tracker already ("Ce qu'une session écrit dans le tracker d'un backend
# distant"), and that line holds it. Stdin is the caller's, and curl reads it only
# when an argument says so (`@-`): no call here does, and every body the adapters
# send is a JSON object, which starts with `{` and never with the `@` that would
# make `--data-binary` read a file. And a descriptor above 255, or Linux's
# `/proc/<pid>/fd`, is the bound of `proc_git` above, unchanged.
proc_curl() {
  ( proc_exec_bare curl -q "$@" )
}

# ── a channel nobody else holds ([103]) ──────────────────────────────────────
#
# Three channels of this pack keep what they carry out of a process's reach by
# having no name: the audit receipt's ([96]), the notes a gate's branches answer on
# and the prompt a review lens is handed ([94]). Each is a file made by `mktemp`,
# opened twice — once to write, once to read from offset zero — and unlinked before
# a byte goes into it, so that the only handles on it are the descriptors of the
# shell that opened it and of what that shell forks.
#
# **Unlinked is not never named, and the difference was measured.** The file has a
# name from its `mktemp` to its `rm -f`, and that `rm` is an external program: a
# millisecond or two. A process the judged session left behind, polling `$TMPDIR`
# in a loop without sleeping, finds the name in that instant, opens it, and keeps
# the descriptor once the name is gone — on 29/09/2026, twelve openings won out of
# twelve and 270 forged lines in one receipt, on the code [96] shipped. Nothing
# about the name closes that. `mktemp` makes it unpredictable, not unlistable; a
# file mode or an ACL keeps out another user and not this one; a directory made
# unreadable (`mkdir -m 0300`) stops a process that globs and opens, and not one
# that knows this pack, which can `chmod u+r` what it owns inside the same window;
# and a shorter window closes nothing, because a process that loops wins it for as
# long as it exists. A pipe would have no name at all, and was refused when this
# was opened: bash 3.2 has neither `coproc` nor `{fd}>`, and a `read` on an empty
# pipe blocks where every reader of these channels reads to the end of a file.
#
# So the channel is asked, once its name is gone, who holds it — and that answer is
# decisive at that point and at no earlier one. Before the unlink anybody can open
# the file, on darwin even without its name (`/.vol/<device>/<inode>`, measured).
# After it, there is no way left to open it — `/.vol` refuses an unlinked inode,
# measured — so the processes holding it can only become fewer. If this shell is
# all there is, and the file is still empty, then nothing that used the instant it
# had a name can reach it, and nothing else ever will. Otherwise both ends are
# closed, the channel is refused, and the sentence says who held it.
#
# **Refused and not reopened**, which is the decision a reader would question
# first. A process that won the window once wins it every time — it loops, and the
# window is as wide on the second try — so a retry would only hand it the next file.
# What a refusal costs is a receipt, a gate or a lens, and the three callers already
# handle a channel they could not have; what it saves is a forged one.
#
# Four ways the window was used, and one listing answers all of them:
#
#   held      another process holds the file — the reason this exists
#   written   it is not empty: something wrote into it while it had a name and let
#             go of its descriptor before anyone looked
#   unseen    this shell's two descriptors are not among the files `lsof +L1`
#             reports, which are the open files with no name left: the file still
#             has one — linked or renamed while it had one, so the unlink took
#             nothing back
#   shape     it is not a regular file: its name was replaced between the `mktemp`
#             and the open. A fifo, and that is also why the write end is opened
#             read-write — a write-only open of a fifo nobody reads never returns,
#             and a denial is a defect too
#
# What it cannot see, written where it is claimed. A process of another user,
# whose descriptors this user cannot list — root, which needs no window. A
# descriptor in flight in a socket message at the instant of the listing, held by
# no process until it is received: not measured. And on Linux, `/proc/<pid>/fd/N`,
# which reopens an unlinked file for any process of this user *after* the listing:
# there, this stops the process that polls `$TMPDIR` and not one that knows this
# pack. The zone it excludes — the two descriptors of the shell that opened the
# channel — is kept by that shell, from what it forks by `proc_exec_bare` ([101]),
# and from whatever git runs for it by `proc_git` ([104]).

# Where `lsof` is, resolved once by the pilot and never by its bare name at the
# moment of a check. A check runs inside an iteration, a gate branch or a lens:
# shells forked from a pilot that would otherwise never have looked the name up, so
# each would walk PATH afresh, after a session had had its turn at the directories
# on it — and a session that put an `lsof` in front of the real one would answer
# every check after it. A name resolved before the first session exists is one no
# session can put a program in front of. What a session can still do is rewrite
# the file the name resolved to, where it can write there, and that is [91]'s
# witness — `lsof` is on its list — and [91]'s bound: said, and charged to the
# successor, not undone for the iterations left in this run.
PROC_CHANNEL_LSOF=''

# Why the last channel was refused, as a clause its caller says where it says
# things — a receipt's on the run's output, a gate's through `gate__say`, a lens's
# in its findings. Empty after a channel was served.
PROC_CHANNEL_REFUSAL=''

# A refusal at the door, on a machine with no `lsof`, rather than channels that are
# never checked: a check that cannot run must not read as one that passed ([31]).
# Darwin ships it; a Linux without it is told to install it. Called by
# `loop_preflight`, in the pilot, before any iteration is forked — which is what
# makes the resolution the pilot's. A shell that never called it has no lister,
# and every channel it opens is refused: the lister answers nothing, so nobody
# checked.
proc_channel_preflight() {
  PROC_CHANNEL_LSOF="$(gate_path_where lsof)"
  [ "$PROC_CHANNEL_LSOF" = '-' ] || return 0
  PROC_CHANNEL_LSOF=''
  printf 'ralph: lsof is on no PATH directory — every time this pack opens a channel no other process may hold (an audit receipt, the notes of a gate, the prompt of a review lens), it asks lsof whether anything outside the shell that opened it does, and refuses the channel otherwise. Without lsof every one of them would be refused: install it and start the run again\n' >&2
  return 1
}

# Open FILE as a channel — FD to write, BACK to read from offset zero — unlink it,
# and serve it only if this shell is alone with it. FILE is the module's own
# `mktemp`, made where that module names its files, so the names stay where [62]'s
# census reads them; an empty FILE is a `mktemp` that failed, refused here so that
# every refusal reads the same.
#
# Zero only when all of that is true, which is the guarantee a test can hold it to:
# it never reports a channel it did not open, unlink and find alone. Otherwise both
# ends are closed, the name is gone, and PROC_CHANNEL_REFUSAL says why.
#
# The numbers are literal digits because bash 3.2 has no `{var}>`; they are spent
# through `eval`, here and in the module that closes them, and checked first
# because that `eval` is the one place a stray word would become code.
proc_channel_open() {
  local fd="${1:-}" back="${2:-}" file="${3:-}"
  PROC_CHANNEL_REFUSAL=''
  case "$fd:$back" in
    *[!0-9:]* | :* | *:)
      PROC_CHANNEL_REFUSAL="it was asked for on descriptors that are not numbers ($fd, $back)"
      return 1
      ;;
  esac
  if [ -z "$file" ]; then
    PROC_CHANNEL_REFUSAL='no file could be made for it'
    return 1
  fi
  if ! eval "exec $fd<>\"\$file\" $back<\"\$file\""; then
    rm -f "$file"
    PROC_CHANNEL_REFUSAL='its file could not be opened'
    return 1
  fi
  # Before a byte is written, and that is the order rather than a tidy-up: a record
  # that reached a named file was reachable, and no later unlink takes that back.
  rm -f "$file"
  if ! proc__channel_alone "$fd" "$back"; then
    eval "exec $fd>&- $back<&-"
    return 1
  fi
  return 0
}

# Whether this shell is alone with the file it holds on FD and BACK, asked of
# `lsof +L1` — every open file with no name left — and answered in
# PROC_CHANNEL_REFUSAL. Zero when the file is a regular one, still empty, and held
# by nothing but those two descriptors of this shell.
#
# The listing is taken with nothing of this shell open but the three standard
# descriptors, and read only once it is finished, and both are the check rather
# than hygiene: anything that runs *during* the listing and inherited the channel —
# the subshell of a command substitution, an `awk` reading a pipe from it — is a
# second holder of it, measured, and would refuse every channel this pack opens.
# So `lsof` is exec'd bare in the child, and the `awk` that reads its answer starts
# after it has returned.
proc__channel_alone() {
  local fd="$1" back="$2" listing='' verdict word pid held holders='' written=''
  proc_self
  if [ -n "$PROC_CHANNEL_LSOF" ]; then
    listing="$(proc_exec_bare "$PROC_CHANNEL_LSOF" -w -n -P +L1 -F pftsDi 2>/dev/null)" ||
      true
  fi
  verdict="$(printf '%s\n' "$listing" | awk -v self="$PROC_SELF" -v fd="$fd" -v back="$back" '
    function flush() {
      if (f != "") { n++; P[n] = p; F[n] = f; T[n] = t; S[n] = s; K[n] = d ":" i }
      f = ""; t = ""; s = ""; d = ""; i = ""
    }
    /^p/ { flush(); p = substr($0, 2); next }
    /^f/ { flush(); f = substr($0, 2); next }
    /^t/ { t = substr($0, 2); next }
    /^s/ { s = substr($0, 2); next }
    /^D/ { d = substr($0, 2); next }
    /^i/ { i = substr($0, 2); next }
    END {
      flush()
      if (n == 0) { print "silent"; exit }
      for (j = 1; j <= n; j++) {
        if (P[j] == self && F[j] == fd) w = j
        if (P[j] == self && F[j] == back) r = j
      }
      if (!w || !r || K[w] != K[r]) { print "unseen"; exit }
      if (T[w] != "REG") { print "shape " T[w]; exit }
      for (j = 1; j <= n; j++) if (K[j] == K[w] && j != w && j != r) print "held " P[j] " " F[j]
      if (S[w] != "0") print "written " S[w]
    }')"
  case "$verdict" in
    '') return 0 ;;
    silent)
      PROC_CHANNEL_REFUSAL="the lister that says who holds it (${PROC_CHANNEL_LSOF:-none was resolved for this run}) answered nothing, so nobody checked"
      return 1
      ;;
    unseen)
      PROC_CHANNEL_REFUSAL='its file still had a name once it was unlinked — something linked or renamed it while it had one — so the unlink took nothing back'
      return 1
      ;;
    shape*)
      PROC_CHANNEL_REFUSAL="it was not a regular file but a ${verdict#shape } — something put that in place of its name before it was opened"
      return 1
      ;;
  esac
  # Who held it first, when anybody still does: that is the sentence a human can
  # act on. What was already written is said after it, and alone when its writer
  # let go before the listing.
  while read -r word pid held; do
    case "$word" in
      held) holders="${holders:+$holders, }process $pid on its descriptor $held" ;;
      written) written="$pid" ;;
    esac
  done <<VERDICT
$verdict
VERDICT
  if [ -n "$holders" ]; then
    PROC_CHANNEL_REFUSAL="it was held by $holders once its name was gone — opened in the instant between its creation and its unlink, which is what a process polling \$TMPDIR in a loop does"
    [ -z "$written" ] ||
      PROC_CHANNEL_REFUSAL="$PROC_CHANNEL_REFUSAL, and $written byte(s) were in it already"
  else
    PROC_CHANNEL_REFUSAL="$written byte(s) were in it before this shell wrote one — something wrote into it in the instant it had a name"
  fi
  return 1
}

# ── the hooks git runs for this pack ([102]) ─────────────────────────────────
#
# Git runs programs on its own, and it looks for them in a directory a session can
# write: `$(git rev-parse --git-common-dir)/hooks/`, which every worktree of the
# repository shares and nothing in this pack read. Measured on git 2.54, verb by
# verb in the shapes this pack writes them ([51]: the verb, not the family —
# `.scratch/ralph-pack/sondes/ticket-102/h1`):
#
#   reference-transaction   every `update-ref` — plumbing, and it runs anyway — so
#                           the durable commit, the fold and `failed/<id>`; and
#                           `reset --mixed`, `worktree add`, `push`
#   post-index-change       every index written, `GIT_INDEX_FILE` or not: `add`,
#                           `read-tree`, `write-tree`, `update-index`, `reset`,
#                           `rm --cached`, `worktree add` — every tree snapshot of
#                           the gate and every guard of the tracker
#   post-checkout           `worktree add`, which the *pilot* runs for every
#                           iteration
#   pre-push                the forge backend's `push`
#
# and nothing for the read-only verbs (`rev-parse`, `config`, `ls-tree`,
# `ls-files`, `diff-tree`, `diff`, `cat-file`, `show-ref`, `for-each-ref`,
# `symbolic-ref`, `check-ignore`, `commit-tree`, `checkout-index`,
# `worktree list|prune|remove`, `init`). A hook git runs is a descendant of the
# shell that ran git: until [104] it held that shell's descriptors — the write end
# of an iteration's receipt ([96]), a gate's notes ([94]) — and it still runs at the
# instant the pack chose. Measured in the pack before this ticket: a hook the
# session of 01 planted wrote six lines into 01's receipt and three into 02's, whose
# session had planted nothing, and `post-checkout` ran in the pilot.
#
# So every git this run starts is told it has no hook directory, through the one
# channel every git reads and no config file can override: `GIT_CONFIG_PARAMETERS`,
# which is what `git -c` itself hands down to the git it runs. Command-line scope
# is read last, so a `core.hooksPath` a session writes in `.git/config` or behind
# an `include.path` loses to it (measured, `h3`); `/dev/null` is not a directory,
# so no name resolves under it. In the environment and not as a `-c` on each call,
# because the guarantee is then a property of the shell and not of a hundred call
# sites — a git call added tomorrow is covered without knowing this exists, and
# so is a git that git runs (`worktree add` runs a checkout of its own).
#
# The old `'key=value'` form, which every git reads; the `'key'='value'` form
# needs 2.31. Appended to whatever the operator exported, and that value is kept
# here, in two variables of this shell that a session cannot reach — it inherits
# an environment, never a shell ([81]). `PROC__GIT_PARAMS_HELD` says which of the
# three it was: `set`, `unset`, or empty when nothing was turned off at all.
#
# What this does **not** turn off, and it is the half that is not a directory:
# since git 2.5x a hook can also be *configured* — `hook.<name>.command` and
# `hook.<name>.event` — and `core.hooksPath` does nothing to it (measured: every
# event above fired a configured hook under the token). There is no switch that
# turns them all off, only one per name, and the name is the session's to choose.
# So a configured hook is a key of [46]'s list (`gate_config_keys`), watched,
# removed and charged like `core.fsmonitor` — which holds at MAX_PARALLEL=1 and not
# for a sibling iteration already past its own put-back, nor for a key of the
# operator's `~/.gitconfig`, which no unset of this repository reaches. What those
# still run holds nothing of the shell that ran git since [104] (`proc_git`, above):
# the answer to them is about descriptors, not about whether they run.
#
# **Why the token stays now that nothing git runs holds anything** — [104] asked it,
# and it is a decision and not inertia. A hook without a descriptor still buys
# something: the instant the pack chose — `post-checkout` in the pilot,
# `reference-transaction` between a commit and the ref that will name it — and a
# process that is a child of the pilot or of an iteration rather than of the
# session, so outside the group `session_spawn` sweeps when the session returns. It
# also buys the power to fail a transaction, which a `.lock` file buys as well. None
# of it forges a line, and a session reaches most of it by other routes; but the
# hook directory is a door no key names, which every worktree reaches without trying
# and which outlives the run, and shutting it costs this line. What the operator
# pays is that their own hooks do not run for the pack's git: on a forge backend
# git-lfs's `pre-push` is one of them, so the receipt branch is pushed without its
# LFS objects, and nothing says so at the push. Kept, and the cost written here
# rather than found.
PROC_GIT_HOOKS_OFF="'core.hooksPath=/dev/null'"
PROC__GIT_PARAMS_HELD=''
PROC__GIT_PARAMS=''

# Called once by each entry point, before the first git it runs. Builtins only, so
# it can stand anywhere in a preamble that refuses to resolve a name ([52]).
proc_git_hooks_off() {
  if [ -n "${GIT_CONFIG_PARAMETERS+set}" ]; then
    PROC__GIT_PARAMS_HELD=set
    PROC__GIT_PARAMS="$GIT_CONFIG_PARAMETERS"
    GIT_CONFIG_PARAMETERS="$GIT_CONFIG_PARAMETERS $PROC_GIT_HOOKS_OFF"
  else
    PROC__GIT_PARAMS_HELD=unset
    PROC__GIT_PARAMS=''
    GIT_CONFIG_PARAMETERS="$PROC_GIT_HOOKS_OFF"
  fi
  export GIT_CONFIG_PARAMETERS
  return 0
}

# The operator's `GIT_CONFIG_PARAMETERS`, exactly as `proc_git_hooks_off` found it
# — set to the same value, or not set at all. For a shell about to become, or to
# hand its environment to, a program this pack did not write: the session's git
# then runs the project's hooks as it always did, and a project command that tests
# a hook of its own still sees it. Three callers: `proc_exec_bare` above, the
# drain's interactive session, and the scheduler's submission — `at` keeps the
# environment it was called with for the job, and a successor that inherited the
# token would take it for the operator's and hand it to its own sessions.
#
# Three states and not two: in a shell that never turned the hooks off — a unit
# test driving a lib, a fourth entry point — there is nothing to give back, and
# "not set" would then unset a value the operator exported.
proc_git_hooks_given_back() {
  case "$PROC__GIT_PARAMS_HELD" in
    set)
      GIT_CONFIG_PARAMETERS="$PROC__GIT_PARAMS"
      export GIT_CONFIG_PARAMETERS
      ;;
    unset) unset GIT_CONFIG_PARAMETERS ;;
  esac
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
