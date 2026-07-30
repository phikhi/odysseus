# shellcheck shell=bash
# One contract, two subjects.
#
# The whole suite drives a hand-written fake `claude`. Green therefore proves the
# pack agrees with *our own assumptions* about Claude Code's interface, and
# nothing more. This file holds the assertions that make those assumptions
# falsifiable: the same set runs against the fake's stream on every `test/run.sh`,
# and against the real binary's stream when a human asks for it with
# RALPH_REAL_CLAUDE=1. Drift is caught in both directions — a fake that wandered
# away from the real format, and a Claude Code release that moved the format out
# from under the pack.
#
# What is in the contract: the events and fields the loop reads today, or that a
# ticket already commits to reading. Nothing else. An event type the pack does
# not understand may come and go without breaking anything, and asserting on it
# would only manufacture red runs — `system/thinking_tokens` is the example, and
# that is why it is absent here.
#
# Both streams are produced by the pack's own `session_spawn`, and read back by
# the pack's own `session_result_field` and `monitor_context_tokens`. That is
# deliberate: a contract that retyped the flags would check a copy of the pack
# rather than the pack, and a contract that parsed the fields itself could pass
# while the extractor the loop actually uses reads nothing.
#
# Public API
#   contract_spawn_fake OUT PROMPT [ARG ...]
#                                       stream from the fake on PATH
#   contract_spawn_real OUT PROMPT [ARG ...]
#                                       stream from the real binary, real HOME
#   contract_exit_code                  exit status of the last spawn
#   contract_prompt FILE MARKER         write a prompt asking for MARKER
#   contract_check STREAM EXIT MARKER [fake|real]
#                                       every invariant; findings on stdout
#   contract_real_available             is there a claude binary to test against
#   contract_unguarded_real_spawns FILE any real spawn that skipped the guard
#   contract_init_tools STREAM          the tool set init says the session has
#
# Kept bash 3.2 compatible, like the pack itself.

# Captured at load time, which is before setup() moves PATH and HOME aside for
# the fake: the real binary must not be shadowed by the shim, and its
# credentials live in the developer's HOME.
CONTRACT_HOST_PATH="$PATH"
CONTRACT_HOST_HOME="$HOME"
CONTRACT_HOST_TMPDIR="${TMPDIR:-/tmp}"

# Cheapest model that still exercises the real contract. Overridable for the day
# a release changes the format for one model family only.
CONTRACT_REAL_MODEL="${RALPH_REAL_MODEL:-haiku}"

CONTRACT_EXIT=0

# ── producing a stream ───────────────────────────────────────────────────────

contract_prompt() {
  printf 'Reply with exactly %s and nothing else.\n' "$2" >"$1"
}

# A throwaway working directory outside the repository. The real binary is about
# to run with permissions bypassed, so it gets an empty directory and not the
# checkout — and not the fixture project either, whose `.claude/` would feed it
# the pack's own settings.
contract__workdir() {
  mktemp -d "$CONTRACT_HOST_TMPDIR/ralph-contract.XXXXXX"
}

# The pack spawning a session, for real, in a subshell. The flags under test are
# whatever `session_spawn` passes — retyping them here is exactly the drift this
# file exists to catch. The libs come from the shipped pack rather than a
# fixture copy: the contract is about what gets installed in a project.
#
# OUT and PROMPT must be absolute: the spawn happens from the throwaway working
# directory. PATH and HOME are arguments rather than a prefix on the call,
# because a prefixed assignment on a shell function is not reliably scoped to it.
# Anything after the six positional arguments is passed on to session_spawn, and
# from there to `claude` — which is how the read-only posture a review lens is
# spawned with ([06]) gets checked against the real binary rather than asserted
# from argv.
contract__spawn() {
  local out="$1" prompt="$2" work="$3" model="$4" path="$5" home="$6"
  shift 6
  CONTRACT_EXIT=0
  (
    cd "$work" || exit 1
    PATH="$path" HOME="$home" MODEL="$model" \
      SOFT_LIMIT_TOKENS="${SOFT_LIMIT_TOKENS:-150000}" \
      bash -c '
        set -uo pipefail
        . "$1/lib/monitor.sh"
        . "$1/lib/session.sh"
        pack="$1"
        prompt="$2"
        out="$3"
        shift 3
        session_spawn "$prompt" "$out" "$@"
      ' _ "$RALPH_PACK_ROOT/.claude" "$prompt" "$out" "$@"
  ) || CONTRACT_EXIT=$?
  return 0
}

contract_spawn_fake() {
  local out="$1" prompt="$2" work
  shift 2
  work="$(contract__workdir)"
  contract__spawn "$out" "$prompt" "$work" "${MODEL:-test-model}" "$PATH" "$HOME" "$@"
  rm -rf "$work"
  return 0
}

# Same call, real binary. PATH and HOME are the ones captured before the harness
# replaced them; the shim never sees this spawn.
contract_spawn_real() {
  local out="$1" prompt="$2" work
  shift 2
  work="$(contract__workdir)"
  contract__spawn "$out" "$prompt" "$work" "$CONTRACT_REAL_MODEL" \
    "$CONTRACT_HOST_PATH" "$CONTRACT_HOST_HOME" "$@"
  if [ "${RALPH_KEEP_TMP:-0}" = 1 ]; then
    printf 'contract: kept %s\n' "$work" >&2
  else
    rm -rf "$work"
  fi
  return 0
}

contract_exit_code() {
  printf '%s\n' "$CONTRACT_EXIT"
}

contract_real_available() {
  PATH="$CONTRACT_HOST_PATH" command -v claude >/dev/null 2>&1
}

# Every @test that spawns the real binary, and whether it asked first. One
# finding per line, non-zero when it found one, so `run` reads naturally.
#
# This is the only thing standing between `test/run.sh` and a suite that spends
# quota: nothing else in the pack would notice a real spawn slipping into the
# default run. It would just be slower — and still green.
contract_unguarded_real_spawns() {
  awk '
    /^@test / { name = $0; guarded = 0 }
    /RALPH_REAL_CLAUDE/ { guarded = 1 }
    /contract_spawn_real/ && !guarded {
      printf "%s spawns the real binary without asking RALPH_REAL_CLAUDE first\n", name
      bad = 1
    }
    END { exit bad ? 1 : 0 }
  ' "$1"
}

# ── the contract ─────────────────────────────────────────────────────────────

# Every finding is one line, and says which side to go and fix: a fake that
# drifted from the format, or a pack that depends on something the format no
# longer has. A finding with neither reading would leave whoever runs this with
# a red test and no next step.
contract__found=0

contract__finding() {
  printf '%s\n' "$*"
  contract__found=1
}

contract__note() {
  printf 'note: %s\n' "$*"
}

# Reads the pack's own extractor into this shell. Function definitions only —
# sourcing these libs runs nothing.
contract__load_pack() {
  # shellcheck source=../../.claude/lib/monitor.sh
  . "$RALPH_PACK_ROOT/.claude/lib/monitor.sh"
  # shellcheck source=../../.claude/lib/session.sh
  . "$RALPH_PACK_ROOT/.claude/lib/session.sh"
}

# NDJSON, one event per line. The monitor reads this stream line by line while it
# is being written and carries a trailing partial line over to the next tick, so
# an event spread over two lines — or two events sharing one — would be counted
# as something it is not.
contract__check_ndjson() {
  local file="$1" n=0 line
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    if [ -z "$line" ]; then
      contract__finding "line $n is empty: the stream must be one JSON object per line"
      continue
    fi
    case "$line" in
      '{'*'}') ;;
      *) contract__finding "line $n is not a single JSON object, it starts '$(printf '%.12s' "$line")' and ends '$(printf '%s' "$line" | tail -c 12)'" ;;
    esac
  done <"$file"

  [ "$n" -gt 0 ] || contract__finding "the stream is empty: the session emitted no events at all"

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$file" <<'PY' || contract__finding "the stream is not valid NDJSON (see the parse error above)"
import json, sys
bad = 0
for i, line in enumerate(open(sys.argv[1]), 1):
    if not line.strip():
        continue
    try:
        obj = json.loads(line)
    except ValueError as exc:
        print("line %d does not parse: %s" % (i, exc))
        bad = 1
        continue
    if not isinstance(obj, dict):
        print("line %d is not a JSON object" % i)
        bad = 1
sys.exit(bad)
PY
  else
    contract__note "no python3: lines were checked structurally, not parsed"
  fi
}

# The first event, and the two things the pack needs from it. `permissionMode` is
# the one that matters: an AFK session that stops to ask a human is a night lost,
# and `--dangerously-skip-permissions` is the only thing standing between the
# pack and that.
contract__check_init() {
  local file="$1" first
  first="$(head -1 "$file")"
  case "$first" in
    *'"type":"system"'*'"subtype":"init"'* | *'"subtype":"init"'*'"type":"system"'*) ;;
    *)
      contract__finding "the first event is not system/init: $(printf '%.80s' "$first")"
      return 0
      ;;
  esac
  case "$first" in
    *'"permissionMode":"bypassPermissions"'*) ;;
    *) contract__finding "init does not report bypassPermissions: --dangerously-skip-permissions no longer has the effect the pack depends on, and a session can block on a prompt" ;;
  esac
  case "$first" in
    *'"session_id":"'*) ;;
    *) contract__finding "init carries no session_id" ;;
  esac
  # Only that it is there: the real binary answers with the model it resolved,
  # the fake with the argument it was given, and the pack reads neither.
  case "$first" in
    *'"model":"'*) ;;
    *) contract__finding "init carries no model" ;;
  esac

  # The tool set the session ended up with. [06] gives a review lens
  # `--tools Read,Grep,Glob` because that *removes* the write tools rather than
  # refusing them permission — `--allowedTools` means nothing under
  # `--dangerously-skip-permissions`. That is prevention, and prevention that
  # nothing checks is a hope: this is where it becomes falsifiable, because init
  # reports what the session actually has.
  #
  # A lens that could write would be a model putting code into the repository with
  # no verdict on it. The gate also measures and undoes such a write
  # (gate__contain_lens_writes), and that half holds whatever this flag does — but a
  # release that stopped honouring `--tools` would turn a guarantee into a cleanup,
  # silently, and this is the only thing that would say so.
  case "$first" in
    *'"tools":['*) ;;
    *)
      contract__finding "init carries no tools array: nothing can confirm a review lens was given a read-only session"
      return 0
      ;;
  esac
}

# What init says the session may do, as a comma-separated list. Read off the event
# rather than off argv: argv is what the pack asked for, this is what it got.
contract_init_tools() {
  sed -n 's/.*"tools":\[\([^]]*\)\].*/\1/p' "$1" | head -1 | tr -d '"'
}

# The last event, read the way the loop reads it. The loop greps every
# `"type":"result"` line and keeps the last: if the real result were no longer
# last, or no longer matched that grep, the loop would journal an empty outcome
# for a session that succeeded.
contract__check_result_event() {
  local file="$1" last matched
  last="$(tail -1 "$file")"
  case "$last" in
    *'"type":"result"'*) ;;
    *)
      contract__finding "the last event is not a result: $(printf '%.80s' "$last")"
      return 0
      ;;
  esac
  matched="$(grep '"type":"result"' "$file" | tail -1)"
  if [ "$matched" != "$last" ]; then
    contract__finding "the last result line the loop's grep finds is not the last line of the stream"
  fi
}

# The fields, through `session_result_field` — the pack's own reader. Checking
# them with a parser of our own would let this pass while the loop journals
# nothing.
contract__check_result_fields() {
  local file="$1" value key
  for key in subtype is_error num_turns total_cost_usd session_id \
    stop_reason terminal_reason result; do
    value="$(session_result_field "$file" "$key")"
    if [ -z "$value" ]; then
      contract__finding "the pack's extractor reads nothing for '$key' on the result event"
    fi
  done

  value="$(session_result_field "$file" subtype)"
  [ "$value" = success ] ||
    contract__finding "result subtype is '$value', not 'success', on a prompt that cannot fail"

  value="$(session_result_field "$file" is_error)"
  [ "$value" = false ] ||
    contract__finding "result is_error is '$value', not 'false', on a prompt that cannot fail"

  # The journal's two figures: an iteration that reports turns=0 cost=0 for a
  # session that ran is a receipt nobody can audit ([10]).
  value="$(session_result_field "$file" num_turns)"
  case "$value" in
    '' | *[!0-9]*) contract__finding "num_turns is '$value', which the journal cannot report as a count" ;;
    0) contract__finding "num_turns is 0 for a session that answered" ;;
  esac

  value="$(session_result_field "$file" total_cost_usd)"
  case "$value" in
    '' | *[!0-9.]*) contract__finding "total_cost_usd is '$value', which the journal cannot report as a cost" ;;
  esac

  # Present as objects, so not readable by an extractor built for flat scalars.
  # [08] reads modelUsage, [07] will read permission_denials.
  local last
  last="$(tail -1 "$file")"
  for key in usage modelUsage permission_denials api_error_status; do
    case "$last" in
      *"\"$key\":"*) ;;
      *) contract__finding "the result event has no '$key', which a delivered or committed ticket reads" ;;
    esac
  done
}

# The prompt on stdin was received. Everything else here could hold on a session
# that answered a different question entirely — the pack hands its whole ticket
# over on stdin, and a `-p` that started reading the prompt from somewhere else
# would produce a perfectly well-formed stream about nothing.
contract__check_prompt_landed() {
  local file="$1" marker="$2" answer
  answer="$(session_result_field "$file" result)"
  case "$answer" in
    *"$marker"*) ;;
    *) contract__finding "the answer '$answer' does not contain the marker '$marker' the prompt asked for: the prompt on stdin did not reach the session" ;;
  esac
}

# The smart-zone net's signal ([04]). It has to arrive *while the session runs*,
# which means on the assistant events — a usage figure that only appears on the
# final result can be journalled but can never terminate anything.
contract__check_usage_while_running() {
  local file="$1" events line tokens key counted=0
  events="$(grep '"type":"assistant"' "$file" || true)"
  if [ -z "$events" ]; then
    contract__finding "the stream has no assistant event: the smart-zone net has nothing to watch"
    return 0
  fi

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    tokens="$(monitor_context_tokens "$line")"
    case "$tokens" in
      '') contract__finding "an assistant event yields no context size: the smart-zone net gets no signal from it" ;;
      *[!0-9]*) contract__finding "an assistant event yields '$tokens', which is not a token count" ;;
      0) contract__finding "an assistant event reports a context of 0 tokens" ;;
      *) counted=$((counted + 1)) ;;
    esac

    # Each of the four figures separately, and this is the check with teeth. A
    # renamed key does not make the monitor fail: `monitor__int` reads it as
    # absent and the sum simply comes out smaller. Rename `cache_read_input_tokens`
    # and a real session under-reports by the ~18K its cached system prompt
    # occupies — the net then fires late, or not at all, and every test stays
    # green because they all use synthetic figures of their own.
    for key in input_tokens cache_creation_input_tokens cache_read_input_tokens output_tokens; do
      case "$line" in
        *"\"$key\":"*) ;;
        *) contract__finding "an assistant event has no '$key': the monitor adds up what it finds and silently under-counts the window without it" ;;
      esac
    done
  done <<CONTRACT_EOF
$events
CONTRACT_EOF

  [ "$counted" -gt 0 ] ||
    contract__finding "no assistant event carries usage the monitor can read: the soft limit could only fire after the session had already ended"
  return 0
}

# The in-band budget signal [08] is committed to reading. It costs no request:
# the loop already captures the whole stream.
contract__check_rate_limit_event() {
  local file="$1" line key
  line="$(grep '"type":"rate_limit_event"' "$file" | tail -1)"
  if [ -z "$line" ]; then
    contract__finding "the stream carries no rate_limit_event: [08] reads the budget posture out of it, and without it the only source left is an HTTP call"
    return 0
  fi
  for key in status resetsAt rateLimitType; do
    case "$line" in
      *"\"$key\":"*) ;;
      *) contract__finding "rate_limit_info has no '$key', which [08] reads" ;;
    esac
  done
}

# ── the whole contract ───────────────────────────────────────────────────────

# Findings on stdout, non-zero if there were any. One function so that the fake
# and the real binary cannot end up checked against two drifting lists.
#
# SUBJECT — `fake` or `real` — only changes the closing line, and that line is
# the point: the same finding means opposite work depending on who produced the
# stream. On the fake it is the shim that drifted; on the real binary it is the
# pack that is reading a field the format no longer has.
contract_check() {
  local file="$1" exit_code="$2" marker="$3" subject="${4:-}"
  contract__found=0
  contract__load_pack

  if [ ! -s "$file" ]; then
    contract__finding "no stream at $file: the session wrote nothing"
    contract__verdict "$subject"
    return 1
  fi

  # The loop treats a non-zero exit as a failed iteration whatever the stream
  # says, so this is part of the contract and not a detail of the harness.
  [ "$exit_code" = 0 ] ||
    contract__finding "the session exited $exit_code on a prompt that cannot fail: the loop would count this iteration as failed"

  contract__check_ndjson "$file"
  contract__check_init "$file"
  contract__check_result_event "$file"
  contract__check_result_fields "$file"
  contract__check_prompt_landed "$file" "$marker"
  contract__check_usage_while_running "$file"
  contract__check_rate_limit_event "$file"

  [ "$contract__found" = 0 ] && return 0
  contract__verdict "$subject"
  return 1
}

# Which side of the bridge to go and repair. Without this a reader gets a true
# statement about a stream and no idea whether the pack or the shim is wrong.
contract__verdict() {
  case "$1" in
    fake)
      printf '%s\n' "-> the fake claude has drifted from the real format: fix test/helpers/shims/claude, re-capturing with the command in its header"
      ;;
    real)
      printf '%s\n' "-> the real claude no longer offers what the pack reads: fix the pack first, then bring the fake back in line with a fresh capture"
      ;;
    *)
      printf '%s\n' "-> either the shim drifted from the real format, or the pack reads a field the format no longer has: run RALPH_REAL_CLAUDE=1 test/run.sh test/contract-claude.bats to find out which"
      ;;
  esac
}
