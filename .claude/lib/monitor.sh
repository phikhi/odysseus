# shellcheck shell=bash
# The smart-zone net, and the two deadlines beside it.
#
# Slicing tickets small enough is a design intention; this is the runtime
# guarantee behind it. A session whose context crosses the soft limit is sent
# SIGTERM before it can drift toward the ~200K dumb-zone frontier, where
# reasoning quality collapses and the work silently gets worse.
#
# The signal comes from the session's own stream: every `assistant` event
# carries message.usage, and the context at that call is
#
#   input_tokens + cache_creation_input_tokens + cache_read_input_tokens
#   + output_tokens
#
# Cache reads count — cached or not, those tokens are in the window. On a real
# session the system prompt alone puts the floor around 20K.
#
# No jq: the pack runs with nothing installed, and these are flat integers.
#
# Watching costs nothing per tick, and that is deliberate. Two earlier shapes
# were measured against a real-sized stream and both scaled with the session
# rather than with what it had just written: re-reading the file from the top on
# every tick (a line count plus `tail -n +N`) cost 0.36 s per tick on a 20 MB
# stream, and extracting each figure with `sed` forked four processes per event
# — 21 s of CPU for a single pass over that same stream. A session emits tens of
# megabytes and is watched for tens of minutes, so both costs are paid thousands
# of times, against the very session and test suite they are competing with.
#
# ── the two deadlines ────────────────────────────────────────────────────────
#
# The net above bounds a session's *context*. It does not bound its time, and
# what it watches is the stream: a `claude` that hangs without emitting a token
# is bounded by nothing at all, which for an AFK run is the most expensive
# failure there is — a night that grinds nothing and never gives the terminal
# back ([23]).
#
# So two, and one of them is not enough:
#
#   SESSION_STALL_TIMEOUT   the session wrote nothing at all for this long. Short,
#                           and it is the one that catches a hang.
#   SESSION_TIMEOUT         the session has been running this long, whatever it
#                           wrote. Generous, and it is the one that catches a
#                           session looping over an edit it cannot get right: a
#                           stream that progresses is not proof of progress.
#
# There is a second reason for the wall clock, and it is a trust boundary rather
# than a design taste. The stall deadline reads the session's own stream, and the
# stream is a file in `.scratch/` that the session can append to — nothing in the
# pack guards it ([21] stops at `issues/`). A session that wrote one byte a second
# would defeat the stall and nothing else. The wall clock is measured from the
# spawn, so there is nothing a session can write that moves it.
#
# Both are measured with SECONDS, the shell's own clock. No fork per tick, and no
# drift either: counting ticks would have to assume every tick costs 0.1 s, which
# is exactly what stops being true on the 20 MB stream the loop above was
# rewritten for — a deadline that stretches with the size of the session is not a
# deadline. The price is granularity, and it is worth stating because a test has
# to live with it: SECONDS is an integer, so a deadline fires anywhere between
# limit-1 and limit+1 seconds. Noise against the shipped 1800 s; a constant of
# coverage in a test that measures seconds.

# Sets MONITOR_INT to the integer value of a flat JSON key, or to nothing if the
# key is absent. The opening quote is what makes a key never match a longer one:
# "input_tokens" must not be found inside "cache_read_input_tokens", and there
# the preceding character is an underscore rather than a quote.
#
# The match is the *last* occurrence, so a key quoted inside a tool result
# cannot shadow the real field — and being inside a string, its quotes are
# escaped anyway, which is why anchoring on `{` or `,` as well was unreachable
# defense: no test could distinguish it, so it is gone.
#
# Parameter expansion, not sed: this runs once per key per stream line.
monitor__int() {
  local line="$1" rest
  rest="${line##*\"$2\":}"
  if [ "$rest" = "$line" ]; then
    MONITOR_INT=""
    return 0
  fi
  MONITOR_INT="${rest%%[!0-9]*}"
}

# Sets MONITOR_TOKENS to the context size one stream event reports, or to
# nothing when it reports none. A setter rather than an echo for the same
# reason: `$(...)` on every line is a forked subshell on every line.
monitor__tokens_of() {
  local line="$1" total=0 found=0 key
  MONITOR_TOKENS=""
  case "$line" in
    *'"usage"'*) ;;
    *) return 0 ;;
  esac
  for key in input_tokens cache_creation_input_tokens cache_read_input_tokens output_tokens; do
    monitor__int "$line" "$key"
    if [ -n "$MONITOR_INT" ]; then
      total=$((total + MONITOR_INT))
      found=1
    fi
  done
  [ "$found" = 1 ] || return 0
  MONITOR_TOKENS="$total"
}

# The same answer on stdout, for callers that want a value rather than a
# variable.
monitor_context_tokens() {
  monitor__tokens_of "$1"
  [ -n "$MONITOR_TOKENS" ] && printf '%s\n' "$MONITOR_TOKENS"
  return 0
}

# A deadline read the way GATE_TIMEOUT reads one: zero, empty or non-numeric is
# no deadline at all. A project that could not say "off" would have to write a
# huge number instead, and then a typo would be a deadline nobody chose.
monitor__deadline() {
  case "${1:-0}" in
    '' | *[!0-9]*) printf '0\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# Terminating a session, which is one act in two halves.
#
# TERM to the whole process tree and not to `claude` alone: a session runs tool
# processes of its own, and a dev server or a build a Bash tool started outlives
# the session killed above it. Same walk as the gate's deadline, one primitive
# since [23] gave it a second caller.
#
# Then the half a TERM cannot promise. A TERM is a request — `claude` honours it
# and shuts down — and a session that does not honour it hangs the run, because
# the collection in `session_spawn` waits for the exit status of a child that
# never exits ([28]). Without the KILL that follows, a deadline bounds the moment
# the loop *asks* a session to stop and not the moment it gets it back, which is
# half of the guarantee this whole file claims to give.
#
# The reaper is a process of its own, and that is load-bearing twice over. `wait`
# takes no timeout on bash 3.2, and this function has to return *now*: what
# follows it in `session_spawn` is the one collection a graceful stop has to
# survive ([25], [28]), and doing the grace inline here would move that window
# somewhere no test of [28] is looking. Its pid is left in MONITOR_REAPER, and
# whoever spawned the session collects it.
monitor__terminate() {
  local pid="$1" grace
  grace="$(monitor__deadline "${SESSION_KILL_GRACE:-30}")"
  proc_kill_tree "$pid"
  [ "$grace" -gt 0 ] || return 0
  monitor__reaper "$pid" "$grace" &
  MONITOR_REAPER=$!
  return 0
}

# Sleeps in one-second steps, so killing it leaves at most a one-second orphan
# behind, and gives up the moment the session is gone — which is what makes the
# ordinary case free: `session_spawn` kills this the instant the session is
# collected, and a TERM that was honoured means that is immediately.
monitor__reaper() {
  local pid="$1" grace="$2" waited=0
  while [ "$waited" -lt "$grace" ]; do
    sleep 1
    kill -0 "$pid" 2>/dev/null || return 0
    waited=$((waited + 1))
  done
  proc_kill_tree "$pid" KILL
  return 0
}

# Watch a session's stream while it runs. Returns 0 if it finished on its own,
# non-zero if the monitor terminated it. The peak context seen is left in
# <stream>.tokens for the journal.
#
# Two outputs beside the return code, both read by `session_spawn` in the shell
# that called this: MONITOR_STOPPED says *why* the session was terminated, and
# MONITOR_REAPER holds the process that will KILL it if the TERM goes unanswered.
# Why the reason cannot be the return code: a child killed by a signal answers
# 143 whatever it was killed for, and a `claude` that traps TERM and shuts down
# cleanly answers 0 — so the exit status of a terminated session says nothing at
# all about the deadline that terminated it ([28]).
#
# The stream is held open on a descriptor and read forward, so each tick picks
# up exactly where the last one stopped and costs only what the session has
# written since.
monitor_watch() {
  local file="$1" pid="$2" limit="${3:-${SOFT_LIMIT_TOKENS:-150000}}"
  local partial='' peak=0 line alive rc=0
  local stall wall started idle

  MONITOR_STOPPED=''
  MONITOR_REAPER=''
  stall="$(monitor__deadline "${SESSION_STALL_TIMEOUT:-0}")"
  wall="$(monitor__deadline "${SESSION_TIMEOUT:-0}")"

  : >"$file.tokens"
  if [ ! -r "$file" ]; then
    printf 'ralph: monitor: cannot read the session stream at %s\n' "$file" >&2
    return 1
  fi
  exec 3<"$file"

  started=$SECONDS
  idle=$SECONDS

  while :; do
    if kill -0 "$pid" 2>/dev/null; then alive=1; else alive=0; fi

    # A tick can land in the middle of a write, so a trailing partial line is
    # carried over to the next one instead of being parsed as if it were whole.
    # Half a line is still the session writing, and the stall deadline has to
    # count it as one: a stream that arrives in slow halves would otherwise look
    # exactly like silence, and the session would be killed for writing.
    while IFS= read -r -u 3 line ||
      { partial="$partial$line"; [ -z "$line" ] || idle=$SECONDS; false; }; do
      line="$partial$line"
      partial=''
      idle=$SECONDS
      monitor__tokens_of "$line"
      [ -n "$MONITOR_TOKENS" ] || continue
      if [ "$MONITOR_TOKENS" -gt "$peak" ]; then
        peak="$MONITOR_TOKENS"
        printf '%s\n' "$peak" >"$file.tokens"
      fi
      if [ "$MONITOR_TOKENS" -ge "$limit" ]; then
        # Graceful: the session gets a chance to stop cleanly, and the loop
        # treats the iteration as a non-success rather than a resolution.
        MONITOR_STOPPED=soft-limit
        break
      fi
    done

    # Asked after the read and not before it: a tick that has just picked up a
    # line has, by definition, seen the session write. And asked only of a session
    # that was still running when this tick began — a deadline bounds something
    # that is still going, so a session which finished during its last silent
    # second is finished and not hung. The soft limit above is deliberately not
    # under the same condition: crossing it is a property of what the session
    # wrote, not of when it died. What is left is one tick of window, the process
    # dying between the check at the top of the loop and this line; it is the same
    # window `proc_collect` documents and the same trade — it would cost a green
    # session a retry, never a red one a pass, and no test can pin it down.
    if [ "$alive" = 1 ] && [ -z "$MONITOR_STOPPED" ] && [ "$stall" -gt 0 ] &&
      [ "$((SECONDS - idle))" -ge "$stall" ]; then
      MONITOR_STOPPED=stall
    fi
    if [ "$alive" = 1 ] && [ -z "$MONITOR_STOPPED" ] && [ "$wall" -gt 0 ] &&
      [ "$((SECONDS - started))" -ge "$wall" ]; then
      MONITOR_STOPPED=wall
    fi
    if [ -n "$MONITOR_STOPPED" ]; then
      monitor__terminate "$pid"
      rc=1
      break
    fi

    # Read once more after noticing the process was gone: nothing is missed.
    [ "$alive" = 1 ] || break
    sleep 0.1
  done

  exec 3<&-
  return "$rc"
}

monitor_peak_tokens() {
  cat "$1.tokens" 2>/dev/null || echo 0
}
