#!/usr/bin/env bash
# loop.sh — the ralph loop.
#
# Skeleton only: it resolves the pack, loads the config and every lib, then
# exits clean. The iteration control-flow (frontier scan -> fresh session ->
# QA gate -> marking -> run journal) lands on top of this in a later ticket.
#
# Kept bash 3.2 compatible: the pack must run on a stock macOS shell.
set -euo pipefail

RALPH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RALPH_CONFIG="${RALPH_CONFIG:-$RALPH_DIR/ralph.config.sh}"
export RALPH_DIR

if [ ! -f "$RALPH_CONFIG" ]; then
  printf 'ralph: no config at %s — copy ralph.config.sh.example and edit it\n' \
    "$RALPH_CONFIG" >&2
  exit 2
fi

# shellcheck source=/dev/null
. "$RALPH_CONFIG"

# Libs are sourced in lexical order. An empty lib/ is not an error: the pack
# is usable before every module exists.
for _ralph_lib in "$RALPH_DIR"/lib/*.sh; do
  [ -e "$_ralph_lib" ] || continue
  # shellcheck source=/dev/null
  . "$_ralph_lib"
done
unset _ralph_lib

printf 'ralph: skeleton ok (feature=%s backend=%s)\n' \
  "${FEATURE:-}" "${TRACKER_BACKEND:-}"
