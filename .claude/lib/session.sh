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
# It lives in a lib rather than in the loop because two callers need it — the
# loop's delivery iteration and the failure policy's re-slice — and a lib that
# had to call back up into loop.sh for it would invert the layering. Whoever
# spawns, the shape is the same: a session that inherited a conversation would
# defeat the whole point of the pack.
session_spawn() {
  local promptfile="$1" outfile="$2" pid rc=0
  RALPH_SOFT_LIMIT_HIT=0

  # Created before the spawn: the monitor follows the stream through an open
  # descriptor, and a descriptor cannot be opened on a file that is not there.
  : >"$outfile"

  DISABLE_AUTO_COMPACT=1 claude -p \
    --model "$MODEL" \
    --output-format stream-json \
    --verbose \
    --dangerously-skip-permissions \
    <"$promptfile" >"$outfile" &
  pid=$!

  monitor_watch "$outfile" "$pid" "$SOFT_LIMIT_TOKENS" || RALPH_SOFT_LIMIT_HIT=1
  wait "$pid" || rc=$?
  return "$rc"
}
