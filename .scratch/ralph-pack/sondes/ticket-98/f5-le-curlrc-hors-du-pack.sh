#!/usr/bin/env bash
# Sonde ouverte en commençant [98] le 07/10/2026 (→ [105]). Hors du harnais : le
# vrai `curl` de la machine, un canal délié comme ceux du pack (ouvert deux fois,
# délié avant le premier octet), et un HOME jetable qui porte un `~/.curlrc`.
#
#   bash .scratch/ralph-pack/sondes/ticket-98/f5-le-curlrc-hors-du-pack.sh
#
# Le port 9 est fermé : la requête de la ligne de commande échoue toujours, et ce
# qui arrive quand même vient de la config.
set -u
work="$(mktemp -d "${TMPDIR:-/tmp}/sonde-curlrc.XXXXXX")"
cd "$work" || exit 1
printf 'note\tFORGED-LINE\n' >forged.txt
printf '{"five_hour":{"utilization":100}}\n' >forged.json

channel() { f="$(mktemp ./c.XXXXXX)"; exec 11<>"$f" 12<"$f"; rm -f "$f"; }
shut() { exec 11>&- 12<&-; }
home() { rm -rf home; mkdir home; cat >home/.curlrc; }

printf '%s\n' "$(curl --version | head -1)"

echo '== (a) output= vers un bout ÉCRIVAIN hérité, malgré le -o de la ligne'
home <<EOF
url = "file://$work/forged.txt"
output = "/dev/fd/11"
EOF
channel
HOME="$PWD/home" curl -sS --max-time 3 -o /dev/null http://127.0.0.1:9/ 2>/dev/null
printf '   curl rc=%s, le canal dit : [%s]\n' "$?" "$(cat <&12)"
shut

echo '== (a-q) la même config, curl -q en premier argument'
channel
HOME="$PWD/home" curl -q -sS --max-time 3 -o /dev/null http://127.0.0.1:9/ 2>/dev/null
printf '   curl rc=%s, le canal dit : [%s]\n' "$?" "$(cat <&12)"
shut

echo '== (b) url= sans output : un corps forgé sur le stdout que le pack lit'
home <<EOF
url = "file://$work/forged.json"
EOF
out="$(HOME="$PWD/home" curl -sS --max-time 3 http://127.0.0.1:9/ 2>/dev/null)"
printf '   curl rc=%s, stdout : [%s]\n' "$?" "$out"

echo '== (c) data-binary=@ un bout LECTEUR : vidé avant le lecteur légitime'
home <<'EOF'
data-binary = "@/dev/fd/12"
EOF
channel
printf 'outcome resolved\ndone\n' >&11
HOME="$PWD/home" curl -sS --max-time 3 -o /dev/null http://127.0.0.1:9/ 2>/dev/null
printf '   curl rc=%s, le lecteur légitime lit ensuite : [%s]\n' "$?" "$(cat <&12)"
shut

echo '== (d) output= vers un bout LECTEUR : refusé sur darwin'
home <<EOF
url = "file://$work/forged.txt"
output = "/dev/fd/12"
EOF
channel
HOME="$PWD/home" curl -sS --max-time 3 -o /dev/null http://127.0.0.1:9/ 2>&1 | sed 's/^/   /' | head -1
printf '   le lecteur lit : [%s]\n' "$(cat <&12)"
shut

cd / && rm -rf "$work"
