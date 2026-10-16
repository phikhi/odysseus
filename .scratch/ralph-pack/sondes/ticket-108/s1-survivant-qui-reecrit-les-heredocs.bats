#!/usr/bin/env bats
#
# [108], 16/10/2026 — la mesure DANS le pack (2ᵉ AC). Une session laisse derrière
# elle un survivant perl qui boucle sur /var/tmp/sh-thd*, ouvre chaque fichier en
# lecture-écriture et GARDE le descripteur ; quand bash l'a délié (nlink 0 : le
# lecteur est ouvert), il relit le contenu et, s'il y trouve une ligne `vendor`,
# le réécrit en entier (chaque octet hors newline → `x`, même longueur).
#
# GUARDED_PATHS = `.claude` + `assets` + `vendor` (le 3e : après deux `git add`
# forkés, [passe 16/10 g4]) ; `vendor/` ignoré ; la session écrit `vendor/rogue`.
# Sur `main` (heredoc `<<FORCED`) : la ligne `vendor` est réécrite avant d'être lue,
# le force-staging la saute, la garde ne nomme pas le fichier. Sur la branche :
# aucune liste ne passe par un fichier nommé.
#
#   bash test/run.sh .scratch/ralph-pack/sondes/ticket-108/s1-survivant-qui-reecrit-les-heredocs.bats </dev/null
#
# Instrument, pas test : chaque cas finit sur un `false` volontaire.
load ../../../../test/helpers/harness
load ../../../../test/helpers/assert
setup() { harness_setup; }
teardown() {
  kill -KILL "$(cat "$SHIM_STATE/spy.pid" 2>/dev/null)" 2>/dev/null || true
  harness_teardown
}

prep() {
  use_tickets 01-alpha
  set_config STERILE_K 1
  set_config GUARDED_PATHS '.claude
assets
vendor'
  printf 'assets/\nvendor/\n' >>"$PROJECT_DIR/.gitignore"
  git -C "$PROJECT_DIR" add -A; git -C "$PROJECT_DIR" commit -q -m "test: ignore assets and vendor"
  cat >"$SHIM_STATE/spy.pl" <<'SPY'
use strict; use Fcntl;
$SIG{TERM} = 'IGNORE'; $SIG{HUP} = 'IGNORE';
my ($state, $want, $secs) = @ARGV;
my (%held, %done);
my $end = time + $secs;
open my $r, '>', "$state/spy.ready"; close $r;
sub note { my ($f, $l) = @_; open my $o, '>>', "$state/$f" or return; print $o $l; close $o }
while (time < $end) {
  for my $f (glob '/var/tmp/sh-thd*') {
    next if $held{$f} || $done{$f};
    next unless -O $f;
    sysopen(my $fh, $f, O_RDWR) or next;
    $held{$f} = $fh;
    note('spy.seen', "$f\n");
  }
  for my $f (keys %held) {
    my $fh = $held{$f};
    my @st = stat $fh;
    next unless @st && $st[3] == 0;
    my $buf = '';
    sysseek $fh, 0, 0;
    sysread $fh, $buf, 1 << 20;
    if (grep { $_ eq $want } split /\n/, $buf) {
      note('spy.listed', "--- $f\n$buf");
      (my $forged = $buf) =~ s/[^\n]/x/g;
      sysseek $fh, 0, 0;
      syswrite $fh, $forged;
    }
    close $fh; delete $held{$f}; $done{$f} = 1;
  }
}
SPY
}

write_session() { # $1 = spy|nospy
  cat >"$SHIM_STATE/claude.script" <<FAKE
#!/usr/bin/env bash
if [ "$1" = spy ] && [ ! -e "$SHIM_STATE/spy.pid" ]; then
  nohup perl "$SHIM_STATE/spy.pl" "$SHIM_STATE" vendor 60 >/dev/null 2>&1 &
  printf '%s\n' "\$!" >"$SHIM_STATE/spy.pid"
  # Le survivant regarde avant que la session ne rende la main : sinon le
  # démarrage de perl (~20 ms) rate l'instantané qui suit la session.
  i=0; while [ ! -e "$SHIM_STATE/spy.ready" ] && [ "\$i" -lt 50 ]; do sleep 0.1; i=\$((i + 1)); done
fi
mkdir -p vendor
printf 'written by the session\n' >vendor/rogue
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE
  chmod +x "$SHIM_STATE/claude.script"
}

report() {
  local named=NO; case "$output" in *vendor/rogue*) named=YES ;; esac
  printf '=== rc=%s\n' "$status"
  printf '=== ticket 01-alpha status: %s\n' "$(sed -n 's/^\*\*Status:\*\*[[:space:]]*//p' "$(ticket_file 01-alpha)" 2>/dev/null | head -1)"
  printf '=== vendor/rogue named out-of-surface? %s\n' "$named"
  printf '=== vendor/rogue survives in the tree? %s\n' "$([ -e "$PROJECT_DIR/vendor/rogue" ] && echo YES-SURVIVED || echo no)"
  printf '=== spy alive at the end? %s\n' "$(kill -0 "$(cat "$SHIM_STATE/spy.pid" 2>/dev/null)" 2>/dev/null && echo yes || echo no)"
  printf '=== heredoc files the spy opened: %s\n' "$(wc -l <"$SHIM_STATE/spy.seen" 2>/dev/null | tr -d ' ' || printf 0)"
  printf '=== lists with a `vendor` line it rewrote: %s\n' "$(grep -c '^--- ' "$SHIM_STATE/spy.listed" 2>/dev/null || printf 0)"
  sed 's/^/   listed| /' "$SHIM_STATE/spy.listed" 2>/dev/null | head -40
}

@test "S1t témoin — no spy: the file under the third guarded path is caught" {
  prep
  write_session nospy
  run_loop
  report
  set -e; false
}

@test "S1 — a survivor rewrites every heredoc holding a vendor line: is vendor/rogue still caught?" {
  prep
  write_session spy
  run_loop
  report
  set -e; false
}
