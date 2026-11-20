# Local MetalSafeBars allocation fix

Local modification of [Krabik6/MetalSafeBars](https://github.com/Krabik6/MetalSafeBars),
used by MacosHealthbarsFix 1.0.27. The plugin ID and original healthbar material,
sprite and fill repairs are preserved. The local plugin version is 1.0.2.

The original periodic refresh enumerated Image and TMP components into fresh
arrays both to hash the hierarchy and to patch it. The local version collects
each component type once into reusable lists, including inactive pooled children.
It retains full patching when the hierarchy changes and still periodically repairs
materials. Repeated healthbar diagnostics use debug logging.

Version 1.0.2 replaces the recurring `Resources.FindObjectsOfTypeAll` discovery
scan with the existing HookGen `HealthBar.OnEnable` event. It calls the original
method exactly once and attaches or reinitializes the same fixer when a bar is
enabled, including pooled bars. It no longer retains a global set of bar objects.
Boss-bar exclusion and the fixer's own periodic hierarchy/material repair remain.
The plugin now references the installed `MMHOOK_RoR2.dll`, already required by the
other local gameplay plugin. This removes recurring global discovery work; native
healthbar appearance and any microstutter improvement still need a gameplay check.

Build against the installed game's libraries with a .NET SDK:

```sh
dotnet build local-mods/MetalSafeBars/MetalSafeBars.csproj -c Release \
  "-p:GameDirectory=$HOME/Library/Application Support/Steam/steamapps/common/Risk of Rain 2"
dotnet run --project local-mods/MetalSafeBars/tests/Tests.csproj -c Release
```

The test executable compiles the actual plugin source against small Unity/BepInEx
doubles. It checks initial repair, newly added inactive children, removal and reuse,
event-driven discovery, duplicate prevention, pooled re-enable, original-call
preservation and hook removal. It asserts that no global object search occurs.
After warmup it asserts zero managed
allocations for 10,000 unchanged refreshes and only one scan per component type.
It does not measure Unity native allocations, rendered healthbar visibility or game
frame times. The production DLL is separately built against the real game libraries.

The production output is `bin/Release/netstandard2.1/MetalSafeBars.dll`. With the game
closed, replace only the existing DLL inside
`BepInEx/plugins/LevTeam-MacosHealthbarsFix-1.0.27/MetalSafeBars/`. Do not add a second
copy elsewhere in plugins. The local deployment on 2026-11-11 saved the original and
hashes under:

`~/Library/Application Support/NotProton Game File Safety/manual/ror2-healthbar-allocation-z3kzjl5x/`

To undo, close the game and restore that backup's DLL to its original location.
Mod-manager synchronization or reinstalling MacosHealthbarsFix can replace this local
DLL. Shader compilation, asset streaming and other game/mod work remain possible
sources of hitches; this patch does not promise a stutter-free game.
