# shellcheck shell=bash
# Per-ticket concurrency: an isolated working tree per iteration, a scheduler
# that only ever runs tickets whose write-surfaces cannot meet, and a serialized
# fold back onto the branch the run was started on.
#
# Why an isolated tree is not an optimisation. Three of this pack's guarantees are
# repository-wide and were written for one iteration at a time ([05], [07], [21]):
# the scope-guard measures a diff of the *working tree* around one session, the
# rollback restores that tree path by path and moves HEAD, and the durable commit
# is taken on the branch. Two sessions in one tree see each other's work as their
# own overflow, roll each other's writes back, and commit trees the other is still
# writing into. So the isolation comes first and the parallelism after it — and
# the isolation is worth having on its own, which is the decision below.
#
# **Every iteration gets a worktree, including at MAX_PARALLEL=1.** [34] asked this
# ticket to decide rather than deduce, so: one path and not two. The reasons are
# not about speed. [24] owns "a ticket goes green on an ignored file the previous
# session left behind" and [29] owns "what the gate's own branches wrote is in the
# next iteration's baseline"; both name a throwaway tree as what closes them by
# construction, and closing them only above MAX_PARALLEL=1 would mean the shipped
# default never gets the closure. Two code paths would also be two behaviours to
# test and to mutate, and the second one is the one nobody runs.
#
# What that costs, written here rather than discovered:
#
#   - a fresh worktree does not carry the untracked files of the main tree. That
#     is the point for a leftover; it is a problem for a `.env` or a
#     `node_modules` the project's suite legitimately needs. WORKTREE_PROVISION
#     is the answer and it is deliberately empty by default — what the pilot
#     copies in is a zone no scope-guard will ever see, so it is a decision a
#     project writes down, and the run counts it out loud every iteration ([24]).
#   - a run started on a dirty main tree no longer judges that dirt. The session
#     starts from the branch tip. A human's uncommitted work is neither judged nor
#     rolled back nor committed — it is simply not there, which is a better answer
#     than the three the shared tree gave.
#   - the repository must have a commit. `git worktree add` cannot make a tree out
#     of nothing, so the preflight refuses rather than failing at the first
#     iteration.
#
# What it does **not** close, and the ticket says so in the same breath ([30]):
# `.git/info/exclude` and `core.excludesFile` live in the *common* git directory,
# shared by every linked worktree. What this module isolates is the ignored zone;
# what decides the frontier of that zone stays common, and two iterations putting
# it back at once are a race on state that nothing here holds a lock over.
#
# Layering decided where the fan lives. The scheduler forks the iteration body,
# and the iteration body is `loop.sh` — a lib that forked it would be calling up
# into the loop, which `test/layering.bats` refuses. So this module owns the
# policy primitives (how many may run, which may run together, where they run,
# how they are folded back) and `loop.sh` owns the loop that uses them.

concurrency__log() {
  printf 'ralph: %s\n' "$*"
}

# What has to be true before a single ticket is claimed.
#
# Both refusals are the same shape as the ones [31] wrote the sealed list against:
# a value that would switch a decision off without saying so. A repository with no
# commit cannot be given a worktree, and finding that out at the first iteration
# would mean discovering it with a ticket already claimed; a MAX_PARALLEL nobody
# can read would be read as one, which is a run quietly refusing the parallelism it
# was configured for.
concurrency_preflight() {
  local root rc=0
  root="$(ralph_project_root)"
  if ! (cd "$root" 2>/dev/null && git rev-parse HEAD >/dev/null 2>&1); then
    printf 'ralph: this repository has no commit yet — every iteration runs in a worktree of its own, and git cannot make one out of nothing\n' >&2
    rc=1
  fi
  case "${MAX_PARALLEL:-1}" in
    '' | *[!0-9]* | 0)
      printf 'ralph: MAX_PARALLEL is "%s" — a parallelism this pack cannot read would be read as 1, and a value that switches a setting off in silence is refused (see %s)\n' \
        "${MAX_PARALLEL:-}" "$RALPH_CONFIG" >&2
      rc=1
      ;;
  esac
  return "$rc"
}

# ── how many may be in flight ────────────────────────────────────────────────

# The number of iterations this run may have in flight, MAX_PARALLEL throttled by
# what the budget last measured.
#
# Why throttle at all: `budget_check` is proactive — it is asked before a ticket
# is claimed, so a run that is out of subscription spawns nothing ([08]). With N
# iterations in flight that check can be overshot by up to N iterations' worth of
# sessions, because they were all approved before any of them finished. Fewer
# slots is the only lever this pack has over that.
#
# It is a **rate**, and calling it anything else would be the mistake [08] wrote
# down: this pack cannot price an iteration in advance — one iteration is `1 + n`
# sessions ([06]) — so nothing here converts headroom into a number of iterations.
# What it does is spend a window that is nearly full more slowly than one that is
# nearly empty, proportionally, and never below one. What actually bounds the run
# is still `budget_check` before every claim, plus ITER_CAP and STERILE_K.
#
# When nothing measured a window — the shipped installation, where
# USAGE_TOKEN_CMD is empty and the endpoint answers nothing this pack can read —
# the cap stands at MAX_PARALLEL and the run says so once. Refusing to parallelise
# there would be the honest-looking answer and the wrong one: it would make the
# key inert for most installations, and the human who set MAX_PARALLEL=3 made that
# choice on a subscription they know. Naming the exposure is what [08] does one
# layer up, with the same sentence.
# It sets CONCURRENCY_CAP in the caller's shell rather than printing it, and that
# is load-bearing rather than a taste: `$(concurrency_cap)` forks a subshell, so
# the once-per-run line below would be printed on *every* scheduling pass and the
# flag meant to suppress it would die with each fork. Exactly the reason
# `budget_check` sets variables instead of printing ([08]), one layer up.
concurrency_cap() {
  local want="${MAX_PARALLEL:-1}" head slots
  case "$want" in
    '' | *[!0-9]* | 0) want=1 ;;
  esac
  if [ "$want" -le 1 ]; then
    CONCURRENCY_CAP=1
    return 0
  fi

  head="${RALPH_BUDGET_HEADROOM:-}"
  if [ -z "$head" ]; then
    concurrency__say_once headroom \
      "no usage window was measured, so $want iterations may be in flight against a subscription nothing here can see — MAX_PARALLEL is spending it $want times faster than a sequential run"
    CONCURRENCY_CAP="$want"
    return 0
  fi

  # Ceiling, so a window with any headroom at all keeps at least a fraction of
  # the cap rather than rounding down to one on the first percent spent.
  slots=$(((want * head + 99) / 100))
  [ "$slots" -ge 1 ] || slots=1
  [ "$slots" -le "$want" ] || slots="$want"
  CONCURRENCY_CAP="$slots"
  return 0
}

# Once per run, whatever the caller. Same shape as budget__say_once and for the
# same reason: a line about a zone nobody guards has to be said, and said once —
# repeated on every scheduling decision it would be noise a human stops reading.
concurrency__say_once() {
  local key="$1"
  case " ${CONCURRENCY__SAID:-} " in
    *" $key "*) return 0 ;;
  esac
  CONCURRENCY__SAID="${CONCURRENCY__SAID:-} $key"
  shift
  concurrency__log "$*"
  return 0
}

# ── which may run together ───────────────────────────────────────────────────

# Whether this ticket may run beside the ones already in flight. Non-zero means
# it must wait — which is the fail-safe direction and the only one that can be
# wrong cheaply.
#
# The predicate is `gate_in_surface`, tried both ways round, which is deliberately
# the scope-guard's own ([05]) and not a second reading of a write-surface. A
# surface is a list of globs a human wrote, so `src` against `src/auth/*` only
# matches one way; the same both-directions approximation is what decides a gated
# review lens ([06]), and approximating towards *sequencing* is the safe direction
# here exactly as approximating towards *running the lens* is there.
#
# A surface this pack cannot read is a clash, not a pass. An empty
# `Write-surface:` means the scope-guard has nothing to measure against, so two
# such tickets in one run would be two sessions with no declared boundary — and
# the whole disjunction rests on the declaration being complete. A ticket like that
# runs, it simply runs alone.
#
# What this does *not* hold, and it is the honest half: a write-surface is a
# declaration, and a session that writes outside it is caught by the scope-guard
# *after* the fact. Two iterations whose declarations are disjoint can still touch
# the same file — one of them overflowing — and then each sees the other's write
# in its own tree. In a worktree that costs the overflowing iteration its own gate
# and leaves the other one alone, which is the containment; without the worktree it
# would be the cross-escalation [05] described.
concurrency_clashes() {
  local ticket="$1" others="$2" mine other entry theirs
  # Nothing in flight is nothing to clash with, and asking the questions below
  # anyway would answer "wait" for a ticket with no declared surface — for ever,
  # with nothing running that it could be waiting on. The scheduler has one loop
  # and this is the line that keeps it from spinning in it.
  [ -n "${others# }" ] || return 1
  mine="$(gate_write_surface "$ticket")"
  [ -n "$mine" ] || return 0

  for other in $others; do
    [ -n "$other" ] || continue
    [ "$other" != "$ticket" ] || continue
    theirs="$(gate_write_surface "$other")"
    [ -n "$theirs" ] || return 0
    while IFS= read -r entry; do
      [ -n "$entry" ] || continue
      gate_in_surface "$entry" "$theirs" && return 0
      gate_in_surface "$theirs" "$entry" && return 0
    done <<SURFACE
$mine
SURFACE
  done
  return 1
}

# ── where an iteration runs ──────────────────────────────────────────────────

# The git directory every linked worktree shares. Not the same question as
# `ralph_tree_lock_path`, which wants the *private* one on purpose ([22]): a lock
# that is per working tree is what lets one run own one tree. Everything here is
# the opposite — a guard over the branch, and the leftovers of runs that shared
# this repository — so it has to be the common one.
concurrency__common_dir() {
  local root dir
  root="$(ralph_project_root)"
  dir="$(cd "$root" 2>/dev/null && git rev-parse --git-common-dir 2>/dev/null)" || return 1
  [ -n "$dir" ] || return 1
  case "$dir" in
    /*) ;;
    *) dir="$root/$dir" ;;
  esac
  printf '%s\n' "$dir"
}

# A throwaway working tree at the branch tip, detached.
#
# Detached and not on a branch of its own: git refuses two worktrees on one
# branch, and a branch per iteration would leave a ref per killed run in a
# namespace `failed/<ticket>` already crowds. Detached also makes the durable
# commit's compare-and-swap trivially safe inside the worktree — nothing else can
# be moving that HEAD — and leaves the real contention where it belongs, on the
# one fold in concurrency_integrate.
#
# Prints the tip it was created at, which the fold needs: an iteration whose tip
# never moved is folded by fast-forward and keeps the very commit
# `failures_make_durable` wrote.
concurrency_worktree_add() {
  local dir="$1" root tip
  root="$(ralph_project_root)"
  tip="$(cd "$root" 2>/dev/null && git rev-parse HEAD 2>/dev/null)" || tip=""
  if [ -z "$tip" ]; then
    concurrency__log "this repository has no commit yet — an isolated worktree cannot be made out of nothing"
    return 1
  fi
  if ! (cd "$root" && git worktree add -q --detach "$dir" "$tip" >/dev/null 2>&1); then
    concurrency__log "could not create a worktree at $dir — refusing to run an iteration in the tree the run was started in"
    return 1
  fi
  printf '%s\n' "$tip"
}

# And its removal. `--force` because the tree is expected to be dirty: a rolled
# back iteration leaves what the rollback could not reach, and a red one leaves
# everything the session wrote. Nothing is read out of it after this point — the
# green work has already been folded, the forensic branch has already been
# written from a tree object — so the force is a statement about the throwaway,
# not about the work.
concurrency_worktree_drop() {
  local dir="$1" root
  [ -n "$dir" ] || return 0
  root="$(ralph_project_root)"
  (cd "$root" && git worktree remove --force "$dir" >/dev/null 2>&1) && return 0
  # A worktree git will not let go of still must not be left registered: the
  # administrative entry outlives the directory and every later `git worktree`
  # call carries it. `prune` is the one that reads the registration rather than
  # the tree, so it is what can clean up after a removal that failed.
  rm -rf "$dir" 2>/dev/null || true
  (cd "$root" && git worktree prune >/dev/null 2>&1) || true
  return 0
}

# What a killed run left registered. Counted, never removed, and that is the same
# posture `gate_leftovers` takes for the gate's temporary directories ([36]): this
# pack locks a working tree and not a machine, so a worktree registered a second
# ago belongs to a run that is very much alive. Pruning belongs to [19], the one
# component that lives outside an iteration.
#
# `git worktree list` names the main tree first; it is the run's own and is not a
# leftover.
concurrency_leftovers() {
  local root n
  root="$(ralph_project_root)"
  n="$(cd "$root" 2>/dev/null && git worktree list --porcelain 2>/dev/null |
    awk -v pfx="$(concurrency__prefix)" '
      $1 == "worktree" && index($2, pfx) == 1 { n++ }
      END { print n + 0 }')" || n=0
  [ "${n:-0}" -gt 0 ] || return 1
  printf '%s iteration worktree(s) of earlier runs are still registered in this repository — nothing here removes them\n' "$n"
}

# The name every iteration worktree of this pack carries, so a leftover can be
# told from a worktree a human made. A prefix and not a marker file: the
# registration is what survives a killed run, and it holds a path and nothing
# else.
concurrency__prefix() {
  printf '%s/ralph-worktree.\n' "${TMPDIR:-/tmp}"
}

concurrency_worktree_path() {
  mktemp -d "$(concurrency__prefix)XXXXXX"
}

# What the project needs in a tree that has none of its untracked files.
#
# Copied, never linked, and that is the decision this key exists to make visible.
# A symlink would be cheaper for a `node_modules` and it would put the iteration's
# writes back in the main tree — shared with every sibling, judged by no
# scope-guard, undone by no rollback — which is precisely the isolation this
# module is here to give. The cost is a copy per iteration, and a project whose
# dependencies are too big for that has a real reason to keep MAX_PARALLEL at 1
# and to name only what it must.
#
# Prints the count so the caller can say it out loud. This is a zone no check in
# this pack will ever see, so it gets the treatment [24] gave the ignored zone: it
# is named on every iteration rather than once in a document.
concurrency_provision() {
  local dir="$1" path root taken=0
  root="$(ralph_project_root)"
  while IFS= read -r path; do
    path="${path%/}"
    [ -n "$path" ] || continue
    [ -e "$root/$path" ] || continue
    mkdir -p "$dir/$(dirname "$path")" 2>/dev/null || continue
    cp -R "$root/$path" "$dir/$path" 2>/dev/null || {
      concurrency__log "could not provision $path into this iteration's worktree"
      continue
    }
    taken=$((taken + 1))
  done <<PROVISION
${WORKTREE_PROVISION:-}
PROVISION
  printf '%s\n' "$taken"
}

# ── folding a green iteration back ───────────────────────────────────────────

# The guard the fold is taken under. In the common git directory, for the reason
# the tree lock is in the private one ([22]): this one is about the branch, which
# every worktree of this repository shares, and it must be out of reach of a
# `git clean` and an `rm -rf .scratch` all the same.
concurrency__integration_guard() {
  local dir
  dir="$(concurrency__common_dir)" || return 1
  printf '%s/ralph.integrate.lock\n' "$dir"
}

# ── ordering what every iteration shares ─────────────────────────────────────

# The guard the ignore frontier's restore is taken under ([41]). Same directory
# and same argument as the fold's, one layer down: `.git/info/exclude` and
# `core.excludesFile` are *in* the common git directory, so a guard anywhere else
# would order nothing at all. It is `gate.sh` that takes it — the guard belongs to
# this module because the common directory does, and the decision of when to take
# it belongs to the check that restores.
#
# Public where the fold's is private, and that is the second-caller rule rather
# than an oversight: a guard with a caller in another module is an interface.
concurrency_frontier_guard() {
  local dir
  dir="$(concurrency__common_dir)" || return 1
  printf '%s/ralph.frontier.lock\n' "$dir"
}

# Bounded much shorter than the fold's, and the difference is not a tuning: the
# fold *must* be exclusive to be correct — it is a compare-and-swap on a ref — so
# it is worth a minute of waiting. This one is not correctness. What it restores is
# a fixed value read from the run's own witness, so two unguarded restores write
# the same bytes; the guard buys one restore and one record where there would
# otherwise be two of each. A wait long enough to stall a gate would buy nothing
# and cost the iteration, so a caller that cannot have it goes ahead without it.
concurrency_frontier_take() {
  local guard tries=30
  guard="$(concurrency_frontier_guard)" || return 1
  while [ "$tries" -gt 0 ]; do
    state_guard_take "$guard" "frontier guard" "${FEATURE:-unknown}" && return 0
    tries=$((tries - 1))
    sleep 0.1
  done
  return 1
}

concurrency_frontier_release() {
  local guard
  guard="$(concurrency_frontier_guard)" || return 0
  state_guard_release "$guard"
}

# Fold one gated iteration onto the branch the run was started on, one at a time.
#
# Called with the commit the worktree was created at, the commit the durable
# commit left it on, and the paths the scope-guard approved. Non-zero when the
# work is still only in the worktree, which the caller has to treat as a green
# iteration whose result did not survive — the ticket is marked either way, and
# saying so is the caller's business.
#
# Two shapes, and the first one is why the fast-forward is worth writing:
#
#   fast-forward  the branch has not moved since this worktree was made. The very
#                 commit `failures_make_durable` wrote becomes the tip, so a run
#                 at MAX_PARALLEL=1 produces exactly the history it produced
#                 before this ticket — same tree, same message, same parent.
#   replay        a sibling folded first. The approved paths are taken out of this
#                 iteration's commit and written on top of the new tip, so what
#                 lands is what the scope-guard approved and nothing else. The
#                 sibling's work is not re-tested against it, and that is the cost
#                 of serialized integration: two iterations with disjoint surfaces
#                 can each be green and the combination untested. What bounds it is
#                 the disjunction above and the next iteration's own suite, which
#                 runs on the combined tree.
#
# The ref move is a compare-and-swap on the value read inside the guard, so the
# guard is a scheduling device and not the correctness. A run that lost its guard
# — a session that removed it, a stale takeover — still cannot overwrite a
# sibling's commit; it is refused and says so, which is [07]'s answer to two runs
# on one repository and it holds here unchanged.
concurrency_integrate() {
  local ticket="$1" start="$2" commit="$3" changed="$4"
  local guard root tip rc=0

  # Nothing was committed in the worktree — a durable commit git refused, or one
  # that found everything it approved already in its baseline. There is nothing to
  # fold, and saying "folded onto the branch" about a ref that did not move is the
  # kind of line [30] paid for on `core.excludesFile`: a control reporting its
  # intention instead of its result.
  [ -n "$commit" ] && [ "$commit" != "$start" ] || return 0

  # And the fold's own refusal, which is not the caller's to make ([44]). This is
  # the one point of no return an iteration reaches after a wait it does not
  # control: `concurrency__wait_for_guard` can sit here for a minute while a
  # sibling folds. `state_guard_take` recovers a guard from an owner that is gone,
  # so an orphan asking for it would be *granted* it, in the name of a run that no
  # longer exists — which is exactly what [22] refuses a second run, reached by
  # killing the first. The compare-and-swap below stays the correctness; what is
  # missing without this line is that an orphan may not even try.
  if proc_owner_gone; then
    concurrency__log "$ticket: the run that started this iteration is gone — not taking the integration guard, and not moving the branch"
    return 1
  fi
  root="$(ralph_project_root)"

  if ! guard="$(concurrency__integration_guard)"; then
    concurrency__log "$ticket: no git directory to serialize the fold in — this iteration is not on the branch"
    return 1
  fi

  concurrency__wait_for_guard "$guard" || {
    concurrency__log "$ticket: could not take the integration guard — this iteration is not on the branch"
    return 1
  }

  tip="$(cd "$root" && git rev-parse HEAD 2>/dev/null)" || tip=""
  if [ -z "$tip" ]; then
    concurrency__log "$ticket: could not read the branch this run was started on — this iteration is not on the branch"
    state_guard_release "$guard"
    return 1
  fi

  if [ "$tip" = "$start" ]; then
    if (cd "$root" && git update-ref -m "ralph: $ticket" HEAD "$commit" "$tip" 2>/dev/null); then
      concurrency__log "$ticket: folded onto the branch"
    else
      concurrency__log "$ticket: could not move the branch — this iteration is not on it"
      rc=1
    fi
  else
    concurrency__replay "$ticket" "$tip" "$commit" "$changed" || rc=1
  fi

  # The tip read inside the guard, before either shape moved the ref: the refresh
  # needs to know what the fold actually *did* to the branch, and "is this path in
  # HEAD" alone cannot tell a path the fold removed from a path that was never on
  # the branch at all ([50]).
  [ "$rc" = 0 ] && concurrency__refresh "$changed" "$tip"
  state_guard_release "$guard"
  return "$rc"
}

# Wait for the fold's turn rather than give up on it. Bounded, because a guard
# whose holder died between the mkdir and the release would otherwise hang the run
# until morning — and `state_guard_take` already recovers a guard whose owner is
# gone, so the wait only ever covers a sibling that is really folding. A fold is
# plumbing on tree objects: it takes no session, no test suite and no network, so
# a wait this long means something is wrong rather than something is slow.
concurrency__wait_for_guard() {
  local guard="$1" tries=600
  while [ "$tries" -gt 0 ]; do
    state_guard_take "$guard" "integration guard" "${FEATURE:-unknown}" && return 0
    tries=$((tries - 1))
    sleep 0.1
  done
  return 1
}

# The approved paths of this iteration, written on top of a tip a sibling moved.
#
# Path by path out of the iteration's own commit, and never a merge: what this
# iteration is entitled to put on the branch is exactly what its scope-guard
# approved, and a merge would carry whatever else its worktree happened to hold.
# A path the session deleted is recorded as deleted, which `git ls-tree` answers
# by returning nothing for it.
concurrency__replay() {
  local ticket="$1" tip="$2" commit="$3" changed="$4"
  local root idx path line newtree new

  root="$(ralph_project_root)"
  idx="$(mktemp "${TMPDIR:-/tmp}/ralph-fold.XXXXXX")" || return 1
  rm -f "$idx"
  if ! (cd "$root" && GIT_INDEX_FILE="$idx" git read-tree "$tip^{tree}" 2>/dev/null); then
    rm -f "$idx"
    concurrency__log "$ticket: could not read the branch tip — this iteration is not on the branch"
    return 1
  fi

  while IFS= read -r path; do
    [ -n "$path" ] || continue
    # `:(literal)`, the last of [33]'s readers to be recalled ([54]) — and not for
    # the family that ticket was opened on. `git ls-tree` does not wildmatch at
    # all: it refuses `:(glob)` outright and answers a `src/zone*.txt` with
    # nothing, so a delivered `src/zone[1].txt` comes back on this line either way.
    # A **leading colon** is what breaks it. `:` opens pathspec magic, git does not
    # recognise the short magic `o`, and the question becomes `odd.txt` — a name
    # nothing carries. `line` is empty *with rc=0*, so the branch below cannot tell
    # "the session deleted it" from "I did not understand the path", and reads the
    # first: the `--force-remove` takes a green delivery back off the branch, under
    # a journal line that says it was folded onto it.
    #
    # Only this line. The two neighbours take a file name and not a pathspec, which
    # is why they were right all along and why `:(literal)` would *break* them —
    # measured: `git update-index --force-remove -- ':odd.txt'` removes `:odd.txt`,
    # and the same call with `:(literal):odd.txt` removes nothing at all.
    line="$(cd "$root" && git ls-tree "$commit^{tree}" -- ":(literal)$path" 2>/dev/null)" || line=""
    if [ -z "$line" ]; then
      (cd "$root" && GIT_INDEX_FILE="$idx" git update-index --force-remove -- "$path" 2>/dev/null) || true
    else
      (cd "$root" && GIT_INDEX_FILE="$idx" git update-index --add --cacheinfo \
        "$(printf '%s' "$line" | awk '{ print $1 }'),$(printf '%s' "$line" | awk '{ print $3 }'),$path" 2>/dev/null) || true
    fi
  done <<PATHS
$changed
PATHS

  newtree="$(cd "$root" && GIT_INDEX_FILE="$idx" git write-tree 2>/dev/null)" || newtree=""
  rm -f "$idx"
  if [ -z "$newtree" ]; then
    concurrency__log "$ticket: could not build the folded tree — this iteration is not on the branch"
    return 1
  fi
  if [ "$newtree" = "$(cd "$root" && git rev-parse "$tip^{tree}" 2>/dev/null)" ]; then
    return 0
  fi

  new="$(cd "$root" && git commit-tree "$newtree" -p "$tip" \
    -m "$ticket: iteration delivered (gate green)" 2>/dev/null)" || new=""
  if [ -z "$new" ] ||
    ! (cd "$root" && git update-ref -m "ralph: $ticket" HEAD "$new" "$tip" 2>/dev/null); then
    concurrency__log "$ticket: could not move the branch — this iteration is not on it"
    return 1
  fi
  concurrency__log "$ticket: folded onto the branch over a sibling's commit"
  return 0
}

# The main working tree, brought up to the branch it is checked out on.
#
# Not cosmetic. The iterations run elsewhere, so nothing else would ever write
# these files: the branch moves and the tree a human looks at in the morning shows
# every delivered path as an unstaged *reversal* — and a `git commit -a` on it
# would undo the night. Scoped to the approved paths, the same discipline the
# rollback keeps, so an index a human left half-prepared elsewhere stands.
#
# What it costs is written down: a human's uncommitted edit to a path this
# iteration delivered is overwritten. That is the loss the durable commit already
# took in the shared tree, and it is narrower here — only the paths a gate
# approved, never the rest of the tree.
#
# Which makes the second argument load-bearing rather than an optimisation ([50]).
# The walk used to ask one question — is this path in `HEAD`? — and read "no" as
# "the iteration deleted it", so it deleted it here too. A path the durable commit
# could not stage is not in `HEAD` either, and it answered that question exactly
# like a deletion: probed on the case that opened [50], the main tree's own
# `.claude/cache/keep.txt` was removed, and `rmdir -p` took the directory with it —
# a file no run had ever committed, destroyed by a run that had just said out loud
# it could not commit it. The pre-fold tip settles it: what the fold removed from
# the branch was on the branch a moment ago, and what was on neither side is a path
# this function has nothing true to say about — it is left alone, in the tree and
# in the index both.
concurrency__refresh() {
  local changed="$1" tip="${2:-}" root idx path line n=0 acted=''
  root="$(ralph_project_root)"
  [ -n "$changed" ] || return 0

  idx="$(mktemp "${TMPDIR:-/tmp}/ralph-refresh.XXXXXX")" || return 0
  rm -f "$idx"
  (cd "$root" && GIT_INDEX_FILE="$idx" git read-tree HEAD 2>/dev/null) || {
    rm -f "$idx"
    return 0
  }

  while IFS= read -r path; do
    [ -n "$path" ] || continue
    # `:(literal)`, because a path is not a pattern: a delivered `src/zone[1].txt`
    # asked about `src/zone1.txt` and got an answer about a file that is not it.
    line="$(cd "$root" && git ls-tree HEAD -- ":(literal)$path" 2>/dev/null)" || line=""
    if [ -z "$line" ]; then
      # Not on the branch now. Only a deletion if it was on the branch before the
      # fold — otherwise nothing this run committed put it there or took it away,
      # and the file sitting at that name belongs to whoever wrote it ([50]).
      if [ -z "$tip" ] ||
        [ -z "$(cd "$root" && git ls-tree "$tip" -- ":(literal)$path" 2>/dev/null)" ]; then
        continue
      fi
      rm -f "$root/$path" 2>/dev/null || true
      rmdir -p "$root/$(dirname "$path")" 2>/dev/null || true
    else
      (cd "$root" && GIT_INDEX_FILE="$idx" git checkout-index -f -- "$path" 2>/dev/null) || true
    fi
    acted="$acted$path
"
    n=$((n + 1))
  done <<PATHS
$changed
PATHS

  rm -f "$idx"
  # The real index still describes what was there before the fold, which would
  # read as a staged reversal. Same paths, so nothing else staged is disturbed.
  #
  # One call per path, and the loop above is why this line was worth finding
  # ([33], found here by [39]): the walk reads the list one path per line and this
  # rejoined it into a single whitespace word to hand to git. So a delivered
  # `src/my file.txt` was written back into the tree by the loop and left staged as
  # a *deletion* by this line — which is precisely the state the whole function
  # exists to avoid, on the one path that reached it, and a `git commit -a` in the
  # morning would have undone the night's work on that file.
  #
  # Over what the walk above *acted on* and not over the whole list ([50]): a path
  # the fold neither put on the branch nor took off it has no index entry this run
  # is entitled to move either, and `git reset -- <path>` sets that entry back to
  # HEAD — which would quietly unstage a human's own staged edit at a name this run
  # just declined to commit. Same rule at both ends of the function.
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    (cd "$root" && git reset -q -- ":(literal)$path" 2>/dev/null) || true
  done <<PATHS
$acted
PATHS
  return 0
}
