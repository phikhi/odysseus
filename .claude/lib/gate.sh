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
#   RALPH_GATE_IGNORE       the ignore rule sources this session moved outside the
#                           working tree, already phrased as scope findings. Filled
#                           before the fan, like the tree, because the branch that
#                           reports them is a subshell ([30])
#   RALPH_GATE_TREE         the tree every branch is judged on, so the rollback and
#                           the durable commit act on exactly what was approved.
#                           Taken before the fan and filled in before it, so a
#                           branch — a subshell — inherits it ([29]).
#   RALPH_GATE_NOTHING_DELIVERED
#                           1 when the gate refused before judging anything: this
#                           iteration changed no file it can see, so there is
#                           nothing to commit and nothing to review ([35]). A
#                           failure of its own, not a red check — nothing was
#                           judged, and a human sent to read a verdict has been
#                           misrouted

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

# ── how a list of paths travels ──────────────────────────────────────────────
#
# **One entry per line, everywhere inside this pack.** A path may contain a space
# and it may contain a glob character, so a list carried as one whitespace-joined
# line is not a list of paths — it is a list of whatever word splitting and
# pathname expansion make of it, and the two halves of a mechanism reading it with
# different splitters do not disagree loudly, they disagree in silence.
#
# That is the whole of [33]. `gate_tree_snapshot` forced its paths through
# `for path in $list` while `gate__ignored_walk` excluded them by whole-string
# comparison: an ignore rule naming `my dir/` was cut into two pathspecs that
# matched nothing, so the forcing took nothing — swallowed by the `|| true` that
# exists for a path a project has not created yet — while the zone line dropped
# the path from its listing on the grounds that it was forced. Neither judged, nor
# undone, nor named. The same `for` was the only way in for the guarded paths, so
# a project whose `GUARDED_PATHS` named a directory with a space had no guard at
# all, and had had none since [24].
#
# Two authored formats feed those lists, and each is converted where it is read
# rather than travelling as it was typed:
#
#   - a ticket's `Write-surface:` field: markdown on one line, commas and
#     backticks for the human. Converted by gate_write_surface;
#   - the config keys that name globs (`SECURITY_PATHS`, `VISIBLE_PATHS`):
#     whitespace-separated, converted by their reader in lib/lenses.sh.
#
# Neither can express a path with a space, and that is a property of the format a
# human types — not of the lists this pack builds. `GUARDED_PATHS` is the one
# exception and is authored one path per line, because it names paths rather than
# globs and a project whose guarded directory carries a space has to be able to
# name it. See its comment in ralph.config.sh.example.

# An authored whitespace list as one entry per line. Empty in, empty out.
gate_authored_list() {
  printf '%s\n' "${1-}" | tr -s '[:space:]' '\n' | sed '/^$/d'
}

# Whether a path is one of a list of paths, or under one of them.
#
# Taken **literally**, and that is the difference with gate_in_surface, which
# matches a list of globs a human wrote. This one reads lists of paths the pack
# itself carries — the guarded paths, the sealed configuration — and a path is
# not a pattern: `zone[1]` is a directory a project may really have, and a guard
# that reads it as a character class guards `zone1` instead.
#
# The two readings cannot be mixed, and choosing was the second half of [33]. The
# forcing in gate_tree_snapshot uses `:(literal)` pathspecs for the same reason,
# so a guarded path means the same thing to the half that takes it and to the
# half that decides it was taken. The price is written down rather than hidden: a
# `GUARDED_PATHS` entry written as a glob — `vendor/*` — now guards nothing, and
# says so, because the forcing matches nothing and the zone line then names
# `vendor/` as a path this gate did not judge. Before, it guarded something and
# the zone line stayed quiet about the paths it did not.
gate__under_path() {
  local file="$1" path
  while IFS= read -r path; do
    path="${path%/}"
    [ -n "$path" ] || continue
    case "$file" in
      "$path" | "$path"/*) return 0 ;;
    esac
  done <<PATHS
$2
PATHS
  return 1
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
# able to see which is which. One path per line within a group, for the reason in
# "how a list of paths travels": the last entry is a path a run names through
# `RALPH_CONFIG`, and nothing stops that path from carrying a space.
gate_sealed_paths() {
  printf '%s\n' '.claude/settings.local.json' '.claude/settings.json'
  printf '%s\n' 'CLAUDE.md' 'CLAUDE.local.md'
  printf '%s\n' '.mcp.json'
  printf '%s\n' '.claude/agents' '.claude/commands' '.claude/skills' '.claude/hooks'
  gate__sealed_config
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
  printf '%s\n' '.claude/ralph.config.sh'
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
    "$root"/*) printf '%s\n' "${config#"$root"/}" ;;
  esac
}

# A sealed directory covers what is under it, so `.claude/agents` seals the files
# in it. Matched literally and not as a glob: the last entry of the list is a path
# a run names through `RALPH_CONFIG`, and a seal that read it as a pattern would
# seal a file nobody named. See gate__under_path.
gate_is_sealed() {
  gate__under_path "$1" "$(gate_sealed_paths)"
}

# The paths the whole-tree snapshot takes by force. `.claude` by default — the
# pack itself, and the settings a session reads. GUARDED_PATHS is the project's
# to widen or narrow: a project whose own tooling writes under a guarded path
# while a session runs would otherwise watch every iteration go red on it. The
# sealed configuration is added whatever the key says.
#
# One path per line, on both sides, and the key is authored that way too: a
# directory a project guards may have a space in its name, and splitting the key
# on whitespace would leave it with no guard rather than with a guard it can see
# ([33]).
gate_guarded_paths() {
  printf '%s\n' "${GUARDED_PATHS-.claude}"
  gate_sealed_paths
}

# ── who moves the frontier of that zone ──────────────────────────────────────
#
# [24] asked how far these checks see into the zone above and answered it. The
# missing half is who decides where the zone *starts*: ignore rules are files, and
# a session can write them ([30]). Two paths, both probed on 30/07/2026, both
# green with the off-surface file still standing and no complaint from the
# scope-guard:
#
#   - a `.gitignore` a ticket declares in its write-surface. The loop then commits
#     the rule, so the blindness outlives the run;
#   - `.git/info/exclude`, which needs no write-surface at all, because nothing
#     in this pack looks at `.git/`.
#
# Forcing the whole tree is not the answer and never will be — see
# gate_tree_snapshot. The answer is that **the rules that decide an iteration are
# the rules it was handed**, which is the same shape as the write-surface since
# [21] and makes the legitimate case free: a ticket may add an ignore rule, and it
# takes effect on the next iteration rather than on the one that wrote it.
#
# Four sources decide and they get three treatments, because they are not the same
# kind of thing (see gate_ignore_frontier): the `.gitignore` files of the working
# tree; `.git/info/exclude` and `core.excludesFile`, in the git directory; and the
# global excludes file, which lives outside the repository altogether.

# The rules as they stood, kept as a witness repository — a git directory of its
# own carrying copies of every rule source and no project files at all. Printed as
# a path; the loop holds it in RALPH_IGNORE_PIN for the length of one iteration
# and takes a fresh one for the next.
#
# A witness repository rather than a parsed copy of the rules, because gitignore
# semantics belong to git: directory-only patterns, negations, `**`, and a rule
# whose meaning depends on which directory its file sits in. So "would these rules
# have hidden this path" is asked of `git check-ignore` inside the witness, which
# answers on path names and never stats them — probed on 30/07/2026, including a
# nested `.gitignore` and a directory-only pattern matching a file under it.
#
# It lives in a temporary directory, which is as far from the tree as a pack that
# diffs trees can put anything. A session that reaches into `$TMPDIR` is the same
# limit as one that reaches into `.git/`: out of reach of the loop, and the reason
# the pin is refused rather than ignored when it cannot be read.
gate_ignore_pin() {
  local pin rules file dir
  pin="$(mktemp -d "${TMPDIR:-/tmp}/ralph-ignore.XXXXXX")" || return 1
  rules="$pin/rules"
  mkdir -p "$rules" "$pin/empty" || return 1

  # An empty template: the machine's git templates must not leave an
  # `info/exclude` of their own in the witness, and its hooks have no business
  # running for a repository that exists to answer one question.
  if ! git init -q --template="$pin/empty" "$rules" >/dev/null 2>&1; then
    rm -rf "$pin"
    return 1
  fi

  while IFS= read -r file; do
    [ -n "$file" ] || continue
    dir="$(dirname "$file")"
    mkdir -p "$rules/$dir" 2>/dev/null || continue
    # A tracked rule file the session has since deleted stays in the pin, and
    # that is the right direction: the pin may only ever be wider than what the
    # rules say now, and a narrowing is something this ticket says nothing about.
    cp "$file" "$rules/$file" 2>/dev/null || true
  done <<RULES
$(gate__ignore_tree_rules)
RULES

  # `info/` is created by git's default template, and this witness was told to use
  # an empty one: the directory has to be made rather than assumed. Probed the hard
  # way — without it the copy failed, the pin recorded no local excludes, and the
  # snapshot went on being taken through whatever the session had written there.
  mkdir -p "$rules/.git/info" || true
  : >"$rules/.git/info/exclude"
  file="$(gate__ignore_exclude_path)"
  [ -f "$file" ] && cp "$file" "$rules/.git/info/exclude" 2>/dev/null
  : >"$pin/global"
  file="$(gate__ignore_global_path)"
  [ -f "$file" ] && cp "$file" "$pin/global" 2>/dev/null
  # Set locally, so the machine's own `core.excludesFile` — from the user's global
  # config or from the default `~/.config/git/ignore` — cannot leak into the
  # witness's answers. What the project's rules said about it is pinned above.
  git -C "$rules" config core.excludesFile "$pin/global" >/dev/null 2>&1 || true

  if ! gate__ignore_manifest >"$pin/manifest"; then
    rm -rf "$pin"
    return 1
  fi
  printf '%s\n' "$pin"
}

# Every `.gitignore` of the working tree, tracked or not. A rule file inside an
# ignored directory is deliberately absent: git never reads one either, because it
# never walks into the directory that holds it.
gate__ignore_tree_rules() {
  git ls-files --cached --others --exclude-standard -- '*.gitignore' 2>/dev/null || true
}

gate__ignore_exclude_path() {
  local gitdir
  gitdir="$(git rev-parse --git-dir 2>/dev/null)" || gitdir=""
  [ -n "$gitdir" ] || return 0
  printf '%s/info/exclude\n' "$gitdir"
}

# The excludes file outside the repository: whatever `core.excludesFile` resolves
# to, or git's own default when nothing set it. Named by its path, because that is
# what a human reading a finding needs to go and look at.
gate__ignore_global_path() {
  local value
  value="$(git config --get core.excludesFile 2>/dev/null)" || value=""
  [ -n "$value" ] || value="${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore"
  case "$value" in
    '~/'*) value="$HOME/${value#\~/}" ;;
  esac
  printf '%s\n' "$value"
}

# What the rules are right now, one line per source: kind, name, digest. The three
# kinds are the three answers to "may a session write this, and can the run put it
# back" — gate_ignore_frontier is where that is spelled out.
#
# A missing file digests to `-`, which is what makes an appearing or vanishing
# rule file a movement like any other.
gate__ignore_manifest() {
  local file
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    printf 'tree\t%s\t%s\n' "$file" "$(gate__digest "$file")"
  done <<RULES
$(gate__ignore_tree_rules)
RULES
  printf 'dir\t%s\t%s\n' '.git/info/exclude' \
    "$(gate__digest "$(gate__ignore_exclude_path)")"
  printf 'dir\t%s\t%s\n' 'core.excludesFile' \
    "$(git config --get core.excludesFile 2>/dev/null || printf -- '-')"
  file="$(gate__ignore_global_path)"
  printf 'host\t%s\t%s\n' "$file" "$(gate__digest "$file")"
  return 0
}

gate__digest() {
  [ -n "${1:-}" ] && [ -f "$1" ] || {
    printf -- '-\n'
    return 0
  }
  cksum <"$1" | awk '{ print $1 "." $2 }'
}

# A pin that was set and cannot be read. Refused rather than ignored: the point of
# the pin is that what the checks can see does not depend on what the session left
# behind, so a missing one is a control that cannot see.
gate__ignore_pin_broken() {
  local pin="${RALPH_IGNORE_PIN:-}"
  [ -n "$pin" ] || return 1
  [ -f "$pin/manifest" ] && [ -d "$pin/rules/.git" ] && return 1
  return 0
}

# The rule sources that are not what the pin recorded — appeared, vanished or
# changed — as `kind<TAB>name`. Non-zero when the frontier has not moved, so a
# caller can ask and then do nothing, which is the normal case and the cheap one.
#
# The symmetric difference of two manifests: a line present in both appears twice
# and `uniq -u` drops it. Names are unique inside one manifest, so nothing else
# can pair up.
gate_ignore_moved() {
  local pin="${RALPH_IGNORE_PIN:-}" moved
  [ -n "$pin" ] || return 1
  [ -f "$pin/manifest" ] || return 1
  moved="$( { gate__ignore_manifest; cat "$pin/manifest"; } |
    LC_ALL=C sort | uniq -u | cut -f1,2 | LC_ALL=C sort -u)"
  [ -n "$moved" ] || return 1
  printf '%s\n' "$moved"
}

gate__ignore_pinned() {
  awk -F'\t' -v name="$1" '$2 == name { print $3 }' \
    "${RALPH_IGNORE_PIN:-/dev/null}/manifest" 2>/dev/null || true
}

gate__ignore_current() {
  { gate__ignore_manifest || true; } |
    awk -F'\t' -v name="$1" '$2 == name { print $3 }'
}

# Put one rule source back where the pin found it, and answer whether it is really
# back. Attempt and then verify, because the attempt can succeed on the wrong
# level: `git config --unset` writes the repository's config, so a value a session
# put in the *user's* config would survive it and the restore would be a lie.
gate__ignore_restore() {
  local name="$1" pinned target
  pinned="$(gate__ignore_pinned "$name")"
  case "$name" in
    'core.excludesFile')
      if [ "$pinned" = '-' ]; then
        git config --unset-all core.excludesFile >/dev/null 2>&1 || true
      else
        git config core.excludesFile "$pinned" >/dev/null 2>&1 || true
      fi
      ;;
    '.git/info/exclude')
      target="$(gate__ignore_exclude_path)"
      [ -n "$target" ] || return 1
      if [ "$pinned" = '-' ]; then
        rm -f "$target" 2>/dev/null || true
      else
        # The directory too: a session that removed `info/` outright would
        # otherwise leave a restore that reports success and put nothing back —
        # which the verification below would catch, but as a mystery.
        mkdir -p "$(dirname "$target")" 2>/dev/null || true
        cp "${RALPH_IGNORE_PIN}/rules/.git/info/exclude" "$target" 2>/dev/null || true
      fi
      ;;
    *) return 1 ;;
  esac
  [ "$(gate__ignore_current "$name")" = "$pinned" ]
}

# The frontier this session moved, put back where the run can reach it, and
# phrased as findings for the scope-guard to carry. Non-zero when it found
# something, so `gate_run` can fill a variable and forget about it.
#
# Three kinds, and the difference is the whole of the design:
#
#   tree  a `.gitignore` of the working tree. Ordinary project work — a ticket is
#         allowed to add an ignore rule and [19]'s installer writes one — so
#         nothing is restored and nothing is red. What the rule hides is judged
#         this time round all the same, because the snapshot obeys the pinned
#         rules; from the next iteration on, the rule is what the session was
#         handed and the zone is honestly the project's.
#   dir   `.git/info/exclude` and `core.excludesFile`. Not versioned, not
#         declarable in a write-surface, and between them they decide what every
#         check here can see. Put back from the pin, because otherwise the *next*
#         iteration would pin the widened frontier and inherit the blindness as
#         the project's own configuration — one red iteration would buy a night.
#         And red, on exactly the grounds the sealed configuration is red: this is
#         the harness's own visibility, and no surface may cover it.
#   host  the global excludes file, outside the repository. Red on the same
#         grounds, and this run cannot put it back — what a session writes outside
#         the tree is out of reach of a pack that diffs trees, and the rampart
#         there is the host's isolation ([24]). The iteration that moved it is
#         still judged through the pin; a later one is not, and that residue is
#         written down rather than papered over.
#
# In two passes, and that is the lesson of [29] rather than a shape: a finding has
# to be net of what the run *did* put back. `core.excludesFile` names the file the
# rules come from, so moving it moves two sources at once — the key and the file it
# now points at — and reporting both from one look at the manifest announced a
# path outside the repository as unrecoverable a line after restoring the key that
# had brought it into play. Probed on 03/08/2026: the second finding named a file
# no session had touched.
gate_ignore_frontier() {
  local kind name rc=0
  [ -n "${RALPH_IGNORE_PIN:-}" ] || return 0

  while IFS="$(printf '\t')" read -r kind name; do
    [ "$kind" = dir ] && [ -n "$name" ] || continue
    if gate__ignore_restore "$name"; then
      printf 'moved the ignore frontier in %s, which decides what every check here can see — no write-surface may cover it (put back)\n' "$name"
    else
      printf 'moved the ignore frontier in %s, which decides what every check here can see — and this run could not put it back\n' "$name"
    fi
    rc=1
  done <<INSIDE
$( { gate_ignore_moved || true; } )
INSIDE

  while IFS="$(printf '\t')" read -r kind name; do
    [ "$kind" = host ] && [ -n "$name" ] || continue
    printf 'moved the ignore frontier in %s, outside the repository — no write-surface may cover it, and nothing here can put it back\n' "$name"
    rc=1
  done <<OUTSIDE
$( { gate_ignore_moved || true; } )
OUTSIDE
  return "$rc"
}

# The ignored paths the pinned rules did *not* hide: what a rule written during
# this iteration took out of sight. Forced into the snapshot, which is what makes
# them judged like anything else.
#
# Empty and cheap when the frontier has not moved, which is every ordinary
# iteration: the manifest costs a `git ls-files` and a handful of digests, where
# walking the ignored zone costs the whole working tree.
gate_newly_hidden() {
  local pin="${RALPH_IGNORE_PIN:-}" listing hidden path fence
  [ -n "$pin" ] || return 0
  if gate__ignore_pin_broken; then return 1; fi
  gate_ignore_moved >/dev/null || return 0

  listing="$(git ls-files --others --ignored --exclude-standard --directory 2>/dev/null)" ||
    listing=""
  [ -n "$listing" ] || return 0
  hidden="$( (cd "$pin/rules" 2>/dev/null &&
    printf '%s\n' "$listing" | git check-ignore --stdin 2>/dev/null) || true)"

  fence="
$hidden
"
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    case "$fence" in
      *"
$path
"*) continue ;;
    esac
    printf '%s\n' "$path"
  done <<LISTING
$listing
LISTING
  return 0
}

# The ignored paths nothing in this pack looks at, enumerated rather than
# alluded to. "The tree is back where the session found it, except for a set of
# paths nobody lists" is the half-truth [24] was opened for.
#
# Directories are collapsed, so a project's `node_modules/` is one line and not a
# hundred thousand — which is also the source of the one lie this list has told,
# see gate__ignored_walk.
gate_unguarded_ignored() {
  local listing guarded hidden file
  listing="$(git ls-files --others --ignored --exclude-standard --directory 2>/dev/null)" ||
    listing=""
  guarded="$(gate_guarded_paths)"
  hidden="$(gate_newly_hidden)" || hidden=""

  while IFS= read -r file; do
    [ -n "$file" ] || continue
    gate__ignored_walk "$file" "$guarded" "$hidden"
  done <<IGNORED
$listing
IGNORED
  return 0
}

# One entry of that listing: dropped, printed, or walked into.
#
# Three exclusions, all load-bearing. The guarded paths, because the snapshot
# takes those by force and they *are* judged. The feature's own bookkeeping,
# because [19] gitignores the run journal, the run lock and the session stream,
# all written *during* the window being watched — without it every iteration of
# every project would report the loop's own writes (gate_is_bookkeeping, one
# definition, four readers). And what the pinned rules did not hide, because those
# are forced in too ([30]).
#
# The walk is the lie [24] left in the other direction, and it took [30] to see
# it: `--directory` folds a wholly-ignored directory into one line, so a project
# that gitignores `.scratch/` and has not committed its tracker yet — a fresh
# install, first run — was told `nothing in this gate judged 1 ignored path(s):
# .scratch/`, while [21] snapshots the tickets under it by force. Naming a path
# the pack judged is exactly the half-truth [24] refused for the guarded paths.
# So a folded directory that *holds* something judged is walked one level down
# instead of being reported whole. Everything inside a folded directory is ignored
# by construction — that is why git folded it — so its children can be globbed
# rather than asked of git again.
gate__ignored_walk() {
  local file="$1" guarded="$2" hidden="$3" child
  if gate_is_bookkeeping "$file"; then return 0; fi
  if gate__under_path "${file%/}" "$guarded"; then return 0; fi
  case "
$hidden
" in
    *"
$file
"*) return 0 ;;
  esac

  case "$file" in
    */)
      if gate__ignored_holds_judged "$file" "$guarded"; then
        for child in "$file"* "$file".*; do
          case "${child##*/}" in '.' | '..') continue ;; esac
          [ -e "$child" ] || continue
          if [ -d "$child" ]; then child="$child/"; fi
          gate__ignored_walk "$child" "$guarded" "$hidden"
        done
        return 0
      fi
      ;;
  esac
  printf '%s\n' "$file"
  return 0
}

# Whether a folded directory holds a path this pack judges after all: a guarded
# path, taken by force, or the tracker [21] snapshots by force. Strictly under it —
# a directory that *is* one of those was dropped by the filters above.
gate__ignored_holds_judged() {
  local dir="$1" path
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    case "$path" in
      "$dir"?*) return 0 ;;
    esac
  done <<JUDGED
$2
.scratch/${FEATURE:-}
JUDGED
  return 1
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
#
# A measurement that could not be taken is not an empty measurement ([34]). This
# hands back nothing at all in two cases that look identical on stdout and are
# opposites: nothing changed, and nothing can be said about what changed —
# a baseline the gate never got, or a snapshot the pin refused. So the difference
# lives in the *status*: zero means measured, non-zero means could not measure,
# and every caller below chooses what to do with that rather than inheriting a
# silence. The snapshot already drew that line for the tree it returns; not
# drawing it here left `gate__contain_lens_writes` — the one half of [06] that is
# a guarantee rather than a hope — passing green without having measured, one call
# away from a fail-closed that was correctly written.
gate_unjudged_changes() {
  local judged="$1" now
  [ -n "$judged" ] || return 1
  now="$(gate_tree_snapshot)" || return 1
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
# with two named exceptions. `git add -A --force` on everything is not the fix and
# never will be: a project's build output would land in the tree the scope-guard
# judges and the rollback acts on, so every iteration would look like an overflow
# and every rollback would delete a cache the run has no business touching. So
# the guarded paths are forced on top of an ordinary `git add -A` — a named list,
# which only sees what somebody thought to name — and so is whatever a rule
# written *during this iteration* took out of sight, which is the asymmetric half
# ([30]): the rules obeyed here are the ones the session was handed, so a session
# cannot widen the blind spot it is judged through. What is left is enumerated
# instead of judged: see gate_unguarded_ignored.
gate_tree_snapshot() {
  local index tree path hidden
  index="$(mktemp "${TMPDIR:-/tmp}/ralph-index.XXXXXX")" || return 1
  rm -f "$index"
  if [ "$#" -gt 0 ]; then
    # `:(literal)` here too, for the reason the branch below carries at length: a
    # pathspec is a pattern, so a feature directory really named `sprint[1]` would
    # be forced as `sprint1` — and the caller of this branch is the tracker's own
    # guard ([21]). Left open by [33], which had no caller here to decide for;
    # closed by [34], which had to enumerate every caller anyway.
    #
    # No `|| true`, unlike the branch below, and the asymmetry is the whole point:
    # there a named path a project has not created yet is a tolerated case and the
    # snapshot stands, here a pathspec that matches nothing means the caller cannot
    # be given the thing it asked to watch. `set -e` takes the function down, the
    # caller gets no tree, and that is the refusal it needs — a tracker guard handed
    # an empty tree instead would read it as "the session changed nothing".
    for path in "$@"; do
      GIT_INDEX_FILE="$index" git add -A --force -- ":(literal)$path" >/dev/null 2>&1
    done
  else
    # Asked before anything is added, and a broken pin refuses the whole snapshot:
    # a caller that gets a tree back believes it was built through the rules of the
    # spawn, and a guard that cannot see must not pass.
    if ! hidden="$(gate_newly_hidden)"; then
      rm -f "$index"
      # On stderr, and that is not a detail: every caller of this takes the tree
      # through a command substitution, so a diagnosis on stdout would be captured
      # into the variable and thrown away with the failed status — leaving the
      # refusal downstream with no cause. Probed by destroying a pin mid-session.
      gate__log 'the pinned ignore rules cannot be read — refusing to snapshot a tree whose visibility nothing vouches for' >&2
      return 1
    fi
    GIT_INDEX_FILE="$index" git add -A >/dev/null 2>&1
    # One `git add` per path rather than one for all of them: a pathspec that
    # matches nothing makes git refuse the whole call, and a project is free
    # to name a path it does not have yet. A refused pathspec leaves the snapshot
    # exactly as the plain `git add -A` left it, which is the status quo.
    #
    # One path per line rather than `for path in $list`, and the `|| true` above
    # is why it matters ([33]): word splitting turned a path carrying a space
    # into two pathspecs matching nothing, and the tolerance written for a path a
    # project has not created yet swallowed exactly that. Both producers already
    # print one path per line, and the listing that decides what was *not* forced
    # compares whole lines — so the two halves now cut the list the same way, and
    # cannot disagree about which paths this loop took.
    #
    # `:(literal)` for the same reason one step further in: a git pathspec is a
    # pattern too, so a directory really named `zone[1]` would be taken as a
    # character class and the forcing would land on `zone1`. The listing that
    # names what was not forced reads these paths literally (gate__under_path),
    # and the two halves have to mean the same thing by a guarded path.
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      GIT_INDEX_FILE="$index" git add -A --force -- ":(literal)$path" >/dev/null 2>&1 || true
    done <<FORCED
$(gate_guarded_paths)
$hidden
FORCED
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

# Whether this iteration delivered anything at all: true when the gate can see
# that not one file changed between the tree the session was handed and the tree
# it is about to judge.
#
# The deterministic question none of the three objective branches asks ([35]).
# `tests` and `typecheck` are the project's own commands and answer about the
# tree, not about the change; the scope-guard judges an *overflow*, so an empty
# diff satisfies it by construction — there is nothing sticking out. Until [35]
# the only thing asking it was `lenses_review`, once per lens, as a side effect of
# a judge refusing to judge nothing: a deterministic guarantee filed inside the
# subjective tier, which went out with the tier whenever `LENSES` was empty or no
# lens was triggered. A session that answered without writing a line then took its
# ticket off the frontier for good, `Failures:` dropped with the claim ([26]) and
# nothing anywhere remembering that nobody had done anything.
#
# Asked on the very list `failures_make_durable` commits — `base` against the
# judged tree — and that is the whole of the placement. "Did the session write
# something" and "is what this gate approved non-empty" are one question asked at
# two ends of the chain, and only the second also catches an iteration whose work
# was already in its own baseline. One computation, one meaning.
#
# Fifth reader of a value with two empty answers, and it says which one it is
# ([34]): `gate_changed_files` hands back nothing both when nothing changed and
# when it could not look, and only the first is "nothing was delivered". On the
# second this refuses to conclude — and it does not go red on its own either,
# because the branch that already reds on exactly that is the scope-guard, which
# is handed the same unreadable tree and says so in words a human can act on. A
# "nothing to deliver" computed on a tree nobody could read would be this ticket's
# own false delivered, obtained through the door next to it.
#
# It is written the way `gate__scope_guard` writes its own refusal, and for both
# of its reasons: an empty `now` is refused rather than recomputed, because
# `gate_changed_files` takes a snapshot of its own when it is not given one and
# that would answer about a different tree from the one every branch is judged on
# ([29]).
gate__nothing_delivered() {
  local base="$1" now="$2" changed
  if [ -z "$now" ] || ! changed="$(gate_changed_files "$base" "$now")"; then
    return 1
  fi
  [ -z "$changed" ]
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

# The declared write-surface as a plain list of globs, one per line. Backticks
# and commas are how a ticket writes it for a human; neither means anything here.
# This is one of the two places an authored whitespace list is converted into the
# shape every list travels in — see "how a list of paths travels".
gate_write_surface() {
  gate_authored_list "$(tracker_field "$1" 'Write-surface' 2>/dev/null | tr -d '`,')"
}

# Whether a path is covered by a surface. A pattern also covers what is under
# it, so a ticket can declare a directory instead of enumerating its files.
#
# The surface is read one line per pattern rather than `for pattern in $2`, and
# that is not style ([33]). Word splitting cut a pattern carrying a space into
# two patterns matching nothing — a sealed `my dir/ralph.config.sh` was sealed by
# nothing, a guarded `my vendor/` guarded nothing — and the same expansion also
# globbed the *list* against the working tree, so a pattern like `a[0].txt` was
# replaced by whatever happened to exist. What is deliberately still a glob is
# the pattern in `case`, where an expansion is not word-split.
gate_in_surface() {
  local file="$1" pattern
  while IFS= read -r pattern; do
    pattern="${pattern%/}"
    [ -n "$pattern" ] || continue
    case "$file" in
      $pattern | $pattern/*) return 0 ;;
    esac
  done <<SURFACE
$2
SURFACE
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

  # The frontier of what any of this can see, moved by the session itself, and
  # asked outside the loop over changed files because the sources that carry it are
  # not tree paths at all — `.git/info/exclude` is in no tree, which is precisely
  # why nothing here saw it before [30]. Reported like the seal and for the same
  # reason: it is the harness's own visibility, so no write-surface may cover it,
  # and it is retryable because a fresh session starts from rules the gate has
  # already put back.
  if [ -n "${RALPH_GATE_IGNORE:-}" ]; then
    printf '%s\n' "$RALPH_GATE_IGNORE"
    class=internal
    rc=1
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

# And the cause behind that zone, when the session is the one that moved it. The
# line of [24] names the consequence — `nothing in this gate judged … lib/` — and a
# human reading in the morning cannot tell a build directory a project has always
# ignored from a directory a session decided to make invisible ([30]).
#
# Only the working tree's own rules land here: the sources outside it are findings
# on the scope-guard, not a line, because those the pack refuses outright. This one
# is legitimate work — a ticket may add an ignore rule — so it is said and not
# judged, and what it says is that it did not count this time round.
gate__report_frontier() {
  local ticket="$1" moved
  moved="$( { gate_ignore_moved || true; } |
    awk -F'\t' '$1 == "tree" { print $2 }' | tr '\n' ' ' | sed 's/ *$//')"
  [ -n "$moved" ] || return 0
  gate__log "$ticket: this session moved the ignore frontier: $moved — this iteration was judged through the rules it was handed, the new ones apply from the next"
  return 0
}

# And the other zone nothing here reaches: what the gate's own branches wrote
# while they were judging. Same shape as the line above and for the same reason —
# it is not a verdict, it is the half of "the tree is back where the session found
# it" that would otherwise go unsaid. Said on every iteration, green included:
# a green one has no rollback at all, and the artefact is still there.
#
# And when the measurement cannot be taken, it says that instead — it does not go
# red by symmetry with the containment above ([34]). This is an announcement on an
# iteration that may be perfectly green, and a machine whose `$TMPDIR` was cleaned
# under the run would start refusing honest work. What it owes a human reading the
# morning log is the difference between "this gate wrote nothing" and "nobody
# knows what this gate wrote", which is the lesson [30] paid for on
# `core.excludesFile`: a control that reports its intention rather than its result.
gate__report_changed() {
  local ticket="$1" changed zone
  if ! changed="$(gate_unjudged_changes "$2")"; then
    gate__log "$ticket: this gate could not check what it changed after the tree it judged — nothing here vouches for that zone"
    return 0
  fi
  if zone="$(gate_zone_line "$changed" 'path(s) after the tree it judged')"; then
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
# Fail-closed on both sides of the measurement, and the second side is what [34]
# had to add. The tree *before* the phase was already guarded here; the tree
# *after* it was taken through `gate_unjudged_changes`, which returned an empty
# list when the snapshot refused — so a lens that closed the instrument (a
# destroyed pin, a cleaned `$TMPDIR`, a hook of the judged project) got "nothing to
# undo" and a green iteration with its write still in the tree. Probed.
gate__contain_lens_writes() {
  local ticket="$1" pre="$2" changed left

  if [ -z "$pre" ]; then
    gate__log "$ticket: could not read the tree before the review lenses — cannot say what they wrote, refusing to pass"
    return 1
  fi

  if ! changed="$(gate_unjudged_changes "$pre")"; then
    gate__log "$ticket: could not read the tree after the review lenses — cannot say what they wrote, refusing to pass"
    return 1
  fi
  [ -n "$changed" ] || return 0

  gate__log "$ticket: a review lens changed $(gate_zone_line "$changed" \
    'path(s) in the tree it was judging') — putting them back"
  gate_restore_tree "$pre" >/dev/null || true

  # And once more after the restore, for the same reason: "I put it back" is a
  # claim about a result, and the only thing that can vouch for it is a second
  # measurement. One that refuses says nothing, which is not the same as saying
  # the tree is clean ([30] on `core.excludesFile`, one layer up).
  if ! left="$(gate_unjudged_changes "$pre")"; then
    gate__log "$ticket: could not check what a review lens wrote was put back — refusing to pass this iteration"
    return 1
  fi
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
  local dir names='' pids='' rc=0 finding

  # Cleared before the first thing that can fail, so a gate that refuses to start
  # never leaves the previous iteration's tree standing for the rollback to act on.
  RALPH_GATE_VERDICTS=""
  RALPH_GATE_FAILED=""
  RALPH_GATE_SCOPE_CLASS=""
  RALPH_GATE_IGNORE=""
  RALPH_GATE_TREE=""
  RALPH_GATE_NOTHING_DELIVERED=0
  dir="$(mktemp -d "${TMPDIR:-/tmp}/ralph-gate.XXXXXX")" || return 1

  # Before the tree, so that every branch runs in a repository whose visibility is
  # the run's own and not the session's. The verdict does *not* rest on that
  # ordering, and saying so is the point: the snapshot goes through the pin either
  # way, so a file hidden by a rule written during the session is judged whether or
  # not the rule is still in place. What the restore buys is the iteration *after*
  # this one — without it, the widened frontier is what the next pin records, and a
  # single red iteration would have bought a whole night of blindness ([30]).
  RALPH_GATE_IGNORE="$(gate_ignore_frontier)" || true

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

  # The one verdict this gate can return without starting anything, and it is
  # returned here rather than counted as a fourth branch ([35]). Both trees are
  # already in hand — taken before the fan since [29] — so a branch would pay a
  # process for a string comparison, and would hand the aggregation a verdict that
  # can be pronounced on the spot. What it saves is the rest of the gate: an
  # iteration that delivered nothing is red whatever the project's suite would
  # have answered, so running it, and then a `claude` per lens after it, buys
  # nothing at all.
  if gate__nothing_delivered "$base" "$RALPH_GATE_TREE"; then
    RALPH_GATE_NOTHING_DELIVERED=1
    RALPH_GATE_VERDICTS=" delivery=red"
    RALPH_GATE_FAILED=" delivery"
    rc=1
    gate__log "$ticket: nothing was delivered: this iteration changed no file this gate can see, so there is nothing here to judge and nothing to commit"
    # And what the frontier of that visibility did, which no branch is left to
    # report on this path. `gate_ignore_frontier` has already put the rules back
    # above; its findings normally travel on the scope-guard's output, and a
    # session that moved an ignore rule *and* wrote nothing would otherwise leave
    # the one line naming it unprinted ([30]: a zone nobody guards gets named
    # every time round, not once in a document).
    while IFS= read -r finding; do
      [ -n "$finding" ] || continue
      gate__log "$ticket: $finding"
    done <<IGNORE
${RALPH_GATE_IGNORE:-}
IGNORE
  else
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
  fi

  RALPH_GATE_VERDICTS="${RALPH_GATE_VERDICTS# }"
  RALPH_GATE_FAILED="${RALPH_GATE_FAILED# }"

  gate__log "$ticket: $RALPH_GATE_VERDICTS"
  gate__report_unguarded "$ticket"
  gate__report_frontier "$ticket"
  gate__report_changed "$ticket" "$RALPH_GATE_TREE"
  rm -rf "$dir"
  return "$rc"
}
