#!/usr/bin/env bats
#
# The run lock and atomic publication.
#
# The lock is the coarse guarantee that one tracker has at most one run — AFK
# or human, never both. Everything here drives real processes, because that is
# the only way a lock means anything.

load helpers/harness
load helpers/assert

setup() {
  harness_setup
  use_tickets
}

teardown() {
  # Never leave a background holder behind, whatever the test did.
  if [ -n "${PACK_BG_PID:-}" ]; then
    kill -KILL "$PACK_BG_PID" 2>/dev/null || true
  fi
  harness_teardown
}

@test "the run lock is taken, then released when the run exits" {
  pack_run 'run_lock_acquire && echo acquired'
  assert_success
  assert_output_contains "acquired"

  [ ! -d "$(run_lock_dir)" ] || fail "lock survived the run: $(run_lock_dir)"
}

@test "a live run keeps a second one out" {
  pack_run_bg '
    run_lock_acquire
    : > "$(ralph_project_root)/holding"
    while [ ! -f "$(ralph_project_root)/release" ]; do sleep 0.05; done
  '
  wait_for_file "$PROJECT_DIR/holding" || fail "the background run never took the lock"

  pack_run 'run_lock_acquire && echo acquired'
  assert_failure
  assert_output_contains "another run already holds"
  refute_output_contains "acquired"

  : >"$PROJECT_DIR/release"
  wait "$PACK_BG_PID" || true
  PACK_BG_PID=""

  [ ! -d "$(run_lock_dir)" ] || fail "lock survived the run"
}

@test "the lock is released on a graceful kill" {
  pack_run_bg '
    run_lock_acquire
    : > "$(ralph_project_root)/holding"
    while :; do sleep 0.05; done
  '
  wait_for_file "$PROJECT_DIR/holding" || fail "the background run never took the lock"
  [ -d "$(run_lock_dir)" ] || fail "the lock was not taken"

  kill -TERM "$PACK_BG_PID"
  wait "$PACK_BG_PID" || true
  PACK_BG_PID=""

  [ ! -d "$(run_lock_dir)" ] || fail "SIGTERM left the lock behind"
}

@test "a lock whose holder died is taken over" {
  # A pid that is definitely gone.
  bash -c 'exit 0' &
  dead=$!
  wait "$dead" 2>/dev/null || true

  mkdir -p "$(run_lock_dir)"
  printf '%s\n' "$dead" >"$(run_lock_dir)/pid"

  pack_run 'run_lock_acquire && echo acquired'
  assert_success
  assert_output_contains "stale run lock"
  assert_output_contains "acquired"

  [ ! -d "$(run_lock_dir)" ] || fail "lock survived the run"
}

@test "a lock held by a live process is not stolen" {
  # $$ is this very test process, so the holder is unquestionably alive.
  mkdir -p "$(run_lock_dir)"
  printf '%s\n' "$$" >"$(run_lock_dir)/pid"

  pack_run 'run_lock_acquire && echo acquired'
  assert_failure
  refute_output_contains "acquired"

  assert_equal "$(cat "$(run_lock_dir)/pid")" "$$"
}

@test "a run only releases its own lock" {
  mkdir -p "$(run_lock_dir)"
  printf '%s\n' "$$" >"$(run_lock_dir)/pid"

  pack_run 'run_lock_release'
  assert_success

  [ -d "$(run_lock_dir)" ] || fail "released a lock it never held"
}

@test "the lock is per feature: two features run side by side" {
  mkdir -p "$PROJECT_DIR/.scratch/other/issues"
  mkdir -p "$(run_lock_dir)"
  printf '%s\n' "$$" >"$(run_lock_dir)/pid"

  pack_run 'FEATURE=other; run_lock_acquire && echo acquired'
  assert_success
  assert_output_contains "acquired"

  # And the demo lock was left strictly alone.
  assert_equal "$(cat "$(run_lock_dir)/pid")" "$$"
}

@test "run_lock_held_by names the holder" {
  mkdir -p "$(run_lock_dir)"
  printf '%s\n' "$$" >"$(run_lock_dir)/pid"

  pack_run 'run_lock_held_by'
  assert_success
  assert_equal "$output" "$$"
}

@test "atomic writes publish in one step and leave no temp behind" {
  pack_run 'printf "%s\n" "published" | state_atomic_write "$(ralph_project_root)/artifact.txt"'
  assert_success

  assert_file_contains "$PROJECT_DIR/artifact.txt" "published"

  run bash -c "ls '$PROJECT_DIR' | grep 'artifact.txt.tmp' || true"
  assert_equal "$output" ""
}

@test "a failed atomic write leaves the previous content intact" {
  pack_run 'printf "%s\n" "v1" | state_atomic_write "$(ralph_project_root)/artifact.txt"'
  assert_success

  # A directory where the temp file would go: the write cannot complete.
  pack_run 'printf "%s\n" "v2" | state_atomic_write "$(ralph_project_root)/missing-dir/artifact.txt"'
  assert_failure

  assert_file_contains "$PROJECT_DIR/artifact.txt" "v1"
}
