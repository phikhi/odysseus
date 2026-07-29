# shellcheck shell=bash
# The injected environment behind the process seam.
#
# A test drives the real `loop.sh` / `human-loop.sh` as processes inside a
# throwaway project, and then asserts on the tracker. Everything the pack
# reaches for from the outside world is injected here:
#
#   tracker    a `local` tracker in a tmpdir, seeded from test/fixtures/tickets
#   LLM        a fake `claude` on PATH, scriptable per test, recording argv+stdin
#   budget     a fake `curl` serving a scripted /api/oauth/usage payload
#   scheduler  a fake `at` recording what a successor would have been
#   gate       `stub-cmd` behind TEST_CMD / TYPECHECK_CMD, exit code per test
#   node       `node`/`npm`/`npx` shadowed by hard failures (bash-only fallback)
#
# Public API
#   harness_setup [feature]        create the project, pack, shims, git repo
#   harness_teardown               remove it (RALPH_KEEP_TMP=1 keeps it)
#   use_tickets [NN-slug ...]      seed the tracker (no args = every fixture)
#   set_config KEY VALUE           override a config key in ralph.config.sh
#   run_loop [args ...]            run the real loop.sh through `run`
#   pack_run CODE                  run pack code as a process, config+libs loaded
#   pack_run_bg CODE               same, detached; pid in $PACK_BG_PID
#   wait_for_file PATH [tries]     wait on a background process's marker
#   ticket_file NN-slug            path of a ticket in the tracker
#   ticket_status NN-slug          its Status: value
#   ticket_field NN-slug NAME      any field, read without using the pack
#   ticket_has_field NN-slug NAME  whether the field is present at all
#   run_lock_dir                   where the run lock lives for this feature
#   tree_lock_dir                  where the working-tree lock lives
#   script_claude                  read a script on stdin, use it as fake claude
#   claude_call_count              how many times claude was spawned
#   claude_call_argv N             argv of the Nth spawn
#   claude_call_stdin N            stdin (the prompt) of the Nth spawn
#   claude_call_env N              environment the Nth spawn was given
#   claude_rate_limit JSON         the in-band rate_limit_info the stream carries
#   stub_exit NAME CODE            exit code for `stub-cmd NAME`
#   stub_call_count NAME           how many times it ran
#   usage_respond JSON             body served for /api/oauth/usage
#   usage_exit CODE                curl exit code
#   at_exit CODE                   `at` exit code
#   at_calls                       recorded `at` invocations
#
# Kept bash 3.2 compatible, like the pack itself.

RALPH_HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RALPH_PACK_ROOT="$(cd "$RALPH_HARNESS_DIR/../.." && pwd)"
RALPH_FIXTURES="$RALPH_PACK_ROOT/test/fixtures"

RALPH_TEMPLATE_FEATURE=demo

harness_setup() {
  harness__clear_env
  RALPH_TEST_FEATURE="${1:-$RALPH_TEMPLATE_FEATURE}"
  # Normalised: macOS TMPDIR ends in a slash, and the pack reports paths that
  # went through `cd && pwd`, so raw concatenation would not compare equal.
  RALPH_TEST_DIR="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/ralph-test.XXXXXX")" && pwd -P)"
  SHIM_BIN="$RALPH_TEST_DIR/bin"
  SHIM_STATE="$RALPH_TEST_DIR/shim-state"
  mkdir -p "$SHIM_BIN" "$SHIM_STATE" "$RALPH_TEST_DIR/home"

  # The project is stamped out of a template built once per pack revision:
  # every test used to pay for a full `git init` plus commits, which is most of
  # a test's runtime when the test itself only reads a markdown file.
  # Resolved before the per-test paths exist, because building it borrows them.
  local template
  template="$(harness__template)"

  PROJECT_DIR="$RALPH_TEST_DIR/project"
  PACK_DIR="$PROJECT_DIR/.claude"
  FEATURE_DIR="$PROJECT_DIR/.scratch/$RALPH_TEST_FEATURE"
  TRACKER_DIR="$FEATURE_DIR/issues"
  RALPH_CONFIG_FILE="$PACK_DIR/ralph.config.sh"

  cp -R "$template/project" "$PROJECT_DIR"
  harness__install_shims

  if [ "$RALPH_TEST_FEATURE" != "$RALPH_TEMPLATE_FEATURE" ]; then
    mkdir -p "$TRACKER_DIR"
    cp "$RALPH_FIXTURES/spec.md" "$FEATURE_DIR/spec.md"
    set_config FEATURE "$RALPH_TEST_FEATURE"
  fi

  cd "$PROJECT_DIR" || return 1
}

# Wipe anything in the developer's environment that the pack would read.
#
# This is not paranoia: every config key is written `KEY="${KEY:-default}"`, so
# an exported MODEL or TEST_CMD silently overrides the test's own config. And
# the pack's own settings.json exports DISABLE_AUTO_COMPACT into every session
# of this repository — which made the auto-compact test pass while measuring
# the environment rather than the loop.
harness__clear_env() {
  local key
  for key in $(sed -n 's/^\([A-Z_][A-Z0-9_]*\)=.*/\1/p' \
    "$RALPH_PACK_ROOT/.claude/ralph.config.sh.example"); do
    unset "$key"
  done
  unset DISABLE_AUTO_COMPACT DISABLE_COMPACT RALPH_CONFIG RALPH_DIR \
    RALPH_PROJECT_ROOT RALPH_RUN_LOCK RALPH_TREE_LOCK RALPH_SOFT_LIMIT_HIT
}

# ── project template ─────────────────────────────────────────────────────────

# Keyed by the content of the pack and the fixtures, so editing either one
# builds a fresh template instead of testing a stale copy.
harness__template() {
  local key root tries
  key="$(harness__pack_fingerprint)"
  root="${TMPDIR:-/tmp}/ralph-harness.$key"

  [ -f "$root/.ready" ] && {
    printf '%s\n' "$root"
    return 0
  }

  # mkdir is the test-and-set: exactly one concurrent runner builds it.
  if mkdir "$root" 2>/dev/null; then
    # Each pack revision leaves a template behind; drop the stale ones rather
    # than accumulating them on a machine that never reboots.
    find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'ralph-harness.*' -mtime +7 \
      -exec rm -rf {} + 2>/dev/null || true
    harness__build_project "$root/project"
    : >"$root/.ready"
    printf '%s\n' "$root"
    return 0
  fi

  tries=200
  while [ ! -f "$root/.ready" ] && [ "$tries" -gt 0 ]; do
    sleep 0.05
    tries=$((tries - 1))
  done

  # The builder died mid-way. Fall back to a private copy rather than hand out
  # a half-built project.
  if [ ! -f "$root/.ready" ]; then
    root="$RALPH_TEST_DIR/template"
    mkdir -p "$root"
    harness__build_project "$root/project"
  fi
  printf '%s\n' "$root"
}

# Names as well as contents: hashing only the bytes made the key blind to a
# rename, so moving a lib reused the cached template and quietly tested the
# previous layout.
harness__pack_fingerprint() {
  (
    cd "$RALPH_PACK_ROOT" || return 1
    local files
    files="$(find .claude test/fixtures -type f ! -name 'settings.local.json' | LC_ALL=C sort)"
    printf '%s\n' "$files"
    printf '%s' "$files" | tr '\n' '\0' | xargs -0 cat
  ) | cksum | awk '{print $1}'
}

harness__build_project() {
  local dest="$1"
  PROJECT_DIR="$dest"
  PACK_DIR="$dest/.claude"
  FEATURE_DIR="$dest/.scratch/$RALPH_TEMPLATE_FEATURE"
  TRACKER_DIR="$FEATURE_DIR/issues"
  RALPH_CONFIG_FILE="$PACK_DIR/ralph.config.sh"

  mkdir -p "$PACK_DIR/lib" "$TRACKER_DIR" "$dest/.git-template"

  harness__install_pack
  cp "$RALPH_FIXTURES/CONTEXT.md" "$dest/CONTEXT.md"
  cp "$RALPH_FIXTURES/spec.md" "$FEATURE_DIR/spec.md"

  # Committed last: a run starts from a clean tree, which is what the pre-spawn
  # HEAD snapshot and the scope-guard diff both assume.
  harness__init_git
  rmdir "$dest/.git-template" 2>/dev/null || true
}

harness_teardown() {
  cd "$RALPH_PACK_ROOT" || true
  if [ "${RALPH_KEEP_TMP:-0}" = 1 ]; then
    printf 'harness: kept %s\n' "$RALPH_TEST_DIR" >&2
    return 0
  fi
  [ -n "${RALPH_TEST_DIR:-}" ] && rm -rf "$RALPH_TEST_DIR"
  return 0
}

# ── pack ─────────────────────────────────────────────────────────────────────

harness__install_pack() {
  local f
  cp "$RALPH_PACK_ROOT/.claude/loop.sh" "$PACK_DIR/loop.sh"
  cp "$RALPH_PACK_ROOT/.claude/ralph.config.sh.example" "$PACK_DIR/"
  [ -f "$RALPH_PACK_ROOT/.claude/settings.json" ] &&
    cp "$RALPH_PACK_ROOT/.claude/settings.json" "$PACK_DIR/"
  [ -f "$RALPH_PACK_ROOT/.claude/human-loop.sh" ] &&
    cp "$RALPH_PACK_ROOT/.claude/human-loop.sh" "$PACK_DIR/"
  for f in "$RALPH_PACK_ROOT"/.claude/lib/*.sh; do
    [ -e "$f" ] || continue
    cp "$f" "$PACK_DIR/lib/"
  done
  chmod +x "$PACK_DIR"/*.sh

  # The config a project would actually run, plus the injections every test
  # needs. Starting from the shipped example also proves the example is sound.
  cp "$PACK_DIR/ralph.config.sh.example" "$RALPH_CONFIG_FILE"
  set_config FEATURE "$RALPH_TEST_FEATURE"
  set_config TEST_CMD "stub-cmd tests"
  set_config TYPECHECK_CMD "stub-cmd typecheck"
  set_config MODEL "test-model"
}

# Overrides are committed too: otherwise a rollback (`git reset --hard`) would
# silently undo what the test asked for.
set_config() {
  printf '%s=%s\n' "$1" "$(harness__quote "$2")" >>"$RALPH_CONFIG_FILE"
  harness__commit "test: set $1"
}

harness__commit() {
  [ -d "$PROJECT_DIR/.git" ] || return 0
  git -C "$PROJECT_DIR" add -A
  git -C "$PROJECT_DIR" diff --cached --quiet && return 0
  git -C "$PROJECT_DIR" commit -q -m "$1"
}

harness__quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# ── shims ────────────────────────────────────────────────────────────────────

harness__install_shims() {
  local shim
  for shim in "$RALPH_HARNESS_DIR"/shims/*; do
    cp "$shim" "$SHIM_BIN/"
  done
  chmod +x "$SHIM_BIN"/*

  # A pack that needs node has broken its bash-only promise; make that loud
  # instead of silently depending on whatever the machine has installed.
  local tool
  for tool in node npm npx; do
    cat >"$SHIM_BIN/$tool" <<'NONODE'
#!/usr/bin/env bash
printf "ralph tests: '%s' must not be required (bash-only fallback)\n" "$(basename "$0")" >&2
exit 99
NONODE
    chmod +x "$SHIM_BIN/$tool"
  done

  export RALPH_SHIM_STATE="$SHIM_STATE"
  export PATH="$SHIM_BIN:$PATH"
  export HOME="$RALPH_TEST_DIR/home"
}

# ── git ──────────────────────────────────────────────────────────────────────

harness__init_git() {
  export GIT_CONFIG_NOSYSTEM=1
  # An empty template directory: the machine's git templates and hooks must not
  # leak into a fixture project.
  git -c init.defaultBranch=main init -q \
    --template="$PROJECT_DIR/.git-template" "$PROJECT_DIR"
  git -C "$PROJECT_DIR" config user.name "ralph test"
  git -C "$PROJECT_DIR" config user.email "ralph@test.invalid"
  git -C "$PROJECT_DIR" config commit.gpgsign false
  git -C "$PROJECT_DIR" add -A
  git -C "$PROJECT_DIR" commit -q -m "fixture: initial project"
}

# ── tracker ──────────────────────────────────────────────────────────────────

use_tickets() {
  local t
  if [ "$#" -eq 0 ]; then
    cp "$RALPH_FIXTURES"/tickets/*.md "$TRACKER_DIR/"
  else
    for t in "$@"; do
      cp "$RALPH_FIXTURES/tickets/${t%.md}.md" "$TRACKER_DIR/"
    done
  fi
  harness__commit "test: seed tracker"
}

ticket_file() {
  printf '%s/%s.md' "$TRACKER_DIR" "${1%.md}"
}

ticket_status() {
  ticket_field "$1" Status
}

# Read a ticket field without going through the pack: an assertion that used
# the pack's own reader could not catch the pack writing nonsense. Line endings
# are normalised here too — otherwise a CRLF fixture fails the assertion for
# reasons that have nothing to do with what is being asserted.
ticket_field() {
  sed -n "s/^\*\*$2:\*\*[[:space:]]*//p" "$(ticket_file "$1")" |
    awk 'NR == 1 { sub(/[[:space:]]+$/, ""); print }'
}

ticket_has_field() {
  grep -q "^\*\*$2:\*\*" "$(ticket_file "$1")"
}

run_lock_dir() {
  printf '%s/.run.lock' "$FEATURE_DIR"
}

# Spelled out here rather than asked of the pack: a test that used
# ralph_tree_lock_path could not catch the pack putting the lock somewhere a
# session can reach, which is the one thing this lock has to get right.
tree_lock_dir() {
  printf '%s/.git/ralph.tree.lock' "$PROJECT_DIR"
}

# ── driving the pack ─────────────────────────────────────────────────────────

run_loop() {
  run bash "$PACK_DIR/loop.sh" "$@"
}

# Run pack code as a real process, with the config and libs loaded the way
# loop.sh loads them. Mirrors that bootstrap deliberately: the smoke test keeps
# loop.sh honest, this keeps the libs drivable before the loop uses them.
pack_run() {
  run env RALPH_CONFIG="$RALPH_CONFIG_FILE" bash -c '
    set -euo pipefail
    RALPH_DIR="$1"
    shift
    export RALPH_DIR
    . "$RALPH_CONFIG"
    for lib in "$RALPH_DIR"/lib/*.sh; do
      [ -e "$lib" ] || continue
      . "$lib"
    done
    eval "$@"
  ' _ "$PACK_DIR" "$*"
}

# Same, detached, so a test can hold something (a run lock) while it inspects
# the tracker. Returns the pid in $PACK_BG_PID.
pack_run_bg() {
  env RALPH_CONFIG="$RALPH_CONFIG_FILE" bash -c '
    set -euo pipefail
    RALPH_DIR="$1"
    shift
    export RALPH_DIR
    . "$RALPH_CONFIG"
    for lib in "$RALPH_DIR"/lib/*.sh; do
      [ -e "$lib" ] || continue
      . "$lib"
    done
    eval "$@"
  ' _ "$PACK_DIR" "$*" >"$RALPH_TEST_DIR/bg.out" 2>&1 &
  PACK_BG_PID=$!
}

# Wait for a file to appear, so a test never races a background process.
wait_for_file() {
  local target="$1" tries="${2:-100}"
  while [ "$tries" -gt 0 ]; do
    [ -e "$target" ] && return 0
    tries=$((tries - 1))
    sleep 0.05
  done
  return 1
}

# ── scripting the shims ──────────────────────────────────────────────────────

# Replace the fake claude's behaviour. Reads a bash script on stdin; it is run
# with the real argv and the real prompt on stdin.
script_claude() {
  cat >"$SHIM_STATE/claude.script"
  chmod +x "$SHIM_STATE/claude.script"
}

claude_call_count() {
  cat "$SHIM_STATE/claude.count" 2>/dev/null || echo 0
}

claude_call_argv() {
  cat "$SHIM_STATE/claude.calls/${1:-1}.argv" 2>/dev/null
}

claude_call_stdin() {
  cat "$SHIM_STATE/claude.calls/${1:-1}.stdin" 2>/dev/null
}

claude_call_env() {
  cat "$SHIM_STATE/claude.calls/${1:-1}.env" 2>/dev/null
}

# Drive the in-band budget signal the real binary emits right after init.
# Takes the JSON body of rate_limit_info.
claude_rate_limit() {
  printf '%s' "$1" >"$SHIM_STATE/claude.rate_limit"
}

stub_exit() {
  printf '%s\n' "$2" >"$SHIM_STATE/stub-$1.exit"
}

stub_call_count() {
  if [ -f "$SHIM_STATE/stub-$1.calls" ]; then
    awk 'END { print NR }' "$SHIM_STATE/stub-$1.calls"
  else
    echo 0
  fi
}

usage_respond() {
  printf '%s' "$1" >"$SHIM_STATE/curl.body"
}

usage_exit() {
  printf '%s\n' "$1" >"$SHIM_STATE/curl.exit"
}

curl_calls() {
  cat "$SHIM_STATE/curl.calls" 2>/dev/null
}

at_exit() {
  printf '%s\n' "$1" >"$SHIM_STATE/at.exit"
}

at_calls() {
  cat "$SHIM_STATE/at.calls" 2>/dev/null
}
