#!/usr/bin/env bats
#
# Passe transversale du 27/08 — question 4 de CLAUDE.md posée à [47].
#
# [47] a écarté SON garde de `issues/` en nommant précisément le mécanisme :
# « `issues/` est l'arbre que `failures_protect_tracker` compare autour de chaque
# session, donc un garde pris là arriverait comme un chemin que la restauration
# essaierait de sortir ». Puis il a laissé en place le garde qui y est déjà —
# celui du claim, `<ticket>.md.guard` — sur un argument de durée : « sa fenêtre
# est de l'ordre de la milliseconde et il tombe avant le spawn ».
#
# « Avant le spawn » vaut pour le claim de l'itération elle-même. Une SŒUR
# claime où elle tombe, et depuis [13] il y en a une par slot.
#
# Instrument, pas test : se termine par un `false` volontaire.

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() { harness_setup; }
teardown() { harness_teardown; }

@test "Q5a a sister's claim guard inside the window: what the restore does with it" {
  use_tickets 01-alpha 02-beta

  pack_run '
rc=0
guard="$(tracker_local__path 02-beta).guard"

echo "=== a sister is mid-claim when this iteration snapshots the tracker"
mkdir -p "$guard"
printf "%s\n" "$$" >"$guard/pid"
ralph_now >"$guard/since"
before="$(failures_tracker_tree)"

echo "=== the sister releases it, milliseconds later, while the session runs"
rm -rf "$guard"

echo "=== the session wrote nothing at all in the tracker"
failures_protect_tracker 01-alpha "$before" 0 || rc=$?
echo "protect_tracker rc=$rc"

echo "=== is the guard back?"
if [ -d "$guard" ]; then
  echo "yes: pid=$(cat "$guard/pid" 2>/dev/null) (this pilot is $$)"
else
  echo "no"
fi

echo "=== what 01-alpha was told"
tracker_read_ticket 01-alpha | grep -i "edited the tracker" || echo "(no note)"

echo "=== can 02-beta ever be claimed again in this run?"
tracker_unclaim 02-beta >/dev/null 2>&1 || true
tracker_claim 02-beta "pid:$$" && echo "claimed" || echo "REFUSED"
echo "02-beta status: $(tracker_field 02-beta Status)"
'
  printf '%s\n' "$output"
  echo "=== bats-side rc=$status"
  false
}

@test "Q5b the mirror case: a guard that appears inside the window" {
  use_tickets 01-alpha 02-beta

  pack_run '
rc=0
guard="$(tracker_local__path 02-beta).guard"
before="$(failures_tracker_tree)"

echo "=== the sister claims while the session runs, and is still holding"
mkdir -p "$guard"
printf "%s\n" "$$" >"$guard/pid"
ralph_now >"$guard/since"

failures_protect_tracker 01-alpha "$before" 0 || rc=$?
echo "protect_tracker rc=$rc"

echo "=== what 01-alpha was told"
tracker_read_ticket 01-alpha | grep -i "edited the tracker" || echo "(no note)"

echo "=== and the quarantine, on the same window"
seen="$(printf "01-alpha\n02-beta\n")"
failures_quarantine_strays 01-alpha "$seen" 0 || echo "quarantine rc=non-zero"
echo "tracker now: $(ls "$(tracker_local__issues_dir)" | tr "\n" " ")"
'
  printf '%s\n' "$output"
  echo "=== bats-side rc=$status"
  false
}

@test "Q5c the wider window: the atomic write's own temp file" {
  use_tickets 01-alpha 02-beta

  pack_run '
rc=0
dir="$(tracker_local__issues_dir)"

echo "=== a sister is mid-write (state_atomic_write leaves a temp beside the ticket)"
tmp="$(mktemp "$dir/02-beta.md.tmp.XXXXXX")"
printf "half a ticket\n" >"$tmp"
before="$(failures_tracker_tree)"

echo "=== the sister renames it into place, milliseconds later"
mv -f "$tmp" "$dir/02-beta.md"

failures_protect_tracker 01-alpha "$before" 0 || rc=$?
echo "protect_tracker rc=$rc"

echo "=== what 01-alpha was told"
tracker_read_ticket 01-alpha | grep -i "edited the tracker" || echo "(no note)"

echo "=== what is in issues/ now"
ls "$dir" | tr "\n" " "
echo
echo "=== and what 02-beta holds"
head -3 "$dir/02-beta.md"
'
  printf '%s\n' "$output"
  echo "=== bats-side rc=$status"
  false
}

@test "Q5d end to end: a resurrected claim guard takes a ticket off the frontier" {
  use_tickets 01-alpha 02-beta
  set_config STERILE_K 2
  set_config ITER_CAP 6

  # The state Q5a produces, staged directly: a claim guard on 02-beta whose owner
  # is alive for the whole run. In a real run the owner is the pilot, because
  # `checkout-index` puts back a stamp `$$` wrote; here it is the bats process,
  # which answers `kill -0` exactly the same way.
  guard="$TRACKER_DIR/02-beta.md.guard"
  mkdir -p "$guard"
  printf '%s\n' "$$" >"$guard/pid"
  printf '2026-08-27T00:00:00Z\n' >"$guard/since"

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

  run_loop
  echo "=== rc=$status"
  echo "=== 01-alpha=$(ticket_status 01-alpha) 02-beta=$(ticket_status 02-beta)"
  echo "=== what the run said about 02-beta"
  printf '%s\n' "$output" | grep -i '02-beta' || echo "(nothing)"
  echo "=== how the run ended"
  printf '%s\n' "$output" | tail -4
  echo "=== run.log"
  cat "$FEATURE_DIR/run.log" 2>/dev/null || echo "(none)"
  echo "=== is 02-beta still on the frontier?"
  pack_run 'tracker_frontier'
  printf '%s\n' "$output"
  false
}

@test "Q5e the register of the loop's own writes cannot exempt any of it" {
  use_tickets 01-alpha 02-beta

  pack_run '
export RALPH_TRACKER_LOG="$(ralph_feature_dir)/writes.log"
: >"$RALPH_TRACKER_LOG"
rc=0
dir="$(tracker_local__issues_dir)"
guard="$dir/02-beta.md.guard"

mark="$(tracker_write_mark)"

echo "=== the sister claims 02-beta for real, through the dispatcher"
mkdir -p "$guard"; printf "%s\n" "$$" >"$guard/pid"; ralph_now >"$guard/since"
work="$(mktemp "$dir/02-beta.md.work.XXXXXX")"; cp "$dir/02-beta.md" "$work"
before="$(failures_tracker_tree)"
rm -rf "$guard" "$work"
tracker_claim 02-beta "pid:$$" >/dev/null 2>&1 || true

echo "=== the register now holds:"
cat "$RALPH_TRACKER_LOG"
echo "=== what failures__register_since gives the guard:"
failures__register_since "$mark"

failures_protect_tracker 01-alpha "$before" "$mark" || rc=$?
echo "protect_tracker rc=$rc  (0 would mean the register covered it)"
echo "=== what is back in issues/"
ls "$dir" | tr "\n" " "
'
  printf '%s\n' "$output"
  false
}
