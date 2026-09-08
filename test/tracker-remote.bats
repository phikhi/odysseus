#!/usr/bin/env bats
#
# The two remote tracker adapters, `github` and `gitlab` ([18]).
#
# Driven by a fake forge that keeps state (`test/helpers/shims/forge-api`), which
# is what a canned body could not do: these adapters write the tracker and read
# back what they wrote, so a scenario that only ever reads would exercise none of
# them.
#
# Everything is asserted on what the **forge** holds, read by the harness rather
# than through the pack: a reader shared with the implementation could not catch
# the implementation writing nonsense — the rule test/tracker-local.bats states,
# applied one transport over.

load helpers/harness
load helpers/assert

setup() {
  harness_setup
}

teardown() {
  harness_teardown
}

# Two tickets, the shape every scenario below starts from.
remote__two() {
  forge_seed 1 alpha Alpha <<'T'
# 1 — Alpha

**Status:** ready-for-agent

**Blocked by:** None

**Write-surface:** `src/a.txt`
T
  forge_seed 2 beta Beta <<'T'
# 2 — Beta

**Status:** ready-for-agent

**Blocked by:** None

**Write-surface:** `src/b.txt`
T
}

# ── the interface ────────────────────────────────────────────────────────────

@test "both remote backends implement every operation the dispatcher routes" {
  # AC 1 and AC 5 of [18] read as one rule about the source, because that is the
  # only place either is visible: an operation a backend does not implement gets
  # `3` and a sentence on stderr from `tracker__dispatch`, and every one of its
  # callers reads that through a command substitution. The failure is therefore
  # silent by construction — `gate__surface_owner` concluded "nobody declared this
  # path" from a backend that could not list its tickets — and no functional test
  # of a backend that answers can notice an operation missing from the other.
  local op missing=''
  for op in $(grep -o 'tracker__dispatch [a-z_]*' "$RALPH_PACK_ROOT/.claude/lib/tracker.sh" |
    awk '{ print $2 }' | sort -u); do
    grep -q "^tracker_github_$op()" "$RALPH_PACK_ROOT/.claude/lib/tracker-github.sh" ||
      missing="$missing github:$op"
    grep -q "^tracker_gitlab_$op()" "$RALPH_PACK_ROOT/.claude/lib/tracker-gitlab.sh" ||
      missing="$missing gitlab:$op"
    grep -q "^tracker_local_$op()" "$RALPH_PACK_ROOT/.claude/lib/tracker-local.sh" ||
      missing="$missing local:$op"
  done
  [ -z "$missing" ] || fail "an operation the dispatcher routes and a backend does not answer:$missing"
}

@test "the frontier is ready-for-agent and unblocked, lowest number first" {
  use_forge github
  remote__two
  forge_seed 3 gamma Gamma <<'T'
# 3 — Gamma

**Status:** ready-for-agent

**Blocked by:** 1
T
  forge_seed 4 delta Delta <<'T'
# 4 — Delta

**Status:** ready-for-human
T

  pack_run 'tracker_frontier'
  assert_success
  assert_equal "$output" "1-alpha
2-beta"

  pack_run 'tracker_mark_resolved 1-alpha; tracker_frontier'
  assert_success
  assert_output_contains "3-gamma"
  refute_output_contains "1-alpha"
}

@test "ids lists every ticket whatever its state, and carries the slug" {
  use_forge github
  remote__two
  pack_run 'tracker_mark_resolved 2-beta; tracker_ids'
  assert_success
  assert_equal "$output" "1-alpha
2-beta"
}

@test "an issue with no Slug field is addressed by its bare number" {
  # What a human opens on the forge, and the id the pack then has for it. A bare
  # number is an id this pack already understands — `tracker__carriers` matches it
  # exactly and `Blocked by: 5` resolves to it — so the answer is that id and not a
  # ticket the pack cannot see.
  use_forge github
  forge_seed 5 '' 'Opened by a human' <<'T'
**Status:** ready-for-agent

**Blocked by:** None
T
  # `forge_seed` writes a `Slug:` line; take it away, which is what an issue
  # nobody opened through the adapter looks like.
  grep -v '^\*\*Slug:\*\*' "$SHIM_STATE/forge/issue.5.body" >"$SHIM_STATE/forge/issue.5.body.n"
  mv -f "$SHIM_STATE/forge/issue.5.body.n" "$SHIM_STATE/forge/issue.5.body"

  pack_run 'tracker_ids'
  assert_success
  assert_equal "$output" "5"

  pack_run 'tracker_field 5 Status'
  assert_equal "$output" "ready-for-agent"
}

# ── the claim ────────────────────────────────────────────────────────────────

@test "a claim is published as the assignee and decided locally" {
  # Both halves of spec §152 in one assertion, because they are one mechanism: the
  # assignee is what a human sees on the forge, and `owner=pid:<n>` is what
  # `claim.sh` can ping — which a login on another host never is.
  use_forge github
  remote__two

  pack_run 'tracker_claim 1-alpha'
  assert_success
  assert_equal "$(forge_field 1 Status)" "claimed"
  assert_equal "$(forge_assignee 1)" "ralph-bot"

  pack_run 'tracker_field 1-alpha Claimed'
  assert_success
  assert_output_contains "owner=pid:"
  assert_output_contains " at=2"

  # And the test-and-set: a second claim on a ticket that is no longer
  # `ready-for-agent` is lost, not taken.
  pack_run 'tracker_claim 1-alpha || printf "lost\n"'
  assert_output_contains "lost"
}

@test "a claim this run left behind is reclaimed at sight, with no backstop at all" {
  # The wedge [12] left open for a remote backend and [18] had to close or
  # foresee: with `CLAIM_TTL` disabled, a claim nothing can ping is never
  # reclaimed. The local record is what closes it for this pack's own runs — the
  # owner is a pid, so `claim_is_held` pings it and finds nothing.
  use_forge github
  remote__two
  set_config CLAIM_TTL 0

  pack_run 'tracker_claim 1-alpha'
  assert_success
  # Rewrite the record as a pid nothing answers for, which is what a crashed run
  # leaves behind. Appended rather than edited: the sidecar is append-only with
  # the last line winning, which is what lets two iterations record two tickets
  # without a lock.
  printf '1-alpha\tclaim\towner=pid:999999 at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    >>"$FEATURE_DIR/.forge-claims"

  pack_run 'claim_reclaim_stale'
  assert_success
  assert_output_contains "1-alpha"
  assert_equal "$(forge_field 1 Status)" "ready-for-agent"
}

@test "an assignee this machine never stamped is waited out, never reclaimed on sight" {
  # The other half of the same decision, and it is the one that must not be
  # "fixed": taking a ticket away from the person it is assigned to is worse than
  # waiting for the backstop. `claim_owner_kind` calls it `foreign`, which since
  # [26] also means the ticket is not charged a retry for having been waited out.
  use_forge github
  remote__two
  set_config CLAIM_TTL 0
  printf 'someone-else\n' >"$SHIM_STATE/forge/issue.1.assignee"
  pack_run 'tracker_mark_resolved 2-beta'

  # The ticket says claimed; the forge says who has it.
  pack_run 'printf "**Status:** claimed\n\n**Blocked by:** None\n" >/dev/null
    tracker_claim 1-alpha >/dev/null 2>&1 || true'
  printf 'someone-else\n' >"$SHIM_STATE/forge/issue.1.assignee"
  rm -f "$FEATURE_DIR/.forge-claims"

  pack_run 'tracker_field 1-alpha Claimed'
  assert_success
  assert_output_contains "owner=assignee:someone-else"

  pack_run 'claim_owner_kind "$(tracker_field 1-alpha Claimed)"'
  assert_equal "$output" "foreign"

  pack_run 'claim_is_held "$(tracker_field 1-alpha Claimed)" && printf "held\n"'
  assert_output_contains "held"
}

@test "resolving clears the claim and the retry counter; re-injecting keeps the counter" {
  # The obligation [26] wrote into the interface, and the one a remote backend
  # recreates by forgetting: a counter kept across a delivery is cumulative over
  # the ticket's whole life, so a ticket delivered green twice is escalated
  # `failed-impl` on its third visit — and nothing goes red over it, because the
  # counter is an entry in the tracker and not a return code.
  use_forge github
  remote__two

  pack_run 'tracker_claim 1-alpha && tracker_bump_failures 1-alpha'
  assert_success
  assert_equal "$output" "1"

  pack_run 'tracker_mark_resolved 1-alpha'
  assert_success
  assert_equal "$(forge_field 1 Failures)" ""
  assert_equal "$(forge_field 1 Claimed)" ""
  assert_equal "$(forge_state 1)" "closed"
  assert_equal "$(forge_assignee 1)" ""

  pack_run 'tracker_bump_failures 2-beta >/dev/null; tracker_mark_ready 2-beta'
  assert_success
  assert_equal "$(forge_field 2 Failures)" "1"

  pack_run 'tracker_clear_failures 2-beta'
  assert_success
  assert_equal "$(forge_field 2 Failures)" ""
}

@test "wontfix drops the escalation reason and the counter, and closes the issue" {
  use_forge github
  remote__two
  pack_run 'tracker_bump_failures 1-alpha >/dev/null
    tracker_mark_escalated 1-alpha too-big'
  assert_success
  assert_equal "$(forge_field 1 Escalation)" "too-big"
  assert_equal "$(forge_state 1)" "open"

  pack_run 'tracker_mark_wontfix 1-alpha'
  assert_success
  assert_equal "$(forge_field 1 Status)" "wontfix"
  assert_equal "$(forge_field 1 Escalation)" ""
  assert_equal "$(forge_field 1 Failures)" ""
  assert_equal "$(forge_state 1)" "closed"
}

# ── how an operation refuses ([71]) ──────────────────────────────────────────

@test "an empty escalation reason is a value, and a missing one is a return code" {
  # The clause `lib/tracker.sh` writes down, on a backend that did not exist when
  # it was written. The empty reason is the sink's ordinary shape — what
  # `capability_propose` opens and what `router__put_back` has to be able to
  # restore — and the missing argument is the caller's bug, refused without ending
  # the caller. A `${2:?}` here would kill a drain that has no subshell left
  # between it and this line.
  use_forge github
  remote__two

  pack_run 'tracker_mark_escalated 1-alpha ""'
  assert_success
  assert_equal "$(forge_field 1 Status)" "ready-for-human"
  # The **absence of the line**, and not an empty field read back. A ticket
  # carrying `**Escalation:**` with nothing after it and a ticket carrying no such
  # line read identically through `tracker_field` — the local backend says so in
  # its own comment — so an assertion on the field value is an assertion that
  # cannot fail. What `router__put_back` has to be able to write is the shape the
  # sink actually has, byte for byte.
  case "$(forge_body 1)" in
    *'**Escalation:**'*) fail "the ticket carries an Escalation line: $(forge_body 1)" ;;
  esac

  pack_run 'set +e
    tracker_mark_escalated 2-beta
    printf "rc=%s\n" "$?"
    printf "the caller is still here\n"'
  assert_success
  assert_output_contains "rc=2"
  assert_output_contains "the caller is still here"
  assert_equal "$(forge_field 2 Status)" "ready-for-agent"
}

@test "an unconfigured remote backend refuses every operation without ending its caller" {
  use_forge github
  remote__two
  set_config TRACKER_REPO ""

  pack_run 'set +e
    for op in tracker_frontier tracker_ids; do
      "$op" >/dev/null 2>&1
      printf "%s=%s\n" "$op" "$?"
    done
    tracker_claim 1-alpha >/dev/null 2>&1
    printf "claim=%s\n" "$?"
    printf "the caller is still here\n"'
  assert_success
  assert_output_contains "tracker_frontier=1"
  assert_output_contains "tracker_ids=1"
  assert_output_contains "claim=1"
  assert_output_contains "the caller is still here"
}

@test "an escalation reason carrying an escape does not cut the ticket in two" {
  # The fragility the pass of 29/07/2026 measured on the local backend and named
  # as this ticket's to inherit: `awk -v v=...` interprets the escapes in the value
  # it is given, so a reason carrying `\n` arrives as a real newline, the field
  # after it falls into the body, and the ticket stops being readable at the point
  # where it was cut. Reachable here because a drain puts back what it pinned off a
  # ticket, and a ticket is prose somebody wrote.
  use_forge github
  remote__two

  pack_run 'tracker_mark_escalated 1-alpha "a\nb"'
  assert_success
  assert_equal "$(forge_field 1 Escalation)" 'a\nb'
  # The field written after it is still a field, which is the half that was
  # silently lost: a real newline in the value pushes it into the body.
  assert_equal "$(forge_field 1 'Blocked by')" "None"
  assert_equal "$(forge_field 1 'Write-surface')" '`src/a.txt`'
}

# ── ids that cannot travel ([37], [48], [64]) ────────────────────────────────

@test "an id this backend hands out is one line, whatever a human put in the slug" {
  # The clause of the interface, answered rather than implemented ([48], [64]).
  # `lib/tracker.sh` says a backend numbering server-side calls
  # `tracker_refuse_name` never and finds nothing at the preflight, and that this
  # is the right answer and not a missing one. What makes it true here is that an
  # id is an integer plus a slug in the rendering the transport already uses: a tab
  # a human types into a `Slug:` field arrives as the two characters `\t`.
  #
  # The half that would otherwise be silent is the ticket itself: it is still on
  # the frontier, still claimable, still readable. Dropping it would be worse than
  # an odd-looking id — a ticket nobody can reach and nothing names.
  use_forge github
  remote__two
  printf '**Status:** ready-for-agent\n\n**Blocked by:** None\n\n**Slug:** a	b\n' \
    >"$SHIM_STATE/forge/issue.2.body"

  pack_run 'tracker_ids'
  assert_success
  assert_equal "$output" '1-alpha
2-a\tb'

  pack_run 'tracker_preflight || true'
  assert_success
  refute_output_contains "unaddressable-name"

  pack_run 'tracker_frontier'
  assert_output_contains '2-a\tb'
  pack_run 'tracker_claim "2-a\tb"; tracker_field "2-a\tb" Status'
  assert_success
  assert_equal "$(forge_field 2 Status)" "claimed"

  # And no sentence of the backend's own, which is the shape [64] removed from the
  # local one: the rendering and the destination of a refused name belong to the
  # interface, so a backend that had something to refuse would call it rather than
  # print.
  ! grep -q 'carries a newline in its name' "$RALPH_PACK_ROOT/.claude/lib/forge.sh" ||
    fail "the backend renders a sentence of its own"
}

@test "a backslash inside a slug is not read as the end of the line it is on" {
  # The escaped body is scanned for the separator, which is the two characters
  # `\n` — and a value that itself holds a backslash followed by the letter `n`
  # holds those same two characters. Without folding the escaped backslashes
  # first, the scan stopped **inside** the value: the slug came out as `a\` and
  # the ticket got an id no reader of this tracker would ever meet.
  #
  # A value nobody would type, and reachable all the same: the `Slug:` line of an
  # issue is prose a human edits on the forge, and this is a Windows path away.
  use_forge github
  printf '**Status:** ready-for-agent\n\n**Slug:** a\\nb\n' \
    >"$SHIM_STATE/forge/issue.1.body"
  printf 'x\n' >"$SHIM_STATE/forge/issue.1.title"
  printf 'open\n' >"$SHIM_STATE/forge/issue.1.state"
  : >"$SHIM_STATE/forge/issue.1.assignee"
  printf '1\n' >>"$SHIM_STATE/forge/order"

  # The whole slug, in the rendering the transport uses: the backslash it carries
  # travels as `\\`, which is what keeps the id one line.
  pack_run 'tracker_ids'
  assert_success
  assert_equal "$output" '1-a\\nb'

  # And the ticket is still reachable under it, which is the half that would
  # otherwise be silent: a truncated id resolves to a number that is still there,
  # so nothing goes red and the tracker just answers about a name nobody holds.
  pack_run "tracker_field '$output' Status"
  assert_success
  assert_equal "$output" "ready-for-agent"
}

@test "renumber answers the id it was given, because a forge numbers server-side" {
  # Written down rather than deduced from the fact that it works ([27]). The
  # question underneath still has an answer: a number is unique in a repository, so
  # two tickets never claim one identifier here.
  use_forge github
  remote__two
  pack_run 'tracker_renumber 1-alpha'
  assert_success
  assert_equal "$output" "1-alpha"
}

# ── creating ────────────────────────────────────────────────────────────────

@test "open_unique opens once and answers nothing the second time" {
  # [47]'s operation, on a backend that has to say what serialises creation for
  # it. The question and the write fall on the same side of one guard — a local
  # one, which is what this pack has and all it claims (spec §213).
  use_forge github
  remote__two

  pack_run 'printf "**Status:** ready-for-human\n\n**Blocked by:** None\n" |
    tracker_open_unique cap-thing "A capability"'
  assert_success
  assert_equal "$output" "3-cap-thing"

  pack_run 'printf "**Status:** ready-for-human\n\n**Blocked by:** None\n" |
    tracker_open_unique cap-thing "A capability"'
  assert_success
  assert_equal "$output" ""

  pack_run 'tracker_ids'
  assert_equal "$output" "1-alpha
2-beta
3-cap-thing"
}

@test "an opened ticket carries the slug in its id, which is what two readers of [65] need" {
  # `playthrough__opened_slug` and `playthrough__strangers` both read the slug out
  # of the id **text**. A backend numbering server-side and dropping the slug would
  # report every duplicate as a ticket this run never opened, and would name none
  # of the wiring tickets it did not count — the silence [65] closed, reopened from
  # the backend side.
  use_forge github
  remote__two
  pack_run 'printf "**Status:** ready-for-human\n\n**Blocked by:** None\n" |
    tracker_open_ticket playthrough-wiring-a-hole "A hole"'
  assert_success
  assert_equal "$output" "3-playthrough-wiring-a-hole"

  pack_run 'tracker_ids | grep -- "-playthrough-wiring-"'
  assert_success
  assert_output_contains "3-playthrough-wiring-a-hole"
}

@test "a note is a comment on the issue, and the ticket is not rewritten for it" {
  use_forge github
  remote__two
  pack_run 'printf "re-sliced out of 1-alpha\n" | tracker_append_note 1-alpha'
  assert_success
  [ -n "$(forge_notes 1)" ] || fail "no comment reached the issue"
  case "$(forge_notes 1)" in
    *"re-sliced out of 1-alpha"*) ;;
    *) fail "the comment is not what was written: $(forge_notes 1)" ;;
  esac
}

# ── the receipt is the request ([10], [70]) ──────────────────────────────────

@test "the receipt is a request whose branch is pushed, and no ticket is written for it" {
  # Three things at once, and the third is the one nothing else would catch. The
  # request carries the tree, which is what makes `git show <sha>` in the receipt
  # resolve for somebody who does not have this repository — [10] refused inlining
  # the diff and that has not changed. And the adapter writes **no ticket**: an
  # adapter that wrote a link or a label while emitting a receipt would owe the
  # register of [13] an entry it cannot make, `emit_receipt` being exempt from it
  # by construction.
  use_forge github
  remote__two
  forge_remote off

  local before
  before="$(forge_body 1)"
  pack_run 'printf "## Verdicts\n\ntests green\n" | tracker_emit_receipt 1-alpha'
  assert_success
  assert_equal "$output" "https://forge.test/r/1"

  assert_equal "$(forge_body 1)" "$before"
  case "$(forge_remote_refs)" in
    *"refs/heads/ralph-1-alpha"*) ;;
    *) fail "the branch the receipt is about was not pushed: $(forge_remote_refs)" ;;
  esac
  case "$(forge_request_body 1)" in
    *"tests green"*) ;;
    *) fail "the receipt is not in the request: $(forge_request_body 1)" ;;
  esac
  case "$(forge_request_body 1)" in
    *"#1"*) ;;
    *) fail "the request does not name the issue, so the forge links nothing" ;;
  esac

  pack_run 'tracker_receipt_path 1-alpha'
  assert_success
  assert_equal "$output" "https://forge.test/r/1"
}

@test "one request per ticket, opened by the mark and rewritten by the emit" {
  use_forge github
  remote__two
  forge_remote auto
  forge_ci success

  pack_run 'tracker_claim 1-alpha && tracker_mark_resolved 1-alpha'
  assert_success
  pack_run 'printf "the receipt\n" | tracker_emit_receipt 1-alpha'
  assert_success

  assert_equal "$(forge_requests | grep -c .)" "1"
  case "$(forge_request_body 1)" in
    *"the receipt"*) ;;
    *) fail "the request was not rewritten with the receipt" ;;
  esac
}

@test "a receipt this machine never emitted is nothing to read, not a path that fails" {
  use_forge github
  remote__two
  pack_run 'set +e; tracker_receipt_path 1-alpha; printf "rc=%s\n" "$?"'
  assert_success
  assert_output_contains "rc=1"
  assert_equal "$(printf '%s\n' "$output" | grep -vc 'rc=')" "0"
}

@test "a backend whose receipts are requests is named once by the run, and by the dossier" {
  # [70] provisioned the refusal and left the price to this ticket. The price is
  # that nothing here attests a remote receipt at all — a request is an object a
  # session reaches over the network — so the run says it once and the dossier
  # stops printing a reserve written for a file in the main tree.
  use_forge github
  remote__two

  pack_run 'set +e; tracker_receipt_dir; printf "rc=%s\n" "$?"'
  assert_output_contains "rc=1"

  pack_run 'forensic_uncovered || printf "(nothing to say)\n"'
  assert_success
  assert_output_contains "does not keep audit receipts in a directory"
  refute_output_contains "(nothing to say)"
}

# ── the tracker nothing restores ([21] on a remote backend) ──────────────────

@test "a backend that keeps no tickets in this tree is named once, and vouches for nothing" {
  # The silence [21] could not see, because the only backend that existed kept its
  # tickets here: two git trees of a directory that does not exist are both the
  # empty tree, so the guard compared nothing and **returned zero**. It still
  # returns zero — refusing on every window would make every iteration of a remote
  # backend red, which is no backend at all — and the run now says so once.
  use_forge github
  remote__two

  pack_run 'set +e; tracker_tickets_dir; printf "rc=%s\n" "$?"'
  assert_output_contains "rc=1"

  pack_run 'forensic_uncovered || printf "(nothing to say)\n"'
  assert_success
  assert_output_contains "nothing here restores what a session writes in the tracker"

  pack_run 'failures__gap() { printf "GAP %s\n" "$*"; }
    set +e
    failures_protect_tracker 1-alpha "" ""
    printf "rc=%s\n" "$?"'
  assert_success
  assert_output_contains "rc=0"
  refute_output_contains "GAP"
}

@test "the local backend still restores what a session wrote, and still refuses to vouch blind" {
  # The paired witness of the branch above: a guard that took the remote branch on
  # every backend would be a guard that stopped guarding, and every existing
  # assertion about it would go on passing.
  use_tickets 01-alpha
  pack_run 'tracker_tickets_dir'
  assert_success
  assert_output_contains ".scratch/$RALPH_TEST_FEATURE/issues"

  pack_run 'failures__gap() { printf "GAP %s\n" "$*"; }
    set +e
    failures_protect_tracker 01-alpha "" ""
    printf "rc=%s\n" "$?"'
  assert_success
  assert_output_contains "rc=1"
  assert_output_contains "GAP"
}

# ── what the scope-guard does with a tracker it cannot enumerate (AC 5) ──────

@test "a backend that cannot list its tickets escalates the scope-guard, it does not retry it" {
  # The failure mode [05] wrote into this ticket: `tracker__dispatch` answers `3`
  # for an operation a backend does not implement, and `gate__surface_owner`
  # iterated over an empty list and concluded that nobody declared the path. Every
  # drift against a contract then came back `internal` — retryable — so the ticket
  # burned its whole budget against a tracker nobody could read.
  use_tickets 01-alpha 07-overlaps-alpha
  mkdir -p "$PROJECT_DIR/src"
  local class="$RALPH_TEST_DIR/class"

  pack_run 'tracker_ids() { return 3; }
    mkdir -p src
    base="$(gate_tree_snapshot)"
    printf "spill\n" >src/eta.txt
    now="$(gate_tree_snapshot)"
    set +e
    gate__scope_guard 01-alpha "$base" "$now" '"'$class'"'
    printf "rc=%s\n" "$?"'
  assert_output_contains "nothing here can say whose write-surface it is"
  assert_output_contains "rc=1"
  assert_equal "$(cat "$class")" "contract"
}

@test "the same guard still tells a stray write from a drift when the tracker answers" {
  # The bound of the rule above, and it is what keeps the escalation from becoming
  # the only classification: a tracker that answers must go on producing the two it
  # always did.
  use_tickets 01-alpha 07-overlaps-alpha
  mkdir -p "$PROJECT_DIR/src"
  local class="$RALPH_TEST_DIR/class"

  pack_run 'gate__surface_owner "src/alpha.txt" 07-overlaps-alpha'
  assert_success
  assert_equal "$output" "01-alpha"

  pack_run 'set +e; gate__surface_owner "nobody/at/all.txt" 01-alpha; printf "rc=%s\n" "$?"'
  assert_output_contains "rc=1"

  pack_run 'mkdir -p src
    base="$(gate_tree_snapshot)"
    printf "spill\n" >src/eta.txt
    now="$(gate_tree_snapshot)"
    set +e
    gate__scope_guard 01-alpha "$base" "$now" '"'$class'"'
    printf "rc=%s\n" "$?"'
  assert_output_contains "inside the write-surface of 07-overlaps-alpha"
  assert_equal "$(cat "$class")" "contract"
}

# ── wait_ci ──────────────────────────────────────────────────────────────────

@test "wait_ci green closes the ticket, red escalates it and refuses" {
  use_forge github
  remote__two
  forge_remote auto

  forge_ci success
  pack_run 'tracker_claim 1-alpha && tracker_mark_resolved 1-alpha'
  assert_success
  assert_equal "$(forge_field 1 Status)" "resolved"
  assert_equal "$(forge_state 1)" "closed"

  forge_ci failure
  pack_run 'set +e; tracker_claim 2-beta >/dev/null; tracker_mark_resolved 2-beta; printf "rc=%s\n" "$?"'
  assert_success
  assert_output_contains "rc=1"
  assert_equal "$(forge_field 2 Status)" "ready-for-human"
  assert_equal "$(forge_field 2 Escalation)" "ci-red"
  assert_equal "$(forge_state 2)" "open"
}

@test "auto passes a project with no pipeline; on escalates it" {
  # The two readings of "on by default if CI is detected", and why they are not
  # the same key. `auto` is the detection: no pipeline means this project has no
  # CI and the gate's verdict stands. `on` is a project that said it has one, and a
  # request showing none is then a fact for a human rather than a green.
  use_forge github
  remote__two
  forge_remote auto
  forge_ci ''

  pack_run 'tracker_claim 1-alpha && tracker_mark_resolved 1-alpha'
  assert_success
  assert_equal "$(forge_field 1 Status)" "resolved"

  forge_remote on
  pack_run 'set +e; tracker_claim 2-beta >/dev/null; tracker_mark_resolved 2-beta; printf "rc=%s\n" "$?"'
  assert_output_contains "rc=1"
  assert_equal "$(forge_field 2 Escalation)" "ci-absent"
}

@test "a pipeline status this pack does not recognise is not a green" {
  # [59]'s rule applied to a word rather than to a list: a status neither forge
  # documents — a new state, a proxy answering something else — read as "there is
  # no CI" would pass a green through a machine that said nothing. It is
  # `unknown`, and `unknown` escalates.
  use_forge github
  remote__two
  forge_remote on
  forge_ci 'something-new'

  pack_run 'set +e; tracker_claim 1-alpha >/dev/null; tracker_mark_resolved 1-alpha; printf "rc=%s\n" "$?"'
  assert_output_contains "rc=1"
  assert_equal "$(forge_field 1 Status)" "ready-for-human"
  assert_equal "$(forge_field 1 Escalation)" "ci-unreachable"
}

@test "wait_ci off never opens a request and never asks for a pipeline" {
  use_forge github
  remote__two
  pack_run 'tracker_claim 1-alpha && tracker_mark_resolved 1-alpha'
  assert_success
  assert_equal "$(forge_field 1 Status)" "resolved"
  assert_equal "$(forge_requests | grep -c .)" "0"
  case "$(forge_calls)" in
    *"/status"* | *"/pipelines"*) fail "the forge was asked about CI with WAIT_CI=off" ;;
  esac
}

@test "a request that cannot be opened is not a green, it is an escalation" {
  # `wait_ci` on and no remote to push to: the integration form the project asked
  # for could not be applied, so the ticket is not resolved. What this costs is
  # named rather than hidden — `loop.sh` does not read this operation's status, so
  # `run.log` says `resolved` while the tracker says `ready-for-human`, and the
  # tracker is the authority every later scan reads.
  use_forge github
  remote__two
  set_config WAIT_CI on

  pack_run 'set +e; tracker_claim 1-alpha >/dev/null; tracker_mark_resolved 1-alpha; printf "rc=%s\n" "$?"'
  assert_output_contains "rc=1"
  assert_equal "$(forge_field 1 Status)" "ready-for-human"
  assert_equal "$(forge_field 1 Escalation)" "ci-unreachable"
}

# ── the transport ────────────────────────────────────────────────────────────

@test "a read is asked again before it is given up on, and a write is not" {
  # The asymmetry is the point. A `GET` is idempotent, so a second attempt costs a
  # request and buys a night: the pilot reads the frontier through a heredoc
  # command substitution, so a listing that refused once reaches it as an empty
  # frontier — which is what starts the terminal value gate. A `POST` retried after
  # a timeout is a ticket opened twice, which no caller can undo.
  use_forge github
  remote__two

  forge_answer_status 500
  pack_run 'tracker_ids'
  assert_success
  assert_equal "$output" "1-alpha
2-beta"
  assert_equal "$(forge_calls | grep -c '^GET')" "2"

  forge_answer_status 200 500
  pack_run 'set +e; tracker_mark_ready 1-alpha; printf "rc=%s\n" "$?"'
  assert_output_contains "rc=1"
  assert_equal "$(forge_calls | grep -c '^PATCH')" "1"
}

@test "a tracker that could not be listed is not an empty frontier" {
  use_forge github
  remote__two
  forge_answer_status 404 404 404 404

  pack_run 'set +e; tracker_frontier; printf "rc=%s\n" "$?"'
  assert_output_contains "rc=1"
  assert_output_contains "this is not an empty frontier"

  forge_answer_status 404 404 404 404
  pack_run 'set +e; tracker_ids; printf "rc=%s\n" "$?"'
  assert_output_contains "rc=1"
}

@test "the JSON reader refuses what it cannot parse rather than reading part of it" {
  # Where this parts company with `budget__window`, which prints nothing on a
  # figure it cannot read: that one reads a number off an undocumented endpoint,
  # and this one carries the text of a ticket. A value guessed at here is a ticket
  # rewritten.
  use_forge github
  pack_run 'set +e; printf "{\"a\": tru}" | forge_json; printf "rc=%s\n" "$?"'
  assert_output_contains "rc=1"

  pack_run 'set +e; printf "{\"a\":\"\\\\uCAFE\"}" | forge_json; printf "rc=%s\n" "$?"'
  assert_output_contains "rc=1"

  pack_run 'printf "[{\"a\":\"x\\\\ny\",\"b\":[1,2]},{\"c\":null}]" | forge_json'
  assert_success
  assert_output_contains "0.a	x\\ny"
  assert_output_contains "0.b.1	2"
}

# ── gitlab ───────────────────────────────────────────────────────────────────

@test "gitlab speaks its own dialect and produces the same transitions" {
  # `iid` and not `id`, `description` and not `body`, `state_event` and not
  # `state`, a numeric assignee and not a login. Four differences that are not
  # naming, exercised together because a table read wrong is a backend that quietly
  # writes the wrong field.
  use_forge gitlab
  remote__two
  forge_remote auto
  forge_ci success

  pack_run 'tracker_claim 1-alpha'
  assert_success
  assert_equal "$(forge_field 1 Status)" "claimed"
  assert_equal "$(forge_assignee 1)" "ralph-bot"

  pack_run 'tracker_mark_resolved 1-alpha'
  assert_success
  assert_equal "$(forge_field 1 Status)" "resolved"
  assert_equal "$(forge_state 1)" "closed"

  pack_run 'tracker_mark_ready 1-alpha'
  assert_success
  assert_equal "$(forge_state 1)" "opened"

  # The lookup that a login-based forge never makes, made once.
  assert_equal "$(forge_calls | grep -c '/users?username=')" "1"
}

# ── the same scenario, the same transitions ([18]'s fourth AC) ───────────────

# One scenario, written against the adapter interface and nothing else, printing
# what a reader of the tracker would observe. Ids are printed by their slug: the
# number is the backend's business — a file called `01-alpha.md` on one and issue
# `1` on the other — and a scenario that compared them would be comparing the one
# thing the two backends are entitled to differ on.
remote__scenario() {
  cat <<'SCENARIO'
set +e
slug() { printf '%s\n' "${1#*-}"; }
say() { printf '%s %s\n' "$1" "$2"; }
first="$(tracker_frontier | sed -n 1p)"
say frontier-first "$(slug "$first")"
tracker_claim "$first" >/dev/null 2>&1
say status-after-claim "$(tracker_field "$first" Status)"
say frontier-after-claim "$(tracker_frontier | sed -n 1p | sed 's/^[0-9]*-//')"
tracker_bump_failures "$first" >/dev/null 2>&1
say failures "$(tracker_field "$first" Failures)"
tracker_mark_resolved "$first" >/dev/null 2>&1
say status-after-resolve "$(tracker_field "$first" Status)"
say failures-after-resolve "$(tracker_field "$first" Failures)"
second="$(tracker_frontier | sed -n 1p)"
say frontier-second "$(slug "$second")"
tracker_mark_escalated "$second" too-big >/dev/null 2>&1
say status-after-escalate "$(tracker_field "$second" Status)"
say escalation "$(tracker_field "$second" Escalation)"
tracker_mark_ready "$second" >/dev/null 2>&1
say status-after-ready "$(tracker_field "$second" Status)"
say escalation-after-ready "$(tracker_field "$second" Escalation)"
opened="$(printf '**Status:** ready-for-human\n\n**Blocked by:** None\n' |
  tracker_open_unique cap-thing 'A capability')"
say opened "$(slug "$opened")"
again="$(printf '**Status:** ready-for-human\n\n**Blocked by:** None\n' |
  tracker_open_unique cap-thing 'A capability')"
say opened-again "[$again]"
tracker_block_on "$second" 3 >/dev/null 2>&1
say blocked-by "$(tracker_field "$second" 'Blocked by')"
say frontier-final "$(tracker_frontier | sed 's/^[0-9]*-//' | tr '\n' ',')"
SCENARIO
}

@test "the same scenario on local and on a remote backend observes the same transitions" {
  # AC 4 of [18], and the reason the state model of `lib/forge.sh` keeps the pack's
  # fields in the issue **body** rather than translating them into labels: this
  # comparison is what makes "the loop stays agnostic" a measurement instead of a
  # claim.
  local script="$RALPH_TEST_DIR/scenario.sh"
  remote__scenario >"$script"

  use_tickets 01-alpha 02-beta
  pack_run ". '$script'"
  assert_success
  local on_local="$output"

  # A second project, from scratch: the teardown takes the whole test directory
  # with it, the script included, so it is written again under the new one.
  harness_teardown
  harness_setup
  script="$RALPH_TEST_DIR/scenario.sh"
  remote__scenario >"$script"
  use_forge github
  remote__two
  pack_run ". '$script'"
  assert_success
  local on_remote="$output"

  [ "$on_local" = "$on_remote" ] || fail "the two backends observe different transitions:
--- local ---
$on_local
--- github ---
$on_remote"
}

# ── what the human sink says about a receipt that is not in this tree ────────

@test "the dossier prints the reserve written for a remote receipt, not the one for a file" {
  # [70] left this sentence to be re-read here, and it was **false** on this
  # backend: "a receipt lives in the main tree, which is not the worktree a
  # scope-guard compares" describes a file, and the receipt of a remote backend is
  # a pull request. Which reserve to print is asked of the adapter, exactly as the
  # receipt's location is — a drain deciding it from the shape of the string would
  # be a second author for a layout only the backend knows.
  use_forge github
  forge_seed 1 decision 'For the drain' <<'T'
# 1 — For the drain

**Status:** ready-for-human

**Escalation:** decision

**Write-surface:** `src/one.txt`

**Blocked by:** None
T
  forge_remote off
  pack_run 'printf "## Verdicts\n" | tracker_emit_receipt 1-decision >/dev/null
    router_pin 1-decision
    router_dossier 1-decision'
  assert_success
  assert_output_contains "receipt  https://forge.test/r/1"
  assert_output_contains "not a path in this repository"
  assert_output_contains "reaches over the network"
  refute_output_contains "not the worktree a scope-guard compares"
  assert_output_contains "Read them, do not rely on them."
}

@test "the same dossier on the local backend still says what a file receipt is" {
  # The paired witness. A dossier that took the remote branch on every backend
  # would print a caveat about a network for a document sitting in the main tree,
  # and every existing assertion about it would go on passing.
  use_tickets 01-alpha
  cat >"$TRACKER_DIR/20-decision.md" <<'T'
# 20 — For the drain

**Status:** ready-for-human

**Escalation:** decision

**Write-surface:** `src/one.txt`

**Blocked by:** None
T
  mkdir -p "$PROJECT_DIR/receipts/$RALPH_TEST_FEATURE"
  printf '# Receipt\n' >"$PROJECT_DIR/receipts/$RALPH_TEST_FEATURE/20-decision.md"
  harness__commit "test: a ticket for the sink"

  pack_run 'router_pin 20-decision; router_dossier 20-decision'
  assert_success
  assert_output_contains "not the worktree a scope-guard compares"
  refute_output_contains "not a path in this repository"
}

# ── the run the fakes above do not stage ─────────────────────────────────────
#
# Every test up to here calls the adapter. This one calls `loop.sh`, which is the
# claim AC 1 actually makes — "the loop stays agnostic" is a property of a run and
# not of a function. What it exercises that nothing above does: the pilot's
# preflight, the frontier scan, the claim, a real session in a real worktree, the
# gate, the durable commit, the fold, the mark, the audit receipt, and the terminal
# value gate — all of them against a tracker that is not a directory.

remote__session_writing() {
  local target
  {
    printf '#!/usr/bin/env bash\n'
    for target in "$@"; do
      printf 'mkdir -p "$(dirname %s)" && printf "written\\n" >>%s\n' "$target" "$target"
    done
    printf '%s\n' \
      "echo '{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"num_turns\":1,\"total_cost_usd\":0.02}'"
  } | script_claude
}

@test "a whole run grinds a ticket on a remote backend and closes it on the forge" {
  use_forge github
  set_config STERILE_K 1
  set_config PLAYTHROUGH off
  forge_seed 1 alpha Alpha <<'T'
# 1 — Alpha

**What to build:** Write the alpha marker file.

**Status:** ready-for-agent

**Blocked by:** None

**Write-surface:** `src/alpha.txt`
T
  remote__session_writing src/alpha.txt

  run_loop
  assert_equal "$(forge_field 1 Status)" "resolved"
  assert_equal "$(forge_state 1)" "closed"
  assert_equal "$(forge_field 1 Claimed)" ""
  # The work reached the branch, which is the half a marked ticket does not prove
  # ([35]): a tracker entry with nothing behind it is this pack's own definition
  # of a false delivered.
  assert_file_contains "$PROJECT_DIR/src/alpha.txt" "written"

  # And the run said, once, what nothing in it witnesses on this backend. On the
  # run's own output and not in `run.log`, which is where [70] put the sentence it
  # wrote for the same channel: `loop_log` prints, and the journal carries one
  # structured line per iteration. The drain says the other half of it, per ticket,
  # in the reserve of `router_dossier`.
  assert_output_contains "does not keep audit receipts in a directory"
  assert_output_contains "nothing here restores what a session writes in the tracker"
  assert_equal "$(printf '%s\n' "$output" | grep -c 'does not keep audit receipts')" "1"
}

@test "a run whose session writes outside its surface escalates on a remote backend too" {
  # The scope-guard on a tracker that is not a directory: the write-surface it
  # judges against is read through the adapter, and the classification of an
  # overflow is the same one it makes on a file.
  use_forge github
  set_config STERILE_K 1
  set_config PLAYTHROUGH off
  set_config RETRY_N 1
  forge_seed 1 alpha Alpha <<'T'
# 1 — Alpha

**Status:** ready-for-agent

**Blocked by:** None

**Write-surface:** `src/alpha.txt`
T
  remote__session_writing src/alpha.txt src/elsewhere.txt

  run_loop
  assert_output_contains "src/elsewhere.txt"
  case "$(forge_field 1 Status)" in
    ready-for-agent | ready-for-human) ;;
    *) fail "a session that overflowed its surface left the ticket $(forge_field 1 Status)" ;;
  esac
}
