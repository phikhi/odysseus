#!/usr/bin/env bats
#
# Smoke test of the foundation: the pack boots inside the fully injected
# environment, and every injection point the rest of the delivery relies on is
# actually wired. If this file is red, no other test can be trusted.

load helpers/harness
load helpers/assert

setup() {
  harness_setup
}

teardown() {
  harness_teardown
}

@test "loop.sh boots in the injected environment and says what it found" {
  run_loop
  # Exit 5: booted fine, but this tracker holds nothing to grind.
  assert_failure 5
  assert_output_contains "run start (feature=demo backend=local"
  assert_output_contains "nothing to grind"
}

@test "loop.sh sources every lib, and an empty lib/ is not an error" {
  run_loop
  assert_failure 5

  cat >"$PACK_DIR/lib/zz-probe.sh" <<'PROBE'
: >"$RALPH_DIR/../lib-was-sourced"
PROBE
  run_loop
  assert_failure 5
  assert_file_exists "$PROJECT_DIR/lib-was-sourced"
}

@test "loop.sh refuses to run without a config, with a usable message" {
  rm "$RALPH_CONFIG_FILE"
  run_loop
  assert_failure 2
  assert_output_contains "no config at"
  assert_output_contains "ralph.config.sh.example"
}

@test "the example config declares the whole configuration surface" {
  # Enumerated by hand, which is the one thing wrong with it: four keys added by
  # [24] and [06] were missing from this list for as long as nobody looked, so it
  # was quietly measuring a smaller surface than the pack has. Put back whole in
  # [23], along with that ticket's three — and left as a list, because deriving it
  # from the code means telling a config key from a RALPH_ runtime variable, which
  # is a second hand-written list wearing a grep costume.
  keys="FEATURE MODEL TEST_CMD TYPECHECK_CMD GUARDED_PATHS SOFT_LIMIT_TOKENS \
SESSION_STALL_TIMEOUT SESSION_TIMEOUT SESSION_KILL_GRACE \
BUDGET_CHECK THRESH_5H THRESH_WEEK USAGE_UA USAGE_URL USAGE_TOKEN_CMD \
USAGE_CACHE_TTL BUDGET_MAX_PAUSE \
ITER_CAP STERILE_K RETRY_N GATE_TIMEOUT \
HUMAN_CHECKPOINT_EVERY SCHEDULER WEEKLY_RESUME MAX_PARALLEL WORKTREE_PROVISION \
CLAIM_TTL \
TRACKER_BACKEND WAIT_CI WAIT_CI_TIMEOUT \
TRACKER_REPO TRACKER_API TRACKER_TOKEN_CMD TRACKER_USER \
FORGE_PAGE FORGE_PAGES FORGE_CACHE_TTL \
RECEIPT_REMOTE RECEIPT_BASE \
VISUAL_CMD VISUAL_REAL_ASSETS RUN_CMD \
PLAYTHROUGH_REINJECT_MAX LENSES SECURITY_PATHS SECURITY_REFS FIDELITY_REFS \
VISIBLE_PATHS LENS_DIFF_MAX_LINES \
LANG_INTERACT LANG_ARTIFACT LANG_CHECK LANG_CHECK_THRESHOLD LANG_CHECK_MIN_HITS \
LANG_PROSE_PATHS LANG_EXEMPT_PATHS \
RETRO RETRO_MODEL LEARNINGS_PROMOTE_AT RETRO_BRIEF_MAX_LINES \
CAPABILITY CAPABILITY_RECUR_AT \
LEARNINGS_INDEX_MAX RECEIPTS_RETENTION_DAYS RECEIPT_MAX_LINES"

  # env -i: the example must stand on its own, with nothing inherited.
  run env -i "$(command -v bash)" -c '
    set -u
    . "$1"
    for key in $2; do
      eval "seen=\${$key+set}"
      if [ "$seen" != set ]; then
        echo "undeclared key: $key"
        exit 1
      fi
    done
    echo "surface complete"
  ' _ "$PACK_DIR/ralph.config.sh.example" "$keys"
  assert_success
  assert_output_contains "surface complete"

  # And the direction the list above could not see, which is the one that keeps
  # failing: a key added to the example that nobody added here. [17] shipped three
  # (LANG_CHECK_MIN_HITS, LANG_PROSE_PATHS, LANG_EXEMPT_PATHS) and this test went
  # on reporting a complete surface, exactly as [24] and [06] had before it — the
  # comment above describes the defect and the assertion could not catch it. Two
  # directions make the list an equality instead of a subset, so a key that exists
  # in one place and not the other is a red test rather than a silence.
  for declared in $(sed -n 's/^\([A-Z_][A-Z0-9_]*\)=.*/\1/p' \
    "$PACK_DIR/ralph.config.sh.example"); do
    case " $keys " in
      *" $declared "*) ;;
      *) fail "the example declares $declared, which this test's list does not name" ;;
    esac
  done
}

@test "the headless posture turns auto-compact off" {
  assert_file_exists "$PACK_DIR/settings.json"
  assert_file_contains "$PACK_DIR/settings.json" '"autoCompactEnabled": false'
  assert_file_contains "$PACK_DIR/settings.json" '"DISABLE_AUTO_COMPACT"'
}

@test "the census of the pack's own globals is derived, not written down here" {
  # `harness__clear_env` wipes two namespaces. The config keys come from the
  # `.example`, which is where a project declares them. The pack's own globals
  # come from the pack's source, which is where the pack declares those — and
  # until [89] that half was six names typed by hand out of a hundred and forty
  # odd, held together by a sentence in [40] that nothing checked.
  #
  # The criterion, restated here rather than read back off the derivation, so
  # that the two can disagree:
  #
  #   a global of this pack is a name that is `RALPH_*`, or `<MODULE>_*` for a
  #   module of the pack — one source file of `harness_pack_sources` — and that
  #   the source reads or writes as a variable rather than printing as prose.
  #
  # This test holds the first half and lets the derivation hold the second: it
  # takes every upper-case token in the same zone, keeps the ones the criterion
  # names, and requires the census to account for each. A derivation that cannot
  # say what it does not see proves nothing ([85]).
  local sources pat f mod broad missing
  sources="$(harness_pack_sources "$RALPH_PACK_ROOT")"
  pat='^RALPH_'
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    mod="$(basename "$f" .sh | LC_ALL=C tr 'a-z-' 'A-Z_')"
    pat="$pat|^${mod}_"
  done <<MODULES
$sources
MODULES

  broad="$(printf '%s\n' "$sources" | while IFS= read -r f; do
    [ -n "$f" ] || continue
    cat "$f"
  done | grep -oE '[A-Z][A-Z0-9_]*' | LC_ALL=C sort -u | grep -E "$pat")"
  [ -n "$broad" ] || fail "the broad sweep found nothing: the zone or the pattern is wrong"

  # The one name the criterion catches and the census must not: `RALPH_REAL_USAGE`
  # is a sentence `init.sh` prints to a human and a paragraph in `budget.sh`, and
  # it is the opt-in switch `test/budget.bats` reads *after* `harness_setup`.
  # Unsetting it would turn a loud skip into a silent one, which is the same
  # false green this whole file exists to refuse.
  missing="$(printf '%s\n' "$broad" | grep -vxF -f <(harness_pack_globals) || true)"
  assert_equal "$missing" "RALPH_REAL_USAGE"

  local census
  census="$(harness_pack_globals)"

  # The walk, run again the way nothing protects it: three sources of the pack
  # match none of its three passes, and a pipeline that finds nothing exits 1,
  # which under the `set -e` of a test ends the walk mid-file and returns 0. The
  # cache is built inside an `if`, where errexit is disarmed, so the short census
  # would only ever appear somewhere else — twenty-one names instead of a hundred
  # and forty-nine, with nothing red to show for it.
  harness__derive_globals >"$RALPH_TEST_DIR/census-unprotected"
  assert_equal "$(grep -c . "$RALPH_TEST_DIR/census-unprotected")" \
    "$(printf '%s\n' "$census" | grep -c .)"

  # And the census is not allowed to be a longer list of the same six names: each
  # of these is a global of the pack under its own module's prefix, invisible to
  # any grep for `RALPH_`.
  for f in GATE_SURFACE_FIELD LOOP__FINDINGS ROUTER__PINNED_SURFACE \
    INIT_CLAUDE_OPEN HUMAN_LOOP__STATE RALPH_RETRO_STATE RALPH_PROJECT_ROOT; do
    printf '%s\n' "$census" | grep -qxF "$f" ||
      fail "the census does not name $f, which the pack assigns itself"
  done

  # What it must never name: a variable of this harness. The zone prunes `test/`,
  # so the property is structural rather than a list to maintain — and it has to
  # be, because `harness__clear_env` runs at the top of every `setup` and would
  # otherwise unset the ground it stands on.
  for f in RALPH_PACK_ROOT RALPH_TEST_DIR RALPH_TEST_FEATURE RALPH_FIXTURES \
    RALPH_HARNESS_DIR RALPH_KEEP_TMP RALPH_REAL_CLAUDE RALPH_SHIM_STATE; do
    if printf '%s\n' "$census" | grep -qxF "$f"; then
      fail "the census names $f, which belongs to the harness and not to the pack"
    fi
  done
}

@test "the environment is hermetic: an exported RALPH_ variable does not leak in" {
  # The pendant of the config-key test below, for the namespace the pack makes
  # for itself. Three names, each of which reaches a different part of a run:
  #
  #   RALPH_PROJECT_ROOT  `state_project_root` answers it when it is set, and it
  #                       is never assigned by the pack — it is how a successor
  #                       queued by `at` is told which tree it continues. A value
  #                       from a developer's shell points the whole run at
  #                       another tree.
  #   RALPH_RETRO_STATE   the directory `retro_guards` composes, where the two
  #                       objects [83] named live.
  #   RALPH_RECEIPT       where an iteration's evidence accumulates.
  #
  # Asserting on what changed, not on the run's exit code: a run pointed at
  # another tree can still exit 0.
  harness_teardown
  local elsewhere
  elsewhere="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/ralph-test.XXXXXX")" && pwd -P)"
  export RALPH_PROJECT_ROOT="$elsewhere"
  export RALPH_RETRO_STATE="$elsewhere"
  export RALPH_RECEIPT="$elsewhere"
  harness_setup
  use_tickets 01-alpha 02-beta

  run_loop
  local out="$output"

  unset RALPH_PROJECT_ROOT RALPH_RETRO_STATE RALPH_RECEIPT

  # The run did its work in its own tree, on its own tracker.
  assert_ticket_status 01-alpha resolved
  assert_ticket_status 02-beta resolved
  printf '%s\n' "$out" | grep -q "frontier empty after 2 iterations" ||
    fail "the run did not reach an empty frontier: $out"

  # And nothing of it landed where the environment pointed.
  assert_equal "$(find "$elsewhere" -mindepth 1 | head -n 5)" ""
  rm -rf "$elsewhere"
}

@test "the key the census is cached under sees the installer" {
  # `harness_pack_globals` reads about a megabyte of shell and runs before every
  # test, so it is cached under `$TMPDIR` on the template's key. A key blind to
  # one of the census's own inputs is a census that goes stale without saying so:
  # `init.sh` is pack source, it is where `INIT_CLAUDE_OPEN` and a dozen of its
  # neighbours live, and it sat outside this fingerprint until [89].
  local before after
  before="$(harness__pack_fingerprint)"
  mv "$RALPH_PACK_ROOT/init.sh" "$RALPH_PACK_ROOT/init.sh.probe"
  after="$(harness__pack_fingerprint 2>/dev/null)"
  mv "$RALPH_PACK_ROOT/init.sh.probe" "$RALPH_PACK_ROOT/init.sh"

  [ "$before" != "$after" ] ||
    fail "the fingerprint did not change when init.sh left: $before"
}

@test "a lib's global is assigned before it is read, whatever the shell exported" {
  # The other half of the [40] sentence `harness__clear_env` used to rest on:
  # every global of the pack is assigned unconditionally, so an inherited value
  # is harmless. Five names did not obey it — they were written `X="${X:-}"` at
  # the top of their lib, which preserves whatever the shell that started the run
  # had — and nothing noticed, because the only reader of that rule was a
  # hand-written list of six names elsewhere.
  #
  # Derived rather than listed: every name a lib assigns at the top of the file,
  # minus the config keys, whose whole mechanism is to take an inherited value.
  # `RALPH_CONFIG` and `RALPH_DIR` are entry-point globals and not in this zone:
  # `RALPH_CONFIG` is the one value this pack means to inherit, from the command
  # line `scheduler_command` queues, and its line says so.
  local names n
  names="$(harness_pack_sources "$RALPH_PACK_ROOT" | grep '/lib/' |
    while IFS= read -r n; do
      [ -n "$n" ] || continue
      LC_ALL=C sed -e "s/'[^']*'//g" -e 's/"[^"]*"//g' -e 's/#.*$//' "$n" |
        grep -oE '^[A-Z][A-Z0-9_]*=' | tr -d '='
    done | LC_ALL=C sort -u | grep -vxF -f <(sed -n 's/^\([A-Z_][A-Z0-9_]*\)=.*/\1/p' \
      "$RALPH_PACK_ROOT/.claude/ralph.config.sh.example" | LC_ALL=C sort -u))"
  [ "$(printf '%s\n' "$names" | grep -c .)" -gt 20 ] ||
    fail "the derivation found $(printf '%s\n' "$names" | grep -c .) names, so it is reading the wrong thing"
  printf '%s\n' "$names" | grep -qxF RALPH_RETRO_STATE ||
    fail "the derivation does not see RALPH_RETRO_STATE, which is one of the five"

  for n in $names; do
    export "$n=a-value-from-the-developers-shell"
  done
  export RALPH_PROBE_NAMES="$names"

  # Sourced the way an entry point sources it, then asked what survived.
  pack_run 'for n in $RALPH_PROBE_NAMES; do
      if [ "${!n}" = a-value-from-the-developers-shell ]; then
        printf "%s: preserved\n" "$n"
      fi
    done
    printf "asked about %s names\n" "$(printf %s "$RALPH_PROBE_NAMES" | grep -c .)"'
  assert_success
  assert_output_contains "asked about"
  refute_output_contains "preserved"
}

@test "the environment is hermetic: an exported config key does not leak in" {
  # Every key is written KEY="${KEY:-default}", so an exported value wins over
  # the file — and a developer with STERILE_K or SOFT_LIMIT_TOKENS in their
  # shell would silently be testing their shell instead of the pack.
  #
  # The keys probed here are the ones no test overwrites afterwards. MODEL and
  # DISABLE_AUTO_COMPACT cannot leak whatever the harness does — the config
  # assigns one unconditionally and the loop sets the other on the spawn — so
  # asserting on those two alone proved nothing.
  harness_teardown
  export MODEL=leaked-model
  export DISABLE_AUTO_COMPACT=leaked-value
  export ITER_CAP=1
  export SOFT_LIMIT_TOKENS=1
  harness_setup
  use_tickets 01-alpha 02-beta

  run_loop
  assert_success

  # A leaked ITER_CAP=1 would stop the run after one iteration; a leaked
  # SOFT_LIMIT_TOKENS=1 would terminate every session on its first event.
  assert_output_contains "frontier empty after 2 iterations"
  refute_output_contains "soft limit"
  assert_ticket_status 02-beta resolved

  run claude_call_argv 1
  refute_output_contains "leaked-model"

  run claude_call_env 1
  refute_output_contains "leaked-value"
  assert_output_contains "DISABLE_AUTO_COMPACT=1"
}

@test "node, npm and npx are shadowed: the pack stays bash-only" {
  # 99, not 127: a plain "command not found" would be indistinguishable from
  # the tool simply being absent, and it makes bats warn.
  run node --version
  assert_failure 99
  assert_output_contains "must not be required"

  run npm install
  assert_failure 99

  run npx create-anything
  assert_failure 99
}

@test "the tracker is a disposable tmpdir seeded with fixture tickets" {
  use_tickets

  case "$TRACKER_DIR" in
    "$RALPH_PACK_ROOT"/*) fail "tracker must not live in the repo: $TRACKER_DIR" ;;
  esac

  assert_ticket_status 01-alpha ready-for-agent
  assert_ticket_status 04-claimed claimed
  assert_ticket_status 06-resolved resolved
  assert_ticket_status 09-escalated ready-for-human
  assert_file_contains "$(ticket_file 03-blocked)" "**Blocked by:** 01"
  assert_file_exists "$FEATURE_DIR/spec.md"
  assert_file_exists "$PROJECT_DIR/CONTEXT.md"
}

@test "use_tickets can seed a single ticket" {
  use_tickets 01-alpha
  assert_ticket_status 01-alpha ready-for-agent
  refute_file_exists "$(ticket_file 02-beta)"
}

@test "the project is a git repo whose tree stays clean" {
  use_tickets
  set_config MAX_PARALLEL 2

  # A dirty tree would make the pre-spawn HEAD snapshot and the scope-guard
  # diff meaningless, so the harness must never leave one behind.
  run git -C "$PROJECT_DIR" status --porcelain
  assert_success
  assert_equal "$output" ""

  run git -C "$PROJECT_DIR" rev-parse HEAD
  assert_success

  run git -C "$PROJECT_DIR" ls-files
  assert_output_contains ".scratch/demo/issues/01-alpha.md"
  assert_output_contains ".claude/loop.sh"
}

@test "the claude shim records argv and prompt" {
  run bash -c 'printf "the ticket body\n" | claude -p --output-format stream-json --model test-model'
  assert_success
  assert_output_contains '"type":"result"'
  assert_output_contains '"subtype":"success"'

  assert_equal "$(claude_call_count)" "1"

  run claude_call_argv 1
  assert_output_contains "--output-format"
  assert_output_contains "stream-json"

  run claude_call_stdin 1
  assert_output_contains "the ticket body"
}

@test "the fake stream mirrors the real one, event for event" {
  run bash -c 'printf "x\n" | claude -p --model probe-model --output-format stream-json --verbose'
  assert_success

  # Sequence captured from claude 2.1.220. The smart-zone net watches this
  # stream and the budget gate reads rate_limit_event out of it, so an
  # invented stream would let both be designed against a fiction.
  assert_output_contains '"type":"system","subtype":"init"'
  assert_output_contains '"type":"rate_limit_event"'
  assert_output_contains '"rateLimitType":"five_hour"'
  assert_output_contains '"subtype":"thinking_tokens"'
  assert_output_contains '"type":"assistant"'
  assert_output_contains '"type":"result"'

  # init echoes back the model argument. The real one reports the model it
  # resolved instead — `--model haiku` comes back as claude-haiku-4-5-20251001 —
  # so this is one place the fake is deliberately not faithful. Nothing in the
  # pack reads the field; the contract only asks that it be there.
  assert_output_contains '"model":"probe-model"'

  # Keys on the final result that the loop reads today, or will.
  assert_output_contains '"num_turns"'
  assert_output_contains '"total_cost_usd"'
  assert_output_contains '"stop_reason"'
  assert_output_contains '"terminal_reason"'
  assert_output_contains '"api_error_status"'
  assert_output_contains '"permission_denials"'
}

@test "every line of the fake stream is valid JSON" {
  if ! command -v python3 >/dev/null 2>&1; then
    skip "no python3 to parse with"
  fi

  bash -c 'printf "x\n" | claude -p --output-format stream-json --verbose' \
    >"$RALPH_TEST_DIR/stream.jsonl"

  run python3 -c '
import json, sys
for i, line in enumerate(open(sys.argv[1]), 1):
    if line.strip():
        json.loads(line)
print("ndjson ok")
' "$RALPH_TEST_DIR/stream.jsonl"
  assert_success
  assert_output_contains "ndjson ok"
}

@test "the in-band rate limit signal is scriptable" {
  claude_rate_limit '{"status":"blocked","resetsAt":1784979600,"rateLimitType":"seven_day","isUsingOverage":false}'

  run bash -c 'printf "x\n" | claude -p'
  assert_success
  assert_output_contains '"status":"blocked"'
  assert_output_contains '"rateLimitType":"seven_day"'
}

@test "the claude shim is scriptable per scenario" {
  script_claude <<'FAKE'
#!/usr/bin/env bash
echo '{"type":"result","subtype":"error_during_execution","is_error":true,"session_id":"s"}'
exit 1
FAKE

  run bash -c 'echo prompt | claude -p'
  assert_failure 1
  assert_output_contains "error_during_execution"
  assert_equal "$(claude_call_count)" "1"
}

@test "TEST_CMD and TYPECHECK_CMD stubs have controllable exit codes" {
  run stub-cmd tests
  assert_success

  stub_exit tests 1
  run stub-cmd tests --watch
  assert_failure 1

  stub_exit typecheck 2
  run stub-cmd typecheck
  assert_failure 2

  assert_equal "$(stub_call_count tests)" "2"
  assert_equal "$(stub_call_count typecheck)" "1"
  assert_equal "$(stub_call_count lint)" "0"

  # And the config points the gate at them.
  assert_file_contains "$RALPH_CONFIG_FILE" "TEST_CMD='stub-cmd tests'"
  assert_file_contains "$RALPH_CONFIG_FILE" "TYPECHECK_CMD='stub-cmd typecheck'"
}

@test "the usage endpoint is injectable and records its User-Agent" {
  usage_respond '{"five_hour":{"utilization":0.42,"resets_at":"2026-07-25T12:00:00Z"},"seven_day":{"utilization":0.11,"resets_at":"2026-07-31T00:00:00Z"}}'

  run curl -s -H "User-Agent: claude-code/2.1.220" https://api.anthropic.com/api/oauth/usage
  assert_success
  assert_output_contains '"utilization":0.42'

  run curl_calls
  assert_output_contains "User-Agent: claude-code"
  assert_output_contains "/api/oauth/usage"

  usage_exit 7
  run curl -s https://api.anthropic.com/api/oauth/usage
  assert_failure 7
}

@test "the scheduler shim records the successor instead of arming one" {
  run bash -c 'echo "bash .claude/loop.sh" | at 04:00 2026-07-26'
  assert_success

  run at_calls
  assert_output_contains "argv: 04:00 2026-07-26"
  assert_output_contains "command: bash .claude/loop.sh"

  at_exit 1
  run bash -c 'echo noop | at now'
  assert_failure 1
}

@test "set_config overrides a key the pack then reads" {
  use_tickets 01-alpha
  set_config MODEL zzz-probe

  run_loop
  assert_success

  run claude_call_argv 1
  assert_output_contains "zzz-probe"
}

@test "set_config quotes a value the shell would otherwise eat" {
  # Small, and the whole suite leans on it: this is what writes the template's
  # config, and `harness__template_verify` writes it a second time on every test
  # to compare the cached one against it. It quotes with a parameter expansion
  # rather than a `sed` for that reason — two forks a line, sixty lines a test.
  set_config MODEL "a 'b' c"

  run tail -1 "$RALPH_CONFIG_FILE"
  assert_output_contains "MODEL='a '\''b'\'' c'"
}

@test "the project template is keyed by names as well as contents" {
  # Hashing only the bytes made the key blind to a rename: moving a lib reused
  # the cached template and quietly tested the previous layout.
  # The new name has to keep its place in the sort, or the contents would be
  # concatenated in a different order and the key would change for the wrong
  # reason — which is exactly how this test first passed against the bug.
  before="$(harness__pack_fingerprint)"
  mv "$RALPH_PACK_ROOT/.claude/lib/select.sh" "$RALPH_PACK_ROOT/.claude/lib/selection.sh"
  after="$(harness__pack_fingerprint)"
  mv "$RALPH_PACK_ROOT/.claude/lib/selection.sh" "$RALPH_PACK_ROOT/.claude/lib/select.sh"

  [ "$before" != "$after" ] || fail "the fingerprint did not change: $before"
}
# ── the cached template, as a thing the suite believes ───────────────────────
#
# `harness__template` keeps a whole project — the pack included — under
# `$TMPDIR/ralph-harness.<key>`, and every test is stamped out of it. The key is
# the content of the pack, so whoever knows the tree they are about to hand the
# gate knows the name to drop a copy under, and `$TMPDIR` is a directory anything
# on this machine can write. The pass of 22/09/2026 measured the whole chain: a
# lib of the tree gutted, a clean copy of the template dropped under the new key,
# the suite green on `1 tests, 0 failures` with the pack of the tree broken.
#
# These four stage the forgery from the other side — the copy is what gets
# doctored, which is the same forgery and the one a test can run without editing
# the repository under the rest of the suite's feet.

# A private copy of the template the suite is stamped from, under a `$TMPDIR` of
# this test's own, sitting under the same key.
template_copy() {
  local tmp="$1" key
  key="$(harness__pack_fingerprint)"
  mkdir -p "$tmp"
  cp -R "$(harness__template)" "$tmp/ralph-harness.$key"
  printf '%s\n' "$tmp/ralph-harness.$key"
}

# What `harness_setup` asks for, asked where the forged copy is what it finds.
# In a subshell of its own: taking a template moves `$PROJECT_DIR` and its
# neighbours, and this test is still standing in its own project.
template_take() {
  (
    TMPDIR="$1"
    RALPH_TEST_DIR="$1/take"
    mkdir -p "$RALPH_TEST_DIR"
    harness__template
  )
}

# Committed, because a forgery left loose is a forgery `git status` would name
# on its own — and the clause that reads `git status` is one of the four.
template_commit() {
  git -C "$1/project" add -A
  git -C "$1/project" commit -qm "forged"
}

@test "a cached template that is not the pack of this tree is refused" {
  local tmp="$RALPH_TEST_DIR/probe" root
  root="$(template_copy "$tmp")"

  run template_take "$tmp"
  assert_success

  : >"$root/project/.claude/lib/state.sh"
  template_commit "$root"

  run template_take "$tmp"
  assert_failure
  assert_output_contains ".claude/lib/state.sh"

  # The counter-witness, and it is not decoration: it says the refusal answered
  # to what the file holds and not to the fact that something was committed.
  cp "$RALPH_PACK_ROOT/.claude/lib/state.sh" "$root/project/.claude/lib/state.sh"
  template_commit "$root"

  run template_take "$tmp"
  assert_success
}

@test "a module the census does not name cannot ride in on a cached template" {
  # `loop.sh` sources `lib/*.sh` in lexical order, so a file that rides in on the
  # template is not a stray file: it is a module of the pack, in every test.
  local tmp="$RALPH_TEST_DIR/probe" root
  root="$(template_copy "$tmp")"
  printf 'RALPH_FORGED=1\n' >"$root/project/.claude/lib/zz-forged.sh"
  template_commit "$root"

  run template_take "$tmp"
  assert_failure
  assert_output_contains "zz-forged.sh"
}

@test "the config in a cached template is the one this harness writes" {
  # The one file of the template that is generated and not copied, so it is the
  # one file no source of the repository can be compared against. A forged value
  # here is a switch thrown under every test of the suite at once.
  local tmp="$RALPH_TEST_DIR/probe" root
  root="$(template_copy "$tmp")"
  printf 'MAX_PARALLEL=7\n' >>"$root/project/.claude/ralph.config.sh"
  template_commit "$root"

  run template_take "$tmp"
  assert_failure
  assert_output_contains "ralph.config.sh"
}

@test "what a cached template commits is what it holds" {
  # A lib in the commit and not in the tree is a difference no listing of the
  # tree can show. It matters because the pack rolls an iteration back to `HEAD`,
  # and the rollback is what would put the file there.
  local tmp="$RALPH_TEST_DIR/probe" root
  root="$(template_copy "$tmp")"
  printf 'RALPH_FORGED=1\n' >"$root/project/.claude/lib/zz-forged.sh"
  template_commit "$root"
  rm "$root/project/.claude/lib/zz-forged.sh"

  run template_take "$tmp"
  assert_failure
  assert_output_contains "zz-forged.sh"
}

@test "the cached template is a function of the pack, not of the test that built it" {
  # A cache that is compared back against its source has to be a cache of that
  # source alone. The feature baked into the template's config used to be
  # whichever feature the first test to want a template happened to ask for, and
  # nothing noticed because no test asks for another one.
  local tmp="$RALPH_TEST_DIR/probe"
  mkdir -p "$tmp"

  run bash -c '
    . "$1/test/helpers/harness.bash"
    TMPDIR="$2"
    RALPH_TEST_DIR="$2/build"
    RALPH_TEST_FEATURE=zz-other
    mkdir -p "$RALPH_TEST_DIR"
    harness__template >/dev/null
  ' _ "$RALPH_PACK_ROOT" "$tmp"
  assert_success

  # Built by a process that asked for another feature; taken by one that did not.
  run template_take "$tmp"
  assert_success
}
