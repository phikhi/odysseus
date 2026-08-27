#!/usr/bin/env bats
#
# Passe transversale du 27/08 — angle 2 de [47].
#
# `$$` est le pid du pilote dans toute itération, donc deux sœurs présentent le
# même propriétaire à `state_guard_take` et calculent le **même** nom de
# déplacement (`$guard.stale.$$`). `state.sh` nomme la course qu'il ne ferme pas
# — « deux appelants décidant ensemble qu'un propriétaire est mort » — et liste
# ce qui la couvre en aval : la revérification des deux verrous à chaque
# itération, et le test-and-set du claim sur le `Status:` du ticket.
#
# [47] a ajouté un troisième consommateur dont la correction EST l'exclusion
# mutuelle : rien en aval ne revérifie qu'un numéro alloué n'est pas déjà pris.
# La liste de `state.sh` n'a pas été élargie.
#
# Instrument, pas test : se termine par un `false` volontaire.

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() { harness_setup; }
teardown() { harness_teardown; }

@test "Q4a two subshells of one pilot, one stale guard: do both get it?" {
  use_tickets 01-alpha

  pack_run '
g="$(ralph_feature_dir)/probe.guard"
go="$(ralph_feature_dir)/probe.go"
both=0 a_only=0 b_only=0 neither=0 n=0
while [ $n -lt 300 ]; do
  rm -rf "$g" "$g.a" "$g.b" "$g".stale.* "$go"
  mkdir -p "$g"
  printf "999999\n" >"$g/pid"
  # A spin barrier, so both really enter state_guard_take at the same instant:
  # two bare `&` are serialised by the cost of forking, which is far wider than
  # the window being asked about.
  ( while [ ! -e "$go" ]; do :; done; state_guard_take "$g" probe >/dev/null 2>&1 && : >"$g.a" ) &
  ( while [ ! -e "$go" ]; do :; done; state_guard_take "$g" probe >/dev/null 2>&1 && : >"$g.b" ) &
  sleep 0.02
  : >"$go"
  wait
  if [ -e "$g.a" ] && [ -e "$g.b" ]; then both=$((both + 1))
  elif [ -e "$g.a" ]; then a_only=$((a_only + 1))
  elif [ -e "$g.b" ]; then b_only=$((b_only + 1))
  else neither=$((neither + 1)); fi
  n=$((n + 1))
done
echo "=== 300 rounds, one stale guard, two subshells sharing \$\$"
echo "both=$both  a_only=$a_only  b_only=$b_only  neither=$neither"
'
  printf '%s\n' "$output"
  false
}

@test "Q4b and what that buys on the number space" {
  use_tickets 01-alpha 02-beta

  pack_run '
g="$(tracker_local__open_guard)"
collide=0 n=0
while [ $n -lt 60 ]; do
  rm -rf "$(tracker_local__issues_dir)"/0[3-9]-* "$g" "$g".stale.*
  mkdir -p "$g"
  printf "999999\n" >"$g/pid"
  ( printf "x\n" | tracker_open_ticket "one$n" "One" >/dev/null 2>&1 ) &
  ( printf "y\n" | tracker_open_ticket "two$n" "Two" >/dev/null 2>&1 ) &
  wait
  one="$(ls "$(tracker_local__issues_dir)" | sed -n "s/^\([0-9][0-9]*\)-one$n\.md$/\1/p")"
  two="$(ls "$(tracker_local__issues_dir)" | sed -n "s/^\([0-9][0-9]*\)-two$n\.md$/\1/p")"
  if [ -n "$one" ] && [ "$one" = "$two" ]; then
    collide=$((collide + 1))
    echo "round $n: both took $one"
  fi
  n=$((n + 1))
done
echo "=== 60 rounds with a stale guard in the way: $collide collision(s)"
echo "=== and the same 60 rounds with no stale guard in the way"
collide=0 n=0
while [ $n -lt 60 ]; do
  rm -rf "$(tracker_local__issues_dir)"/1[0-9]-* "$g" "$g".stale.*
  ( printf "x\n" | tracker_open_ticket "p$n" "One" >/dev/null 2>&1 ) &
  ( printf "y\n" | tracker_open_ticket "q$n" "Two" >/dev/null 2>&1 ) &
  wait
  one="$(ls "$(tracker_local__issues_dir)" | sed -n "s/^\([0-9][0-9]*\)-p$n\.md$/\1/p")"
  two="$(ls "$(tracker_local__issues_dir)" | sed -n "s/^\([0-9][0-9]*\)-q$n\.md$/\1/p")"
  if [ -n "$one" ] && [ "$one" = "$two" ]; then collide=$((collide + 1)); fi
  n=$((n + 1))
done
echo "clean guard: $collide collision(s)"
'
  printf '%s\n' "$output"
  false
}

@test "Q4c a refused sister and the guard its sibling holds" {
  use_tickets 01-alpha 02-beta

  pack_run '
g="$(tracker_local__open_guard)"
echo "=== sister A holds the ticket-open guard (same \$\$ as B: $$)"
state_guard_take "$g" "ticket-open guard" demo
echo "holder=$(state_guard_holder "$g")"

echo "=== sister B opens a ticket — 120 tries x 0.05s, then refuses"
t0=$SECONDS
rc=0
printf "body\n" | tracker_open_ticket beeta "Beta" || rc=$?
echo "B rc=$rc after $((SECONDS - t0))s"

echo "=== is A still holding?"
if [ -d "$g" ]; then echo "yes, holder=$(state_guard_holder "$g")"; else echo "NO — B took it away"; fi

echo "=== did B leave a ticket behind?"
ls "$(tracker_local__issues_dir)" | tr "\n" " "
echo
echo "=== and the renumber, refused the same way"
rc=0
tracker_renumber 01-alpha || rc=$?
echo "renumber rc=$rc"
if [ -d "$g" ]; then echo "guard still held"; else echo "GUARD GONE"; fi
state_guard_release "$g"
'
  printf '%s\n' "$output"
  false
}
