#!/usr/bin/env bats
#
# The installer: the one component of the pack that lives outside a run.
#
# Everything here drives the real `init.sh` as a process against a throwaway
# project that has *nothing* — a git repository with one commit, the way a
# developer's repository looks the minute before they install this — and asserts
# on what the project has afterwards.
#
# Two properties of this file are load-bearing rather than incidental.
#
# It runs under the harness's PATH, where `node`, `npm` and `npx` are shadowed by
# a hard failure. So every install below is an install on a machine without node,
# which is the "pure bash engine, node fallback" story checked by exercise rather
# than by reading the script.
#
# And it never installs into `$PROJECT_DIR`. The harness's project already *has*
# the pack, so an installer tested there would be tested against a project where
# every assertion is already true before it runs.

load helpers/harness
load helpers/assert

INIT_SH=""

setup() {
  harness_setup
  INIT_SH="$RALPH_PACK_ROOT/init.sh"
  install_target
}

teardown() {
  harness_teardown
}

# A project the minute before the pack arrives: a git repository, one commit, no
# `.claude`, no `.gitignore`, no `CLAUDE.md`.
install_target() {
  TARGET="$RALPH_TEST_DIR/target"
  mkdir -p "$TARGET"
  git -c init.defaultBranch=main init -q "$TARGET"
  git -C "$TARGET" config user.name "ralph test"
  git -C "$TARGET" config user.email "ralph@test.invalid"
  git -C "$TARGET" config commit.gpgsign false
  printf 'a project that existed first\n' >"$TARGET/README.md"
  git -C "$TARGET" add -A
  git -C "$TARGET" commit -q -m "fixture: the project before the pack"
}

# Off a terminal the forced confirmations have to be spelt on the command line,
# so every one of them is passed here. A test that means to leave one out calls
# `bash "$INIT_SH"` itself.
run_init() {
  run env \
    FEATURE="${I_FEATURE-demo}" \
    TEST_CMD="${I_TEST_CMD-stub-cmd tests}" \
    TYPECHECK_CMD="${I_TYPECHECK_CMD-none}" \
    LANG_ARTIFACT="${I_LANG_ARTIFACT-en}" \
    LANG_CHECK="${I_LANG_CHECK-on}" \
    SCHEDULER="${I_SCHEDULER-none}" \
    VISUAL_REAL_ASSETS="${I_VISUAL_REAL_ASSETS-1}" \
    RUN_CMD="${I_RUN_CMD-stub-cmd run}" \
    VISUAL_CMD="${I_VISUAL_CMD-stub-cmd visual}" \
    WORKTREE_PROVISION="${I_WORKTREE_PROVISION-}" \
    TMPDIR="${I_TMPDIR-$TMPDIR}" \
    bash "${I_INIT-$INIT_SH}" --yes --no-sweep \
    --target "${I_TARGET-$TARGET}" --from "${I_FROM-$RALPH_PACK_ROOT}" "$@"
}

# A pack source of its own, so that a test may break one piece of it without
# touching the repository the suite is running from.
fake_pack_source() {
  local dest="$RALPH_TEST_DIR/pack-source"
  mkdir -p "$dest/.claude" "$dest/docs"
  cp -R "$RALPH_PACK_ROOT/.claude/lib" "$dest/.claude/lib"
  cp -RL "$RALPH_PACK_ROOT/.claude/skills" "$dest/.claude/skills"
  cp "$RALPH_PACK_ROOT/.claude/loop.sh" "$RALPH_PACK_ROOT/.claude/human-loop.sh" \
    "$RALPH_PACK_ROOT/.claude/settings.json" \
    "$RALPH_PACK_ROOT/.claude/ralph.config.sh.example" "$dest/.claude/"
  cp "$RALPH_PACK_ROOT/skills-lock.json" "$dest/skills-lock.json"
  cp "$RALPH_PACK_ROOT/package.json" "$dest/package.json"
  cp -R "$RALPH_PACK_ROOT/docs/agents" "$dest/docs/agents"
  printf '%s\n' "$dest"
}

# ── the whole thing, against the world as it is ──────────────────────────────

@test "a repository that had nothing runs the loop once the installer has been through it" {
  run_init
  assert_success

  # Not "the installer exited 0", which two bugs of this repository have already
  # lived behind: the pack it deposited is started, as a process, and answers
  # the one thing a freshly installed project can answer — an empty frontier.
  run env TMPDIR="$TMPDIR" bash "$TARGET/.claude/loop.sh"
  assert_failure 5
  assert_output_contains "run start (feature=demo backend=local"
  assert_output_contains "nothing to grind"
}

@test "the installer reports that every refusal loop.sh checks passes" {
  run_init
  assert_success
  assert_output_contains "every refusal \`loop.sh\` checks at startup passes on this project"
}

@test "a config the loop would refuse is reported at install time, not at three in the morning" {
  I_SCHEDULER="whenever" run_init
  # The pack is installed either way — the refusal is about the config, and the
  # human is here to read it. What must not happen is silence.
  assert_success
  assert_output_contains 'SCHEDULER is "whenever"'
  assert_output_contains "what \`loop.sh\` would exit 2 on"
}

@test "the set of refusals is derived from loop.sh and not retyped" {
  # Both sides derive; only the derivations are compared. A copy of the list in
  # this file would be [28]'s defect one directory further out — and the list has
  # grown by four entries since it was first written.
  run bash "$INIT_SH" --from "$RALPH_PACK_ROOT" --print-refusals
  assert_success
  local derived="$output"

  local expected
  expected="$(grep -oE '^ *[a-z_]+_preflight \|\|' "$RALPH_PACK_ROOT/.claude/loop.sh" |
    sed 's/^ *//; s/ *||$//' | grep -v '^loop_preflight$' | LC_ALL=C sort -u)"

  [ -n "$expected" ] || fail "no refusal found in loop.sh at all"
  assert_equal "$derived" "$expected"
}

# ── idempotence, and the two files a project owns ────────────────────────────

@test "installing twice leaves one block, one config and one set of markers" {
  run_init
  assert_success
  printf '\n# a line a human added\n' >>"$TARGET/.claude/ralph.config.sh"

  run_init
  assert_success

  assert_equal "$(grep -c 'ralph pack ── managed by init.sh' "$TARGET/.gitignore")" "1"
  assert_equal "$(grep -c 'end ralph pack' "$TARGET/.gitignore")" "1"
  assert_equal "$(grep -c 'ralph pack: start' "$TARGET/CLAUDE.md")" "1"
  assert_file_contains "$TARGET/.claude/ralph.config.sh" "a line a human added"
  assert_output_contains "kept the existing .claude/ralph.config.sh"
}

@test "an existing CLAUDE.md is merged and never overwritten" {
  printf '# Acme\n\nOur own rule: never touch vendor/.\n' >"$TARGET/CLAUDE.md"
  run_init
  assert_success
  assert_output_contains "merged a block into the existing CLAUDE.md"

  assert_file_contains "$TARGET/CLAUDE.md" "Our own rule: never touch vendor/."
  assert_file_contains "$TARGET/CLAUDE.md" "The loop marks tickets, never the session"
}

@test "an existing .gitignore keeps its own rules" {
  printf 'dist/\n.env\n' >"$TARGET/.gitignore"
  run_init
  assert_success
  assert_file_contains "$TARGET/.gitignore" "dist/"
  assert_file_contains "$TARGET/.gitignore" ".scratch/*/run.log"
}

@test "a CLAUDE.md that does not exist is created" {
  refute_file_exists "$TARGET/CLAUDE.md"
  run_init
  assert_success
  assert_output_contains "created CLAUDE.md"
  assert_file_contains "$TARGET/CLAUDE.md" "The tracker"
}

# ── what the ignore block decides ────────────────────────────────────────────

@test "the ignore block covers exactly the bookkeeping, and not the artefacts a project keeps" {
  run_init
  assert_success

  # Asked of git rather than read off the block: what matters is what the rule
  # *does* to a path the pack will really write, and a pattern that reads right
  # and matches nothing is the shape of half the defects in this repository.
  local hidden
  for hidden in \
    ".scratch/demo/run.log" \
    ".scratch/demo/.run.lock/pid" \
    ".scratch/demo/.session.4242.jsonl" \
    ".scratch/demo/successor.log" \
    ".scratch/demo/.forge-claims" \
    ".scratch/demo/.forge.guard/pid" \
    "receipts/demo/01-alpha.md"; do
    git -C "$TARGET" check-ignore -q "$hidden" ||
      fail "the installed .gitignore does not cover $hidden"
  done

  # And the other half, which is the decision and not the mechanism: the lesson
  # index and its records are sealed, so committing them is what puts them under
  # guard ([14]); a playthrough is the proof a feature closed.
  local kept
  for kept in \
    "docs/playthroughs/demo.md" \
    "docs/adr/0001-a-decision.md" \
    "LEARNINGS.md" \
    "learning-records/2026-09-14.md"; do
    if git -C "$TARGET" check-ignore -q "$kept"; then
      fail "the installed .gitignore hides $kept, which this project has to be able to commit"
    fi
  done
}

@test "the tracker and the durable directories have a place before the first run" {
  run_init
  assert_success
  local dir
  for dir in ".scratch/demo/issues" "docs/adr" "docs/playthroughs" "receipts"; do
    [ -d "$TARGET/$dir" ] || fail "$dir was not provisioned"
  done
}

# ── the one file whose name belongs to Claude Code ───────────────────────────

@test "a project with no settings.json gets the headless posture" {
  run_init
  assert_success
  assert_file_contains "$TARGET/.claude/settings.json" '"autoCompactEnabled": false'
  assert_file_contains "$TARGET/.claude/settings.json" "DISABLE_AUTO_COMPACT"
}

@test "a project's own settings.json is kept whole, and the posture it lacks is named" {
  # The file every other piece of the deposit is not: the name is Claude Code's,
  # so what is in it is the project's permissions, hooks and MCP servers — and a
  # deposit that replaced it would take all of that away to add two keys.
  mkdir -p "$TARGET/.claude"
  printf '%s\n' '{ "permissions": { "allow": ["Bash(make release)"] } }' \
    >"$TARGET/.claude/settings.json"

  run_init
  assert_success
  assert_file_contains "$TARGET/.claude/settings.json" "Bash(make release)"
  refute_file_contains "$TARGET/.claude/settings.json" "autoCompactEnabled"

  # Kept is not enough: a session that auto-compacts mid-ticket loses the ticket,
  # so the posture it does not have has to be said rather than assumed.
  assert_output_contains "autoCompactEnabled"
  assert_output_contains "DISABLE_AUTO_COMPACT"
}

@test "a project's settings.json that already has the posture is kept without a lecture" {
  mkdir -p "$TARGET/.claude"
  printf '%s\n' '{ "autoCompactEnabled": false, "env": { "DISABLE_AUTO_COMPACT": "1" }, "permissions": { "allow": ["Bash(make release)"] } }' \
    >"$TARGET/.claude/settings.json"

  run_init
  assert_success
  assert_file_contains "$TARGET/.claude/settings.json" "Bash(make release)"
  assert_output_contains "already carries the headless posture"
}

# ── a path with a space in it ────────────────────────────────────────────────

@test "a project whose path holds a space is installed like any other" {
  # [33]'s rule, applied to the installer's own bookkeeping: a list of paths
  # carried as one whitespace-joined line is not a list of paths. A project
  # directory may hold a space, and this is the shape that found the defect.
  local spaced="$RALPH_TEST_DIR/a project/with a name"
  mkdir -p "$spaced"
  git -c init.defaultBranch=main init -q "$spaced"
  git -C "$spaced" config user.name "ralph test"
  git -C "$spaced" config user.email "ralph@test.invalid"
  git -C "$spaced" config commit.gpgsign false
  printf 'a project that existed first\n' >"$spaced/README.md"
  git -C "$spaced" add -A
  git -C "$spaced" commit -q -m "fixture: the project before the pack"

  I_TARGET="$spaced" run_init
  assert_success
  assert_file_exists "$spaced/.claude/loop.sh"
  assert_file_exists "$spaced/.claude/skills/to-tickets/SKILL.md"
  assert_file_contains "$spaced/.gitignore" ".scratch/*/run.log"
  [ -d "$spaced/.scratch/demo/issues" ] || fail "the tracker was not provisioned"

  run env TMPDIR="$TMPDIR" bash "$spaced/.claude/loop.sh"
  assert_failure 5
  assert_output_contains "nothing to grind"
}

# ── the substrate ────────────────────────────────────────────────────────────

@test "the substrate lands as files, never as links into a directory the project has not got" {
  run_init
  assert_success

  # The measured defect of [07]: `cp -R .claude` deposited twenty-two links into
  # `.agents/`, which does not exist at the host, and every one of them arrived
  # dangling.
  local links
  links="$(find "$TARGET/.claude" -type l | wc -l | tr -d ' ')"
  assert_equal "$links" "0"

  assert_file_exists "$TARGET/.claude/skills/to-tickets/SKILL.md"
  assert_file_exists "$TARGET/.claude/skills/implement/SKILL.md"
  # Pinned: the lock the copy was taken at travels with the copy.
  assert_file_exists "$TARGET/.claude/skills-lock.json"
  assert_file_contains "$TARGET/.claude/skills-lock.json" "computedHash"
}

@test "a substrate link that resolves to nothing is refused rather than deposited" {
  local src
  src="$(fake_pack_source)"
  rm -rf "$src/.claude/skills/tdd"
  ln -s "../../.agents/skills/tdd" "$src/.claude/skills/tdd"

  I_FROM="$src" run_init
  assert_failure 2
  assert_output_contains "links that resolve to nothing"
  assert_output_contains "tdd"
  refute_file_exists "$TARGET/.claude/loop.sh"
}

@test "what was deposited is pinned to a version and to the checkout it came from" {
  run_init
  assert_success
  assert_file_exists "$TARGET/.claude/pack.version"
  assert_file_contains "$TARGET/.claude/pack.version" \
    "$(sed -n 's/^ *"version" *: *"\([^"]*\)".*/\1/p' "$RALPH_PACK_ROOT/package.json" | head -1)"
  assert_file_contains "$TARGET/.claude/pack.version" \
    "$(git -C "$RALPH_PACK_ROOT" rev-parse HEAD)"
}

@test "a pack source missing a piece is named as missing, not as a copy that failed" {
  local src
  src="$(fake_pack_source)"
  rm -f "$src/.claude/human-loop.sh"

  I_FROM="$src" run_init
  assert_failure 2
  assert_output_contains "is missing .claude/human-loop.sh"
}

@test "a bootstrap payload missing a piece is caught by what landed" {
  # The one branch where nothing is copied at all: source and destination are the
  # same tree, so a check on the copy has nothing to look at and the only honest
  # question is whether the project has the piece.
  run_init
  assert_success

  local boot="$RALPH_TEST_DIR/half-bootstrapped"
  cp -R "$TARGET" "$boot"
  cp "$INIT_SH" "$boot/init.sh"
  rm -f "$boot/.claude/skills-lock.json" "$boot/.claude/ralph.config.sh"

  run env \
    FEATURE=demo TEST_CMD="stub-cmd tests" TYPECHECK_CMD=none LANG_ARTIFACT=en \
    LANG_CHECK=on SCHEDULER=none VISUAL_REAL_ASSETS=1 RUN_CMD="stub-cmd run" \
    VISUAL_CMD="stub-cmd visual" WORKTREE_PROVISION= \
    bash "$boot/init.sh" --yes --no-sweep --target "$boot"
  assert_failure 2
  assert_output_contains "is not in the project after the deposit"
}

# ── the config ───────────────────────────────────────────────────────────────

@test "the config carries the answers and an exported value still wins over the file" {
  run_init
  assert_success

  # The example's whole contract: `KEY="${KEY:-default}"`, so a run is scriptable
  # from its environment — a CI, a test, the one-shot successor of [09]. A flat
  # assignment would read the same in the file and take that away.
  run env -i "$(command -v bash)" -c '. "$1"; printf "%s|%s\n" "$FEATURE" "$TEST_CMD"' \
    _ "$TARGET/.claude/ralph.config.sh"
  assert_success
  assert_output_contains "demo|stub-cmd tests"

  run env -i FEATURE=elsewhere "$(command -v bash)" -c '. "$1"; printf "%s\n" "$FEATURE"' \
    _ "$TARGET/.claude/ralph.config.sh"
  assert_success
  assert_output_contains "elsewhere"
}

@test "an answer carrying a quote and a brace arrives in the config as it was typed" {
  I_TEST_CMD="awk '{print}' && it's fine" run_init
  assert_success

  run env -i "$(command -v bash)" -c '. "$1"; printf "%s\n" "$TEST_CMD"' \
    _ "$TARGET/.claude/ralph.config.sh"
  assert_success
  assert_equal "$output" "awk '{print}' && it's fine"
}

@test "the config written for a project declares the same keys as the example, both ways" {
  run_init
  assert_success

  # The third copy of the configuration surface. `test/smoke.bats` holds the
  # example against its own list in both directions; this holds what a project
  # actually installs against the example, in both directions too — a key the
  # installer dropped on the way is a key that falls back to a default nobody
  # chose, and a key it invented is a key nobody reads inside a file that reads
  # like a contract.
  local written declared
  written="$(sed -n 's/^\([A-Z_][A-Z0-9_]*\)=.*/\1/p' \
    "$TARGET/.claude/ralph.config.sh" | LC_ALL=C sort -u)"
  declared="$(sed -n 's/^\([A-Z_][A-Z0-9_]*\)=.*/\1/p' \
    "$TARGET/.claude/ralph.config.sh.example" | LC_ALL=C sort -u)"
  assert_equal "$written" "$declared"
}

# ── the forced confirmations ─────────────────────────────────────────────────

@test "a forced confirmation that was not given stops the install before it writes anything" {
  run env FEATURE=demo TEST_CMD="stub-cmd tests" \
    bash "$INIT_SH" --yes --no-sweep --target "$TARGET" --from "$RALPH_PACK_ROOT"
  assert_failure 3
  assert_output_contains "TYPECHECK_CMD"
  assert_output_contains "LANG_CHECK"
  assert_output_contains "VISUAL_REAL_ASSETS"
  assert_output_contains "WORKTREE_PROVISION"
  refute_file_exists "$TARGET/.claude/loop.sh"
  refute_file_exists "$TARGET/CLAUDE.md"
}

@test "a TEST_CMD that is a no-op is refused, and the refusal says what it does not catch" {
  I_TEST_CMD="true" run_init
  assert_failure 3
  assert_output_contains "which is a no-op"
  assert_output_contains "catches the spelling and not the property"
  refute_file_exists "$TARGET/.claude/loop.sh"
}

@test "a GUARDED_PATHS written wide is refused: it would commit the whole ignored zone" {
  run env \
    FEATURE=demo TEST_CMD="stub-cmd tests" TYPECHECK_CMD=none LANG_ARTIFACT=en \
    LANG_CHECK=on SCHEDULER=none VISUAL_REAL_ASSETS=1 RUN_CMD="stub-cmd run" \
    VISUAL_CMD="stub-cmd visual" WORKTREE_PROVISION= GUARDED_PATHS=. \
    bash "$INIT_SH" --yes --no-sweep --target "$TARGET" --from "$RALPH_PACK_ROOT"
  assert_failure 3
  assert_output_contains "GUARDED_PATHS"
  assert_output_contains "would enter this project's history"
}

@test "a remote backend is not presented as an equivalent option with another name" {
  run env \
    FEATURE=demo TEST_CMD="stub-cmd tests" TYPECHECK_CMD=none LANG_ARTIFACT=en \
    LANG_CHECK=on SCHEDULER=none VISUAL_REAL_ASSETS=1 RUN_CMD="stub-cmd run" \
    VISUAL_CMD="stub-cmd visual" WORKTREE_PROVISION= TRACKER_BACKEND=github \
    bash "$INIT_SH" --yes --no-sweep --target "$TARGET" --from "$RALPH_PACK_ROOT"
  assert_success
  assert_output_contains "nothing in this pack attests its provenance"
  assert_output_contains "ci-unreachable"
}

# ── what a tree has to be before any of this ─────────────────────────────────

@test "a target that is not a git repository is told so, and not told a run holds it" {
  mkdir -p "$RALPH_TEST_DIR/bare"
  I_TARGET="$RALPH_TEST_DIR/bare" run_init
  assert_failure 2
  assert_output_contains "is not a git repository"
  # The diagnosis the ordering exists for: the tree lock lives in the git
  # directory, so a lock taken first fails for want of one and blames a run that
  # has never existed here.
  refute_output_contains "a run holds this working tree"
}

@test "a repository with no commit is refused, because a worktree cannot be made out of nothing" {
  mkdir -p "$RALPH_TEST_DIR/fresh"
  git -c init.defaultBranch=main init -q "$RALPH_TEST_DIR/fresh"
  I_TARGET="$RALPH_TEST_DIR/fresh" run_init
  assert_failure 2
  assert_output_contains "has no commit yet"
}

@test "an install refuses while a run holds this working tree, and writes nothing" {
  # A live owner: this very test process, which the guard's `kill -0` can see.
  mkdir -p "$TARGET/.git/ralph.tree.lock"
  printf '%s\n' "$$" >"$TARGET/.git/ralph.tree.lock/pid"

  run_init
  assert_failure 1
  assert_output_contains "a run holds this working tree"
  refute_file_exists "$TARGET/.claude/loop.sh"
  refute_file_exists "$TARGET/.gitignore"
}

@test "the pack's own repository is refused as a destination" {
  run bash "$INIT_SH" --yes --no-sweep \
    --target "$RALPH_PACK_ROOT" --from "$RALPH_PACK_ROOT"
  assert_failure 2
  assert_output_contains "the pack's own repository"
  # The footgun this guard exists for, checked rather than described.
  assert_file_exists "$RALPH_PACK_ROOT/init.sh"
}

# ── the bootstrap copy ───────────────────────────────────────────────────────

@test "the bootstrap copy removes itself, and a copy run from the pack does not" {
  # Flow one: run from a checkout, installing elsewhere. Nothing is deleted —
  # removing the source's own init.sh would be a bootstrap that breaks the next.
  #
  # Through a *copy* of the pack and not through this repository, so that the
  # mutation which removes the guard deletes a throwaway and not the file the
  # suite is testing. A restore would put the bytes back and not the exec bit.
  local src
  src="$(fake_pack_source)"
  cp "$INIT_SH" "$src/init.sh"
  I_FROM="$src" I_INIT="$src/init.sh" run_init
  assert_success
  assert_file_exists "$src/init.sh"
  refute_output_contains "has nothing left to do here"

  # Flow two: the payload and the script travelled into the project together,
  # which is what the `npx` wizard leaves behind.
  local boot="$RALPH_TEST_DIR/bootstrapped"
  cp -R "$TARGET" "$boot"
  rm -rf "$boot/.claude/ralph.config.sh" "$boot/CLAUDE.md" "$boot/.gitignore"
  cp "$INIT_SH" "$boot/init.sh"
  cp "$RALPH_PACK_ROOT/package.json" "$boot/package.json"

  # Run through the copy that is standing in the project, which is the whole
  # question: `run_init` would start the pack's own script and prove nothing.
  run env \
    FEATURE=demo TEST_CMD="stub-cmd tests" TYPECHECK_CMD=none LANG_ARTIFACT=en \
    LANG_CHECK=on SCHEDULER=none VISUAL_REAL_ASSETS=1 RUN_CMD="stub-cmd run" \
    VISUAL_CMD="stub-cmd visual" WORKTREE_PROVISION= \
    bash "$boot/init.sh" --yes --no-sweep --target "$boot"
  assert_success
  assert_output_contains "has nothing left to do here"
  refute_file_exists "$boot/init.sh"
  assert_file_exists "$boot/.claude/loop.sh"
  assert_file_exists "$boot/CLAUDE.md"
}

# ── the sweep ────────────────────────────────────────────────────────────────

sweep_tmp() {
  SWEEP_TMP="$RALPH_TEST_DIR/sweep-tmp"
  mkdir -p "$SWEEP_TMP"
  printf '%s\n' "$SWEEP_TMP"
}

run_sweep() {
  run env TMPDIR="$SWEEP_TMP" FEATURE=demo \
    bash "$INIT_SH" sweep --target "$TARGET" --from "$RALPH_PACK_ROOT" "$@"
}

@test "the sweep takes what gate_tmp_names names, and leaves the harness's own namespace alone" {
  run_init
  assert_success
  sweep_tmp >/dev/null

  # Derived from the pack, not retyped: one stale directory per name the pack
  # publishes, and the sweep has to take every one of them.
  local name stale
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    stale="$SWEEP_TMP/${name%\*}stale"
    mkdir -p "$stale"
    touch -t 202001010000 "$stale"
  done <<NAMES
$(env TMPDIR="$SWEEP_TMP" bash -c '. "$1"; gate_tmp_names' _ "$RALPH_PACK_ROOT/.claude/lib/gate.sh")
NAMES

  # Two that must survive, and they are the reason `ralph-*` was refused as a
  # pattern: the suite's own template cache is kept seven days on purpose, and a
  # run of another repository legitimately owns a brand-new gate directory.
  mkdir -p "$SWEEP_TMP/ralph-harness.1234" "$SWEEP_TMP/ralph-test.1234"
  touch -t 202001010000 "$SWEEP_TMP/ralph-harness.1234" "$SWEEP_TMP/ralph-test.1234"
  mkdir -p "$SWEEP_TMP/ralph-gate.fresh"

  run_sweep
  assert_success

  while IFS= read -r name; do
    [ -n "$name" ] || continue
    stale="$SWEEP_TMP/${name%\*}stale"
    if [ -e "$stale" ]; then
      fail "the sweep left $stale, which $name names"
    fi
  done <<NAMES
$(env TMPDIR="$SWEEP_TMP" bash -c '. "$1"; gate_tmp_names' _ "$RALPH_PACK_ROOT/.claude/lib/gate.sh")
NAMES

  [ -d "$SWEEP_TMP/ralph-harness.1234" ] ||
    fail "the sweep took the suite's template cache, which is kept seven days on purpose"
  [ -d "$SWEEP_TMP/ralph-test.1234" ] ||
    fail "the sweep took a ralph-test.* of the pack's own harness"
  [ -d "$SWEEP_TMP/ralph-gate.fresh" ] ||
    fail "the sweep took a gate directory another repository's run may still own"
  assert_output_contains "ralph-test.*, ralph-harness.*"
}

@test "the sweep names what it found in the same words the two entry points use" {
  run_init
  assert_success
  sweep_tmp >/dev/null
  mkdir -p "$SWEEP_TMP/ralph-gate.stale"
  touch -t 202001010000 "$SWEEP_TMP/ralph-gate.stale"

  run_sweep
  assert_success
  # `gate_leftovers`' own sentence, which `loop.sh` and `human-loop.sh` both
  # print. Two truths about one disk is what a sweeper of its own invention would
  # produce ([69]).
  assert_output_contains "from earlier runs are still in"
  assert_output_contains "exclusion guards"
}

@test "the sweep removes a successor marker whose instant has passed and keeps one that has not" {
  run_init
  assert_success
  sweep_tmp >/dev/null
  local marker="$TARGET/.git/ralph.successor"

  printf '%s\t%s\t%s\n' "1" "at" "long ago" >"$marker"
  run_sweep
  assert_success
  refute_file_exists "$marker"

  printf '%s\t%s\t%s\n' "$(($(date +%s) + 86400))" "at" "tomorrow" >"$marker"
  run_sweep
  assert_success
  assert_file_exists "$marker"
}

@test "the sweep prunes the worktree registrations a killed run left in the git directory" {
  run_init
  assert_success
  sweep_tmp >/dev/null

  git -C "$TARGET" worktree add --detach -q "$RALPH_TEST_DIR/gone" HEAD
  rm -rf "$RALPH_TEST_DIR/gone"
  git -C "$TARGET" worktree list --porcelain | grep -q "$RALPH_TEST_DIR/gone" ||
    fail "the fixture did not leave a registration to prune"

  run_sweep
  assert_success
  run git -C "$TARGET" worktree list --porcelain
  refute_output_contains "$RALPH_TEST_DIR/gone"
}

@test "the sweep refuses while a run holds this working tree" {
  run_init
  assert_success
  sweep_tmp >/dev/null
  mkdir -p "$SWEEP_TMP/ralph-gate.stale"
  touch -t 202001010000 "$SWEEP_TMP/ralph-gate.stale"

  mkdir -p "$TARGET/.git/ralph.tree.lock"
  printf '%s\n' "$$" >"$TARGET/.git/ralph.tree.lock/pid"

  run_sweep
  assert_failure 1
  [ -d "$SWEEP_TMP/ralph-gate.stale" ] ||
    fail "the sweep swept while a run held the tree"
}

# ── the shape of the two halves of the front door ────────────────────────────

@test "the installer puts no temporary at the top level of TMPDIR" {
  # [62]'s trap, and it is this ticket's alone: the derivation that keeps
  # `gate_tmp_names` honest scans `.claude/**`, and this file is outside it. A
  # `mktemp "$TMPDIR/ralph-install.XXXX"` here would be counted by no control and
  # reported by no derivation. So there is none, and that is checked rather than
  # remembered.
  run bash -c 'grep -n "mktemp" "$1" | grep -v ":[[:space:]]*#"' _ "$INIT_SH"
  assert_failure
}

@test "the node wrapper execs the bash engine and carries no decisions of its own" {
  local wrapper="$RALPH_PACK_ROOT/bin/ralph-init.js"
  assert_file_exists "$wrapper"
  assert_file_contains "$wrapper" "init.sh"
  assert_file_contains "$wrapper" "spawnSync"

  # A front door that decided anything would be a second installer, and the bash
  # fallback would not have whatever it decided. Nothing may write, copy or
  # prompt on this side of the seam.
  local word
  for word in writeFileSync mkdirSync copyFileSync appendFileSync readline; do
    if grep -q "$word" "$wrapper"; then
      fail "the npx wrapper uses $word: the engine is bash, and a machine without node has to install the same way"
    fi
  done
}

@test "the package ships every source the deposit names" {
  run bash "$INIT_SH" --from "$RALPH_PACK_ROOT" --print-payload
  assert_success
  local payload="$output"

  local src covered entry
  while IFS="$(printf '\t')" read -r src _; do
    [ -n "$src" ] || continue
    covered=no
    while IFS= read -r entry; do
      case "$src/" in
        "$entry"*) covered=yes ;;
      esac
      [ "$src" = "$entry" ] && covered=yes
    done <<FILES
$(sed -n 's/^ *"\([^"]*\)",*$/\1/p' "$RALPH_PACK_ROOT/package.json")
FILES
    [ "$covered" = yes ] ||
      fail "the deposit needs $src and package.json does not ship it"
  done <<PAYLOAD
$payload
PAYLOAD

  # The substrate is symlinks in this repository, so the package has to carry the
  # directory they point into or `npx` would publish twenty-two dangling names.
  assert_file_contains "$RALPH_PACK_ROOT/package.json" ".agents/skills/"
}

@test "the engine names no node, npm or npx" {
  # The suite already runs with all three shadowed by a hard failure, so every
  # install above is the proof by exercise. This is the proof by reading, and it
  # is the one that catches a call added on a path no test walks.
  # A command position — start of a line, or after a `;`, `|`, `&&` or `$(` —
  # and not the word in a sentence: the note about `npm run` putting a directory
  # on PATH is prose this file is allowed to carry.
  run bash -c 'grep -nE "(^|[;&|(])[[:space:]]*(node|npm|npx)[[:space:]]" "$1" |
    grep -v ":[[:space:]]*#"' _ "$INIT_SH"
  assert_failure
}
