#!/usr/bin/env bats
#
# The hostile canary: one run, three iterations, against the world as it is
# rather than as the fixtures wish it were.
#
# Every defect this pack has shipped so far lived in the gap between the
# cooperative fake the rest of the suite drives — writes nothing, commits
# nothing, emits three perfect lines at once, finishes instantly — and a real
# session. So this file drives the opposite: sessions that actually write their
# write-surface, one that commits everything it touched, one whose stream
# arrives in pieces with a line cut in half, over a tracker that is dirty,
# CRLF-encoded and already carrying someone else's claim.
#
# It is a canary, not a unit test: when it goes red, something about the way the
# pack meets reality just changed. Read it before touching the assertions.

load helpers/harness
load helpers/assert

setup() {
  harness_setup
}

teardown() {
  harness_teardown
}

# A session that reads its own ticket, writes exactly the files the ticket
# declared, and reports success — the honest behaviour the pack asks for. Its
# stream is emitted differently on each call, so one run covers three shapes.
script_honest_session() {
  script_claude <<'FAKE'
#!/usr/bin/env bash
prompt="$(cat)"
n="$(cat "$RALPH_SHIM_STATE/canary-seq" 2>/dev/null || echo 0)"
n=$((n + 1))
printf '%s\n' "$n" >"$RALPH_SHIM_STATE/canary-seq"

# Read the way any sane reader would, carriage returns included: a session
# handed a CRLF ticket writes `src/beta.txt`, not `src/beta.txt\r`.
surface="$(printf '%s' "$prompt" |
  sed -n 's/^\*\*Write-surface:\*\* //p' | head -1 | tr -d '`\r' | tr ',' ' ')"
for target in $surface; do
  mkdir -p "$(dirname "$target")"
  printf 'written by the session\n' >"$target"
done

echo '{"type":"system","subtype":"init","session_id":"s","model":"test-model"}'

case "$n" in
  1)
    # The plain case, plus enough volume to exercise reading a stream that is
    # still being appended to.
    i=0
    while [ $i -lt 200 ]; do
      printf '{"type":"user","message":{"content":[{"type":"tool_result","content":"line %s"}]}}\n' "$i"
      i=$((i + 1))
    done
    echo '{"type":"assistant","message":{"role":"assistant","usage":{"input_tokens":1200,"cache_creation_input_tokens":0,"cache_read_input_tokens":18000,"output_tokens":300}}}'
    ;;
  2)
    # An agent that commits its work — including, if nothing stops it, the
    # tracker in the middle of its own claim.
    git add -A >/dev/null 2>&1
    git commit -q -m "session: work on iteration 2" >/dev/null 2>&1
    echo '{"type":"assistant","message":{"role":"assistant","usage":{"input_tokens":900,"cache_read_input_tokens":9000,"output_tokens":100}}}'
    ;;
  *)
    # A usage event cut in half, with a pause: a monitor tick lands mid-write.
    printf '{"type":"assistant","message":{"role":"assistant","usage":{"input_tokens":50,"cache_read'
    sleep 0.3
    printf '_input_tokens":700,"output_tokens":25}}}\n'
    ;;
esac

echo '{"type":"result","subtype":"success","is_error":false,"result":"done","num_turns":4,"total_cost_usd":0.03,"usage":{"input_tokens":100,"output_tokens":10,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}'
FAKE
}

# The tracker as a real project hands it over: one ticket saved with DOS line
# endings, one claimed by a process that is not this run, and a working tree
# that was already dirty when the run started.
seed_hostile_world() {
  use_tickets 01-alpha 02-beta 03-blocked 04-claimed

  perl -pi -e 's/\n/\r\n/' "$(ticket_file 02-beta)"
  harness__commit "test: a tracker written the DOS way"

  mkdir -p "$PROJECT_DIR/src"
  printf 'someone else was here\n' >"$PROJECT_DIR/wip.txt"
  printf '\nan edit nobody committed\n' >>"$PROJECT_DIR/CONTEXT.md"
}

@test "the canary: three iterations against a hostile world, all resolved" {
  seed_hostile_world
  script_honest_session

  run_loop
  assert_success
  assert_output_contains "frontier empty after 3 iterations"

  # Every ticket the run could grind, ground — including the CRLF one, and
  # including the one that only became eligible when 01 resolved.
  assert_ticket_status 01-alpha resolved
  assert_ticket_status 02-beta resolved
  assert_ticket_status 03-blocked resolved

  # Nobody else's claim was touched.
  assert_ticket_status 04-claimed claimed

  # The work is really there, all three of it: an iteration must not be charged
  # with what the previous one left in the tree.
  assert_file_contains "$PROJECT_DIR/src/alpha.txt" "written by the session"
  assert_file_contains "$PROJECT_DIR/src/beta.txt" "written by the session"
  assert_file_contains "$PROJECT_DIR/src/gamma.txt" "written by the session"

  # Three green gates, no scope-guard casualty.
  run bash -c "grep -c 'scope=green' <<'OUT'
$output
OUT"
  assert_equal "$output" "3"
  refute_output_contains "scope=red"
  refute_output_contains "gate-red"
}

@test "the canary: an overflow is not absolved by having already failed once" {
  # The hole this test was written for: with nothing putting the tree back after
  # a red gate, a second attempt on the same ticket started from a baseline that
  # already contained the overflow. Write the very same violation twice and the
  # scope-guard saw no change at all, and said green — ticket resolved, rogue
  # file still there, exit 0. A session could beat the guard by failing once.
  #
  # What closes it is the rollback: every attempt is judged against the same
  # baseline, because every failed attempt is undone before the next one starts.
  use_tickets 01-alpha
  set_config STERILE_K 3

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src
printf 'alpha\n' >src/alpha.txt
printf 'rogue\n' >src/rogue.txt
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_failure 4

  # Three attempts, three red scope-guards. Not two reds and a green.
  run bash -c "grep -c 'scope=red' <<'OUT'
$output
OUT"
  assert_equal "$output" "3"

  # Two fresh retries, then the human sink — and never a resolution.
  assert_ticket_status 01-alpha ready-for-human
  assert_equal "$(ticket_field 01-alpha Failures)" "3"
  run bash -c "grep -c resolved '$FEATURE_DIR/run.log' || true"
  assert_equal "$output" "0"

  # The tree the next run inherits carries nothing of the three attempts.
  refute_file_exists "$PROJECT_DIR/src/rogue.txt"
  refute_file_exists "$PROJECT_DIR/src/alpha.txt"
}

@test "the canary: a session cannot widen its own write-surface" {
  # A known hole, kept visible rather than forgotten. The scope-guard reads the
  # write-surface off the disk at gate time — after the session — and three
  # mechanisms agree to hide what a session writes inside the tracker: the guard
  # drops `.scratch/<feature>/` as the loop's own bookkeeping ([05], rightly: the
  # claim and the journal live there), the rollback leaves the same prefix alone
  # ([07], rightly: otherwise the retry counter resets every attempt), and the
  # quarantine compares ids, so it sees a ticket created and not one edited.
  #
  # Reproduced, in this exact scenario: `scope=green`, ticket `resolved`, exit 0,
  # rogue file still in the tree and CONTEXT.md edited. A false green with a
  # mechanism. Un-skipping this test is [21]'s acceptance criterion.
  skip "closed by [21] tracker-inviolable: nothing guards the tracker from a session"

  use_tickets 01-alpha
  set_config STERILE_K 1

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src
printf 'written\n' >src/alpha.txt
printf 'written\n' >src/rogue.txt
printf 'written\n' >>CONTEXT.md
perl -pi -e 's/^\*\*Write-surface:\*\* .*/**Write-surface:** `*`/' \
  .scratch/demo/issues/01-alpha.md
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_failure 4

  # Judged against the surface the ticket declared when the session started.
  assert_output_contains "scope=red"
  assert_output_contains "src/rogue.txt"

  # The edit itself is undone, and the iteration resolves nothing.
  assert_equal "$(ticket_field 01-alpha Write-surface)" '`src/alpha.txt`'
  assert_ticket_status 01-alpha ready-for-agent
  refute_file_exists "$PROJECT_DIR/src/rogue.txt"
}

@test "the canary: the journal tells the truth about the run" {
  seed_hostile_world
  script_honest_session

  run_loop
  assert_success

  journal="$FEATURE_DIR/run.log"
  run bash -c "awk 'END { print NR }' '$journal'"
  assert_equal "$output" "3"

  run bash -c "grep -c resolved '$journal'"
  assert_equal "$output" "3"

  # Peak context is the whole window, cache included: 1200 + 18000 + 300.
  assert_file_contains "$journal" "tokens=19500"
  assert_file_contains "$journal" "turns=4"
}

@test "the canary: the run leaves nothing of its own behind" {
  seed_hostile_world
  script_honest_session

  run_loop
  assert_success

  run bash -c "ls -a '$FEATURE_DIR' | grep -E '\.session\.|\.tokens' || true"
  assert_equal "$output" ""
  [ ! -d "$(run_lock_dir)" ] || fail "the lock survived the run"

  # And it did not tidy up after anyone else: the work in progress that was
  # already in the tree is still exactly as it was.
  assert_file_contains "$PROJECT_DIR/wip.txt" "someone else was here"
  assert_file_contains "$PROJECT_DIR/CONTEXT.md" "an edit nobody committed"
}
