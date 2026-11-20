# Dark Souls III: 40 or 45 FPS with DXMT

This optional NotProton plugin paces CAMetalLayer drawable acquisition at 45 FPS by default.
It is enabled only when `NOTPROTON_DS3_45FPS=1` and `SteamAppId=374320`.
Set `DS3_FRAME_LIMIT_FPS=40` in the plugin environment to use 40 FPS.
Plugin environment names must not start with `NOTPROTON_`; the launcher reserves that prefix.
The existing enable flag is retained so Steam launch options do not need changing.
Each Metal layer has its own deadline. Timer oversleep does not accumulate,
and a whole missed interval resets the schedule. No game executable, simulation timing, or save
file is changed.

Disable DXMT's display-divisor limiter with
`DXMT_CONFIG=d3d11.preferredMaxFrameRate=0`, retain
`CX_GRAPHICS_BACKEND=dxmt`, and enable the plugin in this game's launch options.
On a 60 Hz display, both caps still have uneven display-refresh spacing. This caps
frame production; it does not change the physical refresh rate or guarantee
the game can sustain the target FPS in demanding scenes.

Build and check from this directory:

```sh
clang -arch arm64 -arch x86_64 -O2 -dynamiclib -framework Foundation -framework QuartzCore ds3_frame_limit.m -o ds3-frame-limit.dylib
codesign -fs - ds3-frame-limit.dylib
clang -O2 -framework Foundation -framework QuartzCore check.m -o check
./check
./check 40
python3 check-launch.py # after installation: verify the launcher accepts the cap variable
```

Install the library under `~/Library/Application Support/notproton/plugins/`
alongside a `.conf` containing:

```ini
[NOTPROTON_DS3_45FPS]
label = Dark Souls III: 40 FPS
description = Cap Dark Souls III at 40 FPS while retaining DXMT.
on = 1
inject = 1
requires = Library/Application Support/notproton/plugins/ds3-frame-limit.dylib
env = DS3_FRAME_LIMIT_FPS=40
```

Remove `NOTPROTON_DS3_45FPS=1` from the game's launch options to disable it.

## Sekiro: 40 FPS

The active Sekiro setup uses this plugin for the requested 40 FPS cap:
`NOTPROTON_SEKIRO_40FPS=1 DXMT_CONFIG=d3d11.preferredMaxFrameRate=0 CX_GRAPHICS_BACKEND=dxmt WINEMSYNC=0 %command%`.
The native 30 FPS and MSync-off trial did not resolve reported combat-action delay.
MSync remains off; no controlled input-latency measurement established its effect.

The same library also supports Sekiro (`SteamAppId=814380`) through a separate
`NOTPROTON_SEKIRO_40FPS=1` launch option. It retains the game's existing renderer.
The enable flag keeps its original name; `SEKIRO_FRAME_LIMIT_FPS=30` in the plugin
environment selects 30 FPS. Without that setting the library defaults to 40 FPS.
Neither game's flag enables the limiter for the other game.
Install `sekiro-40fps.conf` alongside the existing library:

```ini
[NOTPROTON_SEKIRO_40FPS]
label = Sekiro: 40 FPS
description = Cap Sekiro at 40 FPS with its existing Metal renderer.
on = 1
inject = 1
requires = Library/Application Support/notproton/plugins/ds3-frame-limit.dylib
env = SEKIRO_FRAME_LIMIT_FPS=40
```

Add `NOTPROTON_SEKIRO_40FPS=1` to Sekiro's existing Steam launch options.
With DXMT, also set `DXMT_CONFIG=d3d11.preferredMaxFrameRate=0` to prevent its
display-divisor limiter from rounding the cap down to 30 on a 60 Hz display.
Run `./check 40` and `python3 check-launch.py` to check pacing and game isolation.
Restart the game after changing the library or its plugin environment.
Remove that launch option to disable the cap.
