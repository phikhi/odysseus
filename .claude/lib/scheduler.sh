# shellcheck shell=bash
# The one-shot successor: how a weekly wall becomes a run that starts itself
# once, at the instant the wall lifts, and never again.
#
# ## Why a successor and not a sleep
#
# `budget_pause` waits a session window out in-process, because a session window
# resets within five hours and a run that sleeps is a run that still holds its
# locks. A **weekly** window is days out ([08]), and there is no honest way to
# hold a process — and two locks, and a claim — open across a weekend. So the run
# stops on `exit 6`, and this module arms something that will start a *fresh* run
# at the reset.
#
# ## What a successor is, and it is the decision this file exists to record
#
# **A successor is a new run and inherits nothing from the one that armed it.**
# The queued command is `loop.sh` and two environment variables, and that is all.
# Three things a run holds are therefore *not* handed on, and each of them is a
# per-run baseline taken before the first session exists:
#
#   the lesson index   ([14]) copied into `$TMPDIR` at start-up, so the successor
#                      re-reads `LEARNINGS.md` from the main tree as it stands.
#   the capability     ([15], [46]) taken on both roots at start-up, so a drift
#   witness            this run reported is the successor's baseline, and the
#                      successor will never say it again.
#   the retry brief    ([14]) which already died with the pilot.
#
# The other exit was to hand a baseline over in a file, and it is refused on
# [40]'s ground rather than on effort: a queued job's command line is readable by
# anything running as this user — `at -c` prints it — so the name of that file
# would be a name a session can learn, and a baseline a session can write is not
# a baseline. What is done instead is to make the *gap* loud where it is cheap:
# a run that is leaving the shared frontier somewhere it did not find it does not
# arm at all (see `scheduler_arm`), because that residue is precisely what a fresh
# run would adopt in silence.
#
# ## What arming is, and what it is not
#
# `at` answers for the **submission**, never for the job: POSIX says the exit
# status is the queue's, and a job whose `atd`/`atrun` is not running is queued
# and never runs. On macOS `atrun` ships disabled. So this module never claims a
# successor *will* run — it says what it queued, with whatever that mechanism
# cannot promise, and the row in docs/frontiere-de-confiance.md says the same.
#
# ## The three ends of a weekly wall, and the third one is a state
#
# A run stopped by a weekly window exits 6 whatever happens next, so the journal
# is the only thing that tells a morning reader which of three things happened.
# Arming sits at the **end** of `loop_main`, after a drain that lasts as long as
# the slowest session in flight ([13], [28]), and a run killed inside that window
# never reaches this file at all:
#
#   budget-wall successor-armed       the wall was hit and something is queued
#   budget-wall successor-blocked-*   the wall was hit and nothing is, with the
#     or budget-wall weekly-pause     reason in the word — see scheduler_outcome
#   budget-wall                       alone: the run was killed between the wall
#                                     and this module, during the drain
#
# The third one is a state and not a gap, and it is written down here because it
# is the one nothing can print: the process that would have logged it is gone.
# `budget-wall` with nothing under it is a run that was killed, never a run that
# decided — and until [53] measured it, the pack assumed that case left the
# journal silent altogether.
#
# ## What the queued line carries, and what it checks before it trusts it
#
# `at` takes a command line and runs it in a shell with no login environment, so
# everything a successor needs is on that line — and everything on that line was
# chosen by a dying run, in a repository a session has been writing to all night.
# Two of the things it names live in a zone a session reaches:
#
#   the log      `<feature_dir>/successor.log`, beside `run.log` because that is
#                the file a human opens in the morning — moving it out of reach
#                was the other exit and [10] refused it for `run.log` on the
#                ground that holds here too. The redirection is the **first**
#                thing the job's shell does, before `loop.sh`, so before every
#                preflight and every gate this pack owns; and a redirection on an
#                `at` line has nowhere to put a guard. So the line runs a
#                `bash -c` that tests the target first and falls back saying so
#                (`scheduler__wake`, [53]). Measured before it was written: the
#                name turned into a directory makes the job exit 1 and `loop.sh`
#                never starts, the name turned into a link into the sealed
#                `.claude/` makes this pack write through it at an instant when
#                no run exists to be judged.
#   the programs `PATH`, verbatim, which is the third thing on this line a
#                session reaches and the one that is not a *path in the tree* at
#                all ([52]). A directory already on it — `~/.local/bin`,
#                `/usr/local/bin`, `node_modules/.bin` — is writable by the same
#                user the session runs as, and what it holds decides which `git`
#                and which `claude` the woken run gets. Nothing on this line can
#                check that, and nothing in the job's shell can either: the check
#                has to compare against what the *dying* run started with. So it
#                is made where that baseline exists — a run leaving a moved
#                program behind arms nothing at all (`scheduler_arm`, return 6).
#   the tracker  `FEATURE`, which this line did not carry until [53]. The config
#                ships `FEATURE="${FEATURE:-}"`, so a run started with one in its
#                environment armed a successor that exits 2 on an empty tracker
#                while its own journal said `successor-armed`. It travels under
#                the name it really has, which is [31]'s rule for `RALPH_CONFIG`
#                applied to the second selector the environment gives. It also
#                settles a twin defect: the log path is computed with the dying
#                run's `FEATURE`, so the two agreeing is what keeps one feature's
#                successor out of another feature's directory.
#
# ## The chain, ordered by reboot survival
#
# A weekly wall is days out, so the wait can cross a reboot. `at` keeps its queue
# on disk (`/var/spool`) and survives one; a transient `systemd-run` timer lives
# in `/run`, which is tmpfs, and does not. So `at` comes first everywhere, and
# the order is the property being ordered by rather than a preference.
#
# The cloud `schedule` skill is deliberately **not** in this chain and cannot be
# put in it by configuration: it creates a routine on Anthropic infrastructure,
# needs a claude.ai login rather than an API key, and is refused outright when
# telemetry is switched off — which is the ordinary shape of an AFK night. It
# would also have no access to this repository. See
# .scratch/dev-framework/research/one-shot-scheduling-portable.md.

scheduler__log() {
  printf '%s\n' "$*"
}

# ── configuration ────────────────────────────────────────────────────────────

# Refuse to start rather than grind a night behind a weekly wall this run will
# not know how to come back from. Both refusals are the shape every preflight in
# this pack is written against ([31], [17]): a value that switches the control
# off, or points it at something that is not there, without saying so.
#
#   SCHEDULER       anything outside the set would be read as "no mechanism" —
#                   a run that stops for good on the first weekly wall while
#                   looking exactly like one that arms a successor.
#   WEEKLY_RESUME   anything but the two words would be read as `human`, which is
#                   the same silence.
scheduler_preflight() {
  local rc=0

  case "${SCHEDULER:-auto}" in
    auto | at | systemd-run | none) ;;
    schedule | routines)
      printf 'ralph: SCHEDULER is "%s" — the `schedule` skill creates a routine on Anthropic infrastructure, needs a claude.ai login rather than an API key, and is refused when telemetry is off, so it is not a local one-shot timer. Use auto, at, systemd-run, or none\n' \
        "${SCHEDULER:-}" >&2
      rc=1
      ;;
    *)
      printf 'ralph: SCHEDULER is "%s" — it has to be auto, at, systemd-run or none; anything else would be read as no mechanism at all and stop this run for good on its first weekly wall\n' \
        "${SCHEDULER:-}" >&2
      rc=1
      ;;
  esac

  case "${WEEKLY_RESUME:-schedule}" in
    schedule | human) ;;
    *)
      printf 'ralph: WEEKLY_RESUME is "%s" — it has to be schedule or human, and anything else would be read as human, which is a night that ends without a word about why nothing was armed\n' \
        "${WEEKLY_RESUME:-}" >&2
      rc=1
      ;;
  esac

  return "$rc"
}

# ── the chain ────────────────────────────────────────────────────────────────

# Every mechanism this platform could use, in the order they are tried, whatever
# this machine happens to have installed. One per line.
#
# Pure, and taking the platform as an argument rather than reading it, for two
# reasons that are the same reason: the ordering is the guarantee — `at` before a
# transient timer, because one survives a reboot and the other does not — and a
# guarantee tested only on the machine the test runs on is tested on one of the
# two platforms this pack promises.
#
# macOS has no systemd, so the chain there is one long. That is not a gap being
# papered over: the second macOS mechanism the research names is a
# self-uninstalling LaunchAgent, which is a community pattern rather than a
# launchd feature, and this pack does not install plist files into a human's
# `~/Library` to save a night. A macOS box without `atrun` enabled falls back to
# the human, and says so.
scheduler_candidates() {
  local platform="${1:-$(uname -s 2>/dev/null || printf Unknown)}"
  case "${SCHEDULER:-auto}" in
    none) return 0 ;;
    at | systemd-run)
      printf '%s\n' "${SCHEDULER:-}"
      return 0
      ;;
  esac
  printf 'at\n'
  case "$platform" in
    Darwin) ;;
    *) printf 'systemd-run\n' ;;
  esac
  return 0
}

# The same list, minus what this machine does not have. Empty is an answer and
# the caller says so out loud; it is never an error.
scheduler_chain() {
  local platform="${1:-}" mech
  while IFS= read -r mech; do
    [ -n "$mech" ] || continue
    command -v "$mech" >/dev/null 2>&1 || continue
    printf '%s\n' "$mech"
  done <<CANDIDATES
$(scheduler_candidates "$platform")
CANDIDATES
  return 0
}

# What a mechanism cannot promise, said next to the line that says it armed one.
# Empty for nothing to declare. A blind spot has to be named where a human reads
# it ([24]), and "armed" is exactly the word that would otherwise be read as
# "will run".
scheduler_caveat() {
  case "$1" in
    at)
      case "$(uname -s 2>/dev/null || printf Unknown)" in
        Darwin)
          printf 'that is a submission and not a promise: `at` answers for the queue, and on macOS `atrun` ships disabled — if it was never enabled as root the job sits in the spool and never runs\n'
          ;;
        *)
          printf 'that is a submission and not a promise: `at` answers for the queue, so a machine whose `atd` is not running has queued a job that never runs\n'
          ;;
      esac
      ;;
    systemd-run)
      printf 'that is a transient timer in /run, which is tmpfs: a reboot before the reset takes the successor with it, and a `--user` unit dies at logout unless this account has linger enabled\n'
      printf 'and it carries none of this run environment beyond PATH and the config: a credential this run had in its own environment will not be there\n'
      ;;
  esac
  return 0
}

# ── the instant ──────────────────────────────────────────────────────────────

# How far out each window this pack prices may honestly reset, in seconds. A
# `five_hour` window resets within five hours and a `seven_day` one within seven
# days, by what the words mean: this is a ceiling those words carry, not a clamp
# on arithmetic.
#
# One table and not a `case` per reader, because it has two readers and they must
# not drift apart: `scheduler_deadline` holds the instant a wall hands over to it,
# and `scheduler_armed_at` holds the instant a *marker* claims ([53]). A window
# added here widens both, or neither.
scheduler__ceilings() {
  printf 'five_hour\t18000\n'
  printf 'seven_day\t604800\n'
  printf 'seven_day_opus\t604800\n'
}

# The ceiling of one window, or non-zero for a name this pack does not know —
# which is a refusal and never the widest one, for the reason every default in
# this module is a refusal ([27]).
scheduler__ceiling() {
  local name seconds
  while IFS="$(printf '\t')" read -r name seconds; do
    [ "$name" = "${1:-}" ] || continue
    printf '%s\n' "$seconds"
    return 0
  done <<CEILINGS
$(scheduler__ceilings)
CEILINGS
  return 1
}

# The widest of them, derived rather than typed a second time: it is the furthest
# instant *this pack* could have written into a marker, and a bound typed by hand
# would be a bound that stops matching the table the day a window is added.
scheduler__ceiling_max() {
  scheduler__ceilings | awk -F'\t' '$2 > max { max = $2 } END { print max + 0 }'
}

# May this run arm a successor at that instant, and when. Sets two variables in
# the caller's shell and returns non-zero when it may not:
#
#   RALPH_SUCCESSOR_AT    the epoch to arm at, when there is one
#   RALPH_SUCCESSOR_WHY   why there is not, in words for the morning log
#
# Variables and not stdout, the way `budget_check` answers, because the refusal
# and the instant are two answers to one question and a caller needs both.
#
# Four guards, and every one of them is a way the reset could be something this
# run did not measure ([08], and [27] on a fallback that disarms itself):
#
#   readable   `exit 6` has two causes and only one of them carries an instant.
#              An unreadable reset arrives here as an empty or non-numeric field,
#              and a successor armed on it would be armed at the epoch 0.
#   future     a reset in the past contradicts the wall that was just measured.
#              Arming on it wakes a run into the same wall, which arms again.
#   the window a `five_hour` window resets within five hours and a `seven_day`
#              one within seven days, by what the words mean. That is where
#              "never +7 days" comes from: not a clamp on the arithmetic, but a
#              ceiling each window carries — and a window name this pack does not
#              know is refused rather than given the widest one.
#   the source `stream` means the instant came out of a session's own stream,
#              which is a file that session can write ([08], [23]). A forged one
#              buys a pause worth `BUDGET_MAX_PAUSE` today; it must not buy a
#              successor days out, so the stream is held to the same cap.
scheduler_deadline() {
  local window="${1:-}" reset="${2:-}" source="${3:-}" now span ceiling

  RALPH_SUCCESSOR_AT=''
  RALPH_SUCCESSOR_WHY=''

  case "$reset" in
    '' | *[!0-9]*)
      RALPH_SUCCESSOR_WHY="not arming a successor: the reset of the window that blocks this run is not an instant anything measured (${reset:-none}) — a successor armed on it would be armed at the epoch 0"
      return 1
      ;;
  esac

  if ! ceiling="$(scheduler__ceiling "$window")"; then
    RALPH_SUCCESSOR_WHY="not arming a successor: ${window:-an unnamed window} is not a window this pack knows how to price, so nothing here can say how far out its reset may honestly be"
    return 1
  fi

  now="$(date +%s)"
  span=$((reset - now))
  if [ "$span" -le 0 ]; then
    RALPH_SUCCESSOR_WHY="not arming a successor: the reset of $window is not in the future ($span s), and a run woken into the same wall would arm another one"
    return 1
  fi
  if [ "$span" -gt "$ceiling" ]; then
    RALPH_SUCCESSOR_WHY="not arming a successor: the reset of $window is ${span}s out, further than a $window window can reset (${ceiling}s) — that is a clock or an endpoint this run cannot believe"
    return 1
  fi
  if [ "$source" = stream ] && [ "$span" -gt "${BUDGET_MAX_PAUSE:-21600}" ]; then
    RALPH_SUCCESSOR_WHY="not arming a successor: that instant came from a session's own stream, which the judged session writes, and it is ${span}s out — further than BUDGET_MAX_PAUSE (${BUDGET_MAX_PAUSE:-21600}s), which is all a forged one is allowed to buy"
    return 1
  fi

  RALPH_SUCCESSOR_AT="$reset"
  return 0
}

# ── the singleton ────────────────────────────────────────────────────────────
#
# Two successors for one working tree would be two runs racing for one tree lock:
# the loser exits 1 and the night is half spent. The lock is the net and this is
# the fence, and both are wanted — the lock cannot stop a second job being queued,
# and a marker cannot stop two jobs that are already queued from waking together.
#
# It lives beside the working-tree lock, in the git directory, for that lock's
# reason ([22]): out of reach of a `git add -A`, a `git clean` and an
# `rm -rf .scratch`, and already per working tree, which is the granularity a
# successor has. Out of reach is not the same as unreachable, and the direction
# of the exposure is what makes it acceptable: a session that forged a marker
# would stop a successor being armed, which ends the night with a human — the
# cautious side, the same side a forged `rate_limit_event` is allowed to move
# things on ([08]). A session that *deleted* one buys a second successor, and the
# tree lock is what that costs.
#
# Nothing removes it: a successor that wakes finds its own marker in the past and
# writes over it. One that never wakes — `atrun` disabled, the case the frontier
# table assumes rather than fixes — leaves an instant in the past that blocks
# nothing and that nobody used to count. `gate_leftovers` says it at the start of
# the next run since [53], on the terms it says the other two on: a line, never a
# sweep and never a red.

# Public since [53], because it has a second caller and a private name with two
# callers is a lie: `gate_leftovers` counts a marker nobody woke, the way it
# counts a temporary directory and an exclusion guard nobody released.
scheduler_marker_path() {
  local lock
  lock="$(ralph_tree_lock_path)" || return 1
  [ -n "$lock" ] || return 1
  printf '%s/ralph.successor\n' "${lock%/*}"
}

# The instant a successor is already armed at for this tree. Non-zero when there
# is none, when the one there is has already passed, and — since [53] — when it
# claims an instant no window this pack prices could have produced.
#
# That third bound is the answer to what "a forged marker ends the night with a
# human" left open, and it is a bound rather than a check on *who wrote the file*
# because nothing here can answer that question. `.git/` is out of the sweeps and
# not out of reach ([22]): a session reaches it from a green iteration with
# `git rev-parse --git-common-dir`, measured. What can be answered is what this
# pack could have *written* — every marker it writes carries an instant that
# passed `scheduler_deadline`, so it is at most the widest ceiling a priced
# window carries. Beyond that the file was written by something else, and
# honouring it hands one line of a session's choosing every night from here to
# whenever it says: measured at 5.8 days on the 30/08 pass, nights one and two
# refused, marker intact, `run.log` saying `weekly-pause` both times.
#
# The direction [09] chose is kept and only bounded: a forged marker still
# *prevents* an arming rather than causing one, which is the cautious side.
scheduler_armed_at() {
  local marker at now
  marker="$(scheduler_marker_path)" || return 1
  [ -f "$marker" ] || return 1
  at="$(awk -F'\t' 'NR == 1 { print $1 }' "$marker" 2>/dev/null || true)"
  case "$at" in
    '' | *[!0-9]*) return 1 ;;
  esac
  now="$(date +%s)"
  [ "$at" -gt "$now" ] || return 1
  [ "$((at - now))" -le "$(scheduler__ceiling_max)" ] || return 1
  printf '%s\n' "$at"
}

scheduler__mark() {
  local marker
  marker="$(scheduler_marker_path)" || return 1
  printf '%s\t%s\t%s\n' "$1" "$2" "$(ralph_now)" >"$marker" 2>/dev/null || return 1
  return 0
}

# ── what gets queued ─────────────────────────────────────────────────────────

scheduler__quote() {
  printf "'%s'" "$(printf '%s' "${1:-}" | sed "s/'/'\\\\''/g")"
}

# The shell a successor runs before it runs anything of this pack, and the only
# place a guard on the redirection can sit ([53]).
#
# `at` takes a command line, and `cmd >>log` on one has nowhere to put a test:
# the redirection happens in the job's shell before the first byte of `loop.sh`,
# so no preflight, no lock and no gate of this pack has been reached yet when the
# name is resolved. A `bash -c` that tests the target and then execs is therefore
# the only shape available — the check has to be *in the job*.
#
# Three clauses, and each of them is a measured way the name was not the file it
# was queued as:
#
#   -L on either  a symlink, on the path or on the directory holding it: the
#                 append lands wherever a session pointed it. Measured on
#                 `.claude/settings.json`, which is sealed against a session
#                 ([24], [31]) and not against this job — 153 bytes of JSON
#                 turned into 1240 and every later `claude` broken.
#   -f and -O     a directory, a socket, a file this user does not own: the shell
#                 says `Is a directory`, the job exits 1, and `loop.sh` never
#                 starts at all — into `at`'s mail, which is the silence the
#                 redirection existed to avoid.
#   : >>          and the ordinary reasons the two above do not name: a full
#                 disk, a read-only mount, a directory that is gone.
#
# `$1` is the log the dying run wanted, `$2` the fallback beside the tree lock,
# `$3` the loop. **A refusal is never fatal**: the point of this job is that
# `loop.sh` starts, so an unusable log costs the log and a sentence and never the
# night — which is the defect this replaces, taken by the other end.
#
# The sentence travels in `RALPH_SUCCESSOR_NOTE`, which `loop_main` journals: the
# fallback log is in the git directory, out of a session's sweeps and out of a
# human's habits, so the reader who matters is reached through `run.log` and not
# through the file that was written instead.
#
# One line, because a queued command is read as one line everywhere it is read —
# by `at -c`, by the shim that records it, by the test that executes it.
#
# Where the next guard goes: this is the job's own preflight, and it is the place
# for anything that has to be true *before* `loop.sh` is trusted to check it.
#
# [52] looked and put nothing here, which is worth writing down so the question
# is not reopened by guesswork. Its check — a PATH entry that is not an absolute
# directory — is asked by `gate_path_preflight`, at the top of `loop_main`, and
# `loop.sh` reaches it having run no program by name at all (it computes
# `RALPH_DIR` with parameter expansion rather than `dirname` for exactly that).
# A copy here would be a second spelling of one rule, and only one of the two
# would be the one under test. What genuinely cannot be checked from inside the
# job is the *other* half — whether the programs this PATH resolves to are the
# ones the dying run started with — because the baseline for that died with the
# run that took it. That is why the answer is a refusal to arm and not a check at
# the wake.
scheduler__wake() {
  local usable pick run
  usable='ralph_wake_usable() { [ -n "$1" ] && [ ! -L "$1" ] && [ ! -L "${1%/*}" ] && { [ ! -e "$1" ] || { [ -f "$1" ] && [ -O "$1" ]; }; } && ( : >>"$1" ) 2>/dev/null; };'
  pick='out=""; note=""; if ralph_wake_usable "$1"; then out="$1"; else note="the log this successor was queued with is not a plain file this user owns ($1) — a session can write that path, and this job resolves it before any gate of this pack exists"; ralph_wake_usable "$2" && out="$2"; fi;'
  run='[ -z "$out" ] || exec >>"$out" 2>&1; if [ -n "$note" ]; then RALPH_SUCCESSOR_NOTE="$note; wrote to ${out:-nowhere: this output goes wherever the scheduler puts it} instead"; export RALPH_SUCCESSOR_NOTE; printf "ralph: %s\\n" "$RALPH_SUCCESSOR_NOTE"; fi; exec "$3"'
  printf '%s %s %s\n' "$usable" "$pick" "$run"
}

# The command line a successor runs. Public because a test has to be able to read
# it without a scheduler on the machine, and because it is the whole of what is
# handed on — anything not on this line is something a successor does not inherit.
#
# Absolute paths and an explicit `PATH`, because `at` and cron hand a job a
# minimal environment and no login shell; and stdout and stderr redirected,
# because `at` mails a job's output and a headless box with no MTA loses it in
# silence. The log sits beside `run.log` on purpose: it is the file a human opens
# in the morning, and a successor's first words belong next to the dead run's
# last ones — and since [53] the job checks that name before it writes through
# it, because that directory is a zone a session writes in.
#
# Four variables and no more. `PATH` so the successor finds the same `claude`
# and the same `git` this run found — **and whatever else a session put in one of
# its directories**, which is the half that was missing until [52]: this line
# freezes the pilot's PATH, and a successor is a fresh shell that has hashed
# nothing, so every name on it is resolved again days later with no human in the
# room. That is answered by a refusal to arm (`scheduler_arm`, on the witness
# `gate_path_witness` takes before the first session) and **not** by a sentence on
# the arming line: a caveat would put the words next to a job that was queued
# anyway, and the whole reason [09] arms one at all is that nobody is reading.
# `RALPH_CONFIG` under the name it really has
# ([31]: a run started with another value must not silently hand its successor
# the default); `FEATURE` for the same reason and it is the same rule ([53]: the
# config ships `FEATURE="${FEATURE:-}"`, so a run pointed at a tracker by its
# environment armed a successor that exits 2 on an empty one);
# `RALPH_PROJECT_ROOT` only when this run was given one.
scheduler_command() {
  local root cfg log alt marker shell
  root="$(ralph_project_root)"
  cfg="${RALPH_CONFIG:-$root/.claude/ralph.config.sh}"
  log="$(ralph_feature_dir)/successor.log"
  alt=''
  if marker="$(scheduler_marker_path)"; then alt="$marker.log"; fi
  shell="$(command -v bash 2>/dev/null || printf '/bin/bash')"

  printf 'PATH=%s' "$(scheduler__quote "${PATH:-}")"
  printf ' RALPH_CONFIG=%s' "$(scheduler__quote "$cfg")"
  printf ' FEATURE=%s' "$(scheduler__quote "${FEATURE:-}")"
  [ -z "${RALPH_PROJECT_ROOT:-}" ] ||
    printf ' RALPH_PROJECT_ROOT=%s' "$(scheduler__quote "$RALPH_PROJECT_ROOT")"
  printf ' %s -c %s ralph-successor %s %s %s\n' \
    "$(scheduler__quote "$shell")" \
    "$(scheduler__quote "$(scheduler__wake)")" \
    "$(scheduler__quote "$log")" \
    "$(scheduler__quote "$alt")" \
    "$(scheduler__quote "$root/.claude/loop.sh")"
}

# An epoch as a local wall-clock stamp. BSD spelling first, because that is the
# shell this pack promises to run on, GNU second — the same order `budget__epoch`
# reads an instant in. Local and not UTC: `at` and `systemd-run` both read the
# machine's timezone.
scheduler__stamp() {
  local epoch="$1" fmt="$2"
  date -r "$epoch" +"$fmt" 2>/dev/null && return 0
  date -d "@$epoch" +"$fmt" 2>/dev/null && return 0
  return 1
}

# `at` takes whole minutes, so the instant is rounded **up**. Down would wake a
# run before the wall lifts, which is the one thing a successor must not do: it
# would find the same window, stop again, and arm again.
scheduler__minute_up() {
  printf '%s\n' "$(((${1:-0} + 59) / 60 * 60))"
}

# Queue the successor with one mechanism. Prints what the mechanism said when it
# refused, so a fallback down the chain is explicable rather than silent.
scheduler__submit() {
  local mech="$1" epoch="$2" cmd out stamp
  cmd="$(scheduler_command)" || return 1

  case "$mech" in
    at)
      stamp="$(scheduler__stamp "$(scheduler__minute_up "$epoch")" '%Y%m%d%H%M')" || return 1
      out="$(printf '%s\n' "$cmd" | at -t "$stamp" 2>&1)" || {
        scheduler__log "at would not take the successor: $(printf '%s' "$out" | tr '\n' ' ')"
        return 1
      }
      ;;
    systemd-run)
      stamp="$(scheduler__stamp "$epoch" '%Y-%m-%d %H:%M:%S')" || return 1
      out="$(systemd-run --user --on-calendar="$stamp" \
        --timer-property=RemainAfterElapse=no \
        /bin/sh -c "$cmd" 2>&1)" || {
        scheduler__log "systemd-run would not take the successor: $(printf '%s' "$out" | tr '\n' ' ')"
        return 1
      }
      ;;
    *) return 1 ;;
  esac
  return 0
}

# ── arming ───────────────────────────────────────────────────────────────────

# The word the run journal gets for what `scheduler_arm` just did, out of the
# code it returned. In this module and not in the pilot because the reasons are
# this module's, and it is a **table of words and not of sentences** on purpose:
# `run.log` is a journal a human greps, and a sentence there would be a sentence
# to keep in step with the one already logged.
#
# It exists because until [53] every refusal was journalled `weekly-pause`, which
# is the exact word of a project that chose `WEEKLY_RESUME=human`. A morning
# reader could not tell "this project resumes by hand" from "a marker in the git
# directory has been refusing every night since Tuesday" — the sentence that
# named the marker being a `scheduler__log`, so stdout, so dead with the process.
scheduler_outcome() {
  case "${1:-0}" in
    0) printf 'successor-armed\n' ;;
    1) printf 'weekly-pause\n' ;;
    2) printf 'successor-blocked-residue\n' ;;
    3) printf 'successor-blocked-instant\n' ;;
    4) printf 'successor-blocked-marker\n' ;;
    5) printf 'successor-blocked-mechanism\n' ;;
    6) printf 'successor-blocked-path\n' ;;
    *) printf 'successor-blocked\n' ;;
  esac
}

# Arm a one-shot successor at the reset of the window that stopped this run.
# Prints the lines a human reads in the morning, one per line, and returns
# non-zero when nothing was armed — which is the `pause-hebdo` fallback and not
# an error: the run has already decided to stop.
#
# The non-zero it returns says *which* refusal it was, and `scheduler_outcome`
# turns that into the word the journal gets ([53]). A code and not a variable,
# because the pilot reads this through a command substitution and a variable set
# in a subshell dies there — the same trap that made the reclaim lines of [10]
# invisible to the run that wrote them.
#
# Called by the pilot **after the last iteration has been drained** ([13], [28]),
# never from an iteration: the point of a successor is to stop spending the
# quota this run has run out of, and arming while a `claude` per slot is still
# burning it would arm the wrong thing at the wrong instant.
#
# `residue` is what this run is leaving of the shared frontier somewhere it did
# not find it ([30], [46]) — a `.git/info/exclude` or a `core.fsmonitor` a session
# moved and this run could not put back. It is a refusal to arm and not a warning
# on the arming line, and that is the decision this ticket owed [46]. A fresh run
# pins the configuration it finds as its own baseline, so a successor would adopt
# that residue in silence and grind a night through it — with `core.fsmonitor`,
# a program a session chose, running in the pilot process tree on every index
# refresh. The human this successor exists to replace is exactly the person who
# would have read the receipt and caught it.
#
# `programs` is the same decision one level up, and it is asked **first** ([52]).
# `residue` is what git said about git's own configuration, so a `git` a session
# planted on this run's PATH is what answered it: an interposed program does not
# get past the residue check, it *writes* the residue check's answer. And the
# exposure is worse here than there, because the queued line carries this run's
# PATH verbatim — a successor days out resolves the same names to the same files,
# in a fresh shell that has hashed nothing, with no human between.
scheduler_arm() {
  local window="${1:-}" reset="${2:-}" source="${3:-}" residue="${4:-}"
  local programs="${5:-}"
  local mech line armed at chain kind name

  if [ "${WEEKLY_RESUME:-schedule}" != schedule ]; then
    scheduler__log "not arming a successor: WEEKLY_RESUME=${WEEKLY_RESUME:-} — this project resumes a weekly wall by hand"
    return 1
  fi

  if [ -n "$programs" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      scheduler__log "$line"
    done <<PROGRAMS
$programs
PROGRAMS
    scheduler__log "not arming a successor: the line this run would queue carries its own PATH, so a fresh shell days from now resolves those names the same way — and a fresh run adopts what it finds as the project's own and never says it again. A human has to look first"
    return 6
  fi

  if [ -n "$residue" ]; then
    while IFS="$(printf '\t')" read -r kind name; do
      [ -n "$name" ] || continue
      scheduler__log "this run is leaving $name somewhere it did not find it ($kind), and could not put it back"
    done <<RESIDUE
$residue
RESIDUE
    scheduler__log "not arming a successor: a fresh run pins the configuration it finds as its own baseline, so it would take that as the project's own and never say it again — a human has to look first"
    return 2
  fi

  if ! scheduler_deadline "$window" "$reset" "$source"; then
    scheduler__log "$RALPH_SUCCESSOR_WHY"
    return 3
  fi

  if at="$(scheduler_armed_at)"; then
    scheduler__log "not arming a successor: one is already armed for this working tree at $(scheduler__stamp "$at" '%Y-%m-%dT%H:%M:%S%z' || printf '%s' "$at") — two of them would be two runs racing for one tree lock"
    return 4
  fi

  chain="$(scheduler_chain)"
  if [ -z "$chain" ]; then
    scheduler__log "no one-shot scheduler on this machine (tried: $(scheduler_candidates | tr '\n' ' ' | sed 's/ *$//')) — this run stops on the wall and a human resumes it"
    return 5
  fi

  armed=''
  while IFS= read -r mech; do
    [ -n "$mech" ] || continue
    if scheduler__submit "$mech" "$RALPH_SUCCESSOR_AT"; then
      armed="$mech"
      break
    fi
  done <<CHAIN
$chain
CHAIN

  if [ -z "$armed" ]; then
    scheduler__log "every one-shot scheduler on this machine refused the successor — this run stops on the wall and a human resumes it"
    return 5
  fi

  scheduler__mark "$RALPH_SUCCESSOR_AT" "$armed" ||
    scheduler__log "armed a successor and could not record it beside the tree lock: a second run stopped by the same wall would arm a second one, and the tree lock is then all that keeps them apart"

  scheduler__log "armed a one-shot successor with $armed at $(scheduler__stamp "$RALPH_SUCCESSOR_AT" '%Y-%m-%dT%H:%M:%S%z' || printf '%s' "$RALPH_SUCCESSOR_AT") — the reset of $window as the ${source:-endpoint} gave it"
  scheduler__log "it is a new run and inherits nothing from this one: it re-reads the lesson index from the tree, takes its own baseline of what a fresh session loads, and knows nothing of the tickets this run retried"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    scheduler__log "$line"
  done <<CAVEAT
$(scheduler_caveat "$armed")
CAVEAT
  return 0
}
