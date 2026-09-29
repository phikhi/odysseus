#!/bin/bash
#
# Ticket [98], avant d'écrire une ligne. La forme exacte des trois enveloppes de
# fermeture du pack, rejouée hors du pack : `receipt_shut`, `gate_notes_shut` et
# `receipt_shut_exec` ferment un descripteur par une redirection posée sur un APPEL
# DE FONCTION (ou sur un `exec` qui porte une commande). Bash 3.2 sauvegarde alors le
# descripteur sur une copie >= 10, sans close-on-exec, et le programme lancé dedans
# en hérite. `lsof` dit le numéro, le mode et le fichier.
#
#   bash .scratch/ralph-pack/sondes/ticket-98/f1-les-copies-de-sauvegarde.sh
# prints "fd -> name" for fds 3..40 of the calling process
report='lsof -p $$ -a -d 3-40 -F fan 2>/dev/null | awk "/^f/{fd=substr(\$0,2)} /^a/{a=substr(\$0,2)} /^n/{print \"   fd\" fd a \" -> \" substr(\$0,2)}" | sed "s#-> .*/#-> #"'
work="$(mktemp -d "${TMPDIR:-/tmp}/sonde-98.XXXXXX")"
f="$(mktemp "$work/R5.XXXXXX")"; exec 5>"$f" 4<"$f"; rm -f "$f"
g="$(mktemp "$work/N9.XXXXXX")"; exec 9>"$g" 8<"$g"; rm -f "$g"
receipt_shut() { eval "\"\$@\" 5>&- 4<&-"; }
receipt_shut_exec() { eval "exec \"\$@\" 5>&- 4<&-"; }
gate_notes_shut() { eval "\"\$@\" 9>&- 8<&-"; }
proc_group_fork() { set -m; bash -c "$2" & PID=$!; set +m; wait $PID; }
echo "== A. gate__command_branch shape: receipt_shut gate_notes_shut proc_group_fork '' cmd"
receipt_shut gate_notes_shut proc_group_fork '' "$report"
echo "== B. session_spawn shape: receipt_shut_exec claude & (inside a function)"
spawn() { receipt_shut_exec bash -c "$report" & wait $!; }
spawn
echo "== C. plain external, no wrapper"
bash -c "$report"
rmdir "$work"
