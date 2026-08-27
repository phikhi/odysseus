# shellcheck shell=bash
# Spotting a capability this run needed and does not have — and never building it.
#
# A capability is anything a *fresh* `claude` picks up before the model sees a
# prompt: a review lens ([06]), an agent, a skill, a slash command, a hook. They
# are not code. Code is what a ticket delivers and what the gate judges; a
# capability changes what every later session **is**, so it changes the contract,
# so it is a human's decision and never a night's.
#
# ── the line this module draws ───────────────────────────────────────────────
#
# Detecting is not creating. The retro subagent ([14]) is the one model in the
# pack that looks back at a finished iteration, so it is the one that can notice
# "nothing here reviewed the SQL this ticket wrote". What it may do with that
# notice is exactly one thing: name it. This module turns the name into a ticket
# on the human sink, and there is no branch anywhere in it that writes a lens, an
# agent or a skill.
#
# That refusal is not a promise. `gate_sealed_paths` puts `.claude/agents`,
# `.claude/commands`, `.claude/skills` and `.claude/hooks` in the snapshot
# whatever `GUARDED_PATHS` says, and **no write-surface can cover them** ([31]),
# so a session that created a capability reds its own iteration and is rolled
# back. What that seal covers and what it does not is the whole of
# `capability_witness` at the bottom of this file, and it is written in
# `docs/frontiere-de-confiance.md` rather than assumed.
#
# ── one shape of proposal, two producers ─────────────────────────────────────
#
# [14] already opens tickets on the human sink: a rule that would need a gate, a
# lint or a hook to hold is not a lesson, and it escalates. This module asks for
# something different — a capability, not a rule — and the two would have been
# two producers with two formats, which is the thing a human emptying the sink
# discovers only once it is already there.
#
# So the *shape* lives here, in one function (`capability_propose`), and both
# producers go through it: `retro.sh` for a rule, `capability_review` for a
# capability. Same status, same tracker adapter — therefore the same register
# ([13]) and the same two guards ([42]) — same deduplication against the tracker.
# What differs is the slug prefix and the body, which is what a human reads to
# tell one from the other.
#
# ── the bar, and why the pack holds it rather than the prompt ────────────────
#
# A retro that proposed a capability every time it felt one was missing would
# fill the sink in a week, and a sink nobody empties is a channel that is off.
# The bar is **recurrence or an uncovered class**, and it is decided here:
#
#   uncovered   nothing in this project answers for that name at all — no lens,
#               no agent, no skill, no command. That is a structural hole and one
#               sighting is enough, because a second sighting would tell a human
#               nothing the first did not.
#   recurrent   something *does* answer for it, so what is being asked for is a
#               refinement of something that exists. One sighting of that is an
#               opinion; `CAPABILITY_RECUR_AT` of them in one run is a pattern.
#
# Both arms are computed from the inventory and from a counter this loop keeps,
# never from the model's own claim to have seen something before. A model asked
# "is this recurrent?" answers yes, and that answer would be a guarantee resting
# on a sentence in a prompt — which is what `docs/frontiere-de-confiance.md`
# exists to refuse.
#
# The counter is **per run**, in the retro's own workspace: a `$TMPDIR` directory
# under a `mktemp` name the pilot never exports ([14], [30], [40]). Across runs
# there is no memory, and that is the price of not putting the file in the tree
# where the sessions being counted could write it. Written down rather than
# implied, like the brief's own per-run limit.
#
# ── reuse before create ──────────────────────────────────────────────────────
#
# The cheapest true answer first: extending a lens's brief costs a line of
# config, reusing a skill the substrate already ships costs nothing at all, and
# only a name nothing answers for is worth building. `capability_route` walks the
# inventories in that order and the proposal carries the verdict, so the human
# reading the ticket is told what already exists before being asked to add to it.
# The model is told too — the inventory is in its prompt — but that half is a
# mitigation and this half is the measurement.
#
# Public API
#   capability_preflight              refuse the values that switch this off in silence
#   capability_kinds                  the closed set of things this module names
#   capability_is_kind WORD           is this one of them, as a string and not a pattern
#   capability_inventory KIND         what already exists: name<TAB>where
#   capability_covered KIND NAME      does anything of that kind answer for it?
#   capability_bar KIND NAME DIR      uncovered | recurrent | below-bar n/at
#   capability_route NAME             extend | reuse | create, with the candidate
#   capability_prompt TOKEN           the fragment the retro's prompt carries
#   capability_review TOKEN TICKET STREAM DIR   the whole of it
#   capability_propose SLUG TITLE     the human-sink ticket, deduplicated (stdin: body)
#   capability_surfaces               what a fresh `claude` loads as a capability
#   capability_witness DIR            the run's baseline, before any session exists
#   capability_drift DIR              what moved under it, said out loud

# The tag suffixes this module owns. The prefix comes from whoever carries the
# answer — the retro, today — and is passed in rather than read out of its
# module: a second copy of `RALPH-RETRO` here would be a second thing to keep in
# step, and only one of the two would be the one the subagent was told about.
CAPABILITY_TAG='CAPABILITY'
CAPABILITY_WHY_TAG='CAPABILITY-WHY'

# ── the keys, and the values that would switch this off without saying so ────
#
# Same rule as everywhere else in this pack ([17], [31]): a value that reads as
# "off" is a decision a project takes out loud, never one it falls into.
capability_preflight() {
  local rc=0
  case "${CAPABILITY:-}" in
    on | off) ;;
    *)
      printf 'ralph: CAPABILITY is "%s" — it is `on` or `off`, and anything else would be read as off: a run could need a review it does not have every night and never once say so\n' \
        "${CAPABILITY:-}" >&2
      rc=1
      ;;
  esac
  case "${CAPABILITY_RECUR_AT:-}" in
    '' | 0 | *[!0-9]*)
      printf 'ralph: CAPABILITY_RECUR_AT is "%s" — at zero every first opinion about a capability that already exists becomes a ticket on the human sink, which is the bar removed rather than lowered\n' \
        "${CAPABILITY_RECUR_AT:-}" >&2
      rc=1
      ;;
  esac
  return "$rc"
}

capability__log() {
  printf 'ralph: %s\n' "$*"
}

# ── what a name may be ───────────────────────────────────────────────────────

# The closed set. A kind outside it is a model answering something else, and it
# is refused rather than guessed at: `capability_route` and the ticket body both
# read this word, and a fifth kind would be a proposal nobody can act on.
#
# Membership is asked with `grep -qxF` and the `F` is the whole control, not a
# flourish. This word comes out of a model, and part of what that model read was
# written by the session under review; without `-F` it is a **regex**, so a kind
# of `.*` matches `lens` and travels on into `capability-.*-sql`, which is a file
# name in `issues/` carrying a glob character — the family of defect [33] spent a
# ticket on, reached this time by letting a session choose the name. Probed on
# 25/08/2026: `.*` and `s.ill` both passed the check before the `F`.
capability_kinds() {
  printf '%s\n' lens agent skill command
}

# Is this one of them? One definition, because two spellings of a closed set is
# two closed sets. Every caller downstream of this — the slug, the `case` in
# `capability_inventory`, the `grep` the counter runs — assumes the answer.
capability_is_kind() {
  [ -n "${1:-}" ] || return 1
  capability_kinds | grep -qxF "$1"
}

# One lowercase word. Deliberately narrower than the slug a lesson gets ([14]):
# this name is compared against directory names and against `LENSES`, and a name
# that cannot be one of those is not a capability anybody could reuse. Empty when
# the answer was not one.
capability__name() {
  local name
  name="$(printf '%s' "${1:-}" | tr 'A-Z' 'a-z' | tr -d '\000-\037' |
    sed -e 's/[^a-z0-9-]//g' -e 's/^-*//' -e 's/-*$//' | cut -c1-32)" || name=''
  printf '%s\n' "$name"
  return 0
}

# One line, stripped and bounded, for everything that came out of a model. Same
# job as `retro__oneline` and a copy of it on purpose: this module is handed a
# stream by whoever spawned the session and not by that module, and a lib
# reaching into a neighbour's internals is the mesh `test/layering.bats` refuses.
capability__oneline() {
  printf '%s' "$*" |
    tr '\n\r\t' '   ' |
    tr -d '\000-\037' |
    sed -e 's/  */ /g' -e 's/^ //' -e 's/ $//' |
    cut -c1-240
}

# ── what already exists ──────────────────────────────────────────────────────

# The roots a capability can be installed under, in the order a reader should
# think about them: this project first, then the operator who started the run.
#
# The **worktree is not one of them**, and that is the point rather than an
# omission. An iteration runs in a throwaway worktree ([13]); a capability
# written there dies with it and never reaches a spawn. What reaches a spawn is
# the main tree — which a determined session can find, `git worktree list` names
# it — and the operator's home, which no tree of this pack ever contained.
capability__roots() {
  local root
  root="$(ralph_project_root 2>/dev/null)" || root=''
  [ -z "$root" ] || printf '%s\n' "$root"
  [ -z "${HOME:-}" ] || [ "$HOME" = "$root" ] || printf '%s\n' "$HOME"
  return 0
}

# What exists of one kind, `name<TAB>where` per line.
#
# A lens is not a file, so it is read where a lens actually lives: the names
# `LENSES` enables, minus the ones no predicate answers for. Through that
# module's public readers and never through a second list of the shipped set — a
# list here would look like the authority and be neither, exactly as `lenses.sh`
# says about itself.
capability_inventory() {
  local kind="$1" root entry name unknown

  case "$kind" in
    lens)
      unknown="$(lenses_unknown 2>/dev/null || true)"
      for name in $(lenses_enabled 2>/dev/null || true); do
        printf '%s\n' "$unknown" | grep -qx "$name" && continue
        printf '%s\tLENSES\n' "$name"
      done
      ;;
    skill)
      while IFS= read -r root; do
        [ -n "$root" ] || continue
        [ -d "$root/.claude/skills" ] || continue
        for entry in "$root/.claude/skills"/*; do
          [ -e "$entry" ] || continue
          name="$(basename "$entry")"
          printf '%s\t%s\n' "$name" "$root/.claude/skills/$name"
        done
      done <<ROOTS
$(capability__roots)
ROOTS
      ;;
    agent | command)
      while IFS= read -r root; do
        [ -n "$root" ] || continue
        [ -d "$root/.claude/${kind}s" ] || continue
        for entry in "$root/.claude/${kind}s"/*.md; do
          [ -e "$entry" ] || continue
          name="$(basename "$entry" .md)"
          printf '%s\t%s\n' "$name" "$root/.claude/${kind}s/$name.md"
        done
      done <<ROOTS
$(capability__roots)
ROOTS
      ;;
  esac
  return 0
}

# Does anything of that kind already answer for that name?
capability_covered() {
  local kind="$1" name="$2" have rest
  [ -n "$name" ] || return 1
  while IFS="$(printf '\t')" read -r have rest; do
    [ "$have" = "$name" ] || continue
    return 0
  done <<HAVE
$(capability_inventory "$kind")
HAVE
  return 1
}

# Reuse before create, as three answers and in that order:
#
#     extend<TAB>lens<TAB>LENSES
#     reuse<TAB>skill<TAB>/path/to/it
#     create<TAB><TAB>
#
# A lens comes first because a lens *is* a brief: widening the rubric of one that
# already runs is a line of prose and no new moving part. A skill, an agent or a
# command the substrate already ships comes second — it exists, somebody wrote
# it, and pointing at it costs nothing. Only a name that nothing answers for is
# worth building, and that is the answer a human should have to reach last.
#
# The requested kind is deliberately **not** consulted: a retro asking for a
# `migrations` lens when the substrate ships a `migrations` skill is asking for
# something that is already in the building, and answering "create a lens"
# because the word `lens` was in the question is the mistake this ordering exists
# to prevent.
capability_route() {
  local name="$1" kind have where
  if [ -n "$name" ]; then
    for kind in lens skill agent command; do
      while IFS="$(printf '\t')" read -r have where; do
        [ "$have" = "$name" ] || continue
        if [ "$kind" = lens ]; then
          printf 'extend\t%s\t%s\n' "$kind" "$where"
        else
          printf 'reuse\t%s\t%s\n' "$kind" "$where"
        fi
        return 0
      done <<HAVE
$(capability_inventory "$kind")
HAVE
    done
  fi
  printf 'create\t\t\n'
  return 0
}

# ── the bar ──────────────────────────────────────────────────────────────────

# One sighting, counted. Append-only and counted by lines rather than read,
# incremented and written back: two iterations share this directory above
# `MAX_PARALLEL=1` ([13]), and a read-modify-write between them loses a sighting
# in the one case the bar is about. A single short line appended with `>>` is the
# cheapest thing in this pack that two writers cannot corrupt.
capability__seen() {
  local dir="$1" kind="$2" name="$3" n
  if [ -z "$dir" ] || [ ! -d "$dir" ]; then
    printf '0\n'
    return 0
  fi
  printf '%s/%s\n' "$kind" "$name" >>"$dir/capability.seen" 2>/dev/null || true
  n="$(grep -c "^$kind/$name\$" "$dir/capability.seen" 2>/dev/null | tr -d ' ')" || n=0
  case "$n" in '' | *[!0-9]*) n=0 ;; esac
  printf '%s\n' "$n"
  return 0
}

# `uncovered`, `recurrent` or `below-bar <n>/<at>` — the whole of the acceptance
# criterion, in one place a test can drive without a session.
capability_bar() {
  local kind="$1" name="$2" dir="$3" n at="${CAPABILITY_RECUR_AT:-2}"
  if ! capability_covered "$kind" "$name"; then
    printf 'uncovered\n'
    return 0
  fi
  n="$(capability__seen "$dir" "$kind" "$name")" || n=1
  case "$n" in '' | 0 | *[!0-9]*) n=1 ;; esac
  if [ "$n" -ge "$at" ]; then
    printf 'recurrent\n'
  else
    printf 'below-bar %s/%s\n' "$n" "$at"
  fi
  return 0
}

# ── the human sink ───────────────────────────────────────────────────────────

# One ticket, one shape, both producers. Body on stdin; everything above it is
# written here, so a second producer cannot drift from the first.
#
# `ready-for-human` and never `ready-for-agent`: what is being asked for changes
# what every later session is, and an agent that could take this ticket would be
# the auto-creation this whole module refuses, arriving one night later through
# the tracker.
#
# Opened through the tracker adapter and not by writing a file, which is what
# puts it in the loop's own register of writes ([13]) and therefore out of reach
# of the two guards that would otherwise restore it or quarantine it ([42]).
#
# Deduplicated against the tracker rather than against a list of its own: a
# proposal already waiting for a human is the same proposal, and a second one
# buries the first. Prints the id it opened, and nothing at all when it opened
# nothing — the caller reads emptiness, never an exit code, because "already
# waiting" is a success.
#
# The deduplication is `tracker_open_unique` and no longer a `tracker_ids` read
# here, and that is [47] rather than tidying: reading the tracker and then opening
# leaves the answer stale for exactly as long as it takes to write the ticket, so
# two proposals in flight both found nothing and both opened — the same race as
# the number allocation, entered by the other end. The adapter asks the question
# on the side of its own guard, where it settles something.
capability_propose() {
  local slug="$1" title="$2" body
  body="$(cat)"
  tracker_open_unique "$slug" "$title" <<BODY
**Status:** ready-for-human

**Blocked by:** None

$body
BODY
  return 0
}

# ── the fragment the retro carries ───────────────────────────────────────────

# What already exists, one line per kind, for a prompt.
#
# In the prompt because a model that cannot see the inventory proposes what is
# already there, and this is the half that makes "reuse before create" something
# the subagent can act on rather than something the pack corrects afterwards.
# Bounded: an operator with two hundred skills must not turn this into the
# prompt.
capability__inventory_line() {
  local kind="$1" names
  names="$(capability_inventory "$kind" | cut -f1 | LC_ALL=C sort -u |
    tr '\n' ' ' | sed -e 's/  */ /g' -e 's/ $//' | cut -c1-400)" || names=''
  [ -n "$names" ] || names='(none)'
  printf '  %-8s %s\n' "$kind" "$names"
  return 0
}

capability_prompt() {
  local token="$1"
  cat <<PROMPT
- A **capability** this iteration needed and this project does not have — a
  review lens, an agent, a skill, a slash command — is *named* here and never
  built. This loop cannot create one: the paths a fresh session reads are sealed
  against every write-surface, so what you name becomes a ticket a human decides
  on, and nothing else.

    $token-$CAPABILITY_TAG: <lens|agent|skill|command> <one-word-name>
    $token-$CAPABILITY_WHY_TAG: what went unreviewed for want of it, in one line

  The name is one lowercase word (letters, digits, dashes). Name something that
  is already in the list below to ask for it to be **extended**; the cheapest
  true answer is a lens whose brief grows by a sentence, then a skill that
  already exists, and only then something new.

$(capability__inventory_line lens)
$(capability__inventory_line skill)
$(capability__inventory_line agent)
$(capability__inventory_line command)

  At most one, and saying nothing is the normal answer. A capability named every
  night is a sink nobody empties.
PROMPT
}

# ── reading the answer ───────────────────────────────────────────────────────

capability__said() {
  local token="$1" tag="$2" stream="$3" line
  line="$(lenses_findings "$stream" 2>/dev/null |
    sed -n "s/^[[:space:]]*$token-$tag:[[:space:]]*//p" | tail -1)" || line=''
  [ -n "$line" ] || return 0
  capability__oneline "$line"
  printf '\n'
  return 0
}

# Did the session name a capability at all? Public because the caller has to know
# before this module runs: a retro whose only answer was a capability *answered*,
# and an iteration where that happened must not be reported as one where the
# subagent said nothing ([06]'s rule about silence, applied one tag further).
capability_said() {
  capability__said "$1" "$CAPABILITY_TAG" "$2"
}

# Why this proposal is on the sink tonight rather than next month.
capability__because() {
  local bar="$1" name="$2"
  case "$bar" in
    uncovered)
      printf 'Nothing in this project answers for `%s` at all — no lens, no skill, no agent, no command. An uncovered class is a structural hole, and one sighting says as much about it as ten would.\n' \
        "$name"
      ;;
    *)
      printf 'Something already answers for `%s`, so this is a refinement and not a hole — and it came back %s time(s) in this run, which is the bar `CAPABILITY_RECUR_AT` sets before a human is asked about one.\n' \
        "$name" "${CAPABILITY_RECUR_AT:-2}"
      ;;
  esac
}

# The cheapest true answer, named in the ticket so that a human reads it before
# the expensive one.
capability__cheapest() {
  local decision="$1" candidate="$2" where="$3" name="$4"
  case "$decision" in
    extend)
      printf 'Extend what exists: `%s` is already a %s (%s). A brief that grows by a sentence is cheaper than anything else on this list, and what reviews that %s today reviews the addition too.\n' \
        "$name" "$candidate" "$where" "$candidate"
      ;;
    reuse)
      printf 'Reuse what exists: this project already has a %s called `%s` (%s). Wiring it in is cheaper than writing one, and it has an author who is not this loop.\n' \
        "$candidate" "$name" "$where"
      ;;
    *)
      printf 'Nothing here answers for `%s`, in any of the four kinds this loop can see, so this one would be new. That is the last answer on the list and not the first: check the two above before building it.\n' \
        "$name"
      ;;
  esac
}

# The whole of it, from a finished retro session's stream.
#
# Never fatal and never a non-zero return, for the reason `retro_run` is neither:
# this is the last paperwork of an iteration whose work is already marked, and a
# proposal that could not be written must cost a line on the receipt rather than
# the night.
capability_review() {
  local token="$1" ticket="$2" stream="$3" dir="$4"
  local said why kind name bar route decision candidate where slug id body

  if [ "${CAPABILITY:-on}" != on ]; then
    receipt_note "the capability review is off (CAPABILITY=off): nothing looked at whether this iteration needed a lens, an agent or a skill this project does not have"
    return 0
  fi

  said="$(capability__said "$token" "$CAPABILITY_TAG" "$stream")"
  [ -n "$said" ] || return 0

  kind="$(printf '%s' "$said" | awk '{ print $1 }')"
  name="$(capability__name "$(printf '%s' "$said" | awk '{ print $2 }')")"
  if ! capability_is_kind "$kind" || [ -z "$name" ]; then
    receipt_note "the retro named a capability this loop could not read (\"$(capability__oneline "$said")\") — nothing was opened for it, and that is an answer this pack could not parse rather than an iteration that needed nothing"
    return 0
  fi

  # The bar, before anything is written: an opinion about something that already
  # exists is kept and counted, and it is said out loud rather than dropped —
  # a proposal that never reaches a human and never leaves a trace is
  # indistinguishable from a retro that saw nothing.
  bar="$(capability_bar "$kind" "$name" "$dir")"
  case "$bar" in
    below-bar*)
      receipt_note "the retro asked for a $kind called \`$name\`, which this project already has something for — counted, not proposed: the bar for changing something that exists is $(printf '%s' "$bar" | awk '{ print $2 }') sighting(s) in one run"
      return 0
      ;;
  esac

  route="$(capability_route "$name")"
  decision="$(printf '%s' "$route" | cut -f1)"
  candidate="$(printf '%s' "$route" | cut -f2)"
  where="$(printf '%s' "$route" | cut -f3)"
  why="$(capability__said "$token" "$CAPABILITY_WHY_TAG" "$stream")"
  [ -n "$why" ] ||
    why='The retro named it and did not say in one line what went unreviewed without it.'

  slug="capability-$kind-$name"
  body="$(
    cat <<BODY
**Proposal:** the retro subagent of an autonomous run named a capability this project does not have. Detecting one is not creating one, so nothing was built.

**What was asked**

A $kind called \`$name\`.

**What went unreviewed without it**

> $why

**Why it is here and not built**

A capability is what a fresh session picks up before it reads a prompt: a review
lens, an agent, a skill, a command, a hook. It does not change what one ticket
delivers, it changes what every later session is — so it changes the contract,
and this loop does not take that decision. \`.claude/agents\`, \`.claude/commands\`,
\`.claude/skills\` and \`.claude/hooks\` are sealed against every write-surface, so
this is a refusal with a mechanism behind it and not a habit.

**Why now**

$(capability__because "$bar" "$name")

**Cheapest answer first**

$(capability__cheapest "$decision" "$candidate" "$where" "$name")

**Where it came from**

The iteration on \`$ticket\`. Its audit receipt carries the verdicts and the
findings the retro read.
BODY
  )"

  id="$(printf '%s\n' "$body" | capability_propose "$slug" "a $kind called \`$name\` — a capability this run needed and does not have")" || id=''
  if [ -n "$id" ]; then
    capability__log "$ticket: the retro named a capability this loop must not build — opened $id"
    receipt_note "the retro named a $kind called \`$name\` that this project does not have, and this loop does not build capabilities: $id is on the human sink, with \"$decision\" as the cheapest answer"
  else
    receipt_note "the retro named a $kind called \`$name\` and no ticket was opened for it — either one was already waiting for a human or the tracker refused the write"
  fi
  return 0
}

# ── what nothing else is watching ────────────────────────────────────────────
#
# The acceptance criterion of [15] is that no capability is created automatically
# during an AFK run. [31] holds that for the tree: the four directories are
# sealed, no write-surface can cover them, a session that writes one reds its
# iteration and is rolled back before anything spawns again.
#
# It holds it for **the tree**. Two routes reach a later spawn without ever
# entering a tree the scope-guard compares:
#
#   the main working tree   an iteration is judged inside a throwaway worktree
#                           ([13]); the main tree is not in it, and a session
#                           that goes looking — `git worktree list` names it —
#                           can write `.claude/agents/x.md` there. That is the
#                           route [14] found for `LEARNINGS.md`, and the answer
#                           it used is not available here: an index can be served
#                           from a copy the pilot took, a capability is loaded by
#                           the binary and there is no copy to serve.
#   the operator's home     `~/.claude/agents`, `~/.claude/skills`,
#                           `~/.claude/settings.json` — and a hook in that last
#                           one is a *command*, which runs inside the next
#                           session's process on its first tool call. Nothing in
#                           this pack has ever looked outside the repository, by
#                           design, and a lens is spawned with
#                           `--setting-sources user` on purpose ([06]): the trust
#                           direction is that a lens inherits from whoever
#                           started the run, never from the tree under review.
#                           That direction assumes the operator's home is not
#                           writable by the session being judged. It is.
#
# So this is a **witness** and not a control, exactly like the one [10] put on
# `run.log`: the baseline is taken by the pilot before a single session of the
# run exists, and every iteration says what moved under it. It cannot prevent —
# nothing here reaches outside the repository to undo a file — and it never reds
# an iteration either, because a false red on the operator's own home would stop
# a night over a file the operator wrote. What it buys is that a capability
# appearing mid-run is a sentence on the receipt of every iteration after it
# instead of a silence.
#
# The list is written against the criterion and not against the cases that made
# it ([31], [45]): everything a fresh `claude` loads which changes what a session
# *is*, on both roots. One file is deliberately left out and it is named rather
# than forgotten — `~/.claude.json`, which the binary rewrites on every start
# (project history, startup counters). Witnessing it would report drift on every
# single iteration, which is the same as reporting none.

capability_surfaces() {
  local root
  while IFS= read -r root; do
    [ -n "$root" ] || continue
    printf '%s\n' \
      "$root/.claude/agents" \
      "$root/.claude/commands" \
      "$root/.claude/skills" \
      "$root/.claude/hooks" \
      "$root/.claude/settings.json" \
      "$root/.claude/settings.local.json" \
      "$root/.claude/CLAUDE.md" \
      "$root/CLAUDE.md" \
      "$root/.mcp.json"
  done <<ROOTS
$(capability__roots)
ROOTS
  return 0
}

# One number for a file or for a whole directory. `-L` and not a plain walk: here
# `.claude/skills` is a farm of symlinks into `.agents/`, and a write *through* a
# link lands outside the sealed path — which is the reserve [31] wrote down, and
# the one case a witness that did not follow links would be blind to.
#
# A path that is not there digests to `-`, and an empty directory does not: a
# capability directory being *created* mid-run is exactly the event this is for.
capability__digest() {
  local path="$1" sum=''
  if [ -f "$path" ]; then
    sum="$(cksum <"$path" 2>/dev/null | awk '{ print $1 "." $2 }')" || sum=''
  elif [ -d "$path" ]; then
    sum="$(find -L "$path" -type f 2>/dev/null | LC_ALL=C sort |
      while IFS= read -r f; do
        printf '%s ' "$f"
        cksum <"$f" 2>/dev/null || printf -- '-\n'
      done | cksum | awk '{ print $1 "." $2 }')" || sum=''
  fi
  [ -n "$sum" ] || sum='-'
  printf '%s\n' "$sum"
  return 0
}

# The run's baseline. Taken by the pilot, before any session exists — which is
# what makes a difference afterwards attributable to this run at all — into the
# same secret directory the rest of the fourth layer uses.
capability_witness() {
  local dir="$1" path
  [ -n "$dir" ] && [ -d "$dir" ] || return 1
  : >"$dir/capability.witness" 2>/dev/null || return 1
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    printf '%s\t%s\n' "$path" "$(capability__digest "$path")" \
      >>"$dir/capability.witness"
  done <<PATHS
$(capability_surfaces)
PATHS
  return 0
}

# What moved under it, one sentence per surface, on the document that answers for
# this iteration. Silent when nothing moved: this is an *event* channel and not a
# coverage one, so its silence says no such event was recorded, which is all it
# ever claimed ([45]'s own line between the two).
#
# A gap and not a note, for the same reason: the notes are the zones nothing
# walked and they are on every receipt; this is the pack's own promise coming
# apart, it is rare, and what a human does about it is different.
capability_drift() {
  local dir="$1" path was now
  [ -n "$dir" ] && [ -s "$dir/capability.witness" ] || return 0
  while IFS="$(printf '\t')" read -r path was; do
    [ -n "$path" ] || continue
    now="$(capability__digest "$path")"
    [ "$now" != "$was" ] || continue
    receipt_gap "a capability surface changed while this run was in flight: $path — nothing here judged it, no rollback undoes it, and what a fresh session loads from it is what is there now"
    capability__log "a capability surface changed under this run: $path"
  done <"$dir/capability.witness"
  return 0
}
