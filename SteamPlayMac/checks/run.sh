#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p out/checks
clang -std=c17 -Isrc checks/steam_build.c src/util/file.c -o out/checks/steam-build
clang -std=c17 -Isrc -ffunction-sections -Wl,-dead_strip checks/stats_layout.c -o out/checks/stats-layout
clang -std=c17 -Isrc -ffunction-sections -Wl,-dead_strip checks/owner_layout.c -o out/checks/owner-layout
clang -std=c17 -Isrc checks/ownership.c src/feats/apps.c src/config/config.c src/util/log.c src/util/file.c -o out/checks/ownership
clang -std=c17 -Isrc checks/license.c src/config/config.c src/core/session.c src/util/log.c src/util/file.c -o out/checks/license
clang -std=c17 -Isrc checks/manifest.c src/config/config.c src/util/log.c src/util/file.c -framework CoreFoundation -framework CFNetwork -o out/checks/manifest
cat > out/checks/manifest-watch-helper <<'HELPER'
#!/bin/sh
printf '%s %s %s\n' "$1" "$2" "$3" > "$HOME/manifest-watch-called"
HELPER
chmod +x out/checks/manifest-watch-helper
clang -std=gnu17 -Isrc -DWATCH_HELPER="\"$PWD/out/checks/manifest-watch-helper\"" checks/manifest_watch.c src/config/config.c src/util/log.c src/util/file.c -o out/checks/manifest-watch
out/checks/stats-layout
out/checks/owner-layout
out/checks/ownership
out/checks/license
python3 checks/manifest_server.py "$PWD/out/checks/manifest"
out/checks/manifest-watch
swiftc SteamPlayMac-app/Sources/SteamPlayMacApp/{Paths,StepFailure,Subprocess,MacCrab,SteamInstaller,ZipImporter,LuaManifest,SteamPlayMacConfig}.swift checks/safety.swift -o out/checks/safety
swiftc SteamPlayMac-app/Sources/SteamPlayMacApp/{Paths,StepFailure,Subprocess,ZipImporter,LuaManifest,SteamPlayMacConfig,ManifestFetcher}.swift checks/manifest_fetch.swift -o out/checks/manifest-fetch
out/checks/manifest-fetch
if [[ -n "${MACSTEAM_CHECK_CLIENT:-}" ]]; then
    out/checks/safety "$PWD/out/checks/steam-build" "$PWD/out/SteamPlayMac.dylib" "$MACSTEAM_CHECK_CLIENT"
else
    out/checks/safety "$PWD/out/checks/steam-build" "$PWD/out/SteamPlayMac.dylib"
fi
scratch=$(mktemp -d "${TMPDIR:-/tmp}/steamplaymac-runtime.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
package="$scratch/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/package"
profiles="$scratch/Library/Application Support/macsteam/signatures/macos.arm64"
mkdir -p "$package" "$profiles"
printf 'publicbeta' > "$package/beta"
printf '"version" "999"\n' > "$package/steam_client_publicbeta_osx.manifest"
printf '{"steam_build":"888"}' > "$profiles/999.json"
touch "$scratch/.crash"
clang checks/steam_process.c -o "$scratch/steam_osx"
HOME="$scratch" DYLD_INSERT_LIBRARIES="$PWD/out/SteamPlayMac.dylib" "$scratch/steam_osx" 2> "$scratch/log"
grep -q 'Steam build 999 has no matching profile; SteamPlayMac is inactive' "$scratch/log"
test -f "$scratch/.crash"
echo 'Unsupported runtime profile remains inactive and leaves Steam files untouched'
clang -dynamiclib checks/steam_process.c -o "${package%/package}/steamclient.dylib"
client_hash=$(shasum -a 256 "${package%/package}/steamclient.dylib" | cut -d ' ' -f 1)
printf '{"steam_build":"999","steamclient_sha256_arm64":"%064d"}' 0 > "$profiles/999.json"
HOME="$scratch" DYLD_INSERT_LIBRARIES="$PWD/out/SteamPlayMac.dylib" "$scratch/steam_osx" 2> "$scratch/log"
grep -q 'Steam build 999 has no matching profile; SteamPlayMac is inactive' "$scratch/log"
test -f "$scratch/.crash"
printf '{"steam_build":"999","steamclient_sha256_arm64":"%s"}' "$client_hash" > "$profiles/999.json"
mkdir -p "$scratch/Library/Application Support/Steam/appcache"
printf '\350\116\000\000\002billingtype' > "$scratch/Library/Application Support/Steam/appcache/packageinfo.vdf"
before=$(shasum -a 256 "$scratch/Library/Application Support/Steam/appcache/packageinfo.vdf")
HOME="$scratch" DYLD_INSERT_LIBRARIES="$PWD/out/SteamPlayMac.dylib" "$scratch/steam_osx" 2> "$scratch/log"
grep -q 'SteamPlayMac loaded into steam_osx' "$scratch/log"
test "$before" = "$(shasum -a 256 "$scratch/Library/Application Support/Steam/appcache/packageinfo.vdf")"
echo 'Matching client hash starts safely without changing the package cache when no apps are configured'
if [[ -n "${MACSTEAM_CHECK_CLIENT:-}" ]]; then
    clang -std=c17 -Isrc -Ivendor -o out/checks/profile-probe checks/profile_probe.c \
        src/core/macho.c src/resolver/{aob,anchor,sigdb,resolver}.c src/util/{log,file,hex}.c vendor/cJSON.c -framework Foundation
    sandbox-exec -p '(version 1)(allow default)(deny network*)(deny file-write*)' \
        out/checks/profile-probe "$MACSTEAM_CHECK_CLIENT" "signatures/macos.arm64/$(out/checks/steam-build "$HOME").json"
fi
