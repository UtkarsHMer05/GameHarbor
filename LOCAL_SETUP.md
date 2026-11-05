# NotProton setup on this Mac

Checked on 5 November 2026. NotProton, its Steam integration, and the activated CrossOver runner are installed. Noita is fully installed. ULTRAKILL was left uninstalled at the user's request.

## Installed and verified

| Item | State |
| --- | --- |
| Mac | MacBook Air, Apple M2, 8 GB RAM; macOS reports 27.0.1 |
| Repository | Full Git clone in `/Users/utkarshkhajuria/Desktop/notproton`; release `v1.2.3`, commit `1c851b6`, plus the local WebUI route, per-game Wine launcher, overlay render-pass, and Game Mode support fixes described below |
| NotProton | Version 1.2.3 in `/Applications/NotProton.app`, initially installed through Homebrew, then updated with the local fix |
| CrossOver | Version 26.3, build 26.3.0.39832, in `/Applications/CrossOver.app`; NotProton verifies the activation signature as valid |
| Rosetta | Already installed; an x86_64 execution check passed |
| App Management | NotProton permission observed enabled in System Settings after user approval |
| Steam integration | NotProton reports `Installed (1.2.3)` and `Components, Ready.`; deployed content is current and 19/19 support files are present |
| Steam runtime | Started after installation; the log reports 13/13 core hooks, 3/3 Steam UI hooks, and 1/1 Steam service hooks installed |
| Game runner | CrossOver 26.3 Rosetta, build 26.3.0.39832, ready; registered in Steam as `notproton-26.3` |
| Noita | Steam reports Fully Installed, app ID 881100, 1,639,174,567 bytes on disk; first-run Microsoft Visual C++ dependencies installed; main menu and user gameplay tested; one Noita N Dock icon confirmed; user reports near 60 FPS with small dips to 55–57 and no stutters after the shared overlay change, including with Steam overlay enabled |
| ULTRAKILL | Neither installed nor queued; excluded at the user's request |

Both original installer archives matched their published Homebrew SHA256 values. CrossOver, the original NotProton app, the locally updated NotProton app, and the patched Steam app passed code-signature integrity checks. NotProton is ad-hoc signed rather than signed with an Apple Developer ID; its Homebrew-documented quarantine removal was applied only to `/Applications/NotProton.app`.

## Everyday use

1. Open the normal macOS Steam app.
2. Install and launch games from the Steam library. A game with a macOS build stays on Steam's native path. Windows-only games use NotProton and the CrossOver runner automatically. CrossOver's and NotProton's windows do not need to be open.
3. Leave compatibility forcing off for native macOS games. Only use **Properties > Compatibility > Force the use of a specific Steam Play compatibility tool > CrossOver 26.3** if a Windows game needs an explicit override.
4. Keep the apps installed and CrossOver activated. Open NotProton for updates, repairs, runner setup, or prefix settings.

A native macOS port uses the graphics API its developer implemented. Metal is used where the port supports it; this setup does not convert a native OpenGL port to Metal. Windows games use CrossOver's applicable graphics translation path.

A Steam account with access to each game and enough disk space is required. **NotProton 1.2.3 does not support the CrossOver trial.** Compatibility is game-specific; unsupported anti-cheat and other Windows-only requirements can still prevent a title from running.

Windows, Parallels, a separate Windows Steam installation, and a source build of NotProton are not required for this setup. CrossOver supplies the Wine runtime and graphics translation components. Add game-specific runtime packages only if an actual game error calls for them.

## Local prefix-control fix

Steam remains on the existing `publicbeta` channel, build **1793740892**. The original NotProton release logged:

```text
webui: no room left to serve NotProton.OpenPrefixLog#1
compatsvc: the Compatibility page cannot rebuild prefixes
```

The source registered nine WebUI routes but allocated eight route/factory slots. This was a NotProton capacity bug, not evidence that the beta alone caused the warning. The local change in `dylib/feats/webui.c` provides nine slots and factories, with a compile-time assertion that their counts agree.

The dylib was built with the project's pinned Dobby revision `5dfc8546954ce3b3198132ab13fddb89ee92cdd7`. `make compatsvc-check compatpage-check` passed. The updated app deployed it through NotProton's installer. A fresh Steam startup then served all nine routes, including `NotProton.OpenPrefixLog#1`, without the prior capacity warning.

The initial route-only dylib SHA256 before installer re-signing was `4e8d993b5b567e4986024de0f5e0bd037f54e0490bb865884932d95318f34f62`; the final build below supersedes it. This is a local patch to 1.2.3, not an official upstream release. A future app reinstall can replace it. Client updates were left enabled; a later Steam update can require a NotProton update or repair.

## Local single-icon launcher fix

The 1.2.3 launcher gave the Steam shim a branded Noita app while the visible game ran in a separate Wine process. Hiding only that launcher removed one icon but left a generic `wine` / `exec` icon.

The local change in `dylib/feats/compat_run.sh` backports the per-game Wine bundle logic from upstream commits [d01287d](https://github.com/NotProtonNot/NotProton/commit/d01287d2095b31a7628d9e13277be68e813988ed) and [e67dd9b](https://github.com/NotProtonNot/NotProton/commit/e67dd9ba984a74025d7857f998842c8173df294c), adapted to the stable release without importing unrelated plugin changes. A further local correction makes CrossOver 26's flat child-loader path execute the actual bundled Wine executable. It restores the graphics injection environment after the system shell. This is applied to reused caches as well as newly created ones.

The actual Noita game process now belongs to `com.notproton.launcher.881100` and uses the game's name and icon. Its Steam shim and Wine helpers stay out of the Dock. The runner uses APFS copy-on-write clones of Wine's library tree and links to the installed runner's other files. The original CrossOver app remains unchanged. Steam's native-first selection logic is unchanged and passed its native-versus-Windows tests.

The user confirmed exactly one Noita N icon, without an extra `wine`, `exec`, or `noita.exe` icon. macOS running-application metadata independently showed one regular Noita app and the other Wine processes as hidden helpers. Both NotProton and CrossOver GUIs were closed during the Steam launch. Noita's main menu rendered. The user later tested gameplay for the performance investigation below; the agent did not start or overwrite a game run.

Validation passed:

- `make runcheck launchercheck bundlecheck envcheck envpasscheck featstagecheck compatcheck compatsvc-check compatpage-check`
- After the child-loader correction: `make runcheck launchercheck featstagecheck envpasscheck compatcheck`
- `make -j4 dylib`
- `git diff --check`

The launcher fixtures cover fresh clones, cache reuse, runner changes, CrossOver 26.3 layout, literal arguments containing spaces and shell syntax, reserved environment names, restoring injected libraries, cleanup, lock contention, and session termination. Failure-case messages in the check logs are intentional fixture inputs; the checks exited successfully.

Final local payload hashes before installer re-signing:

- `run`: `116115de148ffcb74d0fdfdb346b0321c0df1a6ae41a6f329fab8d3a62612f6a`
- `notproton.dylib`: `c4a72d5cb0849fc825a9ff268a9f62db05da34c8b8bc426e82cf2be4b4303b65`
- `overlay-shim.dylib`: `213ff45800587ec2a634f07715119b13c76cfad38364d82593054f13ad01ee21`

The modified source and fixtures are now preserved in four local functional commits on `codex/local-macos-fixes-2026-11-05`, with local documentation commits. Standard patches and a standalone Git source bundle are saved outside the checkout at `/Users/utkarshkhajuria/Documents/NotProton Local Patches/2026-11-05-v1.2.3-with-game-mode`. See [LOCAL_PATCHES.md](LOCAL_PATCHES.md) for recovery and future update migration. Nothing was pushed or published. A future stock NotProton update or reinstall can replace the local changes. The known fallback for a custom user-supplied `WINEDLLPATH` retains the legacy launcher; that custom configuration was not used for Noita. Other Windows games can use the shared launcher fix, but were not individually launch-tested.

## Shared overlay render-pass correction

The user reported micro-stutters with FPS dipping from 60 to roughly 47–54, despite a previously smooth direct CrossOver run using Auto graphics. Auto graphics and the existing MSync default were left unchanged.

In `overlay-shim/overlay_shim.m`, `hook_render_encoder` previously inspected and tracked every game-created Metal render encoder. The shim's format correction is for overlay pipelines. The local fast path now forwards game-created encoders without installing overlay encoder hooks, reading attachment metadata, or adding entries to the overlay encoder table. Overlay-created encoders retain the existing correction and ownership handling. This uses the same overlay-origin check the code already uses to identify overlay pipelines.

This is shared runtime code, with no Noita app-ID special case. It applies to Windows games that load this NotProton overlay shim. Native macOS games continue using the normal Steam launch path. The change does not promise that every Windows game will run smoothly or be compatible.

Validation and limits:

- `make overlay-shim overlay-shim-tests` passed on the actual Mac: 8 passed, 0 skipped across arm64 and x86_64. Tests cover the game-pass fast path, overlay pipeline ownership and format substitution, completion/discard/rebuild handling, device delivery, and the Metal 4 event bridge.
- The final expanded ownership fixture also passed in the full eight-check run. It verifies that a game pass with a render target remains untracked and does not install encoder hooks.
- Noita's runtime log after the change no longer reports the extra `ensure_encoder_hooks` installation seen in earlier runs.
- The user reported that stutters were gone and FPS was stable during a quiet same-section comparison. The user then re-enabled the Steam overlay and reported almost stable 60 FPS, occasional 55–57 FPS dips, and no stutters. The overlay is left enabled.
- Synthetic render-pass timings varied across runs and did not establish a reliable game-FPS improvement. No automated gameplay frame-time benchmark was captured; the gameplay result is user-reported. Other Windows games were not individually tested.
- A short process sample showed Noita using OpenGL. System diagnostics also found substantial swap usage on this 8 GB Mac; that is a possible additional contributor rather than a proven cause of the original stutters.

Steam can keep its renderer loaded when the overlay UI is disabled, including for capture. A proposed injection gate was not deployed. The final patch preserves renderer delivery and the Metal 4 bridge, and targets the redundant per-pass work instead. No global overlay-disable flag, graphics-backend forcing, or blanket MSync change was added.

The tested shim is installed both in NotProton's payload and in its deployed support folder. Their bytes match. NotProton subsequently reported Installed (1.2.3), Components Ready, and current installed content. App Management permission was observed enabled. NotProton, CrossOver, Terminal, and the temporary Settings window were closed; normal macOS Steam was left running and signed in.

## Automatic Game Mode support

The shared Windows game bundle generator now sets Apple's `LSSupportsGameMode` key to the boolean `true`, in addition to the existing games category. The declaration applies to current and future game IDs in the shared template. Existing game bundles update on their next Steam launch. Native macOS games continue through the native Steam path.

`make runcheck launchercheck compatcheck` passed after this change. The added fixture generates metadata for game IDs 123 and 456 and verifies the boolean for each; the remaining launcher checks also passed. The updated run script and embedded dylib were rebuilt, packaged, and deployed through NotProton's installer, which reported successful installation.

The setting declares eligibility. macOS controls actual activation. Apple's public support guide requires Apple silicon, macOS 14 or later, and supported macOS full-screen mode; it also documents that a manually disabled per-game Game Mode setting remains disabled until re-enabled. Game Mode prioritizes CPU/GPU access, reduces background activity, and improves Bluetooth accessory responsiveness. It is not a memory-cleaning service and does not guarantee zero stutters.

References: [Apple Game Mode guide](https://support.apple.com/en-us/105118), [LSSupportsGameMode](https://developer.apple.com/documentation/bundleresources/information-property-list/lssupportsgamemode).

## Backup and diagnostic locations

- Complete local patch backup: `/Users/utkarshkhajuria/Documents/NotProton Local Patches/2026-11-05-v1.2.3-with-game-mode`
- Game Mode checks: `/tmp/notproton-game-mode-checks.log`
- Before-Game-Mode payloads: `/Users/utkarshkhajuria/Library/Application Support/NotProtonSetupBackup/2026-11-05/before-game-mode-flag/`
- Original Steam app archive: `/Users/utkarshkhajuria/Library/Application Support/NotProtonSetupBackup/2026-11-05/Steam.before-notproton.zip`
- Original NotProton app archive: `/Users/utkarshkhajuria/Library/Application Support/NotProtonSetupBackup/2026-11-05/NotProton.before-route-fix.zip`
- Backup archive SHA256: `ed29440c8888154b4c432082fe3f47bb39e8650a0aad7451354dda30d3ef1797`
- Original Steam Info.plist SHA256: `32c53f9d8cb62261c312fbcc9ae2fbe7ddf312600fd7fecd8bdfeab78e0bde54`
- Setup log: `/Users/utkarshkhajuria/Library/Application Support/notproton/app.log`
- Steam integration log: `/Users/utkarshkhajuria/Library/Application Support/notproton/notproton.log`
- Before-Dock-fix payloads: `/Users/utkarshkhajuria/Library/Application Support/NotProtonSetupBackup/2026-11-05/before-dock-fix/`
- Launcher check logs: `/tmp/notproton-launcher-checks.log` and `/tmp/notproton-child-loader-checks.log`
- Performance rollback copy: `/Users/utkarshkhajuria/Library/Application Support/NotProtonSetupBackup/2026-11-05/before-performance-test/`
- Final overlay checks: `/tmp/notproton-final-overlay-checks.log`
- Diagnostic sample: `/tmp/notproton-noita-sample.txt`
- Noita runner log: `/Users/utkarshkhajuria/Library/Application Support/Steam/steamapps/compatdata/881100/notproton-run.log`
- NotProton's **Setup > Repair Steam** restores the Steam app through its built-in repair flow. Keep the backup archive and game/save folders if reverting the integration.

## Official references

- [NotProton project and requirements](https://github.com/NotProtonNot/NotProton)
- [Installed NotProton release](https://github.com/NotProtonNot/NotProton/releases/tag/v1.2.3)
- [CrossOver license enforcement in this release](https://github.com/NotProtonNot/NotProton/blob/v1.2.3/app/Sources/NotProtonApp/Model/CrossOverLicense.swift)
- [CrossOver user guide](https://support.codeweavers.com/en_US/crossover-mac-user-guide)
- [Noita compatibility reports](https://www.codeweavers.com/compatibility/crossover/noita): Mac rating `Runs Great`, last tested with CrossOver 26.3.0.
- [ULTRAKILL compatibility reports](https://www.codeweavers.com/compatibility/crossover/ultrakill): Mac rating `Runs Well`, last tested with CrossOver 26.3.0.
- [Noita on Steam](https://store.steampowered.com/app/881100/Noita/)
- [ULTRAKILL on Steam](https://store.steampowered.com/app/1229490/ULTRAKILL/)

These compatibility reports are external evidence. Local launch and icon checks, user-reported gameplay results, and their limits are recorded separately above. Steam's visible library, Noita installer, download completion, overlay setting, and Play button were inspected through its Steam Helper window.
