# GameHarbor

GameHarbor is my personal macOS project for managing Steam compatibility tools and running Windows Steam games through CrossOver on Apple silicon. The desktop app manages the Steam integration, runners, and per-game Wine prefixes. SteamPlayMac is a companion built from the same repository. It has its own config app, launcher, and `SteamPlayMac.dylib`.

## Install

You need an Apple silicon Mac running macOS 15 or later. Install Steam and open it once to download the Steam client. GameHarbor’s Windows compatibility tool also requires a supported version of CrossOver and a valid CrossOver license. A Steam client build must have a matching signature profile for the integration you install.

1. Download `GameHarbor.dmg` or `SteamPlayMac.dmg` from the [latest release](https://github.com/UtkarsHMer05/GameHarbor/releases/latest). Open the disk image and drag the app you want to Applications.
2. In GameHarbor, review the Steam and CrossOver status, install the integration, and restart Steam. Select the **GameHarbor** compatibility tool for the game.
3. If you want the companion, open `SteamPlayMac Config.app`. Choose **Install** for a fresh setup or **Update** to switch an existing integration to `SteamPlayMac.dylib`.

Downloads require access to this repository. These builds use ad hoc signing and may require macOS approval on first open. A successful build and test run on `main` publishes both disk images to Releases. Steam updates can move the client to a build without a matching profile. GameHarbor keeps its existing tool IDs and support directory. SteamPlayMac uses `~/Library/Application Support/SteamPlayMac` and migrates the previous settings directory on first use.

## Architecture

| Component | What it does |
| --- | --- |
| [Desktop app](app/) | SwiftUI interface and deployment tools. It checks Steam and CrossOver, manages compatibility tools, and handles prefix rebuilds and backups. |
| [Steam integration](dylib/) and [signature profiles](signatures/) | Native library loaded by Steam. Profiles identify the supported Steam client routines for each build. The library exposes the compatibility tools and connects game launches to their runner and prefix settings. |
| [Runner entry point](dylib/feats/compat_run.sh) | Resolves the selected runner and per-game options, sets up the Wine prefix and environment, and launches the game. |
| [Steam bridge](bridge/), [Steam client adapter](lsteamclient/), and [Windows shim](steam-shim/) | Connect the Windows side of a game running under Wine to the macOS Steam client. |
| [Helpers](helpers/), [loader patches](ntdll-patch/), [overlay shim](overlay-shim/), and [fonts](fonts/) | Provide packaging and metadata tools, runner-specific loader support, overlay integration, and fonts staged into the app payload. |
| [SteamPlayMac](SteamPlayMac/) | AppKit config app, native library, and optional launcher. The config app stages and verifies Steam bundle changes before replacing the working bundle. The launcher passes its packaged `SteamPlayMac.dylib` to the Steam client. |

## Build from source

Use Xcode 27 and the build dependencies listed in the [GameHarbor workflow](.github/workflows/app.yml). The workflow pins Dobby and records the versions of the font tools needed for a clean build.

```sh
git clone https://github.com/UtkarsHMer05/GameHarbor.git
cd GameHarbor
```

Clone the pinned Dobby revision as described in [vendor/README.md](vendor/README.md). With the workflow’s toolchain and prerequisites installed, run these commands from the repository root in order:

```sh
make dobby
make bridge
make fonts
make app
make app-tests
```

The app is built at `out/GameHarbor.app`. Run `make app-dmg` to package it as a disk image.

To build and check SteamPlayMac from the same checkout:

```sh
make -C SteamPlayMac
bash SteamPlayMac/SteamPlayMac-app/make_app.sh
make -C SteamPlayMac/launcher app
bash SteamPlayMac/checks/run.sh
```

Run `make -C SteamPlayMac dmg` to package `SteamPlayMac Config.app` in `SteamPlayMac/out/SteamPlayMac.dmg`.

The companion build produces `SteamPlayMac/out/SteamPlayMac.dylib`, the config app in `SteamPlayMac/SteamPlayMac-app/.build/`, and the launcher in `SteamPlayMac/launcher/build/`.

Source and dependency notices are in [licenses/](licenses/).

Credit to [@NotProtonNot](https://github.com/NotProtonNot) and contributors for the original NotProton project.
