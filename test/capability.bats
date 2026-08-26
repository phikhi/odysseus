#!/usr/bin/env bats
#
# Spotting a capability the run needed, and never building one.
#
# A capability — a review lens, an agent, a skill, a command, a hook — is not
# code. It is what a *fresh* `claude` picks up before it reads a prompt, so it
# changes what every later session is, so it changes the contract. That is why
# every assertion below is about a refusal:
#
#   - the loop opens a `ready-for-human` ticket and writes no capability, ever.
#     The proposal goes through the tracker adapter, which is what keeps the two
#     guards of [42] off it, and it is deduplicated against the tracker.
#   - the bar is held by the pack and not by the prompt. An uncovered class fires
#     on the first sighting; a refinement of something that already exists waits
#     for `CAPABILITY_RECUR_AT` of them, counted here and never claimed by a model.
#   - reuse before create is a computation over what exists, not a sentence in a
#     prompt: a lens beats a skill, a skill beats nothing, and the proposal names
#     the winner.
#
# And the acceptance criterion nobody could see the edge of. [31] sealed
# `.claude/agents`, `.claude/commands`, `.claude/skills` and `.claude/hooks`, so
# a session that writes one reds its own iteration — that half is asserted in
# test/gate.bats, where the seal lives. It covers the tree an iteration is judged
# in. Two places reach a later spawn without ever entering that tree: the **main**
# working tree, which a session can find through `git worktree list`, and the
# **operator's home**, which a lens is deliberately spawned to read
# (`--setting-sources user`, [06]). Nothing undoes a write there and nothing here
# pretends to; what this file asserts is that neither one happens in silence.

load helpers/harness
load helpers/assert

setup() {
  harness_setup
}

teardown() {
  harness_teardown
}

# The tier is off in the harness for the reason LENSES is ([06], [14]): the retro
# is a `claude` too. Every test that needs the review puts it back.
retro_on() {
  set_config RETRO on
}

receipt_path() {
  printf '%s/receipts/%s/%s.md\n' "$PROJECT_DIR" "$RALPH_TEST_FEATURE" "$1"
}

# The ticket a proposal opened, by the slug it carries. Empty when none was
# opened, which is what half the tests here are about.
opened_ticket() {
  ls "$TRACKER_DIR" 2>/dev/null | grep "$1" | head -1
}

# ── reuse before create ──────────────────────────────────────────────────────

@test "reuse before create: a lens beats a skill, a skill beats building one" {
  # The ordering is the acceptance criterion, and it is a computation over what
  # exists rather than a preference expressed to a model. A lens comes first
  # because a lens *is* a brief — widening a rubric is a line of prose and no new
  # moving part; a skill the project already ships comes next because it exists
  # and has an author who is not this loop; new is what a human should reach for
  # last.
  set_config LENSES "standards spec"
  mkdir -p "$PROJECT_DIR/.claude/skills/migrations"
  mkdir -p "$PROJECT_DIR/.claude/agents"
  printf 'name: auditor\n' >"$PROJECT_DIR/.claude/agents/auditor.md"

  pack_run 'capability_route standards'
  assert_success
  assert_output_contains "extend"
  assert_output_contains "lens"

  pack_run 'capability_route migrations'
  assert_success
  assert_output_contains "reuse"
  assert_output_contains "skill"

  pack_run 'capability_route auditor'
  assert_success
  assert_output_contains "reuse"
  assert_output_contains "agent"

  pack_run 'capability_route sql'
  assert_success
  assert_output_contains "create"
}

@test "the requested kind does not decide the route" {
  # A retro asking for a `migrations` **lens** when the project already ships a
  # `migrations` skill is asking for something that is already in the building.
  # Answering "build a lens" because the word `lens` was in the question is the
  # mistake the ordering exists to prevent, so the route is read off the
  # inventory and never off the kind.
  set_config LENSES none
  mkdir -p "$PROJECT_DIR/.claude/skills/migrations"

  pack_run 'capability_route migrations'
  assert_success
  assert_output_contains "reuse"
  refute_output_contains "create"
}

# ── the bar ──────────────────────────────────────────────────────────────────

@test "an uncovered class does not wait, and a refinement of what exists does" {
  # Two arms, one criterion. Nothing answering for a name at all is a structural
  # hole and a second sighting says nothing the first did not. Something that
  # *does* answer for it makes this a refinement, and one sighting of a
  # refinement is an opinion.
  set_config LENSES "standards spec"
  set_config CAPABILITY_RECUR_AT 2

  pack_run 'dir="$(mktemp -d)"; capability_bar lens sql "$dir"'
  assert_success
  assert_output_contains "uncovered"

  pack_run 'dir="$(mktemp -d)"
    capability_bar lens standards "$dir"
    capability_bar lens standards "$dir"'
  assert_success
  assert_output_contains "below-bar 1/2"
  assert_output_contains "recurrent"
}

@test "the count is the pack's and not the model's" {
  # The one shape of guarantee this repository keeps a table about: a bar a model
  # is asked to respect is a sentence in a prompt. Two sightings of *different*
  # names are not a recurrence, whatever a session says about having seen it
  # before.
  set_config LENSES "standards spec"
  set_config CAPABILITY_RECUR_AT 2

  pack_run 'dir="$(mktemp -d)"
    capability_bar lens standards "$dir"
    capability_bar lens spec "$dir"'
  assert_success
  assert_output_contains "below-bar 1/2"
  refute_output_contains "recurrent"
}

# ── the proposal ─────────────────────────────────────────────────────────────

@test "a capability the retro names is a ticket on the human sink, and nothing else" {
  use_tickets 01-alpha
  retro_on
  retro_answer \
    "RALPH-RETRO-CAPABILITY: lens sql" \
    "RALPH-RETRO-CAPABILITY-WHY: this ticket wrote three migrations and nothing here read them"

  run_loop
  assert_success

  opened="$(opened_ticket 'capability-lens-sql')"
  [ -n "$opened" ] || fail "no ticket was opened for the capability the retro named"
  assert_file_contains "$TRACKER_DIR/$opened" "**Status:** ready-for-human"
  assert_file_contains "$TRACKER_DIR/$opened" "Detecting one is not creating one"
  assert_file_contains "$TRACKER_DIR/$opened" "nothing here read them"

  # And the refusal itself, asserted rather than trusted: not one file under any
  # of the four sealed directories, in the tree a human will be looking at.
  run bash -c "find '$PROJECT_DIR/.claude/agents' '$PROJECT_DIR/.claude/commands' '$PROJECT_DIR/.claude/skills' '$PROJECT_DIR/.claude/hooks' -type f 2>/dev/null | wc -l | tr -d ' '"
  assert_output_contains "0"

  # Never silent: a proposal that exists only in a ticket nobody was told about is
  # the same failure as no proposal at all.
  assert_file_contains "$(receipt_path 01-alpha)" "does not build capabilities"
}

@test "the proposal names the cheapest answer before the expensive one" {
  # What a human reads first decides what a human does. A proposal that did not
  # say "this already exists" would be asking for a second one.
  set_config LENSES "standards spec"
  set_config CAPABILITY_RECUR_AT 1
  use_tickets 01-alpha
  retro_on
  retro_answer "RALPH-RETRO-CAPABILITY: lens standards"

  run_loop
  assert_success

  opened="$(opened_ticket 'capability-lens-standards')"
  [ -n "$opened" ] || fail "no ticket was opened"
  assert_file_contains "$TRACKER_DIR/$opened" "Extend what exists"
}

@test "a proposal already waiting for a human is not opened again" {
  use_tickets 01-alpha 02-beta
  retro_on
  retro_answer "RALPH-RETRO-CAPABILITY: skill migrations"

  run_loop
  assert_success

  run bash -c "ls '$TRACKER_DIR' | grep -c 'capability-skill-migrations'"
  assert_equal "$output" "1"
}

@test "a proposal the loop opened is not quarantined as a ticket a session gave itself" {
  # The trap [42] left behind and [14] already walked into: the two guards over
  # `issues/` read the loop's own register, and a ticket that appeared without a
  # register line is a session granting itself work. This goes through the tracker
  # adapter for that reason, and the shape is shared with the retro's escalation
  # so that there is one answer and not two.
  use_tickets 01-alpha 02-beta
  retro_on
  retro_answer "RALPH-RETRO-CAPABILITY: agent dba"

  run_loop
  assert_success

  opened="$(opened_ticket 'capability-agent-dba')"
  [ -n "$opened" ] || fail "the capability proposal is not in the tracker"
  refute_file_contains "$TRACKER_DIR/$opened" "quarantine"
  assert_equal "$(ticket_status "${opened%.md}")" "ready-for-human"
}

@test "a capability this project already has is counted out loud, not proposed" {
  set_config LENSES "standards spec"
  set_config CAPABILITY_RECUR_AT 3
  use_tickets 01-alpha
  retro_on
  retro_answer "RALPH-RETRO-CAPABILITY: lens spec"

  run_loop
  assert_success

  assert_equal "$(opened_ticket 'capability-lens-spec')" ""
  # Counted, and said: an opinion that reaches neither a human nor a document is
  # indistinguishable from a retro that saw nothing.
  assert_file_contains "$(receipt_path 01-alpha)" "counted, not proposed"
}

@test "an answer this pack cannot read opens nothing and says which it was" {
  use_tickets 01-alpha
  retro_on
  retro_answer "RALPH-RETRO-CAPABILITY: gadget something or other"

  run_loop
  assert_success

  run bash -c "ls '$TRACKER_DIR' | grep -c 'capability-' || true"
  assert_output_contains "0"
  assert_file_contains "$(receipt_path 01-alpha)" "could not read"
}

@test "a kind that is a pattern is not a kind" {
  # The word comes out of a model, and part of what that model read was written by
  # the session under review. Asked as a regex, `.*` matches `lens` and travels on
  # into the slug — so the loop itself writes `issues/NN-capability-.*-sql.md`, a
  # file name carrying a glob character, chosen by a session, through the one
  # channel neither guard over `issues/` will touch because the loop wrote it.
  # That is [33]'s family of defect reached from a new door.
  use_tickets 01-alpha
  retro_on
  retro_answer "RALPH-RETRO-CAPABILITY: .* sql"

  run_loop
  assert_success

  run bash -c "ls '$TRACKER_DIR' | grep -c 'capability-' || true"
  assert_output_contains "0"
  # And the name itself, because "no ticket matched that prefix" would also be
  # true of a ticket whose name is a pattern that matched nothing.
  run bash -c "ls '$TRACKER_DIR'"
  refute_output_contains '*'
  assert_file_contains "$(receipt_path 01-alpha)" "could not read"
}

@test "a retro whose only answer was a capability is not a retro that said nothing" {
  # Silence is not an answer here for the reason it is not one for a lens ([06]):
  # a session that died or replied prose has distilled nothing, and an iteration
  # where that happened must not read like one where the subagent looked and found
  # nothing worth saying. A capability *is* an answer.
  use_tickets 01-alpha
  retro_on
  retro_answer "RALPH-RETRO-CAPABILITY: skill fixtures"

  run_loop
  assert_success

  refute_file_contains "$(receipt_path 01-alpha)" "ended without an answer this loop could read"
}

@test "the subagent is told what already exists" {
  # The half of "reuse before create" that lives in the prompt. The pack corrects
  # the route afterwards either way, but a model that cannot see the inventory
  # proposes what is already there every night, and the correction is a ticket
  # nobody needed.
  set_config LENSES "standards spec"
  mkdir -p "$PROJECT_DIR/.claude/skills/migrations"
  use_tickets 01-alpha
  retro_on

  run_loop
  assert_success

  run retro_call_stdin
  assert_output_contains "RALPH-RETRO-CAPABILITY"
  assert_output_contains "standards"
  assert_output_contains "migrations"
}

@test "the capability review switched off says so" {
  set_config CAPABILITY off
  use_tickets 01-alpha
  retro_on
  retro_answer "RALPH-RETRO-CAPABILITY: lens sql"

  run_loop
  assert_success

  assert_equal "$(opened_ticket 'capability-lens-sql')" ""
  assert_file_contains "$(receipt_path 01-alpha)" "CAPABILITY=off"
}

# ── the values that would switch this off in silence ─────────────────────────

@test "a CAPABILITY that is neither on nor off is refused at the door" {
  set_config CAPABILITY maybe
  use_tickets 01-alpha

  run_loop
  assert_failure
  assert_output_contains "CAPABILITY is"
}

@test "a bar of zero is refused" {
  set_config CAPABILITY_RECUR_AT 0
  use_tickets 01-alpha

  run_loop
  assert_failure
  assert_output_contains "CAPABILITY_RECUR_AT is"
}

# ── what the seal does not cover ─────────────────────────────────────────────

@test "a capability appearing in the main tree under the run is named on the receipt" {
  # An iteration is judged inside a throwaway worktree ([13]). The main tree is
  # not in it, and a session that goes looking — `git worktree list` names it —
  # can write `.claude/agents/x.md` there, where no scope-guard ever looks and no
  # rollback reaches. [14] found the same route for `LEARNINGS.md` and could serve
  # the index from a copy; a capability is loaded by the binary and there is no
  # copy to serve. So it is a witness, taken before any session of the run exists.
  use_tickets 01-alpha
  session_writes "src/alpha.txt" "$PROJECT_DIR/.claude/agents/rogue.md"

  run_loop
  assert_success

  assert_file_contains "$(receipt_path 01-alpha)" "a capability surface changed while this run was in flight"
  assert_file_contains "$(receipt_path 01-alpha)" ".claude/agents"
}

@test "a capability installed in the operator's home is named too" {
  # The route nothing in this pack had ever looked at, and the trust direction
  # that makes it reachable: a lens is spawned with `--setting-sources user` on
  # purpose ([06]) — it inherits from whoever started the run, never from the tree
  # under review. That assumes the operator's home is not writable by the session
  # being judged, and it is. A hook in `~/.claude/settings.json` is a *command*
  # that runs inside the next session's process.
  #
  # Detection and not prevention, and the difference is written down rather than
  # implied: nothing here reaches outside the repository to undo a file, and this
  # never reds an iteration, because a false red on the operator's own home would
  # stop a night over a file the operator wrote.
  use_tickets 01-alpha
  session_writes "src/alpha.txt" "$HOME/.claude/agents/backdoor.md"

  run_loop
  assert_success
  assert_ticket_status 01-alpha resolved

  assert_file_contains "$(receipt_path 01-alpha)" "a capability surface changed while this run was in flight"
  assert_file_contains "$(receipt_path 01-alpha)" "$HOME/.claude/agents"
}

@test "a write through a symlinked skill is seen, where the seal cannot see it" {
  # The reserve [31] wrote down and left for this ticket: here `.claude/skills` is
  # a farm of symlinks, and a write *through* a link lands outside the sealed
  # path — the scope-guard sees that write as itself, the seal does not see it at
  # all. A witness that did not follow links would be blind to exactly that case.
  mkdir -p "$PROJECT_DIR/substrate/tdd" "$PROJECT_DIR/.claude/skills"
  printf 'first\n' >"$PROJECT_DIR/substrate/tdd/SKILL.md"
  ln -s "$PROJECT_DIR/substrate/tdd" "$PROJECT_DIR/.claude/skills/tdd"

  pack_run 'dir="$(mktemp -d)"
    capability_witness "$dir"
    printf "second\n" >"'"$PROJECT_DIR"'/substrate/tdd/SKILL.md"
    receipt_gap() { printf "GAP %s\n" "$*"; }
    capability_drift "$dir"'
  assert_success
  assert_output_contains "a capability surface changed"
  assert_output_contains ".claude/skills"
}

@test "a run whose capability surfaces did not move says nothing about them" {
  # The line between the two channels [45] drew: the notes are coverage and are on
  # every receipt, these are events. A silence here says no such event was
  # recorded, which is all it ever claimed — and a sentence on every green
  # iteration would be the one nobody reads by the third night.
  use_tickets 01-alpha

  run_loop
  assert_success

  refute_file_contains "$(receipt_path 01-alpha)" "a capability surface changed"
}
