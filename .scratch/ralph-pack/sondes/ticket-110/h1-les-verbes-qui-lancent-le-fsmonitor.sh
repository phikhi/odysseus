#!/bin/bash
# Which git verbs run core.fsmonitor, and does the program read git's stdin?
set -u
D=$(mktemp -d); cd "$D"
cat >spy <<'S'
#!/bin/sh
printf '%s\n' "$*" >>"$SPYLOG"
n=0; while IFS= read -r l; do n=$((n+1)); done
printf 'drained %s\n' "$n" >>"$SPYLOG"
printf '/\0'
S
chmod +x spy
export SPYLOG="$D/spy.log"
export HOME="$D/home"; mkdir -p "$HOME"; export GIT_CONFIG_NOSYSTEM=1
git init -q repo; cd repo
git config user.email a@b; git config user.name a
printf 'x\n' >a; printf 'y\n' >b; git add a b; git commit -q -m one
git config --global core.fsmonitor "$D/spy"
feed() { printf 'L1\nL2\nL3\n'; }
try() { : >"$SPYLOG"; feed | "$@" >/dev/null 2>&1; printf '%-60s %s\n' "$*" "$(tr '\n' ' ' <"$SPYLOG")"; }
for round in 1 2; do
echo "--- round $round"
try git rev-parse HEAD
try git status --porcelain
try git add -A
try git add -A --force -- ':(literal)a'
try git write-tree
try git diff --name-only HEAD --
try git ls-files --others --exclude-standard
try git ls-files --others --ignored --exclude-standard --directory
try git diff-tree -r --name-only HEAD HEAD~0
try git reset -q -- ':(literal)a'
try git checkout-index -f -- a
try git update-index --add --cacheinfo 100644,$(git rev-parse HEAD:a),c
try git cat-file -p HEAD:a
try git ls-tree HEAD
try git config --get core.fsmonitor
try git read-tree HEAD
try git rm -r -f -q --cached --ignore-unmatch -- zz
done
echo "--- GIT_INDEX_FILE fresh"
I=$(mktemp -u "$D/idx.XXXX")
: >"$SPYLOG"; feed | GIT_INDEX_FILE=$I git read-tree HEAD; echo "read-tree fresh: $(tr '\n' ' ' <"$SPYLOG")"
: >"$SPYLOG"; feed | GIT_INDEX_FILE=$I git add -A --force -- ':(literal)a'; echo "add on it: $(tr '\n' ' ' <"$SPYLOG")"
: >"$SPYLOG"; feed | GIT_INDEX_FILE=$I git add -A --force -- ':(literal)b'; echo "add again: $(tr '\n' ' ' <"$SPYLOG")"
: >"$SPYLOG"; feed | GIT_INDEX_FILE=$I git write-tree >/dev/null; echo "write-tree: $(tr '\n' ' ' <"$SPYLOG")"
echo "--- check-ignore --stdin in a fresh repo with no index (the pin's rules repo)"
cd "$D"; git init -q rules; printf 'vendor/\n' >rules/.gitignore; cd rules
for i in 1 2 3; do
: >"$SPYLOG"; out=$(printf 'vendor/\nassets/\nfoo\n' | git check-ignore --stdin); echo "check-ignore #$i out=[$(echo $out)] spy: $(tr '\n' ' ' <"$SPYLOG")"
done
ls .git/index 2>/dev/null || echo "no index file"
echo "--- same, with an index present"
git add .gitignore
for i in 1 2 3; do
: >"$SPYLOG"; out=$(printf 'vendor/\nassets/\nfoo\n' | git check-ignore --stdin); echo "check-ignore #$i out=[$(echo $out)] spy: $(tr '\n' ' ' <"$SPYLOG")"
done
git --version
rm -rf "$D"
