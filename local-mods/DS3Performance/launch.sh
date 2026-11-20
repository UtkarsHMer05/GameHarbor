#!/bin/sh
set -eu
[ "$#" -ge 3 ] || exit 64
compat=$1
verb=$2
game=$3
shift 3
case "$game" in
  */DARK\ SOULS\ III/Game/DarkSoulsIII.exe) ;;
  *) echo "Unexpected game executable" >&2; exit 64 ;;
esac
exec "$compat" "$verb" "${game%/*}/modengine2_launcher.exe" -t ds3 -p "Z:$game" -c "Z:${game%/*}/ds3-performance.toml" "$@"
