#!/usr/bin/env bats
#
# [102] h2 — which hooks git runs for the pack in a real run, from which process,
# planted BEFORE the run in the common git dir (every name of githooks(5)) and as
# one configured hook per event (`hook.cfg-<event>.command`, git >= 2.5x).
# A1: an AFK run, two tickets, one green and one red (fold, durable commit, ref).
# A2: the drain, one re-injection answered.
#
# Instrument, not test: each case ends on a deliberate `false`.
load ../../../../test/helpers/harness
load ../../../../test/helpers/assert
setup() { harness_setup; }
teardown() { harness_teardown; }

plant_everything() {
  local common names n
  common="$(git -C "$PROJECT_DIR" rev-parse --git-common-dir)"
  case "$common" in /*) ;; *) common="$PROJECT_DIR/$common" ;; esac
  names='applypatch-msg pre-applypatch post-applypatch pre-commit pre-merge-commit prepare-commit-msg commit-msg post-commit pre-rebase post-checkout post-merge pre-push pre-receive update proc-receive post-receive post-update reference-transaction push-to-checkout pre-auto-gc post-rewrite sendemail-validate fsmonitor-watchman post-index-change'
  mkdir -p "$common/hooks"
  for n in $names; do
    cat >"$common/hooks/$n" <<HOOK
#!/bin/sh
cat >/dev/null 2>&1 &
printf 'DIR %s parent=%s\n' "$n" "\$(ps -o command= -p \$PPID | cut -c1-60)" >>"$SHIM_STATE/hooks.ran"
exit 0
HOOK
    chmod +x "$common/hooks/$n"
    git -C "$PROJECT_DIR" config "hook.cfg-$n.command" "printf 'CFG $n\\n' >>'$SHIM_STATE/hooks.ran'; cat >/dev/null 2>&1; true"
    git -C "$PROJECT_DIR" config --add "hook.cfg-$n.event" "$n"
  done
}

@test "A1 an AFK run, one green and one red" {
  use_tickets 01-alpha 02-beta
  plant_everything
  script_claude <<'FAKE'
#!/usr/bin/env bash
prompt="$(cat)"
case "$prompt" in
  *02-beta*) printf '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}\n'; exit 0 ;;
esac
chmod -x "$RALPH_SHIM_STATE/claude.script"
printf '%s' "$prompt" | exec claude "$@"
FAKE
  run_loop
  printf '=== rc=%s\n' "$status"
  printf '=== hooks that ran (count, kind, event, parent):\n'
  sort "$SHIM_STATE/hooks.ran" 2>/dev/null | uniq -c | sed 's/^/   /' || printf '   none\n'
  set -e
  false
}

@test "A2 the drain, one re-injection" {
  mkdir -p "$TRACKER_DIR"
  printf '# 20-one\n\n**What to build:** x\n\n**Status:** ready-for-human\n\n**Escalation:** failed-impl\n\n**Write-surface:** `src/one.txt`\n\n**Blocked by:** None\n\n- [ ] x\n' >"$TRACKER_DIR/20-one.md"
  harness__commit "test: 20-one"
  plant_everything
  run bash "$PACK_DIR/human-loop.sh" <<ANSWERS
r
ANSWERS
  printf '=== rc=%s\n' "$status"
  printf '%s\n' "$output" | tail -5 | sed 's/^/   out: /'
  printf '=== hooks that ran (count, kind, event, parent):\n'
  sort "$SHIM_STATE/hooks.ran" 2>/dev/null | uniq -c | sed 's/^/   /' || printf '   none\n'
  set -e
  false
}
