#!/usr/bin/env bats
#
# Passe transversale du 30/08 — angle (e) ouvert par [09], et la question de [46]
# posée un cran plus bas.
#
# [46] a tranché : « la configuration git décide aussi de ce que git exécute »,
# et la frontière du run épingle ces sources. Mais ce qui décide de **quel
# programme le pack exécute** ne s'arrête pas à la config git : c'est `PATH`. Le
# pack appelle `git`, `claude`, `at`, `date`, `find`, `awk` par leur nom nu, dans
# le shell du pilote, pendant que le gate tourne.
#
# `scheduler_command` **fige ce `PATH`** et le met dans la file : ce que le run
# exécutait, le successeur l'exécutera aussi, des jours plus tard, sans humain.
#
# Trois questions : le pack regarde-t-il son `PATH`, qu'achète une session qui
# écrit dans un répertoire qui s'y trouve, et le successeur en hérite-t-il ?
#
# Instrument, pas test : chaque cas se termine par un `false` volontaire.

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() { harness_setup; }
teardown() { harness_teardown; }

sched_soon() { printf '%s\n' "$(($(date +%s) + ${1:-2}))"; }

sched_weekly_wall() {
  local reset="$1"
  printf '{"five_hour":{"utilization":0.10,"resets_at":%s},' "$(sched_soon 3600)"
  printf '"seven_day":{"utilization":0.85,"resets_at":%s},' "$reset"
  printf '"seven_day_opus":{"utilization":0.01,"resets_at":%s}}\n' "$reset"
}

sched_queued_command() { at_calls | sed -n 's/^command: //p'; }

@test "R5a a session plants a git on the pilot's PATH" {
  set +e
  # A directory on PATH that the same user can write is the ordinary case, not a
  # contrived one: ~/.local/bin, /usr/local/bin on many macs, node_modules/.bin
  # under `npm run`. Here it stands in front, the way a login shell puts a
  # user's own bin dir first.
  local mine="$RALPH_TEST_DIR/mine-bin"
  mkdir -p "$mine"
  export PATH="$mine:$PATH"

  use_tickets 01-alpha
  script_claude <<'FAKE'
#!/usr/bin/env bash
prompt="$(cat)"
# Find the first writable directory on PATH and put a `git` there. A passthrough
# that records, so the run carries on and the probe measures reach, not damage.
target=""
IFS=: read -ra dirs <<<"$PATH"
for d in "${dirs[@]}"; do
  case "$d" in *mine-bin) target="$d"; break ;; esac
done
if [ -n "$target" ]; then
  real="$(PATH="${PATH#*:}" command -v git)"
  cat >"$target/git" <<PLANT
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$RALPH_SHIM_STATE/planted-git.calls"
exec "$real" "\$@"
PLANT
  chmod +x "$target/git"
  printf '%s\n' "$target/git" >"$RALPH_SHIM_STATE/planted.where"
fi
surface="$(printf '%s' "$prompt" |
  sed -n 's/^\*\*Write-surface:\*\* //p' | head -1 | tr -d '`\r' | tr ',' ' ')"
for t in $surface; do
  mkdir -p "$(dirname "$t")" && printf 'written\n' >"$t"
done
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  echo "=== rc=$status 01-alpha=$(ticket_status 01-alpha)"
  echo "=== the session planted: $(cat "$SHIM_STATE/planted.where" 2>/dev/null || echo '(nowhere)')"
  echo "=== how many git calls of THIS run went through it: $(wc -l <"$SHIM_STATE/planted-git.calls" 2>/dev/null || echo 0)"
  echo "--- the first few, so we know who was calling"
  head -6 "$SHIM_STATE/planted-git.calls" 2>/dev/null || echo "(none)"
  echo "=== did any gate, any zone line, any receipt name it?"
  printf '%s\n' "$output" | grep -i 'mine-bin\|PATH' || echo "(nothing on stdout)"
  grep -rl 'mine-bin' "$PROJECT_DIR/receipts" "$FEATURE_DIR/run.log" 2>/dev/null || echo "(nothing durable)"
  echo "=== and it is still there after the run, outside every tree the pack judges"
  ls -l "$mine" 2>/dev/null

  # The pilot that was already running had `git` in its hash table long before
  # the session existed, so the plant cannot reach *this* shell. Every later run
  # is a fresh bash — and so is the successor, days out. Second run, same tree:
  rm -f "$SHIM_STATE/claude.script"
  rm -rf "$SHIM_STATE/claude.calls"
  use_tickets 02-beta
  run_loop
  echo "=== second run rc=$status 02-beta=$(ticket_status 02-beta)"
  echo "=== git calls of the SECOND run through the planted binary: $(wc -l <"$SHIM_STATE/planted-git.calls" 2>/dev/null || echo 0)"
  echo "--- who was calling"
  head -8 "$SHIM_STATE/planted-git.calls" 2>/dev/null || echo "(none)"
  echo "=== did that second run say a word about it?"
  printf '%s\n' "$output" | grep -i 'mine-bin\|PATH\|capability' || echo "(nothing)"
  set -e
  false
}

@test "R5b the successor inherits that PATH, frozen, days later" {
  set +e
  local mine="$RALPH_TEST_DIR/mine-bin"
  mkdir -p "$mine"
  export PATH="$mine:$PATH"

  use_tickets 01-alpha
  set_config USAGE_CACHE_TTL 0
  usage_respond "$(sched_weekly_wall "$(sched_soon 200000)")"
  run_loop
  echo "=== rc=$status at_call_count=$(at_call_count)"
  echo "=== the queued PATH"
  sched_queued_command | sed -n "s/^PATH=\\('[^']*'\\).*/\\1/p"
  echo "=== does it carry the session-writable directory?"
  sched_queued_command | grep -c 'mine-bin' || echo 0
  echo "=== and gate_frontier_residue, which is the one thing that can refuse to arm:"
  pack_run 'gate_frontier_residue || echo "(no residue)"'
  printf '%s\n' "$output"
  echo "(the residue is git configuration only — it has nothing to say about PATH)"
  set -e
  false
}

@test "R5c what the pack looks at, and what it does not" {
  set +e
  echo "=== every place the pack reads PATH:"
  grep -rn '\bPATH\b' "$PACK_DIR/loop.sh" "$PACK_DIR"/lib/*.sh |
    grep -v '_PATHS\|PATHS=' || echo "(none)"
  echo
  echo "=== the frontier's list of what makes git run a program ([46]):"
  pack_run 'gate_config_keys'
  printf '%s\n' "$output"
  echo
  echo "=== bare command names the pack executes (a sample):"
  grep -rhoE '\$\((git|at|date|find|awk|sed|mktemp) ' "$PACK_DIR"/lib/*.sh |
    sort | uniq -c | sort -rn | head
  set -e
  false
}
