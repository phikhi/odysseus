# shellcheck shell=bash
# The smart-zone net.
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

# Sets MONITOR_INT to the integer value of a flat JSON key, or to nothing if the
# key is absent. Anchored on `{` or `,` so a key never matches a longer one —
# "input_tokens" must not match "cache_read_input_tokens".
#
# Parameter expansion, not sed: this runs once per key per stream line.
monitor__int() {
  local line="$1" rest
  rest="${line##*[,{]\"$2\":}"
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

# Watch a session's stream while it runs. Returns 0 if it finished on its own,
# 1 if it was terminated for crossing the limit. The peak context seen is left
# in <stream>.tokens for the journal.
#
# The stream is held open on a descriptor and read forward, so each tick picks
# up exactly where the last one stopped and costs only what the session has
# written since.
monitor_watch() {
  local file="$1" pid="$2" limit="${3:-${SOFT_LIMIT_TOKENS:-150000}}"
  local partial='' peak=0 line alive rc=0

  : >"$file.tokens"
  if [ ! -r "$file" ]; then
    printf 'ralph: monitor: cannot read the session stream at %s\n' "$file" >&2
    return 1
  fi
  exec 3<"$file"

  while :; do
    if kill -0 "$pid" 2>/dev/null; then alive=1; else alive=0; fi

    # A tick can land in the middle of a write, so a trailing partial line is
    # carried over to the next one instead of being parsed as if it were whole.
    while IFS= read -r -u 3 line || { partial="$partial$line"; false; }; do
      line="$partial$line"
      partial=''
      monitor__tokens_of "$line"
      [ -n "$MONITOR_TOKENS" ] || continue
      if [ "$MONITOR_TOKENS" -gt "$peak" ]; then
        peak="$MONITOR_TOKENS"
        printf '%s\n' "$peak" >"$file.tokens"
      fi
      if [ "$MONITOR_TOKENS" -ge "$limit" ]; then
        # Graceful: the session gets a chance to stop cleanly, and the loop
        # treats the iteration as a non-success rather than a resolution.
        kill -TERM "$pid" 2>/dev/null
        rc=1
        break
      fi
    done
    [ "$rc" -eq 0 ] || break

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
