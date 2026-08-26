#!/usr/bin/env bats
#
# Passe transversale — probe 6.
#
# The sibling `docs/frontiere-de-confiance.md` names and calls "non sondé, même
# famille, aucun propriétaire": a `smudge` filter installed through
# `.git/info/attributes` rewrites what the rollback's `git checkout-index`
# produces. Probed here.

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() { harness_setup; }
teardown() { harness_teardown; }

receipt_path() {
  printf '%s/receipts/%s/%s.md\n' "$PROJECT_DIR" "$RALPH_TEST_FEATURE" "$1"
}

@test "P6 a smudge filter survives the rollback and rewrites what it restores" {
  use_tickets 01-alpha
  set_config RETRY_N 0
  set_config STERILE_K 1
  stub_exit tests 1

  # A tracked file with known content, so "what the rollback put back" is a
  # question with an answer.
  mkdir -p "$PROJECT_DIR/src"
  printf 'the original line\n' >"$PROJECT_DIR/src/alpha.txt"
  git -C "$PROJECT_DIR" add -A
  git -C "$PROJECT_DIR" commit -q -m "fixture: a tracked file"

  script_claude <<'FAKE'
#!/usr/bin/env bash
cat >/dev/null
root="$(cat "$RALPH_SHIM_STATE/project-dir")"
printf 'the session was here\n' >"src/alpha.txt"
mkdir -p "$root/.git/info"
printf '* filter=ralphprobe\n' >>"$root/.git/info/attributes"
cat >>"$root/.git/config" <<CFG
[filter "ralphprobe"]
	smudge = sed s/original/REWRITTEN-BY-THE-SESSION/
	clean = cat
CFG
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  echo "=== rc=$status"
  printf '%s\n' "$output" | head -25
  echo "=== 01-alpha=$(ticket_status 01-alpha)"
  echo "=== what the rollback left in the main tree:"
  cat "$PROJECT_DIR/src/alpha.txt"
  echo "=== git's own idea of the file:"
  git -C "$PROJECT_DIR" show HEAD:src/alpha.txt
  echo "=== did anything say a word?"
  grep -h 'attributes\|smudge\|filter' "$PROJECT_DIR/receipts/$RALPH_TEST_FEATURE"/*.md \
    "$FEATURE_DIR/run.log" 2>/dev/null || echo "(nothing)"
  false
}
