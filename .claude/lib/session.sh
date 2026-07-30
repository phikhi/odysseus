# shellcheck shell=bash
# Spawning one session, and the only place in the pack that runs `claude`.
#
# A fresh session: never --continue, never --resume. Those are exactly the flags
# that would replay history and drag the context toward the dumb zone.
#
# DISABLE_AUTO_COMPACT is set here as well as in settings.json: compaction is the
# mechanism that produces a dumb-zone session, and the guarantee must not depend
# on a settings file the target project could overwrite.
#
# The session runs in the background so the smart-zone net can watch its stream
# and stop it while it is still running. Sets RALPH_SOFT_LIMIT_HIT when it does.
#
# One prompt, one stream, from a file rather than a pipe: a pipeline would run
# this in a subshell and RALPH_SOFT_LIMIT_HIT would die with it.
#
# It lives in a lib rather than in the loop because three callers need it — the
# loop's delivery iteration, the failure policy's re-slice and a review lens
# ([06]) — and a lib that had to call back up into loop.sh for it would invert
# the layering. Whoever spawns, the shape is the same: a session that inherited a
# conversation would defeat the whole point of the pack.
#
# Anything after the two file arguments is passed to `claude` as it stands. That
# is the one extension point, and it exists so that a caller which needs a
# different posture — a review lens, which gets a read-only tool set — does not
# retype the invocation. A second copy of these flags would be a second thing to
# keep in step with reality, and only one of them would be under contract ([20]).
session_spawn() {
  local promptfile="$1" outfile="$2" pid rc=0
  shift 2
  RALPH_SOFT_LIMIT_HIT=0

  # Created before the spawn: the monitor follows the stream through an open
  # descriptor, and a descriptor cannot be opened on a file that is not there.
  : >"$outfile"

  DISABLE_AUTO_COMPACT=1 claude -p \
    --model "$MODEL" \
    --output-format stream-json \
    --verbose \
    --dangerously-skip-permissions \
    "$@" \
    <"$promptfile" >"$outfile" &
  pid=$!

  monitor_watch "$outfile" "$pid" "$SOFT_LIMIT_TOKENS" || RALPH_SOFT_LIMIT_HIT=1
  wait "$pid" || rc=$?
  return "$rc"
}

# Pull one field out of the final `result` event. Deliberately not jq: the pack
# promises to run with nothing installed, and these fields are flat scalars.
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
  local file="$1" key="$2" line
  line="$(grep '"type":"result"' "$file" 2>/dev/null | tail -1)" || line=""
  [ -n "$line" ] || return 0
  printf '%s' "$line" |
    sed -n "s/.*\"$key\":\"\{0,1\}\([^,\"}]*\)\"\{0,1\}.*/\1/p"
}
