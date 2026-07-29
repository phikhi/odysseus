#!/usr/bin/env bash
# Run the pack's test suite.
#
# Default runner is microbats (pure bash, no install). `--bats` hands the same
# files to bats-core if you have it. Both read the same .bats files.
#
#   test/run.sh                     every test/*.bats
#   test/run.sh test/smoke.bats     one file
#   test/run.sh -f "config"         only tests whose name matches
#   test/run.sh --bats              via bats-core
#
# The suite is hermetic: no network, no quota, a fake `claude` on PATH. One file
# asks for more than that. test/contract-claude.bats checks the pack's
# assumptions about Claude Code's interface against the real binary, and skips
# that half — loudly — unless it is asked for:
#
#   RALPH_REAL_CLAUDE=1 test/run.sh test/contract-claude.bats
#
# That spawns real sessions: network, quota, a few cents of it. RALPH_REAL_MODEL
# picks the model (haiku by default).
set -uo pipefail

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
runner="micro"
filter=""
files=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --bats) runner="bats" ;;
    -f | --filter)
      shift
      filter="${1:-}"
      ;;
    -h | --help)
      sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      printf 'run.sh: unknown option %s\n' "$1" >&2
      exit 2
      ;;
    *) files+=("$1") ;;
  esac
  shift
done

if [ "${#files[@]}" -eq 0 ]; then
  for f in "$TEST_DIR"/*.bats; do
    [ -e "$f" ] || continue
    files+=("$f")
  done
fi

if [ "${#files[@]}" -eq 0 ]; then
  echo "run.sh: no .bats files found in $TEST_DIR" >&2
  exit 1
fi

if [ "$runner" = "bats" ]; then
  if ! command -v bats >/dev/null 2>&1; then
    echo "run.sh: --bats asked for bats-core, which is not installed" >&2
    exit 1
  fi
  if [ -n "$filter" ]; then
    exec bats --filter "$filter" "${files[@]}"
  fi
  exec bats "${files[@]}"
fi

# shellcheck source=helpers/microbats.bash
. "$TEST_DIR/helpers/microbats.bash"
MICROBATS_FILTER="$filter"
microbats_main "${files[@]}"
