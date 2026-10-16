n="$1"
list=''
for i in $(seq 1 "$n"); do list="$list"$'path/to/some/fïle-'"$i"$'.txt\tdigest-abcdef0123456789\n'; done
list="${list%$'\n'}"
now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
t0=$(now)
c=0
while IFS=$'\t' read -r a b; do c=$((c+1)); done <<L
$list
L
t1=$(now)
old="$IFS"; IFS=$'\n'; set -f; arr=($list); set +f; IFS="$old"
t1b=$(now)
c2=0
for line in "${arr[@]}"; do a="${line%%$'\t'*}"; c2=$((c2+1)); done
t2=$(now)
echo "n=$n bytes=${#list} LANG=${LC_ALL:-$LANG} heredoc=$(echo "$t1-$t0"|bc)s/$c split=$(echo "$t1b-$t1"|bc)s iterate=$(echo "$t2-$t1b"|bc)s/$c2"
