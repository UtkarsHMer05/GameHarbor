# Temporary Risk of Rain 2 frame probe

Deployment status on 2026-11-11: disabled and moved out of the game's plugins after
the user reported worse stuttering during the instrumented runs. The game has been
returned to D3DMetal + MSync without this diagnostic plugin. Source remains here for
review; it is not an installed performance fix.

Local diagnostic code, built against the installed game's assemblies. It does not
change graphics, synchronization, game logic or garbage-collector settings.

`Probe.cs` reads Unity's available main/render-thread, collection-time and allocation
recorders. It also records Mono collection counts and managed heap sizes. In focused
gameplay it emits one `FRAMEWINDOW` line per two seconds in BepInEx's LogOutput.log.
Each line includes the worst frame and count of frames over 20 ms. Recorder values
are approximate previous-frame samples; a collection in the same window alone does
not establish that it caused the worst frame. Unavailable counters are reported as
`-1`, never as zero time. Menus and unfocused windows are excluded.

Version 1.0.1 also times the existing HookGen events for EffectManager.SpawnEffect,
CharacterBody.OnInventoryChanged and PurchaseInteraction.OnInteractionBegin. It
calls the original method exactly once, preserves its exceptions, and records call
counts and maximum elapsed duration per window. Nested durations can overlap;
they must not be added together. It does not alter item, purchase or effect behavior.
Version 1.0.2 renames the recorder factory to CreateRecorder so Unity does not mistake
the helper for its Start lifecycle callback. This corrected build is not deployed.

Build and check with a .NET SDK:

```sh
dotnet build local-mods/RoR2FrameProbe/RoR2FrameProbe.csproj -c Release \
  "-p:GameDirectory=$HOME/Library/Application Support/Steam/steamapps/common/Risk of Rain 2"
dotnet run --project local-mods/RoR2FrameProbe/tests/Tests.csproj -c Release
```

The tests exercise the actual frame-window accumulator, including peak selection,
collection counts, unavailable counters, reset and zero allocations during frame
accumulation. Runtime recorder support must be checked in the game log.

Installed only at `BepInEx/plugins/LocalFrameProbe/RoR2FrameProbe.dll`. To disable,
close the game and move that DLL outside BepInEx/plugins. Logging and recorder reads
add diagnostic overhead, so disable it after collecting the required reproduction.
It is a diagnostic tool, not a performance fix or an FPS guarantee.


A separate pickup-only elapsed-timing diagnostic was used on 2026-11-11 and then
removed after the user accepted the gameplay result. Four pickup windows were
saved; the final two had a worst Unity frame delta of 16.65 ms and no frames over
20 ms. The first window still contained a 78.28 ms frame, so these samples are not
a guarantee that all first-use hitches are eliminated.

The temporary diagnostic source, DLL, instrumented display plugin and logs are
archived outside the game under:

`~/Library/Application Support/NotProton Game File Safety/manual/ror2-targeted-pickup-timing-yz9xmvpb/`

Production `AsyncItemDisplays` 1.2.0 has been restored with no timing observer.
The original Unity-recorder probe described above remains disabled.
