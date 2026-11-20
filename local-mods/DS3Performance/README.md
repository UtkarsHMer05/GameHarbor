# Dark Souls III selective performance shaders

Uses the official Mod Engine 2.1 launcher through the existing NotProton Steam
compatibility command. The wrapper replaces only the DS3 executable argument and
converts mod-launcher file arguments to Wine Z: paths. Other arguments and the
compatibility verb are preserved. No Wine DLL proxy is required.

Installed wrapper: `~/Library/Application Support/notproton/plugins/ds3-performance-launch.sh`.
Its quoted absolute path sits immediately before `%command%` in DS3 launch options.
The existing DXMT, MSync and 45 FPS plugin options are retained.

The active profile contains only `gxffxshader.shaderbnd.dcx` from performance mod
1.05. The material/model, post-processing, renderer and decal bundles were removed
after gameplay testing because of startup failures, missing compute shaders and
unacceptable changes to character appearance. The game loads its original versions
from its archives. High textures, original geometry, `Data0.bdt` and draw-distance
data are retained. ReShade, the mod DXGI DLL and its Data0 replacement were omitted.

Mod Engine reads `Game/ds3-performance.toml` with loose params and external DLL
discovery disabled. The game executable and gameplay/regulation archives are not
rewritten. Existing save files are used; a copy was made before installation.

The experimental Metal 3.1 shader target was reverted after the user reported more
stutter. The original Metal 3.2 shader cache remains intact. Test evidence and a
file installation manifest are in `~/Documents/NotProton Local Patches/2026-11-14-ds3-performance-mod/`.

Check wrapper argument preservation and game restriction with `python3 check.py`.
The 45 FPS cap limits frame production; it cannot guarantee sustained performance
or evenly spaced refreshes on a 60 Hz display.

The official DXMT 0.80 runner trial was rejected after severe stutter and a reported system crash. Its variant selection was removed; the original CrossOver DXMT renderer is active. The lower-resolution and model-shader trials were also reverted.
