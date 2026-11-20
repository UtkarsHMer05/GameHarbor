#!/bin/sh
set -eu

root=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/steam-coexist.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir -p "$tmp/steamui/css" "$tmp/home/Library/Application Support"
cp "$root/dylib/tests/webpatch-fixtures/gates.selecttool.js" "$tmp/steamui/sp.js"
printf 'a{background:linear-gradient(to top, #171d25,#000)}\n' > "$tmp/steamui/css/test.css"
printf 'ordinary file\n' > "$tmp/steamui/ordinary.txt"
printf 'HideWhatsNew: yes\n' > "$tmp/config.yaml"
clang -o "$tmp/read" "$root/SteamPlayMac/checks/coexist.c"
np="$root/out/notproton.dylib"
ms="$root/SteamPlayMac/out/SteamPlayMac.dylib"

read_file() {
    HOME="$tmp/home" STEAMPLAYMAC_CONFIG="$tmp/config.yaml" DYLD_INSERT_LIBRARIES="$1" \
        "$tmp/read" "$2" "$3" > "$4"
}

read_file "$np" open "$tmp/steamui/sp.js" "$tmp/js.expected"
read_file "$ms" open "$tmp/steamui/css/test.css" "$tmp/css.expected"
if cmp -s "$tmp/steamui/sp.js" "$tmp/js.expected" || cmp -s "$tmp/steamui/css/test.css" "$tmp/css.expected"; then
    echo 'A standalone patch did not run' >&2
    exit 1
fi

for libs in "$np:$ms" "$ms:$np"; do
    for api in open fopen openat; do
        read_file "$libs" "$api" "$tmp/steamui/sp.js" "$tmp/result"
        cmp "$tmp/js.expected" "$tmp/result"
        read_file "$libs" "$api" "$tmp/steamui/css/test.css" "$tmp/result"
        cmp "$tmp/css.expected" "$tmp/result"
        read_file "$libs" "$api" "$tmp/steamui/ordinary.txt" "$tmp/result"
        cmp "$tmp/steamui/ordinary.txt" "$tmp/result"
    done
    for api in open+ fopen+; do
        for original in "$tmp/steamui/sp.js" "$tmp/steamui/css/test.css"; do
            read_file "$libs" "$api" "$original" "$tmp/result"
            cmp "$original" "$tmp/result"
        done
    done
done

printf 'HideWhatsNew: no\n' > "$tmp/config.yaml"
read_file "$np:$ms" open "$tmp/steamui/css/test.css" "$tmp/result"
cmp "$tmp/steamui/css/test.css" "$tmp/result"
echo 'SteamPlayMac and NotProton web patches coexist in both load orders.'
