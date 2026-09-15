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
#
# **Since [87] these rules derive the zone they walk instead of being handed
# one.** The glob was widened by hand once already: [16] shipped a second entry
# point and `"$dir"/loop.sh` became `"$dir"/*.sh`. [19] shipped a third — `init.sh`,
# at the repository root and outside `.claude/**` — and nothing widened, so for
# four tickets the pack's most prose-dense file was the one file none of these
# rules read. `layering_sources` walks the repository and classifies what it
# finds; a fourth entry point is judged the day it lands, and a file the criterion
# cannot place is a finding in every rule rather than a file quietly skipped.
#
# [90] added the fifth rule, and it inherits that zone by construction rather than
# by a second glob: `layering_quoted_prose` reads the same sources and refuses the
# same backtick in the form the pack actually writes most of its prose in — a
# double-quoted argument, where the rule of [61] was green.

load helpers/harness
load helpers/assert

setup() {
  harness_setup
}

teardown() {
  harness_teardown
}

# ── the zone, derived ────────────────────────────────────────────────────────

# Every shell file in the repository that can be pack source, one path per line.
#
# A walk and not a glob, because the glob is what went stale. The four pruned
# names are the places that are deliberately *not* the pack's stack, and each is
# pruned for a reason rather than for tidiness:
#
#   .git        not source at all.
#   .scratch    the tracker, the passes and the prototypes — including a whole
#               second copy of `init.sh` under `dev-framework/`, which is a
#               snapshot of an old form factor and not a fourth entry point.
#   test        this harness. The rules are about what the pack ships; a rule
#               that walked the file defining it would be judging its own tools.
#   .agents     the skill substrate `.claude/skills` links into. It ships in the
#               npm payload, but a skill's `*.template.sh` is an asset a skill
#               hands a human, not a module of this stack. (`find` does not follow
#               the links in `.claude/skills` either, so this prune is the second
#               of two locks on the same door.)
#
# `node_modules` is pruned wherever it appears: `npx ralph-pack` is a supported
# entry path, so a checkout can acquire one, and vendored shell would otherwise
# arrive here as hundreds of unclassifiable findings.
#
# `bin/ralph-init.js` is not walked and is not an omission: it is node, these are
# rules about bash, and [19] keeps it to an exec precisely so that it holds no
# logic. Shell landing under `bin/` *would* be walked, which is the point.
layering__shell_files() {
  local root="$1"
  find "$root" \
    \( -path "$root/.git" \
    -o -path "$root/.scratch" \
    -o -path "$root/test" \
    -o -path "$root/.agents" \
    -o -name node_modules \) -prune -o \
    -type f -name '*.sh' -print | LC_ALL=C sort
}

# Each of those files classified, one `<kind><TAB><path>` per line, `kind` being
# `lib`, `entry`, or `unclassified` followed by a third field saying why.
#
# The criterion is the **first line**, and it is not the executable bit the
# obvious reading suggests: `.claude/human-loop.sh` is mode `100644` in the index
# and is started as `bash .claude/human-loop.sh`, so an `-x` test would read the
# pack's second entry point as a lib and hand the four rules a zone that is wrong
# in the same direction as the glob it replaces. What actually separates the two
# kinds is what the file is *for*: an entry point is executed, so it carries a
# `#!` line; a lib is sourced, so it cannot carry one and carries the
# `# shellcheck shell=bash` directive that says as much to the linter. Twenty-four
# libs and three entry points, and not one file in the pack is ambiguous.
#
# Position is checked against the marker rather than used instead of it. Where a
# file sits is the hand-written knowledge this ticket removes, so it is not
# allowed to *decide* anything; but a `lib/` file that carries a shebang, or an
# entry point that carries the directive, is a pack whose two signals disagree,
# and the honest answer there is a refusal and not a guess.
#
# Nothing here reads a list the pack publishes about itself. [62] and [85] both
# land on the same line: pack source lives in a tree a judged session writes, so a
# census of the pack's own entry points, published by the pack, is a census that
# session can shorten. The derivation lives in the test.
layering_sources() {
  local root="$1" f first kind where rc=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    first=''
    first="$(head -n 1 "$f")" || first=''
    case "$first" in
      '#!'*bash*) kind=entry ;;
      '# shellcheck shell=bash') kind=lib ;;
      *) kind='' ;;
    esac
    case "$f" in
      "$root"/lib/* | "$root"/*/lib/*) where=lib ;;
      *) where=entry ;;
    esac
    if [ -z "$kind" ]; then
      printf 'unclassified\t%s\tits first line is neither a bash shebang nor the `# shellcheck shell=bash` of a sourced module\n' "$f"
      rc=1
      continue
    fi
    if [ "$kind" != "$where" ]; then
      printf 'unclassified\t%s\tit reads as an entry point or a lib by its first line (%s) and sits where the other one goes (%s)\n' \
        "$f" "$kind" "$where"
      rc=1
      continue
    fi
    printf '%s\t%s\n' "$kind" "$f"
  done <<FILES
$(layering__shell_files "$root")
FILES
  return "$rc"
}

# The files one rule walks: those of `want` — `lib`, `entry`, or `any` — plus,
# never dropped, one `!`-prefixed line per source the classification refused.
#
# The prefix is how a refusal reaches the rule that asked: a path starts with a
# slash, so no finding can be mistaken for a file. A rule that filtered the
# refusals out would be a rule that reads a pack holding an unreadable file
# exactly like a clean one, which is the failure the teeth test below exists to
# make impossible.
layering__zone() {
  local root="$1" want="$2" kind path note rc=0
  while IFS="$(printf '\t')" read -r kind path note; do
    [ -n "$kind" ] || continue
    case "$kind" in
      unclassified)
        printf '!%s is neither a lib nor an entry point: %s\n' "${path#"$root"/}" "$note"
        rc=1
        ;;
      *)
        [ "$want" = any ] || [ "$kind" = "$want" ] || continue
        printf '%s\n' "$path"
        ;;
    esac
  done <<SOURCES
$(layering_sources "$root")
SOURCES
  return "$rc"
}

# ── the rules ────────────────────────────────────────────────────────────────

# Every call into another module's internals, one finding per line. Comments are
# stripped first: a comment naming a neighbour's internal is documentation, not a
# dependency. Non-zero when it found something, so `run` reads naturally.
#
# Libs and entry points both, because an entry point outside the zone is one where
# a lib's `__` internals are reachable with nothing to say so. Each file owns the
# prefix `basename … .sh | tr '-' '_'` gives it — `human_loop` for
# `human-loop.sh`, `init` for `init.sh` — which is the same rule the libs get,
# arrived at by the same line.
layering_privates() {
  local root="$1" f own call mod rc=0
  while IFS= read -r f; do
    case "$f" in
      '') continue ;;
      '!'*)
        printf '%s\n' "${f#"!"}"
        rc=1
        continue
        ;;
    esac
    own="$(basename "$f" .sh | tr '-' '_')"
    for call in $(grep -v '^[[:space:]]*#' "$f" |
      grep -o '[a-z][a-z0-9_]*__[a-z0-9_]*' | sort -u); do
      mod="${call%%__*}"
      [ "$mod" = "$own" ] && continue
      printf '%s calls %s, which is private to %s\n' "$(basename "$f")" "$call" "$mod"
      rc=1
    done
  done <<ZONE
$(layering__zone "$root" any)
ZONE
  return "$rc"
}

# Every call from a lib up into the loop that drives it.
#
# Libs only, and [87] decided that by measuring rather than by inheriting it. The
# rule's sentence is about the *stack*: a lib sits under the loop, so a lib naming
# `loop_*` is a lib nothing can reuse without the loop. An entry point sits under
# nothing, and the three the pack ships each say so differently — `loop.sh` *is*
# the loop; `human-loop.sh` shares its locks and its sink and is entitled to its
# public surface; and `init.sh` names `loop_preflight` on purpose, in the
# `grep -v` of `init_refusals`, because [19] derives the list of things the loop
# refuses to start on from `loop.sh`'s body instead of retyping it.
#
# So extending this rule upward would need two carve-outs on the pack as
# delivered: one for the loop itself, one to tell a grep pattern from a call. A
# rule with a carve-out is one that gets worked around rather than obeyed — the
# same argument `layering_heredoc_prose` makes below for not reporting the two
# forms that fix it. The teeth test asserts the decision rather than leaving it to
# this paragraph: the planted pack's `init.sh` really does carry the name, and
# this rule really does not report it.
layering_upward() {
  local root="$1" f call rc=0
  while IFS= read -r f; do
    case "$f" in
      '') continue ;;
      '!'*)
        printf '%s\n' "${f#"!"}"
        rc=1
        continue
        ;;
    esac
    for call in $(grep -v '^[[:space:]]*#' "$f" |
      grep -o 'loop_[a-z0-9_]*' | sort -u); do
      printf '%s calls %s: a lib must not depend on the loop\n' "$(basename "$f")" "$call"
      rc=1
    done
  done <<ZONE
$(layering__zone "$root" lib)
ZONE
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
  local root="$1" f line rc=0
  while IFS= read -r f; do
    case "$f" in
      '') continue ;;
      '!'*)
        printf '%s\n' "${f#"!"}"
        rc=1
        continue
        ;;
    esac
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      printf '%s: %s masks the status of the substitution it assigns\n' \
        "$(basename "$f")" "$line"
      rc=1
    done <<MASKED
$(grep -nE '^[[:space:]]*(local|export|declare|readonly|typeset)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*="?\$\(' "$f")
MASKED
  done <<ZONE
$(layering__zone "$root" any)
ZONE
  return "$rc"
}

# Every unescaped backtick in the body of an **unquoted** heredoc, one finding
# per line.
#
# [61]'s defect, as a rule about the source, because that is the only place it is
# visible. In `cat <<PROMPT` a backtick is a command substitution: the paragraph
# [58] added to `router_prompt` named two tracker fields the way markdown names
# them, and what the session received had two holes where the names were while
# the human watched `router.sh: line 1015: Status:: command not found` scroll past
# on every routed session. Nothing turned red — a substitution that fails inside a
# heredoc prints to stderr, hands back an empty string, and the prompt goes out.
#
# **Backticks and not `$`, and the asymmetry is the reason — but it is weaker
# than it reads.** A `$word` written in prose is caught by `set -euo pipefail`: an
# unbound variable kills the run, loudly, at the first session. That is true of
# two of the three entry points. `init.sh` carries `set -uo pipefail` **without
# `-e`**, on purpose and written down at `init.sh:39` — it sources the pack's libs
# and calls their public censuses, which answer non-zero for "nothing to say", so
# errexit would end the installer on the tidiest machine at its first honest
# answer. Measured under `set -u` alone: an undefined `$word` in a `cat <<BLOCK`
# writes "unbound variable" to stderr, makes the `cat` return 1, and **the script
# carries on**. What catches it there is the `|| init__die` every mutating step
# carries, not errexit. A backtick is caught by nothing anywhere.
#
# The residue this leaves is named rather than guarded — a prose heredoc that
# writes the name of a variable that *is* set (`$HOME`, `$LANG_ARTIFACT`) still
# substitutes it in silence, and what stands between that and a prompt is a
# reader. `docs/frontiere-de-confiance.md` carries the line.
#
# The escape is what the rest of the pack already does — `loop.sh`, `lenses.sh`,
# `retro.sh`, `capability.sh` and `failures.sh` all write \` in prose — so this is
# a rule and not a migration. `router_prompt` went further and quotes its
# heredocs outright, which is the only form no future paragraph can break.
#
# The file this rule was least able to reach until [87] is the one it costs the
# most on: `init.sh` carries nine unquoted heredocs, two of which write into the
# target project, and one of those writes `CLAUDE.md` — sealed by [31] and read by
# every fresh `claude` in that project for the life of the repository. [61] paid a
# ticket for this fault in the prompt of one session; here it reaches every
# session of a project, and the installer runs once.
layering_heredoc_prose() {
  local root="$1" f found rc=0
  while IFS= read -r f; do
    case "$f" in
      '') continue ;;
      '!'*)
        printf '%s\n' "${f#"!"}"
        rc=1
        continue
        ;;
    esac
    found="$(awk -v name="$(basename "$f")" '
      BEGIN { inbody = 0; SQ = sprintf("%c", 39) }
      inbody {
        line = $0
        if (dash) sub(/^\t+/, "", line)
        if (line == delim) { inbody = 0; next }
        if (quoted) next
        # Drop every escaped pair first, backslash-backslash included, so that a
        # `\`` reads as prose and a lone backtick is what is left.
        probe = $0
        gsub(/\\./, "", probe)
        if (index(probe, "`") > 0)
          printf "%s:%d: an unescaped backtick in the body of an unquoted heredoc, which is a command substitution and not prose\n", name, FNR
        next
      }
      /^[[:space:]]*#/ { next }
      {
        p = index($0, "<<")
        if (p == 0) next
        rest = substr($0, p + 2)
        if (substr(rest, 1, 1) == "<") next
        dash = 0
        if (substr(rest, 1, 1) == "-") { dash = 1; rest = substr(rest, 2) }
        quoted = 0
        if (substr(rest, 1, 1) == "\"" || substr(rest, 1, 1) == SQ) {
          quoted = 1
          rest = substr(rest, 2)
        }
        if (substr(rest, 1, 1) !~ /[A-Za-z_]/) next
        delim = ""
        for (i = 1; i <= length(rest); i++) {
          c = substr(rest, i, 1)
          if (c !~ /[A-Za-z0-9_]/) break
          delim = delim c
        }
        inbody = 1
      }
    ' "$f")" || found=''
    [ -n "$found" ] || continue
    printf '%s\n' "$found"
    rc=1
  done <<ZONE
$(layering__zone "$root" any)
ZONE
  return "$rc"
}

# Every unescaped backtick the shell would run outside a single-quoted string,
# one finding per line.
#
# [61]'s defect again, in the form the pack actually writes its prose in.
# `layering_heredoc_prose` above reads the body of an unquoted heredoc, because
# that is where [61] happened to land; but the pack writes far more prose into
# double-quoted arguments — 52 sites where the escape `\`` is load-bearing, 30 of
# them in `init.sh`. Measured on a real run of the installer ([90]): one
# un-escaped backtick in the `init__note` at `init.sh:375` and the operator reads
# "·  is not on this PATH. Every session, review lens, retro and value gate is a
# process…" with the word `claude` gone from both holes, the installer exits **0**,
# and a single `command not found` is lost in a forty-line report. The rule above
# is green on that file: the hole is in an argument, not in a body.
#
# The mechanism of the silence is [61]'s word for word — a substitution that fails
# inside an argument writes to stderr, hands back an empty string, and does not
# change the status of the command.
#
# Escaped (`\``) or single-quoted, a backtick is prose the shell never reads, and
# neither form is reported. That is the same argument the rule above makes for
# itself: a rule that flagged the two forms that fix the defect would be worked
# around rather than obeyed. It is also what makes this a rule and not a
# migration — the hundreds of other backticks in the pack live inside
# `printf '…'`, which is the pack's de-facto convention, and a scanner run over
# the delivered pack finds no unescaped backtick in a double-quoted string at all.
#
# **The cost here is the scanner, not the rule**, which is why the boundary is a
# guarantee of its own with witnesses of its own. A heredoc has a delimiter, so
# knowing whether you are inside one is free. A quote has none: `'`, `"`, `\` and
# `$( )` have to be followed across lines, and a state machine that loses track is
# worse than no rule at all. Counted both ways: a line-by-line scanner reports
# three findings on the delivered pack and all three are false. The shapes it has
# to get right, each planted below with a real violation on the far side of it so
# that losing the state is a red test and not a quiet miss:
#
#   - a single-quoted string opened on one line and closed on another — the body
#     of an `awk '…'` at `lang.sh:176`, where the backticks are a markdown fence
#     the shell never reads;
#   - a `$( … )` that reopens quoting inside a double-quoted string —
#     `gate.sh:3081`, where `tr -d '`,'` sits inside two levels of quoting;
#   - a comment, where a backtick is prose and an apostrophe is not an opening
#     quote;
#   - the body of a heredoc, which belongs to the rule above and is skipped here.
#
# And a file the machine cannot read back to the top is a finding rather than a
# clean answer, for the same reason [87] carries an unclassifiable source through
# as one: a scanner that desynchronised would otherwise read exactly like a pack
# with nothing in it.
layering_quoted_prose() {
  local root="$1" f found rc=0
  while IFS= read -r f; do
    case "$f" in
      '') continue ;;
      '!'*)
        printf '%s\n' "${f#"!"}"
        rc=1
        continue
        ;;
    esac
    found="$(awk -v name="$(basename "$f")" '
      BEGIN {
        SQ = sprintf("%c", 39); DQ = sprintf("%c", 34); BS = sprintf("%c", 92)
        depth = 1; stack[1] = "U"; head = 1; tail = 0; inbody = 0
      }
      function say(where) {
        if (said) return
        printf "%s:%d: an unescaped backtick %s, which is a command substitution and not prose\n", name, FNR, where
        said = 1
      }
      {
        line = $0
        # A heredoc body belongs to the rule above, and reading it as code here
        # would desynchronise on the first apostrophe of a prose paragraph.
        if (inbody) {
          probe = line
          if (hd_dash[head]) sub(/^\t+/, "", probe)
          if (probe == hd_delim[head]) { head++; inbody = (head <= tail) }
          next
        }
        said = 0; n = length(line); i = 1
        while (i <= n) {
          c = substr(line, i, 1); top = stack[depth]
          # Inside a single-quoted string nothing is special but the closing
          # quote, which is why prose survives there and why this state has to
          # outlive the line that opened it.
          if (top == "S") { if (c == SQ) depth--; i++; continue }
          if (c == BS) { i += 2; continue }
          if (top == "D") {
            if (c == DQ) { depth--; i++; continue }
            if (c == "`") { say("inside a double-quoted string"); i++; continue }
            if (c == "$" && substr(line, i + 1, 1) == "(") { depth++; stack[depth] = "U"; i += 2; continue }
            i++; continue
          }
          if (c == SQ) { depth++; stack[depth] = "S"; i++; continue }
          if (c == DQ) { depth++; stack[depth] = "D"; i++; continue }
          if (c == "`") { say("in an unquoted word"); i++; continue }
          if (c == "$" && substr(line, i + 1, 1) == "(") { depth++; stack[depth] = "U"; i += 2; continue }
          if (c == ")") { if (depth > 1) depth--; i++; continue }
          # A word starting with # is a comment to the end of the line, so its
          # backticks are prose and its apostrophes open nothing.
          if (c == "#" && (i == 1 || index(" \t;&|(", substr(line, i - 1, 1)) > 0)) break
          if (c == "<" && substr(line, i + 1, 1) == "<") {
            if (substr(line, i + 2, 1) == "<") { i += 3; continue }
            j = i + 2; dash = 0
            if (substr(line, j, 1) == "-") { dash = 1; j++ }
            while (substr(line, j, 1) == " ") j++
            q = ""
            if (substr(line, j, 1) == SQ || substr(line, j, 1) == DQ) { q = substr(line, j, 1); j++ }
            if (substr(line, j, 1) !~ /[A-Za-z_]/) { i = j; continue }
            d = ""
            while (j <= n) { ch = substr(line, j, 1); if (ch !~ /[A-Za-z0-9_]/) break; d = d ch; j++ }
            if (q != "" && substr(line, j, 1) == q) j++
            tail++; hd_delim[tail] = d; hd_dash[tail] = dash
            i = j; continue
          }
          i++
        }
        if (tail >= head) inbody = 1
      }
      END {
        if (depth != 1)
          printf "%s: a quote opened in this file is never closed, so this rule could not read it to the end\n", name
        else if (inbody)
          printf "%s: a heredoc body never meets its delimiter, so this rule could not read it to the end\n", name
      }
    ' "$f")" || found=''
    [ -n "$found" ] || continue
    printf '%s\n' "$found"
    rc=1
  done <<ZONE
$(layering__zone "$root" any)
ZONE
  return "$rc"
}

# ── the teeth ────────────────────────────────────────────────────────────────

# A copy of the real pack with a violation of each kind planted in it. A copy,
# not the pack itself: a run interrupted halfway must not leave the repository
# holding a bogus function.
#
# It mirrors the shipped layout rather than flattening it — `.claude/` with the
# libs and the two loops under it, `init.sh` beside it at the root — because since
# [87] the zone is derived from that layout, and a planted pack shaped differently
# from the real one would exercise a walk the real pack never takes.
layering__planted_pack() {
  local dest="$RALPH_TEST_DIR/planted"
  mkdir -p "$dest/.claude"
  cp -R "$RALPH_PACK_ROOT/.claude/lib" "$dest/.claude/lib"
  cp "$RALPH_PACK_ROOT/.claude/loop.sh" "$dest/.claude/loop.sh"
  cp "$RALPH_PACK_ROOT/.claude/human-loop.sh" "$dest/.claude/human-loop.sh"
  cp "$RALPH_PACK_ROOT/init.sh" "$dest/init.sh"
  printf 'probe_reaches_in() { gate__scope_guard x y z; }\n' >>"$dest/.claude/lib/state.sh"
  printf 'probe_reaches_up() { loop_log hi; }\n' >>"$dest/.claude/lib/state.sh"
  printf 'probe_masks_status() {\n  local tree="$(gate_tree_snapshot)"\n}\n' \
    >>"$dest/.claude/lib/state.sh"
  # The shape that must *not* be reported, planted beside it: a rule that flagged
  # this would be worked around rather than obeyed.
  printf 'probe_default_value() {\n  local host="${1:-$(hostname 2>/dev/null || printf x)}"\n}\n' \
    >>"$dest/.claude/lib/state.sh"
  # And the same violation in the *other* entry point, which is what keeps the
  # derived zone honest ([16]). A check that walked `loop.sh` by name would read a
  # pack with a second entry point exactly like a clean one, and `human-loop.sh`
  # reaching into `loop__arm_successor` — the one call [09] forbids it — is
  # precisely the shape that would go unremarked.
  printf 'probe_second_entry() { loop__arm_successor; }\n' >>"$dest/.claude/human-loop.sh"
  # And in the *third*, which is [87]'s own ([19] shipped it outside `.claude/**`
  # and nothing here read it for four tickets). Appended rather than edited into
  # place: [86] rewrites the prose of `init_claude_block` next, and a plant
  # anchored on a sentence of that block would drift into a green the day it
  # lands. The prefix `init_` is what `basename … .sh` gives this file, so
  # `gate__scope_guard` is a reach into a neighbour here exactly as it is in a lib
  # — that is asserted below rather than assumed.
  cat >>"$dest/init.sh" <<'PLANTED'
probe_init_reaches_in() { gate__scope_guard x y z; }
probe_init_masks_status() {
  local tree="$(gate_tree_snapshot)"
}
probe_init_prose_heredoc() {
  cat <<PROSE
The conventions this pack deposits are in `docs/agents/`.
PROSE
}
PLANTED
  # And [61]'s, with both of its paired witnesses beside it. The escape and the
  # quote are the two forms that keep prose out of the shell, and a rule that
  # reported either would be worked around rather than obeyed.
  cat >>"$dest/.claude/lib/state.sh" <<'PLANTED'
probe_prose_heredoc() {
  cat <<PROSE
The drain took every ticket's `Status:` before this session started.
PROSE
}
probe_escaped_heredoc() {
  cat <<PROSE
The drain took every ticket's \`Escalation:\` before this session started.
PROSE
}
probe_quoted_heredoc() {
  cat <<'PROSE'
The drain took every ticket's `Blocked by:` before this session started.
PROSE
}
PLANTED
  # And [90]'s, in the form the pack writes most of its prose in. The first four
  # are violations — three in a double-quoted string, one in a bare word — and
  # the last three are the boundary this rule is mostly made of: a single-quoted
  # program that outlives the line that opened it, a substitution that reopens
  # quoting two levels deep, and a comment whose apostrophe opens nothing. Each
  # boundary carries a real violation on its far side, so a state machine that
  # lost track there fails this test instead of quietly missing everything after
  # it.
  #
  # The paired witnesses carry the same sentence and the same backticks as the
  # violation: escaped in a double-quoted string, and whole inside a single-quoted
  # one. Those are the two forms that fix the defect, and a rule reporting either
  # would be worked around rather than obeyed.
  cat >>"$dest/.claude/lib/state.sh" <<'PLANTED'
probe_quoted_prose() {
  printf '%s\n' "The drain took every `Status:` field before this session started."
}
probe_escaped_quote() {
  printf '%s\n' "The drain took every \`Status:\` field before this session started."
}
probe_single_quote() {
  printf '%s\n' 'The drain took every `Status:` field before this session started.'
}
probe_unquoted_word() {
  printf '%s\n' The drain took every `Status:` field before this session started.
}
probe_multiline_program() {
  awk '
    { if (0) print "```" }
  ' /dev/null
  printf '%s\n' "The drain took every `Status:` field before this session started."
}
probe_reopened_quote() {
  printf '%s\n' "$(printf '%s' "$1" | tr -d '`,')"
  printf '%s\n' "The drain took every `Status:` field before this session started."
}
probe_prose_comment() {
  # prose in a comment, apostrophes and all: a `Status:` field that isn't code
  printf '%s\n' "The drain took every `Status:` field before this session started."
}
PLANTED
  # The same thing in the third entry point, which is where 30 of the pack's 52
  # load-bearing escapes live and where [90] measured the defect on a real run.
  cat >>"$dest/init.sh" <<'PLANTED'
probe_init_quoted_prose() {
  init__note "the conventions this pack deposits are in `docs/agents/`."
}
PLANTED
  # A file no state machine can read to the end. Without it a scanner that
  # desynchronised on the first odd quote would answer "nothing found" for
  # everything after it, and read exactly like a clean pack.
  cat >"$dest/.claude/lib/unbalanced.sh" <<'PLANTED'
# shellcheck shell=bash
probe_unbalanced() {
  printf '%s\n' 'a quote that opens here and never closes
}
PLANTED
  # Two files the criterion cannot place, one of each shape: a first line that is
  # neither marker, and a file whose marker and whose position disagree. Without
  # them a derivation that silently dropped what it could not classify would be
  # indistinguishable from one that classified everything.
  printf '# a script, of some kind, that says nothing about what it is\nprobe_stray() { :; }\n' \
    >"$dest/.claude/stray.sh"
  printf '#!/usr/bin/env bash\nprobe_misplaced() { :; }\n' \
    >"$dest/.claude/lib/misplaced.sh"
  printf '%s\n' "$dest"
}

# The first or the last line of a planted probe's body, read out of the planted
# file rather than counted by hand.
#
# [90]'s assertions name a violation and refute a witness by line number, which is
# the only handle there is: a finding is `file:line:` and a sentence about the
# shape, never the text of the offending line. A hand-counted offset would drift
# into a green the first time a probe grows a line, so the number is derived and
# an empty answer is a failure rather than a silent pass.
layering__probe_body() {
  local file="$1" fn="$2" end="$3"
  awk -v head="$fn() {" -v end="$end" '
    $0 == head { start = FNR; next }
    start && $0 == "}" { print (end == "last" ? FNR - 1 : start + 1); exit }
  ' "$file"
}

@test "the zone these rules walk is derived from the pack, not written as a glob" {
  run layering_sources "$RALPH_PACK_ROOT"
  assert_success

  tab="$(printf '\t')"
  # The three entry points the pack ships, the third of which is what [87] is
  # for: `init.sh` sits at the repository root, outside `.claude/**`, where the
  # hand-written glob had no way to grow to it.
  assert_output_contains "entry$tab$RALPH_PACK_ROOT/.claude/loop.sh"
  assert_output_contains "entry$tab$RALPH_PACK_ROOT/.claude/human-loop.sh"
  assert_output_contains "entry$tab$RALPH_PACK_ROOT/init.sh"
  assert_output_contains "lib$tab$RALPH_PACK_ROOT/.claude/lib/gate.sh"

  # And every file the walk found came back classified. Both sides derived, and
  # neither counted by hand: a classification that dropped what it could not
  # place would read exactly like a pack in which everything is placed.
  assert_equal "$(printf '%s\n' "$output" | grep -c .)" \
    "$(layering__shell_files "$RALPH_PACK_ROOT" | grep -c .)"

  # The pruned zones are pruned, and the witness is a real file in each: a walk
  # that reached into `test/` would judge this harness, and one that reached into
  # `.scratch/` would judge a prototype's `init.sh` as a fourth entry point.
  refute_output_contains "$RALPH_PACK_ROOT/test/run.sh"
  refute_output_contains "$RALPH_PACK_ROOT/.scratch/"
}

@test "no module reaches into another module's internals" {
  run layering_privates "$RALPH_PACK_ROOT"
  assert_success
}

@test "no lib depends on the loop that drives it" {
  run layering_upward "$RALPH_PACK_ROOT"
  assert_success
}

@test "no declaration swallows the status of what it is assigned from" {
  run layering_masked_status "$RALPH_PACK_ROOT"
  assert_success
}

@test "no unquoted heredoc carries a backtick the shell will run" {
  run layering_heredoc_prose "$RALPH_PACK_ROOT"
  assert_success
}

@test "no double-quoted string carries a backtick the shell will run" {
  run layering_quoted_prose "$RALPH_PACK_ROOT"
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
  # The third entry point, judged by the same line as the other two: `init.sh`
  # owns `init_`, which is what `basename … .sh` hands it, so a neighbour's
  # internal is a finding here without the rule knowing this file exists.
  assert_output_contains "init.sh calls gate__scope_guard, which is private to gate"
  # And the two sources the derivation refused, carried through this rule rather
  # than filtered out of it.
  #
  # Anchored at the start of a line, and the anchor is the whole assertion. With
  # the `!` prefix gone the refusal reaches the rule as if it were a path, and the
  # `grep: <the sentence>: No such file or directory` that comes back on stderr
  # carries every word of the sentence — `run` merges stderr, so a substring
  # assertion passes on the error message. Measured: it did, and the entry that
  # takes the prefix away came back VACUOUS against a test that looked right.
  assert_equal "$(printf '%s\n' "$output" |
    grep -c '^\.claude/stray\.sh is neither a lib nor an entry point')" "1"
  assert_equal "$(printf '%s\n' "$output" |
    grep -c '^\.claude/lib/misplaced\.sh is neither a lib nor an entry point')" "1"

  run layering_upward "$planted"
  assert_failure
  assert_output_contains "state.sh calls loop_log"
  # And the decision this rule documents, asserted instead of described. The
  # installer is in the derived zone — the run above reports it — and it really
  # does carry the name, in the `grep -v` of `init_refusals`; this rule is the one
  # that does not report it, because an entry point sits under no loop.
  refute_output_contains "init.sh calls loop_"
  [ -n "$(grep -v '^[[:space:]]*#' "$planted/init.sh" |
    grep -o 'loop_[a-z0-9_]*')" ] ||
    fail "init.sh no longer names a loop_ function, so the refutation above proves nothing"

  run layering_masked_status "$planted"
  assert_failure
  assert_output_contains "state.sh: "
  assert_output_contains "init.sh: "
  assert_output_contains "local tree="
  # And the paired witness of the rule's own boundary: a default value is not a
  # masked status, and the planted one beside it is not reported.
  refute_output_contains "local host="

  run layering_heredoc_prose "$planted"
  assert_failure
  assert_output_contains "state.sh:"
  assert_output_contains "init.sh:"
  assert_output_contains "an unescaped backtick in the body of an unquoted heredoc"
  # Two findings and not four. The escaped copy and the quoted copy carry the
  # same sentence and the same backticks: if either were reported the rule would
  # be flagging the two forms that fix it, and if the count were not asserted a
  # rule that reported *every* backtick would pass this test.
  assert_equal "$(printf '%s\n' "$output" | grep -c 'unescaped backtick')" "2"

  run layering_quoted_prose "$planted"
  assert_failure
  assert_output_contains "an unescaped backtick inside a double-quoted string"
  assert_output_contains "an unescaped backtick in an unquoted word"

  # The lines this rule reports and the lines it does not, as one set rather than
  # as a count. A count catches a rule that reports every backtick; only the set
  # catches a rule that reports the escaped copy *instead of* the bare one, or one
  # that finds the violation before a boundary and nothing after it.
  state="$planted/.claude/lib/state.sh"
  expected="$(printf '%s\n' \
    "$(layering__probe_body "$state" probe_quoted_prose first)" \
    "$(layering__probe_body "$state" probe_unquoted_word first)" \
    "$(layering__probe_body "$state" probe_multiline_program last)" \
    "$(layering__probe_body "$state" probe_reopened_quote last)" \
    "$(layering__probe_body "$state" probe_prose_comment last)" | sort -n)"
  assert_equal "$(printf '%s\n' "$expected" | grep -c .)" "5"
  assert_equal "$(printf '%s\n' "$output" |
    sed -n 's/^state\.sh:\([0-9]*\):.*/\1/p' | sort -n)" "$expected"

  # The two forms that fix the defect, named rather than left to the set above:
  # the same sentence and the same backticks, escaped in a double-quoted string
  # and whole inside a single-quoted one.
  escaped="$(layering__probe_body "$state" probe_escaped_quote first)"
  single="$(layering__probe_body "$state" probe_single_quote first)"
  [ -n "$escaped" ] && [ -n "$single" ] ||
    fail "the paired witnesses of [90] are gone, so the refutations below prove nothing"
  refute_output_contains "state.sh:$escaped:"
  refute_output_contains "state.sh:$single:"

  # The third entry point, where the defect was measured on a real run.
  planted_init="$(layering__probe_body "$planted/init.sh" probe_init_quoted_prose first)"
  [ -n "$planted_init" ] ||
    fail "the planted violation in init.sh is gone, so the assertion below proves nothing"
  assert_output_contains "init.sh:$planted_init:"

  # And the file the state machine could not read back to the top, which is a
  # finding and not a clean answer.
  assert_output_contains "unbalanced.sh: a quote opened in this file is never closed"
}
