#!/usr/bin/env bats
#
# Typed failures: what the loop does with an iteration that did not deliver.
#
# Four kinds, four answers — a slice too big gets cut up, a scoping conflict goes
# straight to the human, a red gate or a dead session gets fresh retries — and
# one thing they all share: the repository goes back to where the session found
# it, and nothing the gate already approved is ever taken away.

load helpers/harness
load helpers/assert

setup() {
  harness_setup
}

teardown() {
  harness_teardown
}

# A session that writes the given files, relative to the project root, then
# reports success.
script_session_writing() {
  local target
  {
    printf '#!/usr/bin/env bash\n'
    for target in "$@"; do
      printf 'mkdir -p "$(dirname %s)" && printf "written\\n" >>%s\n' "$target" "$target"
    done
    printf '%s\n' \
      "echo '{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"num_turns\":1,\"total_cost_usd\":0.02}'"
  } | script_claude
}

# What the run left uncommitted, the loop's own tracker aside.
worktree_dirt() {
  git -C "$PROJECT_DIR" status --porcelain | grep -v '\.scratch/' || true
}

git_subjects() {
  git -C "$PROJECT_DIR" log --format='%s'
}

# A session that writes exactly what its own ticket declared, whichever ticket
# it is handed — so a run of several iterations stays inside every surface.
script_honest_session() {
  script_claude <<'FAKE'
#!/usr/bin/env bash
surface="$(cat | sed -n 's/^\*\*Write-surface:\*\* //p' | head -1 | tr -d '`\r' | tr ',' ' ')"
for target in $surface; do
  mkdir -p "$(dirname "$target")" && printf 'written\n' >"$target"
done
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE
}

# The first session runs out of context — it reports a context far over the limit
# and keeps going, so the smart-zone net has to stop it — and every session after
# it runs the script given on stdin, with the prompt in $prompt and the call
# number in $n. That first call is what the loop reads as "this slice is too big".
script_too_big_then() {
  {
    cat <<'HEAD'
#!/usr/bin/env bash
prompt="$(cat)"
n="$(cat "$RALPH_SHIM_STATE/seq" 2>/dev/null || echo 0)"
n=$((n + 1)); printf '%s\n' "$n" >"$RALPH_SHIM_STATE/seq"
if [ "$n" = 1 ]; then
  echo '{"type":"system","subtype":"init","session_id":"s"}'
  echo '{"type":"assistant","message":{"role":"assistant","usage":{"input_tokens":10,"cache_read_input_tokens":9000,"output_tokens":5}}}'
  i=0
  while [ $i -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
  exit 0
fi
HEAD
    cat
  } | script_claude
}

# ── retry, then the human sink ───────────────────────────────────────────────

@test "a red gate buys fresh retries before anybody is escalated" {
  use_tickets 01-alpha
  set_config RETRY_N 2
  set_config STERILE_K 5
  stub_exit tests 1

  run_loop
  # Exit 0: three attempts, then nothing left on the frontier to grind.
  assert_success
  assert_output_contains "01-alpha: gate-red -> fresh retry (1 of 2)"
  assert_output_contains "01-alpha: gate-red -> fresh retry (2 of 2)"
  assert_output_contains "escalated to the human sink (failed-impl)"

  # Every retry is a session of its own: nothing is resumed.
  assert_equal "$(claude_call_count)" "3"
  assert_ticket_status 01-alpha ready-for-human
  assert_equal "$(ticket_field 01-alpha Failures)" "3"
  assert_equal "$(ticket_field 01-alpha Escalation)" "failed-impl"
  run ticket_has_field 01-alpha Claimed
  assert_failure
}

@test "the retry budget is the configured one, not a number in the code" {
  use_tickets 01-alpha
  set_config RETRY_N 0
  set_config STERILE_K 5
  stub_exit tests 1

  run_loop
  assert_success
  assert_equal "$(claude_call_count)" "1"
  assert_ticket_status 01-alpha ready-for-human
  assert_equal "$(ticket_field 01-alpha Failures)" "1"
}

@test "a dead session is retried too, and journalled apart from a red gate" {
  use_tickets 01-alpha
  set_config RETRY_N 1
  set_config STERILE_K 5

  script_claude <<'FAKE'
#!/usr/bin/env bash
echo '{"type":"result","subtype":"error_during_execution","is_error":true}'
exit 1
FAKE

  run_loop
  assert_success
  assert_output_contains "01-alpha: crash -> fresh retry (1 of 1)"
  assert_equal "$(claude_call_count)" "2"
  assert_ticket_status 01-alpha ready-for-human
  assert_file_contains "$FEATURE_DIR/run.log" "failed"
}

# ── a scoping conflict is not an attempt to retry ────────────────────────────

@test "a contractual overflow escalates at once, without spending a retry" {
  use_tickets 01-alpha 02-beta
  set_config STERILE_K 5
  script_session_writing src/beta.txt

  run_loop
  assert_success
  assert_output_contains "scope overflow on 01-alpha: contract"
  assert_output_contains "escalated to the human sink (decision)"

  assert_ticket_status 01-alpha ready-for-human
  assert_equal "$(ticket_field 01-alpha Escalation)" "decision"
  # No retry burned: the counter was never touched.
  run ticket_has_field 01-alpha Failures
  assert_failure

  # One attempt on it, and the run carries on with the rest of the frontier.
  assert_equal "$(claude_call_count)" "2"
  assert_ticket_status 02-beta resolved
}

@test "the classification table, as the budget classifier will find it" {
  pack_run '
    failures_classify over-soft-limit
    failures_classify gate-red contract
    failures_classify gate-red internal
    failures_classify gate-red
    failures_classify failed
    failures_classify over-soft-limit contract'
  assert_success
  assert_equal "$output" "too-big
contract
gate-red
gate-red
crash
too-big"
}

# ── rollback ─────────────────────────────────────────────────────────────────

@test "a stray write is undone: the next session inherits none of the attempt" {
  use_tickets 01-alpha
  set_config STERILE_K 1

  # Staged but not committed, which is what an agent interrupted mid-commit
  # leaves. Undoing the files without unstaging them would leave the attempt
  # sitting in the index, ready to ride along with the next commit.
  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src
printf 'written\n' >src/alpha.txt
printf 'written\n' >src/rogue.txt
git add -A
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_failure 4
  assert_output_contains "rolled back 2 path(s) the session touched"

  # The whole attempt, not just the part that broke the gate.
  refute_file_exists "$PROJECT_DIR/src/rogue.txt"
  refute_file_exists "$PROJECT_DIR/src/alpha.txt"
  assert_equal "$(worktree_dirt)" ""
}

@test "a commit the session made does not survive its own red gate" {
  use_tickets 01-alpha
  set_config STERILE_K 1

  # Work in progress the run inherited, and never touched: it is on the way of a
  # `git reset --hard` plus `git clean -fd`, which is what the obvious rollback
  # of a session that committed would be.
  printf 'mine\n' >"$PROJECT_DIR/wip.txt"
  printf 'edited by a human\n' >>"$PROJECT_DIR/CONTEXT.md"

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src
printf 'written\n' >src/alpha.txt
printf 'written\n' >rogue.txt
git add -A
git commit -q -m "session: work"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_failure 4
  assert_output_contains "rolled back the commit the session made"

  run git_subjects
  refute_output_contains "session: work"
  refute_file_exists "$PROJECT_DIR/rogue.txt"
  refute_file_exists "$PROJECT_DIR/src/alpha.txt"

  # The commit is gone and what it committed of somebody else's work is back
  # where it was: uncommitted, and still there.
  assert_file_contains "$PROJECT_DIR/wip.txt" "mine"
  assert_file_contains "$PROJECT_DIR/CONTEXT.md" "edited by a human"
  run bash -c "git -C '$PROJECT_DIR' status --porcelain | grep -v '\.scratch/'"
  assert_output_contains "?? wip.txt"
  assert_output_contains "M CONTEXT.md"

  # The tracker was committed mid-claim by that same session. Rolling the commit
  # back must not roll the loop's own marking back with it.
  assert_ticket_status 01-alpha ready-for-agent
}

@test "a rollback is not a reset --hard: work nobody in this run made stands" {
  use_tickets 01-alpha
  set_config STERILE_K 1

  # Someone's work in progress: an untracked file and an uncommitted edit. A
  # blanket `git reset --hard` plus `git clean -fd` would delete both.
  mkdir -p "$PROJECT_DIR/src"
  printf 'mine\n' >"$PROJECT_DIR/wip.txt"
  printf 'edited by a human\n' >>"$PROJECT_DIR/CONTEXT.md"

  script_session_writing src/alpha.txt src/rogue.txt

  run_loop
  assert_failure 4

  assert_file_contains "$PROJECT_DIR/wip.txt" "mine"
  assert_file_contains "$PROJECT_DIR/CONTEXT.md" "edited by a human"
  refute_file_exists "$PROJECT_DIR/src/rogue.txt"
}

@test "a file the session deleted comes back" {
  use_tickets 01-alpha
  set_config STERILE_K 1

  script_claude <<'FAKE'
#!/usr/bin/env bash
rm -f CONTEXT.md
printf 'written\n' >rogue.txt
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_failure 4
  assert_file_contains "$PROJECT_DIR/CONTEXT.md" "Fixture context for the harness"
  assert_equal "$(worktree_dirt)" ""
}

@test "a rollback never restores the tracker, whatever moved in it" {
  use_tickets 01-alpha

  # Driven directly, because the loop takes its post-session snapshot before it
  # writes the retry counter: at the process seam the tracker never even shows up
  # in the rollback's diff, so the exclusion looks free until the day something
  # writes the tracker earlier. What it protects is that counter — restore the
  # ticket from the pre-session snapshot and `Failures:` goes back to nothing,
  # which means no ticket is ever escalated again.
  pack_run '
    base="$(gate_tree_snapshot)"
    printf "stray\n" >stray.txt
    tracker_bump_failures 01-alpha >/dev/null
    tree="$(gate_tree_snapshot)"
    failures_rollback "" "$base" "$tree" >/dev/null
    printf "stray=%s failures=%s\n" \
      "$([ -f stray.txt ] && echo yes || echo no)" \
      "$(tracker_field 01-alpha Failures)"'
  assert_success
  assert_equal "$output" "stray=no failures=1"
}

# ── the attempt is kept ──────────────────────────────────────────────────────

@test "before the escalation, a branch keeps the attempt the human will read" {
  use_tickets 01-alpha
  set_config RETRY_N 0
  set_config STERILE_K 1
  script_session_writing src/alpha.txt src/rogue.txt

  run_loop
  assert_failure 4
  assert_output_contains "the attempt is kept on branch failed/01-alpha"

  run git -C "$PROJECT_DIR" show "failed/01-alpha:src/rogue.txt"
  assert_success
  assert_output_contains "written"

  # A forensic artefact, not a snapshot of the loop's own bookkeeping.
  run git -C "$PROJECT_DIR" ls-tree -r --name-only "failed/01-alpha"
  refute_output_contains ".scratch/"

  # And the branch is the only place it survives.
  refute_file_exists "$PROJECT_DIR/src/rogue.txt"
}

# ── a green iteration is durable ─────────────────────────────────────────────

@test "what a green gate approved is committed, and nothing else is" {
  use_tickets 01-alpha 02-beta

  script_claude <<'FAKE'
#!/usr/bin/env bash
n="$(cat "$RALPH_SHIM_STATE/seq" 2>/dev/null || echo 0)"
n=$((n + 1)); echo "$n" >"$RALPH_SHIM_STATE/seq"
mkdir -p src
case "$n" in
  1) printf 'written\n' >src/alpha.txt ;;
  2) printf 'written\n' >src/beta.txt ;;
esac
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_success

  run git_subjects
  assert_output_contains "01-alpha: iteration delivered (gate green)"
  assert_output_contains "02-beta: iteration delivered (gate green)"

  run git -C "$PROJECT_DIR" show --stat --format= HEAD
  assert_output_contains "src/beta.txt"
  refute_output_contains "src/alpha.txt"
  refute_output_contains ".scratch/"

  # Nothing of the two iterations is left uncommitted.
  assert_equal "$(worktree_dirt)" ""
}

@test "a later rollback never takes away what an earlier gate had approved" {
  use_tickets 01-alpha 02-beta
  set_config STERILE_K 1

  script_claude <<'FAKE'
#!/usr/bin/env bash
n="$(cat "$RALPH_SHIM_STATE/seq" 2>/dev/null || echo 0)"
n=$((n + 1)); echo "$n" >"$RALPH_SHIM_STATE/seq"
mkdir -p src
case "$n" in
  1) printf 'written\n' >src/alpha.txt ;;
  2) printf 'written\n' >src/beta.txt; printf 'written\n' >src/rogue.txt ;;
esac
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_failure 4

  assert_ticket_status 01-alpha resolved
  assert_file_contains "$PROJECT_DIR/src/alpha.txt" "written"

  # Still in the tree is not the guarantee — being committed is. Uncommitted, it
  # would be at the mercy of the next iteration's rollback.
  run git -C "$PROJECT_DIR" log --oneline -- src/alpha.txt
  assert_output_contains "01-alpha"

  refute_file_exists "$PROJECT_DIR/src/beta.txt"
  refute_file_exists "$PROJECT_DIR/src/rogue.txt"
}

@test "a commit the session made does not survive its own green gate either" {
  # The asymmetry that was left: on a red gate the rollback moves HEAD back, on a
  # green one nothing did. So a session that ran `git add -A && git commit` — the
  # ordinary reflex of an agent told to finish its work — put the loop's own state
  # into the target project's history: the ticket frozen mid-claim at `claimed`, a
  # state that was never true, next to the run journal and a session stream that
  # can run to tens of megabytes.
  use_tickets 01-alpha

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src
printf 'written\n' >src/alpha.txt
git add -A >/dev/null 2>&1
git commit -q -m "session: committed everything I could see" >/dev/null 2>&1
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  # Where the project's history stood before the run: the tracker is committed by
  # the harness, like a real project would, so only what the run added is at issue.
  before="$(git -C "$PROJECT_DIR" rev-parse HEAD)"

  run_loop
  assert_success
  assert_ticket_status 01-alpha resolved

  # The work is durable, and it is the loop's commit that carries it.
  run git_subjects
  assert_output_contains "01-alpha: iteration delivered (gate green)"
  refute_output_contains "session: committed everything"

  # And nothing of the loop's own state went with it, ever — not on this commit
  # and not anywhere in the history the run produced.
  run git -C "$PROJECT_DIR" show --stat --format= HEAD
  assert_output_contains "src/alpha.txt"
  refute_output_contains ".scratch/"

  run git -C "$PROJECT_DIR" log --format='%s' --name-only "$before..HEAD" -- .scratch
  assert_equal "$output" ""
}

# ── a slice too big for one session ──────────────────────────────────────────

# The ticket used here declares two files, so a split can hand one to each of
# two smaller tickets without inventing a surface nobody granted.
#
# Call 2 is the planning session: it reads the plan path out of its own prompt and
# writes the split there. Every call after that is an honest delivery session
# writing what its ticket declared.
script_reslice_world() {
  script_too_big_then <<'FAKE'
if [ "$n" = 2 ]; then
    plan="$(printf '%s' "$prompt" | sed -n 's/^Write the plan to \([^,]*\),.*/\1/p' | head -1)"
    printf '%s' "$plan" >"$RALPH_SHIM_STATE/plan-path"
    cat >"$plan" <<'PLAN'
--- ticket: alpha-half | The alpha half ---
**What to build:** The first half of what was too big.

**Blocked by:** None

**Write-surface:** `src/alpha.txt`

**Status:** ready-for-agent

- [ ] the alpha half exists
--- ticket: eta-half | The eta half ---
**What to build:** The second half of what was too big.

**Blocked by:** None

**Write-surface:** `src/eta.txt`

**Status:** ready-for-agent

- [ ] the eta half exists
PLAN
    echo '{"type":"result","subtype":"success","is_error":false,"num_turns":2,"total_cost_usd":0.01}'
    exit 0
fi

surface="$(printf '%s' "$prompt" |
  sed -n 's/^\*\*Write-surface:\*\* //p' | head -1 | tr -d '`\r' | tr ',' ' ')"
for target in $surface; do
  mkdir -p "$(dirname "$target")" && printf 'written\n' >"$target"
done
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":3,"total_cost_usd":0.02}'
FAKE
}

@test "a slice too big for one session is cut up, and the pieces get ground" {
  use_tickets 07-overlaps-alpha
  set_config SOFT_LIMIT_TOKENS 5000
  set_config STERILE_K 5
  script_reslice_world

  run_loop
  assert_success
  assert_output_contains "07-overlaps-alpha: too big -> re-sliced into 08-alpha-half 09-eta-half"

  # The pieces were created by the loop, on the frontier, and ground.
  assert_ticket_status 08-alpha-half resolved
  assert_ticket_status 09-eta-half resolved
  assert_file_contains "$PROJECT_DIR/src/alpha.txt" "written"
  assert_file_contains "$PROJECT_DIR/src/eta.txt" "written"
  assert_file_contains "$(ticket_file 08-alpha-half)" "- [ ] the alpha half exists"
  assert_file_contains "$(ticket_file 08-alpha-half)" "Re-sliced out of 07-overlaps-alpha"

  # The ticket that was too big waited for them, then earned its own green gate.
  assert_file_contains "$(ticket_file 07-overlaps-alpha)" "Re-sliced into: 08-alpha-half, 09-eta-half"
  assert_ticket_status 07-overlaps-alpha resolved

  # The plan was written outside the repository, and the planning session never
  # became an iteration of its own.
  refute_output_contains "iteration 2: 07-overlaps-alpha"
  run bash -c "ls '$PROJECT_DIR'"
  refute_output_contains "plan"
}

@test "the planning session is fresh, and told where the plan goes" {
  use_tickets 07-overlaps-alpha
  set_config SOFT_LIMIT_TOKENS 5000
  set_config STERILE_K 1
  script_reslice_world

  run_loop

  run claude_call_stdin 2
  assert_output_contains "split it into smaller tickets"
  assert_output_contains "# 07 — Overlaps alpha"
  assert_output_contains "gains a second line"
  assert_output_contains "--- ticket: <slug> | <title> ---"

  run claude_call_argv 2
  refute_output_contains "--continue"
  refute_output_contains "--resume"

  # Written where the loop said, which is not inside the repository.
  run cat "$SHIM_STATE/plan-path"
  case "$output" in
    "$PROJECT_DIR"*) fail "the plan was written inside the repository: $output" ;;
  esac
}

@test "a slice nobody can split goes to the human, with the reason said" {
  use_tickets 07-overlaps-alpha
  set_config SOFT_LIMIT_TOKENS 5000
  set_config STERILE_K 1

  # The planner answers, and writes no plan: nothing it can do preserves the
  # acceptance criteria.
  script_too_big_then <<'FAKE'
echo 'No split preserves the acceptance criteria.'
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":2,"total_cost_usd":0.01}'
FAKE

  run_loop
  assert_failure 4
  assert_output_contains "no re-slice plan came back"

  assert_ticket_status 07-overlaps-alpha ready-for-human
  assert_equal "$(ticket_field 07-overlaps-alpha Escalation)" "too-big"
  assert_output_contains "the attempt is kept on branch failed/07-overlaps-alpha"

  # And no ticket was invented on the way.
  run bash -c "ls '$TRACKER_DIR' | awk 'END { print NR }'"
  assert_equal "$output" "1"
}

@test "a split that widens the write-surface is refused whole" {
  use_tickets 07-overlaps-alpha
  set_config SOFT_LIMIT_TOKENS 5000
  set_config STERILE_K 1

  script_too_big_then <<'FAKE'
plan="$(printf '%s' "$prompt" | sed -n 's/^Write the plan to \([^,]*\),.*/\1/p' | head -1)"
cat >"$plan" <<'PLAN'
--- ticket: alpha-half | The alpha half ---
**Write-surface:** `src/alpha.txt`

- [ ] the alpha half exists
--- ticket: land-grab | While we are here ---
**Write-surface:** `src/elsewhere.txt`

- [ ] something the original never declared
PLAN
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":2,"total_cost_usd":0.01}'
FAKE

  run_loop
  assert_failure 4
  assert_output_contains "would write src/elsewhere.txt, outside the write-surface being split"

  assert_ticket_status 07-overlaps-alpha ready-for-human
  assert_equal "$(ticket_field 07-overlaps-alpha Escalation)" "too-big"

  # Refused whole: not even the sound half was created.
  run bash -c "ls '$TRACKER_DIR' | awk 'END { print NR }'"
  assert_equal "$output" "1"
}

@test "a plan that splits nothing is not a split" {
  use_tickets 07-overlaps-alpha
  set_config SOFT_LIMIT_TOKENS 5000
  set_config STERILE_K 1

  script_too_big_then <<'FAKE'
plan="$(printf '%s' "$prompt" | sed -n 's/^Write the plan to \([^,]*\),.*/\1/p' | head -1)"
cat >"$plan" <<'PLAN'
--- ticket: the-same-thing | The whole thing, again ---
**Write-surface:** `src/alpha.txt`, `src/eta.txt`

- [ ] everything the original asked for
PLAN
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":2,"total_cost_usd":0.01}'
FAKE

  run_loop
  assert_failure 4
  assert_output_contains "the plan does not split anything (1 ticket(s))"

  assert_ticket_status 07-overlaps-alpha ready-for-human
  run bash -c "ls '$TRACKER_DIR' | awk 'END { print NR }'"
  assert_equal "$output" "1"
}

# ── a session that writes the tracker itself ─────────────────────────────────
#
# The one write nothing else catches: the scope-guard drops `.scratch/<feature>/`
# as the loop's own bookkeeping and the rollback leaves it alone, so what a
# session writes there used to survive the iteration. Two shapes, two answers —
# a ticket it created is quarantined for a human, a ticket it edited is restored
# from the snapshot taken at spawn time, before the gate reads a single field.

@test "an edited ticket is put back, and the iteration pays for the edit" {
  # The canary drives the exploit — a surface widened to `*` — and a red
  # scope-guard is enough to make it fail there. This one takes the exploit away:
  # the session writes nothing but the file its ticket declared, so every gate
  # branch is green and the edited tracker is the only thing wrong with it.
  use_tickets 01-alpha
  set_config STERILE_K 1

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src
printf 'written\n' >src/alpha.txt
printf '\n- [ ] and one criterion the discovery never wrote\n' \
  >>.scratch/demo/issues/01-alpha.md
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_failure 4
  assert_output_contains "the session edited the tracker — restored 1 ticket file(s)"

  # Green branches, and no green iteration.
  assert_output_contains "tests=green typecheck=green scope=green"
  assert_ticket_status 01-alpha ready-for-agent
  assert_equal "$(ticket_field 01-alpha Failures)" "1"
  refute_file_contains "$(ticket_file 01-alpha)" "the discovery never wrote"

  # Reported as itself rather than folded into a red gate: the branches were all
  # green, and a receipt that said `gate-red` would send a human looking at tests.
  assert_file_contains "$FEATURE_DIR/run.log" "tracker-write"
  run bash -c "grep -c resolved '$FEATURE_DIR/run.log' || true"
  assert_equal "$output" "0"

  # And the work goes back with the attempt, like any other failed iteration.
  refute_file_exists "$PROJECT_DIR/src/alpha.txt"
  assert_file_contains "$(ticket_file 01-alpha)" "edited the tracker itself"
}

@test "a session cannot resolve a ticket it was not given" {
  # The same hole seen from the other side, and the more expensive one: marking
  # somebody else's ticket resolved takes it out of the frontier for good, and the
  # run reports a night in which it was simply never picked up.
  use_tickets 01-alpha 02-beta

  # Only the first session cheats; the retry and the iteration after it are
  # honest. So the run has to reach 02 on its own, which it can only do if 02 is
  # still on the frontier after somebody else marked it resolved.
  script_claude <<'FAKE'
#!/usr/bin/env bash
prompt="$(cat)"
n="$(cat "$RALPH_SHIM_STATE/seq" 2>/dev/null || echo 0)"
n=$((n + 1)); printf '%s\n' "$n" >"$RALPH_SHIM_STATE/seq"

surface="$(printf '%s' "$prompt" |
  sed -n 's/^\*\*Write-surface:\*\* //p' | head -1 | tr -d '`\r' | tr ',' ' ')"
for target in $surface; do
  mkdir -p "$(dirname "$target")" && printf 'written\n' >"$target"
done

if [ "$n" = 1 ]; then
  perl -pi -e 's/^\*\*Status:\*\* .*/**Status:** resolved/' \
    .scratch/demo/issues/02-beta.md
fi
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_success

  # 02 was really ground: the run spawned a session for it rather than walking
  # past a ticket already marked done and calling the frontier drained.
  assert_ticket_status 02-beta resolved
  assert_file_contains "$PROJECT_DIR/src/beta.txt" "written"
  assert_equal "$(claude_call_count)" "3"
  run bash -c "grep -c 'tracker-write' '$FEATURE_DIR/run.log'"
  assert_equal "$output" "1"
}

@test "a ticket the session created is quarantined, not quietly restored away" {
  # Restoring the directory wholesale would delete it — and with it the only copy
  # of what it asked for. The two checks have to agree: edits go back, additions
  # go to a human.
  use_tickets 01-alpha

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src .scratch/demo/issues
printf 'written\n' >src/alpha.txt
cat >.scratch/demo/issues/50-self-served.md <<'TICKET'
# 50 — Self served

**Blocked by:** None

**Write-surface:** `src/anything.txt`

**Status:** ready-for-agent

- [ ] whatever this session felt like doing next
TICKET
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_success

  assert_file_exists "$(ticket_file 50-self-served)"
  assert_ticket_status 50-self-served ready-for-human
  # An addition alone is not a failure of its own: [07] settled that the work can
  # be good while the entry it smuggled in is neutralised.
  assert_ticket_status 01-alpha resolved
  refute_output_contains "the session edited the tracker"
}

@test "a session that deletes the whole tracker gets it back" {
  # The hostile end of the same mechanism, and the one that would end a run: the
  # tracker is the only authority on state, so a `rm -rf` in the wrong place is
  # not one lost ticket but every ticket, including the claim of the iteration
  # running. The snapshot has to be able to rebuild the directory itself, not just
  # overwrite files inside one.
  use_tickets 01-alpha 02-beta 03-blocked
  set_config STERILE_K 1

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src
printf 'written\n' >src/alpha.txt
rm -rf .scratch/demo/issues
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_failure 4
  assert_output_contains "the session edited the tracker — restored 3 ticket file(s)"

  # Every ticket is back, with the state it had at spawn time — and the run went
  # on to mark and journal against it rather than dying on a missing file.
  assert_ticket_status 01-alpha ready-for-agent
  assert_ticket_status 02-beta ready-for-agent
  assert_ticket_status 03-blocked ready-for-agent
  assert_equal "$(ticket_field 01-alpha Failures)" "1"
  assert_file_contains "$FEATURE_DIR/run.log" "tracker-write"
}

@test "a project that keeps its scratch out of git is guarded all the same" {
  # The probe that decided the snapshot is taken by force. Plenty of real projects
  # gitignore their scratch directory — and [19] provisions exactly that for the
  # journal and the session streams. An ignore rule the target project happens to
  # write must not be able to switch the tracker's own guard off, which is what an
  # ordinary `git add -A` would have done: both snapshots empty, no delta ever,
  # and the exploit back with no trace of the guard having declined.
  use_tickets 01-alpha
  set_config STERILE_K 1
  printf '.scratch/\n' >>"$PROJECT_DIR/.gitignore"
  harness__commit "test: a project that keeps its scratch out of git"

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src
printf 'written\n' >src/alpha.txt
printf 'written\n' >src/rogue.txt
perl -pi -e 's/^\*\*Write-surface:\*\* .*/**Write-surface:** `*`/' \
  .scratch/demo/issues/01-alpha.md
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_failure 4

  assert_output_contains "the session edited the tracker"
  assert_output_contains "scope=red"
  assert_equal "$(ticket_field 01-alpha Write-surface)" '`src/alpha.txt`'
  assert_ticket_status 01-alpha ready-for-agent
  refute_file_exists "$PROJECT_DIR/src/rogue.txt"
}

@test "a tracker nothing can vouch for does not pass" {
  use_tickets 01-alpha

  # The same rule the scope-guard follows: a guard that cannot see must not pass.
  # Reached when git refuses to write a tree object — the run is in trouble either
  # way, and the one thing it must not do is call the iteration clean.
  pack_run 'rc=0; failures_protect_tracker 01-alpha "" || rc=$?; printf "rc=%s\n" "$rc"'
  assert_success
  assert_output_contains "rc=1"
  assert_output_contains "cannot be vouched for"
}

@test "a tracker the session staged does not stay staged" {
  use_tickets 01-alpha
  set_config STERILE_K 1

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src
printf 'written\n' >src/alpha.txt
perl -pi -e 's/^\*\*Write-surface:\*\* .*/**Write-surface:** `*`/' \
  .scratch/demo/issues/01-alpha.md
git add -A >/dev/null 2>&1
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_failure 4

  # Putting the file back is not enough if the index still holds the session's
  # version: it would leave with whatever a human commits next. The rollback
  # cannot do it — it unstages only the paths it restored, and the tracker is
  # deliberately outside its reach.
  run git -C "$PROJECT_DIR" diff --cached --name-only
  refute_output_contains "issues/01-alpha.md"

  # Scoped to the tickets, and the rest of `.scratch/` is not this ticket's to
  # keep: what an unfiltered `git add` stages there — the lock, the prompt, a
  # session stream of any size — is [19]'s `.gitignore` to provision. Pinned so
  # that the day it is provisioned, this line says what changed.
  assert_output_contains ".session."
}

@test "a planning session that edits the tracker has its whole plan refused" {
  use_tickets 07-overlaps-alpha
  set_config SOFT_LIMIT_TOKENS 5000
  set_config STERILE_K 2

  # A sound plan, from a session that widened the parent's write-surface on its
  # way past. Widening it is what a plan may not do — so a plan validated against
  # a surface the planner just wrote is validated against nothing.
  script_too_big_then <<'FAKE'
perl -pi -e 's/^\*\*Write-surface:\*\* .*/**Write-surface:** `*`/' \
  .scratch/demo/issues/07-overlaps-alpha.md
plan="$(printf '%s' "$prompt" | sed -n 's/^Write the plan to \([^,]*\),.*/\1/p' | head -1)"
cat >"$plan" <<'PLAN'
--- ticket: everything | Everything, now that it is allowed ---
**Write-surface:** `src/alpha.txt`

- [ ] the alpha half exists
--- ticket: and-more | And the rest of the repository ---
**Write-surface:** `docs/`

- [ ] the rest exists
PLAN
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":2,"total_cost_usd":0.01}'
FAKE

  run_loop
  assert_success
  assert_output_contains "the session edited the tracker"

  assert_ticket_status 07-overlaps-alpha ready-for-human
  assert_equal "$(ticket_field 07-overlaps-alpha Escalation)" "too-big"
  assert_equal "$(ticket_field 07-overlaps-alpha Write-surface)" '`src/alpha.txt`, `src/eta.txt`'

  # Nothing was created out of the plan, sound as each half looked.
  run bash -c "ls '$TRACKER_DIR' | awk 'END { print NR }'"
  assert_equal "$output" "1"
}

@test "a delivery session does not get to put its own tickets on the frontier" {
  use_tickets 01-alpha
  set_config STERILE_K 2

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src .scratch/demo/issues
printf 'written\n' >src/alpha.txt
cat >.scratch/demo/issues/50-self-served.md <<'TICKET'
# 50 — Self served

**Blocked by:** None

**Write-surface:** `src/anything.txt`

**Status:** ready-for-agent

- [ ] whatever this session felt like doing next
TICKET
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_success
  assert_output_contains "the session wrote the tracker itself — quarantined 50-self-served"

  # Its own work still stands or falls on the gate — this is a separate matter.
  assert_ticket_status 01-alpha resolved

  # The ticket it granted itself waits for a human, and was never ground.
  assert_ticket_status 50-self-served ready-for-human
  assert_equal "$(ticket_field 50-self-served Escalation)" "decision"
  refute_file_exists "$PROJECT_DIR/src/anything.txt"
  assert_equal "$(claude_call_count)" "1"

  # And the ticket that let it happen says so.
  assert_file_contains "$(ticket_file 01-alpha)" "wrote these tickets into the tracker itself"
}

@test "a planning session that writes tickets has its whole plan refused" {
  use_tickets 07-overlaps-alpha
  set_config SOFT_LIMIT_TOKENS 5000
  set_config STERILE_K 2

  # A plan that is perfectly sound, alongside a ticket it published on its own.
  # Sound or not, the output of a session that wrote the tracker is not read.
  script_too_big_then <<'FAKE'
mkdir -p .scratch/demo/issues
cat >.scratch/demo/issues/50-self-served.md <<'TICKET'
# 50 — Self served

**Blocked by:** None

**Write-surface:** `src/anything.txt`

**Status:** ready-for-agent

- [ ] whatever this session felt like doing next
TICKET
plan="$(printf '%s' "$prompt" | sed -n 's/^Write the plan to \([^,]*\),.*/\1/p' | head -1)"
cat >"$plan" <<'PLAN'
--- ticket: alpha-half | The alpha half ---
**Write-surface:** `src/alpha.txt`

- [ ] the alpha half exists
--- ticket: eta-half | The eta half ---
**Write-surface:** `src/eta.txt`

- [ ] the eta half exists
PLAN
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":2,"total_cost_usd":0.01}'
FAKE

  run_loop
  assert_success
  assert_output_contains "the session wrote the tracker itself"

  assert_ticket_status 50-self-served ready-for-human
  assert_ticket_status 07-overlaps-alpha ready-for-human
  assert_equal "$(ticket_field 07-overlaps-alpha Escalation)" "too-big"

  # The plan was not read: no half was created, however sound it looked.
  refute_file_exists "$(ticket_file 08-alpha-half)"
  run bash -c "ls '$TRACKER_DIR' | awk 'END { print NR }'"
  assert_equal "$output" "2"
}

# ── when git itself says no ──────────────────────────────────────────────────

@test "a commit git refuses is a warning, not the end of the run" {
  use_tickets 01-alpha 02-beta
  script_honest_session

  # What a crashed git leaves behind. Every `update-ref` on the current branch
  # fails from here on, so no iteration can be made durable.
  : >"$PROJECT_DIR/.git/refs/heads/main.lock"

  run_loop
  assert_success
  assert_output_contains "could not commit the iteration — it is not durable"

  # Said out loud, and the night's work happens anyway.
  assert_ticket_status 01-alpha resolved
  assert_ticket_status 02-beta resolved
  assert_file_contains "$PROJECT_DIR/src/alpha.txt" "written"
}

@test "a branch git cannot name is a warning too, and the escalation still lands" {
  use_tickets 01-alpha
  set_config RETRY_N 0
  set_config STERILE_K 1
  script_session_writing src/alpha.txt src/rogue.txt

  # A project with a branch called `failed` cannot also have `failed/01-alpha`:
  # git refuses the ref, and the forensic branch is the one thing lost.
  git -C "$PROJECT_DIR" branch failed

  run_loop
  assert_failure 4
  assert_output_contains "could not write branch failed/01-alpha"

  assert_ticket_status 01-alpha ready-for-human
  assert_equal "$(ticket_field 01-alpha Escalation)" "failed-impl"
  refute_file_exists "$PROJECT_DIR/src/rogue.txt"
}

# ── a gate branch that never comes back ──────────────────────────────────────

@test "a gate branch that hangs is red, and does not hang the run" {
  use_tickets 01-alpha
  set_config STERILE_K 1
  set_config GATE_TIMEOUT 1
  set_config TEST_CMD "sleep 30"

  run_loop
  assert_failure 4
  assert_output_contains "tests red (timed out after 1s)"

  # The deadline kills the branches, not the verdicts already in: a hung test
  # suite must not hide what the other checks found.
  assert_output_contains "scope=green"
  assert_output_contains "typecheck=green"
  assert_ticket_status 01-alpha ready-for-agent
}
