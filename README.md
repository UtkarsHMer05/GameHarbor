# GameHarbor

GameHarbor is my personal macOS project(though almost a fork right now with just a few changes) for managing Steam compatibility tools and running Windows Steam games through CrossOver on Apple silicon. The desktop app manages the Steam integration, runners, and per-game Wine prefixes. SteamPlayMac is a secret app(which I sometimes needed too), when you download it, you will know🤫.

# NOTE:
1. See this is a project I am gonna implement/improve as a Hobby and a project as I also need to play games..I don't know the architecture of this whole project very well. I am learning it though.(gonna use ChatGPT). There can be issues like I don't know how to proceed furthur because of my less experience in doing it.
2. See here, the secret dmg file - SteamPlayMac ..(I will keep it updated, unlike the guy stopped because my games depend on it too), if you guys have any suggestions like what can we change etc. in this file, do open the issues tab and try to explain in eveything in detail 
3. Similar thing, like I am planning to add support for other wine tools instead of crossover(I don't have much experiece etc like what can we add) so you are free to open Pr/issues tab explainig with links etc. if possible
4. Well don't expect me to fix the bugs or add anything new daily..I am also kinda busy with stuff..I will add/fix it eventually but not like every day like @NotProtonNot..I am not good as him in this domain (well you can say it's my first time 😂)


## Install

You need an Apple silicon Mac running macOS 15 or later. Install Steam and open it once to download the Steam client. GameHarbor’s Windows compatibility tool also requires a supported version of CrossOver and a valid CrossOver license. A Steam client build must have a matching signature profile for the integration you install.

1. Download `GameHarbor.dmg` or `SteamPlayMac.dmg` from the [latest release](https://github.com/UtkarsHMer05/GameHarbor/releases/latest). Open the disk image and drag the app you want to Applications.
2. In GameHarbor, review the Steam and CrossOver status, install the integration, and restart Steam. Select the **GameHarbor** compatibility tool for the game.
3. If you want the companion, open `SteamPlayMac Config.app`. and research the other things which you need

Downloads require access to this repository. These builds use ad hoc signing and may require macOS approval on first open. A successful build and test run on `main` publishes both disk images to Releases. Steam updates can move the client to a build without a matching profile. GameHarbor keeps its existing tool IDs and support directory. SteamPlayMac uses `~/Library/Application Support/SteamPlayMac` and migrates the previous settings directory on first use.

## Existing Windows game downloads

To reuse a completed download from Windows Steam in CrossOver, select the Windows compatibility tool for the title in macOS Steam, then quit both Steam clients and all Wine games. From a GameHarbor checkout, run the import with the game's Steam AppID and the source library's `steamapps` directory.

```sh
python3 tools/game_file_safety.py --import-game 123456 --from-steamapps "/path/to/source/steamapps"
```

The import copies the game files and manifest to the main Steam library. Use `--to-steamapps` to select another existing library. It keeps the source and refuses to overwrite a destination game, including its manifest. Saves, settings, and Wine prefixes stay in their original locations.

Use an APFS Steam library for Wine prefixes. GameHarbor refuses to start or rebuild prefixes on NTFS, exFAT, and FAT. If your prefix is already on one of those formats, keep a separate copy of the prefix and check your saves after moving the library.

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
