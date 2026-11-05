# Local NotProton fixes and update migration

Saved locally on 5 November 2026 at the user's request. Nothing was pushed or published.

## Source and artifacts

- Working repository: `/Users/utkarshkhajuria/Desktop/notproton`
- Local branch: `codex/local-macos-fixes-2026-11-05`
- Original source: NotProton `v1.2.3`, commit `1c851b661107724f9ec2801913b58c84d84a9ede`
- Saved code head: `222a6828719f95a0a2e0d6f421f4a992ef4a6a90`
- Independent backup folder: `/Users/utkarshkhajuria/Documents/NotProton Local Patches/2026-11-05-v1.2.3`
- `patches/`: three standard Git patches, including their regression fixtures.
- `notproton-local-fixes.bundle`: self-contained Git history for this local branch and the original release tag; it can restore the source without the existing checkout.
- `manifest.json` and `SHA256SUMS`: commit identities, source hashes, artifact hashes, and the recovery-check result.
- `LOCAL_SETUP.md`: installed components, runtime hashes, user-reported Noita results, test commands, and rollback locations.

The source bundle contains NotProton source and local documentation. Installed CrossOver, its activation, Steam accounts, downloaded games, saves, ignored build products, and external build dependencies are outside this Git backup. Obtain dependencies required by the target release when rebuilding.

## Separate fixes

| Order | Local commit | Fix | Patch file |
| --- | --- | --- | --- |
| 1 | `cb9836727268` | Fix capacity for all registered Steam WebUI routes | `patches/0001-Fix-capacity-for-all-registered-Steam-WebUI-routes.patch` |
| 2 | `d7b39807204a` | Give Windows games one branded macOS Dock identity | `patches/0002-Give-Windows-games-one-branded-macOS-Dock-identity.patch` |
| 3 | `222a6828719f` | Skip overlay tracking for game-created render passes | `patches/0003-Skip-overlay-tracking-for-game-created-render-passes.patch` |

The documentation is saved in an additional local commit. Only the three functional commits are exported as migration patches.

Patch 2 contains a backport of upstream per-game Wine-bundle work from `d01287d2095b31a7628d9e13277be68e813988ed` and `e67dd9ba984a74025d7857f998842c8173df294c`, plus the local flat Wine child-loader correction. A future release may already contain part or all of this. Inspect both the per-game bundle and the child-loader path before choosing what to port.

## Bring the fixes into an update

1. Keep this backup folder. Identify the exact new upstream release or commit first.
2. Use a separate worktree or checkout for the new version. For example, in the working repository, replace `NEW_RELEASE_TAG_OR_COMMIT` below with the actual target:

   ```sh
   git fetch origin --tags
   git worktree add -b codex/port-local-macos-fixes ../notproton-update NEW_RELEASE_TAG_OR_COMMIT
   ```

3. Inspect the new version for each fix: all WebUI route/factory slots agree; visible Wine game processes use the game's branded bundle while helpers stay hidden; game-created render passes bypass overlay-only tracking. Keep upstream implementations where the behavior is already correct.
4. In the new checkout, apply only missing patches in the listed order. Git's three-way application can reuse the original blob identities. For example, if the WebUI fix is still missing:

   ```sh
   git am --3way "/Users/utkarshkhajuria/Documents/NotProton Local Patches/2026-11-05-v1.2.3/patches/0001-Fix-capacity-for-all-registered-Steam-WebUI-routes.patch"
   ```

   Apply the other selected patch files the same way. If upstream has only part of a fix, adapt the missing behavior to its current structure. Resolve conflicts in the new checkout and use `git am --continue`; use `git am --abort` to cancel that attempt. An unknown future version is not guaranteed to accept these patches unchanged.
5. Follow that release's build prerequisites, then rebuild affected components. For this saved release the affected build targets are:

   ```sh
   make -j4 dylib overlay-shim
   ```

6. Run the relevant regression checks, adapting target names if upstream changes them:

   ```sh
   make runcheck launchercheck bundlecheck envcheck envpasscheck featstagecheck compatcheck compatsvc-check compatpage-check
   make overlay-shim-tests
   git diff --check
   ```

7. Package the rebuilt components with the matching new release payload and deploy through NotProton's installer. Check signatures, current installed content, and any macOS authorization prompt. Old compiled libraries are not a substitute for rebuilding against the new source.
8. Launch from normal macOS Steam. Confirm one correctly branded game Dock icon, hidden Wine helpers, native-first routing, and a same-scene Noita gameplay comparison with the Steam overlay enabled. Other Windows games need their own compatibility and performance checks.
9. Export a new local patch set and bundle after a successful port. Preserve this original backup as a known reference.

No background updater, automatic patch application, new graphics tuning policy, or blanket MSync change was added. This backup preserves the fixes; future integration is a reviewed source port.

## Recover if the working repository is lost

From any suitable parent folder:

```sh
git clone "/Users/utkarshkhajuria/Documents/NotProton Local Patches/2026-11-05-v1.2.3/notproton-local-fixes.bundle" NotProton-local-restored
cd NotProton-local-restored
git switch codex/local-macos-fixes-2026-11-05
```

The bundle also includes the `v1.2.3` tag. Its source can be recovered offline; rebuilding still requires the appropriate tools and dependencies.

To check backup integrity:

```sh
cd "/Users/utkarshkhajuria/Documents/NotProton Local Patches/2026-11-05-v1.2.3"
shasum -a 256 -c SHA256SUMS
```

## Verification boundary

The preservation check clones the standalone bundle into a temporary directory, verifies the saved source and documentation hashes, checks out the exact original release, reapplies all three migration patches, and verifies that every modified source/test file matches the saved version byte for byte. This proves recovery on the recorded baseline. A future release has not been selected or tested.

Existing gameplay evidence is the user's Noita report: almost stable 60 FPS, occasional 55–57 FPS dips, and no noticeable stutters with the overlay enabled after the shared change. Synthetic render-pass timings were variable and are not a universal FPS claim.
