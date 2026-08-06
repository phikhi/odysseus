#!/usr/bin/env bats
#
# The language gate ([17]).
#
# Two keys and one check. `LANG_ARTIFACT` is the language durable prose is
# written in; `LANG_INTERACT` is the language an agent speaks to a human, and no
# session this loop spawns is ever told it. The rule used to live only in the
# session prompt — docs/frontiere-de-confiance.md listed it as held by nothing —
# and this file is what holds it: a fourth branch of the objective phase, reading
# back what the iteration wrote.
#
# What every test here has to keep honest, because it is where a language check
# goes wrong: it must judge the tree the *gate* judges and not the working
# directory (the suite is writing there at the same time), it must let a
# quotation through, and it must refuse to be switched off in silence.

load helpers/harness
load helpers/assert

setup() {
  harness_setup
}

teardown() {
  harness_teardown
}

# A ticket whose write-surface is prose, which the fixture tickets deliberately
# are not: `src/alpha.txt` is a marker file, and the shipped LANG_PROSE_PATHS
# reads a `.txt` as data rather than as documentation.
lang_ticket() {
  local id="$1" surface="$2"
  {
    printf '# %s\n\n' "$id"
    printf '**What to build:** A ticket written by test/lang.bats.\n\n'
    printf '**Blocked by:** None\n\n'
    printf '**Write-surface:** %s\n\n' "$surface"
    printf '**Status:** ready-for-agent\n\n'
    printf -- '- [ ] The document exists.\n'
  } >"$TRACKER_DIR/$id.md"
}

# Enough prose to be judged at all, in each of the two languages this file uses.
# Written out rather than generated: a detector is only as good as the text it is
# shown, and a test that fed it `the the the` would be measuring nothing.
lang_english() {
  cat <<'PROSE'
# The delivery loop

This document explains what the loop does with a ticket, and what it will not do
on its own. The gate is the part that decides whether the work can be committed,
and it does not ask a model for that answer. If any of the checks is red, the
iteration is rolled back and the ticket goes round again with a fresh session.
PROSE
}

lang_french() {
  cat <<'PROSE'
# La boucle de livraison

Ce document explique ce que la boucle fait d'un ticket, et ce qu'elle ne fera pas
toute seule. Le gate est la partie qui decide si le travail peut etre commite, et
il ne demande pas la reponse a un modele. Si l'un des controles est rouge, alors
l'iteration est annulee et le ticket repasse dans la file avec une session
fraiche.
PROSE
}

# A session that writes one file with content of its own, rather than the
# harness's four-word marker. The gate has to have prose to read.
script_session_writing_prose() {
  local target="$1"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'mkdir -p "$(dirname %s)"\n' "$target"
    printf 'cat >%s <<%s\n' "$target" "'PROSE'"
    cat
    printf 'PROSE\n'
    printf '%s\n' \
      "echo '{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"num_turns\":1,\"total_cost_usd\":0.02}'"
  } | script_claude
}

# ── the detector ─────────────────────────────────────────────────────────────

@test "the detector reads the dominant language of a text, not its subject" {
  # Both directions in one test on purpose: a scorer that answered `en` to
  # everything would pass the first half, and one that answered whatever it was
  # asked for would pass the second.
  lang_english >"$RALPH_TEST_DIR/en.md"
  lang_french >"$RALPH_TEST_DIR/fr.md"

  # <recognised> <hits for the language asked about> <dominant> <its hits>
  pack_run "lang_measure en <'$RALPH_TEST_DIR/en.md'"
  assert_success
  assert_equal "$(printf '%s\n' "$output" | awk '{ print $3 }')" "en"

  pack_run "lang_measure en <'$RALPH_TEST_DIR/fr.md'"
  assert_success
  assert_equal "$(printf '%s\n' "$output" | awk '{ print $3 }')" "fr"
  assert_equal "$(printf '%s\n' "$output" | awk '{ print $2 }')" "0"
}

@test "a word two languages claim votes for neither" {
  # The rule that lets the shipped lists be written generously instead of being
  # hand-made disjoint. Driven through lang_table so the assertion is about the
  # scorer and not about which words happen to be in the shipped lists today.
  #
  # `alpha` is claimed by both, `beta` only by the first: a scorer without the
  # rule reports two recognised words and a tie it breaks alphabetically, which
  # is a language decided by a word that says nothing about language.
  pack_run '
    lang_codes() { printf "aa\nbb\n"; }
    lang_words_aa() { printf "alpha beta\n"; }
    lang_words_bb() { printf "alpha gamma\n"; }
    printf "%s\n" "$(printf "alpha alpha alpha beta\n" | lang_measure aa)"'
  assert_success
  # One recognised word — the three `alpha` say nothing — and it is `beta`.
  assert_output_contains "1 1 aa 1"
}

@test "a file with too little prose is not judged, and is counted as such" {
  # The tolerance that keeps the gate from teaching a project to switch it off. A
  # stub, a table of identifiers, a two-line note: not evidence of a language.
  lang_ticket 01-doc 'docs/note.md'
  printf 'TODO: fill this in.\n' | script_session_writing_prose docs/note.md
  set_config LANG_ARTIFACT fr

  run_loop
  assert_success
  assert_ticket_status 01-doc resolved
  # And the zone is named rather than passed over: this is the count a human
  # reads to know how much of what was written nothing vouched for.
  assert_output_contains "could not tell the language of 1"
}

# ── the gate ─────────────────────────────────────────────────────────────────

@test "prose written in another language than LANG_ARTIFACT is red, and retryable" {
  lang_ticket 01-doc 'docs/guide.md'
  lang_french | script_session_writing_prose docs/guide.md
  set_config STERILE_K 1

  run_loop
  assert_output_contains "lang=red"
  assert_output_contains "wrote docs/guide.md"
  assert_output_contains "reads as fr"
  # Retryable, which is the whole difference with a scoping conflict: the ticket
  # comes back to the frontier with a retry spent, rather than going to a human.
  assert_ticket_status 01-doc ready-for-agent
  assert_equal "$(ticket_field 01-doc Failures)" "1"
  # And the work is not in the tree: a red gate rolls back like any other.
  refute_file_exists "$PROJECT_DIR/docs/guide.md"
}

@test "prose in LANG_ARTIFACT passes, quoted foreign terms and all" {
  # The refutation of the test above, and the reason the check is a share rather
  # than a match: an English document that quotes French terms and a command line
  # is an English document. Without this, the gate would be an incentive to write
  # documentation that never names anything.
  lang_ticket 01-doc 'docs/guide.md'
  {
    lang_english
    printf '\nThe French call this a `chien de garde`, and the flag is spelled\n'
    printf -- '--dangerously-skip-permissions. Both are kept as they are.\n'
  } | script_session_writing_prose docs/guide.md

  run_loop
  assert_success
  assert_output_contains "lang=green"
  assert_ticket_status 01-doc resolved
}

@test "an edit matches the language of the file, not LANG_ARTIFACT" {
  # The half of the ticket a share against a config key cannot express. A project
  # whose LANG_ARTIFACT is English may perfectly well have a French document in
  # it, and a loop that rewrote it into English on the first edit would be doing
  # damage nobody asked for.
  lang_ticket 01-doc 'docs/guide.md'
  mkdir -p "$PROJECT_DIR/docs"
  lang_french >"$PROJECT_DIR/docs/guide.md"
  git -C "$PROJECT_DIR" add docs/guide.md
  git -C "$PROJECT_DIR" commit -q -m "a document this project already had"

  {
    lang_french
    printf '\nUne section ajoutee par la session, dans la langue du fichier.\n'
  } | script_session_writing_prose docs/guide.md

  run_loop
  assert_success
  assert_output_contains "lang=green"
  assert_ticket_status 01-doc resolved
}

@test "the same edit in LANG_ARTIFACT is red, and says which language the file was in" {
  # The refutation of the one above. Without it, a gate that judged nothing at all
  # on an existing file would pass both.
  lang_ticket 01-doc 'docs/guide.md'
  mkdir -p "$PROJECT_DIR/docs"
  lang_french >"$PROJECT_DIR/docs/guide.md"
  git -C "$PROJECT_DIR" add docs/guide.md
  git -C "$PROJECT_DIR" commit -q -m "a document this project already had"

  lang_english | script_session_writing_prose docs/guide.md
  set_config STERILE_K 1

  run_loop
  assert_output_contains "lang=red"
  assert_output_contains "that file was already in fr"
  assert_ticket_status 01-doc ready-for-agent
}

@test "the language of an existing file is read from before the session, not after" {
  # The corollary this pack keeps rediscovering: a control whose input the
  # controlled writes is not a control. If the expected language were read off the
  # working tree, a session could set it by writing the file — and then every file
  # matches itself and the gate is a no-op that reports green.
  #
  # Staged with a file that exists in the base tree in English: the session
  # rewrites it whole in French, so the "language of the file" is French
  # everywhere except in the one place that is allowed to answer.
  lang_ticket 01-doc 'docs/guide.md'
  mkdir -p "$PROJECT_DIR/docs"
  lang_english >"$PROJECT_DIR/docs/guide.md"
  git -C "$PROJECT_DIR" add docs/guide.md
  git -C "$PROJECT_DIR" commit -q -m "a document this project already had"

  lang_french | script_session_writing_prose docs/guide.md
  set_config STERILE_K 1

  run_loop
  assert_output_contains "lang=red"
  assert_output_contains "that file was already in en"
}

@test "the gate judges the tree it was handed, not what the suite writes beside it" {
  # [29] one branch further along. TEST_CMD runs concurrently with this branch, so
  # a check that read the file off disk would answer about a state no other branch
  # is judging — and the verdict would depend on who wrote first.
  #
  # Staged the way the defect would show: the session writes French, the project's
  # test command rewrites the same path in English while the gate runs. Red is the
  # right answer, because French is what the iteration delivered.
  lang_ticket 01-doc 'docs/guide.md'
  lang_french | script_session_writing_prose docs/guide.md

  {
    printf '#!/usr/bin/env bash\n'
    # Relative to wherever the suite runs, which since [13] is the iteration's own
    # worktree — an absolute path into the tree the run was started in would
    # rewrite a file this gate is not looking at, and the branch would read the
    # right thing for the wrong reason.
    printf 'cat >docs/guide.md <<%s\n' "'PROSE'"
    lang_english
    printf 'PROSE\n'
  } >"$RALPH_TEST_DIR/rewriter.sh"
  chmod +x "$RALPH_TEST_DIR/rewriter.sh"
  set_config TEST_CMD "bash $RALPH_TEST_DIR/rewriter.sh"
  set_config STERILE_K 1

  run_loop
  assert_output_contains "lang=red"
  assert_output_contains "reads as fr"
}

@test "a tree this branch cannot read refuses to pass rather than finding no prose" {
  # Fail-closed, and deliberately not delegated to the scope-guard's refusal on
  # the same tree: a guard whose fail-closed belongs to somebody else goes green
  # the day that somebody else moves ([34]).
  pack_run 'lang_check 01-alpha "" "" /dev/null'
  assert_failure
  assert_output_contains "could not read the working tree"
}

# ── what the gate does not judge, said out loud ──────────────────────────────

@test "the pack's own files are exempt, and the exemption is counted" {
  # This pack ships in English into projects of any language, so its own prose is
  # not judged against LANG_ARTIFACT. The count is the other half: LANG_EXEMPT_PATHS
  # is the key that could turn the whole check off without a word, so what it takes
  # out is announced where the coverage is ([24]).
  use_tickets 01-alpha
  set_config LANG_ARTIFACT fr

  pack_run '
    base="$(gate_tree_snapshot)"
    mkdir -p .claude src
    printf "The pack documents itself in English, whatever this project writes.\n" >.claude/NOTES.md
    printf "written\n" >src/alpha.txt
    lang_check 01-alpha "$base" "$(gate_tree_snapshot)" "$RALPH_SHIM_STATE/zone"
    printf "rc=%s\n" "$?"
    cat "$RALPH_SHIM_STATE/zone"'
  assert_success
  assert_output_contains "rc=0"
  assert_output_contains "did not look at 1"
}

@test "a name git prints quoted is counted, not judged" {
  # Found by probing this gate on real names, and it is not this gate's defect:
  # `git diff-tree --name-only` C-quotes anything outside pure ASCII, so
  # `docs/spécification.md` reaches every consumer of the changed-file list as
  # `"docs/sp\303\251cification.md"` — a string `git cat-file`, `git add` and
  # `rm` all refuse ([39]). Judging it is impossible; being silent about it would
  # hide a hole four mechanisms share.
  #
  # Two snapshots taken in two processes rather than one, because the file has to
  # be written between them and the harness's fake is not what stages this.
  use_tickets 01-alpha
  pack_run 'gate_tree_snapshot'
  assert_success
  local base="$output"

  mkdir -p "$PROJECT_DIR/docs"
  lang_french >"$PROJECT_DIR/docs/spécification.md"

  pack_run "lang_check 01-alpha '$base' \"\$(gate_tree_snapshot)\" '$SHIM_STATE/zone'; printf 'rc=%s\n' \"\$?\"; cat '$SHIM_STATE/zone'"
  assert_success
  # French prose in a project whose LANG_ARTIFACT is `en`, and green all the
  # same: reddening a project because one of its files has an accent in its name
  # is the false red on honest work this gate exists to avoid.
  assert_output_contains "rc=0"
  assert_output_contains "could not address 1"
}

@test "a project can switch the gate off, and every iteration says so" {
  # A decision a project is entitled to make — the pack has word lists for six
  # languages and there are rather more than six. What it must not be is quiet: a
  # run with no language gate has to be distinguishable from a run whose prose was
  # checked and found right.
  lang_ticket 01-doc 'docs/guide.md'
  lang_french | script_session_writing_prose docs/guide.md
  set_config LANG_CHECK off

  run_loop
  assert_success
  assert_ticket_status 01-doc resolved
  assert_output_contains "the language gate is off"
  refute_output_contains "lang=green"
}

# ── the preflight ────────────────────────────────────────────────────────────

@test "a LANG_ARTIFACT this pack has no words for is refused at the door" {
  # The failure this refusal exists to prevent is the silent one: with no word
  # list, every file is "too little prose to tell", the branch is green, and a
  # night of iterations reports a language gate that judged nothing at all.
  use_tickets 01-alpha
  set_config LANG_ARTIFACT ja

  run_loop
  assert_failure
  assert_output_contains "no word list for LANG_ARTIFACT"
  assert_output_contains "LANG_CHECK=off"
  # Refused before anything ran, not after a night of it.
  assert_equal "$(claude_call_count)" "0"
}

@test "a LANG_CHECK that is neither on nor off is refused, not read as off" {
  use_tickets 01-alpha
  set_config LANG_CHECK ON

  run_loop
  assert_failure
  assert_output_contains "it has to be on or off"
}

@test "a threshold that is not a fraction is refused, not read as zero" {
  # A threshold read as zero passes every file: the same switched-off-by-typo
  # shape as the two above, one layer down.
  use_tickets 01-alpha
  set_config LANG_CHECK_THRESHOLD "80%"

  run_loop
  assert_failure
  assert_output_contains "LANG_CHECK_THRESHOLD"

  set_config LANG_CHECK_THRESHOLD "0"
  run_loop
  assert_failure
  assert_output_contains "LANG_CHECK_THRESHOLD"
}

@test "the two keys that would silently leave nothing to judge are refused too" {
  # Read against the criterion — which value of which key makes this branch pass
  # everything without a word — rather than against the cases that prompted the
  # first three ([31]). An empty LANG_PROSE_PATHS is an off switch that says
  # nothing, where LANG_CHECK=off says it every iteration; a floor of zero words
  # divides by zero on the first file with no recognisable word, so the branch
  # dies with no verdict instead of judging.
  use_tickets 01-alpha
  set_config LANG_PROSE_PATHS ""

  run_loop
  assert_failure
  assert_output_contains "LANG_PROSE_PATHS is empty"

  set_config LANG_PROSE_PATHS "*.md"
  set_config LANG_CHECK_MIN_HITS "0"
  run_loop
  assert_failure
  assert_output_contains "LANG_CHECK_MIN_HITS"

  # And the refutation: put both back and the same project runs.
  set_config LANG_CHECK_MIN_HITS "12"
  run_loop
  assert_success
  assert_ticket_status 01-alpha resolved
}

# ── the rule the session is handed ───────────────────────────────────────────

@test "the session prompt carries LANG_ARTIFACT, and says the rule is checked" {
  lang_ticket 01-doc 'docs/guide.md'
  lang_english | script_session_writing_prose docs/guide.md
  set_config LANG_ARTIFACT fr
  set_config LANG_CHECK off

  run_loop
  run claude_call_stdin 1
  assert_output_contains "Durable prose you write"
  assert_output_contains "is in fr"
  # Off, so the prompt asks and does not claim: a rule advertised as checked while
  # nothing checks it is the exact confusion this ticket was opened to remove.
  refute_output_contains "This one is checked"
}

@test "the rule says it is checked when it is" {
  lang_ticket 01-doc 'docs/guide.md'
  lang_english | script_session_writing_prose docs/guide.md

  run_loop
  run claude_call_stdin 1
  assert_output_contains "This one is checked"
}

@test "an AFK session is never told LANG_INTERACT" {
  # The fourth acceptance criterion, asserted on what the loop actually sent
  # rather than on the code that builds it. `LANG_INTERACT` is the language of a
  # conversation with a human, and there is no human here.
  lang_ticket 01-doc 'docs/guide.md'
  lang_english | script_session_writing_prose docs/guide.md
  set_config LANG_INTERACT "klingon"

  run_loop
  run claude_call_stdin 1
  refute_output_contains "klingon"
  refute_output_contains "LANG_INTERACT"
}

@test "the AFK entry point does not read LANG_INTERACT at all" {
  # The structural half, on the real pack rather than on the installed copy. The
  # behavioural test above covers the prompt a delivery session gets; this one is
  # what a later ticket has to notice — the human loop ([16]) is a different entry
  # point, and the key belongs to it.
  run bash -c "grep -c 'LANG_INTERACT' '$RALPH_PACK_ROOT/.claude/loop.sh' || true"
  assert_output_contains "0"
}
