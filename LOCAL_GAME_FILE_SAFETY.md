# Local Steam game-file safety copies

Set up on 10 November 2026 after Steam removed the Windows depots for Noita and Risk of Rain 2 when the NotProton integration was absent. Steam's content log records that automatic reconfiguration; the game folders were downloaded again after NotProton was restored.

The local helper `tools/game_file_safety.py` makes copy-on-write clones of completed Windows game folders in the default Steam library. The active copy is installed at `~/Library/Application Support/NotProton Game File Safety/game_file_safety.py`. A per-user LaunchAgent checks every two minutes and at login, without opening a window. It delays work while a Wine game is running, and it only accepts games whose Steam manifest says they are fully installed, whose game files include a Windows executable, and whose game folder is at least as large as Steam's recorded installed size. A changing manifest or game tree, a copy failure, and insufficient free space prevent replacing the prior safety copy.

Copies live at `~/Library/Application Support/NotProton Game File Safety/games/<Steam app ID>/current/`. Each contains `files/`, `appmanifest.acf`, and `metadata.json`. If a game changes, the helper keeps the previous verified copy as `previous/` until another verified version replaces it. If a game is uninstalled, the safety copy is deliberately retained. `status.json` records the most recent scan and errors. An additional initial copy of Noita and Risk of Rain 2 is retained in `initial-2026-11-10/`.

These are local copies on the same APFS volume. They can retain disk blocks after Steam deletes its files and consume additional space as files change. The helper pauses new copies if less than 15 GiB is free. It does not follow symlinks, protect their external targets, cover extra Steam libraries on other volumes, or copy Wine prefixes and save files. It is not an off-disk backup and does not protect against disk failure. A game is not covered until a completed scan records a successful copy; changes while a game is running wait until a later scan.

## Recover a game

First quit Steam and all Windows games, then repair NotProton if it is missing. The helper refuses to restore while Steam or a Wine game is running or while NotProton is absent. For Noita, for example:

```sh
/usr/bin/python3 "$HOME/Library/Application Support/NotProton Game File Safety/game_file_safety.py" --restore 881100
```

Use app ID `632360` for Risk of Rain 2. The helper validates the safety copy, creates a cloned recovery copy, moves any current game directory into a uniquely named folder under `recoveries/`, saves the current Steam manifest there, and then restores the saved game folder and manifest. It does not touch the game's Wine prefix or saves. If an operation fails before completion, it attempts to restore the original game folder and manifest. Start Steam only after recovery and let Steam check for any game updates.

Automatic copies do not automatically replace files in Steam: recovery is explicit to avoid racing Steam downloads or overwriting files. Ask for help with recovery if unsure.

## Checks and management

Run the tests from the NotProton checkout:

```sh
/usr/bin/python3 -m unittest -v tools/test_game_file_safety.py
```

The checks cover a removed game file, an incomplete download, retained previous copies, failed cloning, unsafe paths, an active Wine game, safe recovery, an active Steam client, a missing current copy, a changed backup, and a simulated manifest-replacement failure.

The LaunchAgent is `~/Library/LaunchAgents/com.notproton.game-file-safety.plist`. To stop future scans without deleting existing copies, run:

```sh
launchctl bootout "gui/$(id -u)/com.notproton.game-file-safety"
```

The helper and this documentation are local changes. They do not modify Steam's game files during normal scans.
