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

@test "a ticket nothing ever delivers goes to the human sink under its own name" {
  # Not `failed-impl`, for the reason [26] had to learn about `Failures:` and [23]
  # applied to a session that hung: nothing was judged, so a human sent to read a
  # verdict has been misrouted. One step further than [23], though — there is
  # nothing to read *at all* here, so the forensic branch is not written and the
  # note carries the question instead ([35]).
  use_tickets 01-alpha
  set_config RETRY_N 1
  set_config STERILE_K 3
  session_writes_nothing

  run_loop
  # Exit 0: two attempts, then nothing left on the frontier to grind.
  assert_success
  assert_output_contains "01-alpha: nothing-delivered -> fresh retry (1 of 1)"
  assert_output_contains "escalated to the human sink (nothing-delivered)"

  assert_ticket_status 01-alpha ready-for-human
  assert_equal "$(ticket_field 01-alpha Escalation)" "nothing-delivered"
  assert_equal "$(ticket_field 01-alpha Failures)" "2"

  # No branch to send a human to: it would hold the very tree the session was
  # handed, offered as the thing to go and read.
  run git -C "$PROJECT_DIR" rev-parse --verify "refs/heads/failed/01-alpha"
  assert_failure

  # What the ticket gets instead is the question to ask.
  assert_file_contains "$(ticket_file 01-alpha)" "changed no file the gate can see"
  assert_file_contains "$(ticket_file 01-alpha)" "why this ticket makes a session do nothing"
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

@test "a green delivery clears the retry counter" {
  # `Failures:` is a budget, not a history, and nothing used to clear it: probed on
  # 29/07/2026, a ticket delivered green twice was escalated `failed-impl` on its
  # third visit to the frontier, on a counter that had never been reset. Red once,
  # then green, and the counter is gone — a ticket that comes back to the frontier
  # after a delivery comes back for a new reason, with its whole budget.
  use_tickets 01-alpha
  set_config RETRY_N 2
  set_config STERILE_K 5
  stub_exit tests 1

  # The first session leaves the test command failing and the second one repairs
  # it, so the ticket is really retried rather than delivered on the first attempt.
  script_claude <<'FAKE'
#!/usr/bin/env bash
n="$(cat "$RALPH_SHIM_STATE/seq" 2>/dev/null || echo 0)"
n=$((n + 1)); printf '%s\n' "$n" >"$RALPH_SHIM_STATE/seq"
mkdir -p src
printf 'written\n' >src/alpha.txt
[ "$n" -ge 2 ] && printf '0\n' >"$RALPH_SHIM_STATE/stub-tests.exit"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_success

  # The retry really happened, so the counter really was at 1 in between: without
  # this line the assertion below would hold on a ticket that never failed at all.
  assert_output_contains "01-alpha: gate-red -> fresh retry (1 of 2)"
  assert_equal "$(claude_call_count)" "2"
  assert_ticket_status 01-alpha resolved

  run ticket_has_field 01-alpha Failures
  assert_failure
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

@test "an iteration never touches work nobody in this run made" {
  # This used to be "a rollback is not a reset --hard", and since [13] it proves
  # something else — still true, and stronger. A human's uncommitted work is not
  # spared by a narrow rollback any more; it is simply not in the tree the
  # iteration runs in. What keeps the name is the lib-level test further down,
  # where the width of the rollback is still visible.

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

# ── the rollback, driven as a lib ────────────────────────────────────────────
#
# Four mutations went VACUOUS here the day [13] landed, and they were right. An
# iteration rolls back inside a worktree that is thrown away straight afterwards,
# so a loop-level test that asserts `refute_file_exists "$PROJECT_DIR/…"` is
# asserting something that is true whether the rollback ran or not — the tree the
# run was started in never had the file. What those tests still prove is worth
# keeping (the ticket, the retries, the lines the run printed); what they stopped
# proving is proved here, on the primitive, in a tree where the effect is visible.
#
# Driven with no pre-session commit (`pre` empty), so HEAD is left alone: what is
# under test is the tree half. The commit half has its own test above.

# The state a failed session leaves, staged the way an agent interrupted mid-commit
# leaves it, plus a file nobody in this run made. Prints the pre-session tree so a
# test can hand it back.
failures__stage_a_failed_session() {
  pack_run '
    cd "$(ralph_project_root)"
    printf "human work\n" >untracked-by-nobody.txt
    printf "%s\n" "$(gate_tree_snapshot)" >.base
    mkdir -p src
    printf "written\n" >src/added.txt
    printf "edited\n" >>CONTEXT.md
    rm -f README-fixture.txt
    git add -A >/dev/null 2>&1
    printf "%s\n" "$(gate_tree_snapshot)" >.now
  '
}

@test "the rollback removes what the session added and brings back what it deleted" {
  use_tickets 01-alpha
  printf 'a file the run did not make\n' >"$PROJECT_DIR/README-fixture.txt"
  harness__commit "test: a tracked file for the session to delete"

  failures__stage_a_failed_session
  assert_success
  assert_file_exists "$PROJECT_DIR/src/added.txt"
  refute_file_exists "$PROJECT_DIR/README-fixture.txt"

  pack_run '
    cd "$(ralph_project_root)"
    failures_rollback "" "$(cat .base)" "$(cat .now)"
  '
  assert_success
  assert_output_contains "rolled back"

  refute_file_exists "$PROJECT_DIR/src/added.txt"
  assert_file_contains "$PROJECT_DIR/README-fixture.txt" "a file the run did not make"
  refute_file_contains "$PROJECT_DIR/CONTEXT.md" "edited"
}

@test "the rollback unstages what it put back, and only those paths" {
  use_tickets 01-alpha
  printf 'a file the run did not make\n' >"$PROJECT_DIR/README-fixture.txt"
  harness__commit "test: a tracked file for the session to delete"

  failures__stage_a_failed_session
  assert_success
  pack_run '
    cd "$(ralph_project_root)"
    failures_rollback "" "$(cat .base)" "$(cat .now)"
  '
  assert_success

  # Undoing the files without unstaging them would leave the attempt sitting in
  # the index, ready to ride along with the next commit.
  run bash -c "git -C '$PROJECT_DIR' diff --cached --name-only"
  refute_output_contains "src/added.txt"
  refute_output_contains "CONTEXT.md"
  refute_output_contains "README-fixture.txt"
}

@test "a rollback is not a reset --hard: work nobody in this run made stands" {
  # The whole reason the rollback is exactly as wide as the session's diff. A
  # `git reset --hard` plus `git clean -fd` is the obvious implementation and it
  # takes a human's uncommitted work down with the failed attempt.
  use_tickets 01-alpha
  printf 'a file the run did not make\n' >"$PROJECT_DIR/README-fixture.txt"
  harness__commit "test: a tracked file for the session to delete"

  failures__stage_a_failed_session
  assert_success
  pack_run '
    cd "$(ralph_project_root)"
    failures_rollback "" "$(cat .base)" "$(cat .now)"
  '
  assert_success

  # It was there before the session, it is not in the session's diff, and it is
  # still there. `git clean -fd` would have taken it.
  assert_file_contains "$PROJECT_DIR/untracked-by-nobody.txt" "human work"
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

@test "the rollback names the ignored paths it could not undo" {
  # "The tree is back where the session found it" was true except for a set of
  # paths nobody enumerated — everything this project's `.gitignore` covers. The
  # rollback cannot reach them: it diffs git trees, and they are not in either
  # one. So it says so, and this test holds both halves — the claim, and the fact
  # that the file really is still lying there.
  use_tickets 01-alpha
  set_config STERILE_K 1
  printf 'cache/\n' >>"$PROJECT_DIR/.gitignore"
  harness__commit "test: the project ignores a build cache"

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src cache
printf 'written\n' >src/alpha.txt
printf 'written\n' >src/rogue.txt
printf 'payload\n' >cache/payload
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_failure 4

  assert_output_contains "this rollback could not undo"
  assert_output_contains "cache/"
  # Named inside the iteration and gone with its worktree since [13]: the line
  # above is the guarantee — a rollback that says "the tree is back" while an
  # unenumerated set of paths is exempt — and what changed is only that the
  # exemption no longer outlives the iteration that made it.
  refute_file_exists "$PROJECT_DIR/cache/payload"
  # What it could see is undone, as before.
  refute_file_exists "$PROJECT_DIR/src/rogue.txt"
  refute_file_exists "$PROJECT_DIR/src/alpha.txt"
}

@test "a rollback with nothing to undo names the zone all the same" {
  # The probe that opened [24], second of three: a session whose only write is an
  # ignored file. The rollback finds nothing in its diff — the honest reading of
  # which is not silence, because the file is still there. A report tied to
  # "something was undone" would say nothing in exactly the case where the tree is
  # *not* back where the session found it.
  use_tickets 01-alpha
  set_config STERILE_K 1
  stub_exit tests 1
  printf 'cache/\n' >>"$PROJECT_DIR/.gitignore"
  harness__commit "test: the project ignores a build cache"

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p cache && printf 'payload\n' >cache/payload
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_failure 4

  refute_output_contains "rolled back"
  assert_output_contains "this rollback could not undo"
  assert_output_contains "cache/"
  # Named inside the iteration and gone with its worktree since [13]: the line
  # above is the guarantee — a rollback that says "the tree is back" while an
  # unenumerated set of paths is exempt — and what changed is only that the
  # exemption no longer outlives the iteration that made it.
  refute_file_exists "$PROJECT_DIR/cache/payload"
}

@test "the rollback names what the gate itself changed, and leaves it standing" {
  # The third exemption of a rollback that announces "the tree is back where the
  # session found it": the tracker it leaves on purpose, the ignored zone it cannot
  # see, and — since [29] — what the gate's own branches wrote after the tree it
  # judged was taken. That artefact is in neither of the two trees this function
  # diffs, and git does not ignore it, so [24]'s line does not name it either. A
  # suite that writes a report and then goes red is any real suite.
  use_tickets 01-alpha
  set_config STERILE_K 1
  set_config TEST_CMD 'mkdir -p build; printf report >build/coverage.xml; exit 1'
  script_session_writing src/alpha.txt

  run_loop
  assert_failure 4

  assert_output_contains \
    "this rollback could not undo 1 path(s) the gate itself changed after the tree it judged: build/coverage.xml"
  # Named inside the iteration and gone with its worktree since [13]: the line
  # above is the guarantee — a rollback that says "the tree is back" while an
  # unenumerated set of paths is exempt — and what changed is only that the
  # exemption no longer outlives the iteration that made it.
  refute_file_exists "$PROJECT_DIR/build/coverage.xml"
  # What it could see is undone, as before.
  refute_file_exists "$PROJECT_DIR/src/alpha.txt"
}

@test "a path the rollback did put back is not named as one it could not" {
  # The lie in the other direction, which is the shape this suite has got wrong
  # before. A suite that rewrites a file the session had also touched — an updated
  # snapshot, a formatter, a code generator — differs from the judged tree just like
  # a fresh artefact does, but this rollback restores it from the pre-session
  # snapshot like any other path in its diff. Naming it would send a human looking
  # for something that is not there.
  use_tickets 01-alpha
  set_config STERILE_K 1
  set_config TEST_CMD 'printf suite >>src/alpha.txt; exit 1'
  script_session_writing src/alpha.txt

  run_loop
  assert_failure 4

  # Kept in a variable: the refutation has to be about this line and not about
  # whichever `run` happened last.
  local named
  named="$(printf '%s\n' "$output" | grep 'the gate itself changed' || true)"
  assert_equal "$named" ""
  refute_file_exists "$PROJECT_DIR/src/alpha.txt"
  assert_equal "$(worktree_dirt)" ""
}

@test "a rollback that cannot measure what the gate left says so, and does not go red" {
  # The fourth reader of the same primitive ([34]). This line is printed after a
  # rollback that has already happened, so there is nothing left to refuse — what it
  # owes is the difference between "there was nothing left" and "nobody knows what
  # was left". Driven directly: the instrument has to close *between* the trees the
  # rollback was handed and the report that comes after it, which is a window the
  # loop has no way to hand a test.
  use_tickets 01-alpha
  pack_run '
    base="$(gate_tree_snapshot)"
    printf "stray\n" >stray.txt
    tree="$(gate_tree_snapshot)"
    mkdir -p build && printf "report\n" >build/coverage.xml
    gate_tree_snapshot() { return 1; }
    failures_rollback "" "$base" "$tree"'
  # `assert_success` is the "does not go red" half: pack_run runs under `set -e`,
  # so a rollback that returned non-zero here would take the script down with it.
  assert_success
  assert_output_contains "this rollback could not check what the gate itself changed"

  # The witness: the same window with the instrument open names the artefact
  # instead. Without it this test would pass on a report that had simply stopped
  # counting.
  #
  # A different artefact, and it is not cosmetic: the two `pack_run` calls share one
  # project directory, and the first one's `build/coverage.xml` is still lying there
  # — it would be in this one's baseline, and a file that did not change is in no
  # diff, so the report would be silent for a reason that has nothing to do with
  # what is asserted here.
  pack_run '
    base="$(gate_tree_snapshot)"
    printf "stray\n" >stray.txt
    tree="$(gate_tree_snapshot)"
    mkdir -p build && printf "report\n" >build/witness.xml
    failures_rollback "" "$base" "$tree"'
  assert_success
  assert_output_contains \
    "this rollback could not undo 1 path(s) the gate itself changed after the tree it judged: build/witness.xml"
  refute_output_contains "could not check what the gate itself changed"
}

@test "a rollback that could not act stops the run instead of laundering it" {
  # Probe B of [34], end to end. Every fail-closed on the way works and none of
  # them is enough: the session writes out of its surface and destroys the pinned
  # ignore rules, so the snapshot refuses, the scope-guard refuses to pass a tree
  # it cannot read, and the rollback says out loud that it undid nothing. What
  # nothing stopped was the *next* iteration, which snapshots that tree as its own
  # pre-session baseline — after which `lib/rogue.sh` is nobody's change and the
  # ticket that inherits it goes green carrying it. One retry was the price [30]
  # wrote down; a laundered write is not.
  #
  # Two tickets on the frontier, which is what makes "the run stopped" mean
  # something: without the stop the loop goes straight on to 02-beta.
  use_tickets 01-alpha 02-beta

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src lib
printf 'written\n' >src/alpha.txt
printf 'rogue\n' >lib/rogue.sh
rm -rf "${TMPDIR:-/tmp}"/ralph-ignore.*
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop_own_tmp
  assert_failure 4
  assert_output_contains "cannot read the working tree — nothing was rolled back"
  assert_output_contains "stopping rather than grinding on an instrument that is already closed"

  # And the announcement of what the gate itself left behind says which of the two
  # it is. This one is not red and must not become one — it is printed on green
  # iterations too — but "this gate wrote nothing" and "nobody knows what this gate
  # wrote" are not the same line to read in the morning.
  assert_output_contains "this gate could not check what it changed after the tree it judged"

  # The out-of-surface write really is still there — that is what the run is
  # stopping *about*, and asserting the message alone would pass on a run that
  # stopped for any other reason.
  # It went with the worktree, which is what [13] closed here: the laundering
  # this stop exists to refuse cannot happen through an inherited tree any more.
  # The stop is kept all the same, and loop.sh says why — a rollback fails for
  # reasons that are not local to one tree, and the sibling beside it is about to
  # meet all of them.
  refute_file_exists "$PROJECT_DIR/lib/rogue.sh"

  # And the second ticket was never ground: one session, one iteration.
  assert_ticket_status 02-beta ready-for-agent
  assert_equal "$(claude_call_count)" "1"
}

@test "a rollback that could act lets the run carry on to the next ticket" {
  # The paired witness of the test above, and it carries two refutations at once.
  # Without it, a loop that stopped after every failed iteration — or a snapshot
  # that always refused — would pass there and nothing here would notice. The same
  # session, the same out-of-surface write, the pin left alone: rolled back, one
  # retry charged, and the run goes on.
  use_tickets 01-alpha 02-beta
  set_config RETRY_N 0

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src lib
printf 'written\n' >src/alpha.txt
printf 'rogue\n' >lib/rogue.sh
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop_own_tmp

  refute_output_contains "nothing was rolled back"
  refute_output_contains "stopping rather than letting the next iteration"
  refute_file_exists "$PROJECT_DIR/lib/rogue.sh"

  # 01-alpha is out of retries and escalated, so the loop moved on and ground
  # 02-beta with the same session — two calls, which is the whole point.
  assert_ticket_status 01-alpha ready-for-human
  assert_equal "$(claude_call_count)" "2"
}

# ── the ignore frontier, where no gate judged ────────────────────────────────
#
# [30] put `.git/info/exclude` and `core.excludesFile` back after every iteration
# that widened them, because the *next* iteration pins what it finds and would
# inherit the blindness as the project's own configuration. It put them back
# inside `gate_run` and inside the re-slice — and an iteration whose session
# crashed or was cut short goes through neither ([32]). The price for a session is
# a non-zero exit, which it controls.
#
# Every class of `failures_classify` is named by one test, here or elsewhere: a
# correction placed on the path that happened to be probed is exactly what [30]
# shipped. `crash` and `timeout` below; `too-big` in "the re-slice session cannot
# leave the ignore frontier widened"; `gate-red` and `nothing-delivered` in the
# two counting tests below, which is where `contract` rides too — it is a
# `gate-red` the scope-guard classified, judged by the same gate.

@test "a session that crashed cannot leave the ignore frontier widened" {
  # The probe of [32], in both halves. The first alone would pass on a correction
  # that puts the file back without anybody checking that putting it back counts
  # for anything — so what the *second* iteration inherits is asserted first.
  use_tickets 01-alpha
  set_config RETRY_N 1
  set_config STERILE_K 3

  script_claude <<'FAKE'
#!/usr/bin/env bash
cat >/dev/null
n="$(cat "$RALPH_SHIM_STATE/seq" 2>/dev/null || echo 0)"
n=$((n + 1)); printf '%s\n' "$n" >"$RALPH_SHIM_STATE/seq"
mkdir -p src rogue
printf 'written\n' >src/alpha.txt
if [ "$n" = 1 ]; then
  # A worktree answers `.git` with a *file*, so the naive `>>.git/info/exclude`
# writes nothing at all and this scenario would stage nothing while reading as
# green. The rule source git really reads is in the **common** git directory,
# which is what a session in any working tree of this repository would find,
# and what the pin looks at since [13].
printf 'rogue/\n' >>"$(git rev-parse --git-common-dir)/info/exclude"
  printf 'backdoor\n' >rogue/backdoor
  exit 1
fi
printf 'second\n' >rogue/second
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_success
  local loop_output="$output"

  # The half that matters, and the reason the restore exists at all: the second
  # session writes outside its surface behind the rule the first one wrote. Left
  # widened, `rogue/` is what this iteration pins, so nothing sees the write, the
  # gate is green and the ticket resolves carrying it.
  assert_output_contains "wrote rogue/second, outside the declared write-surface"
  refute_file_exists "$PROJECT_DIR/rogue/second"
  assert_ticket_status 01-alpha ready-for-human

  # And the half [30] already held, on a path it never reached.
  output="$loop_output"
  assert_output_contains "moved the ignore frontier in .git/info/exclude"
  assert_output_contains "(put back)"
  refute_file_contains "$PROJECT_DIR/.git/info/exclude" "rogue/"
  refute_file_exists "$PROJECT_DIR/rogue/backdoor"

  # Once for the whole run: the second iteration has nothing to put back, so a
  # second line here would mean the run is reporting a movement nobody made.
  run bash -c "grep -c 'moved the ignore frontier in .git/info/exclude' <<'OUT'
$loop_output
OUT"
  assert_equal "$output" "1"
}

@test "a session the loop cut short cannot leave it widened either" {
  # The other class with no caller, and the one that was two days old when [30]
  # was written ([23]). A hung session is killed, `claude` traps TERM and comes
  # back a success, and the iteration is never gated — same hole, different door.
  use_tickets 01-alpha
  set_config SESSION_STALL_TIMEOUT 2
  set_config STERILE_K 1

  script_claude <<'FAKE'
#!/usr/bin/env bash
cat >/dev/null
# A worktree answers `.git` with a *file*, so the naive `>>.git/info/exclude`
# writes nothing at all and this scenario would stage nothing while reading as
# green. The rule source git really reads is in the **common** git directory,
# which is what a session in any working tree of this repository would find,
# and what the pin looks at since [13].
printf 'rogue/\n' >>"$(git rev-parse --git-common-dir)/info/exclude"
mkdir -p rogue && printf 'backdoor\n' >rogue/backdoor
echo '{"type":"system","subtype":"init","session_id":"s"}'
echo '{"type":"assistant","message":{"role":"assistant","usage":{"input_tokens":10,"cache_read_input_tokens":9000,"output_tokens":5}}}'
i=0
while [ $i -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
exit 0
FAKE

  run_loop
  assert_failure 4
  assert_output_contains "hung, terminated"
  assert_output_contains "moved the ignore frontier in .git/info/exclude"
  assert_output_contains "(put back)"
  refute_file_contains "$PROJECT_DIR/.git/info/exclude" "rogue/"

  # What was written behind the rule goes with it: the rollback runs after the
  # restore, so it measures the tree through the rules the run was handed.
  refute_file_exists "$PROJECT_DIR/rogue/backdoor"
}

@test "an iteration a gate judged says the frontier moved once, not twice" {
  # The failure mode of the obvious correction: a restore at the head of
  # `failures_handle` covers the two missing classes and doubles the one path that
  # already had it. Two findings for one movement, and a line claiming no gate
  # judged an iteration a gate judged — the half-truth [29] refused, in the other
  # direction.
  #
  # Both sources are moved, and that is what makes this test able to fail. The
  # restore of `.git/info/exclude` is idempotent by construction — the second
  # caller finds it back where the pin says and reports nothing — so a doubled
  # call is invisible there. The tree's rules are never put back, on purpose, so
  # they are the one place a second speaker has something to say twice.
  use_tickets 01-alpha
  set_config STERILE_K 1
  stub_exit tests 1

  script_claude <<'FAKE'
#!/usr/bin/env bash
cat >/dev/null
# A worktree answers `.git` with a *file*, so the naive `>>.git/info/exclude`
# writes nothing at all and this scenario would stage nothing while reading as
# green. The rule source git really reads is in the **common** git directory,
# which is what a session in any working tree of this repository would find,
# and what the pin looks at since [13].
printf 'rogue/\n' >>"$(git rev-parse --git-common-dir)/info/exclude"
printf 'lib/\n' >>.gitignore
mkdir -p src && printf 'written\n' >src/alpha.txt
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_failure 4
  local loop_output="$output"

  assert_output_contains "tests=red"
  assert_output_contains "moved the ignore frontier in .git/info/exclude"
  refute_file_contains "$PROJECT_DIR/.git/info/exclude" "rogue/"

  # A gate ran, so the sentence a gateless path prints has no business here.
  output="$loop_output"
  refute_output_contains "no gate judged this iteration"

  run bash -c "grep -c 'moved the ignore frontier in .git/info/exclude' <<'OUT'
$loop_output
OUT"
  assert_equal "$output" "1"

  run bash -c "grep -c 'this session moved the ignore frontier: .gitignore' <<'OUT'
$loop_output
OUT"
  assert_equal "$output" "1"
}

@test "an iteration refused before the fan says it once too" {
  # The third printer, and the one that only exists since [35]: a delivery refusal
  # returns its verdict before a single branch starts, so there is no scope-guard
  # to carry the findings and `gate_run` prints them itself. A restore added in
  # `failures_handle` without looking would double this one as well.
  use_tickets 01-alpha
  set_config STERILE_K 1
  session_writes_nothing

  script_claude <<'FAKE'
#!/usr/bin/env bash
cat >/dev/null
# A worktree answers `.git` with a *file*, so the naive `>>.git/info/exclude`
# writes nothing at all and this scenario would stage nothing while reading as
# green. The rule source git really reads is in the **common** git directory,
# which is what a session in any working tree of this repository would find,
# and what the pin looks at since [13].
printf 'rogue/\n' >>"$(git rev-parse --git-common-dir)/info/exclude"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_failure 4
  local loop_output="$output"

  assert_output_contains "nothing was delivered"
  refute_file_contains "$PROJECT_DIR/.git/info/exclude" "rogue/"

  run bash -c "grep -c 'moved the ignore frontier in .git/info/exclude' <<'OUT'
$loop_output
OUT"
  assert_equal "$output" "1"
}

@test "a rule the crashed session wrote in the tree is named before it goes" {
  # The `.gitignore` of the working tree has nothing to put back — a ticket may
  # add an ignore rule, that is project work ([30]) — but on a path with no gate
  # nobody was naming it either. A human read `this rollback could not undo … lib/`
  # with no way to tell a build directory from one a session had just decided to
  # hide. And the sentence is not the gated one: here the rollback takes the rule
  # away, so "the new rules apply from the next iteration" would be false.
  use_tickets 01-alpha
  set_config STERILE_K 1

  script_claude <<'FAKE'
#!/usr/bin/env bash
cat >/dev/null
printf 'lib/\n' >>.gitignore
mkdir -p lib src
printf 'rogue\n' >lib/rogue.sh
printf 'written\n' >src/alpha.txt
exit 1
FAKE

  run_loop
  assert_failure 4
  assert_output_contains "this session moved the ignore frontier: .gitignore"
  assert_output_contains "no gate judged this iteration"

  # And it really did go: the line describes what the rollback is about to do.
  refute_file_exists "$PROJECT_DIR/.gitignore"
  refute_file_exists "$PROJECT_DIR/lib/rogue.sh"
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
  # and not anywhere in the history the run produced. Cheaper to hold since [13]
  # than the assertion suggests, and worth saying rather than quietly banking: the
  # run journal, the lock and a session stream of any size live in the tree the run
  # was started in, so a `git add -A` inside an iteration's worktree cannot reach
  # them. What is still exercised here is the half that matters — the session's own
  # commit is undone and the loop's is the one that carries the work.
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

  # The ticket that was too big waited for them, came back to the frontier, and
  # went to a human — which is what [35] changed here and it is worth reading
  # slowly. Its acceptance criteria were split into the two children by
  # construction, so once they are resolved a session on the parent has nothing
  # left to write; before [35] that empty iteration was `resolved` on three green
  # branches, which is to say the parent was rubber-stamped by a gate that had
  # nothing to judge. Now it is refused and escalated, and the note on it asks
  # exactly the right question — "why does this ticket make a session do nothing",
  # whose third answer is "the work is already done". Whether a split really added
  # up to its parent is a human's call: nothing in the pack checks that the
  # children carried every criterion, the re-slice prompt only *asks* for it.
  assert_file_contains "$(ticket_file 07-overlaps-alpha)" "Re-sliced into: 08-alpha-half, 09-eta-half"
  assert_ticket_status 07-overlaps-alpha ready-for-human
  assert_equal "$(ticket_field 07-overlaps-alpha Escalation)" "nothing-delivered"

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

@test "the re-slice session cannot leave the ignore frontier widened" {
  # A planning session is a session, and it is the one this pack never gates: its
  # whole output is thrown away, so nothing downstream would ever have put the
  # ignore rules back — and `.git/info/exclude` is in no tree, so the rollback
  # cannot reach it either ([30]). Left alone, one planning session would set what
  # the *next* iteration pins as if it were the project's own configuration.
  use_tickets 07-overlaps-alpha
  set_config SOFT_LIMIT_TOKENS 5000
  set_config STERILE_K 1

  script_too_big_then <<'FAKE'
if [ "$n" = 2 ]; then
    # A worktree answers `.git` with a *file*, so the naive `>>.git/info/exclude`
# writes nothing at all and this scenario would stage nothing while reading as
# green. The rule source git really reads is in the **common** git directory,
# which is what a session in any working tree of this repository would find,
# and what the pin looks at since [13].
printf 'rogue/\n' >>"$(git rev-parse --git-common-dir)/info/exclude"
    mkdir -p rogue && printf 'backdoor\n' >rogue/backdoor
    echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.01}'
    exit 0
fi
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.01}'
FAKE

  run_loop
  assert_output_contains "the re-slice session moved the ignore frontier"
  refute_file_contains "$PROJECT_DIR/.git/info/exclude" "rogue/"
  # And what it wrote behind the rule went with the rest of its output: the
  # rollback runs through the pin, so the rule bought no invisibility here either.
  refute_file_exists "$PROJECT_DIR/rogue/backdoor"
}

@test "a plan from a planning session the loop cut short is refused whole" {
  # The twin of "the re-slice session crossed the soft limit too", for the two
  # deadlines of [23] — and the one that needed writing, because a session cut for
  # *time* comes back a success: `claude` traps TERM and exits 0. The planner here
  # writes a plan that would validate perfectly and then hangs. Acting on it would
  # mean creating tickets out of what a session had written *so far*, and the
  # tracker is the one thing no rollback can take back.
  use_tickets 07-overlaps-alpha
  set_config SOFT_LIMIT_TOKENS 5000
  set_config SESSION_STALL_TIMEOUT 2
  set_config STERILE_K 1

  script_too_big_then <<'FAKE'
if [ "$n" = 2 ]; then
    plan="$(printf '%s' "$prompt" | sed -n 's/^Write the plan to \([^,]*\),.*/\1/p' | head -1)"
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
    trap 'echo "{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"num_turns\":2,\"total_cost_usd\":0.01}"; exit 0' TERM
    i=0
    while [ $i -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
    exit 0
fi
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":3,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_failure 4
  assert_output_contains "the re-slice session ran out of time too (stall)"
  assert_output_contains "no re-slice plan came back"

  assert_ticket_status 07-overlaps-alpha ready-for-human
  assert_equal "$(ticket_field 07-overlaps-alpha Escalation)" "too-big"

  # And the split it had already written on disk was not acted on: one ticket in
  # the tracker, the one that was too big.
  run bash -c "ls '$TRACKER_DIR' | awk 'END { print NR }'"
  assert_equal "$output" "1"
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
  >>"$(cat "$RALPH_SHIM_STATE/tracker-dir")/01-alpha.md"
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
    "$(cat "$RALPH_SHIM_STATE/tracker-dir")/02-beta.md"
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
mkdir -p src
printf 'written\n' >src/alpha.txt
cat >"$(cat "$RALPH_SHIM_STATE/tracker-dir")/50-self-served.md" <<'TICKET'
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

@test "a renamed ticket file does not leave two tickets carrying one number" {
  # The composition the two checks above did not cover, and it is permanent when
  # it lands: a rename is a deletion plus an addition, so the restore puts the
  # ticket back and the quarantine keeps the copy — one `NN` on two files, a bare
  # number that resolves to nothing, and every ticket holding `Blocked by: NN`
  # out of the frontier for the rest of the tracker's life ([27]).
  #
  # Only the first session renames. The run has to be able to finish afterwards:
  # 03 depends on 01, so it can only be reached if the number 01 still resolves.
  use_tickets 01-alpha 03-blocked

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
  d="$(cat "$RALPH_SHIM_STATE/tracker-dir")"
  mv "$d/01-alpha.md" "$d/01-alpha-v2.md"
fi
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_success

  # The rename cost the iteration, like any other tracker edit.
  assert_output_contains "the session edited the tracker — restored 1 ticket file(s)"
  assert_file_contains "$FEATURE_DIR/run.log" "tracker-write"

  # The addition is kept — nothing a session wrote is destroyed — under a number
  # nobody else carries, and it is named as having moved.
  refute_file_exists "$TRACKER_DIR/01-alpha-v2.md"
  assert_file_exists "$(ticket_file 04-alpha-v2)"
  assert_ticket_status 04-alpha-v2 ready-for-human
  assert_equal "$(ticket_field 04-alpha-v2 Escalation)" "decision"
  assert_file_contains "$(ticket_file 04-alpha-v2)" "reached the tracker as \`01-alpha-v2\`"
  assert_output_contains "renumbered 01-alpha-v2 -> 04-alpha-v2"

  # And the frontier survives it: 01 still resolves, so 03 is reachable and the
  # run drains it instead of walking past a ticket that left the board in silence.
  assert_file_exists "$(ticket_file 01-alpha)"
  assert_ticket_status 01-alpha resolved
  assert_ticket_status 03-blocked resolved
  assert_file_contains "$PROJECT_DIR/src/gamma.txt" "written"
}

@test "a ticket the session invents on a number already taken moves too" {
  # The same collision without a rename, and the likelier half: nothing stops a
  # session writing a file called `01-anything.md` into the tracker. The repair
  # is keyed on the number, not on git calling something a rename.
  use_tickets 01-alpha 03-blocked

  script_claude <<'FAKE'
#!/usr/bin/env bash
prompt="$(cat)"
mkdir -p src
# Its own ticket's surface, and not 01-alpha's twice: the second iteration would
# otherwise be writing bytes that are already there, which delivers nothing since
# [35] — and used to deliver a `resolved` for a session that had done nothing for
# the ticket it was handed.
for target in $(printf '%s' "$prompt" | sed -n 's/^\*\*Write-surface:\*\* //p' |
  head -1 | tr -d '`\r' | tr ',' ' '); do
  mkdir -p "$(dirname "$target")" && printf 'written\n' >"$target"
done
cat >"$(cat "$RALPH_SHIM_STATE/tracker-dir")/01-self-served.md" <<'TICKET'
# 01 — Self served

**Blocked by:** None

**Write-surface:** `src/anything.txt`

**Status:** ready-for-agent

- [ ] whatever this session felt like doing next
TICKET
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_success

  refute_file_exists "$TRACKER_DIR/01-self-served.md"
  assert_file_exists "$(ticket_file 04-self-served)"
  assert_ticket_status 04-self-served ready-for-human

  # An addition alone is not a failure of its own ([07]), renumbered or not.
  assert_ticket_status 01-alpha resolved
  assert_ticket_status 03-blocked resolved
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
rm -rf "$(cat "$RALPH_SHIM_STATE/tracker-dir")"
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
  "$(cat "$RALPH_SHIM_STATE/tracker-dir")/01-alpha.md"
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
  "$(cat "$RALPH_SHIM_STATE/tracker-dir")/01-alpha.md"
# The *main* index, and it has to be named: a `git add` in the worktree stages
# an index that goes with it, so the guarantee this test names — the tracker
# never leaves in the target project's next commit — would be exercised by
# nothing at all ([13]).
git -C "$(cat "$RALPH_SHIM_STATE/project-dir")" add -A >/dev/null 2>&1
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
  "$(cat "$RALPH_SHIM_STATE/tracker-dir")/07-overlaps-alpha.md"
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
mkdir -p src
printf 'written\n' >src/alpha.txt
cat >"$(cat "$RALPH_SHIM_STATE/tracker-dir")/50-self-served.md" <<'TICKET'
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
cat >"$(cat "$RALPH_SHIM_STATE/tracker-dir")/50-self-served.md" <<'TICKET'
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

# ── two runs on one repository ───────────────────────────────────────────────

@test "a run that lost its lock stops instead of grinding beside another one" {
  # Probed before it was written, and it was alive: a session that deletes the run
  # lock left the run going with exit 0, every ticket resolved, and not a word
  # said. From that point a second `loop.sh` starts — the lock directory is simply
  # gone — and two runs grind one repository, rolling back and committing over
  # each other. The lock lives in the tracker, the one part of the loop's state a
  # session can reach, so nothing else was ever going to notice.
  use_tickets 01-alpha 02-beta

  script_claude <<'FAKE'
#!/usr/bin/env bash
prompt="$(cat)"
surface="$(printf '%s' "$prompt" |
  sed -n 's/^\*\*Write-surface:\*\* //p' | head -1 | tr -d '`\r' | tr ',' ' ')"
for target in $surface; do
  mkdir -p "$(dirname "$target")" && printf 'written\n' >"$target"
done
rm -rf "$(cat "$RALPH_SHIM_STATE/project-dir")/.scratch/demo/.run.lock"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_failure 4
  assert_output_contains "the run lock is gone or not ours any more after 1 iterations"

  # The first iteration is not thrown away — it was gated and committed while the
  # run still held the lock. What stops is everything after it.
  assert_ticket_status 01-alpha resolved
  assert_ticket_status 02-beta ready-for-agent
  assert_equal "$(claude_call_count)" "1"
}

@test "a run that lost the tree lock stops too, though nothing normal can reach it" {
  # The tree lock lives in `.git/`, which is why an `rm -rf .scratch` or a
  # `git clean` cannot touch it. A session that deletes the directory outright
  # still can — and from that point a second `loop.sh` starts on this tree and the
  # two undo each other's work. Out of reach of an accident is not out of reach,
  # so the loop asks the question every iteration, for this lock as for the other.
  use_tickets 01-alpha 02-beta

  script_claude <<'FAKE'
#!/usr/bin/env bash
prompt="$(cat)"
surface="$(printf '%s' "$prompt" |
  sed -n 's/^\*\*Write-surface:\*\* //p' | head -1 | tr -d '`\r' | tr ',' ' ')"
for target in $surface; do
  mkdir -p "$(dirname "$target")" && printf 'written\n' >"$target"
done
rm -rf "$(cat "$RALPH_SHIM_STATE/project-dir")/.git/ralph.tree.lock"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_failure 4
  assert_output_contains "the working-tree lock is gone or not ours any more after 1 iterations"

  # The iteration that ran while the lock was still held is kept, like the run
  # lock's own case: what stops is everything after it.
  assert_ticket_status 01-alpha resolved
  assert_ticket_status 02-beta ready-for-agent
  assert_equal "$(claude_call_count)" "1"
}

@test "a durable commit never overwrites a HEAD it did not read" {
  # The window the lock check cannot cover: between reading HEAD and moving it,
  # another run can commit. Without the old value passed to `update-ref` the move
  # is a plain write, and one run's green iteration vanishes from the history
  # while both report `resolved`. Driven with a git that commits underneath us at
  # exactly that moment — the one way to stand in the window on purpose.
  use_tickets 01-alpha

  cat >"$SHIM_BIN/git" <<'GITSHIM'
#!/usr/bin/env bash
# Transparent, except once: on the commit-tree that precedes the durable commit,
# a concurrent run gets its commit in first.
real() { PATH="${PATH#"$RALPH_SHIM_BIN":}" command git "$@"; }
if [ "$1" = commit-tree ] && [ -f "$RALPH_SHIM_STATE/race-armed" ]; then
  rm -f "$RALPH_SHIM_STATE/race-armed"
  printf 'the other run was here\n' >other-run.txt
  real add -A -- other-run.txt >/dev/null 2>&1
  real -c user.name=other -c user.email=other@test.invalid \
    commit -q -m "another run committed here" >/dev/null 2>&1
fi
exec_real() { real "$@"; }
exec_real "$@"
GITSHIM
  chmod +x "$SHIM_BIN/git"
  export RALPH_SHIM_BIN="$SHIM_BIN"

  script_session_writing src/alpha.txt
  : >"$SHIM_STATE/race-armed"

  run_loop
  assert_failure 4

  # The iteration says it could not be made durable, rather than saying nothing.
  assert_output_contains "could not commit the iteration — it is not durable"

  # What is asserted about the overwrite is what survives [13]: this commit is
  # taken inside the iteration's worktree now, and that worktree is gone by the
  # time a test can look at it — so "the other run's commit is still the tip" is
  # not a question anything can be asked here any more. The refusal itself is the
  # guarantee, and its evidence is that nothing of this iteration reached the
  # history: with the old value dropped from `update-ref` the move is a plain
  # write, it succeeds, and the loop's commit shows up below.
  run git -C "$PROJECT_DIR" log --format='%s'
  refute_output_contains "01-alpha: iteration delivered"
  # The branch's own compare-and-swap — the one that now stands between two runs
  # of this pack — is a different line and has a test of its own, in
  # test/concurrency.bats.
  assert_ticket_status 01-alpha ready-for-agent
}

# ── when git itself says no ──────────────────────────────────────────────────

@test "a commit git refuses stops the run rather than resolving nothing" {
  # The guarantee this test names is the one [13] had to turn round, and it is
  # worth reading as a finding rather than as an edit. [07] wrote "a git that
  # refuses the commit is a warning, not the end of the run: the work is in the
  # tree either way, and the precise rollback does not touch what it did not put
  # there" — true while the iteration ran in the tree the run was started in, and
  # false the moment it runs in a tree that is about to be destroyed. Left alone,
  # a `main.lock` a crashed git forgot would have marked every ticket `resolved`
  # with nothing at all behind it: a whole frontier drained, a clean `exit 0`, and
  # not one line delivered. That is this pack's own definition of a false
  # delivered ([35]), reached through the door next to it.
  use_tickets 01-alpha 02-beta
  script_honest_session

  # What a crashed git leaves behind. Every `update-ref` on the current branch
  # fails from here on, so no iteration can reach it.
  : >"$PROJECT_DIR/.git/refs/heads/main.lock"

  run_loop
  assert_failure 4
  assert_output_contains "could not move the branch — this iteration is not on it"
  assert_output_contains "the gate was green and the work did not reach the branch — stopping"

  # The ticket goes back and pays nothing: the gate was green, so there is nothing
  # wrong with it to bill — the same reasoning [08] applies to a session the
  # subscription refused.
  assert_ticket_status 01-alpha ready-for-agent
  assert_equal "$(ticket_field 01-alpha Failures)" ""
  # And the run stops instead of spending a session per ticket to rediscover it.
  assert_ticket_status 02-beta ready-for-agent
  assert_equal "$(claude_call_count)" "1"
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
