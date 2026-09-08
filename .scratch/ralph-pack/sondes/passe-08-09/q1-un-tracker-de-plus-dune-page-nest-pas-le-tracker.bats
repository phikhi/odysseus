#!/usr/bin/env bats
#
# Passe transversale du 08/09 — Q1.
#
# `forge__listing` pagine, et son commentaire dit pourquoi : « a tracker of a
# hundred tickets is ordinary and a first page is not the tracker ». Deux
# défauts empilés, dont le second est caché par le premier.
#
# 1. La borne de page est comptée ainsi :
#
#      count="$(… awk -F'\t' '{ split($1, f, "."); if (f[1] != last) { n++; last = f[1] } }
#                              END { print n + 0 }')"
#      [ "${count:-0}" -ge "${FORGE_PAGE:-100}" ] || break
#
#    `f[1]` est un *strnum* (« 0 » ressemble à un nombre) et `last` n'est pas
#    initialisée : la comparaison est **numérique**, `0 == 0`, donc le premier
#    enregistrement de chaque page n'est jamais compté. Une page pleine de cent
#    issues compte quatre-vingt-dix-neuf, `99 >= 100` est faux, et la boucle
#    s'arrête. **La page deux n'est jamais demandée.**
#
# 2. Si elle l'était : `forge__records` reconstruit un enregistrement par
#    **indice de tableau** (`rec = substr(p, 1, dot - 1)`), et `forge_json`
#    numérote les éléments de **chaque document**. La première issue de la page
#    deux est `0.number`, comme celle de la page une : elle l'écrase.
#
# Le faux `curl` du harnais ne peut montrer ni l'un ni l'autre — il le dit
# lui-même : « Page two and beyond are empty: this fake holds fewer tickets than
# a page. » Cette sonde en installe un qui sert deux pages pleines.
#
# Instrument, pas test : chaque cas finit par un `false` volontaire.

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() {
  harness_setup
}

teardown() {
  harness_teardown
}

# Un `curl` qui sert une forge de quatre issues, deux par page. Il remplace la
# copie que le harnais a posée dans le PATH du test ; `test/helpers/shims/curl`
# n'est pas touché.
sonde__paged_curl() {
  local per_page="${1:-2}"
  cat >"$SHIM_BIN/curl" <<PAGED
#!/usr/bin/env bash
set -uo pipefail
url=''
for arg in "\$@"; do
  case "\$arg" in http://* | https://*) url="\$arg" ;; esac
done
printf '%s\n' "\$url" >>"\$RALPH_SHIM_STATE/paged.urls"
page="\${url##*page=}"
case "\$page" in '' | *[!0-9]*) page=1 ;; esac

issue() {
  printf '{"number":%s,"state":"open","assignees":[],"body":"**Status:** ready-for-agent\\\\n\\\\n**Blocked by:** None\\\\n\\\\n**Write-surface:** src/%s.txt\\\\n\\\\n**Slug:** %s"}' \\
    "\$1" "\$2" "\$2"
}

if [ "$per_page" = all ]; then
  case "\$page" in
    1) printf '['; issue 1 alpha; printf ','; issue 2 beta; printf ','
       issue 3 gamma; printf ','; issue 4 delta; printf ']' ;;
    *) printf '[]' ;;
  esac
else
  case "\$page" in
    1) printf '['; issue 1 alpha; printf ','; issue 2 beta; printf ']' ;;
    2) printf '['; issue 3 gamma; printf ','; issue 4 delta; printf ']' ;;
    *) printf '[]' ;;
  esac
fi
printf '\n200\n'
PAGED
  chmod +x "$SHIM_BIN/curl"
}

sonde__pages_asked() {
  sed 's/.*page=/page /' "$SHIM_STATE/paged.urls" 2>/dev/null | sort | uniq -c |
    sed 's/^/    /'
}

@test "Q1a une page pleine, et la suivante n est jamais demandée" {
  # `FORGE_PAGE 2` = « une page pleine porte deux issues », ce que ce faux sert.
  use_forge github
  set_config FORGE_PAGE 2
  sonde__paged_curl 2

  pack_run 'tracker_ids'
  printf '=== rc de tracker_ids : %s\n' "$status"
  printf '=== les ids que le pack voit (la forge en porte 4) :\n'
  printf '%s\n' "$output" | sed 's/^/    /'

  pack_run 'tracker_frontier'
  printf '=== la frontière :\n'
  printf '%s\n' "$output" | sed 's/^/    /'

  pack_run 'tracker_field 3-gamma Status || printf "(refus rc=%s)\n" "$?"'
  printf '=== le Status de 3-gamma, une issue ouverte et ready-for-agent : %s\n' "$output"

  printf '=== pages demandées :\n'
  sonde__pages_asked

  printf '=== ce que la borne compte sur une page de deux enregistrements : %s\n' \
    "$(printf '0.number\t1\n0.state\topen\n1.number\t2\n1.state\topen\n' |
      LC_ALL=C awk -F'\t' '{ split($1, f, "."); if (f[1] != last) { n++; last = f[1] } }
        END { print n + 0 }')"
  printf '=== et sur une page PLEINE de cent enregistrements : %s (borne : %s)\n' \
    "$(LC_ALL=C awk 'BEGIN { for (i = 0; i < 100; i++) printf "%d.number\t%d\n", i, i }' |
      LC_ALL=C awk -F'\t' '{ split($1, f, "."); if (f[1] != last) { n++; last = f[1] } }
        END { print n + 0 }')" 100

  set -e
  false
}

@test "Q1b témoin appairé : les mêmes quatre tickets sur une seule page" {
  use_forge github
  sonde__paged_curl all

  pack_run 'tracker_ids'
  printf '=== les ids que le pack voit :\n'
  printf '%s\n' "$output" | sed 's/^/    /'
  printf '=== pages demandées :\n'
  sonde__pages_asked

  set -e
  false
}

@test "Q1c la borne desserrée : le pack pagine, et la page deux écrase la page une" {
  # `FORGE_PAGE 1` fait franchir au compte faussé sa propre borne, ce qui met la
  # boucle de pagination en marche — c'est le seul moyen d'atteindre le second
  # défaut, que le premier cache.
  use_forge github
  set_config FORGE_PAGE 1
  sonde__paged_curl 2

  pack_run 'tracker_ids'
  printf '=== les ids que le pack voit :\n'
  printf '%s\n' "$output" | sed 's/^/    /'
  printf '=== pages demandées :\n'
  sonde__pages_asked

  pack_run 'tracker_field 1-alpha Status || printf "(refus rc=%s)\n" "$?"'
  printf '=== le Status de 1-alpha, servi par la page une : %s\n' "$output"

  set -e
  false
}

@test "Q1d ce que la disparition coûte au scope-guard : qui revendique la surface" {
  # `gate__surface_owner` demande `tracker_ids` puis la write-surface de chacun,
  # pour distinguer un débordement dans un fichier neutre d'un débordement dans
  # la surface d'un **autre** ticket ([05], AC 5 de [18]). Un ticket que le
  # listing a perdu ne revendique plus rien : le drift contractuel devient un
  # débordement interne, donc un retry au lieu d'une escalade.
  use_forge github
  set_config FORGE_PAGE 2
  sonde__paged_curl 2

  pack_run 'gate__surface_owner src/beta.txt 1-alpha || printf "(rc=%s)\n" "$?"'
  printf '=== qui revendique src/beta.txt (surface de 2-beta, page une) : %s\n' "$output"

  pack_run 'gate__surface_owner src/delta.txt 1-alpha || printf "(rc=%s)\n" "$?"'
  printf '=== qui revendique src/delta.txt (surface de 4-delta, page deux) : %s\n' "$output"

  set -e
  false
}
