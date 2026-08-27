#!/usr/bin/env bats
#
# [37] — s3 : la limite que la convention « une entrée par ligne » ne peut pas
# franchir. Un nom de fichier unix peut contenir un saut de ligne. Que devient un
# ticket que la session dépose sous `99-a<LF>b.md` ?
#
# Tournée APRÈS le correctif : ce qu'elle mesure est ce qui reste ouvert, pas ce
# que le ticket a fermé.

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() { harness_setup; }
teardown() { harness_teardown; }

@test "S3a un id qui porte un saut de ligne" {
  use_tickets 01-alpha

  pack_run '
    seen="$(failures_tracker_snapshot)"
    printf "**Status:** ready-for-agent\n\n**Blocked by:** None\n\n**Write-surface:** \`*\`\n" \
      >"$(ralph_feature_dir)/issues/99-a
b.md"
    printf "ids[%s]\n" "$(tracker_ids | tr "\n" "|")"
    printf "strays[%s]\n" "$(failures__strays "$seen" | tr "\n" "|")"
    failures_quarantine_strays 01-alpha "$seen"
    printf "rc=%s\n" "$?"
  '
  printf '%s\n' "$output"

  echo "=== le tracker après"
  ls "$TRACKER_DIR"

  echo "=== le statut du ticket que la session s'est écrit"
  pack_run 'tracker_field "99-a
b" Status; printf "rc=%s\n" "$?"'
  printf '%s\n' "$output"

  echo "=== et la frontière : la boucle irait-elle le broyer ?"
  pack_run 'tracker_frontier | tr "\n" "|"'
  printf '%s\n' "$output"
  false
}
