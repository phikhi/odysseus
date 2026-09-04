#!/usr/bin/env bats
#
# Rules about the shipped source that no functional test can notice.
#
# Who may call whom, first. The pack is a stack: `loop.sh` on top, `lib/*.sh`
# under it, each lib a module owning its `<module>_` prefix and hiding its
# `<module>__` internals. Two ways that stack turns into a mesh, and both happened
# while delivering [07]:
#
#   - a lib reaching into another module's `__` internals, which makes the
#     private name a lie and freezes an implementation detail into an interface;
#   - a lib calling up into `loop.sh`, which makes the lib unusable without the
#     loop and the loop impossible to reason about layer by layer.
#
# And since [59], one rule about how a refusal travels, for the same reason: it is
# a property of the source that a green suite cannot see.
#
# None of them breaks a test on its own — that is exactly why this file exists. It
# reads the real pack rather than the fixture copy: the rules are about the
# shipped layout, not about what a test happens to install.

load helpers/harness
load helpers/assert

setup() {
  harness_setup
}

teardown() {
  harness_teardown
}

# Every call into another module's internals, one finding per line. Comments are
# stripped first: a comment naming a neighbour's internal is documentation, not a
# dependency. Non-zero when it found something, so `run` reads naturally.
# `"$dir"/*.sh` and not `"$dir"/loop.sh`: the pack has two entry points since
# [16], and an entry point outside this glob is one where a lib's `__` internals
# are reachable with nothing to say so. `human-loop.sh` owns `human_loop_`, which
# is what `basename … .sh | tr '-' '_'` gives it — the same rule the libs get,
# arrived at by the same line.
layering_privates() {
  local dir="$1" f own call mod rc=0
  for f in "$dir"/lib/*.sh "$dir"/*.sh; do
    [ -e "$f" ] || continue
    own="$(basename "$f" .sh | tr '-' '_')"
    for call in $(grep -v '^[[:space:]]*#' "$f" |
      grep -o '[a-z][a-z0-9_]*__[a-z0-9_]*' | sort -u); do
      mod="${call%%__*}"
      [ "$mod" = "$own" ] && continue
      printf '%s calls %s, which is private to %s\n' "$(basename "$f")" "$call" "$mod"
      rc=1
    done
  done
  return "$rc"
}

# Every call from a lib up into the loop that drives it.
layering_upward() {
  local dir="$1" f call rc=0
  for f in "$dir"/lib/*.sh; do
    [ -e "$f" ] || continue
    for call in $(grep -v '^[[:space:]]*#' "$f" |
      grep -o 'loop_[a-z0-9_]*' | sort -u); do
      printf '%s calls %s: a lib must not depend on the loop\n' "$(basename "$f")" "$call"
      rc=1
    done
  done
  return "$rc"
}

# Every declaration that swallows the status of the command substitution it is
# assigned from, one finding per line.
#
# `local x="$(f)"` returns the status of `local`, which is zero whatever `f`
# answered — so a function that refuses by return code is refused by nothing, and
# the caller carries on holding an empty string. That is [59]'s whole mechanism
# taken apart in one keyword: `gate_tree_snapshot` now hands its refusal back
# through the status precisely because errexit could not carry it, and a single
# caller written this way would put the hole back without a test noticing. The
# correct form is two statements — `local x` then `x="$(f)" || …` — and the pack
# is already written that way everywhere, which is what makes this a rule rather
# than a migration.
#
# Only a **bare** substitution counts: `local x="${1:-$(f)}"` is a default value
# whose status was never the substitution's, and flagging it would teach the next
# reader to distrust the rule.
layering_masked_status() {
  local dir="$1" f line rc=0
  for f in "$dir"/lib/*.sh "$dir"/*.sh; do
    [ -e "$f" ] || continue
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      printf '%s: %s masks the status of the substitution it assigns\n' \
        "$(basename "$f")" "$line"
      rc=1
    done <<MASKED
$(grep -nE '^[[:space:]]*(local|export|declare|readonly|typeset)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*="?\$\(' "$f")
MASKED
  done
  return "$rc"
}

# A copy of the real pack with a violation of each kind planted in it. A copy,
# not the pack itself: a run interrupted halfway must not leave the repository
# holding a bogus function.
layering__planted_pack() {
  local dest="$RALPH_TEST_DIR/planted"
  mkdir -p "$dest"
  cp -R "$RALPH_PACK_ROOT/.claude/lib" "$dest/lib"
  cp "$RALPH_PACK_ROOT/.claude/loop.sh" "$dest/loop.sh"
  cp "$RALPH_PACK_ROOT/.claude/human-loop.sh" "$dest/human-loop.sh"
  printf 'probe_reaches_in() { gate__scope_guard x y z; }\n' >>"$dest/lib/state.sh"
  printf 'probe_reaches_up() { loop_log hi; }\n' >>"$dest/lib/state.sh"
  printf 'probe_masks_status() {\n  local tree="$(gate_tree_snapshot)"\n}\n' \
    >>"$dest/lib/state.sh"
  # The shape that must *not* be reported, planted beside it: a rule that flagged
  # this would be worked around rather than obeyed.
  printf 'probe_default_value() {\n  local host="${1:-$(hostname 2>/dev/null || printf x)}"\n}\n' \
    >>"$dest/lib/state.sh"
  # And the same violation in the *other* entry point, which is what keeps the
  # glob honest ([16]). A check that walked `loop.sh` by name would read a pack
  # with a second entry point exactly like a clean one, and `human-loop.sh`
  # reaching into `loop__arm_successor` — the one call [09] forbids it — is
  # precisely the shape that would go unremarked.
  printf 'probe_second_entry() { loop__arm_successor; }\n' >>"$dest/human-loop.sh"
  printf '%s\n' "$dest"
}

@test "no module reaches into another module's internals" {
  run layering_privates "$RALPH_PACK_ROOT/.claude"
  assert_success
}

@test "no lib depends on the loop that drives it" {
  run layering_upward "$RALPH_PACK_ROOT/.claude"
  assert_success
}

@test "no declaration swallows the status of what it is assigned from" {
  run layering_masked_status "$RALPH_PACK_ROOT/.claude"
  assert_success
}

@test "the rule has teeth: a planted violation of each kind is caught" {
  # Without this, a check that silently matched nothing — a bad glob, a renamed
  # convention — would read exactly like a clean pack.
  planted="$(layering__planted_pack)"

  run layering_privates "$planted"
  assert_failure
  assert_output_contains "state.sh calls gate__scope_guard, which is private to gate"
  assert_output_contains "human-loop.sh calls loop__arm_successor, which is private to loop"

  run layering_upward "$planted"
  assert_failure
  assert_output_contains "state.sh calls loop_log"

  run layering_masked_status "$planted"
  assert_failure
  assert_output_contains "local tree="
  # And the paired witness of the rule's own boundary: a default value is not a
  # masked status, and the planted one beside it is not reported.
  refute_output_contains "local host="
}
