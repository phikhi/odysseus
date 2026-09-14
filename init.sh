#!/usr/bin/env bash
# init.sh — put this pack into a repository, once, by hand.
#
# This script is the one component of the pack that lives **outside a run**, and
# that is not a convenience, it is the only position the sealing leaves it ([31]).
# Almost everything it writes — `CLAUDE.md`, `.claude/settings.json`, the file the
# next run sources under the name it carries — is sealed: no ticket's
# write-surface can cover those paths, so a delivery session can never write them
# and an `init.sh` the loop tried to deliver would be red at every attempt. A
# human runs this, once, before there is a run.
#
# Being outside a run is also what entitles it to sweep ([13], [36], [62]): an
# iteration that swept `$TMPDIR` would delete the witness of another one.
#
#   bash init.sh --target .          install the pack into a repository
#   bash init.sh sweep --target .    take away what killed runs left behind
#   bash init.sh --print-payload     what the deposit is, `source<TAB>destination`
#   bash init.sh --print-refusals    what `loop.sh` refuses to start on
#   bash init.sh --help
#
# The two `--print-*` forms read the pack `--from` names, so they come after it
# on the command line, and they answer without touching anything.
#
# The engine is bash, and the `npx` wizard (`bin/ralph-init.js`) is a shim that
# execs this file: a machine without node installs the same way, which is user
# story 7 of the spec and is checked by the suite running with `node`, `npm` and
# `npx` shadowed by a hard failure.
#
# Exit codes
#   0  installed (or swept)
#   1  a run holds this working tree — the installer writes what a run reads, so
#      it takes the same tree lock a run takes ([22], [46])
#   2  refused to start: not a git repository, no commit, a PATH this pack cannot
#      witness, a pack source missing a piece, or the pack's own repository
#   3  a forced confirmation was not given. Not 2: 2 is a machine that cannot
#      carry a run, 3 is a human who did not confirm a value that has no safe
#      default, and the two are answered differently
#
# `set -e` is deliberately **not** on, where every other entry point of this pack
# has it. This file sources the pack's libs and calls their public census
# functions, and those answer *non-zero for "nothing to say"* — `gate_leftovers`
# returns 1 when a machine is clean, `concurrency_leftovers` returns 1 when no
# worktree is registered. Under errexit the tidiest machine would end the
# installer at its first honest answer. Every mutating step below therefore
# checks its own status and calls `init__die`.
set -uo pipefail

# Parameter expansion rather than `dirname`, for [52]'s reason: the PATH check
# below refuses a PATH this pack cannot witness, and `dirname` would be the first
# program resolved through the very PATH being refused.
_init_src="${BASH_SOURCE[0]}"
case "$_init_src" in
  */*) _init_dir="${_init_src%/*}" ;;
  *) _init_dir='.' ;;
esac
INIT_SELF="$(cd "$_init_dir" && pwd)/${_init_src##*/}"
INIT_SOURCE="$(cd "$_init_dir" && pwd)"
unset _init_src _init_dir

INIT_TAB="$(printf '\t')"
INIT_TARGET="$PWD"
INIT_ACTION=install
INIT_ASSUME_YES=0
INIT_KEEP_SELF=0
INIT_SWEEP=1
INIT_TMPFILES=""
INIT_NOTES=""
INIT_KEPT=""
INIT_ANSWERS=""
INIT_ENV_PRESENT=""
INIT_ENV_VALUE=""

# ── talking to the human ─────────────────────────────────────────────────────

init__say() { printf 'init: %s\n' "$*"; }
init__warn() { printf 'init: %s\n' "$*" >&2; }

init__die() {
  printf 'init: %s\n' "$*" >&2
  exit "${INIT_DIE_CODE:-2}"
}

# A finding kept for the report at the end rather than printed as it is found: a
# wizard that interleaves findings with questions is a wizard whose findings are
# scrolled off the screen by the answers.
init__note() {
  INIT_NOTES="${INIT_NOTES}$*
"
}

# The header above, up to the first line that is not a comment. A line range
# would be a number to keep in step with an edit three screens away.
init__usage() {
  awk 'NR > 1 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "$INIT_SELF"
}

init__tmp_add() {
  INIT_TMPFILES="${INIT_TMPFILES}$1
"
}

init__tmp_drop() {
  INIT_TMPFILES="$(printf '%s' "$INIT_TMPFILES" | grep -vxF -- "$1")
"
}

# One path per line and never a whitespace-joined list, which is [33]'s rule and
# applies to this file's own bookkeeping as much as to the pack's: a project
# directory may hold a space.
init__cleanup() {
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -e "$f" ] && rm -f "$f"
  done <<TMPFILES
$INIT_TMPFILES
TMPFILES
  return 0
}

# ── what the deposit is ──────────────────────────────────────────────────────

# The deposit, as `<source path><TAB><destination path>` lines, and it is the
# answer to a question [07] left open on purpose: *what is the pack, exactly?*
#
# Until this file the definition of the pack was the test harness's own
# `harness__install_pack` — loop.sh, human-loop.sh, settings.json, the config
# example, `lib/*.sh` — which is a definition of fact and nobody's decision. Two
# things are added here, and each is a decision this ticket owed:
#
#   - **the substrate is deposited, dereferenced.** `.claude/skills/` in this
#     repository is twenty-two symlinks into `.agents/skills/`, and the README's
#     `cp -R .claude` recipe deposited twenty-two *broken* links in the target,
#     verified. Copied with `-L`, so what lands in the project is files. The whole
#     directory and not the eleven the spec names: a hand-picked subset is a
#     twelfth list to keep in step with a prose paragraph, and the criterion that
#     can be read off the disk — *the skills this pack carries* — is the directory
#     itself.
#   - **the lock is deposited with it**, as `.claude/skills-lock.json`, which is
#     what "pinned to a version" means for a vendored substrate: the hashes the
#     copy was taken at, in the project, beside the copy. At the project root it
#     would collide with a project that vendors skills of its own.
#
# `docs/agents/` is in, because a ticket written by `to-tickets` is read against
# those conventions, and a project that does not carry them grinds tickets whose
# format nothing agrees on.
#
# `settings.local.json` is out, deliberately: it is the machine-local half of the
# posture, and depositing one developer's permissions into every project is the
# kind of silent inheritance the sealing exists to stop.
init_payload() {
  printf '%s\t%s\n' \
    '.claude/loop.sh' '.claude/loop.sh' \
    '.claude/human-loop.sh' '.claude/human-loop.sh' \
    '.claude/settings.json' '.claude/settings.json' \
    '.claude/ralph.config.sh.example' '.claude/ralph.config.sh.example' \
    '.claude/lib' '.claude/lib' \
    '.claude/skills' '.claude/skills' \
    'skills-lock.json' '.claude/skills-lock.json' \
    'docs/agents' 'docs/agents'
}

# The one destination a reinstall must leave exactly as it found it.
#
# Everything else in the payload is *the pack*, under this pack's own names, and
# overwriting it is the upgrade path: a project installing a newer checkout is
# asking for a newer `loop.sh` and newer libs. `.claude/settings.json` is the
# exception because the **name belongs to Claude Code and not to this pack**: a
# project already using Claude Code keeps its permissions, its hooks and its MCP
# servers in that file, and a deposit that replaced it would take all of that
# away in order to add two keys. There is no JSON merge written in bash worth
# trusting with someone's permissions, so the file is left alone and the posture
# it has to carry is *checked and named* instead — which is the same arrangement
# as `CLAUDE.md` and `ralph.config.sh`, and the only one consistent with [31]
# sealing all three.
init_project_owned() {
  printf '%s\n' '.claude/settings.json'
}

init__is_project_owned() {
  local owned
  while IFS= read -r owned; do
    [ -n "$owned" ] || continue
    [ "$owned" = "$1" ] && return 0
  done <<OWNED
$(init_project_owned)
OWNED
  return 1
}

# The durable directories a run writes into, provisioned so an artefact has a
# place from the first iteration rather than being created by whichever iteration
# happens to produce one first (spec §6).
init_durable_dirs() {
  printf '%s\n' 'docs/adr' 'docs/playthroughs' 'receipts' '.scratch'
}

# ── the environment, before the pack overwrites it ───────────────────────────

# Every config key this shell was *given*, taken before a single lib is sourced.
#
# It has to happen here and it took a defect to see why: `init__load_pack` sources
# `ralph.config.sh.example`, and the example assigns **every** key. After that
# `${TEST_CMD+set}` is true whatever the human did, so a presence check would pass
# for a key nobody ever spelt — which is a forced confirmation that confirms
# nothing, in the one file whose whole job is to make a human say a value out loud.
init__snapshot_env() {
  local key value
  for key in $(sed -n 's/^\([A-Z_][A-Z0-9_]*\)=.*/\1/p' \
    "$INIT_SOURCE/.claude/ralph.config.sh.example"); do
    eval "[ \"\${$key+set}\" = set ]" || continue
    eval "value=\"\${$key}\""
    INIT_ENV_PRESENT="$INIT_ENV_PRESENT $key"
    INIT_ENV_VALUE="${INIT_ENV_VALUE}${key}${INIT_TAB}${value}
"
    # A key given on the command line is an answer like any other, so it is
    # written into the project's config rather than dropped on the floor. Asking
    # overwrites it below: `init__answer_of` reads the last record.
    init__record "$key" "$value"
  done
}

init__env_has() {
  case " $INIT_ENV_PRESENT " in
    *" $1 "*) return 0 ;;
  esac
  return 1
}

init__env_of() {
  printf '%s' "$INIT_ENV_VALUE" | sed -n "s/^$1${INIT_TAB}//p" | tail -1
}

# ── loading the pack ─────────────────────────────────────────────────────────

# Source a pack the way an entry point sources it: the configuration first, then
# every lib in lexical order. What that buys is the whole reason this file is
# allowed to be short — the sweeping specification, the PATH refusal, the census
# of what killed runs left and the list of what a run refuses to start on are all
# *asked of the pack* instead of retyped here. [28]'s fault is the one this file
# would be most likely to repeat: `gate_tmp_names` stayed at six names out of
# eighteen for twenty tickets because a second copy of it existed.
#
# The config is the project's when it has one and the shipped example otherwise —
# the example assigns every key, so the libs below source cleanly under `set -u`
# before a project has answered anything.
init__load_pack() {
  local dir="$1" cfg lib
  [ -f "$dir/loop.sh" ] || return 1
  cfg="$dir/ralph.config.sh"
  [ -f "$cfg" ] || cfg="$dir/ralph.config.sh.example"
  [ -f "$cfg" ] || return 1

  RALPH_DIR="$dir"
  RALPH_CONFIG="$cfg"
  # The tree this pack would act on, said rather than derived from `$RALPH_DIR/..`:
  # during an install the pack being sourced is the *source's*, which sits in
  # another repository altogether, and every lock and census below has to answer
  # about the target.
  RALPH_PROJECT_ROOT="$INIT_TARGET"
  export RALPH_DIR RALPH_CONFIG RALPH_PROJECT_ROOT

  # shellcheck source=/dev/null
  . "$cfg" || return 1
  for lib in "$dir"/lib/*.sh; do
    [ -e "$lib" ] || continue
    # shellcheck source=/dev/null
    . "$lib" || return 1
  done
  return 0
}

# ── preconditions ────────────────────────────────────────────────────────────

# What `loop.sh` refuses to start on, asked of `loop.sh` rather than retyped.
#
# A refusal is a `<name>_preflight` called as a bare command whose failure ends
# the run — `gate_path_preflight || exit 2` before the locks, the eight inside
# `loop_preflight` — and that shape is what this reads. `tracker_preflight` is
# invoked as a command substitution and is therefore not in the set, which is
# correct and not luck: it *reports findings* about the tracker's contents and
# returns non-zero when it found some, so a run starts with them all the same.
#
# `loop_preflight` itself is the one name taken back out, because it is the
# function whose body this derives and it lives in an entry point nothing can
# source — `loop.sh` ends on `loop_main "$@"`.
init_refusals() {
  local pack="$1"
  sed -n 's/^ *\([a-z_][a-z_0-9]*_preflight\) *|| *.*/\1/p' "$pack/loop.sh" |
    grep -v '^loop_preflight$' | LC_ALL=C sort -u
}

# Whether this is a tree at all, asked **before the lock** and not with the rest.
#
# The order is the difference between a diagnosis and a lie, and it took the
# wrong message to see it: the tree lock lives in the git directory, so on a
# target that is not a repository `tree_lock_acquire` fails for want of one and
# the operator was told "a run holds this working tree" about a directory where
# no run has ever started.
init_tree_preflight() {
  git -C "$INIT_TARGET" rev-parse --git-dir >/dev/null 2>&1 ||
    init__die "$INIT_TARGET is not a git repository — the scope-guard diffs git trees, so a pack installed outside one would judge nothing and undo nothing. Run \`git init\` and make a first commit first"
  return 0
}

# Everything that decides whether this project is grindable at all, before a
# single file is written. Refusals are fatal; the rest is kept for the report.
init_preflight() {
  local entry list key found='' n=0

  # The footgun this file would otherwise carry: run with no arguments inside the
  # pack's own repository it would install the pack onto itself and — standing
  # inside its own target — delete itself on the way out. Install only: sweeping
  # the pack's own repository is the one machine with the most to sweep.
  if [ "$INIT_SOURCE" = "$INIT_TARGET" ] && [ -f "$INIT_TARGET/test/mutate.sh" ]; then
    init__die "this is the pack's own repository, not a project to install it into — pass --target <project> (the pack is the source, never the destination)"
  fi

  if ! git -C "$INIT_TARGET" rev-parse HEAD >/dev/null 2>&1; then
    init__die "$INIT_TARGET has no commit yet — every iteration runs in a worktree of its own and git cannot make one out of nothing ([13]). Commit something first"
  fi

  # [52], and the reason it is here rather than only in the loop: this is the one
  # refusal in the list that is not read out of a file. It is a property of the
  # shell the human is standing in, so an operator whose profile carries one colon
  # too many finds out at install time instead of at the first `exit 2` of the
  # first night.
  gate_path_preflight ||
    init__die "the PATH above cannot carry a run. This installer does not rewrite it: a project has the right to keep its \`claude\` and its \`git\` where it wants, and a pack that chose its own PATH would break every non-standard installation in silence ([52])"

  # And what a PATH may carry that is not a refusal but is worth a line: an entry
  # inside the tree a session writes to. `node_modules/.bin` spelt absolutely is
  # what `npm run` does and is ordinary; it is watched like every other writable
  # directory the pack resolves a program through.
  list="${PATH:-}:"
  while [ -n "$list" ]; do
    entry="${list%%:*}"
    list="${list#*:}"
    case "$entry" in
      "$INIT_TARGET" | "$INIT_TARGET"/*)
        init__note "PATH carries $entry, inside the tree a session writes to. Nothing here refuses it — \`npm run\` puts node_modules/.bin there — but the run takes a baseline of what its own names resolve to and reports any program that moves under it ([52])."
        ;;
    esac
  done

  # [46]: the config keys that decide what git *executes* and what git
  # *transforms* are pinned per run and turn an iteration red when one moves. A
  # `~/.gitconfig` carrying one in good faith — a legitimate fsmonitor exists —
  # would turn every iteration red for a reason that has nothing to do with any
  # ticket, and this is the only place in the pack that can say so before the
  # night. The set is asked of `gate_config_keys` and never retyped.
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    # The names git answers with, not the patterns asked for: a note that reads
    # `credential\..*\.helper` names a regex and not a setting anybody has.
    found="$found $(git -C "$INIT_TARGET" config --get-regexp "^$key\$" 2>/dev/null |
      sed 's/ .*//' | tr '\n' ' ')"
  done <<KEYS
$(gate_config_keys)
KEYS
  found="$(printf '%s' "$found" | tr ' ' '\n' | sed '/^$/d' | LC_ALL=C sort -u |
    tr '\n' ' ' | sed 's/ *$//')"
  n="$(printf '%s' "$found" | wc -w | tr -d ' ')"
  [ "$n" = 0 ] || init__note "$n of the git-config keys this pack pins are already set here: $found. A value already there in good faith is the baseline and is fine; one **added while a run is going** is a red iteration on innocent work ([46]). Set them before a run, or through .claude/ralph.config.sh, never with \`git config\` at three in the morning."

  # [08]: the half of the usage budget that nothing here has ever verified.
  if [ -z "$(init__effective USAGE_TOKEN_CMD)" ]; then
    init__note "USAGE_TOKEN_CMD is empty, so the proactive half of the usage budget is not wired: the run flies on the in-band signal alone, which only arrives *after* a session has started — a session the API refuses is paid for before the wall is known ([08]). The probe that lifts the assumption is RALPH_REAL_USAGE=1 with a token command."
  fi

  # The program the whole pack exists to spawn. Named, not refused: a project is
  # allowed to install the pack on a machine where `claude` is not on the PATH
  # yet, and finding that out here is the point.
  command -v claude >/dev/null 2>&1 ||
    init__note "\`claude\` is not on this PATH. Every session, review lens, retro and value gate is a \`claude\` process, so a run here would fail at its first spawn."

  # [24]/[50]: a project that ignores `.claude/` in full is a real case, and it
  # changes what the pack can promise in two directions at once.
  if git -C "$INIT_TARGET" check-ignore -q .claude 2>/dev/null; then
    init__note "this project ignores .claude/. Two consequences, both already decided: what a session writes there is judged and undone all the same, because GUARDED_PATHS forces it into the snapshot ([24]); and a guarded path the project ignores is **committed** rather than named and lost, because the durable commit stages the approved paths with --force ([50]). Keep .claude in GUARDED_PATHS."
  fi
  return 0
}

# ── forced confirmations ─────────────────────────────────────────────────────
#
# The keys with no safe default. A wrong value here does not make a run fail, it
# makes the gate **green without proving anything**, which is the one failure this
# pack has no other defence against: `TEST_CMD="true"` passes every automatic
# check there is. No exit code can catch that. Only the human, at install time,
# reading the value out loud.
#
# Off a terminal — `--yes`, a CI, the npx wizard's non-interactive path — the
# confirmation becomes: the value must be **present in the environment**, spelt by
# whoever ran the command. That is weaker, and it is reported as weaker. What it
# is not is skippable: a missing forced key is exit 3, never a default.

# Keys where an empty answer is not an answer.
init__forced_required() {
  printf '%s\n' FEATURE TEST_CMD TYPECHECK_CMD LANG_ARTIFACT LANG_CHECK \
    SCHEDULER VISUAL_REAL_ASSETS
}

# Keys where empty *is* a legitimate answer and being asked is the whole point.
# WORKTREE_PROVISION ships empty on purpose ([13]), and a project with a `.env` or
# a `node_modules` that never heard the question watches its first gate go red for
# a reason that has nothing to do with the ticket. RUN_CMD and VISUAL_CMD ship
# empty too, and with both empty the terminal value gate refuses before spending a
# session, opens a ticket on the human sink and the run exits 4 — every night,
# with all the work done and the feature never closed ([11]).
init__forced_optional() {
  printf '%s\n' RUN_CMD VISUAL_CMD WORKTREE_PROVISION
}

init__is_tty() {
  [ "$INIT_ASSUME_YES" = 0 ] && [ -t 0 ] && [ -t 1 ]
}

# What the shipped example gives a key, read out of the example rather than
# retyped — the harness's `config_default` exists for the same reason. Both
# operators are matched: three keys are written `${KEY-…}` because empty is a
# statement for them.
init_config_default() {
  sed -n "s/^$1=\"\\\${$1:\{0,1\}-\(.*\)}\"\$/\1/p" \
    "$INIT_SOURCE/.claude/ralph.config.sh.example" | head -1
}

# The value this install will end up writing for a key: the answer if there is
# one, the environment if it was given, the shipped default otherwise.
init__effective() {
  local v
  v="$(init__answer_of "$1")"
  [ -n "$v" ] && {
    printf '%s' "$v"
    return 0
  }
  init__answer_has "$1" && return 0
  init_config_default "$1"
}

init__answer_of() {
  printf '%s' "$INIT_ANSWERS" | sed -n "s/^$1${INIT_TAB}//p" | tail -1
}

init__answer_has() {
  printf '%s' "$INIT_ANSWERS" | grep -q "^$1${INIT_TAB}"
}

init__answer_keys() {
  printf '%s' "$INIT_ANSWERS" | sed -n "s/${INIT_TAB}.*//p" | LC_ALL=C sort -u
}

init__record() {
  INIT_ANSWERS="${INIT_ANSWERS}$1${INIT_TAB}$2
"
}

# Ask for a key, or take it from the environment. `why` is printed above the
# question and again nowhere else: a value confirmed without its reason is a value
# nobody read.
init__ask() {
  local key="$1" why="$2" preset reply
  preset="$(init__env_of "$key")"

  if init__is_tty; then
    printf '\n  %s\n' "$why"
    printf '  %s [%s]: ' "$key" "${preset:-$(init_config_default "$key")}"
    IFS= read -r reply || reply=''
    [ -n "$reply" ] || reply="${preset:-$(init_config_default "$key")}"
    init__record "$key" "$reply"
    return 0
  fi

  init__env_has "$key" || return 1
  init__record "$key" "$preset"
  return 0
}

init_confirmations() {
  local key value missing=''

  # Presence first, and all of it before any question: a wizard that refuses on
  # the ninth key after eight answers is a wizard nobody finishes.
  if ! init__is_tty; then
    for key in $(init__forced_required) $(init__forced_optional); do
      init__env_has "$key" || missing="$missing $key"
    done
    if [ -n "$missing" ]; then
      INIT_DIE_CODE=3 init__die "not a terminal, so these values cannot be confirmed by a human and must be spelt on the command line:$missing. They are the keys with no safe default: a wrong one makes the gate green without proving anything, which is the one failure this pack cannot catch by itself"
    fi
  fi

  init__ask FEATURE "The tracker this run grinds: .scratch/<FEATURE>/issues/. The loop refuses to start on an empty one, and it no longer creates the directory itself — a typo used to make a phantom tracker and a run that reported success on nothing." || true
  init__ask TEST_CMD "The full test suite. It must exit non-zero on failure, and it must actually prove something: TEST_CMD=\"true\" passes every automatic check this pack has. Nothing downstream can tell a real suite from a no-op — this question is the only place it is asked." || true
  init__ask TYPECHECK_CMD "The type or static check. \`none\`, spelt out, is how a project declares it has none; empty is a config nobody filled in, and the loop refuses it." || true
  init__ask LANG_ARTIFACT "The language of this project's durable prose. The pack has word lists for six (en fr es de it pt); a project outside them is refused at startup unless LANG_CHECK=off, and it repeats that at every iteration." || true
  init__ask LANG_CHECK "The objective language gate: on or off. This is the one key whose misreading switches a check off in silence, which is why it is confirmed." || true
  init__ask SCHEDULER "How a one-shot successor is queued at a weekly reset: auto | at | systemd-run | none. \`none\` is a legitimate declaration — this machine has no scheduler — and nothing downstream disputes it, which is exactly why an unintended one has to be caught here: one night in two would stop for good, looking like a run that had armed a successor ([09])." || true
  init__ask RUN_CMD "How this feature is run end to end, for the terminal value gate. Empty is allowed and has a price: with RUN_CMD and VISUAL_CMD both empty the value gate refuses before spending a session, opens a ticket on the human sink and the run exits 4 — every night, with all the work done and the feature never closed ([11])." || true
  init__ask VISUAL_CMD "The visual check of the same gate. Same trade as above." || true
  init__ask VISUAL_REAL_ASSETS "1 if the two commands above run against this project's real assets, 0 otherwise. Nothing in this pack verifies that claim; it is a statement the project makes about its own commands." || true
  init__ask WORKTREE_PROVISION "What a fresh iteration worktree needs and a commit does not carry — a .env, a node_modules, a virtualenv — one path per line. Empty on purpose, and asked rather than defaulted ([13])." || true

  for key in $(init__forced_required); do
    value="$(init__answer_of "$key")"
    [ -n "$value" ] ||
      INIT_DIE_CODE=3 init__die "$key was left empty, and empty is not an answer for it"
  done

  # What a return code *can* catch, said for exactly what it is. This recognises
  # the spelling of a no-op and not the property of being one: a TEST_CMD of `make
  # test` behind an empty target passes here and proves nothing, and no check
  # written anywhere could tell. The confirmation above is the control; this is a
  # courtesy.
  case "$(init__answer_of TEST_CMD)" in
    true | : | 'exit 0' | /bin/true | /usr/bin/true)
      INIT_DIE_CODE=3 init__die "TEST_CMD is \"$(init__answer_of TEST_CMD)\", which is a no-op: the gate would be green on every iteration without running anything. This catches the spelling and not the property — a suite that proves nothing under another name passes here — which is why the value is confirmed out loud rather than pattern-matched"
      ;;
  esac

  # [50]: a GUARDED_PATHS written wide is the one value that turns the whole
  # ignored zone into something the durable commit puts in the project's history,
  # and this confirmation is the only place that can see it.
  case "$(init__effective GUARDED_PATHS)" in
    '.' | './')
      INIT_DIE_CODE=3 init__die "GUARDED_PATHS is \".\", which forces the entire tree into the snapshot — and since [50] a guarded path the project ignores is committed rather than named, so every ignored file a write-surface covers would enter this project's history"
      ;;
  esac
  case "$(init__effective LANG_EXEMPT_PATHS)" in
    '.' | './')
      INIT_DIE_CODE=3 init__die "LANG_EXEMPT_PATHS is \".\", which exempts the whole tree and switches the language gate off while leaving it reporting green"
      ;;
  esac

  # Seen rather than confirmed, which is the difference [14] asked for: a tier
  # that costs a session per delivered ticket is a value a project should watch go
  # past at install time, even though no wrong answer produces a false green.
  init__note "RETRO_MODEL is \"$(init__effective RETRO_MODEL)\" and the retro runs once per delivered ticket; LENSES is \"$(init__effective LENSES)\" and each lens named there is a fresh \`claude\` on every green iteration. Count 1 + n sessions per delivered ticket."

  case "$(init__effective MAX_PARALLEL)" in
    1) ;;
    *)
      init__note "MAX_PARALLEL is $(init__effective MAX_PARALLEL). Above 1 this is a trade and not a performance setting: a live session runs while *another* iteration is being gated, so what that gate writes in \$TMPDIR is within its reach, and nothing in the pack can close that — see docs/frontiere-de-confiance.md."
      ;;
  esac

  # [18]: a remote backend is not an equivalent option with a different name.
  case "$(init__effective TRACKER_BACKEND)" in
    github | gitlab)
      init__note "TRACKER_BACKEND=$(init__effective TRACKER_BACKEND) needs TRACKER_REPO, TRACKER_TOKEN_CMD (a command that prints the token, never the token) and TRACKER_USER; without TRACKER_REPO every operation refuses at its first call, by a status and a sentence ([71]). FORGE_PAGE and FORGE_PAGES bound a listing and FORGE_CACHE_TTL bounds how long a reading is served. Two things it does not buy: there is no receipts directory at all — the receipt is a pull request and **nothing in this pack attests its provenance** ([18]), and nothing restores what a session writes to a remote tracker beyond what [73] puts back — and WAIT_CI ships as \`auto\`, so each ticket waits for a CI and pushes a branch: a backend with no usable remote ends every green ticket as ready-for-human with Escalation: ci-unreachable."
      ;;
  esac
  return 0
}

# ── the deposit ──────────────────────────────────────────────────────────────

init_deposit() {
  local src dst from to n=0 broken=''

  # [07], measured: the substrate in this repository is symlinks, and a copy that
  # follows the links is the difference between a project that has the skills and
  # a project that has twenty-two dangling names. A link that does not resolve at
  # the source would be copied as a dangling name here too, so it is refused —
  # loudly, with the names — rather than deposited.
  if [ -d "$INIT_SOURCE/.claude/skills" ]; then
    for from in "$INIT_SOURCE"/.claude/skills/*; do
      [ -L "$from" ] || continue
      [ -e "$from" ] || broken="$broken ${from##*/}"
    done
    [ -z "$broken" ] ||
      init__die "the substrate at $INIT_SOURCE/.claude/skills carries links that resolve to nothing:$broken. Depositing them would put dangling names in the project, which is exactly what the README's \`cp -R\` recipe did"
  fi

  while IFS="$INIT_TAB" read -r src dst; do
    [ -n "$src" ] || continue
    from="$INIT_SOURCE/$src"
    to="$INIT_TARGET/$dst"

    # The bootstrap case: this script was copied into the project along with its
    # payload, so the pack is already where it is going. There is nothing to copy
    # — a piece is either the very same file as its destination, which a copy
    # would truncate, or it travelled under the name it has in the project rather
    # than the one it has in the pack — and the only honest question left is
    # whether the project *has* each piece, which the check below the loop asks.
    if [ "$INIT_SOURCE" = "$INIT_TARGET" ]; then
      continue
    fi
    if [ "$from" -ef "$to" ] 2>/dev/null; then
      continue
    fi
    if [ -e "$to" ] && init__is_project_owned "$dst"; then
      INIT_KEPT="${INIT_KEPT}${dst}
"
      continue
    fi

    [ -e "$from" ] ||
      init__die "the pack source at $INIT_SOURCE is missing $src — pass --from <a checkout of the pack>"

    if [ -d "$from" ]; then
      mkdir -p "$to" || init__die "cannot create $to"
      # -L: what lands in the project is files, never links into a directory the
      # project has not got.
      cp -RL "$from"/. "$to"/ || init__die "cannot copy $src into $dst"
    else
      mkdir -p "${to%/*}" || init__die "cannot create ${to%/*}"
      cp "$from" "$to" || init__die "cannot copy $src to $dst"
    fi
    n=$((n + 1))
  done <<PAYLOAD
$(init_payload)
PAYLOAD

  # Asserted on what landed rather than on what was copied, which is the same
  # rule the rest of this pack is held to: a count of copies is not a project
  # that has the pack, and in the bootstrap flow above the count is zero by
  # construction.
  while IFS="$INIT_TAB" read -r src dst; do
    [ -n "$dst" ] || continue
    [ -e "$INIT_TARGET/$dst" ] ||
      init__die "$dst is not in the project after the deposit — the pack source at $INIT_SOURCE is incomplete"
  done <<PAYLOAD
$(init_payload)
PAYLOAD

  chmod +x "$INIT_TARGET/.claude"/*.sh 2>/dev/null || true

  # "Pinned to a version" for the pack itself and not only for the substrate:
  # what was deposited, taken from where, on what day. A project that upgrades
  # wants to know what it had, and a bug report wants to be able to say it.
  {
    printf 'pack\t%s\n' "$(init__pack_version)"
    printf 'source\t%s\n' "$INIT_SOURCE"
    printf 'commit\t%s\n' "$(git -C "$INIT_SOURCE" rev-parse HEAD 2>/dev/null || printf 'unknown')"
    printf 'installed\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } >"$INIT_TARGET/.claude/pack.version" ||
    init__die "cannot write .claude/pack.version"

  init__say "deposited $n path(s) into .claude/ and docs/agents/"
  return 0
}

# Read out of package.json, which is the file the registry versions this by. A
# `sed` and not a JSON parser: the engine is bash, and a version is one line.
init__pack_version() {
  local v
  v="$(sed -n 's/^ *"version" *: *"\([^"]*\)".*/\1/p' \
    "$INIT_SOURCE/package.json" 2>/dev/null | head -1)"
  printf '%s' "${v:-unknown}"
}

# The headless posture, on the one file this installer refuses to overwrite.
#
# Auto-compact is not a preference here: a delivery session that compacts
# mid-ticket loses the ticket, which is the whole of the smart-zone net ([04]).
# So the posture is required — and on a project that already had this file it is
# *said*, not imposed, because what the file also holds is that project's
# permissions.
init_settings() {
  local file="$INIT_TARGET/.claude/settings.json"
  case "$INIT_KEPT" in
    *'.claude/settings.json'*) ;;
    *) return 0 ;;
  esac

  if grep -q '"autoCompactEnabled"[[:space:]]*:[[:space:]]*false' "$file" &&
    grep -q 'DISABLE_AUTO_COMPACT' "$file"; then
    init__say "kept this project's .claude/settings.json — it already carries the headless posture"
    return 0
  fi

  init__note "this project's .claude/settings.json was kept exactly as it was: it holds your permissions, your hooks and your MCP servers, and no JSON merge written in bash is worth trusting with those. It does **not** carry the headless posture, and a delivery session that auto-compacts in the middle of a ticket loses the ticket ([04]). Add \"autoCompactEnabled\": false at the top level and \"DISABLE_AUTO_COMPACT\": \"1\" under \"env\" — the shipped file is at $INIT_SOURCE/.claude/settings.json."
  return 0
}

init_dirs() {
  local dir feature
  feature="$(init__answer_of FEATURE)"
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    mkdir -p "$INIT_TARGET/$dir" || init__die "cannot create $dir"
  done <<DIRS
$(init_durable_dirs)
DIRS

  # The tracker's own directory, which the loop stopped creating on purpose: a
  # typo in FEATURE used to make a phantom tracker and a run that exited on
  # success having ground nothing.
  [ -n "$feature" ] || return 0
  mkdir -p "$INIT_TARGET/.scratch/$feature/issues" ||
    init__die "cannot create .scratch/$feature/issues"
  init__say "provisioned .scratch/$feature/issues, docs/adr, docs/playthroughs, receipts"
  return 0
}

# ── the two files that are merged and never overwritten ──────────────────────

# Replace what lies between the markers, or append the block. Idempotent by
# construction: a reinstall rewrites the pack's block and touches nothing else,
# which is what makes "never overwritten" hold for a file the project owns.
#
# Line numbers from `grep -nxF` and not `awk -v`: awk processes escape sequences
# in a `-v` assignment, so a block carrying a backslash would arrive at awk as
# something else. The block is prose written by this file today; it is a file a
# later ticket edits.
init__merge_block() {
  local file="$1" open="$2" close="$3" bodyfile="$4" tmp start end
  tmp="$file.ralph-init.$$"
  init__tmp_add "$tmp"

  start=''
  [ -f "$file" ] && start="$(grep -nxF -- "$open" "$file" | head -1 | cut -d: -f1)"

  if [ -n "$start" ]; then
    end="$(grep -nxF -- "$close" "$file" | head -1 | cut -d: -f1)"
    [ -n "$end" ] || end="$(wc -l <"$file" | tr -d ' ')"
    {
      [ "$start" -gt 1 ] && sed -n "1,$((start - 1))p" "$file"
      cat "$bodyfile"
      sed -n "$((end + 1)),\$p" "$file"
    } >"$tmp" || return 1
  else
    {
      if [ -f "$file" ]; then
        cat "$file"
        printf '\n'
      fi
      cat "$bodyfile"
    } >"$tmp" || return 1
  fi

  mv -f "$tmp" "$file" || return 1
  init__tmp_drop "$tmp"
  return 0
}

INIT_GITIGNORE_OPEN='# ── ralph pack ── managed by init.sh; this block is replaced on reinstall'
INIT_GITIGNORE_CLOSE='# ── end ralph pack ──'

# The ignore rules, and this is not hygiene — it is a condition of operation, and
# a decision this installer owes in writing.
#
# **Why.** The loop commits every green iteration, and `gate_tree_snapshot` runs
# `git add -A` into a throwaway index **twice per iteration**, which writes a blob
# for every untracked, unignored file — a session stream of several megabytes
# included. Measured on the fixture project: five iterations with a ~1 MB stream
# each took `.git` from 180 KB to 512 KB and left 115 loose objects. A night is
# dozens of iterations with real streams; the project's object store grows by
# hundreds of megabytes of blobs nobody will ever read. Worse, and probed: a
# session that runs `git add -A` leaves `.run.lock/pid`, the stream and the prompt
# **staged in the project's index**, ready to leave with the next human commit.
# The tracker protection of [21] unstages `issues/` and cannot do more, because
# the stream is written *during* the window it watches. These rules are the only
# mechanism that closes that, and this is the only component that can write them.
#
# **What it costs, said rather than deduced ([24]).** What `.gitignore` covers is
# invisible to the scope-guard and to the rollback. Since [24] the subtraction is
# at least *declared*: `gate_is_bookkeeping` is what stops the loop's own
# bookkeeping being reported as an unjudged write, and a test holds it. Every line
# below is a line of `docs/frontiere-de-confiance.md`.
#
# **`receipts/` is in the block, and that is the decision.** A receipt is written
# by the iteration into the **main** tree, outside every tree the gate judges, and
# nothing in this pack commits it. Left un-ignored, the one thing that can happen
# to it is the thing that must not: a project that commits `receipts/` puts an
# earlier ticket's audit document inside the judged tree, where a write-surface can
# reach it and no guard would notice — GUARDED_PATHS does not cover it and the
# sealing of [31] does not either. Ignoring changes nothing about who guards them
# (nobody does, before or after) and removes the only way they enter history.
#
# **`docs/playthroughs/`, `LEARNINGS.md`, `learning-records/` and `docs/adr/` are
# deliberately *not* in the block**, for two different reasons. The lesson index
# and its records are **sealed** ([14], [31]): committing them is what puts them
# under guard, so the hole described above does not reopen there. A playthrough is
# the proof a feature closed — the one artefact of the five worth having in the
# project's history — and leaving it un-ignored and uncommitted is what makes a
# human see it listed by the drain's refusal.
init_gitignore_block() {
  cat <<IGNORE
$INIT_GITIGNORE_OPEN
#
# Run bookkeeping. Not hygiene: \`gate_tree_snapshot\` writes a blob for every
# untracked, unignored file twice per iteration, and a session stream is
# megabytes. Without these the project's object store grows by hundreds of
# megabytes a night, and a \`git add -A\` leaves the lock and the stream staged.
.scratch/*/run.log
.scratch/*/.run.lock/
.scratch/*/.session.*.jsonl
# The scheduled successor's output. \`at\` posts a job's output and a machine with
# no MTA loses it, so the redirection is not optional ([09]).
.scratch/*/successor.log
# A remote backend's local sidecar: the claim, the request number, the receipt
# URL. It must survive the run and must not enter history ([18], [77]).
.scratch/*/.forge-claims
.scratch/*/.forge.guard/
# Audit receipts. Written into the main tree, outside every judged tree, and
# committed by nothing here. A project that committed them would put an earlier
# ticket's audit document inside the tree a write-surface can reach ([10]).
receipts/
$INIT_GITIGNORE_CLOSE
IGNORE
}

init_gitignore() {
  local body="$INIT_TARGET/.gitignore.ralph-init-body.$$"
  init__tmp_add "$body"
  init_gitignore_block >"$body" || init__die "cannot write the ignore block"
  init__merge_block "$INIT_TARGET/.gitignore" \
    "$INIT_GITIGNORE_OPEN" "$INIT_GITIGNORE_CLOSE" "$body" ||
    init__die "cannot write .gitignore"
  rm -f "$body"
  init__tmp_drop "$body"
  init__say "merged the ignore block into .gitignore"
  return 0
}

INIT_CLAUDE_OPEN='<!-- ralph pack: start — managed by init.sh, edit outside this block -->'
INIT_CLAUDE_CLOSE='<!-- ralph pack: end -->'

# `CLAUDE.md` is **sealed** ([31]): a fresh `claude` reads it at startup, so no
# write-surface can cover it and this installer is its only writer. Merged and
# never overwritten — a project's own rules are the reason the file exists.
init_claude_block() {
  local feature="$1"
  cat <<BLOCK
$INIT_CLAUDE_OPEN

## The tracker

Issues and specs are markdown under \`.scratch/$feature/\`: one file per ticket in
\`issues/NN-slug.md\`, the feature spec in \`spec.md\`. A ticket is self-contained —
no context is inherited between sessions, so it has to read alone. The conventions
are in \`docs/agents/\`.

A ticket carries \`Status:\`, \`Blocked by:\`, \`Write-surface:\` and its acceptance
criteria. **The loop marks tickets, never the session**: marking happens after the
gate, and a \`Status:\` a session writes is restored from the snapshot taken before
that session started.

## What a delivery session is judged on

Stay inside the ticket's declared write-surface. The scope-guard diffs the tree
around the session against that surface and the rollback undoes what falls
outside. The harness the next session runs under is sealed: \`.claude/settings.json\`,
\`CLAUDE.md\`, \`.mcp.json\`, \`.claude/agents\`, \`commands\`, \`skills\`, \`hooks\` and
\`.claude/ralph.config.sh\` cannot be covered by any write-surface.

$INIT_CLAUDE_CLOSE
BLOCK
}

init_claude_md() {
  local feature had=no body
  feature="$(init__answer_of FEATURE)"
  body="$INIT_TARGET/.CLAUDE.md.ralph-init-body.$$"
  init__tmp_add "$body"
  init_claude_block "$feature" >"$body" || init__die "cannot write the CLAUDE.md block"

  [ -f "$INIT_TARGET/CLAUDE.md" ] && had=yes
  init__merge_block "$INIT_TARGET/CLAUDE.md" \
    "$INIT_CLAUDE_OPEN" "$INIT_CLAUDE_CLOSE" "$body" ||
    init__die "cannot write CLAUDE.md"
  rm -f "$body"
  init__tmp_drop "$body"

  if [ "$had" = yes ]; then
    init__say "merged a block into the existing CLAUDE.md — nothing else in it was touched"
  else
    init__say "created CLAUDE.md"
  fi
  return 0
}

# ── the config ───────────────────────────────────────────────────────────────

# Single-quoted, with `'` spelt `'\''`, and written *inside* the example's own
# `${KEY:-…}` rather than as a plain assignment after it. The form matters: the
# example's contract is that an exported value wins over the file, which is what
# makes a run scriptable — a CI, a test, the one-shot successor of [09] — and a
# flat `KEY=value` appended at the end would quietly take that away for exactly
# the keys a project cares most about.
#
# The example's outer double quotes go with the substitution (`KEY=${KEY:-'…'}`
# and not `KEY="${KEY:-'…'}"`): inside double quotes the single quotes would be
# literal characters of the value.
init__quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

init_config() {
  local example="$INIT_TARGET/.claude/ralph.config.sh.example"
  local dest="$INIT_TARGET/.claude/ralph.config.sh" tmp key op line

  if [ -f "$dest" ]; then
    init__say "kept the existing .claude/ralph.config.sh — never overwritten"
    return 0
  fi

  tmp="$dest.ralph-init.$$"
  init__tmp_add "$tmp"
  : >"$tmp" || init__die "cannot write $dest"

  while IFS= read -r line; do
    key="$(printf '%s' "$line" |
      sed -n 's/^\([A-Z_][A-Z0-9_]*\)="\${\1:\{0,1\}-.*}"$/\1/p')"
    if [ -n "$key" ] && init__answer_has "$key"; then
      op="$(printf '%s' "$line" |
        sed -n 's/^[A-Z_][A-Z0-9_]*="\${[A-Z_][A-Z0-9_]*\(:\{0,1\}-\).*}"$/\1/p')"
      printf '%s=${%s%s%s}\n' \
        "$key" "$key" "$op" "$(init__quote "$(init__answer_of "$key")")" >>"$tmp"
      continue
    fi
    printf '%s\n' "$line" >>"$tmp"
  done <"$example"

  mv -f "$tmp" "$dest" || init__die "cannot write $dest"
  init__tmp_drop "$tmp"
  init__say "wrote .claude/ralph.config.sh from the example, carrying your answers"
  return 0
}

# Every key this installer writes has to exist in the example, or it is a key
# nobody reads spelt into a file that reads like a contract. The suite holds the
# example and its own list in both directions ([76], [75]); this holds the third
# copy the installer would otherwise become.
init_config_check() {
  local key unknown=''
  for key in $(init__answer_keys); do
    grep -q "^$key=" "$INIT_TARGET/.claude/ralph.config.sh.example" ||
      unknown="$unknown $key"
  done
  [ -z "$unknown" ] ||
    init__die "this installer answered keys the shipped example does not declare:$unknown"
  return 0
}

# Run what `loop.sh` refuses to start on, against the config just written, while a
# human is still here to read it. Derived from `loop.sh` rather than retyped, so a
# refusal a later ticket adds is picked up without a line changing here.
init_validate() {
  local fn rc=0
  init__load_pack "$INIT_TARGET/.claude" ||
    init__die "the deposited pack does not load from $INIT_TARGET/.claude"

  for fn in $(init_refusals "$INIT_TARGET/.claude"); do
    command -v "$fn" >/dev/null 2>&1 || continue
    "$fn" || rc=1
  done

  if [ "$rc" != 0 ]; then
    init__warn "the refusals above are what \`loop.sh\` would exit 2 on. The pack is installed; edit .claude/ralph.config.sh and run this again"
    return 1
  fi
  init__say "every refusal \`loop.sh\` checks at startup passes on this project"
  return 0
}

# ── the sweep ────────────────────────────────────────────────────────────────

# What killed runs left behind, and the one component entitled to take it away.
#
# Entitled, because an iteration that swept `$TMPDIR` would delete another
# iteration's witness ([13], [36]); and obliged to take away *exactly* what the
# pack's own census names, because since [69] that census is read by **two** entry
# points — an AFK run and a human drain both print it — and a sweeper that removed
# something the list does not name would make an object disappear from both
# sentences at once with nobody the wiser.
#
# Three rules that are constraints and not implementation details:
#
#   1. **The names come from `gate_tmp_names`**, called, never copied. That list
#      is seventeen globs derived from the pack's own `mktemp` calls by a test on
#      the shipped source ([62]); it stood at six out of eighteen for twenty
#      tickets precisely because a second copy of it existed ([28]).
#   2. **`-mtime +7`, never less** ([22], [41]). This pack locks a working tree and
#      not a machine, so a run of another repository legitimately owns a brand-new
#      `ralph-gate.*` right now, and the movement register inside a **live**
#      `ralph-frontier.*` is what a keen sweep would destroy.
#   3. **`ralph-*` was considered and refused, and the price is written down.**
#      That namespace has two writers in the repository where this pack is
#      developed: the pack, and the pack's own test harness — `ralph-test.*` per
#      test, `ralph-harness.*` for a template cache kept seven days **on purpose**,
#      `ralph-mutate.*`, `ralph-contract.*`. A `ralph-* -mtime +7` sweep would
#      destroy that cache at the moment the suite needs it. On a target project's
#      machine those names do not exist; on a pack developer's, they do.
#
# Which is also why the number printed here is smaller than a developer expects:
# the bulk of the ~1 GB a ticket leaves on this repository's own machine is
# `ralph-test.*` and `ralph-harness.*`, which is precisely what `gate_tmp_names`
# does not name. This returns tens of megabytes, not a gigabyte, and says so
# rather than letting the opposite be assumed.
init_sweep() {
  local tmp="${TMPDIR:-/tmp}" name removed=0 n before after marker retention feature

  init__say "what earlier runs left here:"
  gate_leftovers 2>/dev/null | sed 's/^/  · /' ||
    init__say "  · nothing this pack's census names"
  concurrency_leftovers 2>/dev/null | sed 's/^/  · /' || true

  while IFS= read -r name; do
    [ -n "$name" ] || continue
    n="$(find "$tmp" -maxdepth 1 -name "$name" -mtime +7 2>/dev/null | wc -l | tr -d ' ')"
    [ "${n:-0}" -gt 0 ] || continue
    find "$tmp" -maxdepth 1 -name "$name" -mtime +7 -exec rm -rf {} + 2>/dev/null || true
    removed=$((removed + n))
  done <<NAMES
$(gate_tmp_names)
NAMES

  # [13]: a killed run leaves its iteration worktrees registered in the common git
  # directory, and every later `git worktree` call carries the registration.
  # `concurrency_leftovers` counts them and removes nothing.
  before="$(cd "$INIT_TARGET" && git worktree list --porcelain 2>/dev/null |
    grep -c '^worktree ')" || before=0
  (cd "$INIT_TARGET" && git worktree prune) || true
  after="$(cd "$INIT_TARGET" && git worktree list --porcelain 2>/dev/null |
    grep -c '^worktree ')" || after=0

  # [09] and the pass of 30/08: a successor that never woke leaves its marker for
  # good, in the git directory nothing else looks at. Only an instant that has
  # **passed** — a marker armed for tonight belongs to a run that is waiting on
  # it, and the pack's own census is what tells the two apart.
  marker="$(scheduler_marker_path 2>/dev/null || printf '')"
  if [ -n "$marker" ] && [ -f "$marker" ] &&
    gate_leftovers 2>/dev/null | grep -q 'successor marker'; then
    rm -f "$marker"
    init__say "removed a one-shot successor marker armed for an instant that has passed"
  fi

  # [45]: `RECEIPTS_RETENTION_DAYS` was documented as active pruning while nothing
  # pruned. It is implemented here, which is the honest half of that choice — the
  # sweep lives outside an iteration like the rest of this. And the limit is said
  # rather than implied ([16]): a receipt names git **objects** a `gc` can collect
  # long before the retention runs out, so pruning on a file's age does not align
  # the two durations and does not pretend to.
  retention="$(init__effective RECEIPTS_RETENTION_DAYS)"
  feature="$(init__answer_of FEATURE)"
  [ -n "$feature" ] || feature="${FEATURE:-}"
  case "$retention" in
    '' | *[!0-9]* | 0) ;;
    *)
      if [ -n "$feature" ] && [ -d "$INIT_TARGET/receipts/$feature" ]; then
        n="$(find "$INIT_TARGET/receipts/$feature" -type f -name '*.md' \
          -mtime "+$retention" 2>/dev/null | wc -l | tr -d ' ')"
        if [ "${n:-0}" -gt 0 ]; then
          find "$INIT_TARGET/receipts/$feature" -type f -name '*.md' \
            -mtime "+$retention" -delete 2>/dev/null || true
          init__say "pruned $n receipt(s) older than RECEIPTS_RETENTION_DAYS=$retention — and the git objects a receipt names can be collected by a \`gc\` long before that, so the two durations are not aligned"
        fi
      fi
      ;;
  esac

  init__say "swept $removed temporary entries older than seven days, and pruned $((before - after)) worktree registration(s)"
  init__say "not swept, on purpose: ralph-test.*, ralph-harness.*, ralph-mutate.*, ralph-contract.* — that namespace belongs to the pack's own test harness, whose template cache is kept seven days deliberately. On a machine where this pack is developed those are most of the disk, so this sweep returns tens of megabytes and not a gigabyte"
  init__say "not swept either: exclusion guards. One a killed run left is taken over by the next allocation ([47], [49]), and removing one a live process holds would break the exclusion it exists for. They are counted above, never taken"
  return 0
}

# ── the report ───────────────────────────────────────────────────────────────

init_report() {
  printf '\n'
  init__say "installed. What this project has now, and what it does not:"
  printf '\n'
  printf '%s' "$INIT_NOTES" | sed '/^$/d' | sed 's/^/  · /'
  cat <<'REPORT'
  · Nothing here was committed. This installer decides what a project *has*,
    never what enters its history — read the diff, then commit it yourself.
  · The durable directories are on disk and empty, and git does not track an
    empty directory: docs/adr and docs/playthroughs appear in the history the day
    a run writes in them.
  · A run leaves `failed/<ticket>` branches in this repository. They are the
    pack's artefacts, not work branches.
  · Guarded is not committed, and this installer widens the asymmetry by writing
    ignore rules: a ticket whose write-surface is a path the project ignores goes
    green, and unless that path is guarded the work lives in the working tree and
    nowhere else ([24], [50]).
  · An ignore rule added *during* a session only counts from the next iteration:
    the tree is judged through the rules pinned at spawn ([30]). The rules this
    installer wrote are older than any session, so they count from the first one.
  · `.git/info/exclude` is not versioned, and the pack puts it back and turns the
    iteration red when a session widens it — so nothing was provisioned there.
  · Next: write the feature spec and its tickets (`to-spec`, `to-tickets` under
    `.claude/skills/`), then `bash .claude/loop.sh`.
REPORT
  return 0
}

# ── main ─────────────────────────────────────────────────────────────────────

init_main() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      install | sweep) INIT_ACTION="$1" ;;
      --target)
        shift
        INIT_TARGET="${1:-}"
        ;;
      --from)
        shift
        INIT_SOURCE="${1:-}"
        ;;
      -y | --yes) INIT_ASSUME_YES=1 ;;
      --keep) INIT_KEEP_SELF=1 ;;
      --no-sweep) INIT_SWEEP=0 ;;
      --print-payload)
        init_payload
        return 0
        ;;
      --print-refusals)
        [ -d "$INIT_SOURCE/.claude" ] || init__die "no pack at $INIT_SOURCE/.claude"
        init_refusals "$INIT_SOURCE/.claude"
        return 0
        ;;
      -h | --help)
        init__usage
        return 0
        ;;
      *)
        init__warn "unknown option $1"
        init__usage >&2
        return 2
        ;;
    esac
    shift
  done

  [ -d "$INIT_TARGET" ] || init__die "no such directory: $INIT_TARGET"
  INIT_TARGET="$(cd "$INIT_TARGET" && pwd)"
  [ -d "$INIT_SOURCE" ] || init__die "no such pack source: $INIT_SOURCE"
  INIT_SOURCE="$(cd "$INIT_SOURCE" && pwd)"
  [ -f "$INIT_SOURCE/.claude/ralph.config.sh.example" ] ||
    init__die "no pack at $INIT_SOURCE/.claude — pass --from <a checkout of the pack>"

  # Before a single lib is sourced: see init__snapshot_env.
  init__snapshot_env
  # The pack's functions answer about the tree they are standing in as often as
  # about `RALPH_PROJECT_ROOT`, so the installer works from the target.
  cd "$INIT_TARGET" || init__die "cannot enter $INIT_TARGET"

  trap 'init__cleanup' EXIT
  trap 'init__cleanup; exit 130' INT
  trap 'init__cleanup; exit 143' TERM

  # The sweep reads the pack that made the debris — the target's when it has one,
  # the source's otherwise — because the names it sweeps are that pack's names.
  if [ "$INIT_ACTION" = sweep ]; then
    init__load_pack "$INIT_TARGET/.claude" || init__load_pack "$INIT_SOURCE/.claude" ||
      init__die "no pack to read the sweeping specification from: pass --from <a checkout of the pack>"
  else
    init__load_pack "$INIT_SOURCE/.claude" ||
      init__die "the pack at $INIT_SOURCE/.claude does not load"
  fi

  init_tree_preflight

  # The same lock a run takes, for the same reason, taken before anything is
  # written. This installer writes the config a run sources, the settings a fresh
  # `claude` reads and the ignore rules every check is framed by; doing that while
  # a run is going is [46]'s defect with a different author — a frontier pinned at
  # the start of a night, moved under it at three in the morning, and an innocent
  # iteration turning red for it.
  #
  # `tree_lock_acquire` installs an EXIT trap of its own, which *replaces* the one
  # set above — bash traps do not stack. The handler is put back here, chained, so
  # that neither the lock nor the temporary files are leaked ([57]'s shape).
  if ! tree_lock_acquire; then
    INIT_DIE_CODE=1 init__die "a run holds this working tree. The installer writes what a run reads — stop the run, or wait for it"
  fi
  trap 'init__cleanup; state_locks_release' EXIT
  trap 'init__cleanup; state_locks_release; exit 130' INT
  trap 'init__cleanup; state_locks_release; exit 143' TERM

  if [ "$INIT_ACTION" = sweep ]; then
    init_sweep
    return 0
  fi

  init_preflight
  init_confirmations
  init_deposit
  init_settings
  init_dirs
  init_gitignore
  init_claude_md
  init_config
  init_config_check
  [ "$INIT_SWEEP" = 0 ] || init_sweep
  init_validate || true
  init_report
  init__self_delete
  return 0
}

# It removes itself when it is standing **inside the project it has just
# installed**, and only then. That is the bootstrap copy — the script an `npx`
# wizard or a `cp -R` of this pack left in the project — and leaving it there
# would leave a script in a repository that has no use for it, on a path no
# write-surface covers and no run maintains.
#
# Run from a checkout of the pack with `--target <elsewhere>` it deletes nothing:
# deleting the source's own `init.sh`, or the copy inside an npm cache, would be a
# bootstrap that breaks the next one.
init__self_delete() {
  case "$INIT_SELF" in
    "$INIT_TARGET"/*) ;;
    *) return 0 ;;
  esac
  if [ "$INIT_KEEP_SELF" = 1 ]; then
    init__say "kept $INIT_SELF (--keep)"
    return 0
  fi
  rm -f "$INIT_SELF" || return 0
  init__say "removed $INIT_SELF — the bootstrap copy has nothing left to do here"
  return 0
}

init_main "$@"
