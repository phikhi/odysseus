#!/bin/bash
set -u
D=$(mktemp -d); cd "$D"
cat >spy <<'S'
#!/bin/sh
printf 'ran %s\n' "$*" >>"$SPYLOG"
n=0; while IFS= read -r l; do n=$((n+1)); done
printf 'drained %s\n' "$n" >>"$SPYLOG"
printf '/\0'
S
chmod +x spy
export SPYLOG="$D/spy.log" HOME="$D/home" GIT_CONFIG_NOSYSTEM=1; mkdir -p "$HOME"
git config --global core.fsmonitor "$D/spy"
git config --global filter.x.clean "$D/spy"; git config --global filter.x.process "$D/spy"
git init -q rules; mkdir -p rules/sub; printf 'vendor/\n*.log\n!keep.log\n' >rules/.gitignore; printf 'deep\n' >rules/sub/.gitignore
printf '* filter=x\n' >"$HOME/attrs"; git config --global core.attributesFile "$HOME/attrs"
cd rules
in='vendor/
assets/
a.log
keep.log
sub/deep
sub/x
"caf\303\251.log"'
for mode in "" "--no-index"; do
  : >"$SPYLOG"
  out=$(printf '%s\n' "$in" | git check-ignore $mode --stdin; echo "rc=$?")
  printf 'mode=[%s] out=[%s] spy=[%s]\n' "$mode" "$(echo $out)" "$(tr '\n' ' ' <"$SPYLOG")"
done
echo "--- without the planted fsmonitor"
git config --global --unset core.fsmonitor
for mode in "" "--no-index"; do
  : >"$SPYLOG"
  out=$(printf '%s\n' "$in" | git check-ignore $mode --stdin; echo "rc=$?")
  printf 'mode=[%s] out=[%s] spy=[%s]\n' "$mode" "$(echo $out)" "$(tr '\n' ' ' <"$SPYLOG")"
done
rm -rf "$D"
