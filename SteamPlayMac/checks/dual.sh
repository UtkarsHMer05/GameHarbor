#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# != 3 && $# != 4 ]]; then echo 'usage: dual.sh NOTPROTON_DYLIB STEAMCLIENT NOTPROTON_PROFILE [STEAM_BUILD]' >&2; exit 2; fi
notproton=$1
client=$2
np_profile=$3
build=${4:-1794266161}
scratch=$(mktemp -d "${TMPDIR:-/tmp}/steamplaymac-dual.XXXXXX")
scratch=$(cd "$scratch" && pwd -P)
cleanup() {
    if [[ $1 != 0 ]]; then
        cat "$scratch/stderr" 2>/dev/null || true
        find "$scratch/Library/Application Support" -name "*.log" -exec cat {} \; 2>/dev/null || true
    fi
    rm -rf "$scratch"
}
trap 'cleanup "$?"' EXIT
inner="$scratch/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS"
ms="$scratch/Library/Application Support/macsteam"
mkdir -p "$inner/package" "$ms/signatures/macos.arm64" "$scratch/Library/Application Support/notproton"
if [[ -n "${MACSTEAM_CHECK_CONFIG:-}" ]]; then
    cp "$MACSTEAM_CHECK_CONFIG" "$ms/config.yaml"
    mkdir -p "$scratch/Library/Application Support/Steam/appcache"
    printf '\350\116\000\000\002billingtype' > "$scratch/Library/Application Support/Steam/appcache/packageinfo.vdf"
fi
printf 'publicbeta' > "$inner/package/beta"
printf '"version" "%s"\n' "$build" > "$inner/package/steam_client_publicbeta_osx.manifest"
ln -s "$client" "$inner/steamclient.dylib"
cp "signatures/macos.arm64/$build.json" "$ms/signatures/macos.arm64/"
clang checks/runtime_dual.c -o "$scratch/steam_osx"
clang -dynamiclib checks/input_allow.c -framework CoreGraphics -o "$scratch/input-allow.dylib"
sandbox-exec -p "(version 1)(allow default)(deny network*)(deny file-write*)(allow file-write* (subpath \"$scratch\"))" \
    /usr/bin/env HOME="$scratch" NOTPROTON_SIG="$np_profile" \
    DYLD_INSERT_LIBRARIES="$scratch/input-allow.dylib:$notproton:$PWD/out/SteamPlayMac.dylib" \
    "$scratch/steam_osx" "$client" 2> "$scratch/stderr"
grep -q 'signatures: 32/32 resolved' "$ms/SteamPlayMac.log"
grep -q '\[relaunch\] NotProton handles child process injection' "$ms/SteamPlayMac.log"
grep -q 'SteamPlayMac ready: 18/18 hooks installed' "$ms/SteamPlayMac.log"
grep -q 'install_thread: ready, 13/13 hooks installed' "$scratch/Library/Application Support/notproton/notproton.log"
if [[ -n "${MACSTEAM_CHECK_CONFIG:-}" ]]; then grep -q 'config loaded: [1-9][0-9]* apps' "$ms/SteamPlayMac.log"; fi
echo 'Both integrations resolved and installed their hooks together in the isolated Steam client'
