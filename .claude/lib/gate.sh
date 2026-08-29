# shellcheck shell=bash
# The gate, in two phases.
#
# **The objective phase.** Four deterministic checks decide whether an iteration
# delivered: the project's test suite, its type check, the scope-guard, and the
# language gate ([17], the only one of the four a project may switch off). The
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
#   RALPH_GATE_FRONTIER     the sources outside the working tree this session moved
#                           — the ignore rules that decide what every check can see
#                           ([30]) and the git configuration that decides what git
#                           *runs* and what it *hands* the next session ([46]) —
#                           already phrased as scope findings. Filled before the
#                           fan, like the tree, because the branch that reports them
#                           is a subshell
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
#   RALPH_GATE_QUOTA        the in-band posture of the last review lens whose
#                           session the API refused, as `<status> <window>
#                           <reset>`, or empty. Read out of the lens's stream
#                           before this module removes it ([43]); it is a
#                           correction for the pilot's budget watch and may only
#                           ever make the run more cautious
#   RALPH_GATE_QUOTA_ONLY   1 when this gate is red and **every** red branch is a
#                           lens the API refused before it could look. Not a green,
#                           and never a forgiven red: the verdicts still say red,
#                           and what it buys the ticket is a give-back with no
#                           retry charged — the criterion [08] wrote and wired to
#                           two outcomes only ([43])
#   RALPH_GATE_FRONTIER_READ
#                           1 once this gate has put the frontier back and read this
#                           iteration's share of the movement register. The failure
#                           policy asks again on the paths where nobody did, and a
#                           second ask charges a widening twice ([41])

gate__log() {
  printf 'ralph: gate: %s\n' "$*"
}

# Said out loud *and* kept, for the lines that outlive the night ([10]).
#
# Two kinds of sentence go through here and no others: what this gate did **not**
# judge — the ignored zone, the frontier a session moved, what the branches wrote
# after the tree was taken, what the language gate skipped — and the admissions
# that are not zeroes, where a measurement could not be taken at all ([34]). They
# are the ones a human needs *after* a night rather than in a stdout that has
# scrolled, and they are the ones a receipt cannot reconstruct afterwards: asking
# the same questions again would walk the ignored zone a second time and, for the
# frontier, would advance a register that is read once per iteration by design
# ([41]).
#
# `receipt_note` is a no-op when no receipt is open, which is what lets this be
# used unconditionally: the gate has its own tests, and a call site that had to ask
# first would grow the question in six places and lose it in the seventh.
gate__say() {
  gate__log "$@"
  receipt_note "$@"
}

# The third kind, and it is not a zone ([45]): something this gate was going to do
# and could not. A path it failed to put back is not a corner of the repository
# nobody looked at, it is a promise — "the tree is as the lenses found it" — that
# came back short, and a reader acts on it differently. Same no-op discipline as
# above.
gate__gap() {
  gate__log "$@"
  receipt_gap "$@"
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

  # And the language gate's own three, for the same reason ([17]): a threshold
  # that reads as zero, a `LANG_CHECK` misspelt into off, or a `LANG_ARTIFACT`
  # nothing here has words for all produce a branch that passes everything while
  # reporting green. Refused at the door rather than discovered in the morning.
  lang_preflight || rc=1

  return "$rc"
}

# What earlier runs left in `$TMPDIR`, said once at the start of a run and never
# removed here ([36]).
#
# This module makes both of the temporary *directories* the pack uses — the gate's
# own, one per iteration, and the witness holding the pinned ignore rules ([30]) —
# and both are cleaned up on every path an iteration can take. Every path except
# one: a run that dies of violence takes none of them, so a `kill -9` leaves a gate
# directory and a witness behind for good. Naming them is this module's business
# because their names are; counting them at run start is the loop's.
#
# Older than a day, and that is the whole of the concurrency question: the pack
# takes one lock per tree ([22]) and not one per machine, so another run of another
# repository may perfectly well own a fresh `ralph-gate.*` right now. A directory
# nobody has touched in twenty-four hours belongs to no run that is still going.
#
# It says and does not sweep, which is a decision and not an omission. The
# opportunistic `find -mtime +7` the test harness runs on its own templates is the
# obvious shape, and the component entitled to run it is the installer ([19]), the
# only part of the pack that lives outside an iteration. And a warning for whoever
# writes that: this is disk, nothing else. The witness of a killed run recovers no
# state for anyone — the ignore frontier it was pinning is put back on the three
# exits an iteration has ([32]) and on none of the ways a run is killed, so the
# next run pins whatever the dead one left widened. That limit is structural and
# written in docs/frontiere-de-confiance.md; a temporary file cannot carry it.
#
# The list grew with [13] rather than gaining a second line of its own: an
# iteration's worktree and the slot its outcome comes back through are the same
# statement about the same directory, and two sentences saying "a killed run left
# something in $TMPDIR" would be two things to keep in step. What the worktrees
# cost *inside* the repository — a registration in the common git directory that
# every later `git worktree` call carries — is a different fact and is said by
# `concurrency_leftovers`.
#
# One finding per line since [49], because the second one is not a sentence about
# `$TMPDIR` at all: what a killed run leaves in the feature directory is an
# exclusion guard, and it is counted on liveness rather than on age.
gate_leftovers() {
  local rc=1
  if gate__tmp_leftovers; then rc=0; fi
  if gate__stale_guards; then rc=0; fi
  return "$rc"
}

gate__tmp_leftovers() {
  local tmp="${TMPDIR:-/tmp}" n
  n="$(find "$tmp" -maxdepth 1 \
    \( -name 'ralph-gate.*' -o -name 'ralph-ignore.*' \
    -o -name 'ralph-worktree.*' -o -name 'ralph-slot.*' \
    -o -name 'ralph-frontier.*' \) -mtime +0 2>/dev/null |
    wc -l | tr -d ' ')"
  [ -n "$n" ] && [ "$n" -gt 0 ] || return 1
  printf '%s temporary director(ies) from earlier runs are still in %s: a run killed mid-iteration leaves one behind, and nothing here removes them\n' \
    "$n" "$tmp"
  return 0
}

# And what a killed run leaves *inside* the feature directory: an exclusion guard
# nobody owns any more ([49]).
#
# The run lock is released by the trap its own acquisition installs, so it comes
# off on every ordinary death. The ticket-open guard of [47] is released by the
# call that took it and by nothing else, and it is the whole of the mutual
# exclusion on the number space — so a run killed while holding it crossed every
# later run in complete silence, `gate_leftovers` having only ever looked at
# `$TMPDIR`. It is recovered at the next allocation (`state_guard_take` displaces a
# guard whose owner is gone), which is the right behaviour and not a reason for
# nobody to have counted it: a guard nobody counts is also a guard nobody notices
# is *held*, and this pack has a document about what it does not look at.
#
# Liveness rather than the age used above, and the difference is which question
# each one can answer. `$TMPDIR` is shared with runs of other repositories, so
# ownership there is unknowable and a day of silence is the only evidence
# available. This directory belongs to one feature of one tree, which this run
# holds the lock on: a guard whose owner still answers `kill -0` belongs to
# something alive, and one whose owner does not belongs to nobody at all.
gate__stale_guards() {
  local dir guard owner names='' n=0
  [ -n "${FEATURE:-}" ] || return 1
  dir="$(ralph_feature_dir)" || return 1
  [ -d "$dir" ] || return 1
  for guard in "$dir"/*.guard "$dir"/.*.guard; do
    [ -d "$guard" ] || continue
    owner="$(cat "$guard/pid" 2>/dev/null)" || owner=''
    if [ -n "$owner" ] && kill -0 "$owner" 2>/dev/null; then continue; fi
    n=$((n + 1))
    names="$names $(basename "$guard")"
  done
  [ "$n" -gt 0 ] || return 1
  printf '%s exclusion guard(s) left in %s by an earlier run:%s — the owner is gone, nothing here removes them, and the next caller that needs one takes it over without a word\n' \
    "$n" "$dir" "$names"
  return 0
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
# itself carries — the guarded paths, the sealed configuration, the paths the
# language gate is told not to read ([17]) — and a path is not a pattern:
# `zone[1]` is a directory a project may really have, and a guard that reads it
# as a character class guards `zone1` instead.
#
# Public because it has a second module calling it, which is the rule this pack
# keeps rather than a preference: a `__` with two callers is an interface whose
# name lies. It was `gate__under_path` until [17] gave `LANG_EXEMPT_PATHS` the
# same literal reading as `GUARDED_PATHS` — and a private copied into lang.sh
# would have been the second definition of a splitting convention that has
# already cost this pack one silent false green ([33]).
#
# The two readings cannot be mixed, and choosing was the second half of [33]. The
# forcing in gate_tree_snapshot uses `:(literal)` pathspecs for the same reason,
# so a guarded path means the same thing to the half that takes it and to the
# half that decides it was taken. The price is written down rather than hidden: a
# `GUARDED_PATHS` entry written as a glob — `vendor/*` — now guards nothing, and
# says so, because the forcing matches nothing and the zone line then names
# `vendor/` as a path this gate did not judge. Before, it guarded something and
# the zone line stayed quiet about the paths it did not.
gate_under_path() {
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

# Whether git had to print this name quoted — which is to say whether it is a name
# anything in this pack can address at all.
#
# Every list of paths in here comes out of `git diff-tree`, and git C-quotes a name
# it cannot print as itself: the whole name wrapped in double quotes, the offending
# bytes escaped. `core.quotePath=false`, passed by every producer of a path list in
# this pack since [39], takes the *non-ASCII* case out of that set — and that was
# the case that mattered, because `docs/spécification.md` is a name a French
# project really writes. It used to reach every consumer of this list as
# `"docs/sp\303\251cification.md"`, a string `git cat-file`, `git add`, `rm` and
# `git checkout-index` all refuse (probed on 05/08/2026, six ways).
#
# What stays quoted is a name carrying a character git cannot show as itself: a
# newline, a tab, a double quote, a backslash. That residue is a **named limit**
# and the decision is written in docs/frontiere-de-confiance.md rather than left
# implicit: `-z` would make those names addressable and would also make every list
# in this pack NUL-separated, which is the convention [33] settled end to end, in
# nine readers, for a name no project has. Git's own quoting is what makes keeping
# that convention safe — a name carrying a newline arrives as one quoted *line*, so
# it never splits a list in silence. It arrives instead as something no consumer
# can address, which is a thing each of them can refuse out loud.
#
# Public because a second module reads it — the language gate — which is this
# pack's rule for a name rather than a preference, the same one that took
# `gate__under_path` public in [17]. Four readers ask the question and each does
# something different with it: the scope-guard reds on it, the restore refuses to
# claim it put it back, the language gate counts it, and the tracker's own guard
# ([21] via [49]) treats a ticket that moved under such a name as a tracker it
# cannot vouch for — the only one of the four that cannot even tell whether what
# it is looking at is a ticket.
gate_unaddressable() {
  case "$1" in
    '"'*'"') return 0 ;;
  esac
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
#   LEARNINGS.md, learning-records        the lesson index is **inlined** into
#                                         every fresh session's prompt ([14]), so
#                                         it is read at startup as surely as
#                                         `CLAUDE.md` is — by a different route,
#                                         and the criterion above does not ask
#                                         about routes. Sealing it is what stops
#                                         [14] from rebuilding, under another
#                                         name, the channel this list closed: a
#                                         session that could write the index would
#                                         be writing the prompt of every session
#                                         after it. The records go with it because
#                                         the index points at them and because the
#                                         loop is their only writer. Free to seal
#                                         for the same reason as the line below —
#                                         no ticket needs to write them, the retro
#                                         writes them from outside every judged
#                                         tree
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
  printf '%s\n' 'LEARNINGS.md' 'learning-records'
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

  # The tree the *run* was started in, and not `git rev-parse --show-toplevel`.
  # Since [13] this function runs with its working directory inside a throwaway
  # worktree, whose toplevel is not where `RALPH_CONFIG` points — so the prefix
  # test decided the config lived outside the repository and sealed nothing, on
  # every iteration. A control failing open on the shape of a path is what this
  # comment already warned about; the shape simply changed. Resolved with `pwd -P`
  # for the reason above: both sides have to be physical or neither is.
  root="$(cd "$(ralph_project_root)" 2>/dev/null && pwd -P)" || return 0
  [ -n "$root" ] || return 0
  case "$config" in
    "$root"/*) printf '%s\n' "${config#"$root"/}" ;;
  esac
}

# A sealed directory covers what is under it, so `.claude/agents` seals the files
# in it. Matched literally and not as a glob: the last entry of the list is a path
# a run names through `RALPH_CONFIG`, and a seal that read it as a pattern would
# seal a file nobody named. See gate_under_path.
gate_is_sealed() {
  gate_under_path "$1" "$(gate_sealed_paths)"
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
# kind of thing (see gate_frontier): the `.gitignore` files of the working
# tree; `.git/info/exclude` and `core.excludesFile`, in the git directory; and the
# global excludes file, which lives outside the repository altogether.
#
# ── and the other half of the same question ([46]) ───────────────────────────
#
# Everything above is about what a check can **see**. The same configuration files
# decide what git *runs* and what it *hands back*, and none of that was pinned,
# looked at, or said out loud. Measured on 26/08/2026 rather than reasoned about:
#
#   - `core.fsmonitor` is a path to a program, and git runs it on every index
#     refresh. A session that set it — in `<main tree>/.git/config`, or in the
#     operator's `~/.gitconfig`, both writable by a session — got **252
#     executions on a run of two iterations**, with `git` itself as the parent, so
#     inside the *pilot's* process tree: not in a session, not in a worktree, not
#     under a gate. Both tickets came out `resolved`, `run.log` said nothing and no
#     receipt said anything.
#   - a `filter.<n>.smudge` armed by `.git/info/attributes` rewrites what git
#     writes into a working tree. Both files live in the **common** git directory,
#     so a filter installed by one iteration applies to every worktree the run
#     creates afterwards: probed, the second iteration's session was handed a
#     `CONTEXT.md` that had been rewritten while the main tree and the blob still
#     held the original, two greens, two `resolved`, complete silence. Nothing
#     *could* see it — the scope-guard compares two trees and both are filtered the
#     same way, so the diff is empty.
#
# So the same machinery — a pinned value, compared, restored, and red — carries a
# fourth kind, `cfg`. What is on that list is derived from a criterion and not
# from the three keys the probe happened to try ([31]): **anything a session can
# put in a git configuration source that makes git execute a program or transform
# a content**. gate_config_keys is the list and says what it leaves out and why.

# ── two witnesses, because the sources are not all the same shape ────────────
#
# [30] gave every iteration one witness of its own, and [13] then put every
# iteration in a worktree of its own. Those two facts do not compose, and that is
# [41]: the `.gitignore` files of the tree really are per-worktree, but
# `.git/info/exclude` and `core.excludesFile` live in the **common** git directory
# and `~/.config/git/ignore` outside the repository altogether. Three sources
# shared by every iteration in flight, pinned at three different instants.
#
# What that bought, probed on 06/08/2026 at `MAX_PARALLEL=2`: an iteration that
# spawns *while* a sibling's session has the frontier widened pins the widened
# frontier as its own baseline — so it goes blind behind a rule it never wrote,
# and its own restore would then put the widening **back** over the sibling's
# witness. And whichever gate looks first is the one charged, which is the
# misattribution the rest of this section is about.
#
# So the common sources get a witness at the level they actually live at: one per
# **run**, taken before the first session of the night, and every per-iteration pin
# copies its non-tree half from it rather than from disk. Two consequences, both
# wanted: the restore target is a fixed value no session ever gets to move, so two
# restores in flight cannot fight, and a sibling that spawns mid-widening still
# judges through the frontier the *run* was handed.
#
# The loop refuses to start without it, the way it refuses without a pin. The
# fallback below — no witness, read the live sources — exists so `gate_*` stays
# drivable outside a run, and never fires under `loop.sh`.
gate_frontier_common() {
  local dir file
  dir="$(mktemp -d "${TMPDIR:-/tmp}/ralph-frontier.XXXXXX")" || return 1
  : >"$dir/exclude"
  file="$(gate__ignore_exclude_path)"
  if [ -n "$file" ] && [ -f "$file" ]; then
    cp "$file" "$dir/exclude" 2>/dev/null || true
  fi
  : >"$dir/global"
  file="$(gate__ignore_global_path)"
  if [ -n "$file" ] && [ -f "$file" ]; then
    cp "$file" "$dir/global" 2>/dev/null || true
  fi
  # And the file that arms a filter or a diff driver on a path ([46]). In the
  # common git directory like `info/exclude`, in no tree, declarable in no
  # write-surface, and shared by every worktree the run makes.
  : >"$dir/attributes"
  file="$(gate__config_attributes_path)"
  if [ -n "$file" ] && [ -f "$file" ]; then
    cp "$file" "$dir/attributes" 2>/dev/null || true
  fi
  if ! { gate__ignore_shared_manifest; gate__config_manifest; } >"$dir/manifest"; then
    rm -rf "$dir"
    return 1
  fi
  # The register of frontier movements this run has seen, and the only thing that
  # survives a restore. See gate_frontier: a movement erased by the first
  # gate to look would otherwise be invisible to every iteration behind it.
  : >"$dir/ledger"
  printf '%s\n' "$dir"
}

# One rule source into a witness: from the run's witness when there is one, from
# the live file when there is not.
gate__frontier_common_copy() {
  local slot="$1" dest="$2" live="$3" common="${RALPH_FRONTIER_COMMON:-}"
  if [ -n "$common" ] && [ -f "$common/$slot" ]; then
    cp "$common/$slot" "$dest" 2>/dev/null || true
    return 0
  fi
  if [ -n "$live" ] && [ -f "$live" ]; then
    cp "$live" "$dest" 2>/dev/null || true
  fi
  return 0
}

# What one iteration's pin records: the tree rules as they stand right now, and
# the common sources as the *run* was handed them.
#
# The tree half is asked for on its own rather than filtered out of the whole
# manifest, which is a cost and not a style: since [46] the shared half asks git
# for every configuration key it watches, and computing that here only to throw it
# away would pay for it on every iteration for nothing.
gate__frontier_pin_manifest() {
  local common="${RALPH_FRONTIER_COMMON:-}"
  if [ -n "$common" ] && [ -f "$common/manifest" ]; then
    gate__ignore_tree_manifest || true
    cat "$common/manifest"
    return 0
  fi
  gate__frontier_manifest
}

# How many movements the run's register held when this pin was taken. What an
# iteration is charged for is what appears in it after that mark.
gate__frontier_ledger_len() {
  local common="${RALPH_FRONTIER_COMMON:-}"
  if [ -n "$common" ] && [ -f "$common/ledger" ]; then
    awk 'END { print NR + 0 }' "$common/ledger"
    return 0
  fi
  printf '0\n'
}

# Where this iteration starts reading the register: the length its pin recorded at
# spawn. One definition and two readers — the share below, and the fail-closed
# check that a register never got *shorter* than it — because the same number
# answers both, and two copies of it would drift the day one of them is corrected.
gate__frontier_mark() {
  local seen
  seen="$(cat "${RALPH_FRONTIER_PIN:-}/ledger-seen" 2>/dev/null || printf '0')"
  case "$seen" in '' | *[!0-9]*) seen=0 ;; esac
  printf '%s\n' "$seen"
}

# The rules as they stood, kept as a witness repository — a git directory of its
# own carrying copies of every rule source and no project files at all. Printed as
# a path; the loop holds it in RALPH_FRONTIER_PIN for the length of one iteration
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
gate_frontier_pin() {
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
  #
  # Both of these come from the run's witness when there is one ([41]): they are
  # sources every iteration in flight shares, so a copy taken at *this* instant
  # would record whatever a sibling's session had written a second earlier.
  mkdir -p "$rules/.git/info" || true
  : >"$rules/.git/info/exclude"
  gate__frontier_common_copy exclude "$rules/.git/info/exclude" \
    "$(gate__ignore_exclude_path)"
  : >"$pin/global"
  gate__frontier_common_copy global "$pin/global" "$(gate__ignore_global_path)"
  # And the attributes file the restore puts back ([46]). Beside the pin rather
  # than inside the witness repository: `git check-ignore` is what that repository
  # exists to answer, and an attributes file would change nothing it says.
  : >"$pin/attributes"
  gate__frontier_common_copy attributes "$pin/attributes" \
    "$(gate__config_attributes_path)"
  # Set locally, so the machine's own `core.excludesFile` — from the user's global
  # config or from the default `~/.config/git/ignore` — cannot leak into the
  # witness's answers. What the project's rules said about it is pinned above.
  git -C "$rules" config core.excludesFile "$pin/global" >/dev/null 2>&1 || true

  if ! gate__frontier_pin_manifest >"$pin/manifest"; then
    rm -rf "$pin"
    return 1
  fi
  # Where this iteration starts reading the run's register of movements. Taken
  # here, in the pilot and before the iteration is forked, so that "recorded after
  # my mark" is "recorded while I was in flight".
  gate__frontier_ledger_len >"$pin/ledger-seen"
  printf '%s\n' "$pin"
}

# Every `.gitignore` of the working tree, tracked or not. A rule file inside an
# ignored directory is deliberately absent: git never reads one either, because it
# never walks into the directory that holds it.
gate__ignore_tree_rules() {
  git ls-files --cached --others --exclude-standard -- '*.gitignore' 2>/dev/null || true
}

# One file under the git directory's `info/`, by name — the **common** git
# directory and not this working tree's private one, which is the same distinction
# `ralph_tree_lock_path` makes in the other direction ([22]). A linked worktree
# answers `--git-dir` with `.git/worktrees/<name>/`, and git reads neither ignore
# rules nor attributes from there: `info/` is one of the paths every worktree
# shares, so the files that decide what a check can see — and, since [46], what git
# transforms on its way into a worktree — are the common ones.
#
# Probed on 06/08/2026, because reading it wrong is silent in exactly the way this
# section exists to refuse: a rule written into the common `info/exclude` hides a
# file inside a linked worktree, while a pin that had looked in the private
# directory would have recorded no local excludes at all — and the snapshot would
# then go on being taken through whatever a session had written there ([13]).
#
# Two callers rather than one since [46], which is why it takes a name: the same
# reading mistake would be silent in the same way for `info/attributes`, and two
# copies of this would be two chances to make it.
gate__frontier_info_path() {
  local gitdir
  gitdir="$(git rev-parse --git-common-dir 2>/dev/null)" || gitdir=""
  [ -n "$gitdir" ] || return 0
  printf '%s/info/%s\n' "$gitdir" "$1"
}

gate__ignore_exclude_path() {
  gate__frontier_info_path exclude
}

gate__config_attributes_path() {
  gate__frontier_info_path attributes
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

# What the frontier is right now, one line per source: kind, name, digest. The four
# kinds are the four answers to "may a session write this, what does it decide, and
# can the run put it back" — gate_frontier is where that is spelled out.
#
# A missing file digests to `-`, which is what makes an appearing or vanishing
# rule file a movement like any other.
#
# In three producers rather than one, and the split is the one the witnesses make:
# the tree half is per-worktree and pinned per iteration, the other two are shared
# by every iteration in flight and pinned per run ([41], [46]). A caller that wants
# one of them must not pay for the others — the config half asks git for a list of
# keys, and `gate__frontier_pin_manifest` would otherwise buy it once per iteration
# to throw it away.
gate__frontier_manifest() {
  gate__ignore_tree_manifest
  gate__ignore_shared_manifest
  gate__config_manifest
  return 0
}

gate__ignore_tree_manifest() {
  local file
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    printf 'tree\t%s\t%s\n' "$file" "$(gate__digest "$file")"
  done <<RULES
$(gate__ignore_tree_rules)
RULES
  return 0
}

gate__ignore_shared_manifest() {
  local file
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

# ── the configuration that decides what git runs ([46]) ──────────────────────
#
# One extended regular expression per line, matched against the **effective**
# configuration — `git config --list` answers with system, global, local, worktree
# and every `include` already resolved, which is what the criterion is about: not
# "what is in this file" but "what will git do".
#
# The criterion, and the list is derived from it rather than from the three keys a
# probe happened to try ([31]): **what a session can put in a git configuration
# source that makes git execute a program, or transform a content on its way into
# or out of the object database.** Section and key come back lowercased and the
# subsection verbatim, which is why the patterns are lowercase and the middle is
# `.*`.
#
# What is deliberately **not** here, each with its reason, because a list with a
# silent omission is the defect this ticket is about:
#
#   `alias.*`             a `!command` alias is a program, and git will not run one
#                         for any name it has a built-in for. Every git invocation
#                         in this pack is a built-in subcommand, so this cannot
#                         fire — a property of *git*, which is what makes it a
#                         bound and not a bet on this pack's current call sites.
#   `core.excludesFile`   watched one mechanism up, by [30], and restored there.
#                         Two owners restoring one key would put it back twice and
#                         charge for it twice.
#   `core.worktree`,      they decide what git *addresses* — which tree, which
#   `core.bare`           objects — and not what it runs or transforms. A different
#                         question, with no owner, and said here rather than left
#                         to look like an oversight.
#
# And two that are here even though the probe of 26/08/2026 measured them *not*
# firing, which is the same rule read the other way: `core.hooksPath` does nothing
# today because `failures_make_durable` commits with plumbing on purpose, and
# `diff.external` does nothing because every diff this pack takes is
# `--name-only` or `--name-status`. Both of those are facts about this pack's
# current call sites and not about git, so leaving them out would make the list
# derived from the code instead of from the criterion — and the ticket that
# switched one `git commit-tree` for a `git commit` would reopen the hole with
# nothing to notice it.
gate_config_keys() {
  printf '%s\n' \
    'core\.fsmonitor' \
    'core\.hookspath' \
    'core\.sshcommand' \
    'core\.gitproxy' \
    'core\.alternaterefscommand' \
    'core\.askpass' \
    'core\.editor' \
    'core\.pager' \
    'sequence\.editor' \
    'pager\..*' \
    'credential\.helper' \
    'credential\..*\.helper' \
    'diff\.external' \
    'diff\..*\.command' \
    'diff\..*\.textconv' \
    'merge\..*\.driver' \
    'filter\..*\.clean' \
    'filter\..*\.smudge' \
    'filter\..*\.process' \
    'gpg\.program' \
    'gpg\..*\.program' \
    'commit\.gpgsign' \
    'tag\.gpgsign' \
    'trailer\..*\.command' \
    'trailer\..*\.cmd' \
    'uploadpack\.packobjectshook' \
    'remote\..*\.uploadpack' \
    'remote\..*\.receivepack' \
    'remote\..*\.proxy' \
    'difftool\..*\.cmd' \
    'mergetool\..*\.cmd' \
    'guitool\..*\.cmd' \
    'browser\..*\.cmd' \
    'web\.browser' \
    'help\.browser' \
    'sendemail\.smtpserver' \
    'sendemail\..*\.smtpserver' \
    'init\.templatedir' \
    'protocol\..*\.allow' \
    'ssh\.variant' \
    'core\.autocrlf' \
    'core\.eol' \
    'core\.safecrlf' \
    'core\.symlinks' \
    'core\.attributesfile' \
    'core\.quotepath' \
    'core\.precomposeunicode' \
    'core\.protectntfs' \
    'core\.protecthfs' \
    'extensions\.worktreeconfig' \
    'include\.path' \
    'includeif\..*\.path'
  return 0
}

# The effective keys that match, deduplicated: a key set in two sources — or a
# multi-valued one — is listed once per value by git and is one source here.
#
# The match is caught in a variable rather than piped straight through, and that is
# the pack running under `set -o pipefail` and not a preference: the ordinary case
# here is a project where **none** of these keys is set, so the `grep` exits 1, so
# the pipeline does, and a function that let that status escape would be a
# fail-open dressed as an empty answer — exactly the shape `gate__frontier_share`
# has a paragraph about one screen down.
gate__config_names() {
  local re names
  re="$(gate_config_keys |
    awk 'NR == 1 { printf "%s", $0; next } { printf "|%s", $0 } END { printf "\n" }')"
  [ -n "$re" ] || return 0
  names="$({ git config --list --name-only 2>/dev/null || true; } |
    LC_ALL=C grep -E "^($re)\$" || true)"
  [ -n "$names" ] || return 0
  printf '%s\n' "$names" | LC_ALL=C sort -u
  return 0
}

# What git would do with that key, as one number. `--get-all` and not `--get`: a
# multi-valued key is a list, and a session that appends a second `filter.x.smudge`
# has moved the frontier whatever the first one says.
gate__config_digest() {
  local value
  value="$({ git config --get-all "$1" 2>/dev/null || true; })"
  printf '%s' "$value" | cksum | awk '{ print $1 "." $2 }'
}

# The name a key gets in the manifest when its own name cannot travel in one.
#
# A subsection may hold any byte but a newline, a tab included, and the manifest is
# tab-separated — so `filter.a<TAB>b.smudge` would be read as a name of `filter.a`
# and restored on the wrong key. They are folded into one line instead, digested
# name and value together so that any change to any of them still moves it, and
# `gate__config_restore` re-derives the real names rather than reading them back
# out of a field that cannot hold them ([39]'s posture on a path git prints quoted:
# name it, and never pretend to have addressed it).
GATE_CONFIG_ODD='a git configuration key whose name carries a control character'

gate__config_manifest() {
  local tab cr name odd=''
  tab="$(printf '\t')"
  cr="$(printf '\r')"
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    case "$name" in
      *"$tab"* | *"$cr"*)
        odd="$odd$name=$({ git config --get-all "$name" 2>/dev/null || true; })
"
        continue
        ;;
    esac
    printf 'cfg\t%s\t%s\n' "$name" "$(gate__config_digest "$name")"
  done <<NAMES
$(gate__config_names)
NAMES
  [ -z "$odd" ] ||
    printf 'cfg\t%s\t%s\n' "$GATE_CONFIG_ODD" \
      "$(printf '%s' "$odd" | cksum | awk '{ print $1 "." $2 }')"
  # And the file that arms those filters and drivers on a path. In the same kind
  # because it answers the same question — it decides what git hands a worktree —
  # and it is put back the same way, from the run's witness.
  printf 'cfg\t%s\t%s\n' '.git/info/attributes' \
    "$(gate__digest "$(gate__config_attributes_path)")"
  return 0
}

# One configuration source back where the pin found it, and whether it is really
# back — the same attempt-then-verify `gate__frontier_restore` makes for the ignore
# sources, and for a sharper version of the same reason: `git config --unset-all`
# writes *this repository's* config, so a value a session put in the operator's
# `~/.gitconfig` survives it untouched and a restore that only checked its own exit
# status would be a lie on exactly the door [15] found open.
#
# Nothing is written outside the repository, here as everywhere in this pack. What
# that costs is stated in the finding rather than hidden: a key that still answers
# with the session's value after the unset is named as one this run could not put
# back, and the iteration stays red for as long as it does.
gate__config_restore() {
  local name="$1" pinned="$2" tab cr key target
  case "$name" in
    '.git/info/attributes')
      target="$(gate__config_attributes_path)"
      [ -n "$target" ] || return 1
      if [ "$pinned" = '-' ]; then
        rm -f "$target" 2>/dev/null || true
      else
        mkdir -p "$(dirname "$target")" 2>/dev/null || true
        cp "${RALPH_FRONTIER_PIN}/attributes" "$target" 2>/dev/null || true
      fi
      [ "$(gate__digest "$(gate__config_attributes_path)")" = "$pinned" ]
      return
      ;;
    "$GATE_CONFIG_ODD")
      # The run was handed keys of this shape already: nothing is done and nothing
      # is claimed. Unsetting them would take away the operator's own configuration
      # to answer a question about the session's, and this line cannot tell the two
      # apart — the names it would need are the ones that do not fit in the field.
      [ -z "$pinned" ] || return 1
      # None at the pin, so every one of them appeared under this run. Asked for
      # again rather than read back out of a field that cannot hold them.
      tab="$(printf '\t')"
      cr="$(printf '\r')"
      while IFS= read -r key; do
        [ -n "$key" ] || continue
        case "$key" in
          *"$tab"* | *"$cr"*)
            git config --unset-all "$key" >/dev/null 2>&1 || true
            ;;
        esac
      done <<NAMES
$(gate__config_names)
NAMES
      [ -z "$(gate__frontier_current "$GATE_CONFIG_ODD")" ]
      return
      ;;
  esac
  git config --unset-all "$name" >/dev/null 2>&1 || true
  [ "$(gate__frontier_current "$name")" = "$pinned" ]
}

# A pin that was set and cannot be read. Refused rather than ignored: the point of
# the pin is that what the checks can see does not depend on what the session left
# behind, so a missing one is a control that cannot see.
#
# The run's witness of the shared sources and its register of movements are held to
# the same standard ([41]), and they have to be: they live in the same `$TMPDIR`
# under the same kind of unguessable name, so a session that can reach one can
# reach the other — and the fallbacks around them are "read the live sources",
# which is a quiet return to the behaviour this ticket removed. Destroying the pin
# stops the night; destroying these would have cost nothing.
gate__frontier_pin_broken() {
  local pin="${RALPH_FRONTIER_PIN:-}" common="${RALPH_FRONTIER_COMMON:-}" seen total
  [ -n "$pin" ] || return 1
  [ -f "$pin/manifest" ] && [ -d "$pin/rules/.git" ] || return 0
  [ -n "$common" ] || return 1
  [ -f "$common/manifest" ] && [ -f "$common/exclude" ] &&
    [ -f "$common/attributes" ] && [ -f "$common/ledger" ] || return 0

  # A register that got shorter is one somebody rewrote: it is append-only by
  # construction, so a length below this iteration's own mark is not a state this
  # pack can produce. What it does *not* catch is written down rather than implied
  # — a truncation back to exactly an iteration's mark erases a movement that
  # iteration had not read yet, and nothing here can tell that from a night in
  # which nothing moved.
  seen="$(gate__frontier_mark)"
  total="$(awk 'END { print NR + 0 }' "$common/ledger")"
  [ "$total" -lt "$seen" ] && return 0
  return 1
}

# The rule sources that are not what the pin recorded — appeared, vanished or
# changed — as `kind<TAB>name`. Non-zero when the frontier has not moved, so a
# caller can ask and then do nothing, which is the normal case and the cheap one.
#
# The symmetric difference of two manifests: a line present in both appears twice
# and `uniq -u` drops it. Names are unique inside one manifest, so nothing else
# can pair up.
gate_frontier_moved() {
  local pin="${RALPH_FRONTIER_PIN:-}" moved
  [ -n "$pin" ] || return 1
  [ -f "$pin/manifest" ] || return 1
  moved="$( { gate__frontier_manifest; cat "$pin/manifest"; } |
    LC_ALL=C sort | uniq -u | cut -f1,2 | LC_ALL=C sort -u)"
  [ -n "$moved" ] || return 1
  printf '%s\n' "$moved"
}

gate__frontier_pinned() {
  awk -F'\t' -v name="$1" '$2 == name { print $3 }' \
    "${RALPH_FRONTIER_PIN:-/dev/null}/manifest" 2>/dev/null || true
}

gate__frontier_current() {
  { gate__frontier_manifest || true; } |
    awk -F'\t' -v name="$1" '$2 == name { print $3 }'
}

# Put one source back where the pin found it, and answer whether it is really
# back. Attempt and then verify, because the attempt can succeed on the wrong
# level: `git config --unset` writes the repository's config, so a value a session
# put in the *user's* config would survive it and the restore would be a lie.
#
# Dispatched on the **kind** and not on the name since [46]: a `cfg` source is a
# configuration key whose name a session chooses, so a `case` on the name alone
# would be a case a session gets to steer.
gate__frontier_restore() {
  local kind="$1" name="$2" pinned target
  pinned="$(gate__frontier_pinned "$name")"
  if [ "$kind" = cfg ]; then
    gate__config_restore "$name" "$pinned"
    return
  fi
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
        cp "${RALPH_FRONTIER_PIN}/rules/.git/info/exclude" "$target" 2>/dev/null || true
      fi
      ;;
    *) return 1 ;;
  esac
  [ "$(gate__frontier_current "$name")" = "$pinned" ]
}

# The frontier this run has seen move while this iteration was in flight, put back
# where the run can reach it, and phrased as findings for the scope-guard to
# carry. Non-zero when it found something, so `gate_run` can fill a variable and
# forget about it.
#
# **Who is charged, and why it cannot be who wrote it** ([41]). This function used
# to answer "has the frontier moved since *my* witness", which was the same
# question as "who moved it" for exactly as long as one iteration lived at a time.
# With two in flight it is a draw: the first gate to look finds the widening,
# reports it, is rolled back and billed a retry, and puts the file back — so the
# iteration whose session actually wrote it arrives at its own gate to find
# nothing moved, and goes green, commits, resolves. Probed at `MAX_PARALLEL=2`;
# the same pair at `MAX_PARALLEL=1` bills the author three times to escalation, so
# it is the concurrency and not the scenario that moves the bill.
#
# There is no fix that attributes, and that is a property of the sources rather
# than a gap in this code: `.git/info/exclude` is one file in the git directory
# every worktree shares, so nothing observable says which of them wrote it. Of the
# two honest exits, this is the one taken: **every iteration in flight when the
# frontier moved is charged**. The movement goes into a register the restore does
# not erase, and each iteration reads what was recorded after its own spawn. What
# that does not hold is written down and said out loud in the findings: a sibling
# that wrote nothing pays a retry, and at its last attempt an escalation, for a
# file its session never opened.
#
# The exit not taken — serializing iterations as soon as a frontier moves — is
# refused on its cost: a movement is only ever *detected* at a gate, so by then
# both sessions have already run, and what serializing buys is the next iteration
# rather than this one. It would also hand every session a one-line way to take
# the run's concurrency away for the rest of the night.
#
# Four kinds, and the difference is the whole of the design:
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
#   cfg   a git configuration key that makes git run a program or transform a
#         content, and `.git/info/attributes`, which arms those on a path ([46]).
#         Not about seeing at all: `core.fsmonitor` is a command git executes on
#         every index refresh — 252 of them on a probed run of two iterations, in
#         the *pilot's* process tree — and a `filter.<n>.smudge` rewrites what git
#         writes into every worktree the run makes afterwards. Red on the same
#         grounds as `dir` and put back the same way, with one difference that is
#         stated in the finding rather than assumed: the restore is an `unset` in
#         **this repository's** config, so a value that came from the operator's
#         `~/.gitconfig`, from the machine's, or from a key a session *removed* is
#         named as one this run could not put back — and the iteration, and every
#         iteration of this run after it, stays red over it. Fail-closed and loud,
#         which is the same residue `host` has one line up.
#
# In two passes, and that is the lesson of [29] rather than a shape: a finding has
# to be net of what the run *did* put back. `core.excludesFile` names the file the
# rules come from, so moving it moves two sources at once — the key and the file it
# now points at — and reporting both from one look at the manifest announced a
# path outside the repository as unrecoverable a line after restoring the key that
# had brought it into play. Probed on 03/08/2026: the second finding named a file
# no session had touched.
gate_frontier() {
  local mine share
  [ -n "${RALPH_FRONTIER_PIN:-}" ] || return 0
  mine="$(gate_frontier_put_back)"
  share="$(gate__frontier_share "$mine")" || true
  [ -n "$share" ] || return 0
  printf '%s\n' "$share"
  return 1
}

# Detect, put back, record — and stop there, without reading this iteration's
# share of the register.
#
# Public because it has a second caller, and the second caller is the point
# ([46]). The three sites [32] wired are all *after* the tracker guard, and the
# tracker guard reads and writes files through whatever git has been configured to
# do to them: `failures_tracker_tree` stages `issues/` — so a `clean` filter
# rewrites every ticket on the way into the tree it compares — and its
# `checkout-index` writes them back out through the matching `smudge`. A session
# that installed a filter and left could have the guard rewrite the whole tracker
# on disk, durably, before anything got as far as noticing. So the loop puts the
# frontier back the moment its session returns, and the gate's own call then finds
# nothing moved and reads the movement out of the register instead — which is what
# the register is for.
#
# Under a guard in the common git directory, for the reason the fold takes one
# ([13]): every source but `tree` is shared by every worktree, so two iterations
# detecting and restoring at once would each write over the other's attempt and
# each record a movement for one widening. Under it, the first one through puts
# the file back and the second finds nothing moved — which is what makes "the
# restore happens once" a fact rather than an intention.
#
# A guard that cannot be taken is not a reason to skip the restore: the target is
# a fixed value from the run's witness, so the worst an unguarded race costs is
# the same movement recorded twice, and skipping would cost the night. Released
# only if it was taken — `state_guard_release` matches on `$$`, which a subshell
# of the pilot shares with its siblings, so releasing a guard we never held would
# take it away from the iteration that does.
gate_frontier_put_back() {
  local mine took=0
  [ -n "${RALPH_FRONTIER_PIN:-}" ] || return 0
  if concurrency_frontier_take; then took=1; fi
  mine="$(gate__frontier_detect)" || true
  gate__frontier_record "$mine" || true
  if [ "$took" = 1 ]; then concurrency_frontier_release || true; fi
  [ -z "$mine" ] || printf '%s\n' "$mine"
  return 0
}

# What moved since this iteration's witness, put back, and phrased. The detection
# proper: everything above it is about who gets told.
gate__frontier_detect() {
  local kind name rc=0

  while IFS="$(printf '\t')" read -r kind name; do
    [ "$kind" = dir ] && [ -n "$name" ] || continue
    if gate__frontier_restore "$kind" "$name"; then
      printf 'moved the ignore frontier in %s, which decides what every check here can see — no write-surface may cover it (put back)\n' "$name"
    else
      printf 'moved the ignore frontier in %s, which decides what every check here can see — and this run could not put it back\n' "$name"
    fi
    rc=1
  done <<INSIDE
$( { gate_frontier_moved || true; } )
INSIDE

  while IFS="$(printf '\t')" read -r kind name; do
    [ "$kind" = host ] && [ -n "$name" ] || continue
    printf 'moved the ignore frontier in %s, outside the repository — no write-surface may cover it, and nothing here can put it back\n' "$name"
    rc=1
  done <<OUTSIDE
$( { gate_frontier_moved || true; } )
OUTSIDE

  # And the half that is not about seeing at all ([46]): what git *runs*, and what
  # it transforms on the way into a worktree. Said in its own words rather than
  # under the sentence above, because a human who reads "the ignore frontier" about
  # `core.fsmonitor` has been told the wrong thing about what just happened.
  while IFS="$(printf '\t')" read -r kind name; do
    [ "$kind" = cfg ] && [ -n "$name" ] || continue
    if gate__frontier_restore "$kind" "$name"; then
      printf 'moved %s, which decides what git executes and what it hands the next session — no write-surface may cover it (put back)\n' "$name"
    else
      printf 'moved %s, which decides what git executes and what it hands the next session — and this run could not put it back: what answers for it now is not written in this repository, and nothing here writes outside it\n' "$name"
    fi
    rc=1
  done <<EXEC
$( { gate_frontier_moved || true; } )
EXEC
  return "$rc"
}

# One movement into the run's register, tagged with the witness of the iteration
# that saw it. The tag is the pin's path — a name in `$TMPDIR` no session is told,
# the same secret the pin itself is ([40]) — and it is what lets the reader tell
# "I found this" from "a sibling found this while I was in flight".
#
# Appended and never rewritten: the register is the one trace of a widening that
# outlives the restore, so a writer that could shorten it would hand a session the
# eraser this whole section exists to take away.
gate__frontier_record() {
  local findings="$1" common="${RALPH_FRONTIER_COMMON:-}" line
  local tag="${RALPH_FRONTIER_PIN:-}" tab nl seen
  [ -n "$common" ] && [ -f "$common/ledger" ] || return 0
  [ -n "$findings" ] || return 0

  # Once per movement per iteration, and it is the register that says so rather
  # than a convention about call sites ([46] on [41]). [41] wrote "one caller per
  # iteration, whichever path it takes", and `failures_handle` keeps a flag to
  # honour it — because a movement **no restore can undo** is re-detected by every
  # look, so a second look recorded it a second time and billed every sibling in
  # flight for it twice. That invariant broke the moment the loop started putting
  # the frontier back before the tracker guard: two calls, one iteration.
  #
  # So the rule moves into the thing it is about. A line this pin has already
  # recorded and **not yet read** is not appended again. Scoped to the unread part
  # on purpose: after `gate_run` has read its share the mark has moved past it, so
  # the same sentence recorded later is a genuinely new event — which is exactly
  # the re-slice's planning session moving the same source a second time ([32]),
  # and dropping that one would under-report a movement nothing else names.
  tab="$(printf '\t')"
  nl='
'
  seen="$nl$(tail -n "+$(($(gate__frontier_mark) + 1))" "$common/ledger" 2>/dev/null ||
    true)$nl"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$seen" in
      *"$nl$tag$tab$line$nl"*) continue ;;
    esac
    printf '%s\t%s\n' "$tag" "$line" >>"$common/ledger"
    seen="$seen$tag$tab$line$nl"
  done <<RECORD
$findings
RECORD
  return 0
}

# This iteration's share of the register: every movement recorded since its pin
# was taken, whoever saw it. The mark is advanced as it reads, because one
# iteration can ask twice — `gate_run` before the fan, and `failures_reslice`
# after the planning session it spawns ([32]) — and the second ask is about what
# moved since the first, not about the whole night.
#
# With no register — `gate_*` driven outside a run — an iteration is charged for
# what it saw itself, which is what this did before [41].
gate__frontier_share() {
  local mine="$1" pin="${RALPH_FRONTIER_PIN:-}" common="${RALPH_FRONTIER_COMMON:-}"
  local ledger seen total tag finding foreign=0

  ledger="$common/ledger"
  if [ -z "$common" ] || [ ! -f "$ledger" ]; then
    # Spelled as an `if` rather than an `&&`, because this one is not protected by
    # its caller the way the rest of this file is: an `&&` whose left half is false
    # returns non-zero, and a caller that ever stops wrapping this in `|| true`
    # would take the run down here on the ordinary case of nothing to report.
    if [ -n "$mine" ]; then printf '%s\n' "$mine"; fi
    return 0
  fi

  seen="$(gate__frontier_mark)"
  total="$(awk 'END { print NR + 0 }' "$ledger")"
  [ "$total" -gt "$seen" ] || return 0
  printf '%s\n' "$total" >"$pin/ledger-seen" 2>/dev/null || true

  while IFS="$(printf '\t')" read -r tag finding; do
    [ -n "$finding" ] || continue
    printf '%s\n' "$finding"
    [ "$tag" = "$pin" ] || foreign=1
  done <<LEDGER
$(tail -n "+$((seen + 1))" "$ledger" 2>/dev/null || true)
LEDGER

  # And the line that says what nobody can be charged for. Printed only when a
  # movement this iteration did not see itself lands in its share — so it never
  # appears at `MAX_PARALLEL=1`, where the iteration that looks is the only one
  # that could have written. It is a finding like the others and rides on the
  # scope-guard's output: a bill nobody can contest has to be readable by the
  # person who gets it.
  [ "$foreign" = 0 ] || printf '%s\n' \
    'the ignore frontier above moved while more than one iteration was in flight — those sources are shared by every worktree, so nothing here can tell which session wrote them and every iteration in flight is charged'
  return 0
}

# The `.gitignore` files of the working tree this session moved, on one line, and
# non-zero when it moved none.
#
# Public because it has a second caller, and the second caller is the point of
# [32]: the sentence written around this list is not the same one on a path where
# a gate judged and on a path where nothing did. Here the new rules apply from the
# next iteration; there the rollback takes them away with the rest of what the
# session wrote. One lister, two claims, each owned by the site that can vouch for
# it — rather than one message with a clause nobody checks.
gate_moved_tree_rules() {
  local moved
  moved="$( { gate_frontier_moved || true; } |
    awk -F'\t' '$1 == "tree" { print $2 }' | tr '\n' ' ' | sed 's/ *$//')"
  [ -n "$moved" ] || return 1
  printf '%s\n' "$moved"
}

# The ignored paths the pinned rules did *not* hide: what a rule written during
# this iteration took out of sight. Forced into the snapshot, which is what makes
# them judged like anything else.
#
# Empty and cheap when the frontier has not moved, which is every ordinary
# iteration: the manifest costs a `git ls-files` and a handful of digests, where
# walking the ignored zone costs the whole working tree.
gate_newly_hidden() {
  local pin="${RALPH_FRONTIER_PIN:-}" listing hidden path fence
  [ -n "$pin" ] || return 0
  if gate__frontier_pin_broken; then return 1; fi
  gate_frontier_moved >/dev/null || return 0

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
  if gate_under_path "${file%/}" "$guarded"; then return 0; fi
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
  git -c core.quotePath=false diff-tree -r --name-only "$judged" "$now" 2>/dev/null |
    gate__drop_bookkeeping
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
    # names what was not forced reads these paths literally (gate_under_path),
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
#
# `core.quotePath=false` on this producer and on every other one in the pack
# ([39]): git escapes any byte outside pure ASCII by default, so a name a French
# project really writes came back as a string none of the four consumers of this
# list could address — see gate_unaddressable for what that cost and for what is
# deliberately left quoted.
gate_changed_files() {
  local base="$1" now="${2:-}"
  [ -n "$now" ] || now="$(gate_tree_snapshot)" || now=""
  [ -n "$base" ] && [ -n "$now" ] || return 1
  git -c core.quotePath=false diff-tree -r --name-only "$base" "$now" 2>/dev/null |
    gate__drop_bookkeeping
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
# Every admission in here goes to **stderr**, and that is not a detail — it is the
# same trap `gate_tree_snapshot` names one screen up ([30], found again here by
# [39]). The list of paths this put back *is* the return value, taken by both
# callers through a command substitution, so a `could not restore` printed on
# stdout does not merely scroll past: it lands in the list as though it were a path
# that had been put back, gets counted in `rolled back N path(s)`, is handed to the
# unstaging as a pathspec, and nets itself out of the "could not undo" line. A
# failure reported into the channel that reports successes is a failure reported as
# a success.
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
    # A name nothing here can address ([39]). Said rather than acted on, and that
    # is the whole of the entry: `rm -f` on the quoted string removes nothing and
    # reports success, `checkout-index` answers `is not in the cache`, and the
    # line at the bottom of this loop then printed the path as one this restore
    # put back. An intention rendered for a result is exactly what [30] paid for
    # on `core.excludesFile`, one mechanism over.
    if gate_unaddressable "$path"; then
      gate__gap "could not put back $path — git prints this name quoted and nothing here can address it" >&2
      continue
    fi
    case "$status" in
      A)
        rm -f "$path"
        # Stops at the first directory that is not empty, so a directory the
        # session did not create survives.
        rmdir -p "$(dirname "$path")" 2>/dev/null || true
        # Checked rather than assumed, for the same reason as the branch below,
        # which has a status to look at: `rm -f` reports success for a path it did
        # not remove — a permission on the directory, a name that is not the name
        # git meant — and this loop's business is to print what it really put back.
        if [ -e "$path" ] || [ -L "$path" ]; then
          gate__gap "could not remove $path" >&2
          continue
        fi
        ;;
      *)
        # No `:(literal)` here, unlike everywhere else a path is handed to git:
        # `checkout-index` takes file names and not pathspecs, and answers
        # `:(literal)docs/x.md is not in the cache` to the magic (probed).
        if ! GIT_INDEX_FILE="$idx" git checkout-index -f -- "$path" 2>/dev/null; then
          gate__gap "could not restore $path" >&2
          continue
        fi
        ;;
    esac
    printf '%s\n' "$path"
  done <<RESTORE
$(git -c core.quotePath=false diff-tree -r --name-status "$base" "$now" 2>/dev/null)
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
#
# The ids are read one per line for the reason the surface is ([33], then [37] for
# this namespace): `for id in $(tracker_ids)` cut a ticket named `99-my ticket`
# into two ids that resolve to nothing, so nobody owned its declared surface and
# an overflow into it came back classified as a stray write — retryable, when the
# whole point of this function is to say it is not (probed, s2c).
gate__surface_owner() {
  local file="$1" self="$2" id
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    [ "$id" != "$self" ] || continue
    if gate_in_surface "$file" "$(gate_write_surface "$id")"; then
      printf '%s\n' "$id"
      return 0
    fi
  done <<IDS
$(tracker_ids)
IDS
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
  if [ -n "${RALPH_GATE_FRONTIER:-}" ]; then
    printf '%s\n' "$RALPH_GATE_FRONTIER"
    class=internal
    rc=1
  fi

  surface="$(gate_write_surface "$ticket")"

  while IFS= read -r file; do
    [ -n "$file" ] || continue
    # Asked before anything compares this string to a list ([39]). A quoted name
    # matches no pattern a human wrote and no path this pack carries, so every
    # answer below would be an answer about a different string — and the two the
    # ticket could get are both wrong in the same direction: a declared surface of
    # `*` matches it like anything else, and the durable commit then drops the file
    # in silence because `git add` refuses the same string this loop just approved.
    # Red whatever the surface says, and retryable: what a fresh session has to do
    # about it is rename the file, which is work a session can do.
    if gate_unaddressable "$file"; then
      rc=1
      if [ -z "$class" ]; then class=internal; fi
      printf 'wrote %s, a name this gate cannot address — git prints it quoted because it carries a character it cannot show as itself, and nothing here can commit it, roll it back or read it. No write-surface may cover it: rename the file\n' "$file"
      continue
    fi
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
#
# Two checks now stand between the sleep and the signal, and neither is decoration
# ([36]). A `kill -9` on the run left this in flight: half an hour later a process
# nobody owned wrote its marker and walked a process tree, on numbers the system
# had been free to hand out since — probed at eight seconds, and `proc_kill_tree`
# descends, so it is a signal to a descendance and not to a process.
#
#   - the countdown gives up the moment the shell that armed it is gone, which is
#     the whole of "a dead run has no deadline firing in its name" — see
#     proc_countdown for why that is a parent link and not a pid;
#   - and each target is fired at only if it still answers to the parent it
#     answered to when this was armed. A branch that finished is reaped by bash,
#     and a reaped pid is one the system may reissue while the run is still very
#     much alive — so "is it alive" is not the question, "is it still the one I was
#     aimed at" is.
#
# What is *not* conditional is the marker. The tempting shape is to give up as soon
# as there is nothing left to kill, and it would lose the cause: `gate__aggregate`
# reads this file to say "red (timed out)" rather than "red (no verdict)", and a
# branch that overran is the case where both are true at once. The deadline expired
# — that is a fact about this gate, not about which pids are still standing.
gate__watchdog() {
  local limit="$1" marker="$2"
  shift 2
  local pid parent aimed=''

  for pid in "$@"; do
    parent="$(proc_parent_of "$pid")"
    [ -n "$parent" ] || continue
    aimed="$aimed $pid:$parent"
  done

  proc_countdown "$limit" || return 0

  : >"$marker"
  for pid in $aimed; do
    parent="${pid#*:}"
    pid="${pid%%:*}"
    [ "$(proc_parent_of "$pid")" = "$parent" ] || continue
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
    gate__say "$ticket: nothing in this gate judged $zone"
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
  moved="$(gate_moved_tree_rules)" || return 0
  gate__say "$ticket: this session moved the ignore frontier: $moved — this iteration was judged through the rules it was handed, the new ones apply from the next"
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
    gate__say "$ticket: this gate could not check what it changed after the tree it judged — nothing here vouches for that zone"
    return 0
  fi
  if zone="$(gate_zone_line "$changed" 'path(s) after the tree it judged')"; then
    gate__say "$ticket: this gate itself changed $zone"
  fi
  return 0
}

# What the language gate covered, and what it did not ([17]). Same shape as the
# three lines above and for the same reason: a check that judges *some* of what a
# session wrote owes a human the size of the rest, every iteration, rather than a
# sentence in a document nobody reads at three in the morning ([24]).
#
# Four numbers, and the last three are the ones that matter. A file with too
# little prose to tell is not evidence and is not judged; a file whose name git
# had to quote is one no consumer of a changed-file list can address at all
# ([39]); a file under `LANG_EXEMPT_PATHS` is one the project told this gate to
# skip — that key is the switch which could turn the whole check off without a
# word, so what it takes out is counted where the coverage is announced and not
# left to the config file.
#
# Off is announced too, and it is the `LENSES is empty` line one tier down: a
# project may run without a language gate, and a run that does must not look like
# a run whose prose was checked and found right.
gate__report_lang() {
  local ticket="$1" dir="$2"

  if ! lang_enabled; then
    gate__say "$ticket: the language gate is off (LANG_CHECK=off): nothing here checked what language this iteration wrote its prose in"
    return 0
  fi
  [ -f "$dir/lang.zone" ] || return 0
  gate__say "$ticket: $(cat "$dir/lang.zone")"
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
    # Which of the three it is decides where the sentence goes, and that is [45]
    # rather than a formatting choice. An exit code is a **verdict**: something ran
    # and came back wrong, its output is on the way to the findings below, and
    # stdout is where a verdict belongs. The other two are the branch saying
    # nothing at all — killed at the deadline, or gone without leaving one — which
    # is the criterion `gate__say` is for, and the receipt is the only place it can
    # last. Left on `gate__log`, they produced a document reading `tests=red` and
    # `escalated:failed-impl` with no line anywhere saying that nothing had run:
    # exactly the misrouting [43] fixed one door down, by the other cause.
    #
    # The branch output cannot carry it either, which is why the channel is the
    # only fix: a killed branch's `.out` is empty, so `receipt_keep_branch` drops
    # it and there is no findings section to read the absence off. The neighbouring
    # case is healthy and must stay as it is — a lens that dies writes its own
    # sentence into its `.out` and exits non-zero, so it arrives here as an exit
    # code and reaches the receipt through the findings.
    if [ -n "$brc" ]; then
      gate__log "$name red (exit $brc)"
    elif [ -f "$dir/timed-out" ]; then
      gate__say "$name red (timed out after ${GATE_TIMEOUT}s): this branch was killed at the gate's own deadline, so it judged nothing — the verdict is red because no verdict came back, and not because anything was found wrong"
    else
      gate__say "$name red (no verdict): this branch ended without leaving one, so it judged nothing — the verdict is red because no verdict came back, and not because anything was found wrong"
    fi
    gate__report "$dir/$name.out"
    # And the whole of it, kept while this directory still exists ([10]). Twenty
    # lines are enough to see which test broke in a log that scrolls; a review
    # lens's findings are prose, this is the only copy — `gate_run` removes the
    # directory, and with it the prompt and the stream ([06]) — and a session
    # retried without them rewrites the same code and is reddened identically.
    receipt_keep_branch "$name" "$dir/$name.out"
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
  local lenses pids='' name pre rc=0 agg=0 contained=0 refused='' posture

  lenses="$(lenses_triggered "$ticket" | tr '\n' ' ')"

  # A zone nothing guards gets named every time round, not once in a document
  # ([24]). A gate with no judgement tier is green on its own tests and on
  # nothing else, and a human reading the morning log has to be able to see that
  # without remembering which key was set.
  if [ -z "${lenses# }" ]; then
    if [ -z "$(lenses_enabled)" ]; then
      gate__say "$ticket: no review lens ran (LENSES is empty): nothing here judged this work by anything but its own tests"
    else
      gate__say "$ticket: no review lens was triggered by this ticket"
    fi
    return 0
  fi

  if [ "$objective_rc" != 0 ]; then
    gate__say "$ticket: the review lenses did not run: the objective checks are already red ($RALPH_GATE_FAILED)"
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
  gate__aggregate "$dir" "$lenses" || agg=1

  # Which of them judged nothing because the API refused the session, read here
  # and nowhere else: the streams live under `$dir`, and `gate_run` removes it
  # ([43]). A branch is a subshell, so this cannot be the branch's own answer.
  #
  # Not asked at all when this fan hit its deadline, and that is [23]'s rule one
  # layer down: a reason this pack measured itself is not overwritten by one read
  # out of the stream of what it measured. A lens the watchdog killed judged
  # nothing either, and letting its last event speak would hand a free give-back to
  # anything that can arrange to hang past `GATE_TIMEOUT` with a blocked line in
  # the stream. The marker is this fan's own: an objective fan that timed out is
  # red, and a red objective fan skips this phase before the tree is even
  # snapshotted. A green fan that raced the watchdog reads as timed out here, which
  # costs a give-back the ticket would have got — the cautious side.
  if [ ! -f "$dir/timed-out" ]; then
    for name in $lenses; do
      if posture="$(lenses_refused_posture "$dir" "$name")"; then
        RALPH_GATE_QUOTA="$posture"
        refused="$refused $name"
        # Said *and* kept, and this one is the reason [43] left work here ([10]):
        # the outcome of a refused delivery session and of a refused lens is the
        # same word, so a reader with only the outcome cannot tell which half of
        # the iteration was refused. Recorded per lens, because
        # `RALPH_GATE_QUOTA` keeps only the last posture — the pilot needs one
        # window, a receipt that wants the list has to have been told.
        gate__say "$ticket: the $name lens judged nothing because the API refused its session ($(printf '%s' "$posture" | awk '{ print $2 }')) — the branch is still red, and this iteration is not an attempt at the ticket"
      fi
    done
  fi

  gate__contain_lens_writes "$ticket" "$pre" || contained=1

  # Red, and red for one reason only. Three conditions, and dropping any of them
  # would hand a session something this signal must never buy ([43]):
  #
  #   agg = 1        there is a red to explain at all. A green gate is green, and
  #                  nothing here may touch it.
  #   contained = 0  the tree the lenses were handed is back where they found it.
  #                  A write nobody could undo is a refusal this pack measured
  #                  itself, and a claim read out of a stream does not overwrite a
  #                  measurement ([23]).
  #   every red is   the one that matters. A lens that answered `fail` looked and
  #   a refused one  found something wrong, and a sibling lens the API refused
  #                  beside it does not take that away. `RALPH_GATE_FAILED` holds
  #                  only lens names here — this phase is skipped outright when an
  #                  objective branch is red — so the comparison is exact.
  if [ "$agg" = 1 ] && [ "$contained" = 0 ] && [ -n "$refused" ] &&
    gate__all_in "$RALPH_GATE_FAILED" "$refused"; then
    RALPH_GATE_QUOTA_ONLY=1
  fi

  [ "$agg" = 0 ] || rc=1
  [ "$contained" = 0 ] || rc=1
  return "$rc"
}

# Whether every word of the first list appears in the second. Both are
# space-delimited; an empty first list is vacuously true, which is why the caller
# tests for a non-empty one before asking.
gate__all_in() {
  local have=" $2 " name
  for name in $1; do
    case "$have" in
      *" $name "*) ;;
      *) return 1 ;;
    esac
  done
  return 0
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
    gate__say "$ticket: could not read the tree before the review lenses — cannot say what they wrote, refusing to pass"
    return 1
  fi

  if ! changed="$(gate_unjudged_changes "$pre")"; then
    gate__say "$ticket: could not read the tree after the review lenses — cannot say what they wrote, refusing to pass"
    return 1
  fi
  [ -n "$changed" ] || return 0

  gate__say "$ticket: a review lens changed $(gate_zone_line "$changed" \
    'path(s) in the tree it was judging') — putting them back"
  gate_restore_tree "$pre" >/dev/null || true

  # And once more after the restore, for the same reason: "I put it back" is a
  # claim about a result, and the only thing that can vouch for it is a second
  # measurement. One that refuses says nothing, which is not the same as saying
  # the tree is clean ([30] on `core.excludesFile`, one layer up).
  if ! left="$(gate_unjudged_changes "$pre")"; then
    gate__say "$ticket: could not check what a review lens wrote was put back — refusing to pass this iteration"
    return 1
  fi
  [ -n "$left" ] || return 0
  gate__say "$ticket: could not undo $(gate_zone_line "$left" \
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
  RALPH_GATE_FRONTIER=""
  RALPH_GATE_TREE=""
  RALPH_GATE_NOTHING_DELIVERED=0
  RALPH_GATE_QUOTA=""
  RALPH_GATE_QUOTA_ONLY=0
  RALPH_GATE_FRONTIER_READ=0
  dir="$(mktemp -d "${TMPDIR:-/tmp}/ralph-gate.XXXXXX")" || return 1

  # Before the tree, so that every branch runs in a repository whose visibility is
  # the run's own and not the session's. The verdict does *not* rest on that
  # ordering, and saying so is the point: the snapshot goes through the pin either
  # way, so a file hidden by a rule written during the session is judged whether or
  # not the rule is still in place. What the restore buys is the iteration *after*
  # this one — without it, the widened frontier is what the next pin records, and a
  # single red iteration would have bought a whole night of blindness ([30]).
  RALPH_GATE_FRONTIER="$(gate_frontier)" || true
  # Said to whoever comes after, and it has one reader: the failure policy asks
  # again on the paths where nobody restored, and reads that list off its own
  # classification ([32]). Since [08] one class on that list — `budget` — can also
  # arrive from an iteration whose gate ran (a delivery session that wrote nothing,
  # and since [43] a review lens the API refused), and asking twice re-detects the
  # one movement no restore can undo, records it in the run's register a second
  # time, and charges every sibling in flight for it twice ([41]).
  RALPH_GATE_FRONTIER_READ=1

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
    gate__say "$ticket: nothing was delivered: this iteration changed no file this gate can see, so there is nothing here to judge and nothing to commit"
    # And what the frontier of that visibility did, which no branch is left to
    # report on this path. `gate_frontier` has already put the rules back
    # above; its findings normally travel on the scope-guard's output, and a
    # session that moved an ignore rule *and* wrote nothing would otherwise leave
    # the one line naming it unprinted ([30]: a zone nobody guards gets named
    # every time round, not once in a document).
    while IFS= read -r finding; do
      [ -n "$finding" ] || continue
      gate__say "$ticket: $finding"
    done <<IGNORE
${RALPH_GATE_FRONTIER:-}
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

    # The fourth objective branch, and last in the fan on purpose: it is the
    # cheapest of them, so the verdict string keeps reading `tests … typecheck …
    # scope …` and nothing anchored on that prefix moves. Off is a decision a
    # project is entitled to make ([17]), and one gate__report_lang says out loud
    # every iteration rather than leaving a silent gap in the verdicts.
    if lang_enabled; then
      gate__start "$dir" lang \
        lang_check "$ticket" "$base" "$RALPH_GATE_TREE" "$dir/lang.zone"
      names="$names lang"
      pids="$pids $!"
    fi

    gate__await "$dir" "$pids"
    gate__aggregate "$dir" "$names" || rc=1
    gate__report_lang "$ticket" "$dir"

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
