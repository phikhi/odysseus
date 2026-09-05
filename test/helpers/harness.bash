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
#   stamp_claim ID [OWNER] [ISO]   claim a ticket behind the pack's back
#   $RALPH_SHIM_STATE/tracker-dir  (read by a fake) the real tracker's path
#   $RALPH_SHIM_STATE/project-dir  (read by a fake) the tree the run started in
#   set_config KEY VALUE           override a config key in ralph.config.sh
#   config_default KEY             what the shipped example gives that key
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
#   session_writes PATH ...        paths the delivery session writes (default:
#                                  the write-surface the ticket declared)
#   session_writes_nothing         a session that answers and writes nothing
#   lens_verdict NAME pass|fail    what a review lens answers ('' = every lens)
#   lens_writes NAME PATH ...      paths a lens writes in the tree it judges
#   lens_refused NAME [STATUS ...] a lens the API refused: the in-band event, no
#                                  verdict, non-zero exit
#   lens_call_count NAME           how many times that lens was spawned
#   lenses_that_ran                every lens that was spawned, sorted
#   lens_call_stdin NAME           the prompt that lens was handed
#   lens_call_argv NAME            argv that lens was spawned with
#   retro_answer LINE ...          the tagged lines the retro subagent answers
#   retro_answer_nth N LINE ...    what the Nth retro of the run answers
#   retro_refused [STATUS ...]     a retro session the API refused
#   retro_rate_limit JSON          the in-band event the retro's stream carries,
#                                  on a session that answers all the same
#   retro_call_count               how many retro subagents were spawned
#   retro_call_stdin [N]           the prompt the Nth retro was handed
#   retro_call_argv [N]            argv the Nth retro was spawned with
#   playthrough_answer LINE ...    the tagged lines the terminal value gate answers
#   playthrough_answer_nth N ...   what the Nth value gate of the run answers
#   playthrough_refused [STATUS]   a value-gate session the API refused
#   playthrough_rate_limit JSON    the in-band event that one session's stream carries
#   playthrough_call_count         how many value gates were spawned
#   playthrough_call_stdin [N]     the prompt the Nth one was handed
#   playthrough_call_argv [N]      argv it was spawned with
#   playthrough_file               where this feature's playthrough is written
#   stub_exit NAME CODE            exit code for `stub-cmd NAME`
#   stub_call_count NAME           how many times it ran
#   usage_respond JSON [JSON ...]  body served for /api/oauth/usage; several
#                                  bodies answer one call each, last one repeats
#   usage_exit CODE                curl exit code
#   curl_call_count                how many times the endpoint was asked
#   at_exit CODE                   `at` exit code
#   at_calls                       recorded `at` invocations
#   at_call_count                  how many successors were queued
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

  # Where the *real* tracker is, for a fake that means to write it.
  #
  # Since [13] a session's working directory is a throwaway worktree, so
  # `.scratch/<feature>/issues/…` written relative to it lands in a copy nobody
  # reads and nothing restores — a scenario staging "a session edits the tracker"
  # would then assert against a guarantee it had not exercised. Four of them did.
  # A determined session can find the tree the run was started in (`git worktree
  # list` answers it); this file is how a fake does the same thing in one line.
  printf '%s\n' "$TRACKER_DIR" >"$SHIM_STATE/tracker-dir"
  # And the tree the run was started in, for the same reason: a fake that means
  # to reach the run's own lock, index or git directory is reaching for the main
  # tree, not for the worktree it happens to be standing in.
  printf '%s\n' "$PROJECT_DIR" >"$SHIM_STATE/project-dir"

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
#
# This file is in the key too, and it took a mutation to notice it was not: the
# template carries a whole `.git` directory built by harness__build_project, so an
# edit to how the fixture world is *built* was reusing a project stamped out before
# it. The symptom was the honest shape of a false green — a mutation that removed a
# line from the fixture's git directory reported VACUOUS against a test that was
# fine, because the mutated line had never run.
harness__pack_fingerprint() {
  (
    cd "$RALPH_PACK_ROOT" || return 1
    local files
    files="$(find .claude test/fixtures test/helpers/harness.bash -type f \
      ! -name 'settings.local.json' | LC_ALL=C sort)"
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

  # The gate's judgement tier, off — an injection of the same kind as the three
  # above, and for the same reason. A review lens is a `claude` session ([06]), so
  # a suite that left the tier on would spawn two extra ones per green iteration
  # and every assertion about how many sessions the loop started would really be
  # an assertion about the fan.
  #
  # The shipped default is *on*, and this is exactly the arrangement that makes a
  # promise "verified only on the fake that finishes fast". So it is verified in
  # two other places on purpose: test/lenses.bats drives the registry itself, and
  # test/canary.bats puts the default back with config_default and runs the loop
  # the way a project would get it.
  set_config LENSES none

  # The terminal value gate, configured — and this one is injected *on*, which is
  # the opposite of the two below and not an inconsistency ([11]). A project can
  # switch the lens tier and the retro tier off; it cannot switch this one off,
  # because a value gate with an off switch is a feature closing on nothing. So
  # the harness cannot make a count of sessions stay a count of sessions by
  # turning it off — what it can do is give it the three keys a project that
  # means to finish a feature has to give it, so that a run which drains its
  # frontier closes the way a configured project's does.
  #
  # `stub-cmd` behind both commands, like TEST_CMD and TYPECHECK_CMD, so a test
  # drives their exit codes and their output with `stub_exit` and reads
  # `stub_call_count`. `VISUAL_REAL_ASSETS=1` is the claim a project makes about
  # its own commands; the case where it has not made it is a test of its own.
  set_config RUN_CMD "stub-cmd run"
  set_config VISUAL_CMD "stub-cmd visual"
  set_config VISUAL_REAL_ASSETS 1

  # The fourth layer's subagent, off, and it is the same injection for the same
  # reason ([14]). The retro is a `claude` too, so a suite that left it on would
  # spawn one more session on every iteration that finished a ticket, and every
  # assertion about how many sessions the loop started would really be an
  # assertion about the retro.
  #
  # The shipped default is *on*. It is put back in two places on purpose, so that
  # the promise is not "verified only where it was switched off": test/retro.bats
  # drives the module and the loop with it on, and test/canary.bats runs the loop
  # the way a project would get it, with config_default.
  set_config RETRO off
}

# What the shipped config gives a key, read out of the example rather than
# retyped. A test asserting on "the default" has to take the default from the one
# file a project installs, or it goes on passing against a value nobody ships any
# more.
config_default() {
  sed -n "s/^$1=\"\\\${$1:-\(.*\)}\"\$/\1/p" \
    "$PACK_DIR/ralph.config.sh.example" | head -1
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
  # What the empty template took away and every real `git init` puts there. It is
  # not decoration: `.git/info/exclude` is an ignore rule source, so it decides
  # what any check built on a git tree can see — and a fixture without it is a
  # world where the hole [30] closed could not even be staged. Probed the hard
  # way: the first probe of that ticket wrote to a directory that did not exist,
  # and the session's own widening silently failed with it.
  mkdir -p "$PROJECT_DIR/.git/info"
  printf '# git ls-files --others --exclude-from=.git/info/exclude\n' \
    >"$PROJECT_DIR/.git/info/exclude"
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
  harness__stamp_live_claims
  harness__commit "test: seed tracker"
}

# `owner=pid:@LIVE_PID@ at=@NOW@` in a fixture becomes a claim held by a process
# that really is alive, right now.
#
# A static fixture cannot express that, and the difference is the whole of [12]:
# a claim held by a live run must stay out of the frontier, a claim left behind by
# a dead one must come back to it. The fixture that used to stand for "someone
# else's claim" named pid 999999 and a timestamp from the week before — a *dead*
# owner — so three tests asserting "the loop leaves it alone" were really
# asserting that nothing ever looked.
#
# The pid is this bats process: alive for as long as the test runs, and it
# belongs to the user running the suite, so `kill -0` answers for it.
harness__stamp_live_claims() {
  local f
  for f in "$TRACKER_DIR"/*.md; do
    [ -e "$f" ] || continue
    grep -q '@LIVE_PID@' "$f" || continue
    perl -pi -e "s/\@LIVE_PID\@/$$/g; s/\@NOW\@/$(date -u +%Y-%m-%dT%H:%M:%SZ)/g" "$f"
  done
}

# Put a claim on a ticket without going through the pack, so a test can seed the
# case it means: a dead owner, a live one, a stamp from another century, no stamp
# at all. Written the way the tracker writes it — the point is to be
# indistinguishable from a claim the pack left behind.
#
#   stamp_claim 01-alpha 'pid:999999' '2026-07-25T08:00:00Z'
#   stamp_claim 01-alpha "pid:$$"                              (now)
#   stamp_claim 01-alpha ''                                    (claimed, no record)
stamp_claim() {
  local id="$1" owner="${2:-}" at="${3:-}" file record
  file="$(ticket_file "$id")"
  [ -n "$at" ] || at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  perl -pi -e 's/^\*\*Status:\*\*.*$/**Status:** claimed/; s/^\*\*Claimed:\*\*.*\n//' "$file"
  if [ -n "$owner" ]; then
    record="owner=$owner at=$at"
    perl -pi -e "s/^(\\*\\*Status:\\*\\* claimed)\$/\$1\\n\\n**Claimed:** $record/" "$file"
  fi
  harness__commit "test: claim $id"
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

# The same run, with a temporary directory of its own.
#
# Everything the pack mktemps lands there — the pinned ignore rules above all
# ([30]) — which is what makes "a session that closes the instrument" stageable at
# all: the pin is the one part of the pack a session can reach and the pack cannot
# protect, so a scenario has to be able to destroy it. A fake reaching into the
# machine's shared `$TMPDIR` would find the pin of a suite running beside this one,
# and the harness already assumes concurrent runners ([34]).
run_loop_own_tmp() {
  mkdir -p "$RALPH_TEST_DIR/tmp"
  run env TMPDIR="$RALPH_TEST_DIR/tmp" bash "$PACK_DIR/loop.sh" "$@"
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

# A shell that forks a `sleep` and stays alive, written to the shim state so that
# a test can run it as the layer *between* a stand-in run and the process a
# deadline aims at ([36]). Killing it takes the target's parent away without
# touching the run, which is the only way a test can stage "this number no longer
# names what I was aimed at": the real cause, a reissued pid, cannot be arranged on
# demand. Its target's pid lands in `$SHIM_STATE/victim.pid`.
#
# Here rather than in one of the two files that use it — the gate's deadline and
# the session's — because both ask the same thing of it, and a second copy would be
# a second place for the staging to drift from what it is supposed to stage.
write_middle_shell() {
  cat >"$SHIM_STATE/middle.sh" <<'MIDDLE'
#!/usr/bin/env bash
sleep 30 &
printf '%s\n' "$!" >"$RALPH_SHIM_STATE/victim.pid"
wait
MIDDLE
}

# Two recorders in front of everything, passing through to the real thing: what
# they record is every program the pack resolved through the PATH being judged.
# The marker lands in `$SHIM_STATE/ran`, and its *absence* is the assertion — a
# refusal handed down after a planted program has already run is not a refusal.
#
# Here rather than in one of the two files that use it, and for the reason
# `write_middle_shell` is here: the pack has two entry points since [16] and both
# owe the same guarantee ([52] — the refusal lands before the first name is
# resolved through the PATH being refused). A second copy would be a second place
# for the staging to drift from what it is supposed to stage, and only one of the
# two would be measuring anything.
#
# `dirname` is one of the two on purpose: it is the program a bootstrap reaches
# for, and computing `RALPH_DIR` with parameter expansion instead is exactly what
# these recorders exist to hold in place.
harness_path_recorders() {
  local name dir="$RALPH_TEST_DIR/recorder"
  mkdir -p "$dir"
  for name in git dirname; do
    {
      printf '#!/usr/bin/env bash\n'
      printf 'printf "%%s\\n" "%s" >>"%s/ran"\n' "$name" "$SHIM_STATE"
      printf 'exec "$(PATH="${PATH#*:}" command -v %s)" "$@"\n' "$name"
    } >"$dir/$name"
    chmod +x "$dir/$name"
  done
  printf '%s\n' "$dir"
}

# Wait for a file to appear, so a test never races a background process.
#
# It counts *tries*, not seconds, and that is fine for what it is for — waiting on
# something that is about to happen. It is not a deadline: under load a try costs
# more than its sleep, so 240 of them can outlast a wall-clock minute. A test whose
# guarantee is that something terminates must therefore not rest its verdict on
# this timing out; it needs an assertion on what only the termination could have
# prevented. One did, and a full mutate.sh run stretched it far enough for the
# session to end by itself — the test stayed green with the guarantee removed ([23]).
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

# Every spawn, delivery sessions and review lenses alike. Counted from the slots
# the fake claimed rather than from a counter it wrote: the slots are allocated
# with `mkdir`, so they survive concurrency, and a number written by three
# processes at once does not.
claude_call_count() {
  local slot n=0
  for slot in "$SHIM_STATE/claude.calls"/*; do
    [ -d "$slot" ] || continue
    n=$((n + 1))
  done
  printf '%s\n' "$n"
}

claude_call_argv() {
  cat "$SHIM_STATE/claude.calls/${1:-1}/argv" 2>/dev/null
}

claude_call_stdin() {
  cat "$SHIM_STATE/claude.calls/${1:-1}/stdin" 2>/dev/null
}

claude_call_env() {
  cat "$SHIM_STATE/claude.calls/${1:-1}/env" 2>/dev/null
}

# What the tree the session started in contributed to it, as the shim recorded it:
# the project MCP servers it would have loaded, and the project-side settings and
# CLAUDE.md it would have read. Empty is the answer a review lens must get ([31]) —
# and an empty file and a missing one are the same answer here, because a project
# without a `.mcp.json` contributes nothing either way.
# `|| true` and not `; return 0`: a missing file is the *expected* answer here, and
# the runner traps ERR — a `cat` that failed on its way to a zero return still
# printed a failure line into the output the caller is about to assert on.
claude_call_mcp_loaded() {
  cat "$SHIM_STATE/claude.calls/${1:-1}/mcp-loaded" 2>/dev/null || true
}

claude_call_project_config() {
  cat "$SHIM_STATE/claude.calls/${1:-1}/project-config" 2>/dev/null || true
}

lens_call_mcp_loaded() {
  claude_call_mcp_loaded "$(head -1 "$SHIM_STATE/claude.lenses/$1" 2>/dev/null)"
}

lens_call_project_config() {
  claude_call_project_config "$(head -1 "$SHIM_STATE/claude.lenses/$1" 2>/dev/null)"
}

# Drive the in-band budget signal the real binary emits early in the stream —
# third event in the capture, after init and a first thinking estimate.
# Takes the JSON body of rate_limit_info.
claude_rate_limit() {
  printf '%s' "$1" >"$SHIM_STATE/claude.rate_limit"
}

# ── scripting the review lenses ──────────────────────────────────────────────
#
# Addressed by lens name and never by call index. The lens branches are started
# concurrently, so which of them is the loop's second `claude` is not a fact a
# test is entitled to know — and a test that assumed it would pass or fail on
# process scheduling.

# What verdict the fake answers for a lens. `lens_verdict '' fail` sets it for
# every lens that has no verdict of its own.
lens_verdict() {
  if [ -n "$1" ]; then
    printf '%s\n' "$2" >"$SHIM_STATE/lens-$1.verdict"
  else
    printf '%s\n' "$2" >"$SHIM_STATE/lens.verdict"
  fi
}

# Paths a lens writes in the tree it is judging, one per line. The case the gate
# has to contain, and nothing but a fake can stage it on demand.
lens_writes() {
  local name="$1"
  shift
  printf '%s\n' "$@" >"$SHIM_STATE/lens-$name.writes"
}

# A lens the API refused ([43]): its stream carries the in-band event, it says no
# verdict at all, and it exits non-zero. The lens half of
# `script_refused_session`, which can only stage the delivery session — and named
# per lens, because the whole question is telling a refused branch apart from the
# lens that judged beside it.
#
# `allowed` is a legal argument here and is the refutation the pair needs: the
# same missing verdict with a stream that says nothing about quota is a lens that
# died, and stays red and billed.
lens_refused() {
  local name="$1" status="${2:-blocked}" window="${3:-five_hour}" reset="${4:-0}"
  printf '{"status":"%s","resetsAt":%s,"rateLimitType":"%s","isUsingOverage":false}\n' \
    "$status" "$reset" "$window" >"$SHIM_STATE/lens-$name.refused"
}

# A lens that destroys the pinned ignore rules `gate_tree_snapshot` refuses
# without ([34]) — the instrument the gate measures a lens's writes with. Only
# meaningful under `run_loop_own_tmp`, which is what makes the sweep hit this
# test's pin and nobody else's.
lens_closes_measurement() {
  mkdir -p "$RALPH_TEST_DIR/tmp"
  printf '%s\n' "$RALPH_TEST_DIR/tmp" >"$SHIM_STATE/lens-$1.closes-measurement"
}

# Paths the delivery session writes, one per line. With no arguments — and by
# default, without calling this at all — it writes whatever the ticket it was
# handed declared as its write-surface.
#
# Delivering is the default since [35] and the reason is not comfort: an iteration
# that changes no file the gate can see is red now, so a fake that wrote nothing
# would put every test in this suite on the failure path. The empty case is what a
# test asks for explicitly.
session_writes() {
  printf '%s\n' "$@" >"$SHIM_STATE/session.writes"
}

# A session that answers and writes nothing at all: the defect [35] closed, and
# nothing hostile is needed to produce it — a session that refuses the task, one
# that was handed a truncated prompt, one that spent its turn reading.
session_writes_nothing() {
  : >"$SHIM_STATE/session.silent"
}

lens_call_count() {
  if [ -f "$SHIM_STATE/claude.lenses/$1" ]; then
    awk 'END { print NR }' "$SHIM_STATE/claude.lenses/$1"
  else
    echo 0
  fi
}

# Every lens that was spawned, sorted, as one line — so a test can assert the
# whole set that ran and, more to the point, the set that did not.
lenses_that_ran() {
  local f out=''
  for f in "$SHIM_STATE/claude.lenses"/*; do
    [ -e "$f" ] || continue
    out="$out $(basename "$f")"
  done
  printf '%s\n' "$(printf '%s' "${out# }" | tr ' ' '\n' | LC_ALL=C sort |
    tr '\n' ' ' | sed 's/ *$//')"
}

lens_call_stdin() {
  claude_call_stdin "$(head -1 "$SHIM_STATE/claude.lenses/$1" 2>/dev/null)"
}

lens_call_argv() {
  claude_call_argv "$(head -1 "$SHIM_STATE/claude.lenses/$1" 2>/dev/null)"
}

# ── scripting the retro subagent ─────────────────────────────────────────────
#
# Addressed by nothing at all: there is at most one retro per iteration, and it is
# the last session an iteration spawns. What a test needs is the answer it gives
# and the prompt it was handed.

# The tagged lines the retro answers with, one per argument. No answer at all —
# and by default, without calling this — is `RALPH-RETRO-NOTHING`, which is what
# the shipped prompt asks for and what makes the tier self-suppressing.
#
# Avoid double quotes in an argument: the fake puts the answer in a JSON string,
# the way the real binary does, and a fake that escaped them would be modelling
# its own escaping rather than the pack's scanner.
retro_answer() {
  printf '%s\n' "$@" >"$SHIM_STATE/retro.answer"
}

# The answer the Nth retro of the run gives, for a test that needs two iterations
# to say different things — a lesson that supersedes an earlier one, two lessons
# that have to coexist in the index.
retro_answer_nth() {
  local n="$1"
  shift
  printf '%s\n' "$@" >"$SHIM_STATE/retro.answer.$n"
}

# A retro session the API refused ([08]/[43] applied to this tier): the in-band
# event, no answer, non-zero exit.
retro_refused() {
  local status="${1:-blocked}" window="${2:-five_hour}" reset="${3:-0}"
  printf '{"status":"%s","resetsAt":%s,"rateLimitType":"%s","isUsingOverage":false}\n' \
    "$status" "$reset" "$window" >"$SHIM_STATE/retro.refused"
}

# The in-band budget event the retro session's own stream carries, and only that
# one — `claude_rate_limit` would tell the delivery session's stream the same
# thing, and the pilot reads *that* posture to decide whether to pause, so a test
# using it would be measuring a paused run instead of a refused retro.
#
# The case `retro_refused` cannot express, and the reason nobody had written it
# ([63]): an event **with** an answer. `retro_refused` is the event plus `exit 1`
# and no answer at all — a session that never started. This one is a session that
# ran, answered its tagged lines, and was told in passing that a window it may
# never spend is blocked. The value gate has had its own since [11]
# (`playthrough_rate_limit`); this tier did not, and the defect lived in the gap.
retro_rate_limit() {
  printf '%s' "$1" >"$SHIM_STATE/retro.rate_limit"
}

retro_call_count() {
  if [ -f "$SHIM_STATE/claude.retros/calls" ]; then
    awk 'END { print NR }' "$SHIM_STATE/claude.retros/calls"
  else
    echo 0
  fi
}

retro_call_stdin() {
  claude_call_stdin "$(sed -n "${1:-1}p" "$SHIM_STATE/claude.retros/calls" 2>/dev/null)"
}

retro_call_argv() {
  claude_call_argv "$(sed -n "${1:-1}p" "$SHIM_STATE/claude.retros/calls" 2>/dev/null)"
}

# ── scripting the terminal value gate ────────────────────────────────────────
#
# Addressed by nothing at all, like the retro: there is at most one playthrough
# per run and it is the last session of it.

# The tagged lines the value gate answers with, one per argument. No call at all
# is a green playthrough with one step — the shipped prompt's own shape, and the
# default every test that only means to drain a frontier gets.
#
# Avoid double quotes in an argument, for the reason `retro_answer` gives: the
# fake puts the answer in a JSON string the way the real binary does.
playthrough_answer() {
  printf '%s\n' "$@" >"$SHIM_STATE/playthrough.answer"
}

# What the Nth value gate of the run answers, for a test that needs two rounds —
# a red one that re-injects a wiring ticket, and the one that follows the
# iteration which closed the hole.
playthrough_answer_nth() {
  local n="$1"
  shift
  printf '%s\n' "$@" >"$SHIM_STATE/playthrough.answer.$n"
}

# A value gate the API refused ([43] applied to this tier): the in-band event, no
# verdict, non-zero exit. The feature does not close and nobody is accused.
playthrough_refused() {
  local status="${1:-blocked}" window="${2:-five_hour}" reset="${3:-0}"
  printf '{"status":"%s","resetsAt":%s,"rateLimitType":"%s","isUsingOverage":false}\n' \
    "$status" "$reset" "$window" >"$SHIM_STATE/playthrough.refused"
}

# The in-band budget event the value gate's own stream carries, and only that
# one: the pilot reads the delivery session's posture to decide whether to pause,
# so `claude_rate_limit` would be staging something else entirely.
playthrough_rate_limit() {
  printf '%s' "$1" >"$SHIM_STATE/playthrough.rate_limit"
}

playthrough_call_count() {
  if [ -f "$SHIM_STATE/claude.playthroughs/calls" ]; then
    awk 'END { print NR }' "$SHIM_STATE/claude.playthroughs/calls"
  else
    echo 0
  fi
}

playthrough_call_stdin() {
  claude_call_stdin "$(sed -n "${1:-1}p" "$SHIM_STATE/claude.playthroughs/calls" 2>/dev/null)"
}

playthrough_call_argv() {
  claude_call_argv "$(sed -n "${1:-1}p" "$SHIM_STATE/claude.playthroughs/calls" 2>/dev/null)"
}

# Where the artefact lands for this test's feature. Spelled out here rather than
# asked of the pack: a test that used `playthrough_path` could not catch the pack
# writing the document somewhere nobody reads it.
playthrough_file() {
  printf '%s/docs/playthroughs/%s.md' "$PROJECT_DIR" "$RALPH_TEST_FEATURE"
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

# What the usage endpoint answers. One body answers every call; several answer
# one call each, in order, and the last one repeats — which is how a test drives
# a run that pauses on a spent window and then finds it refilled.
usage_respond() {
  local i=0 body
  for body in "$@"; do
    i=$((i + 1))
    printf '%s' "$body" >"$SHIM_STATE/curl.body.$i"
  done
  printf '%s' "${!#}" >"$SHIM_STATE/curl.body"
}

# How many times the endpoint was asked, counted from the slots the shim claimed.
curl_call_count() {
  local slot n=0
  for slot in "$SHIM_STATE/curl.slots"/*; do
    [ -d "$slot" ] || continue
    n=$((n + 1))
  done
  printf '%s\n' "$n"
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

# How many successors were queued. Zero is the answer a test needs most often
# here ([09]: almost every guard on arming is a refusal to arm), and `at_calls`
# cannot say it — an empty recording and a missing file read the same.
at_call_count() {
  cat "$SHIM_STATE/at.count" 2>/dev/null || printf 0
}

# The shell an iteration runs in: a child of the pilot ([13]). A test that means
# to reproduce "a signal reached the iteration, not just the run" — a Ctrl-C, a
# `kill` addressed to the process group — has to aim at this one, because the
# pilot's own children do not inherit its traps and never see a signal sent to it
# alone. Empty when nothing is in flight.
# Narrowed to the shells running the pack, and that narrowing is load-bearing: the
# pilot's other children are its own `sleep`s, and a TERM delivered to one of them
# takes the whole run down through `errexit` — which is a signal a test would then
# be measuring instead of the one it meant to send.
# Whether a background run is still *running*, as opposed to still answering.
#
# `kill -0` is the wrong question and [36] wrote down why: a process that has
# exited but has not been reaped by the shell that started it is a zombie, and a
# zombie answers `kill -0` exactly like a live process. A test that asked the
# number instead of the state watched a run that had been gone for ten seconds and
# concluded it was draining.
pack_still_running() {
  local state
  state="$(ps -o state= -p "${1:-$PACK_BG_PID}" 2>/dev/null | awk 'NR == 1 { print $1 }')"
  [ -n "$state" ] || return 1
  case "$state" in
    Z*) return 1 ;;
  esac
  return 0
}

pack_iteration_pids() {
  ps -A -o pid= -o ppid= -o command= 2>/dev/null |
    awk -v p="${1:-$PACK_BG_PID}" '$2 == p && $0 ~ /loop\.sh/ { print $1 }'
}
