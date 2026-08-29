#!/usr/bin/env bats
#
# [46] part B: the git configuration that decides what git runs and produces.
#
#   Q2  `core.fsmonitor` written into `<main tree>/.git/config`
#   Q3  the same, in the operator's `~/.gitconfig`
#   Q4  a `filter.<n>.smudge` armed by `.git/info/attributes`
#   Q5  a `clean`/`smudge` filter and the tracker guard, which reads and writes
#       `issues/` through git before any of [32]'s three sites is reached

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() { harness_setup; }
teardown() { harness_teardown; }

@test "Q2 fsmonitor in .git/config" {
  use_tickets 01-alpha 02-beta
  set_config RETRY_N 0
  mkdir -p "$HOME/hooks"
  cat >"$HOME/hooks/fsm" <<HOOK
#!/usr/bin/env bash
printf 'x\n' >>"$SHIM_STATE/fsmonitor-fired"
exit 1
HOOK
  chmod +x "$HOME/hooks/fsm"

  script_claude <<'FAKE'
#!/usr/bin/env bash
surface="$(cat | sed -n 's/^\*\*Write-surface:\*\* //p' | head -1 | tr -d '`\r' | tr ',' ' ')"
for target in $surface; do
  mkdir -p "$(dirname "$target")" && printf 'written\n' >"$target"
done
root="$(cat "$RALPH_SHIM_STATE/project-dir")"
printf '[core]\n\tfsmonitor = %s/hooks/fsm\n' "$HOME" >>"$root/.git/config"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  echo "=== rc=$status"
  printf '%s\n' "$output" | head -30
  echo "=== fsmonitor invocations: $(awk 'END{print NR+0}' "$SHIM_STATE/fsmonitor-fired" 2>/dev/null || echo 0)"
  echo "=== 01-alpha=$(ticket_status 01-alpha) 02-beta=$(ticket_status 02-beta)"
  echo "=== the key now:"
  git -C "$PROJECT_DIR" config --get core.fsmonitor || echo "(unset)"
  echo "=== receipts"
  grep -h 'fsmonitor' "$PROJECT_DIR/receipts/$RALPH_TEST_FEATURE"/*.md 2>/dev/null || echo "(no receipt names it)"
  false
}

@test "Q3 fsmonitor in the operator's home" {
  use_tickets 01-alpha
  set_config RETRY_N 0
  mkdir -p "$HOME/hooks"
  cat >"$HOME/hooks/fsm" <<HOOK
#!/usr/bin/env bash
printf 'x\n' >>"$SHIM_STATE/fsmonitor-fired"
exit 1
HOOK
  chmod +x "$HOME/hooks/fsm"

  script_claude <<'FAKE'
#!/usr/bin/env bash
surface="$(cat | sed -n 's/^\*\*Write-surface:\*\* //p' | head -1 | tr -d '`\r' | tr ',' ' ')"
for target in $surface; do
  mkdir -p "$(dirname "$target")" && printf 'written\n' >"$target"
done
printf '[core]\n\tfsmonitor = %s/hooks/fsm\n' "$HOME" >"$HOME/.gitconfig"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  echo "=== rc=$status"
  printf '%s\n' "$output" | head -30
  echo "=== 01-alpha=$(ticket_status 01-alpha)"
  echo "=== receipts"
  grep -h 'fsmonitor' "$PROJECT_DIR/receipts/$RALPH_TEST_FEATURE"/*.md 2>/dev/null || echo "(no receipt names it)"
  false
}

@test "Q4 a smudge filter and the next iteration" {
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
    cp CONTEXT.md "$RALPH_SHIM_STATE/what-02-beta-saw" 2>/dev/null || true
    ;;
esac
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  echo "=== rc=$status"
  printf '%s\n' "$output" | head -40
  echo "=== 01-alpha=$(ticket_status 01-alpha) 02-beta=$(ticket_status 02-beta)"
  echo "=== what the second session was handed as CONTEXT.md:"
  cat "$SHIM_STATE/what-02-beta-saw" 2>/dev/null || echo "(never ran)"
  echo "=== the filter now:"
  git -C "$PROJECT_DIR" config --get filter.ralphprobe.smudge || echo "(unset)"
  echo "=== info/attributes now:"
  cat "$PROJECT_DIR/.git/info/attributes" 2>/dev/null || echo "(gone)"
  echo "=== receipts"
  grep -h 'attributes\|filter\.' "$PROJECT_DIR/receipts/$RALPH_TEST_FEATURE"/*.md 2>/dev/null || echo "(nothing)"
  false
}

@test "Q5 a clean filter and the tracker guard" {
  use_tickets 01-alpha 02-beta
  set_config RETRY_N 0
  set_config STERILE_K 5

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
	smudge = sed s/Status/SsSsS/
	clean = sed s/Status/Status/
CFG
    ;;
esac
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  echo "=== rc=$status"
  printf '%s\n' "$output" | head -40
  echo "=== 01-alpha=$(ticket_status 01-alpha) 02-beta=$(ticket_status 02-beta)"
  echo "=== the tickets on disk, first three lines each:"
  for f in "$TRACKER_DIR"/*.md; do echo "--- $f"; head -6 "$f"; done
  false
}
