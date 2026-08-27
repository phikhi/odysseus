#!/usr/bin/env bats
#
# Passe transversale du 27/08 — combien vaut la fenêtre de q5.
#
# q5 met la main sur l'état ; celle-ci demande à quelle fréquence il arrive tout
# seul. La question exacte : un `failures_tracker_tree` pris pendant qu'une sœur
# écrit le tracker capture-t-il quelque chose qui n'est pas un fichier de ticket
# — le garde de claim (`<id>.md.guard/`) ou le temporaire de
# `state_atomic_write` (`<id>.md.tmp.XXXXXX`) ?
#
# Instrument, pas test : se termine par un `false` volontaire.

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() { harness_setup; }
teardown() { harness_teardown; }

@test "Q6a how often a pre-session snapshot catches a sister mid-write" {
  use_tickets 01-alpha 02-beta

  pack_run '
dir="$(tracker_local__issues_dir)"
root="$(ralph_project_root)"
stop="$(ralph_feature_dir)/stop"
rm -f "$stop"

# A sister doing exactly what loop__start does on every iteration: claim, then
# release. Each claim is one guard directory and several atomic writes.
( while [ ! -e "$stop" ]; do
    tracker_claim 02-beta "pid:$$" >/dev/null 2>&1 || true
    tracker_unclaim 02-beta >/dev/null 2>&1 || true
  done ) &
writer=$!

# `pipefail` plus a `grep` that finds nothing is an exit status this loop must
# not inherit: a failing command substitution in an assignment ends the script
# under `set -e`, and the writer below then spins on, holding stdout open — which
# is how the first version of this probe hung instead of measuring.
set +e
hits=0 n=0 caught=""
while [ $n -lt 60 ]; do
  snap="$(failures_tracker_tree)" || snap=""
  if [ -n "$snap" ]; then
    stray="$(cd "$root" && git ls-tree -r --name-only "$snap" | grep -v "\.md$" | head -2)"
    if [ -n "$stray" ]; then
      hits=$((hits + 1))
      caught="$caught
$stray"
    fi
  fi
  n=$((n + 1))
done
: >"$stop"
wait $writer 2>/dev/null || true

echo "=== $hits of 60 pre-session snapshots caught something that is not a ticket"
echo "=== what they caught (first few)"
printf "%s\n" "$caught" | sort -u | grep . | head -8 || echo "(nothing)"
'
  printf '%s\n' "$output"
  false
}

@test "Q6b the two durations the window is made of" {
  use_tickets 01-alpha 02-beta

  pack_run '
set +e
ms() { perl -MTime::HiRes=time -e "printf \"%.0f\n\", time*1000"; }

t0=$(ms); n=0
while [ $n -lt 20 ]; do failures_tracker_tree >/dev/null; n=$((n + 1)); done
t1=$(ms)
echo "=== failures_tracker_tree (the pre-session snapshot): $(( (t1 - t0) / 20 )) ms"

t0=$(ms); n=0
while [ $n -lt 20 ]; do
  tracker_claim 02-beta "pid:$$" >/dev/null 2>&1
  tracker_unclaim 02-beta >/dev/null 2>&1
  n=$((n + 1))
done
t1=$(ms)
echo "=== one claim + one unclaim (what loop__start does per iteration): $(( (t1 - t0) / 20 )) ms"

t0=$(ms); n=0
while [ $n -lt 20 ]; do tracker_local__set_fields 02-beta Failures "$n" >/dev/null 2>&1; n=$((n + 1)); done
t1=$(ms)
echo "=== one set_fields (the .work + .work.p transient): $(( (t1 - t0) / 20 )) ms"
'
  printf '%s\n' "$output"
  false
}
