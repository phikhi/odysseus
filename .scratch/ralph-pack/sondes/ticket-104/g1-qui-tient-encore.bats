#!/usr/bin/env bats
#
# [104] g1 — after every pack git goes through proc_git, a core.fsmonitor of the
# operator's ~/.gitconfig still found fds 3 and 5 open ten times (h4 C4 replayed on
# the branch). Who ran that git? Each run of the program records its own forger
# result next to its ancestry (parent, grandparent, great-grandparent commands).
#
# Instrument, not test: ends on a deliberate `false`.
load ../../../../test/helpers/harness
load ../../../../test/helpers/assert
setup() { harness_setup; }
teardown() { harness_teardown; }

@test "G1 who runs git holding 3 and 5" {
  use_tickets 01-alpha 02-beta
  set_config STERILE_K 5
  fd_forger
  cat >"$SHIM_STATE/planted-hook" <<HOOK
#!/bin/sh
out="\$("$SHIM_STATE/fd-forger" "\$(printf 'note\tFORGED-BY-AN-FSMONITOR')" /dev/stdout | tr '\n' ' ')"
p=\$PPID; chain=''
for k in 1 2 3 4; do
  c="\$(ps -o ppid=,command= -p \$p 2>/dev/null | cut -c1-160)"
  chain="\$chain || \$c"
  p="\$(printf '%s' "\$c" | awk '{print \$1}')"
  [ -n "\$p" ] || break
done
printf '%s ## %s\n' "\$out" "\$chain" >>"$SHIM_STATE/runs"
exit 1
HOOK
  chmod +x "$SHIM_STATE/planted-hook"
  cat >"$SHIM_STATE/claude.script" <<FAKE
#!/usr/bin/env bash
prompt="\$(cat)"
if [ ! -e "$SHIM_STATE/planted" ]; then
  : >"$SHIM_STATE/planted"
  git config --global core.fsmonitor '$SHIM_STATE/planted-hook'
fi
chmod -x "$SHIM_STATE/claude.script"
printf '%s' "\$prompt" | claude "\$@"
status=\$?
chmod +x "$SHIM_STATE/claude.script"
exit \$status
FAKE
  chmod +x "$SHIM_STATE/claude.script"
  run_loop
  cp "$SHIM_STATE/runs" "$SHIM_STATE/runs.after-loop"
  printf '=== rc=%s runs=%s\n' "$status" "$(grep -c . "$SHIM_STATE/runs.after-loop")"
  printf '=== runs with an OPEN fd:\n'
  grep 'OPEN' "$SHIM_STATE/runs.after-loop" | sort | uniq -c | head -20
  set -e; false
}
