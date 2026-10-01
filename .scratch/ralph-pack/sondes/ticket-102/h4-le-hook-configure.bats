#!/usr/bin/env bats
#
# [102] h4 — a hook the session CONFIGURES (`hook.<name>.command` + `.event`,
# git >= 2.5x), which `core.hooksPath=/dev/null` does not turn off. Does the pack's
# git run it before [46]'s put-back removes the key, and with which descriptors?
#   C1  repository config, MAX_PARALLEL=1, two tickets
#   C2  repository config, MAX_PARALLEL=2, two tickets: the planting session lives
#       on 8 s while its sibling is judged
#   C3  the operator's ~/.gitconfig, MAX_PARALLEL=1 (a value no unset reaches)
# The hook forges on every fd it holds (fd_forger) and logs which process ran it.
#
# Instrument, not test: each case ends on a deliberate `false`.
load ../../../../test/helpers/harness
load ../../../../test/helpers/assert
setup() { harness_setup; }
teardown() { harness_teardown; }

write_session() { # $1 = repo|global, $2 = seconds the planting session lives on
  fd_forger
  cat >"$SHIM_STATE/planted-hook" <<HOOK
#!/bin/sh
cat >/dev/null 2>&1
printf 'ran %s from %s\n' "\$1" "\$(ps -o command= -p \$PPID | cut -c1-50)" >>"$SHIM_STATE/hook.ran"
"$SHIM_STATE/fd-forger" "\$(printf 'note\tFORGED-BY-A-CONFIGURED-HOOK')" "$SHIM_STATE/hook.fds"
exit 0
HOOK
  chmod +x "$SHIM_STATE/planted-hook"
  local where='' ; [ "$1" = global ] && where='--global'
  cat >"$SHIM_STATE/claude.script" <<FAKE
#!/usr/bin/env bash
prompt="\$(cat)"
if [ ! -e "$SHIM_STATE/planted" ]; then
  : >"$SHIM_STATE/planted"
  for ev in reference-transaction post-index-change post-checkout; do
    git config $where --add hook.planted.event \$ev
  done
  git config $where hook.planted.command '$SHIM_STATE/planted-hook'
  sleep ${2:-2}
fi
chmod -x "$SHIM_STATE/claude.script"
printf '%s' "\$prompt" | claude "\$@"
status=\$?
chmod +x "$SHIM_STATE/claude.script"
exit \$status
FAKE
  chmod +x "$SHIM_STATE/claude.script"
}

report() {
  printf '=== rc=%s\n' "$status"
  printf '=== configured-hook runs:\n'; sort "$SHIM_STATE/hook.ran" 2>/dev/null | uniq -c | sed 's/^/   /' || printf '   none\n'
  printf '=== fds it could write:\n'; sort "$SHIM_STATE/hook.fds" 2>/dev/null | uniq -c | sed 's/^/   /' || printf '   none\n'
  printf '=== forged lines in receipts:\n'; grep -rc 'FORGED' "$PROJECT_DIR/receipts" 2>/dev/null | sed 's/^/   /' || printf '   none\n'
  printf '=== key left in config:\n'; { git -C "$PROJECT_DIR" config --get-regexp '^hook\.' || true; } | sed 's/^/   /'
  printf '=== named:\n'; printf '%s\n' "$output" | grep -i 'hook\.' | head -5 | sed 's/^/   /'
}

@test "C1 repository config, MAX_PARALLEL=1" {
  use_tickets 01-alpha 02-beta
  set_config STERILE_K 5
  write_session repo
  run_loop
  report
  set -e; false
}

@test "C2 repository config, MAX_PARALLEL=2" {
  use_tickets 01-alpha 02-beta
  set_config MAX_PARALLEL 2
  set_config STERILE_K 5
  write_session repo 8
  run_loop
  report
  set -e; false
}

@test "C3 the operator's ~/.gitconfig, MAX_PARALLEL=1" {
  use_tickets 01-alpha 02-beta
  set_config STERILE_K 5
  write_session global
  run_loop
  report
  set -e; false
}

# C2b — the window C2 could not catch by timing, staged by a release protocol:
# 02's gate is held inside its test command until 01's session has planted, so
# what 02's gate runs after that is git under a configured hook it never saw put
# back (its own put-back ran before the plant).
@test "C2b repository config, MAX_PARALLEL=2, planted while the sibling is in its gate" {
  use_tickets 01-alpha 02-beta
  set_config MAX_PARALLEL 2
  set_config STERILE_K 5
  fd_forger
  cat >"$SHIM_STATE/planted-hook" <<HOOK
#!/bin/sh
cat >/dev/null 2>&1
printf 'ran %s from %s\n' "\$1" "\$(ps -o command= -p \$PPID | cut -c1-50)" >>"$SHIM_STATE/hook.ran"
"$SHIM_STATE/fd-forger" "\$(printf 'note\tFORGED-BY-A-CONFIGURED-HOOK')" "$SHIM_STATE/hook.fds"
exit 0
HOOK
  chmod +x "$SHIM_STATE/planted-hook"
  cat >"$SHIM_STATE/gate-test.sh" <<'TESTCMD'
#!/usr/bin/env bash
s="$RALPH_SHIM_STATE"
if [ ! -e "$s/planted" ]; then
  : >"$s/02-in-gate"
  for i in $(seq 1 300); do [ -e "$s/planted" ] && break; sleep 0.1; done
fi
exit 0
TESTCMD
  chmod +x "$SHIM_STATE/gate-test.sh"
  set_config TEST_CMD "bash '$SHIM_STATE/gate-test.sh'"
  cat >"$SHIM_STATE/claude.script" <<FAKE
#!/usr/bin/env bash
prompt="\$(cat)"
case "\$prompt" in
  *"## The lens you are"*|*RALPH-LENS-VERDICT*) ;;
  *01-alpha*)
    if [ ! -e "$SHIM_STATE/planted" ]; then
      for i in \$(seq 1 300); do [ -e "$SHIM_STATE/02-in-gate" ] && break; sleep 0.1; done
      for ev in reference-transaction post-index-change post-checkout; do
        git config --add hook.planted.event \$ev
      done
      git config hook.planted.command '$SHIM_STATE/planted-hook'
      : >"$SHIM_STATE/planted"
      sleep 6
    fi
    ;;
esac
chmod -x "$SHIM_STATE/claude.script"
printf '%s' "\$prompt" | claude "\$@"
status=\$?
chmod +x "$SHIM_STATE/claude.script"
exit \$status
FAKE
  chmod +x "$SHIM_STATE/claude.script"
  run_loop
  report
  printf '=== protocol: in-gate=%s planted=%s\n' "$([ -e "$SHIM_STATE/02-in-gate" ] && echo yes || echo no)" "$([ -e "$SHIM_STATE/planted" ] && echo yes || echo no)"
  set -e; false
}

# C4 — the same door with a key [46] already watched: `core.fsmonitor` in the
# operator's ~/.gitconfig, MAX_PARALLEL=1. Not a hook, and the token does nothing to
# it either: is it the same residue, with the same descriptors?
@test "C4 core.fsmonitor in the operator's ~/.gitconfig, MAX_PARALLEL=1" {
  use_tickets 01-alpha 02-beta
  set_config STERILE_K 5
  fd_forger
  cat >"$SHIM_STATE/planted-hook" <<HOOK
#!/bin/sh
printf 'ran fsmonitor from %s\n' "\$(ps -o command= -p \$PPID | cut -c1-50)" >>"$SHIM_STATE/hook.ran"
"$SHIM_STATE/fd-forger" "\$(printf 'note\tFORGED-BY-AN-FSMONITOR')" "$SHIM_STATE/hook.fds"
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
  report
  set -e; false
}
