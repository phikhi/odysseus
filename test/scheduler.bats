#!/usr/bin/env bats
#
# The one-shot successor ([09]).
#
# A weekly window resets days out, so the run stops (`exit 6`) and arms something
# that will start a *fresh* run at the reset. Four things every test here has to
# keep honest, and each of them is a way this feature turns into a lie:
#
#   - **arming is not running.** `at` answers for its queue and not for the job,
#     and macOS ships `atrun` disabled. A test that asserted "a successor was
#     armed" and nothing else would be asserting the thing the pack cannot
#     promise; what is asserted is the submission, its instant, and the sentence
#     that says what the mechanism cannot vouch for.
#   - **the instant is the reset, never an arithmetic +7 days**, and never one
#     nothing measured. `exit 6` has two causes and only one of them carries an
#     instant ([08]).
#   - **a successor inherits nothing.** That is the decision this ticket owed
#     [14], [15] and [46], and the assertion for it is on the queued command
#     line: anything not on it is something a successor does not get.
#   - **two successors are two runs racing for one tree lock.** The marker is the
#     fence, the lock is the net, and the net is tested by running the queued
#     command against a held lock.
#
# The platform half is tested as a pure function on both names rather than on
# whichever machine runs the suite: the ordering *is* the guarantee, and a
# guarantee tested on one of the two platforms is tested on half of them.

load helpers/harness
load helpers/assert

setup() {
  harness_setup
}

teardown() {
  harness_teardown
}

# An instant N seconds from now, as an epoch.
sched_soon() {
  printf '%s\n' "$(($(date +%s) + ${1:-2}))"
}

# The stamp `at -t` is given for an epoch, computed the way the pack computes it:
# rounded up to the whole minute, in local time. Spelled out here rather than
# asked of the pack — a test that reused `scheduler__stamp` could not catch it
# rounding *down*, which is the one direction that wakes a run into the same wall.
sched_at_stamp() {
  local up=$((($1 + 59) / 60 * 60))
  date -r "$up" +%Y%m%d%H%M 2>/dev/null && return 0
  date -d "@$up" +%Y%m%d%H%M 2>/dev/null && return 0
  return 1
}

# A usage payload whose weekly window is over the shipped threshold (0.80).
sched_weekly_wall() {
  local reset="$1"
  printf '{"five_hour":{"utilization":0.10,"resets_at":%s},' "$(sched_soon 3600)"
  printf '"seven_day":{"utilization":0.85,"resets_at":%s},' "$reset"
  printf '"seven_day_opus":{"utilization":0.01,"resets_at":%s}}\n' "$reset"
}

# And one with room in every window, for a run that has to reach its second
# decision before the wall goes up.
sched_all_clear() {
  local reset
  reset="$(sched_soon 3600)"
  printf '{"five_hour":{"utilization":0.10,"resets_at":%s},' "$reset"
  printf '"seven_day":{"utilization":0.05,"resets_at":%s},' "$reset"
  printf '"seven_day_opus":{"utilization":0.01,"resets_at":%s}}\n' "$reset"
}

# The command line the successor would run, out of what the shim recorded.
sched_queued_command() {
  at_calls | sed -n 's/^command: //p'
}

# Where the singleton marker lives. Spelled out rather than asked of the pack,
# for the reason `tree_lock_dir` is: a test that asked would not catch the marker
# moving into the tree, where a session writes.
sched_marker() {
  printf '%s/.git/ralph.successor' "$PROJECT_DIR"
}

# ── the chain, ordered by reboot survival ────────────────────────────────────

@test "the chain tries the queue that survives a reboot before the timer that does not" {
  # A weekly reset is days out, so the wait can cross a restart. `at` spools to
  # disk; a transient systemd-run timer lives in /run, which is tmpfs. The order
  # is the guarantee — reversed, the feature still "works" every night nobody
  # reboots, which is the shape of a bug nobody finds.
  pack_run 'scheduler_candidates Linux'
  assert_success
  assert_equal "$output" "at
systemd-run"
}

@test "macOS has no systemd, and the chain is one long there" {
  pack_run 'scheduler_candidates Darwin'
  assert_success
  assert_equal "$output" "at"
}

@test "the cloud schedule skill is in no chain, on either platform" {
  # It is a routine on Anthropic infrastructure: claude.ai login rather than an
  # API key, refused when telemetry is off, and no access to this repository.
  # Neither platform may reach it by falling through.
  pack_run 'scheduler_candidates Linux; scheduler_candidates Darwin'
  assert_success
  refute_output_contains "schedule"
  refute_output_contains "routines"
}

@test "asking for the cloud skill by name is refused with the reason, not read as none" {
  use_tickets 01-alpha
  set_config SCHEDULER schedule

  run_loop
  assert_failure 2
  assert_output_contains "needs a claude.ai login rather than an API key"
  assert_equal "$(claude_call_count)" "0"
}

@test "a mechanism this machine does not have is not in the chain" {
  # The candidate list is what the platform *could* use; the chain is what this
  # box has. Probed by taking `at` away rather than by counting on some machine
  # not having systemd — the suite runs on both platforms.
  pack_run 'scheduler_chain Darwin'
  assert_success
  assert_equal "$output" "at"

  pack_run '(PATH=/nonexistent; scheduler_chain Darwin); printf "(end)\n"'
  assert_success
  assert_equal "$output" "(end)"
}

@test "naming one mechanism uses that one or nothing, never the next one down" {
  # A project that asked for `at` and silently got a transient timer has been told
  # the wrong thing about whether its night survives a reboot.
  set_config SCHEDULER systemd-run
  pack_run 'scheduler_candidates Linux'
  assert_success
  assert_equal "$output" "systemd-run"
}

@test "SCHEDULER=none is a declaration and empties the chain" {
  set_config SCHEDULER none
  pack_run 'scheduler_candidates Linux; printf "(end)\n"'
  assert_success
  assert_equal "$output" "(end)"
}

# ── the instant ──────────────────────────────────────────────────────────────

@test "a weekly wall arms exactly one successor, at the reset rounded up to the minute" {
  # The reset is deliberately 30 s past a whole minute. `at` takes whole minutes,
  # so rounding down and rounding up differ here on every run of this test — with
  # a reset taken straight off the clock they would agree one time in sixty, and
  # the mutation that rounds down would report `ok` fifty-nine times and lie once.
  # Rounding down is the one direction that wakes a run *before* the wall lifts.
  use_tickets 01-alpha
  reset="$(((($(date +%s) + 200000) / 60) * 60 + 30))"
  usage_respond "$(sched_weekly_wall "$reset")"

  run_loop
  assert_failure 6
  assert_output_contains "armed a one-shot successor with at"
  assert_equal "$(at_call_count)" "1"

  calls="$(at_calls)"
  printf '%s' "$calls" | grep -q "argv: -t $(sched_at_stamp "$reset")" ||
    fail "the successor was not queued at the reset: $calls"
  assert_ticket_status 01-alpha ready-for-agent
  assert_file_contains "$FEATURE_DIR/run.log" "successor-armed"
}

@test "the deadline is never a computed week: a reset further out than its window is refused" {
  # "never +7 days" is a ceiling each window carries, not a clamp on arithmetic.
  # A seven_day reset nine days out is a clock or an endpoint this run cannot
  # believe, and arming on it would be arming on nothing.
  pack_run 'scheduler_deadline seven_day '"$(sched_soon 800000)"' endpoint ||
    printf "%s\n" "$RALPH_SUCCESSOR_WHY"'
  assert_success
  assert_output_contains "further than a seven_day window can reset"
}

@test "a five-hour window is held to five hours, not to seven days" {
  # The witness for the line above: without a per-window ceiling both windows
  # would share the widest one, and that test would still pass.
  pack_run 'scheduler_deadline five_hour '"$(sched_soon 100000)"' endpoint ||
    printf "%s\n" "$RALPH_SUCCESSOR_WHY"'
  assert_success
  assert_output_contains "further than a five_hour window can reset"

  pack_run 'scheduler_deadline five_hour '"$(sched_soon 3600)"' endpoint &&
    printf "at=%s\n" "$RALPH_SUCCESSOR_AT"'
  assert_success
  assert_output_contains "at="
}

@test "a reset nothing measured arms nothing, on the same exit code" {
  # `exit 6` has two causes ([08]) and only one of them carries an instant. A
  # successor armed on the empty field would be armed at the epoch 0 — [27]'s
  # fallback that disarms itself, in its exact shape.
  pack_run 'scheduler_deadline seven_day "" endpoint ||
    printf "%s\n" "$RALPH_SUCCESSOR_WHY"'
  assert_success
  assert_output_contains "not an instant anything measured"

  pack_run 'scheduler_deadline seven_day "in a week" endpoint ||
    printf "%s\n" "$RALPH_SUCCESSOR_WHY"'
  assert_success
  assert_output_contains "not an instant anything measured"
}

@test "the run that could not read its own reset stops without queuing anything" {
  # The end-to-end half of the test above: the session window is blocked, its
  # reset is beyond what this run may sleep to, and the endpoint gave an instant
  # nothing can parse. Same exit 6, nothing armed.
  use_tickets 01-alpha
  set_config BUDGET_MAX_PAUSE 3
  usage_respond '{"five_hour":{"utilization":0.99,"resets_at":"not an instant"},"seven_day":{"utilization":0.05,"resets_at":0}}'

  run_loop
  assert_failure 6
  assert_output_contains "not an instant this run can wait for"
  assert_equal "$(at_call_count)" "0"
  assert_file_contains "$FEATURE_DIR/run.log" "weekly-pause"
}

@test "a reset in the past is refused, or a woken run would arm another one" {
  pack_run 'scheduler_deadline seven_day '"$(($(date +%s) - 60))"' endpoint ||
    printf "%s\n" "$RALPH_SUCCESSOR_WHY"'
  assert_success
  assert_output_contains "is not in the future"
}

@test "a window this pack cannot price is refused rather than given the widest one" {
  pack_run 'scheduler_deadline three_hour '"$(sched_soon 600)"' endpoint ||
    printf "%s\n" "$RALPH_SUCCESSOR_WHY"'
  assert_success
  assert_output_contains "not a window this pack knows how to price"
}

@test "an instant a session wrote buys no more than a pause would" {
  # `stream` means the reset came out of a session's own stream, which is a file
  # that session writes ([08], [23]). A forged one is worth BUDGET_MAX_PAUSE for a
  # pause today; it must not be worth a successor days out.
  reset="$(sched_soon 200000)"

  pack_run 'scheduler_deadline seven_day '"$reset"' stream ||
    printf "%s\n" "$RALPH_SUCCESSOR_WHY"'
  assert_success
  assert_output_contains "further than BUDGET_MAX_PAUSE"

  # The paired witness: the same instant from the endpoint is armable, so what
  # the test above measures is the source and not the span.
  pack_run 'scheduler_deadline seven_day '"$reset"' endpoint &&
    printf "at=%s\n" "$RALPH_SUCCESSOR_AT"'
  assert_success
  assert_output_contains "at=$reset"
}

# ── the human fallback ───────────────────────────────────────────────────────

@test "with no scheduler on the machine the run stops on the wall and says a human resumes it" {
  use_tickets 01-alpha
  set_config SCHEDULER none
  usage_respond "$(sched_weekly_wall "$(sched_soon 200000)")"

  run_loop
  assert_failure 6
  assert_output_contains "no one-shot scheduler on this machine"
  assert_output_contains "a human resumes it"
  assert_equal "$(at_call_count)" "0"
  assert_file_contains "$FEATURE_DIR/run.log" "weekly-pause"
  assert_ticket_status 01-alpha ready-for-agent
}

@test "a project that resumes weekly walls by hand is never scheduled for" {
  use_tickets 01-alpha
  set_config WEEKLY_RESUME human
  usage_respond "$(sched_weekly_wall "$(sched_soon 200000)")"

  run_loop
  assert_failure 6
  assert_output_contains "this project resumes a weekly wall by hand"
  assert_equal "$(at_call_count)" "0"
}

@test "a scheduler that refuses the submission is a fallback, not a silent success" {
  # Pinned to `at`, and not out of tidiness: on a Linux box that really has
  # systemd the chain would fall through and this test would arm a live transient
  # timer on the machine running the suite.
  use_tickets 01-alpha
  set_config SCHEDULER at
  at_exit 1
  usage_respond "$(sched_weekly_wall "$(sched_soon 200000)")"

  run_loop
  assert_failure 6
  assert_output_contains "at would not take the successor"
  assert_output_contains "every one-shot scheduler on this machine refused"
  refute_output_contains "armed a one-shot successor"
  assert_file_contains "$FEATURE_DIR/run.log" "weekly-pause"
  refute_file_exists "$(sched_marker)"
}

@test "arming says what the mechanism cannot promise" {
  # `at` answers for its queue and never for the job: POSIX says the status is the
  # submission's, and on macOS `atrun` ships disabled. A line that said "armed"
  # and stopped there would be read as "it will run".
  use_tickets 01-alpha
  usage_respond "$(sched_weekly_wall "$(sched_soon 200000)")"

  run_loop
  assert_failure 6
  assert_output_contains "that is a submission and not a promise"
}

# ── what a successor inherits, and it is nothing ─────────────────────────────

@test "the queued command is the loop and three variables, and names nothing of this run" {
  # The decision this ticket owed [14], [15] and [46]: a successor is a new run.
  # Handing it a baseline would mean a file, and a queued command line is readable
  # by anything running as this user (`at -c`), so the name of that file would be a
  # name a session can learn ([40]).
  use_tickets 01-alpha
  usage_respond "$(sched_weekly_wall "$(sched_soon 200000)")"

  run_loop
  assert_failure 6

  cmd="$(sched_queued_command)"
  printf '%s' "$cmd" | grep -q "loop.sh" || fail "the successor does not run the loop: $cmd"
  printf '%s' "$cmd" | grep -q "RALPH_CONFIG=" || fail "no config on the line: $cmd"
  printf '%s' "$cmd" | grep -q "PATH=" || fail "no PATH on the line: $cmd"
  # Nothing of this run's workspaces: the lesson index copy ([14]), the tracker
  # register ([40]), the frontier witness ([41]) all live under names in $TMPDIR
  # this shell holds and never hands out.
  printf '%s' "$cmd" | grep -q "ralph-retro\|ralph-slot\|ralph-frontier\|ralph-ignore" &&
    fail "the successor was handed one of this run's own secrets: $cmd"
  assert_output_contains "it is a new run and inherits nothing from this one"
}

@test "the queued job's output lands beside the run journal, not in a mail nobody has" {
  # `at` mails a job's output; a headless box with no MTA loses it silently. This
  # is piège n°4 of the scheduling research, and it costs the whole point of the
  # feature — a successor that ran and left no trace is a night nobody can read.
  use_tickets 01-alpha
  usage_respond "$(sched_weekly_wall "$(sched_soon 200000)")"

  run_loop
  assert_failure 6

  cmd="$(sched_queued_command)"
  printf '%s' "$cmd" | grep -q "successor.log" || fail "no log on the line: $cmd"
  printf '%s' "$cmd" | grep -q "2>&1" || fail "stderr is not captured: $cmd"
}

# ── the singleton, and the lock behind it ────────────────────────────────────

@test "the successor takes the run lock like any other run" {
  # The net behind the marker, and it is asserted by running the queued command
  # rather than by reading it: a successor that bypassed the lock would look
  # exactly the same on the line.
  use_tickets 01-alpha
  usage_respond "$(sched_weekly_wall "$(sched_soon 200000)")"

  run_loop
  assert_failure 6
  cmd="$(sched_queued_command)"

  # A live holder: this bats process, which is very much alive.
  mkdir -p "$(run_lock_dir)"
  printf '%s\n' "$$" >"$(run_lock_dir)/pid"

  run bash -c "$cmd"
  assert_failure 1
  run cat "$FEATURE_DIR/successor.log"
  assert_output_contains "another run already holds"
}

@test "a successor already armed for this tree is not armed a second time" {
  use_tickets 01-alpha
  printf '%s\tat\t2026-08-29T00:00:00Z\n' "$(sched_soon 100000)" >"$(sched_marker)"
  usage_respond "$(sched_weekly_wall "$(sched_soon 200000)")"

  run_loop
  assert_failure 6
  assert_output_contains "one is already armed for this working tree"
  assert_equal "$(at_call_count)" "0"
  assert_file_contains "$FEATURE_DIR/run.log" "weekly-pause"
}

@test "a marker whose instant has passed is not a successor" {
  # The paired witness for the test above: a check that refused on the mere
  # presence of the file would wedge every run after the first weekly wall, for
  # ever, and would pass that test too.
  use_tickets 01-alpha
  reset="$(sched_soon 200000)"
  printf '%s\tat\t2026-08-29T00:00:00Z\n' "$(($(date +%s) - 100))" >"$(sched_marker)"
  usage_respond "$(sched_weekly_wall "$reset")"

  run_loop
  assert_failure 6
  assert_equal "$(at_call_count)" "1"
  assert_file_contains "$(sched_marker)" "$reset"
}

@test "the marker lands out of reach of a git add -A and of an rm -rf .scratch" {
  use_tickets 01-alpha
  usage_respond "$(sched_weekly_wall "$(sched_soon 200000)")"

  run_loop
  assert_failure 6
  assert_file_exists "$(sched_marker)"
  run git -C "$PROJECT_DIR" status --porcelain
  refute_output_contains "ralph.successor"
}

# ── the residue a fresh run would adopt ──────────────────────────────────────

@test "a configuration source this run could not put back is named as a residue" {
  # `gate_frontier_residue` is the run-level question the successor rests on:
  # what is not where this run found it, after every restore that could fire has
  # fired.
  pack_run '
    cd "$(ralph_project_root)"
    RALPH_FRONTIER_COMMON="$(gate_frontier_common)"
    export RALPH_FRONTIER_COMMON
    gate_frontier_residue && printf "(moved before)\n"
    git config core.fsmonitor "touch /tmp/ralph-probe"
    gate_frontier_residue || printf "(nothing moved)\n"
    rm -rf "$RALPH_FRONTIER_COMMON"'
  assert_success
  refute_output_contains "(moved before)"
  assert_output_contains "core.fsmonitor"
}

@test "a run leaving that residue arms nothing, whatever the instant says" {
  # A fresh run pins the configuration it finds as its own baseline, so a
  # successor would take a session's `core.fsmonitor` as the project's own and
  # run it on every index refresh, all night, without a word. The human this
  # successor replaces is the one who would have read the receipt.
  pack_run '
    residue="$(printf "cfg\tcore.fsmonitor\n")"
    scheduler_arm seven_day '"$(sched_soon 200000)"' endpoint "$residue" ||
      printf "(not armed)\n"'
  assert_success
  assert_output_contains "core.fsmonitor"
  assert_output_contains "could not put it back"
  assert_output_contains "(not armed)"
  assert_equal "$(at_call_count)" "0"

  # The paired witness: the same instant with nothing left behind is armed, so
  # what the assertions above measure is the residue and not the guards under it.
  pack_run 'scheduler_arm seven_day '"$(sched_soon 200000)"' endpoint ""'
  assert_success
  assert_output_contains "armed a one-shot successor"
  assert_equal "$(at_call_count)" "1"
}

@test "a real run that leaves one behind queues nothing for the morning" {
  # The end-to-end half, and it is the one that covers the wiring: a session sets
  # a git configuration key in the operator's own config, which the restore cannot
  # reach — an `unset` writes *this repository* ([46]) — so the run stays red over
  # it, and then the weekly wall goes up. Without the pilot handing the residue to
  # the scheduler, a successor would be queued here and would pin that key as the
  # project's own.
  #
  # `help.browser` because it is on the criterion's list and nothing in this pack
  # ever runs it: a probe that armed `core.fsmonitor` for real would have git
  # executing it on every index refresh of the test suite.
  use_tickets 01-alpha
  set_config USAGE_CACHE_TTL 0
  set_config STERILE_K 5
  usage_respond "$(sched_all_clear)" "$(sched_weekly_wall "$(sched_soon 200000)")"

  script_claude <<'FAKE'
#!/usr/bin/env bash
cat >/dev/null
git config --global help.browser "xdg-open"
printf 'alpha\n' >src/alpha.txt
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_failure 6
  assert_output_contains "this run is leaving help.browser somewhere it did not find it"
  assert_output_contains "a human has to look first"
  assert_equal "$(at_call_count)" "0"
  assert_file_contains "$FEATURE_DIR/run.log" "weekly-pause"
}

# ── the preflight ────────────────────────────────────────────────────────────

@test "a SCHEDULER outside the set is refused, not read as no mechanism at all" {
  use_tickets 01-alpha
  set_config SCHEDULER cron

  run_loop
  assert_failure 2
  assert_output_contains "it has to be auto, at, systemd-run or none"
  assert_equal "$(claude_call_count)" "0"
}

@test "a WEEKLY_RESUME outside the set is refused, not read as human" {
  use_tickets 01-alpha
  set_config WEEKLY_RESUME yes

  run_loop
  assert_failure 2
  assert_output_contains "it has to be schedule or human"
  assert_equal "$(claude_call_count)" "0"
}
