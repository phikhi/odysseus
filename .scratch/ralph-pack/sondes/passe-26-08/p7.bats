#!/usr/bin/env bats
#
# Passe transversale — probe 7.
#
# P6 measured the wrong tree. The mechanism is real at the git level (checked
# raw: `.git/info/attributes` in the common dir applies inside a linked worktree,
# and `git checkout-index` runs the smudge). What it costs the pack is therefore
# not "the rollback of this iteration" but every worktree the run creates
# afterwards.

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() { harness_setup; }
teardown() { harness_teardown; }

@test "P7 one session installs a filter, every later iteration of the run gets it" {
  use_tickets 01-alpha 02-beta
  set_config RETRY_N 0
  set_config STERILE_K 5

  printf 'the original line\n' >"$PROJECT_DIR/CONTEXT.md"
  git -C "$PROJECT_DIR" add -A
  git -C "$PROJECT_DIR" commit -q -m "fixture: a tracked file with known content"

  script_claude <<'FAKE'
#!/usr/bin/env bash
prompt="$(cat)"
surface="$(printf '%s' "$prompt" | sed -n 's/^\*\*Write-surface:\*\* //p' | head -1 | tr -d '`\r' | tr ',' ' ')"
for target in $surface; do
  mkdir -p "$(dirname "$target")" && printf 'written\n' >"$target"
done
case "$prompt" in
  *01-alpha*)
    root="$(cat "$RALPH_SHIM_STATE/project-dir")"
    mkdir -p "$root/.git/info"
    printf '* filter=ralphprobe\n' >>"$root/.git/info/attributes"
    cat >>"$root/.git/config" <<CFG
[filter "ralphprobe"]
	smudge = sed s/original/REWRITTEN-BY-01-ALPHA/
	clean = cat
CFG
    ;;
  *02-beta*)
    # What the second iteration's session actually finds in its worktree.
    cp CONTEXT.md "$RALPH_SHIM_STATE/what-02-beta-saw" 2>/dev/null || true
    ;;
esac
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  echo "=== rc=$status"
  printf '%s\n' "$output" | head -30
  echo "=== 01-alpha=$(ticket_status 01-alpha) 02-beta=$(ticket_status 02-beta)"
  echo "=== what the second session was handed as CONTEXT.md:"
  cat "$SHIM_STATE/what-02-beta-saw" 2>/dev/null || echo "(never ran)"
  echo "=== main tree CONTEXT.md now:"
  cat "$PROJECT_DIR/CONTEXT.md"
  echo "=== git's stored blob:"
  git -C "$PROJECT_DIR" show HEAD:CONTEXT.md
  echo "=== anything said?"
  grep -h 'attributes\|smudge\|filter' \
    "$PROJECT_DIR/receipts/$RALPH_TEST_FEATURE"/*.md "$FEATURE_DIR/run.log" 2>/dev/null ||
    echo "(nothing)"
  false
}
