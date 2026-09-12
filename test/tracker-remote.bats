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

@test "a listing the forge refused is not a free slug, and open_unique refuses" {
  # [78]. The refusal needs no outage since [76]: a tracker that does not end
  # within `FORGE_PAGES` refuses **every** listing, at every pass, so the empty
  # list `forge__slug_taken` used to read out of its own heredoc said "nobody
  # carries cap-thing" on a tracker holding it — and every run reopened it.
  #
  # `FORGE_PAGE 2` and `FORGE_PAGES 1` put that ceiling on the two issues already
  # seeded, which is the cheapest way to stage this without simulating a failure.
  use_forge github
  set_config FORGE_PAGE 2
  set_config FORGE_PAGES 1
  remote__two

  pack_run 'RALPH_TRACKER_LOG="'"$RALPH_TEST_DIR"'/register"
    : >"$RALPH_TRACKER_LOG"
    set +e
    printf "**Status:** ready-for-human\n\n**Blocked by:** None\n" |
      tracker_open_unique cap-thing "A capability"
    printf "rc=%s\n" "$?"
    printf "register:[%s]\n" "$(tr "\n" " " <"$RALPH_TRACKER_LOG")"'
  # The status is the channel, because stdout has none left: an empty stdout is
  # already "one is waiting", which is a success. It survives `tracker__dispatch`,
  # so the refusal is what a caller of the *interface* reads.
  assert_output_contains "rc=1"
  # And it says which slug and why, on the run's stderr, without anybody counting
  # tickets before and after.
  assert_output_contains "the tracker could not be listed"
  assert_output_contains "refusing to open \"cap-thing\""
  refute_output_contains "3-cap-thing"
  # Nothing opened, read off the forge itself and not through the pack.
  [ -z "$(forge_state 3)" ] || fail "a ticket was opened behind a listing nobody could read"
  # And nothing written to the register of [13]: a creation that did not happen is
  # not a write for the two guards over `issues/` to exempt.
  assert_output_contains "register:[]"
}

@test "the same slug under a ceiling that fits still opens once and answers nothing twice" {
  # The paired witness: without it, "it refused" could be an `open_unique` that
  # refuses whatever the ceiling. Same tracker, same slug, one number changed.
  use_forge github
  set_config FORGE_PAGE 2
  set_config FORGE_PAGES 4
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

# ── pagination ───────────────────────────────────────────────────────────────
#
# A tracker is not the first page of it ([76]). Two defects were stacked here and
# the second was hidden by the first: the page bound never counted the first
# record of a page, so page two was never asked for on any tracker — and when it
# was, the records of page two landed on the array indices of page one and
# overwrote them.
#
# The fake forge pages for real (`test/helpers/shims/forge-api` reads `page` and
# `per_page` off the URL), which is the half of this that had to be built first:
# the fake it replaced held fewer tickets than a page and could not make the pack
# ask for a second one.

@test "a tracker of more than one full page is the whole tracker" {
  # The shipped page — a hundred — and a tracker that does not fit in it. This is
  # the only test here that measures the bound as it ships; the ones below drive
  # it with FORGE_PAGE, which is cheaper and proves something narrower.
  use_forge github
  forge_seed_many 1 101

  pack_run 'tracker_ids'
  assert_success
  assert_equal "$(printf '%s\n' "$output" | grep -c .)" "101"
  assert_output_contains "1-bulk-1"
  assert_output_contains "100-bulk-100"
  assert_output_contains "101-bulk-101"

  # And the forge was really asked twice: a hundred and one ids out of one request
  # would mean the fake stopped paging, not that the pack did.
  assert_equal "$(forge_calls | grep -c 'page=2')" "1"
}

@test "the page after a full one does not overwrite the page before it" {
  # `FORGE_PAGE 2` says a full page holds two records, which is what the fake then
  # serves. Four tickets are two pages, and every one of them has to survive.
  use_forge github
  set_config FORGE_PAGE 2
  remote__two
  forge_seed 3 gamma Gamma <<'T'
# 3 — Gamma

**Status:** ready-for-agent

**Blocked by:** None

**Write-surface:** `src/c.txt`
T
  forge_seed 4 delta Delta <<'T'
# 4 — Delta

**Status:** ready-for-agent

**Blocked by:** None

**Write-surface:** `src/d.txt`
T

  pack_run 'tracker_ids'
  assert_success
  assert_equal "$output" "1-alpha
2-beta
3-gamma
4-delta"

  pack_run 'tracker_frontier'
  assert_success
  assert_equal "$output" "1-alpha
2-beta
3-gamma
4-delta"
}

@test "a ticket of the first page is still readable when there is a second" {
  # The witness for the identity half, kept apart from the one above on purpose:
  # a listing where page two lands on page one's indices answers "no such ticket"
  # for 1-alpha while `tracker_ids` merely comes back short — one test would read
  # the two defects as one missing ticket.
  use_forge github
  set_config FORGE_PAGE 2
  remote__two
  forge_seed 3 gamma Gamma <<'T'
# 3 — Gamma

**Status:** ready-for-agent

**Blocked by:** None

**Write-surface:** `src/c.txt`
T
  forge_seed 4 delta Delta <<'T'
# 4 — Delta

**Status:** ready-for-agent

**Blocked by:** None

**Write-surface:** `src/d.txt`
T

  pack_run 'tracker_field 1-alpha Write-surface'
  assert_success
  assert_output_contains "src/a.txt"

  pack_run 'tracker_read_ticket 1-alpha'
  assert_success
  assert_output_contains "# 1 — Alpha"

  pack_run 'tracker_read_ticket 4-delta'
  assert_success
  assert_output_contains "# 4 — Delta"
}

@test "an issue served on two pages is one ticket and not two" {
  # What a forge answers when an issue is opened between the two requests: the
  # window slides and the last issue of page one comes back as the first of page
  # two. Identified by its place in an array that is two tickets with one number.
  use_forge github
  set_config FORGE_PAGE 2
  remote__two
  forge_seed 3 gamma Gamma <<'T'
# 3 — Gamma

**Status:** ready-for-agent

**Blocked by:** None

**Write-surface:** `src/c.txt`
T
  forge_serve_twice 2

  pack_run 'tracker_ids'
  assert_success
  assert_equal "$output" "1-alpha
2-beta
3-gamma"
}

@test "the per_page asked for and the bound a page is measured against are one number" {
  # Two numbers written in two files drift, and the drift is silent both ways: a
  # per_page above the bound asks for pages for ever, one below stops on a full
  # page and calls it the tracker. So the URL is asserted, not the ids — a table
  # still saying 100 would answer the whole tracker on page one and be *right*.
  use_forge github
  set_config FORGE_PAGE 2
  remote__two

  local calls
  pack_run 'tracker_ids'
  assert_success
  # Read into a variable rather than asserted through `$output`, which the `run`
  # above owns: a negative assertion aimed at the wrong output can never fail.
  calls="$(forge_calls)"
  assert_equal "$(printf '%s\n' "$calls" | grep -c 'per_page=2')" "2"
  case "$calls" in
    *per_page=100*) fail "the listing asked for a page of 100 while measuring against 2: $calls" ;;
  esac
}

@test "a listing stopped by the page ceiling refuses instead of coming back short" {
  # [59]'s rule one layer up: a short list is not a shorter tracker, it is a
  # tracker with tickets missing from it, and no caller can tell the two apart.
  use_forge github
  set_config FORGE_PAGE 1
  set_config FORGE_PAGES 2
  remote__two
  forge_seed 3 gamma Gamma <<'T'
# 3 — Gamma

**Status:** ready-for-agent

**Blocked by:** None
T

  pack_run 'set +e; tracker_ids; printf "rc=%s\n" "$?"'
  assert_output_contains "rc=1"
  assert_output_contains "refusing a listing that would be missing tickets"
  refute_output_contains "1-alpha"
}

@test "the same tracker under a ceiling that fits is listed whole" {
  # The paired witness: without it, "it refused" could be a listing that refuses
  # whatever the ceiling. A separate @test because a `pack_run` runs the fake.
  use_forge github
  set_config FORGE_PAGE 1
  set_config FORGE_PAGES 4
  remote__two
  forge_seed 3 gamma Gamma <<'T'
# 3 — Gamma

**Status:** ready-for-agent

**Blocked by:** None
T

  pack_run 'tracker_ids'
  assert_success
  assert_equal "$output" "1-alpha
2-beta
3-gamma"
}

# ── the two refusals the loop used to swallow ────────────────────────────────
#
# [74], and the reason these scenarios live here rather than in the canary: both
# defects are in `loop.sh`, and neither is reachable on a backend that is a
# directory this process owns. A local `frontier` cannot refuse and a local
# `mark_resolved` almost never does — which is exactly why the loop read both of
# them through constructions that throw a status away, and why nothing noticed
# until an adapter that publishes existed.

@test "a marking the forge refused is not a resolved line in the journal" {
  # The shipped integration form and a pipeline that comes back red: the adapter
  # escalates the ticket and refuses. This is a night's most ordinary refusal on
  # this backend, not an incident — and the loop used to write `resolved` behind
  # it without a glance, so the tracker said `ready-for-human` and `run.log` said
  # `resolved` about the same ticket in the same minute.
  use_forge github
  set_config PLAYTHROUGH off
  forge_seed 1 alpha Alpha <<'T'
# 1 — Alpha

**What to build:** Write the alpha marker file.

**Status:** ready-for-agent

**Blocked by:** None

**Write-surface:** `src/alpha.txt`
T
  forge_remote auto
  forge_ci failure
  remote__session_writing src/alpha.txt

  run_loop
  # The tracker is the authority, and it is where the adapter left it.
  assert_equal "$(forge_field 1 Status)" "ready-for-human"
  assert_equal "$(forge_field 1 Escalation)" "ci-red"
  # And the journal now says the same thing about the same minute. Asserted on
  # the tabulated pair and not on the word alone: `resolved` appears in this file
  # for other reasons, and a refutation that matched one of those would pass for
  # the wrong reason.
  assert_file_contains "$FEATURE_DIR/run.log" "$(printf '1-alpha\tnot-marked')"
  refute_file_contains "$FEATURE_DIR/run.log" "$(printf '1-alpha\tresolved')"
  # Said once on the run's own output too, with what the tracker answers *now* —
  # the sentence a human needs is "which of the two refusals was it".
  assert_output_contains "refused to mark it resolved"
  # The work is on the branch all the same, and the failure policy stayed out of
  # it: nothing was wrong with this iteration, so nothing of this ticket's retry
  # budget is spent on somebody else's refusal.
  assert_file_contains "$PROJECT_DIR/src/alpha.txt" "written"
  assert_equal "$(forge_field 1 Failures)" ""
  # And the document this route already owed: the same audit receipt a `resolved`
  # iteration produces — it emitted one before this outcome existed, under a word
  # that was false — with a summary that now says what happened. On this backend
  # the receipt is the pull request's description.
  assert_equal "$(forge_request_body 1 | grep -c 'refused to mark the ticket resolved')" "1"
  assert_equal "$(forge_request_body 1 | grep -c 'outcome: `not-marked`')" "1"
}

@test "a listing the forge refused does not start the terminal value gate" {
  # The value gate is the one session entitled to close a feature, and an empty
  # frontier is the only thing that starts it. A listing that refused is not one.
  #
  # Since [76] it is not a network blip either, and that is what this scenario
  # stages: a repository past the pack's own page ceiling refuses **every**
  # listing, at every pass, until somebody raises the ceiling. `FORGE_PAGE 2` and
  # `FORGE_PAGES 1` put that ceiling two issues up, and the session — like any
  # session that opens a ticket — grows the tracker past it while it works.
  #
  # What the run then looks like, measured rather than assumed: the ceiling is
  # reached from *inside* the iteration too, so the scope-guard cannot say whose
  # surface `src/alpha.txt` is ([76] again, and it says so), the iteration ends
  # without a verdict and the ticket goes back. That is not what is under test and
  # it does not have to be: what matters here is that an iteration happened — so
  # the frontier scan below is on the path to `exit 0` where the value gate lives
  # — and that the pass which finds the tracker unreadable does not take it for a
  # drained frontier.
  use_forge github
  set_config FORGE_PAGE 2
  set_config FORGE_PAGES 1
  forge_seed 1 alpha Alpha <<'T'
# 1 — Alpha

**What to build:** Write the alpha marker file.

**Status:** ready-for-agent

**Blocked by:** None

**Write-surface:** `src/alpha.txt`
T
  {
    printf '#!/usr/bin/env bash\n'
    printf 'mkdir -p src && printf "written\\n" >>src/alpha.txt\n'
    printf 'd="$RALPH_SHIM_STATE/forge"\n'
    printf 'printf "extra" >"$d/issue.9.title"\n'
    printf 'printf "**Status:** ready-for-human\\n\\n**Slug:** extra\\n" >"$d/issue.9.body"\n'
    printf 'printf "open\\n" >"$d/issue.9.state"\n'
    printf ': >"$d/issue.9.assignee"\n'
    printf 'printf "9\\n" >>"$d/order"\n'
    printf '%s\n' \
      "echo '{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"num_turns\":1,\"total_cost_usd\":0.02}'"
  } | script_claude

  run_loop
  assert_failure 4
  assert_output_contains "refused to list the frontier"
  # In `run.log` and not only on a console, which is the rule every other thing
  # this loop stops on follows ([49]): a night that ended on a tracker nobody
  # could read has to appear in the file a human opens in the morning.
  assert_file_contains "$FEATURE_DIR/run.log" "frontier-refused"
  # The assertion the whole scenario exists for, and the one beside it that keeps
  # it from being true for the wrong reason: the value gate never runs at
  # `iteration = 0`, so "no value gate" only means something once a session has
  # been spawned. One session and one only — no lens, no retro, no value gate.
  assert_equal "$(playthrough_call_count)" "0"
  assert_equal "$(claude_call_count)" "1"
  # And it did not report a night of finished work either.
  refute_output_contains "frontier empty after"
}

@test "the frontier count refuses rather than answering zero" {
  # `select_frontier_count` answered with a pipeline, and a pipeline answers for
  # its **last** command: `awk` printed `0` on a listing that never happened.
  # Nobody in the pack reads this function today, which is why it is written down
  # here rather than left alone — it is the shape [74] came to remove, and the
  # next caller would inherit "the frontier is empty" from a tracker that refused.
  use_forge github
  set_config FORGE_PAGE 1
  set_config FORGE_PAGES 1
  remote__two

  pack_run 'set +e; n="$(select_frontier_count)"; printf "rc=%s n=[%s]\n" "$?" "$n"'
  assert_output_contains "rc=1 n=[]"

  # The paired witness: a ceiling that fits, and the same call answers a number.
  # Without it, "it refused" could be a function that refuses whatever it is
  # given.
  set_config FORGE_PAGES 4
  pack_run 'select_frontier_count'
  assert_success
  assert_equal "$output" "2"
}

# ── [77] the local facts this backend keeps in a file of this tree ───────────
#
# Three things only this machine knows live in `.scratch/<feature>/.forge-claims`,
# append-only with the last line winning: who holds a ticket (which is the whole
# of `claim.sh`'s liveness on a backend where a pid means nothing on another
# host), the number of the open request, and the URL the human sink shows as the
# audit receipt. That directory is the one every control of this pack steps over
# — `gate_is_bookkeeping` takes it out of the scope-guard, `failures_protect_tracker`
# only ever looked at `issues/`, and the witness of [70] knows refs, receipt
# **files** and the playthrough.
#
# Measured on 08/09/2026 (`sondes/passe-08-09/q2-*.bats`), on **green** iterations
# each time: one appended line with a live pid silenced `claim_reclaim_stale` and
# emptied the frontier; one appended `receipt` line made the drain's dossier send a
# human to a request of the session's choosing, under a reserve written about a
# network the URL never came from.
#
# What is delivered is the **remise** — a run reads the copy it took before its
# first session, so a line appended under it decides nothing — plus the naming,
# because the file on disk keeps the line and every reader outside a run, the
# drain included, reads the file.

remote__sidecar() { printf '%s/.forge-claims\n' "$FEATURE_DIR"; }

# A sink ticket for the drain, and one the loop can actually deliver.
remote__sink_and_work() {
  forge_seed 1 decision 'For the drain' <<'T'
# 1 — For the drain

**What to build:** Something a human has to arbitrate.

**Status:** ready-for-human

**Escalation:** decision

**Write-surface:** `src/one.txt`

**Blocked by:** None
T
  forge_seed 2 alpha Alpha <<'T'
# 2 — Alpha

**What to build:** Write the alpha marker file.

**Status:** ready-for-agent

**Blocked by:** None

**Write-surface:** `src/alpha.txt`
T
}

@test "a receipt line a session appends to the sidecar is named on both documents" {
  use_forge github
  set_config STERILE_K 1
  set_config PLAYTHROUGH off
  remote__sink_and_work
  # A remote to push the branch of the iteration to, which is what makes the
  # receipt of this backend a request that exists.
  forge_remote off

  # The session reaches the main tree the way any session does — `git worktree
  # list` names it, and the harness hands the same path to a fake — and appends
  # one line about a ticket it never touched.
  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src && printf 'alpha\n' >src/alpha.txt
main="$(cat "$RALPH_SHIM_STATE/project-dir")"
feature="$(basename "$(ls -d "$main"/.scratch/*/ | head -1)")"
printf '1-decision\treceipt\thttps://forge.invalid/pull/9999\n' \
  >>"$main/.scratch/$feature/.forge-claims"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  # The iteration was green — this is a run nobody has any reason to look at, and
  # that is the whole point.
  assert_equal "$(forge_field 2 Status)" "resolved"

  # What the run said, and what it wrote down. The sentence goes to the run's own
  # output and the line to the journal, which is the pair every other drift of
  # this loop travels as ([15]: the journal is the one durable document on the
  # iteration a run stops on, and it has to say where to go and look).
  assert_output_contains \
    "the local record this backend keeps about a ticket moved while this run was in flight"
  assert_output_contains "receipt appeared in"
  assert_output_contains "1-decision"
  assert_file_contains "$FEATURE_DIR/run.log" "sidecar-drift"
  assert_file_contains "$FEATURE_DIR/run.log" ".forge-claims"
  # And the receipt, which on this backend is the request's body.
  assert_equal "$(forge_request_body 1 |
    grep -c 'the local record this backend keeps about a ticket moved')" "1"

  # It named and put nothing back: the line is still where the session wrote it.
  assert_file_contains "$(remote__sidecar)" "https://forge.invalid/pull/9999"
}

@test "a run that wrote its own records accuses nobody of them" {
  # The paired witness, and it is the assertion that costs the most: this run
  # writes the sidecar itself on an ordinary green iteration — a claim, a request
  # and a receipt — so a comparison that read the file against its baseline alone
  # would report every one of them, on every night, and the line above would mean
  # nothing.
  use_forge github
  set_config STERILE_K 1
  set_config PLAYTHROUGH off
  remote__sink_and_work
  # A remote to push the branch of the iteration to, which is what makes the
  # receipt of this backend a request that exists.
  forge_remote off

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src && printf 'alpha\n' >src/alpha.txt
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_equal "$(forge_field 2 Status)" "resolved"
  # The run really did write records of its own, or this would be a witness on an
  # empty file.
  assert_file_contains "$(remote__sidecar)" "receipt"
  assert_file_contains "$(remote__sidecar)" "claim"
  refute_file_contains "$FEATURE_DIR/run.log" "sidecar-drift"
  refute_output_contains "the local record this backend keeps about a ticket moved"
}

@test "the receipt of an iteration goes into the request this run opened, not the one a session named" {
  # The remise, measured on the record where obeying a forged line is a **write**
  # this pack makes somewhere it was never asked to. `forge__request` opens the
  # request once and rewrites it afterwards, and which one it rewrites is the
  # `request` record of this file: one appended line and the receipt of this
  # iteration is `PATCH`ed into a request of the session's choosing — with the
  # branch of the iteration pushed under it.
  use_forge github
  set_config STERILE_K 1
  set_config PLAYTHROUGH off
  remote__sink_and_work
  # A remote to push the branch of the iteration to, which is what makes the
  # receipt of this backend a request that exists.
  forge_remote off

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src && printf 'alpha\n' >src/alpha.txt
main="$(cat "$RALPH_SHIM_STATE/project-dir")"
feature="$(basename "$(ls -d "$main"/.scratch/*/ | head -1)")"
printf '2-alpha\trequest\t4242\n' >>"$main/.scratch/$feature/.forge-claims"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  assert_equal "$(forge_field 2 Status)" "resolved"
  # Nothing was written into the request the session named.
  assert_equal "$(forge_request_body 4242)" ""
  # And the receipt really was emitted, into the request this run opened — or the
  # line above would be true of a run that emitted nothing at all.
  assert_equal "$(forge_request_body 1 | grep -c '## Verdicts')" "1"
  assert_file_contains "$FEATURE_DIR/run.log" "sidecar-drift"
}

@test "a claim a session appends is neither read nor swallowed" {
  # `forge__claimed` answers `tracker_field ID Claimed` out of this file, so one
  # line with a pid that answers `kill -0` is a ticket `claim_reclaim_stale`
  # leaves `claimed` — for the rest of the night, and for ever with `CLAIM_TTL`
  # disabled, the reading [12] allows on purpose.
  #
  # Driven through the module rather than through a run, for the reason the probe
  # of the pass was: what is under test is which file a read resolves against, and
  # a run reclaims on its first scan — before any session exists to append
  # anything.
  use_forge github
  forge_seed 2 alpha Alpha <<'T'
# 2 — Alpha

**Status:** claimed

**Claimed:** owner=pid:999999 at=2020-01-01T00:00:00Z

**Blocked by:** None

**Write-surface:** `src/alpha.txt`
T
  mkdir -p "$FEATURE_DIR"
  printf '2-alpha\tclaim\towner=pid:999999 at=2020-01-01T00:00:00Z\n' \
    >>"$(remote__sidecar)"

  # A witness, then a line a session could leave behind in one `printf`: this
  # shell's own pid, which certainly answers. The drift is read **before** the
  # reclaim, because the reclaim drops the claim record itself — a record the
  # pack has since rewritten is not a forgery any more, and asserting after it
  # would be asserting on the wrong instant.
  mkdir -p "$RALPH_TEST_DIR/tmp"
  export TMPDIR="$RALPH_TEST_DIR/tmp"
  pack_run '
    d="$(mktemp -d "$TMPDIR/ralph-test-witness.XXXXXX")"
    tracker_sidecar_witness "$d"
    printf "2-alpha\tclaim\towner=pid:$$ at=$(ralph_now)\n" >>"$(tracker_sidecar_path)"
    printf "claimed=[%s]\n" "$(tracker_field 2-alpha Claimed)"
    tracker_sidecar_drift "$d"
    printf "reclaim=[%s]\n" "$(claim_reclaim_stale)"'
  # Not read: the record this run holds is the dead one, so the ticket comes back.
  assert_output_contains "claimed=[owner=pid:999999 at=2020-01-01T00:00:00Z]"
  assert_output_contains "reclaim=[2-alpha "
  assert_equal "$(forge_field 2 Status)" "ready-for-agent"
  # Not swallowed either.
  assert_output_contains "sidecar-drift"
  assert_output_contains "which is the whole of its liveness"
}

@test "the same line, with no witness, is the tracker's answer" {
  # The paired witness of the line above, and it is the whole of what [77]
  # delivers: without the copy this is what every reader gets, and it is what the
  # drain still gets — which is why the dossier names the file.
  use_forge github
  forge_seed 2 alpha Alpha <<'T'
# 2 — Alpha

**Status:** claimed

**Claimed:** owner=pid:999999 at=2020-01-01T00:00:00Z

**Blocked by:** None

**Write-surface:** `src/alpha.txt`
T
  mkdir -p "$FEATURE_DIR"
  printf '2-alpha\tclaim\towner=pid:999999 at=2020-01-01T00:00:00Z\n' \
    >>"$(remote__sidecar)"

  pack_run '
    printf "2-alpha\tclaim\towner=pid:$$ at=$(ralph_now)\n" >>"$(tracker_sidecar_path)"
    printf "claimed=[%s]\n" "$(tracker_field 2-alpha Claimed)"
    printf "reclaim=[%s]\n" "$(claim_reclaim_stale)"'
  refute_output_contains "claimed=[owner=pid:999999"
  assert_output_contains "reclaim=[]"
  assert_equal "$(forge_field 2 Status)" "claimed"
}

@test "the instant between the two writes is not a record somebody deleted" {
  # `forge__record_local` writes the copy first and the file second, and that
  # order opens a window on purpose: for as long as it lasts, the copy holds a
  # record the file does not. A comparison that reported it would accuse this run
  # of deleting what it is in the middle of writing — and it would do it on every
  # ordinary claim, which is the false alarm that makes a morning line unreadable.
  # Only a key of the **baseline** is reported as gone.
  #
  # Staged directly and not through a run: the window is microseconds wide, so a
  # scenario that raced it would be a test that passes by luck. What is under test
  # is which side of that window the comparison errs on.
  use_forge github
  remote__sink_and_work
  mkdir -p "$FEATURE_DIR"
  printf '1-decision\treceipt\thttps://forge.invalid/pull/1\n' >>"$(remote__sidecar)"

  mkdir -p "$RALPH_TEST_DIR/tmp"
  export TMPDIR="$RALPH_TEST_DIR/tmp"
  pack_run '
    d="$(mktemp -d "$TMPDIR/ralph-test-witness.XXXXXX")"
    tracker_sidecar_witness "$d"
    printf "2-alpha\tclaim\towner=pid:$$ at=$(ralph_now)\n" >>"$d/sidecar"
    printf "midwrite=[%s]\n" "$(tracker_sidecar_drift "$d")"
    : >"$(tracker_sidecar_path)"
    printf "truncated=[%s]\n" "$(tracker_sidecar_drift "$d")"'

  # The record the run is writing: nothing said about it.
  assert_output_contains "midwrite=[]"
  # And its paired witness, which is what keeps the silence above from being a
  # comparison that never speaks: a record of the baseline that the file no longer
  # carries **is** a session emptying the file, and it is named.
  assert_output_contains "receipt is gone from"
  assert_output_contains "1-decision"
  # And still nothing about the record this run added and the file never held.
  refute_output_contains "claim is gone from"
}

@test "the dossier says where a remote receipt's URL was read, which is not the network" {
  # [70] put a reserve under the two objects the dossier shows, and [18] made it
  # two reserves because on this backend the receipt is a request nothing in this
  # repository attests. Both are about the **object**. Where the object *is* is
  # read here, in a file of this tree that a session appends to — so the reserve
  # sent a human to look at a service they had never been sent to by anything but
  # this line.
  use_forge github
  remote__sink_and_work
  mkdir -p "$FEATURE_DIR"
  printf '1-decision\treceipt\thttps://forge.invalid/pull/9999\n' >>"$(remote__sidecar)"

  run bash -c 'printf "n\nq\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  assert_output_contains "https://forge.invalid/pull/9999"
  assert_output_contains "Where that receipt is, though, is not read over the network"
  assert_output_contains ".forge-claims"
  assert_output_contains "The URL above is whichever line won"
  # The reserve written for the object itself is still there: this adds a
  # sentence, it does not replace one.
  assert_output_contains "this backend keeps it on its own service"

  # And never under a line that says there is none, which is the rule the reserve
  # above already follows ([70]): a caveat about an absence teaches a reader to
  # distrust the one certain sentence of this dossier. A ticket with a branch and
  # no receipt record is the case that tells the two apart — the rest of the
  # reserve is printed for the branch, and this sentence is not.
  git -C "$PROJECT_DIR" update-ref refs/heads/failed/2-alpha HEAD
  pack_run 'router_dossier 2-alpha'
  assert_output_contains "receipt  none was kept for this ticket."
  assert_output_contains "a ref is a path in no"
  refute_output_contains "is not read over the network"
}

@test "a backend that keeps no such file says nothing about one" {
  # The paired witness, on the local backend: its claim is a field of the ticket
  # file, which `failures_protect_tracker` puts back around every session, and its
  # receipt is a path composed from an id rather than a location it remembers. A
  # reserve about a file it does not keep would be a caveat about nothing, and the
  # three refusals are one answer rather than three gaps.
  use_tickets 09-escalated
  pack_run 'set +e
    tracker_sidecar_path; printf "path=%s\n" "$?"
    tracker_sidecar_witness /nonexistent; printf "witness=%s\n" "$?"
    tracker_sidecar_drift /nonexistent; printf "drift=%s\n" "$?"'
  assert_output_contains "path=1"
  assert_output_contains "witness=1"
  assert_output_contains "drift=1"
  # And no backend of this pack ever prints the dispatcher's "does not implement".
  refute_output_contains "does not implement"

  pack_run 'router_dossier 09-escalated'
  assert_output_contains "receipt"
  refute_output_contains "is not read over the network"
  refute_output_contains ".forge-claims"
}

# ── [82] a read has three answers, and four readers that decide on the third ──
#
# `lib/tracker.sh` fixes what a refusal of `read_ticket` or `field` *means*: `0`
# and the value, `1` for a ticket that is not there, `2` for "I could not tell".
# The scenarios live in this file and not in `gate.bats`, `lenses.bats` or
# `human-loop.bats` for the reason the section above gives: the local backend has
# no third state to be in — a file is there or it is not — so the only tracker
# that can stage one is this one, and staging it takes no outage. `FORGE_PAGE 2`
# with `FORGE_PAGES 1` on a tracker of two issues puts this pack's own page bound
# below the tracker, and `forge__listing` refuses every listing of the run ([76],
# [78]) — which is every read.
#
# Measured before the repair (the 10/09 pass, Q1a–Q1d): the two codes were one,
# and the three readers below each took the empty value for an answer.

# Two issues, one of them declaring a surface and a lens tag.
remote__tagged() {
  forge_seed 1 alpha Alpha <<'T'
# 1 — Alpha

**What to build:** the alpha marker.

**Status:** ready-for-agent

**Blocked by:** None

**Write-surface:** `src/alpha.txt`

**Tags:** `security`
T
  forge_seed 2 beta Beta <<'T'
# 2 — Beta

**What to build:** the beta marker.

**Status:** ready-for-agent

**Blocked by:** None

**Write-surface:** `src/beta.txt`
T
}

# The ceiling that refuses every listing of the run.
remote__ceiling_refuses() {
  set_config FORGE_PAGE 2
  set_config FORGE_PAGES 1
}

@test "a field the tracker would not answer and a ticket that is not there are two codes" {
  use_forge github
  remote__tagged
  remote__ceiling_refuses

  pack_run 'set +e
    v="$(tracker_field 1-alpha Status)"; printf "refused=%s value=[%s]\n" "$?" "$v"
    b="$(tracker_read_ticket 1-alpha)"; printf "body=%s\n" "$?"'
  # `2` and not `1`: this ticket exists, is `ready-for-agent`, and nothing here
  # could see it. A caller told `1` would be told "there is no such ticket".
  assert_output_contains "refused=2 value=[]"
  assert_output_contains "body=2"
}

@test "the same tracker under a ceiling that fits answers, and says 1 for a ticket it does not hold" {
  # The paired witness of the three tests above and below, and the one that keeps
  # `2` from being a function that refuses whatever it is given. One number
  # changed.
  use_forge github
  remote__tagged
  set_config FORGE_PAGE 2
  set_config FORGE_PAGES 4

  pack_run 'set +e
    v="$(tracker_field 1-alpha Status)"; printf "read=%s value=[%s]\n" "$?" "$v"
    tracker_field 999-nothing Status >/dev/null; printf "absent=%s\n" "$?"
    tracker_read_ticket 999-nothing >/dev/null; printf "absent-body=%s\n" "$?"
    v="$(tracker_field 2-beta Tags)"; printf "no-field=%s value=[%s]\n" "$?" "$v"'
  assert_output_contains "read=0 value=[ready-for-agent]"
  assert_output_contains "absent=1"
  assert_output_contains "absent-body=1"
  # A ticket that is there and carries no such field is the *value* answer, not
  # either refusal: an empty value is a value, as it is everywhere on this
  # interface.
  assert_output_contains "no-field=0 value=[]"
}

@test "a write-surface nobody could read is a verdict and not an empty perimeter" {
  # Q1b. `src/alpha.txt` is the one path 1-alpha declares, and it came back
  # **outside its own write-surface** — under `internal`, which is the retryable
  # class, so the ticket spent its whole budget on a tracker nobody could read.
  use_forge github
  remote__tagged
  remote__ceiling_refuses
  local class="$RALPH_TEST_DIR/class"

  pack_run 'set +e
    gate_write_surface 1-alpha; printf "surface=%s\n" "$?"'
  assert_output_contains "surface=2"
  refute_output_contains "src/alpha.txt"

  pack_run 'mkdir -p src
    base="$(gate_tree_snapshot)"
    printf "alpha\n" >src/alpha.txt
    now="$(gate_tree_snapshot)"
    set +e
    gate__scope_guard 1-alpha "$base" "$now" '"'$class'"'
    printf "rc=%s\n" "$?"'
  assert_output_contains "rc=1"
  assert_output_contains "the tracker would not say what write-surface 1-alpha declares"
  assert_output_contains "an unreadable surface is not an empty one"
  # And never the sentence that names a file the ticket does declare.
  refute_output_contains "outside the declared write-surface"
  # `contract`, for the reason `gate__surface_owner` has used it since [18]: a
  # tracker that will not answer is not something a fresh session fixes.
  assert_equal "$(cat "$class")" "contract"
}

@test "the same surface under a ceiling that fits is read, and the session stays inside it" {
  use_forge github
  remote__tagged
  set_config FORGE_PAGE 2
  set_config FORGE_PAGES 4
  local class="$RALPH_TEST_DIR/class"

  pack_run 'gate_write_surface 1-alpha'
  assert_success
  assert_equal "$output" "src/alpha.txt"

  pack_run 'mkdir -p src
    base="$(gate_tree_snapshot)"
    printf "alpha\n" >src/alpha.txt
    now="$(gate_tree_snapshot)"
    set +e
    gate__scope_guard 1-alpha "$base" "$now" '"'$class'"'
    printf "rc=%s\n" "$?"'
  assert_output_contains "rc=0"
  refute_output_contains "would not say what write-surface"
  refute_file_exists "$class"
}

@test "a lens gated on a tag the tracker would not answer is not a lens that has nothing to look at" {
  # Q1c. `lenses__triggered_by` already carried the rule — "approximating towards
  # running the lens is the only safe direction for it to be wrong in" — and the
  # empty answer took it away in the one case it was written for.
  use_forge github
  remote__tagged
  remote__ceiling_refuses

  pack_run 'set +e
    lenses_has_tag 1-alpha security; printf "tag=%s\n" "$?"
    lenses__triggered_by 1-alpha security ""; printf "triggered=%s\n" "$?"'
  assert_output_contains "tag=2"
  assert_output_contains "triggered=0"
}

@test "the same lens under a ceiling that fits sees the tag it is gated on, and only that one" {
  use_forge github
  remote__tagged
  set_config FORGE_PAGE 2
  set_config FORGE_PAGES 4

  pack_run 'set +e
    lenses_has_tag 1-alpha security; printf "tag=%s\n" "$?"
    lenses_has_tag 1-alpha perf; printf "other=%s\n" "$?"
    lenses_has_tag 2-beta security; printf "untagged=%s\n" "$?"
    lenses__triggered_by 2-beta security ""; printf "triggered=%s\n" "$?"'
  assert_output_contains "tag=0"
  assert_output_contains "other=1"
  assert_output_contains "untagged=1"
  assert_output_contains "triggered=1"
}

@test "a drain pins nothing on a tracker that would not answer, and accuses nobody" {
  # Q1d's third reader. `router_pin` sets its id last "so that a read that failed
  # halfway leaves the ticket unpinned" — which nothing ever did, because every
  # field was read through `|| VALUE=''`. Two arms: the pin refuses, and a pin
  # taken on a tracker that answers is not turned into an accusation when the
  # tracker stops answering afterwards.
  use_forge github
  remote__tagged
  remote__ceiling_refuses

  pack_run 'set +e
    router_pin 1-alpha
    printf "pinned=[%s]\n" "${ROUTER__PINNED_ID:-}"
    router_protect_tracker 1-alpha 2>&1
    printf "protect=%s\n" "$?"'
  assert_output_contains "pinned=[]"
  # Unpinned is what every transition of this module already refuses, loudly.
  assert_output_contains "nothing pinned what this tracker said"
  assert_output_contains "protect=1"

  # The second arm: pinned while the tracker answered, refused afterwards. The
  # ceiling is raised in the shell rather than stubbed, so what refuses the reads
  # is the pack's own bound and not a fake.
  pack_run 'set +e
    FORGE_PAGES=4
    router_pin 1-alpha
    printf "pinned=[%s]\n" "${ROUTER__PINNED_ID:-}"
    FORGE_PAGES=1
    router__say_drift 1-alpha "Write-surface"
    printf "said=%s\n" "$?"'
  assert_output_contains "pinned=[1-alpha]"
  assert_output_contains "said=0"
  refute_output_contains "Something wrote it in between"
  # `Write-surface` and not `Escalation`, and that is the difference between a
  # test and a test that cannot fail: 1-alpha carries no `Escalation:`, so the pin
  # is the empty string and a refusal read as the empty string *matches* it. The
  # sentence only exists on a pin that holds something.
}

@test "the local backend keeps its two answers and gains no third state" {
  # AC 5, and it is the half that says what the clause must *not* ask for. This
  # backend is never in the third state: a file is there or it is not, and an
  # ambiguous id resolves to no ticket, which is an answer about the tracker and
  # not an uncertainty about reaching it. Both are `1`, both were `1` before [82],
  # and a clause that made this backend invent a `2` would have it report a state
  # it has no way to be in.
  use_tickets 01-alpha 08-no-write-surface
  cp "$RALPH_FIXTURES/tickets/01-alpha.md" "$TRACKER_DIR/01-ambiguous.md"

  pack_run 'set +e
    v="$(tracker_field 08-no-write-surface Status)"; printf "read=%s value=[%s]\n" "$?" "$v"
    v="$(tracker_field 08-no-write-surface "Write-surface")"; printf "no-field=%s value=[%s]\n" "$?" "$v"
    tracker_field 99-nothing Status >/dev/null; printf "absent=%s\n" "$?"
    tracker_read_ticket 99-nothing >/dev/null; printf "absent-body=%s\n" "$?"
    tracker_field 01 Status 2>/dev/null >/dev/null; printf "ambiguous=%s\n" "$?"'
  assert_output_contains "read=0 value=[ready-for-agent]"
  assert_output_contains "no-field=0 value=[]"
  assert_output_contains "absent=1"
  assert_output_contains "absent-body=1"
  assert_output_contains "ambiguous=1"

  # And a ticket that declares nothing still reads as an empty surface rather
  # than as a refusal: the fail-safe of [14] is built on that answer, and [82]
  # must not take it away.
  pack_run 'set +e; gate_write_surface 08-no-write-surface; printf "surface=%s\n" "$?"'
  assert_output_contains "surface=0"
}

# ── [82] a tracker that answers one read and refuses the next ────────────────
#
# The four readers above are staged on the cheapest real refusal this pack has:
# its own page bound, which refuses **every** listing of the run. That is the
# honest common case and it is also why the arms below are stubbed rather than
# seeded — each one needs a tracker that answers one read and refuses another,
# which no configuration of one backend produces and which is exactly what a
# flaky API, a rate limit, or a session that opened a ticket and pushed the
# tracker over the bound produces on a real night. The stub refuses one field by
# name and hands every other read to the backend, so what is under test is the
# reader's handling of a refusal and never the refusal itself.
#
# On the local backend deliberately: these are readers of `lib/tracker.sh`, not
# of a forge, and a local fixture makes the paired witness a one-line change.

@test "a surface_owner that read the ids and not one ticket's surface escalates too" {
  # `gate_write_surface` is called once per ticket *inside* the walk, so the list
  # can be whole and one answer missing. Read as "not this one", the walk ends on
  # "nobody owns it" — the one answer that makes a drift against a contract
  # retryable, which is what [18] escalated for and what [82] left one line above.
  use_tickets 01-alpha 07-overlaps-alpha

  pack_run 'set +e
    gate__surface_owner "src/alpha.txt" 07-overlaps-alpha
    printf "answered=%s\n" "$?"
    tracker_field() { case "$2" in "Write-surface") return 2 ;; *) tracker_local_field "$@" ;; esac; }
    gate__surface_owner "src/alpha.txt" 07-overlaps-alpha
    printf "refused=%s\n" "$?"'
  assert_output_contains "01-alpha"
  assert_output_contains "answered=0"
  assert_output_contains "refused=2"
}

@test "a lens whose ticket carries no tag and whose surface could not be read still runs" {
  # The other half of the lens question ([06]'s predicate is a tag *or* a path
  # overlap), and the same safe direction: a surface nobody could read is not a
  # ticket that touches nothing.
  use_tickets 01-alpha

  pack_run 'set +e
    lenses__triggered_by 01-alpha security "docs/*"; printf "answered=%s\n" "$?"
    tracker_field() { case "$2" in "Write-surface") return 2 ;; *) tracker_local_field "$@" ;; esac; }
    lenses__triggered_by 01-alpha security "docs/*"; printf "refused=%s\n" "$?"'
  # `src/alpha.txt` against `docs/*` overlaps nothing, so the answer is a real
  # "this lens has nothing to look at here" — and it stops being one the moment
  # the surface cannot be read.
  assert_output_contains "answered=1"
  assert_output_contains "refused=0"
}

@test "a drain pins nothing when any one read of the pin could not be answered" {
  # The pin is five reads deep — three fields, then `router__tracker_state`, which
  # walks the whole tracker for four fields and a digest of each ticket — and a
  # baseline is whole or it is not a baseline. Four arms, one per read, and each
  # one refuses a read the *other* three do not make: that is what keeps them from
  # covering for each other. `Write-surface` is the pin's own and nothing else
  # reads it; `Status` is the baseline's own and the pin does not read it;
  # `read_ticket` is the digest's; `ids` is the list the baseline walks.
  use_tickets 09-escalated 01-alpha

  pack_run 'router_pin 09-escalated; printf "pinned=[%s]\n" "${ROUTER__PINNED_ID:-}"'
  assert_output_contains "pinned=[09-escalated]"

  pack_run 'tracker_field() { case "$2" in "Write-surface") return 2 ;; *) tracker_local_field "$@" ;; esac; }
    router_pin 09-escalated
    printf "surface=[%s]\n" "${ROUTER__PINNED_ID:-}"'
  assert_output_contains "surface=[]"

  pack_run 'tracker_field() { case "$2" in Status) return 2 ;; *) tracker_local_field "$@" ;; esac; }
    router_pin 09-escalated
    printf "status=[%s]\n" "${ROUTER__PINNED_ID:-}"'
  assert_output_contains "status=[]"

  pack_run 'tracker_read_ticket() { return 2; }
    router_pin 09-escalated
    printf "body=[%s]\n" "${ROUTER__PINNED_ID:-}"'
  assert_output_contains "body=[]"

  pack_run 'tracker_ids() { return 1; }
    router_pin 09-escalated
    printf "ids=[%s]\n" "${ROUTER__PINNED_ID:-}"'
  assert_output_contains "ids=[]"
}

@test "a tracker that would not list its tickets after a session is not a tracker a session emptied" {
  # [59]'s rule on the drain's own second read. Empty, every pinned ticket reads
  # as one the routed session deleted — one sentence and one `tracker-drift gone`
  # per ticket, in `run.log`, about a session that did nothing.
  use_tickets 09-escalated 01-alpha

  pack_run 'set +e
    router_pin 09-escalated
    tracker_ids() { return 1; }
    router_protect_tracker 09-escalated 2>&1
    printf "rc=%s\n" "$?"'
  assert_output_contains "the tracker would not list its tickets after that session"
  assert_output_contains "rc=1"
  refute_output_contains "did not exist when this drain took"
  refute_output_contains "is gone from the tracker"
}

@test "a ticket whose status could not be read after a session is not put back on a state nobody read" {
  # The one place in this file where a value nobody read becomes a **write** on
  # somebody else's ticket: read as the empty string, `Status:` does not match
  # what was pinned, and the drain calls `tracker_mark_escalated` on a ticket it
  # has no evidence moved.
  use_tickets 09-escalated 01-alpha

  pack_run 'set +e
    router_pin 09-escalated
    tracker_field() { case "$2" in Status) return 2 ;; *) tracker_local_field "$@" ;; esac; }
    router_protect_tracker 09-escalated 2>&1
    printf "rc=%s\n" "$?"'
  assert_output_contains "cannot be read from the tracker after that session"
  assert_output_contains "nothing is put back on a state nobody read"
  # And the ticket the drain is not on is where it was: no transition was made on
  # a comparison against the empty string.
  assert_ticket_status 01-alpha ready-for-agent
  assert_ticket_status 09-escalated ready-for-human
}

@test "a retry budget that could not be read is not a retry budget a session rewrote" {
  # The three things no verb writes back are named rather than restored ([61]),
  # and naming them on a refusal is an accusation: `Failures:` read as nothing
  # against a pin of `2` prints "a retry budget has no verb that writes it" about
  # a number nobody touched, and journals `tracker-drift failures` for it.
  use_tickets 09-escalated

  pack_run 'set +e
    router_pin 09-escalated
    tracker_field() { case "$2" in Failures) return 2 ;; *) tracker_local_field "$@" ;; esac; }
    router_protect_tracker 09-escalated 2>&1
    printf "rc=%s\n" "$?"'
  # Silent and non-zero, which is this function's own word for "nothing moved
  # that this looks at".
  assert_output_contains "rc=1"
  refute_output_contains "a retry budget has no verb"
  refute_output_contains "tracker-drift"
}

@test "a claim record nobody could read is not a claim nobody holds" {
  # `claim_reclaim_stale` decides whether to take somebody else's claim away, and
  # an empty `Claimed:` is a claim nobody holds. A tracker that would not answer
  # therefore handed every claimed ticket back to the frontier while the
  # iterations holding them were still running.
  use_tickets 04-claimed

  pack_run 'tracker_field() { case "$2" in Claimed) return 2 ;; *) tracker_local_field "$@" ;; esac; }
    claim_reclaim_stale ""'
  assert_success
  assert_equal "$output" ""
  assert_ticket_status 04-claimed claimed

  # The paired witness: the same sweep, the same ticket, a record it can read and
  # an owner that is gone.
  stamp_claim 04-claimed "pid:999999" "2026-07-25T08:00:00Z"
  pack_run 'claim_reclaim_stale ""'
  assert_success
  assert_output_contains "04-claimed retry"
}

@test "a lib that meets a refused surface holds a ticket back, it does not end the run" {
  # The two readers of `gate_write_surface` that are not the scope-guard. Both
  # already fail safe on an *empty* surface, so what the refusal buys them is the
  # other half: `loop.sh` sources them under `set -euo pipefail`, and a bare
  # assignment from a function that now answers `2` takes the whole run down —
  # [79]'s family, one lib over. The assertion is the printed line: a shell that
  # died at the assignment prints nothing at all.
  use_tickets 01-alpha 07-overlaps-alpha

  pack_run 'tracker_field() { case "$2" in "Write-surface") return 2 ;; *) tracker_local_field "$@" ;; esac; }
    concurrency_clashes 01-alpha "07-overlaps-alpha"
    printf "clash=%s\n" "$?"'
  # A surface this pack cannot read is a clash, not a pass: the ticket runs alone.
  assert_output_contains "clash=0"

  pack_run 'tracker_field() { case "$2" in "Write-surface") return 2 ;; *) tracker_local_field "$@" ;; esac; }
    set +e
    failures_reslice 01-alpha
    printf "reslice=%s\n" "$?"'
  # And a re-slice refuses **before** it opens a planning session, because the
  # children inherit this list: a contract no gate can measure, written by the
  # loop rather than by a session. The session count is the assertion and the
  # status is not: a re-slice that runs on an empty surface also comes back
  # non-zero, having spent a session first.
  assert_output_contains "reslice=1"
  assert_equal "$(claude_call_count)" "0"
}

# ── one reading of the tracker, shared by the forks under it ([75]) ──────────
#
# What this backend costs is requests, and this pack reads a tracker through
# command substitutions, which are forks: a memo in a shell dies in every one of
# them. The reading is therefore taken in the shell the forks come from, held in a
# variable nothing exports, and bounded three ways — the prime itself, the run's
# register of its own writes, and `FORGE_CACHE_TTL`.

# How many times the pack asked the forge for a listing. The *listing* and not
# every call: a claim is two writes and a receipt is a request, and neither is
# what this reading is about. Matched on the query the list path carries
# (`state=all`), which is what tells it from `GET …/issues/<n>` and from the
# pipeline a `WAIT_CI` asks about — and never on the repository, which travels
# percent-encoded.
remote__listings() {
  forge_calls | grep -c '^GET .*/issues?state=' || true
}

remote__forget_calls() {
  : >"$SHIM_STATE/forge/calls"
}

# Two tickets a human has to decide on, and ten around them — the number is what
# matters: the drain pins the four deciding fields and a digest of **every**
# ticket, once per ticket it offers ([58], [61]).
remote__a_sink_of_twelve() {
  forge_seed 1 decision 'For the drain' <<'T'
# 1 — For the drain

**What to build:** Something a human has to arbitrate.

**Status:** ready-for-human

**Escalation:** decision

**Write-surface:** `src/one.txt`

**Blocked by:** None
T
  forge_seed 2 second 'And another' <<'T'
# 2 — And another

**What to build:** Something else a human has to arbitrate.

**Status:** ready-for-human

**Escalation:** decision

**Write-surface:** `src/two.txt`

**Blocked by:** None
T
  forge_seed_many 3 12 bulk
}

@test "a drained ticket is one reading of the tracker and not one per question" {
  # AC 1, measured on both sides of the same scenario rather than against a number
  # written down once: the second drain is the same drain with the reading
  # switched off, which is what this backend did before [75].
  use_forge github
  remote__a_sink_of_twelve

  # Two tickets and a decision on the first, because that is what tells the two
  # readings apart: closing a ticket is a write, every reading of this run stops
  # being served the moment it lands, and what makes the second ticket cost one
  # listing again is the reading taken at the top of its own pass.
  remote__forget_calls
  run bash -c 'printf "c\nn\nq\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  # The drain really drained: a scenario that refused early would ask for nothing
  # at all and pass this test by doing none of the work. Asserted before the count
  # is taken, and never out of a variable read after the second `run`.
  assert_output_contains "1-decision: closed"
  assert_output_contains "── 2-second ──"
  assert_output_contains "left in the sink"
  local shared
  shared="$(remote__listings)"

  # The same scenario with the reading switched off, on a tracker put back where
  # it was: a second drain over a sink of one ticket would be a different amount
  # of work, and the comparison would be between two scenarios rather than two
  # readings.
  use_forge github
  remote__a_sink_of_twelve
  set_config FORGE_CACHE_TTL 0
  remote__forget_calls
  run bash -c 'printf "c\nn\nq\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  assert_output_contains "1-decision: closed"
  assert_output_contains "── 2-second ──"
  local apiece
  apiece="$(remote__listings)"

  [ "$shared" -gt 0 ] && [ "$apiece" -gt 0 ] ||
    fail "no listing was asked for at all, so this measures nothing: shared=$shared apiece=$apiece"
  [ "$((shared * 10))" -le "$apiece" ] ||
    fail "a drained ticket did not cost an order of magnitude fewer listings: $shared with the reading, $apiece without it"
}

@test "what a routed session wrote on the forge is read when that session returns" {
  # The probe this ticket cannot be delivered without: a session writing the
  # tracker **over the network**, which is the one write no register of this run,
  # no snapshot and no witness of this pack sees ([18]). A reading taken before it
  # and still being served would make the four readers of [56]/[58]/[66]/[68]
  # report that nothing moved — a false green produced by a cache, on the entry
  # point whose whole job is to say what an unjudged session did.
  use_forge github
  remote__sink_and_work
  script_claude <<'SCRIPT'
#!/usr/bin/env bash
d="$RALPH_SHIM_STATE/forge"
printf '**What to build:** Write the alpha marker file.\n\n**Status:** resolved\n\n**Blocked by:** None\n\n**Write-surface:** `src/alpha.txt`\n\n**Slug:** alpha\n' \
  >"$d/issue.2.body"
exit 0
SCRIPT

  run bash -c 'printf "o\nn\nq\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  assert_output_contains "2-alpha was moved to \`Status: resolved\`"
  assert_output_contains "put back to \`ready-for-agent\`"
  # And on the forge, which is where this is true or not: the drain wrote the
  # ticket back through the adapter, so a reading served from memory would show
  # here as a tracker nobody corrected.
  assert_equal "$(forge_field 2 Status)" "ready-for-agent"
}

@test "a write made in a fork is not a reading the shell that forked it keeps" {
  # AC 3, and the trap the ticket named: `n="$(tracker_bump_failures …)"` is the
  # ordinary shape of a write in this pack, and a subshell that drops its own memo
  # leaves its parent holding the state before the write. Over-invalidating costs
  # a request; under-invalidating is a ticket claimed twice.
  use_forge github
  remote__two

  pack_run 'set +e
    d="$(mktemp -d)"
    tracker_cache_open "$d"; printf "open=%s\n" "$?"
    tracker_cache_prime; printf "prime=%s\n" "$?"
    n="$(tracker_bump_failures 1-alpha)"
    printf "bumped=[%s]\n" "$n"
    printf "read=[%s]\n" "$(tracker_field 1-alpha Failures)"
    rm -rf "$d"'
  assert_output_contains "open=0"
  assert_output_contains "prime=0"
  assert_output_contains "bumped=[1]"
  # The forge is what holds the truth here, and this is the shell that was holding
  # a reading taken before the write.
  assert_output_contains "read=[1]"
  assert_equal "$(forge_field 1 Failures)" "1"
}

# A human opening an issue on the forge, which no register of this run sees and
# no write of this pack goes through — staged where a human does it, which is the
# whole of what makes the bound the only thing that can bring it in.
#
# Written into the fake forge by hand rather than through `forge_seed`, because it
# has to happen **inside** the process that is holding a reading: a helper of this
# harness runs in the bats shell, and the reading lives in the shell `pack_run`
# started.
remote__opened_by_a_human() {
  cat <<'ASK'
opened_by_a_human() {
  d="$RALPH_SHIM_STATE/forge"
  printf 'nine' >"$d/issue.9.title"
  printf '**Status:** ready-for-agent\n\n**Blocked by:** None\n\n**Slug:** nine\n' >"$d/issue.9.body"
  printf 'open\n' >"$d/issue.9.state"
  : >"$d/issue.9.assignee"
  printf '9\n' >>"$d/order"
}
ASK
}

@test "a reading is served for as long as the bound the project set" {
  # AC 4, first direction. The shipped bound is sixty seconds, so what is asserted
  # here is that the reading really is being served — a test that read the forge
  # again would pass every assertion of this ticket while buying nothing.
  use_forge github
  remote__two

  local script="$RALPH_TEST_DIR/cache-within.sh"
  {
    remote__opened_by_a_human
    cat <<'ASK'
state="$(mktemp -d)"
tracker_cache_open "$state"
tracker_cache_prime
opened_by_a_human
printf 'within: %s\n' "$(tracker_ids | grep -c .)"
rm -rf "$state"
ASK
  } >"$script"
  pack_run ". '$script'"
  assert_success
  assert_output_contains "within: 2"
}

@test "and the tracker is read again once that bound has run out" {
  # The paired witness, and AC 4's other direction: this pack's frontier is a scan
  # with **no memory** ([04]), which is what makes a killed run, an edit a human
  # makes between two iterations and a cold start behave alike. A reading with no
  # bound would turn a night into one photograph of the tracker taken at its start.
  #
  # A bound of one second and a wait of two, so that what is measured is the bound
  # and never the second this test happened to start in.
  use_forge github
  remote__two
  set_config FORGE_CACHE_TTL 1

  local script="$RALPH_TEST_DIR/cache-after.sh"
  {
    remote__opened_by_a_human
    cat <<'ASK'
state="$(mktemp -d)"
tracker_cache_open "$state"
tracker_cache_prime
opened_by_a_human
sleep 2
printf 'after: %s\n' "$(tracker_ids | grep -c .)"
rm -rf "$state"
ASK
  } >"$script"
  pack_run ". '$script'"
  assert_success
  assert_output_contains "after: 3"
}

@test "a tracker that would not answer is not a reading, and the prime says nothing" {
  # The clause [82] left on this ticket: a cache never memorises a refusal. A
  # listing that refused leaves nothing behind, so the refusal repeats instead of
  # being replaced by an empty list — which is what would read as a tracker
  # holding no tickets at all ([59], [76]).
  use_forge github
  remote__two
  remote__ceiling_refuses

  # The prime is a **plain statement** and never `out="$(tracker_cache_prime)"`,
  # and that is the difference between this test and one that cannot fail: a
  # command substitution is a fork, so a reading taken inside one dies with it —
  # which is the whole defect this ticket is about. Measured: with the prime in a
  # substitution, a mutation that caches a refused listing left this test green.
  pack_run 'set +e
    d="$(mktemp -d)"
    tracker_cache_open "$d"
    tracker_cache_prime 2>"$d/said"; printf "prime=%s said=[%s]\n" "$?" "$(cat "$d/said")"
    tracker_ids >/dev/null 2>&1; printf "ids=%s\n" "$?"
    tracker_field 1-alpha Status >/dev/null 2>&1; printf "field=%s\n" "$?"
    rm -rf "$d"'
  assert_output_contains "prime=1 said=[]"
  assert_output_contains "ids=1"
  # Still the third answer of a read and not "there is no such ticket" ([82]).
  assert_output_contains "field=2"
}

@test "the register of this run's tracker writes is a witness that may only grow" {
  # What the 10/09/2026 pass asked of this ticket: the object it puts on a disk
  # goes into the census of [81] rather than beside it. It is sealed empty and it
  # is appended to by every write, so what it needs from `gate_witness_mutable` is
  # the `grows` line — without it, the first claim of the night turns the run's own
  # register into a witness this run is told it rewrote.
  use_forge github
  remote__two

  local script="$RALPH_TEST_DIR/writes-grow.sh"
  cat >"$script" <<'ASK'
state="$(mktemp -d)"
tracker_cache_open "$state"
RALPH_WITNESS_SEAL="$(gate_witness_seal "$state")"
printf 'sealed: '; gate_witness_moved || printf '(quiet)\n'
tracker_claim 1-alpha >/dev/null 2>&1
printf 'wrote:  %s line(s), ' "$(grep -c . "$state/tracker.writes")"
gate_witness_moved || printf '(quiet)\n'
rm -rf "$state"
ASK
  pack_run ". '$script'"
  assert_success
  assert_output_contains "sealed: (quiet)"
  # The claim really wrote the register: a count of zero would make the line below
  # true about a file nothing touched.
  case "$output" in
    *"wrote:  0 line(s)"*) fail "the claim appended nothing, so this proves nothing: $output" ;;
  esac
  assert_output_contains "line(s), (quiet)"
}

@test "the local backend keeps no such reading, and refuses out loud" {
  # The paired witness. Its tracker is a directory of files on this machine: a
  # fork reads the same files as its parent, and a reading held in a shell would
  # be a second answer about a file anything can open. Both refusals are explicit,
  # because an operation a backend does not implement prints a sentence on the
  # console of every run and every drain ([77]).
  use_tickets 01-alpha

  pack_run 'set +e
    d="$(mktemp -d)"
    out="$( { tracker_cache_open "$d"; printf "open=%s\n" "$?"; } 2>&1)"
    printf "%s\n" "$out"
    out="$( { tracker_cache_prime; printf "prime=%s\n" "$?"; } 2>&1)"
    printf "%s\n" "$out"
    printf "left=[%s]\n" "$(ls "$d")"
    rm -rf "$d"'
  assert_output_contains "open=1"
  assert_output_contains "prime=1"
  assert_output_contains "left=[]"
  refute_output_contains "does not implement"
}
