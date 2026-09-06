#!/usr/bin/env bats
#
# [64] — sonde « run réel ». Instrument, pas test : chaque cas finit par un `false`.

load /Users/philippekhill/Sites/odysseus/test/helpers/harness
load /Users/philippekhill/Sites/odysseus/test/helpers/assert

setup() { harness_setup; }
teardown() { harness_teardown; }

plant() {
  local name="$1"
  {
    printf '# a ticket nobody can address\n\n'
    printf '**Status:** ready-for-agent\n\n'
    printf '**Write-surface:** `src/nowhere.txt`\n\n'
    printf '**Blocked by:** None\n'
  } >"$TRACKER_DIR/$name"
}

count() { printf '%s\n' "$1" | grep -c 'carries a newline in its name' || true; }

@test "S1 deux noms inadressables : deux constats, une fois chacun" {
  use_tickets 01-alpha
  plant "50-a"$'\n'"b.md"
  plant "51-c"$'\n'"d.md"

  run_loop
  printf '=== rc                 : %s\n' "$status"
  printf '=== phrase, combien    : %s\n' "$(count "$output")"
  printf '=== run.log ----------------------------------------\n%s\n' \
    "$(sed 's/^/    /' "$FEATURE_DIR/run.log")"
  printf '=== TMPDIR ralph-tracker.refused.* : %s\n' \
    "$(ls "${TMPDIR:-/tmp}" | grep -c '^ralph-tracker.refused' || true)"
  set -e
  false
}

@test "S2 le nom apparait PENDANT le run : le repli parle encore" {
  use_tickets 01-alpha 02-beta
  script_claude <<'FAKE'
#!/usr/bin/env bash
prompt="$(cat)"
root="$(cat "$RALPH_SHIM_STATE/project-dir")"
dir="$(ls -d "$root"/.scratch/*/issues 2>/dev/null | head -1)"
if [ ! -e "$dir/$(printf '70-x\ny').md" ]; then
  printf '# planted mid-run\n\n**Status:** ready-for-agent\n' >"$dir/$(printf '70-x\ny').md"
fi
printf '%s' "$prompt" | sed -n 's/^\*\*Write-surface:\*\* //p' | head -1 |
  tr -d '`\r' | tr ',' '\n' | while IFS= read -r f; do
    [ -n "$f" ] || continue
    mkdir -p "$(dirname "$f")" && printf 'work %s\n' "$RANDOM" >"$f"
  done
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  printf '=== rc                 : %s\n' "$status"
  printf '=== phrase, combien    : %s\n' "$(count "$output")"
  printf '=== run.log ----------------------------------------\n%s\n' \
    "$(sed 's/^/    /' "$FEATURE_DIR/run.log")"
  printf '=== sortie -----------------------------------------\n%s\n' "$output"
  set -e
  false
}

@test "S3 rien d'inadressable : aucune trace, aucun residu" {
  use_tickets 01-alpha
  run_loop
  printf '=== rc                 : %s\n' "$status"
  printf '=== phrase, combien    : %s\n' "$(count "$output")"
  printf '=== unaddressable dans run.log : %s\n' \
    "$(grep -c 'unaddressable' "$FEATURE_DIR/run.log" || true)"
  printf '=== TMPDIR ralph-tracker.refused.* : %s\n' \
    "$(ls "${TMPDIR:-/tmp}" | grep -c '^ralph-tracker.refused' || true)"
  set -e
  false
}
