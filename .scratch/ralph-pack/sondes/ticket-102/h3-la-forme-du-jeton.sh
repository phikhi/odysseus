#!/usr/bin/env bash
# [102] h3 — the shape of the token the pack puts in GIT_CONFIG_PARAMETERS.
#   a. the old form 'core.hooksPath=/dev/null' is read by this git (the new form
#      'k'='v' needs git >= 2.31);
#   b. it wins over a core.hooksPath a session writes in the local config, and over
#      one in an include (command-line scope is read last);
#   c. it composes with a value the operator already exported;
#   d. it adds nothing to stderr;
#   (each case touches a tracked file first: `update-index --refresh` writes the
#   index — and so fires post-index-change — only when a stat changed)
#   e. git hands it to the git it runs itself (worktree add -> checkout).
set -u
w="$(mktemp -d "${TMPDIR:-/tmp}/h3.XXXXXX")"; trap 'rm -rf "$w"' EXIT
export GIT_AUTHOR_NAME=p GIT_AUTHOR_EMAIL=p@p GIT_COMMITTER_NAME=p GIT_COMMITTER_EMAIL=p@p
unset GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT
git init -q -b main "$w/r"; cd "$w/r"; echo a >a; git add a; git commit -q -m i --no-verify
mkdir -p .git/hooks "$w/elsewhere"
for d in .git/hooks "$w/elsewhere"; do
  printf '#!/bin/sh\necho "RAN %s" >>%s/log\n' "$d" "$w" >"$d/post-index-change"; chmod +x "$d/post-index-change"
done
fire() { : >"$w/log"; sleep 1; touch "$w/r/a"; "$@" >/dev/null 2>"$w/err"; printf '%-58s ran=[%s] stderr=[%s]\n' "$label" "$(tr '\n' ' ' <"$w/log")" "$(tr '\n' ' ' <"$w/err")"; }
tok="'core.hooksPath=/dev/null'"
label="none";                 fire git update-index --refresh
label="a. old form";          GIT_CONFIG_PARAMETERS="$tok" fire git update-index --refresh
git config core.hooksPath "$w/elsewhere"
label="b. session's local core.hooksPath, no token"; fire git update-index --refresh
label="b. session's local core.hooksPath, token";    GIT_CONFIG_PARAMETERS="$tok" fire git update-index --refresh
git config --unset core.hooksPath
printf '[core]\n\thooksPath = %s\n' "$w/elsewhere" >"$w/inc"; git config include.path "$w/inc"
label="b. include.path to core.hooksPath, token";    GIT_CONFIG_PARAMETERS="$tok" fire git update-index --refresh
git config --unset include.path
label="c. operator value + token";  GIT_CONFIG_PARAMETERS="'user.name=op' $tok" fire git update-index --refresh
label="c. operator NEW form + token"; GIT_CONFIG_PARAMETERS="'user.name'='op' $tok" fire git update-index --refresh
printf 'c. operator value still read: %s\n' "$(GIT_CONFIG_PARAMETERS="'user.name=op' $tok" git config user.name)"
printf 'c. token read: %s\n' "$(GIT_CONFIG_PARAMETERS="'user.name=op' $tok" git config core.hooksPath)"
printf '#!/bin/sh\necho "RAN post-checkout" >>%s/log\n' "$w" >.git/hooks/post-checkout; chmod +x .git/hooks/post-checkout
label="e. worktree add, token";  GIT_CONFIG_PARAMETERS="$tok" fire git worktree add -q --detach "$w/wt" HEAD
label="e. worktree add, none";   fire git worktree add -q --detach "$w/wt2" HEAD
