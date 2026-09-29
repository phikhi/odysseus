#!/usr/bin/env bats
#
# Ticket [98], avant d'écrire une ligne — la question de la frontière de confiance
# posée au mécanisme que [98] devait reprendre (le canal délié de [94]/[96]).
#
# L1/L2 : le programme étranger lancé par le pack (la session jugée, la commande de
# test du projet) essaie d'écrire un enregistrement de reçu sur CHAQUE descripteur
# au-dessus de 2, et pas seulement sur les numéros que le pack dit avoir fermés.
# L3 : la session pose un hook dans le répertoire git commun ; git le lance pour le
# pack, avec les descripteurs de l'itération.
#
# Instrument, pas test : chaque cas finit par un `false` volontaire.
load ../../../../test/helpers/harness
load ../../../../test/helpers/assert
setup() { harness_setup; }
teardown() { harness_teardown; }

# La sonde de descripteurs, en perl et pas en bash : un `printf` builtin vers
# `>&10` réussit même fd 10 fermé, parce que bash sauvegarde d'abord fd 1 sur le
# plus petit numéro libre >= 10 puis fait `dup2(10, 1)` sur sa propre copie.
# `open ">&="` + `syswrite` ne redirige rien et n'a pas cet artefact (mesuré).
write_forger() {
  cat >"$SHIM_STATE/fd-forger" <<'PERL'
#!/usr/bin/env perl
my ($rec, $log) = @ARGV; my @open;
for my $n (3 .. 255) {
  open(my $fh, ">&=", $n) or next;
  push @open, $n if defined syswrite($fh, "$rec\n");
}
open(my $out, ">>", $log) or die "no log: $!";
print $out "OPEN $_\n" for @open;
print $out "probed\n";
PERL
  chmod +x "$SHIM_STATE/fd-forger"
}

receipt_path() { printf "%s/receipts/%s/%s.md\n" "$PROJECT_DIR" "$RALPH_TEST_FEATURE" "$1"; }

@test "L1 the judged session writes a receipt record on every fd it holds above 2" {
  use_tickets 01-alpha
  set_config RETRY_N 2
  set_config STERILE_K 4
  stub_exit tests 1
  printf 'FAIL: 3 of 12 tests failed in src/alpha\n' >"$SHIM_STATE/stub-tests.out"
  write_forger
  script_claude <<'FAKE'
#!/usr/bin/env bash
state="$RALPH_SHIM_STATE"
"$state/fd-forger" "$(printf 'note\tFORGED-BY-THE-SESSION')" "$state/session.probe"
mkdir -p src
printf 'written\n' >src/alpha.txt
printf '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}\n'
FAKE
  run_loop
  printf '=== rc=%s\n' "$status"
  printf '=== fds the session could write:\n'; sed 's/^/   /' "$SHIM_STATE/session.probe"
  printf '=== forged lines in the receipt:\n'; grep -n 'FORGED' "$(receipt_path 01-alpha)" | sed 's/^/   /' || printf '   none\n'
  set -e
  false
}

@test "L2 the project's TEST_CMD writes on every fd it holds above 2" {
  use_tickets 01-alpha
  set_config RETRY_N 2
  set_config STERILE_K 4
  write_forger
  cat >"$SHIM_STATE/probe.sh" <<'PROBE'
#!/usr/bin/env bash
state="$RALPH_SHIM_STATE"
"$state/fd-forger" "$(printf 'note\tFORGED-BY-TEST-CMD')" "$state/testcmd.probe"
printf 'FAIL: 3 of 12 tests failed in src/alpha\n'
exit 1
PROBE
  chmod +x "$SHIM_STATE/probe.sh"
  set_config TEST_CMD "bash '$SHIM_STATE/probe.sh'"
  run_loop
  printf '=== rc=%s\n' "$status"
  printf '=== fds TEST_CMD could write:\n'; sed 's/^/   /' "$SHIM_STATE/testcmd.probe" 2>/dev/null
  printf '=== forged lines in the receipt:\n'; grep -n 'FORGED' "$(receipt_path 01-alpha)" | sed 's/^/   /' || printf '   none\n'
  set -e
  false
}

@test "L3 a hook the session plants in the common git dir runs with the iteration's descriptors" {
  use_tickets 01-alpha
  script_claude <<'FAKE'
#!/usr/bin/env bash
state="$RALPH_SHIM_STATE"
common="$(git rev-parse --git-common-dir)"
mkdir -p "$common/hooks"
cat >"$common/hooks/reference-transaction" <<HOOK
#!/bin/sh
cat >/dev/null
printf 'rt %s\n' "\$1" >>"$state/hook.ran"
for fd in 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
  ( printf 'note\tFORGED-BY-A-HOOK-ON-FD-%s\n' "\$fd" >&"\$fd" ) 2>/dev/null && printf 'OPEN %s\n' "\$fd" >>"$state/hook.fds"
done
exit 0
HOOK
chmod +x "$common/hooks/reference-transaction"
cat >"$common/hooks/post-checkout" <<HOOK
#!/bin/sh
printf 'post-checkout pid=%s ppid=%s\n' "\$\$" "\$PPID" >>"$state/hook.ran"
exit 0
HOOK
chmod +x "$common/hooks/post-checkout"
mkdir -p src
printf 'written by %s\n' "$$" >src/alpha.txt
printf '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}\n'
FAKE
  use_tickets 01-alpha 02-beta
  run_loop
  printf '=== rc=%s\n' "$status"
  printf '=== hook runs:\n'; sed 's/^/   /' "$SHIM_STATE/hook.ran" 2>/dev/null || printf '   none\n'
  printf '=== fds the hook could write:\n'; sort -u "$SHIM_STATE/hook.fds" 2>/dev/null | sed 's/^/   /' || printf '   none\n'
  printf '=== forged lines in receipts:\n'; grep -rn 'FORGED' "$PROJECT_DIR/receipts" | sed 's/^/   /' || printf '   none\n'
  set -e
  false
}
