set -euo pipefail
proc_split() {
  local __ws="$1" __s="$2" __f
  shift 2
  __s="${__s%%$'\n'*}"
  __s="${__s#"${__s%%[!$__ws]*}"}"
  while [ "$#" -gt 1 ]; do
    __f="${__s%%[$__ws]*}"
    __s="${__s#"$__f"}"
    __s="${__s#"${__s%%[!$__ws]*}"}"
    printf -v "$1" '%s' "$__f"
    shift
  done
  __s="${__s%"${__s##*[!$__ws]}"}"
  printf -v "$1" '%s' "$__s"
}
PROC_LINES=()
proc_lines() {
  local IFS=$'\n'
  set -f
  PROC_LINES=($1)
  set +f
}
alpha=( '' 'a' 'b c' $'\t' ' ' '\' '\t' '*' '?' '[x]' 'é' $'\t\t' '  ' 'x\ny' '$HOME' '"' "'" )
bad=0 n=0
for i in $(seq 1 4000); do
  s=''
  k=$((RANDOM % 7))
  for j in $(seq 0 $k); do s="$s${alpha[$((RANDOM % ${#alpha[@]}))]}"; done
  for ws in $'\t' $' \t'; do
    IFS="$ws" read -r r1 r2 r3 <<HD || true
$s
HD
    proc_split "$ws" "$s" p1 p2 p3
    n=$((n+1))
    if [ "$r1|$r2|$r3" != "$p1|$p2|$p3" ]; then bad=$((bad+1)); [ $bad -le 5 ] && printf 'DIFF ws=%q s=%q read=%q split=%q\n' "$ws" "$s" "$r1|$r2|$r3" "$p1|$p2|$p3"; fi
    IFS="$ws" read -r q1 <<HD || true
$s
HD
    proc_split "$ws" "$s" o1
    [ "$q1" = "$o1" ] || { bad=$((bad+1)); printf 'DIFF1 %q %q %q\n' "$s" "$q1" "$o1"; }
  done
done
echo "split cases=$n bad=$bad"
# lines: non-empty lines, globs untouched, spaces kept
cd "$(mktemp -d)"; touch aa ab
proc_lines $'a*\n\n  b c \n\t\n?b\n'
printf '<%s>' "${PROC_LINES[@]}"; echo " count=${#PROC_LINES[@]}"
proc_lines ''
for x in ${PROC_LINES[@]+"${PROC_LINES[@]}"}; do echo "never $x"; done; echo "empty ok count=${#PROC_LINES[@]}"
case $- in *f*) echo "noglob LEFT ON" ;; *) echo "noglob off" ;; esac
