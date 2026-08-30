#!/usr/bin/env bats
#
# Passe transversale du 30/08 — angle (d) ouvert par [09].
#
# Le marqueur est **par arbre** (`<gitdir>/ralph.successor`), la frontière du
# résidu aussi, mais le verrou de run est **par feature**. Deux questions : un
# second run peut-il armer par-dessus, et — celle que l'angle ne nommait pas —
# **quelle feature le successeur broie-t-il ?** La ligne mise en file porte
# `PATH`, `RALPH_CONFIG` et `RALPH_PROJECT_ROOT`. Elle ne porte pas `FEATURE`.
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

sched_marker() { printf '%s/.git/ralph.successor' "$PROJECT_DIR"; }
sched_queued_command() { at_calls | sed -n 's/^command: //p'; }

@test "R4a a run whose FEATURE came from the environment — what the successor grinds" {
  set +e
  # The shipped config is `FEATURE="${FEATURE:-}"`, so `FEATURE=x bash loop.sh`
  # is a working invocation and the one a human uses to grind a second feature
  # of the same tree. The queued line carries three variables and FEATURE is not
  # one of them.
  use_tickets 01-alpha
  set_config USAGE_CACHE_TTL 0
  # Put the shipped form back over the harness injection: env wins, config empty.
  # The injected line has to be *removed*, not overridden — the shipped form is
  # `FEATURE="${FEATURE:-}"`, which re-reads whatever an earlier line already set.
  # Appending it after `FEATURE='demo'` yields `demo` and stages nothing (measured).
  perl -ni -e "print unless /^FEATURE='/" "$RALPH_CONFIG_FILE"
  echo "=== the config's FEATURE line is now: $(grep -n '^FEATURE' "$RALPH_CONFIG_FILE")"
  git -C "$PROJECT_DIR" add -A >/dev/null 2>&1
  git -C "$PROJECT_DIR" commit -q -m "fixture: FEATURE comes from the environment" >/dev/null 2>&1
  usage_respond "$(sched_weekly_wall "$(sched_soon 200000)")"

  run env FEATURE="$RALPH_TEST_FEATURE" bash "$PACK_DIR/loop.sh"
  echo "=== rc=$status at_call_count=$(at_call_count)"
  echo "=== what it told the morning"
  printf '%s\n' "$output" | grep -i 'armed a one-shot successor' || echo "(nothing armed)"
  echo "=== the queued command line"
  sched_queued_command
  echo "=== does it carry FEATURE?"
  sched_queued_command | grep -c 'FEATURE' || echo 0

  # Now run exactly what was queued, the way `at` would: a fresh environment.
  local cmd; cmd="$(sched_queued_command)"
  rm -f "$(sched_marker)"
  rm -rf "$SHIM_STATE/curl.slots" "$SHIM_STATE/claude.calls"
  usage_respond "$(sched_weekly_wall "$(sched_soon 200000)")"
  env -u FEATURE bash -c "$cmd"
  echo "=== the successor exited $?"
  echo "--- what it wrote to successor.log"
  cat "$FEATURE_DIR/successor.log" 2>/dev/null || echo "(no log)"
  echo "--- did it grind anything? claude calls: $(claude_call_count)"
  echo "--- 01-alpha=$(ticket_status 01-alpha)"
  set -e
  false
}

@test "R4b two runs, two features, one tree — who is refused and by what" {
  set +e
  use_tickets 01-alpha
  set_config USAGE_CACHE_TTL 0

  # A second feature of the same tree, with its own tracker.
  mkdir -p "$PROJECT_DIR/.scratch/second/issues"
  cp "$FEATURE_DIR/issues/01-alpha.md" "$PROJECT_DIR/.scratch/second/issues/01-alpha.md"

  # The first run holds the tree lock while it sleeps in a session.
  script_claude <<'FAKE'
#!/usr/bin/env bash
: >"$RALPH_SHIM_STATE/session.started"
printf '%s\n' "$$" >"$RALPH_SHIM_STATE/session.pid"
exec sleep 30
FAKE
  bash "$PACK_DIR/loop.sh" >"$RALPH_TEST_DIR/first.out" 2>&1 &
  local first=$!
  wait_for_file "$SHIM_STATE/session.started" || { echo "no session"; false; }

  run env FEATURE=second bash "$PACK_DIR/loop.sh"
  echo "=== second run rc=$status"
  printf '%s\n' "$output" | head -5

  kill -KILL "$first" 2>/dev/null || true
  wait "$first" 2>/dev/null || true
  kill -KILL "$(cat "$SHIM_STATE/session.pid" 2>/dev/null)" 2>/dev/null || true
  echo "=== so a second feature cannot even start while the first run lives"
  set -e
  false
}

@test "R4c sequentially: feature A armed, feature B hits the same wall" {
  set +e
  # Two features of one tree, one after the other. The wall is the account's,
  # so both meet it. The marker is per tree.
  use_tickets 01-alpha
  set_config USAGE_CACHE_TTL 0
  mkdir -p "$PROJECT_DIR/.scratch/second/issues"
  cp "$FEATURE_DIR/issues/01-alpha.md" "$PROJECT_DIR/.scratch/second/issues/01-alpha.md"
  usage_respond "$(sched_weekly_wall "$(sched_soon 200000)")"

  run_loop
  echo "=== feature A: rc=$status at_call_count=$(at_call_count)"
  echo "--- the queued line names which feature?"
  sched_queued_command | tr ' ' '\n' | grep -i 'config\|loop.sh\|successor.log'

  rm -rf "$SHIM_STATE/curl.slots" "$SHIM_STATE/claude.calls"
  usage_respond "$(sched_weekly_wall "$(sched_soon 200000)")"
  run env FEATURE=second bash "$PACK_DIR/loop.sh"
  echo "=== feature B: rc=$status at_call_count=$(at_call_count)"
  printf '%s\n' "$output" | grep -i 'already armed' || echo "(no refusal line)"
  echo "--- feature B's run.log"
  grep -o 'budget-wall\|successor-armed\|weekly-pause' \
    "$PROJECT_DIR/.scratch/second/run.log" 2>/dev/null | tr '\n' ' '; echo
  echo "--- and feature B's ticket, which nothing will pick up:"
  echo "second/01-alpha = $(sed -n 's/^\*\*Status:\*\* //p' "$PROJECT_DIR/.scratch/second/issues/01-alpha.md" | head -1)"
  set -e
  false
}
