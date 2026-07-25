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

# Pull an integer field, anchored on `{` or `,` so that a key never matches a
# longer one — "input_tokens" must not match "cache_read_input_tokens".
monitor__int() {
  printf '%s' "$1" | sed -n "s/.*[,{]\"$2\":\([0-9][0-9]*\).*/\1/p"
}

# Context size reported by one stream event, or nothing if it reports none.
monitor_context_tokens() {
  local line="$1" total=0 part found=0 key
  case "$line" in
    *'"usage"'*) ;;
    *) return 0 ;;
  esac
  for key in input_tokens cache_creation_input_tokens cache_read_input_tokens output_tokens; do
    part="$(monitor__int "$line" "$key")"
    if [ -n "$part" ]; then
      total=$((total + part))
      found=1
    fi
  done
  [ "$found" = 1 ] || return 0
  printf '%s\n' "$total"
}

# Watch a session's stream while it runs. Returns 0 if it finished on its own,
# 1 if it was terminated for crossing the limit. The peak context seen is left
# in <stream>.tokens for the journal.
monitor_watch() {
  local file="$1" pid="$2" limit="${3:-${SOFT_LIMIT_TOKENS:-150000}}"
  local consumed=0 alive rc=0

  : >"$file.tokens"
  while :; do
    if kill -0 "$pid" 2>/dev/null; then alive=1; else alive=0; fi

    consumed="$(monitor__scan "$file" "$consumed" "$limit" "$pid")" || rc=$?
    [ "$rc" -eq 0 ] || return 1

    # Scanned once after noticing the process was gone: nothing is missed.
    [ "$alive" = 1 ] || return 0
    sleep 0.1
  done
}

# Read the lines that appeared since last time. Echoes the new line count and
# returns non-zero once the limit is crossed, having killed the session.
monitor__scan() {
  local file="$1" consumed="$2" limit="$3" pid="$4"
  local line tokens peak over=0

  peak="$(cat "$file.tokens" 2>/dev/null || echo 0)"
  [ -n "$peak" ] || peak=0

  while IFS= read -r line; do
    consumed=$((consumed + 1))
    tokens="$(monitor_context_tokens "$line")"
    [ -n "$tokens" ] || continue
    [ "$tokens" -gt "$peak" ] && peak="$tokens"
    if [ "$tokens" -ge "$limit" ]; then
      over=1
      break
    fi
  done < <(tail -n "+$((consumed + 1))" "$file" 2>/dev/null)

  printf '%s\n' "$peak" >"$file.tokens"
  printf '%s' "$consumed"

  if [ "$over" = 1 ]; then
    # Graceful: the session gets a chance to stop cleanly, and the loop treats
    # the iteration as a non-success rather than a resolution.
    kill -TERM "$pid" 2>/dev/null
    return 1
  fi
  return 0
}

monitor_peak_tokens() {
  cat "$1.tokens" 2>/dev/null || echo 0
}
