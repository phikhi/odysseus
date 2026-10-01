#!/usr/bin/env bash
# [102] h1 — which hook does each git verb the pack uses fire, measured verb by
# verb (the rule of [51]: probe the verb, not the family). Every hook name of
# githooks(5) is planted in the common dir, AND one config-based hook
# (`hook.<name>.command`, git >= 2.5x) listens on every event. Each verb runs in
# the shape the pack writes it, from a linked worktree (where an iteration runs)
# or from the main tree (where the pilot runs).
#
#   bash h1-les-verbes-du-pack.sh            # no override
#   bash h1-les-verbes-du-pack.sh params     # GIT_CONFIG_PARAMETERS core.hooksPath=/dev/null
#   bash h1-les-verbes-du-pack.sh count      # GIT_CONFIG_COUNT  core.hooksPath=/dev/null
set -u
mode="${1:-none}"
w="$(mktemp -d "${TMPDIR:-/tmp}/h1.XXXXXX")"
trap 'rm -rf "$w"' EXIT
log="$w/log"
export H1_LOG="$log"
export GIT_AUTHOR_NAME=p GIT_AUTHOR_EMAIL=p@p GIT_COMMITTER_NAME=p GIT_COMMITTER_EMAIL=p@p
unset GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

git init -q -b main "$w/repo"
git init -q --bare "$w/remote.git"
cd "$w/repo"
printf 'a\n' >a.txt; mkdir -p issues; printf 't\n' >issues/01.md
git add -A; git commit -q -m init --no-verify
git remote add origin "$w/remote.git"
git worktree add -q --detach "$w/wt" HEAD

common="$(git rev-parse --git-common-dir)"
mkdir -p "$common/hooks"
names='applypatch-msg pre-applypatch post-applypatch pre-commit pre-merge-commit prepare-commit-msg commit-msg post-commit pre-rebase post-checkout post-merge pre-push pre-receive update proc-receive post-receive post-update reference-transaction push-to-checkout pre-auto-gc post-rewrite sendemail-validate fsmonitor-watchman post-index-change'
for n in $names; do
  printf '#!/bin/sh\ncat >/dev/null 2>&1 &\nprintf "DIR %s\\n" >>"$H1_LOG"\nexit 0\n' "$n" >"$common/hooks/$n"
  chmod +x "$common/hooks/$n"
done
printf '#!/bin/sh\nprintf "CFG %%s\\n" "$1" >>"$H1_LOG"\ncat >/dev/null 2>&1\nexit 0\n' >"$w/cfg-hook"
chmod +x "$w/cfg-hook"
git config hook.probe.command "$w/cfg-hook \"\$0\""
# One event per name; the config hook does not know which event fired, so the
# event is given by its own friendly name instead.
for n in $names; do
  git config "hook.cfg-$n.command" "printf 'CFG $n\\n' >>\"\$H1_LOG\"; cat >/dev/null 2>&1; true"
  git config --add "hook.cfg-$n.event" "$n"
done
git config --unset hook.probe.command

case "$mode" in
  params) export GIT_CONFIG_PARAMETERS="'core.hooksPath'='/dev/null'" ;;
  count)  export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null ;;
  none) ;;
esac

run() { # where label -- command…
  local where="$1" label="$2"; shift 3
  : >"$log"
  ( cd "$where" && "$@" ) >/dev/null 2>&1
  local rc=$?
  printf '%-44s rc=%s  %s\n' "$label" "$rc" "$(sort -u "$log" | tr '\n' ' ')"
}

tip="$(git rev-parse HEAD)"
tree="$(git rev-parse HEAD^{tree})"
idx="$w/idx"
export -f run 2>/dev/null
R="$w/repo" W="$w/wt"

run "$W" "rev-parse HEAD (wt)" -- git rev-parse HEAD
run "$W" "rev-parse --git-common-dir (wt)" -- git rev-parse --git-common-dir
run "$R" "config --get / --list" -- sh -c 'git config --get core.excludesFile; git config --list --name-only'
run "$R" "config set + --unset-all" -- sh -c 'git config core.excludesFile /x; git config --unset-all core.excludesFile'
run "$R" "worktree add -q --detach (pilot)" -- git worktree add -q --detach "$w/wt2" "$tip"
run "$R" "worktree list --porcelain" -- git worktree list --porcelain
run "$R" "worktree remove --force" -- git worktree remove --force "$w/wt2"
run "$R" "worktree prune" -- git worktree prune
run "$W" "GIT_INDEX_FILE read-tree" -- env GIT_INDEX_FILE="$idx" git read-tree "$tree"
run "$W" "ls-tree" -- git ls-tree "$tree" -- a.txt
run "$W" "GIT_INDEX_FILE update-index --add --cacheinfo" -- env GIT_INDEX_FILE="$idx" git update-index --add --cacheinfo "100644,$(git rev-parse HEAD:a.txt),b.txt"
run "$W" "GIT_INDEX_FILE update-index --force-remove" -- env GIT_INDEX_FILE="$idx" git update-index --force-remove -- b.txt
run "$W" "GIT_INDEX_FILE write-tree" -- env GIT_INDEX_FILE="$idx" git write-tree
run "$W" "commit-tree" -- git commit-tree -p "$tip" -m m "$tree"
c2="$(cd "$W" && git commit-tree -p "$tip" -m m "$tree")"
run "$W" "update-ref -m HEAD new old (wt)" -- git update-ref -m m HEAD "$c2" "$tip"
run "$R" "update-ref refs/heads/failed/x (pilot)" -- git update-ref refs/heads/failed/x "$c2"
run "$R" "update-ref refused (old mismatch)" -- git update-ref refs/heads/failed/x "$c2" "$tip"
run "$W" "GIT_INDEX_FILE checkout-index -f" -- env GIT_INDEX_FILE="$idx" git checkout-index -f -- a.txt
run "$W" "reset -q -- path" -- git reset -q -- a.txt
run "$W" "reset -q --mixed head" -- git reset -q --mixed "$tip"
run "$W" "GIT_INDEX_FILE rm -r --cached" -- env GIT_INDEX_FILE="$idx" git rm -r -f -q --cached --ignore-unmatch -- issues
run "$W" "GIT_INDEX_FILE add -A --force" -- env GIT_INDEX_FILE="$idx" git add -A --force -- .
run "$W" "add -A --force (real index)" -- git add -A --force -- .
run "$W" "LC_ALL GIT_INDEX_FILE add --ignore-errors" -- env LC_ALL=C GIT_INDEX_FILE="$idx" git add -A --ignore-errors
run "$R" "for-each-ref" -- git for-each-ref --format='%(refname)' refs/heads/failed/
run "$R" "symbolic-ref" -- git symbolic-ref --quiet HEAD
run "$R" "show-ref --verify" -- git show-ref --verify --quiet refs/heads/main
run "$W" "ls-files --others" -- git ls-files --cached --others --exclude-standard
run "$W" "check-ignore --stdin" -- sh -c 'printf "a.txt\n" | git check-ignore --stdin'
run "$W" "diff-tree" -- git -c core.quotePath=false diff-tree -r --name-only "$tree" "$tree"
run "$R" "diff --name-only HEAD" -- git -c core.quotePath=false diff --name-only HEAD --
run "$W" "cat-file -e" -- git cat-file -e "$tip"
run "$R" "rev-parse --verify" -- git rev-parse --verify --quiet refs/heads/main
run "$R" "push --force (forge)" -- git push --force origin "$tip:refs/heads/ralph/x"
run "$w" "init -q --template=" -- git init -q --template= "$w/scratch"
