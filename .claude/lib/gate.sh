# shellcheck shell=bash
# The gate, in two phases.
#
# **The objective phase.** Three deterministic checks decide whether an iteration
# delivered: the project's test suite, its type check, and the scope-guard. The
# loop runs them itself, so no model is ever asked whether its own work is good
# enough — complaisance is not a failure mode a return code has.
#
# **The lens phase.** The tier that does involve judgement, from the registry in
# lib/lenses.sh ([06]): a fresh `claude` per lens, reviewing the diff, with a
# read-only tool set. It is a phase and not three more branches in the fan above,
# and there are two reasons, both load-bearing:
#
#   - A lens runs in the tree it is judging. What a branch writes after the judged
#     tree was taken is undone by nothing ([29]), and for a `claude` that would
#     mean model-written code entering the repository with no verdict on it. The
#     gate snapshots the tree around this phase and puts back whatever moved —
#     which is only possible because `TEST_CMD` is no longer writing at the same
#     time. Concurrency here would make the write unattributable, and an
#     unattributable write cannot be undone.
#   - A red objective phase makes the gate red whatever a lens would have said,
#     so spawning one would spend quota to learn nothing. The run says the lenses
#     did not run, and why.
#
# Two properties are load-bearing and easy to lose:
#
#   - Green has to be earned. A branch that is unconfigured, whose command does
#     not exist, that left no verdict at all, or — for a lens — that answered
#     without one, counts red. Otherwise a gate nobody wired up is
#     indistinguishable from a gate everything passes, which is the one failure
#     this whole framework exists to prevent.
#   - Branches within a phase do not short-circuit each other. They are
#     backgrounded and then collected, so a red suite still tells you whether the
#     types are also broken, and the wall-clock of a phase is its slowest branch
#     rather than their sum. Collecting them is the fragile half: a branch that
#     was started and not waited for is read as having no verdict, which counts
#     red — see `proc_collect` for why a bare `wait` does not survive a graceful
#     stop.
#
# `GATE_TIMEOUT` is per phase, not per gate: each fan gets its own deadline, so a
# gate with lenses can take up to twice it. Anything else would mean an objective
# phase that ran long silently eating the lenses' budget.
#
# What the loop reads back, for the failure policy and the audit receipt:
#   RALPH_GATE_VERDICTS     e.g. "tests=green typecheck=red scope=green"
#   RALPH_GATE_FAILED       the red branch names
#   RALPH_GATE_SCOPE_CLASS  internal | contract, when the scope-guard is red
#   RALPH_GATE_TREE         the tree every branch is judged on, so the rollback and
#                           the durable commit act on exactly what was approved.
#                           Taken before the fan and filled in before it, so a
#                           branch — a subshell — inherits it ([29]).

gate__log() {
  printf 'ralph: gate: %s\n' "$*"
}

# ── preflight ────────────────────────────────────────────────────────────────

# Refuse to start rather than grind a whole frontier behind a gate that proves
# nothing. Called by the loop from the project root, before it takes the lock.
gate_preflight() {
  local rc=0 unknown

  if [ -z "${TEST_CMD:-}" ]; then
    printf 'ralph: TEST_CMD is empty — a gate with no test suite is green for the wrong reason\n' >&2
    rc=1
  fi

  # Empty is not the same statement as "this project has no type check": one is
  # a config nobody filled in, the other is a decision. Only the decision passes.
  if [ -z "${TYPECHECK_CMD:-}" ]; then
    printf 'ralph: TYPECHECK_CMD is empty — set it, or set it to "none" to declare this project has no type check\n' >&2
    rc=1
  fi

  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    printf 'ralph: not a git repository — the scope-guard has nothing to diff against\n' >&2
    rc=1
  fi

  # A name in LENSES that nothing can perform. Refused at the door rather than
  # discovered as a red gate on every iteration of a night — and, above all,
  # rather than skipped: a typo that quietly removed a reviewer would leave a gate
  # that looks exactly like a gate whose reviewers all passed.
  if unknown="$(lenses_unknown)"; then
    printf 'ralph: LENSES names a lens this pack cannot run: %s\n' \
      "$(printf '%s' "$unknown" | tr '\n' ' ')" >&2
    rc=1
  fi

  return "$rc"
}

# ── the zone git does not show ───────────────────────────────────────────────
#
# Every check in this pack is built on a git tree object, so every check inherits
# git's own blind spot: what the *target project's* `.gitignore` covers is not in
# the tree, and a control that delegates its visibility to a file the project
# writes has to say how far it sees. Probed on 29/07/2026, three times over: a
# session wrote an ignored file off its write-surface and the verdict was
# `scope=green`; a red gate rolled the tree back and left the ignored file
# standing; and a ticket went green because of an ignored file the *previous*
# ticket's session had left behind, which no review of either ticket alone could
# have caught ([24]).

# The pack's own configuration: what a fresh `claude` process reads when it
# starts, and what the next run sources. No write-surface may cover these, and
# the snapshot takes them by force whatever GUARDED_PATHS says — emptying a
# config key must not be a way to unseal the harness.
#
# `.claude/settings.local.json` is the armed case and the reason this list
# exists: it is ignored by convention in every Claude Code project, so nothing in
# this pack could see it, and hooks, permissions and env in it take effect on the
# very next spawn. A session that wrote it would be configuring the harness that
# judges its successors. `ralph.config.sh` carries TEST_CMD, so a session that
# set it to `true` would make every later gate green while proving nothing.
#
# The list is derived from that sentence and not from the cases that prompted it,
# because [31] found it three files short of its own criterion. Read against the
# criterion, in order:
#
#   settings.json, settings.local.json    permissions, env, and hooks — a hook is
#                                         a command, so this is the entry that
#                                         makes the list about code execution and
#                                         not only about instructions
#   CLAUDE.md, CLAUDE.local.md            read by every spawn. Sealing them means
#                                         no ticket can ever deliver them again,
#                                         and in this repository that includes its
#                                         own definition of done. Taken as a
#                                         decision: the loop does not get to edit
#                                         the rules it is judged by. [14]'s
#                                         autonomous promotion of a recurring
#                                         lesson therefore goes to its own
#                                         injected index, or escalates
#   .mcp.json                             a server's `command` is launched by
#                                         every spawn — probed, [31]. This one is
#                                         not an instruction channel, it is an
#                                         execution channel
#   .claude/agents, commands, skills,     capabilities, which take effect at the
#   hooks                                 next spawn. Free to seal: [15] already
#                                         refuses to let a run create a capability
#                                         on its own, so no ticket needs to write
#                                         them. One reserve, worth knowing before
#                                         claiming coverage: here `.claude/skills`
#                                         is a set of symlinks, and a write
#                                         *through* a link lands outside the sealed
#                                         path. The scope-guard sees that write as
#                                         itself; the seal does not see it at all
#   the config the next run sources       under the name it actually carries, see
#                                         gate__sealed_config
#
# The pack's *code* is deliberately not sealed. A run has sourced its libs before
# the first session starts, so editing them cannot change the judgement of the
# run in progress; and a ticket that rewrites `gate.sh` is exactly what this
# repository does with itself. What a fresh `claude` reads is the different
# question, because it lands on the next spawn and nothing looks at it.
#
# And sealing *detects*: it reds the iteration at aggregation, after every branch
# has run in the tree where the file was. That is enough for the next session — the
# rollback removes the file before anything spawns again — and it is not enough for
# the gate's own lens phase, which is a `claude` starting in that same tree. What
# covers that window is argv, on the spawn: see lenses_posture.
# One printf per group rather than one long line: the groups answer different
# halves of the criterion, and a reader checking the list against it should be
# able to see which is which.
gate_sealed_paths() {
  printf '%s ' '.claude/settings.local.json .claude/settings.json'
  printf '%s ' 'CLAUDE.md CLAUDE.local.md'
  printf '%s ' '.mcp.json'
  printf '%s ' '.claude/agents .claude/commands .claude/skills .claude/hooks'
  gate__sealed_config
  printf '\n'
}

# The file the next run sources, under the name it actually carries. `RALPH_CONFIG`
# is an environment variable: a run started with another value leaves its real
# configuration open to a write-surface, and a session that writes TEST_CMD there
# chooses the gate of every run that follows. Probed on 30/07/2026 with
# `RALPH_CONFIG=.claude/ralph.prod.sh`: green iteration, no complaint, `TEST_CMD`
# set to `true` waiting for the next run.
#
# Worse than a gate that passes, since [29]: what TEST_CMD writes while it runs is
# judged by nothing and undone by nothing, and the one argument that makes that
# tolerable is that the command comes from a sealed file. A config under an
# unsealed name breaks the chain at both ends at once.
#
# Repo-relative, because that is what a tree path is. The default is always in the
# list as well: a run whose RALPH_CONFIG points outside the tree must not quietly
# unseal the ordinary one.
# The path is resolved with `pwd -P` before being compared, and that is not
# defensive noise: `$PWD` is the logical path — on a mac a temporary directory is
# reached as /var/folders/… — while `git rev-parse --show-toplevel` answers the
# physical one, /private/var/folders/…. A literal prefix test would decide that the
# config lives outside the repository and seal nothing at all, which is a control
# that fails open on the shape of a path.
#
# One side, not both: git normalises its own answer, so resolving the root as well
# was a line nothing could ever make red — removed rather than left with a mutation
# entry pretending to cover it.
gate__sealed_config() {
  local config="${RALPH_CONFIG:-}" root dir
  printf '%s' '.claude/ralph.config.sh'
  [ -n "$config" ] || return 0

  case "$config" in
    /*) ;;
    *) config="$PWD/$config" ;;
  esac
  dir="$(cd "$(dirname "$config")" 2>/dev/null && pwd -P)" || return 0
  [ -n "$dir" ] || return 0
  config="$dir/$(basename "$config")"

  root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 0
  [ -n "$root" ] || return 0
  case "$config" in
    "$root"/*) printf ' %s' "${config#"$root"/}" ;;
  esac
}

# Matched the same way a write-surface is, so a sealed directory would cover what
# is under it. See gate_in_surface, below.
gate_is_sealed() {
  gate_in_surface "$1" "$(gate_sealed_paths)"
}

# The paths the whole-tree snapshot takes by force. `.claude` by default — the
# pack itself, and the settings a session reads. GUARDED_PATHS is the project's
# to widen or narrow: a project whose own tooling writes under a guarded path
# while a session runs would otherwise watch every iteration go red on it. The
# sealed configuration is added whatever the key says.
gate_guarded_paths() {
  printf '%s %s\n' "${GUARDED_PATHS-.claude}" "$(gate_sealed_paths)"
}

# The ignored paths nothing in this pack looks at, enumerated rather than
# alluded to. "The tree is back where the session found it, except for a set of
# paths nobody lists" is the half-truth [24] was opened for.
#
# Directories are collapsed, so a project's `node_modules/` is one line and not a
# hundred thousand. Two exclusions, and both are load-bearing: the guarded paths,
# because the snapshot takes those by force and they *are* judged; and the
# feature's own bookkeeping, because [19] gitignores the run journal, the run
# lock and the session stream, all of which are written *during* the window being
# watched. Without the second one, every iteration of every project would report
# its own journal as an unjudged write — which is the same reason the scope-guard
# drops it (gate_is_bookkeeping, one definition, now three readers).
gate_unguarded_ignored() {
  local listing guarded file
  listing="$(git ls-files --others --ignored --exclude-standard --directory 2>/dev/null)" ||
    listing=""
  guarded="$(gate_guarded_paths)"

  while IFS= read -r file; do
    [ -n "$file" ] || continue
    if gate_is_bookkeeping "$file"; then continue; fi
    if gate_in_surface "${file%/}" "$guarded"; then continue; fi
    printf '%s\n' "$file"
  done <<IGNORED
$listing
IGNORED
  return 0
}

# A zone as one line: how many paths, and the first ten of them. Non-zero when
# there is nothing to say, so a caller can ask and stay silent. Ten names and no
# more; the count says how many were left out.
#
# Public, and the noun is the caller's. There are two zones nothing in this pack
# reaches — what git hides and what the gate wrote while it judged — and each of
# them is read by two callers with different things to say about the same list:
# the gate did not judge it, the rollback could not undo it. Counting and
# truncating in four places would drift in four directions.
gate_zone_line() {
  local list="$1" noun="$2"
  [ -n "$list" ] || return 1
  printf '%s %s: %s\n' \
    "$(printf '%s\n' "$list" | awk 'END { print NR }')" "$noun" \
    "$(printf '%s\n' "$list" | head -10 | tr '\n' ' ' | sed 's/ *$//')"
}

gate_ignored_zone() {
  local left
  left="$(gate_unguarded_ignored)" || left=""
  gate_zone_line "$left" 'ignored path(s)'
}

# ── what the gate itself changed ─────────────────────────────────────────────
#
# The gate is not a passive observer of the tree it judges. `TEST_CMD` and
# `TYPECHECK_CMD` are the target project's own commands — a coverage report, an
# updated test snapshot, a compiler cache — and a review lens ([06]) will be a
# `claude`. Whatever they write lands *after* the tree was taken, so it sits in
# neither of the two trees the rollback diffs: it survives the rollback, and it is
# not ignored by git either, so the zone of [24] does not name it.
#
# Which makes it the rollback's second unenumerated exemption, and it gets the
# same answer as the first: name it every time rather than let "the tree is back
# where the session found it" pass for a complete statement. It is not a verdict
# and must not become one — a project whose suite writes an artefact on every run
# has done nothing wrong, and reddening that would refuse every project that has
# a build.
#
# Before [29] this set was not merely unnamed, it was undecidable: the scope-guard
# took its own snapshot from inside its branch, in parallel with the suite, so
# whether a given artefact was "what the gate wrote" or "what the session wrote"
# depended on which process got there first.
gate_unjudged_changes() {
  local judged="$1" now
  [ -n "$judged" ] || return 0
  now="$(gate_tree_snapshot)" || return 0
  [ "$now" != "$judged" ] || return 0
  git diff-tree -r --name-only "$judged" "$now" 2>/dev/null | gate__drop_bookkeeping
}

# ── the diff an iteration is judged on ───────────────────────────────────────

# Everything in the working tree right now, as a git tree object: tracked or
# not, committed or not, the guarded paths included whether the project ignores
# them or not. Built in a throwaway index, so the real one is untouched.
#
# The commit at HEAD would be the obvious baseline and it is the wrong one. A
# green iteration is not committed by anything today, so its files are still
# lying in the tree when the next session starts: judged against HEAD, the
# second iteration of a run inherits the first one's work as its own overflow —
# and, worse, gets it classified as drift into the ticket that produced it. The
# same goes for a run started on a tree that was already dirty. A tree object
# says what was there when this session began, which is the actual question.
#
# Given paths, only those are snapshotted, and they are taken by force —
# ignore rules included. A caller that names a path is watching it deliberately,
# and a target project that gitignores `.scratch/` must not thereby switch the
# tracker's own guard off.
#
# Without paths, the whole tree, and there the project's ignore rules are obeyed
# with one named exception. `git add -A --force` on everything is not the fix and
# never will be: a project's build output would land in the tree the scope-guard
# judges and the rollback acts on, so every iteration would look like an overflow
# and every rollback would delete a cache the run has no business touching. So
# the guarded paths are forced on top of an ordinary `git add -A` — a named list,
# which only sees what somebody thought to name. What is left is enumerated
# instead of judged: see gate_unguarded_ignored.
gate_tree_snapshot() {
  local index tree path
  index="$(mktemp "${TMPDIR:-/tmp}/ralph-index.XXXXXX")" || return 1
  rm -f "$index"
  if [ "$#" -gt 0 ]; then
    GIT_INDEX_FILE="$index" git add -A --force -- "$@" >/dev/null 2>&1
  else
    GIT_INDEX_FILE="$index" git add -A >/dev/null 2>&1
    # One `git add` per guarded path rather than one for all of them: a pathspec
    # that matches nothing makes git refuse the whole call, and a project is free
    # to name a path it does not have yet. A refused pathspec leaves the snapshot
    # exactly as the plain `git add -A` left it, which is the status quo.
    for path in $(gate_guarded_paths); do
      GIT_INDEX_FILE="$index" git add -A --force -- "$path" >/dev/null 2>&1 || true
    done
  fi
  tree="$(GIT_INDEX_FILE="$index" git write-tree 2>/dev/null)" || tree=""
  rm -f "$index"
  [ -n "$tree" ] || return 1
  printf '%s\n' "$tree"
}

# What this session changed, and only this session. The second argument is the
# post-session tree when the caller already has one — the failure policy and the
# durable commit both act on the very tree the scope-guard judged, rather than
# re-reading a tree the test suite may have touched since.
#
# A baseline that is missing is never read as "nothing changed": a guard that
# cannot see must not pass.
#
# Public, and named so: the failure policy commits through it and the review
# lenses will read the diff through it. It was `gate__changed_files` until the
# second caller appeared, which made a private name a lie.
gate_changed_files() {
  local base="$1" now="${2:-}"
  [ -n "$now" ] || now="$(gate_tree_snapshot)" || now=""
  [ -n "$base" ] && [ -n "$now" ] || return 1
  git diff-tree -r --name-only "$base" "$now" 2>/dev/null | gate__drop_bookkeeping
}

# Put every path back to the state a tree object records, and print the ones that
# were put back, one per line.
#
# Two callers, and they are the reason this is here rather than in either of them.
# The rollback of a failed iteration ([07]) restores the tree the session was
# handed; the containment of what a review lens wrote ([06]) restores the tree the
# lens was handed. Same twelve lines, and a second copy of them would drift from
# this one — the pack has already paid for that once, on a bare `wait` written
# twice ([25]). One of the two callers restores a repository a human may have work
# in, so the drift would not be cosmetic.
#
# What it does *not* do is the caller's business: this moves no ref, unstages
# nothing, and says nothing about what it could not reach. The rollback needs all
# three and the lens containment needs none of them.
#
# The loop's own bookkeeping is skipped here rather than by each caller, and that
# is load-bearing in both directions: the tracker is the only authority on state
# this system has, and the session stream is being appended to inside the very
# window a lens runs in.
gate_restore_tree() {
  local base="$1" now="${2:-}" idx status path
  [ -n "$base" ] || return 1
  [ -n "$now" ] || now="$(gate_tree_snapshot)" || now=""
  [ -n "$now" ] || return 1

  idx="$(mktemp "${TMPDIR:-/tmp}/ralph-restore.XXXXXX")" || return 1
  rm -f "$idx"
  if ! GIT_INDEX_FILE="$idx" git read-tree "$base" 2>/dev/null; then
    rm -f "$idx"
    return 1
  fi

  while IFS="$(printf '\t')" read -r status path; do
    [ -n "$path" ] || continue
    if gate_is_bookkeeping "$path"; then continue; fi
    case "$status" in
      A)
        rm -f "$path"
        # Stops at the first directory that is not empty, so a directory the
        # session did not create survives.
        rmdir -p "$(dirname "$path")" 2>/dev/null || true
        ;;
      *)
        GIT_INDEX_FILE="$idx" git checkout-index -f -- "$path" 2>/dev/null ||
          gate__log "could not restore $path"
        ;;
    esac
    printf '%s\n' "$path"
  done <<RESTORE
$(git diff-tree -r --name-status "$base" "$now" 2>/dev/null)
RESTORE

  rm -f "$idx"
  return 0
}

# The loop's own writes are not the session's doing: claiming a ticket rewrites
# it, and the journal, the run lock and the session stream all live in the
# feature directory. Paths are repo-root relative, which is the project root —
# a pack installed below the repo root is out of scope for now.
#
# One definition, two readers: the scope-guard filters a list, the rollback asks
# path by path. A second copy of the rule would drift from this one and let the
# rollback rewrite the tracker — the only authority on state this system has.
gate_is_bookkeeping() {
  case "$1" in
    ".scratch/${FEATURE}/"*) return 0 ;;
  esac
  return 1
}

gate__drop_bookkeeping() {
  local file
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    if gate_is_bookkeeping "$file"; then continue; fi
    printf '%s\n' "$file"
  done
  return 0
}

# ── the scope-guard ──────────────────────────────────────────────────────────

# The declared write-surface as a plain list of globs. Backticks and commas are
# how a ticket writes it for a human; neither means anything here.
gate_write_surface() {
  tracker_field "$1" 'Write-surface' 2>/dev/null | tr -d '`,' | awk '{ $1 = $1; print }'
}

# Whether a path is covered by a surface. A pattern also covers what is under
# it, so a ticket can declare a directory instead of enumerating its files.
gate_in_surface() {
  local file="$1" pattern
  for pattern in $2; do
    pattern="${pattern%/}"
    [ -n "$pattern" ] || continue
    case "$file" in
      $pattern | $pattern/*) return 0 ;;
    esac
  done
  return 1
}

# Which other ticket declared this path. An overflow into another ticket's
# surface is a scoping conflict rather than a stray write: two tickets were
# drawn over one file, and retrying would only break the disjunction the
# parallel scheduler relies on. The failure policy tells them apart.
gate__surface_owner() {
  local file="$1" self="$2" id
  for id in $(tracker_ids); do
    [ "$id" != "$self" ] || continue
    if gate_in_surface "$file" "$(gate_write_surface "$id")"; then
      printf '%s\n' "$id"
      return 0
    fi
  done
  return 1
}

# Runs as a gate branch: findings on stdout, the classification in a sidecar file
# because a branch runs in its own process and cannot set a variable here.
#
# Both trees are given, and neither is read from the tree on disk. This function
# used to snapshot the working tree itself, from inside its own branch — which is
# to say while the test suite and the type check were already writing to it. The
# same session on the same ticket then got `scope=green` or `scope=red` depending
# on which process wrote first, and on one path that draw was final: an artefact
# landing in another ticket's write-surface is classified `contract`, deliberately
# not retryable, so the ticket went to the human sink without spending a retry for
# something no session had done. A control that freezes its input while other
# processes are still writing does not return a verdict, it returns a draw ([29]).
#
# An empty tree is refused rather than recomputed, and that matters more than it
# looks: `gate_changed_files` takes its own snapshot when it is not given one, so
# falling through to it would quietly restore the very race this argument exists
# to close. A guard that cannot see must not pass.
#
# A ticket with no declared write-surface is the fail-safe case: an unknown
# surface can never be assumed to contain anything.
gate__scope_guard() {
  local ticket="$1" base="$2" now="$3" classfile="$4"
  local surface changed file owner class='' rc=0

  if [ -z "$now" ] || ! changed="$(gate_changed_files "$base" "$now")"; then
    printf 'the scope-guard could not read the working tree — refusing to pass it\n'
    return 1
  fi

  surface="$(gate_write_surface "$ticket")"

  while IFS= read -r file; do
    [ -n "$file" ] || continue
    # Asked before the surface is consulted, and that ordering is the whole of
    # the guarantee: a ticket that declared the harness's own configuration would
    # otherwise buy a session the right to configure the sessions after it. Red,
    # and retryable — a fresh session starts from a tree the rollback has already
    # cleaned, so there is nothing here a retry cannot settle.
    if gate_is_sealed "$file"; then
      rc=1
      if [ -z "$class" ]; then class=internal; fi
      printf 'wrote %s, which configures the harness itself — no write-surface may cover it\n' "$file"
      continue
    fi
    if gate_in_surface "$file" "$surface"; then
      continue
    fi
    rc=1
    owner="$(gate__surface_owner "$file" "$ticket" || true)"
    if [ -n "$owner" ]; then
      class=contract
      printf 'wrote %s, inside the write-surface of %s (drift)\n' "$file" "$owner"
    else
      if [ -z "$class" ]; then class=internal; fi
      printf 'wrote %s, outside the declared write-surface\n' "$file"
    fi
  done <<SCOPE
$changed
SCOPE

  if [ -n "$class" ]; then
    printf '%s\n' "$class" >"$classfile"
  fi
  return "$rc"
}

# ── running the branches ─────────────────────────────────────────────────────

# One branch, in its own process: output to a file, exit code to another. The
# exit code file is the verdict, and its absence is a verdict too.
gate__branch() {
  local dir="$1" name="$2"
  shift 2
  local rc=0
  "$@" >"$dir/$name.out" 2>&1 || rc=$?
  printf '%s\n' "$rc" >"$dir/$name.rc"
}

gate__start() {
  local dir="$1" name="$2"
  shift 2
  (gate__branch "$dir" "$name" "$@") &
}

# The deadline. `wait` cannot take a timeout in bash 3.2, so the deadline is a
# process of its own: it sleeps in one-second steps — so that killing it leaves
# at most a one-second orphan behind — and then takes the branches down.
#
# A killed branch writes no exit code, and a branch with no verdict already
# counts red. The timeout needs no verdict of its own: it only has to stop a
# `TEST_CMD` that hangs from hanging the whole run, which the smart-zone net
# cannot do because it watches the session and not the gate.
#
# The walk itself lives in lib/proc.sh since [23] gave it a second caller. What
# does *not* follow it here is the KILL a session deadline needs: what this
# collects is `gate__branch` in a subshell, and a subshell has its traps reset to
# their defaults, so it dies of the TERM whether or not the command under it does
# — probed on 30/07/2026, 143 with no trap against a survivor with `trap '' TERM`.
# A `TEST_CMD` that ignores the signal is therefore orphaned rather than hanging
# the run, which is a leak and not a deadlock. The session is the other case, and
# it is the one that hangs: `claude` is an external binary the loop waits on
# directly, with nothing between the signal and the process.
gate__watchdog() {
  local limit="$1" marker="$2"
  shift 2
  local waited=0 pid
  while [ "$waited" -lt "$limit" ]; do
    sleep 1
    waited=$((waited + 1))
  done
  : >"$marker"
  for pid in "$@"; do
    proc_kill_tree "$pid"
  done
  return 0
}

# The zone this gate did not look at, named on every iteration rather than left
# to a document nobody reads at three in the morning. It is not a verdict and
# must not become one: the paths listed here are the project's own ignored files,
# and turning them red would mean refusing every project that has a build.
#
# What it buys is the one failure a per-ticket review cannot see. A file dropped
# in this zone survives the rollback and every later iteration, so a `TEST_CMD`
# that reads it — an `.env`, a fixture cache, a test database, `node_modules` —
# can be turned green by what an earlier session left behind. Probed: two
# tickets, the second green thanks to the first one's write, both marked
# resolved. Naming the zone is what makes that visible in the morning.
gate__report_unguarded() {
  local ticket="$1" zone
  if zone="$(gate_ignored_zone)"; then
    gate__log "$ticket: nothing in this gate judged $zone"
  fi
  return 0
}

# And the other zone nothing here reaches: what the gate's own branches wrote
# while they were judging. Same shape as the line above and for the same reason —
# it is not a verdict, it is the half of "the tree is back where the session found
# it" that would otherwise go unsaid. Said on every iteration, green included:
# a green one has no rollback at all, and the artefact is still there.
gate__report_changed() {
  local ticket="$1" zone
  if zone="$(gate_zone_line "$(gate_unjudged_changes "$2")" \
    'path(s) after the tree it judged')"; then
    gate__log "$ticket: this gate itself changed $zone"
  fi
  return 0
}

# One fan, from started to collected, with its own deadline.
#
# Extracted because there are two fans now and a second copy of the collection
# would be a second place for the graceful stop to be got wrong — the pack has
# already paid for one bare `wait` written twice ([25]).
#
# An unset, zero or non-numeric GATE_TIMEOUT means no deadline. That is the status
# quo and not a false green: a hung branch never comes back green.
gate__await() {
  local dir="$1" pids="$2" watchdog='' brc

  case "${GATE_TIMEOUT:-0}" in
    '' | 0 | *[!0-9]*) ;;
    *)
      # shellcheck disable=SC2086
      gate__watchdog "$GATE_TIMEOUT" "$dir/timed-out" $pids &
      watchdog=$!
      ;;
  esac

  # The status is dropped here on purpose: a branch's verdict is the `.rc` file it
  # wrote, and the watchdog is expected to come back 143 because we just killed it.
  # `proc_collect` hands the child's status back for the caller that does need it —
  # `session_spawn`, whose exit code is the session's ([28]).
  for brc in $pids; do
    proc_collect "$brc" || true
  done

  if [ -n "$watchdog" ]; then
    kill -TERM "$watchdog" 2>/dev/null || true
    proc_collect "$watchdog" || true
  fi
  return 0
}

# Turn the exit-code files a fan left behind into verdicts, and say what went
# wrong. Appends to RALPH_GATE_VERDICTS and RALPH_GATE_FAILED, so it must be
# called in the loop's own shell and never from a subshell or a pipeline — the
# detail would be lost in silence, and the failure policy would be unable to tell
# a drift from a neutral file ([05]).
#
# The absence of an exit-code file is a verdict of its own, and it is red.
gate__aggregate() {
  local dir="$1" names="$2" name brc rc=0

  for name in $names; do
    brc=""
    if [ -f "$dir/$name.rc" ]; then brc="$(cat "$dir/$name.rc")"; fi
    if [ "$brc" = 0 ]; then
      RALPH_GATE_VERDICTS="$RALPH_GATE_VERDICTS $name=green"
      continue
    fi
    RALPH_GATE_VERDICTS="$RALPH_GATE_VERDICTS $name=red"
    RALPH_GATE_FAILED="$RALPH_GATE_FAILED $name"
    rc=1
    if [ -n "$brc" ]; then
      gate__log "$name red (exit $brc)"
    elif [ -f "$dir/timed-out" ]; then
      gate__log "$name red (timed out after ${GATE_TIMEOUT}s)"
    else
      gate__log "$name red (no verdict)"
    fi
    gate__report "$dir/$name.out"
  done
  return "$rc"
}

# ── the lens phase ───────────────────────────────────────────────────────────

# The judgement tier, after the objective one and never beside it. Returns
# non-zero if a lens was red or if the tree could not be put back the way the
# lenses found it.
#
# Skipped on a red objective phase, and said out loud when it is: a lens costs a
# real session against the subscription, and no verdict it could return would
# change a gate that is already red. Skipped is not passed — nothing is added to
# the verdicts, exactly as an unconfigured type check is absent rather than green.
#
# The local is `lenses` and not `names`, which is not a style choice: the call to
# gate__aggregate below would otherwise be character-for-character the one in
# gate_run, and a mutation anchored on either would silently edit the first. That
# is the trap [29] fell into — a substitution without /g applies to the first match,
# so a duplicated line turns a mutation into a lie whose symptom is VACUOUS on a
# healthy test.
gate__lens_phase() {
  local ticket="$1" base="$2" dir="$3" objective_rc="$4"
  local lenses pids='' name pre rc=0

  lenses="$(lenses_triggered "$ticket" | tr '\n' ' ')"

  # A zone nothing guards gets named every time round, not once in a document
  # ([24]). A gate with no judgement tier is green on its own tests and on
  # nothing else, and a human reading the morning log has to be able to see that
  # without remembering which key was set.
  if [ -z "${lenses# }" ]; then
    if [ -z "$(lenses_enabled)" ]; then
      gate__log "$ticket: no review lens ran (LENSES is empty): nothing here judged this work by anything but its own tests"
    else
      gate__log "$ticket: no review lens was triggered by this ticket"
    fi
    return 0
  fi

  if [ "$objective_rc" != 0 ]; then
    gate__log "$ticket: the review lenses did not run: the objective checks are already red ($RALPH_GATE_FAILED)"
    return 0
  fi

  # The tree as the lenses found it. Taken here rather than reused from
  # RALPH_GATE_TREE on purpose: the suite has run since then and may legitimately
  # have written, so this is the only baseline against which a write is
  # attributable to a lens and nothing else.
  pre="$(gate_tree_snapshot)" || pre=""

  for name in $lenses; do
    gate__start "$dir" "$name" \
      lenses_review "$name" "$ticket" "$base" "$RALPH_GATE_TREE" "$dir"
    pids="$pids $!"
  done

  gate__await "$dir" "$pids"
  gate__aggregate "$dir" "$lenses" || rc=1
  gate__contain_lens_writes "$ticket" "$pre" || rc=1
  return "$rc"
}

# What a lens wrote in the tree it was judging, put back.
#
# This is the half of the read-only promise that is a guarantee. The other half is
# `--tools` on the spawn (lenses_tools), which is prevention and depends on the
# binary honouring it; this is verification and depends on nothing but two tree
# objects. A control that rests on a flag a release could stop honouring is a
# hope, and this pack has a document listing what happens to those.
#
# Red only if something survives being put back. A lens that wrote and was undone
# has cost the iteration nothing, and reddening it would charge a retry to a
# session that did nothing wrong — the mistake [29] found in the scope-guard's
# race, one layer up. A write that *cannot* be undone is different: the pack can no
# longer say what is in the tree, and green would be a false green.
gate__contain_lens_writes() {
  local ticket="$1" pre="$2" changed left

  if [ -z "$pre" ]; then
    gate__log "$ticket: could not read the tree before the review lenses — cannot say what they wrote, refusing to pass"
    return 1
  fi

  changed="$(gate_unjudged_changes "$pre")"
  [ -n "$changed" ] || return 0

  gate__log "$ticket: a review lens changed $(gate_zone_line "$changed" \
    'path(s) in the tree it was judging') — putting them back"
  gate_restore_tree "$pre" >/dev/null || true

  left="$(gate_unjudged_changes "$pre")"
  [ -n "$left" ] || return 0
  gate__log "$ticket: could not undo $(gate_zone_line "$left" \
    'path(s) a review lens wrote') — refusing to pass this iteration"
  return 1
}

# Up to 20 lines of what a red branch had to say. Enough to see which test
# broke in the journal; the full picture belongs to the audit receipt.
gate__report() {
  [ -s "$1" ] || return 0
  tail -20 "$1" | sed 's/^/  /'
  return 0
}

# The gate. Green — return 0 — means every branch that was triggered came back
# green, and that is the only thing that resolves a ticket.
gate_run() {
  local ticket="$1" base="${2:-}"
  local dir names='' pids='' rc=0

  # Cleared before the first thing that can fail, so a gate that refuses to start
  # never leaves the previous iteration's tree standing for the rollback to act on.
  RALPH_GATE_VERDICTS=""
  RALPH_GATE_FAILED=""
  RALPH_GATE_SCOPE_CLASS=""
  RALPH_GATE_TREE=""
  dir="$(mktemp -d "${TMPDIR:-/tmp}/ralph-gate.XXXXXX")" || return 1

  # The tree every branch is judged on, taken once and before a single branch is
  # started. Both halves are load-bearing. *Once*, so that the scope-guard, the
  # rollback, the durable commit and — with [06] — a review lens all speak about
  # one state of the repository instead of four snapshots taken while the suite
  # ran. *Before the fan*, so that nothing the gate itself writes can be charged
  # to the session or, worse, to another ticket. Filled into RALPH_GATE_TREE here
  # rather than after the collection: a branch is a subshell, so it inherits what
  # is set before it starts and nothing that is set after.
  #
  # An unreadable tree is left empty on purpose. The scope-guard refuses to pass a
  # ticket it cannot see, which is what makes this branch red rather than absent —
  # and a branch that was never started leaves no verdict to count.
  RALPH_GATE_TREE="$(gate_tree_snapshot)" || RALPH_GATE_TREE=""

  gate__start "$dir" tests bash -c "$TEST_CMD"
  names="$names tests"
  pids="$pids $!"

  # "none" is a project declaring it has no type check. Not triggered, so not
  # part of the verdict — and never counted as a pass.
  if [ -n "${TYPECHECK_CMD:-}" ] && [ "$TYPECHECK_CMD" != none ]; then
    gate__start "$dir" typecheck bash -c "$TYPECHECK_CMD"
    names="$names typecheck"
    pids="$pids $!"
  fi

  gate__start "$dir" scope \
    gate__scope_guard "$ticket" "$base" "$RALPH_GATE_TREE" "$dir/scope.class"
  names="$names scope"
  pids="$pids $!"

  gate__await "$dir" "$pids"
  gate__aggregate "$dir" "$names" || rc=1

  if [ -f "$dir/scope.class" ]; then
    RALPH_GATE_SCOPE_CLASS="$(cat "$dir/scope.class")"
  fi

  # The judgement tier, and it is handed the objective verdict rather than
  # deciding for itself: a phase that consulted `rc` from inside would have to
  # know what this one means by it.
  gate__lens_phase "$ticket" "$base" "$dir" "$rc" || rc=1

  RALPH_GATE_VERDICTS="${RALPH_GATE_VERDICTS# }"
  RALPH_GATE_FAILED="${RALPH_GATE_FAILED# }"

  gate__log "$ticket: $RALPH_GATE_VERDICTS"
  gate__report_unguarded "$ticket"
  gate__report_changed "$ticket" "$RALPH_GATE_TREE"
  rm -rf "$dir"
  return "$rc"
}
