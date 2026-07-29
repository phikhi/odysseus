#!/usr/bin/env bats
#
# The run locks and atomic publication.
#
# Two locks, two guarantees. The run lock says one tracker has at most one run —
# AFK or human, never both. The working-tree lock says one working tree has at
# most one run, whatever features they were pointed at, because everything the
# gate and the rollback touch is repository-wide. Everything here drives real
# processes, because that is the only way a lock means anything.

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

@test "the lock is per feature, and the loop refuses the second run anyway" {
  # Two statements, and they are not the same one. This test used to make only
  # the first and read as a blessing for two runs on one repository — the
  # arrangement that turned out to be a live fault ([22]).
  #
  # The primitive really is per feature, and has to stay that way: spec §135 wants
  # grind and drain to exclude each other on one tracker, nothing wider. The loop
  # is refused all the same, because what a second run destroys is not the
  # tracker but the tree — snapshot, rollback, commit on green and HEAD are all
  # repository-wide.
  mkdir -p "$PROJECT_DIR/.scratch/other/issues"
  mkdir -p "$(run_lock_dir)"
  printf '%s\n' "$$" >"$(run_lock_dir)/pid"

  pack_run 'FEATURE=other; run_lock_acquire && echo acquired'
  assert_success
  assert_output_contains "acquired"

  # And the demo lock was left strictly alone.
  assert_equal "$(cat "$(run_lock_dir)/pid")" "$$"

  # Now the loop, on that same second feature, with the tree already held by a
  # live process. The feature lock would let it through; the tree lock does not.
  mkdir -p "$(tree_lock_dir)"
  printf '%s\n' "$$" >"$(tree_lock_dir)/pid"
  printf 'demo\n' >"$(tree_lock_dir)/note"
  set_config FEATURE other

  run_loop
  assert_failure 1
  assert_output_contains "another run already holds this working tree"
  assert_output_contains "feature demo"
  # Refused before anything happened, not part-way through an iteration.
  assert_equal "$(claude_call_count)" "0"
}

# ── the working-tree lock ────────────────────────────────────────────────────

@test "the working-tree lock is taken, then released when the run exits" {
  pack_run 'tree_lock_acquire && echo acquired'
  assert_success
  assert_output_contains "acquired"

  [ ! -d "$(tree_lock_dir)" ] || fail "tree lock survived the run: $(tree_lock_dir)"
}

@test "a live run keeps a second one off the tree, whatever feature it grinds" {
  mkdir -p "$PROJECT_DIR/.scratch/other/issues"
  pack_run_bg '
    tree_lock_acquire
    : > "$(ralph_project_root)/holding"
    while [ ! -f "$(ralph_project_root)/release" ]; do sleep 0.05; done
  '
  wait_for_file "$PROJECT_DIR/holding" || fail "the background run never took the tree lock"

  pack_run 'FEATURE=other; tree_lock_acquire && echo acquired'
  assert_failure
  refute_output_contains "acquired"
  # Which run is in the way, and why this one is not allowed to proceed anyway.
  # The feature comes from the holder's own guard, not from the assertion.
  assert_output_contains "another run already holds this working tree"
  assert_output_contains "feature demo"
  assert_output_contains "repository-wide"

  : >"$PROJECT_DIR/release"
  wait "$PACK_BG_PID" || true
  PACK_BG_PID=""

  [ ! -d "$(tree_lock_dir)" ] || fail "tree lock survived the run"
}

@test "the working-tree lock is out of reach of the tree it guards" {
  # The run lock sits under .scratch/<feature>/ and [12] showed a session can
  # delete it. This one has to survive the three ordinary ways a session reaches
  # for the tree, or the guarantee is one clean-up away from being a lie.
  pack_run_bg '
    tree_lock_acquire
    : > "$(ralph_project_root)/holding"
    while [ ! -f "$(ralph_project_root)/release" ]; do sleep 0.05; done
  '
  wait_for_file "$PROJECT_DIR/holding" || fail "the background run never took the tree lock"
  held="$(cat "$(tree_lock_dir)/pid")"

  rm -rf "$PROJECT_DIR/.scratch"
  git -C "$PROJECT_DIR" add -A
  git -C "$PROJECT_DIR" clean -xdff

  [ -d "$(tree_lock_dir)" ] || fail "the lock did not survive a session's reach into the tree"
  assert_equal "$(cat "$(tree_lock_dir)/pid")" "$held"

  # Still doing its job, not merely still present.
  pack_run 'tree_lock_acquire && echo acquired'
  assert_failure
  refute_output_contains "acquired"

  : >"$PROJECT_DIR/release"
  wait "$PACK_BG_PID" || true
  PACK_BG_PID=""
}

@test "the lock is per working tree, not per repository" {
  # The entry point this ticket leaves [13]: give each run its own worktree and
  # several features become possible again with nothing here to change. The path
  # comes from `git rev-parse --git-dir`, which a linked worktree answers with its
  # own private directory — and git keeps that worktree's index and HEAD in there
  # too, which is why two runs in two worktrees are not the fault this lock
  # refuses. Pinned rather than noted: a promise no test holds is not a promise.
  git -C "$PROJECT_DIR" worktree add -q -b wt "$RALPH_TEST_DIR/wt"

  pack_run 'printf "%s\n" "$(ralph_tree_lock_path)"'
  assert_success
  assert_equal "$output" "$PROJECT_DIR/.git/ralph.tree.lock"

  pack_run 'RALPH_PROJECT_ROOT="'"$RALPH_TEST_DIR"'/wt"; printf "%s\n" "$(ralph_tree_lock_path)"'
  assert_success
  assert_equal "$output" "$PROJECT_DIR/.git/worktrees/wt/ralph.tree.lock"
}

@test "a working-tree lock whose holder died is taken over" {
  # Otherwise a run killed without releasing wedges the repository for good, and
  # refusing to start stops being a safeguard and becomes the outage.
  bash -c 'exit 0' &
  dead=$!
  wait "$dead" 2>/dev/null || true

  mkdir -p "$(tree_lock_dir)"
  printf '%s\n' "$dead" >"$(tree_lock_dir)/pid"

  pack_run 'tree_lock_acquire && echo acquired'
  assert_success
  assert_output_contains "stale working-tree lock"
  assert_output_contains "acquired"

  [ ! -d "$(tree_lock_dir)" ] || fail "tree lock survived the run"
}

@test "both locks come off together when the run exits" {
  # One EXIT trap, two locks. Bash traps do not stack, so the acquire that ran
  # second used to be the only one with a handler — and the other lock leaked.
  pack_run '
    tree_lock_acquire
    run_lock_acquire
    printf "tree=%s run=%s\n" "$(ralph_tree_lock_path)" "$(ralph_run_lock_path)"'
  assert_success

  [ ! -d "$(tree_lock_dir)" ] || fail "the tree lock leaked past the run"
  [ ! -d "$(run_lock_dir)" ] || fail "the run lock leaked past the run"
}

@test "a graceful kill frees both locks, not just the last one taken" {
  pack_run_bg '
    tree_lock_acquire
    run_lock_acquire
    : > "$(ralph_project_root)/holding"
    while :; do sleep 0.05; done
  '
  wait_for_file "$PROJECT_DIR/holding" || fail "the background run never took the locks"
  [ -d "$(tree_lock_dir)" ] || fail "the tree lock was not taken"
  [ -d "$(run_lock_dir)" ] || fail "the run lock was not taken"

  kill -TERM "$PACK_BG_PID"
  wait "$PACK_BG_PID" || true
  PACK_BG_PID=""

  [ ! -d "$(tree_lock_dir)" ] || fail "SIGTERM left the tree lock behind"
  [ ! -d "$(run_lock_dir)" ] || fail "SIGTERM left the run lock behind"
}

@test "run_lock_held_by names the holder" {
  mkdir -p "$(run_lock_dir)"
  printf '%s\n' "$$" >"$(run_lock_dir)/pid"

  pack_run 'run_lock_held_by'
  assert_success
  assert_equal "$output" "$$"
}

@test "atomic writes publish in one step and leave no temp behind" {
  pack_run 'printf "%s\n" "v1" | state_atomic_write "$(ralph_project_root)/artifact.txt"'
  assert_success
  assert_file_contains "$PROJECT_DIR/artifact.txt" "v1"
  before="$(ls -i "$PROJECT_DIR/artifact.txt" | awk '{print $1}')"

  pack_run 'printf "%s\n" "v2" | state_atomic_write "$(ralph_project_root)/artifact.txt"'
  assert_success
  assert_file_contains "$PROJECT_DIR/artifact.txt" "v2"

  # The inode is the whole assertion. Rewriting in place keeps it, and keeping
  # it is exactly what lets a reader catch the file half-written; publishing by
  # rename replaces it, so a reader sees v1 or v2 and never anything else.
  # Asserting only "the content is there, no temp left" says nothing: a plain
  # truncate-and-write satisfies both.
  after="$(ls -i "$PROJECT_DIR/artifact.txt" | awk '{print $1}')"
  [ "$before" != "$after" ] || fail "published in place, inode unchanged ($after)"

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

# ── the lock a session can delete ────────────────────────────────────────────

@test "run_lock_is_ours tells a lock we hold from one we lost" {
  pack_run '
    printf "before=%s\n" "$(run_lock_is_ours && echo yes || echo no)"
    run_lock_acquire
    printf "held=%s\n" "$(run_lock_is_ours && echo yes || echo no)"
    rm -rf "$(ralph_run_lock_path)"
    printf "deleted=%s\n" "$(run_lock_is_ours && echo yes || echo no)"
    mkdir -p "$(ralph_run_lock_path)"
    printf "99999" >"$(ralph_run_lock_path)/pid"
    printf "stolen=%s\n" "$(run_lock_is_ours && echo yes || echo no)"'
  assert_success
  # Nothing recorded is not a lock that was lost: the libs are drivable outside
  # a run, and asking there must not read as a failure.
  assert_output_contains "before=yes"
  assert_output_contains "held=yes"
  assert_output_contains "deleted=no"
  assert_output_contains "stolen=no"
}

@test "tree_lock_is_ours tells a tree lock we hold from one we lost" {
  # `.git/` is out of reach of a clean-up, not of a session that deletes the lock
  # outright — so the loop has to be able to ask this one too, every iteration.
  pack_run '
    printf "before=%s\n" "$(tree_lock_is_ours && echo yes || echo no)"
    tree_lock_acquire
    printf "held=%s\n" "$(tree_lock_is_ours && echo yes || echo no)"
    rm -rf "$(ralph_tree_lock_path)"
    printf "deleted=%s\n" "$(tree_lock_is_ours && echo yes || echo no)"
    mkdir -p "$(ralph_tree_lock_path)"
    printf "99999" >"$(ralph_tree_lock_path)/pid"
    printf "stolen=%s\n" "$(tree_lock_is_ours && echo yes || echo no)"'
  assert_success
  assert_output_contains "before=yes"
  assert_output_contains "held=yes"
  assert_output_contains "deleted=no"
  assert_output_contains "stolen=no"
}
