#!/usr/bin/env bats
#
# Passe transversale du 27/08 — angle 1 de [47].
#
# Un répertoire de garde (`.scratch/<feature>/.open.guard`) apparaît maintenant
# pendant un run, à côté du verrou de run. Trois questions jamais posées :
# qui le voit pendant le run, qui le compte quand un run est tué dessus, et
# qu'en dit l'énumération de la zone ignorée quand le projet ignore `.scratch/`.
#
# Instrument, pas test : se termine par un `false` volontaire.

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() { harness_setup; }
teardown() { harness_teardown; }

deliver_normally() {
  script_claude <<'FAKE'
#!/usr/bin/env bash
prompt="$(cat)"
surface="$(printf '%s' "$prompt" |
  sed -n 's/^\*\*Write-surface:\*\* //p' | head -1 | tr -d '`\r' | tr ',' ' ')"
for target in $surface; do
  mkdir -p "$(dirname "$target")" && printf 'written\n' >"$target"
done
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE
}

@test "Q1a a ticket-open guard left by a killed run — who names it, who sweeps it" {
  use_tickets 01-alpha 02-beta
  set_config STERILE_K 5

  # Exactly what a `kill -9` between the mkdir and the release leaves behind.
  mkdir -p "$FEATURE_DIR/.open.guard"
  printf '999999\n' >"$FEATURE_DIR/.open.guard/pid"
  printf '2026-08-01T00:00:00Z\n' >"$FEATURE_DIR/.open.guard/since"
  printf 'ralph-pack\n' >"$FEATURE_DIR/.open.guard/note"

  deliver_normally
  run_loop
  echo "=== rc=$status 01-alpha=$(ticket_status 01-alpha) 02-beta=$(ticket_status 02-beta)"

  echo "=== anything on stdout about a guard or a leftover?"
  printf '%s\n' "$output" | grep -i 'guard\|leftover\|still in\|earlier runs' || echo "(nothing)"

  echo "=== run.log"
  cat "$FEATURE_DIR/run.log" 2>/dev/null || echo "(none)"

  echo "=== any receipt naming it?"
  grep -rl 'open.guard\|ticket-open' "$PROJECT_DIR/receipts" 2>/dev/null || echo "(no receipt names it)"

  echo "=== is it still there after a green run?"
  if [ -d "$FEATURE_DIR/.open.guard" ]; then
    echo "yes: pid=$(cat "$FEATURE_DIR/.open.guard/pid") since=$(cat "$FEATURE_DIR/.open.guard/since")"
  else
    echo "no"
  fi

  echo "=== and what the run lock did, for comparison"
  ls -d "$FEATURE_DIR/.run.lock" 2>/dev/null || echo "(run lock released)"
  false
}

@test "Q1b with .scratch/ ignored, does the zone line name the guard?" {
  use_tickets 01-alpha
  set_config STERILE_K 5
  printf '.scratch/\n' >"$PROJECT_DIR/.gitignore"
  git -C "$PROJECT_DIR" add -A
  git -C "$PROJECT_DIR" commit -q -m "fixture: the project ignores .scratch/"

  # Held by a live owner for the whole run, so it exists while every gate runs.
  # Nothing allocates a number on a plain green path, so this only stages the
  # visibility question.
  mkdir -p "$FEATURE_DIR/.open.guard"
  printf '%s\n' "$$" >"$FEATURE_DIR/.open.guard/pid"
  printf '2026-08-27T00:00:00Z\n' >"$FEATURE_DIR/.open.guard/since"

  deliver_normally
  run_loop
  echo "=== rc=$status 01-alpha=$(ticket_status 01-alpha)"

  echo "=== the zone lines"
  printf '%s\n' "$output" | grep -i 'ignored path' || echo "(none)"

  echo "=== the receipt's zone line"
  grep -rh 'ignored path' "$PROJECT_DIR/receipts" 2>/dev/null || echo "(none)"

  echo "=== what the worktree of the iteration held under .scratch/"
  printf '%s\n' "$output" | grep -i 'worktree' | head -3 || true

  echo "=== main tree status"
  git -C "$PROJECT_DIR" status --porcelain --ignored=matching | head -20
  false
}
