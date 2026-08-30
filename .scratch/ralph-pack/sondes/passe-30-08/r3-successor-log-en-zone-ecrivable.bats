#!/usr/bin/env bats
#
# Passe transversale du 30/08 — angle (c) ouvert par [09].
#
# La ligne mise en file finit par `>>'<feature_dir>/successor.log' 2>&1`. Ce
# chemin est dans `.scratch/<feature>/`, la zone qu'une session atteint depuis
# son worktree (q2 du 27/08 : `git worktree list` mène à l'arbre principal). Et
# cette redirection est **la première chose que le shell du job fait**, avant
# d'exécuter `loop.sh`.
#
# Trois questions : ce que le job fait si la redirection échoue, où sa sortie
# atterrit si le chemin est un lien, et ce que quiconque en apprend.
#
# Instrument, pas test : chaque cas se termine par un `false` volontaire.

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() { harness_setup; }
teardown() { harness_teardown; }

sched_soon() { printf '%s\n' "$(($(date +%s) + ${1:-2}))"; }

sched_weekly_wall() {
  local reset="$1"
  printf '{"five_hour":{"utilization":0.10,"resets_at":%s},' "$(sched_soon 3600)"
  printf '"seven_day":{"utilization":0.85,"resets_at":%s},' "$reset"
  printf '"seven_day_opus":{"utilization":0.01,"resets_at":%s}}\n' "$reset"
}

sched_queued_command() { at_calls | sed -n 's/^command: //p'; }

# Arm one successor and hand back the command line `at` was given.
arm_one() {
  use_tickets 01-alpha
  set_config USAGE_CACHE_TTL 0
  usage_respond "$(sched_weekly_wall "$(sched_soon 200000)")"
  run_loop
  echo "=== armed rc=$status at_call_count=$(at_call_count)"
}

@test "R3a the log path is a directory when the successor wakes" {
  set +e
  arm_one
  local cmd; cmd="$(sched_queued_command)"
  echo "=== queued: $cmd"

  # Exactly what a session leaves by writing a directory over the name — or by
  # what a `mkdir -p` of a path underneath it does by accident.
  rm -f "$FEATURE_DIR/successor.log"
  mkdir -p "$FEATURE_DIR/successor.log"

  # Rearm nothing; just run what was queued, the way `at` would.
  rm -f "$(printf '%s/.git/ralph.successor' "$PROJECT_DIR")"
  rm -rf "$SHIM_STATE/curl.slots" "$SHIM_STATE/claude.calls"
  usage_respond "$(sched_weekly_wall "$(sched_soon 200000)")"
  bash -c "$cmd" >"$RALPH_TEST_DIR/job.out" 2>"$RALPH_TEST_DIR/job.err"
  echo "=== the job exited $?"
  echo "--- what the job wrote to its own stdout (at would mail this)"
  cat "$RALPH_TEST_DIR/job.out"; cat "$RALPH_TEST_DIR/job.err"
  echo "--- did the successor run at all? claude calls: $(claude_call_count) curl calls: $(curl_call_count)"
  echo "--- run.log of the feature after the wake"
  tail -3 "$FEATURE_DIR/run.log" 2>/dev/null || echo "(none)"
  set -e
  false
}

@test "R3b the log path is a symlink into the sealed zone" {
  set +e
  arm_one
  local cmd; cmd="$(sched_queued_command)"

  # `.claude/settings.json` is sealed ([24], [31]): no write-surface may cover
  # it and the gate rolls back any session that touches it. The successor's
  # redirection runs before any gate exists.
  rm -f "$FEATURE_DIR/successor.log"
  ln -s "$PROJECT_DIR/.claude/settings.json" "$FEATURE_DIR/successor.log"
  echo "=== settings.json before: $(wc -c <"$PROJECT_DIR/.claude/settings.json") bytes"

  rm -f "$(printf '%s/.git/ralph.successor' "$PROJECT_DIR")"
  rm -rf "$SHIM_STATE/curl.slots" "$SHIM_STATE/claude.calls"
  usage_respond "$(sched_weekly_wall "$(sched_soon 200000)")"
  bash -c "$cmd"
  echo "=== the job exited $?"
  echo "=== settings.json after: $(wc -c <"$PROJECT_DIR/.claude/settings.json") bytes"
  echo "--- tail of what is now in the sealed file"
  tail -4 "$PROJECT_DIR/.claude/settings.json"
  echo "--- is it still valid json to whoever reads it?"
  head -1 "$PROJECT_DIR/.claude/settings.json"
  set -e
  false
}

@test "R3d end to end: the session plants the symlink, from a green iteration" {
  set +e
  # Not deduced from "the directory is reachable" — measured. The session finds
  # the main tree the way q2 of the 27/08 pass did, and aims at the name the
  # queued line will redirect into. Then the wall goes up and the run arms.
  use_tickets 01-alpha 02-beta
  set_config USAGE_CACHE_TTL 0
  script_claude <<'FAKE'
#!/usr/bin/env bash
prompt="$(cat)"
main="$(git worktree list 2>/dev/null | awk 'NR == 1 { print $1 }')"
feature="$(printf '%s' "$prompt" | sed -n 's/^\*\*Feature:\*\* //p' | head -1 | tr -d '`\r')"
[ -n "$feature" ] || feature=demo
target="$main/.scratch/$feature/successor.log"
rm -f "$target"
ln -s "$main/.claude/settings.json" "$target" 2>/dev/null
printf '%s\n' "$target" >"$RALPH_SHIM_STATE/planted.link"
surface="$(printf '%s' "$prompt" |
  sed -n 's/^\*\*Write-surface:\*\* //p' | head -1 | tr -d '`\r' | tr ',' ' ')"
for t in $surface; do
  mkdir -p "$(dirname "$t")" && printf 'written\n' >"$t"
done
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE
  # First question all clear so an iteration actually runs, then the wall.
  usage_respond '{"five_hour":{"utilization":0.10,"resets_at":'"$(sched_soon 3600)"'},"seven_day":{"utilization":0.05,"resets_at":'"$(sched_soon 3600)"'},"seven_day_opus":{"utilization":0.01,"resets_at":'"$(sched_soon 3600)"'}}' \
    "$(sched_weekly_wall "$(sched_soon 200000)")"

  run_loop
  echo "=== rc=$status 01-alpha=$(ticket_status 01-alpha) at_call_count=$(at_call_count)"
  echo "=== the iteration's verdict"
  printf '%s\n' "$output" | grep -i 'gate: 01-alpha' || echo "(no gate line)"
  echo "=== what the session aimed at: $(cat "$SHIM_STATE/planted.link" 2>/dev/null || echo '(nothing)')"
  echo "=== is successor.log a symlink in the main tree now?"
  ls -l "$FEATURE_DIR/successor.log" 2>/dev/null || echo "(not there)"
  echo "=== settings.json before the successor wakes: $(wc -c <"$PROJECT_DIR/.claude/settings.json") bytes"

  local cmd; cmd="$(sched_queued_command)"
  rm -f "$(printf '%s/.git/ralph.successor' "$PROJECT_DIR")"
  rm -f "$SHIM_STATE/claude.script"
  rm -rf "$SHIM_STATE/curl.slots" "$SHIM_STATE/claude.calls"
  usage_respond "$(sched_weekly_wall "$(sched_soon 200000)")"
  bash -c "$cmd"
  echo "=== the successor exited $?"
  echo "=== settings.json after: $(wc -c <"$PROJECT_DIR/.claude/settings.json") bytes"
  tail -2 "$PROJECT_DIR/.claude/settings.json"
  set -e
  false
}

@test "R3c who ever learns the successor did not start" {
  set +e
  arm_one
  echo "=== what the arming run said it did"
  printf '%s\n' "$output" | grep -i 'armed a one-shot successor\|submission and not a promise' || echo "(nothing)"
  echo "=== what run.log recorded"
  grep -o 'budget-wall\|successor-armed\|weekly-pause' "$FEATURE_DIR/run.log" | tr '\n' ' '; echo
  echo "=== the marker says armed at:"
  cat "$(printf '%s/.git/ralph.successor' "$PROJECT_DIR")"
  echo "=== does anything in the pack ever come back and check?"
  grep -rn 'successor' "$PACK_DIR/loop.sh" | grep -vi 'arm_successor\|# ' | head
  echo "(the question is whether any later run reads the marker for anything but refusing to arm)"
  set -e
  false
}
