#!/usr/bin/env bats
#
# Ticket [109] — sondes du run réel. Instruments, pas tests : chaque cas finit
# par un `false` volontaire pour imprimer ce qu'il a vu.
# Lancer avec `bash test/run.sh <fichier> </dev/null`.

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() {
  harness_setup
}

teardown() {
  harness_teardown
}

show() {
  printf '=== statut du run : %s\n' "$status"
  printf '%s\n' "$output" | grep -E '^ralph:|^  ' | grep -v 'budget:' | sed 's/^/    /' | head -40
  printf '=== exclude : [%s]\n' "$(tr '\n' ' ' <"$PROJECT_DIR/.git/info/exclude" 2>/dev/null)"
  printf '=== core.excludesFile : [%s]\n' "$(git -C "$PROJECT_DIR" config --get core.excludesFile || true)"
  printf '=== appels claude : %s\n' "$(claude_call_count)"
}

@test "Q1 deux itérations : la 1re élargit (pin intact), la 2e élargit et détruit" {
  use_tickets 01-alpha
  script_claude <<'SCRIPT'
#!/usr/bin/env bash
cat >/dev/null
state="$RALPH_SHIM_STATE"
n="$(cat "$state/seq" 2>/dev/null || echo 0)"; n=$((n + 1)); printf '%s\n' "$n" >"$state/seq"
main="$(cat "$state/project-dir")"
excl="$main/.git/info/exclude"
mkdir -p "$(dirname "$excl")" src
if [ "$n" = 1 ]; then
  printf 'src/first.txt\n' >>"$excl"; printf 'x\n' >src/first.txt
else
  printf 'src/second.txt\n' >>"$excl"; printf 'x\n' >src/second.txt
  for pin in "$TMPDIR"/ralph-ignore.*; do [ -d "$pin" ] && rm -rf "$pin"; done
fi
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
SCRIPT
  run_loop_own_tmp
  show
  set -e
  false
}

@test "Q2 chemin crash : .gitignore suivi, élargir, détruire, exit 1" {
  use_tickets 01-alpha
  printf 'cache/\n' >>"$PROJECT_DIR/.gitignore"
  harness__commit "test: the project ignores cache/"
  script_claude <<'SCRIPT'
#!/usr/bin/env bash
cat >/dev/null
state="$RALPH_SHIM_STATE"
main="$(cat "$state/project-dir")"
excl="$main/.git/info/exclude"
mkdir -p "$(dirname "$excl")" src
printf 'src/backdoor.txt\n' >>"$excl"; printf 'x\n' >src/backdoor.txt
for pin in "$TMPDIR"/ralph-ignore.*; do [ -d "$pin" ] && rm -rf "$pin"; done
exit 1
SCRIPT
  run_loop_own_tmp
  show
  set -e
  false
}

@test "Q3 pin détruit + manifeste du témoin du run réécrit au digest courant" {
  use_tickets 01-alpha
  script_claude <<'SCRIPT'
#!/usr/bin/env bash
cat >/dev/null
state="$RALPH_SHIM_STATE"
main="$(cat "$state/project-dir")"
excl="$main/.git/info/exclude"
mkdir -p "$(dirname "$excl")" src
printf 'src/backdoor.txt\n' >>"$excl"; printf 'x\n' >src/backdoor.txt
digest="$(cksum <"$excl" | awk '{ print $1 "." $2 }')"
for c in "$TMPDIR"/ralph-frontier.*; do
  [ -f "$c/manifest" ] || continue
  awk -F'\t' -v OFS='\t' -v d="$digest" '$1 == "dir" && $2 == ".git/info/exclude" { $3 = d } { print }' \
    "$c/manifest" >"$c/m" && mv -f "$c/m" "$c/manifest" && printf '%s\n' "$c" >>"$state/common.forged"
done
for pin in "$TMPDIR"/ralph-ignore.*; do [ -d "$pin" ] && rm -rf "$pin"; done
exit 1
SCRIPT
  run_loop_own_tmp
  printf '=== témoin du run forgé : %s\n' "$(cat "$SHIM_STATE/common.forged" 2>/dev/null)"
  show
  set -e
  false
}

@test "Q6 pin détruit + témoin du run détruit" {
  use_tickets 01-alpha
  script_claude <<'SCRIPT'
#!/usr/bin/env bash
cat >/dev/null
state="$RALPH_SHIM_STATE"
main="$(cat "$state/project-dir")"
excl="$main/.git/info/exclude"
mkdir -p "$(dirname "$excl")" src
printf 'src/backdoor.txt\n' >>"$excl"; printf 'x\n' >src/backdoor.txt
for c in "$TMPDIR"/ralph-frontier.* "$TMPDIR"/ralph-ignore.*; do [ -d "$c" ] && rm -rf "$c" && printf '%s\n' "$c" >>"$state/destroyed"; done
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
SCRIPT
  run_loop_own_tmp
  printf '=== détruits : %s\n' "$(tr '\n' ' ' <"$SHIM_STATE/destroyed" 2>/dev/null)"
  show
  set -e
  false
}
