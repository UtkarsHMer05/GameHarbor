# Async item displays (local Risk of Rain 2 patch)

The installed RoR2 build calls `AssetOrDirectReference<GameObject>.WaitForCompletion`
inside `CharacterModel.ParentedPrefabDisplay.Apply` when an item display uses an
Addressable prefab. That synchronous wait can block the game thread. Unity documents
this behavior in [Synchronous loading](https://docs.unity.cn/Packages/com.unity.addressables%401.21/manual/SynchronousAddressables.html).

This local plugin hooks only item-display creation and cancellation. It requests the
same display assets through the game's existing asset-reference manager, returns to
the game loop while they load, then calls the original display creation code after
all requested assets are ready. Item grants, stats, achievements, inventory saves,
equipment/key-item displays, graphics settings and the compatibility runner are not
changed. A newly acquired item's cosmetic model can appear shortly after pickup.

Pending requests are cancelled when the item display is disabled, the item is removed,
the body/model is destroyed, or its display-rule set changes. Superseded requests
cannot attach duplicate displays. Temporary asset references are released on success,
failure, cancellation and plugin shutdown; the patch does not preload the whole catalog
or keep a permanent asset cache.

The plugin logs activation and, once each per app launch, the first actual deferred
load and successful attachment. It has no frame profiler or per-frame log output.

Version 1.1.0 also defers cached and direct-prefab item displays out of the pickup
frame. It calls the original display method with one rule at a time, allowing at
most one cosmetic rule per frame across all characters. Requests now also cover
scene loading: assets load asynchronously, while attachment waits until scene
loading finishes. Remaining rules are cancelled if the model, run, rule set or item
becomes invalid. Equipment and key-item displays still use the original path.

Version 1.2.0 starts loading cosmetic display assets for nearby uncollected items
before pickup. Every 250 ms it uses the game's existing pickup-instance list to
select at most one new pickup within 30 metres of the first local player. It holds
at most four pickup groups; no full catalog or scene scan is used. References are
released when the pickup is collected, recycled, disabled, too far away, its
character/rule set changes, the scene starts loading, or the plugin stops. Asset
loading remains asynchronous. This prepares assets only; it does not instantiate
dummy objects, compile every shader, or change item behavior. Four pickup groups
is a count limit, not a byte limit: their asset bundles can still consume memory.

During a run with an active scene, the plugin sets
`Application.backgroundLoadingPriority` to `Low` and caps
`QualitySettings.asyncUploadTimeSlice` at 2 ms. Unity documents a 2 ms main-thread
integration budget at Low, compared with 4 ms at the default BelowNormal priority:
[backgroundLoadingPriority (Unity 2021.3)](https://docs.unity3d.com/2021.3/Documentation/ScriptReference/Application-backgroundLoadingPriority.html).
The previous settings resume while scenes load, after a run and on plugin shutdown.
It does not enlarge the upload buffer or preload the catalog. This trades slower
background asset completion and delayed cosmetic attachments for smaller work
bursts; it cannot split one expensive Unity instantiation or eliminate native
shader compilation, synchronous gameplay loads or OS paging.

Build against the installed game's libraries with a .NET SDK:

```sh
dotnet build local-mods/AsyncItemDisplays/AsyncItemDisplays.csproj -c Release \
  "-p:GameDirectory=$HOME/Library/Application Support/Steam/steamapps/common/Risk of Rain 2"
dotnet run --project local-mods/AsyncItemDisplays/tests/Tests.csproj -c Release
```

The tests exercise the actual request scheduler using controllable async loads:
non-blocking multi-asset waits, exactly-once completion, removal/cancellation,
replacement, destroyed models, failed assets, exception propagation and shutdown.
They also check cached/direct deferral, a shared per-frame rule limit, rule order,
the scene-loading gate and cancellation partway through a display group.
Prefetch tests cover its four-group limit, duplicate suppression before loading,
retention, expiration, failed preparation, slot reuse and exactly-once cleanup.
The production build separately compiles against the actual installed RoR2, HookGen,
Addressables and BepInEx assemblies. Native rendering and in-game hitch reduction
still require a gameplay comparison. Asset instantiation, shaders and other game work
can still cause hitches; this patch addresses the identified blocking load path.

The only deployment target is
`BepInEx/plugins/LocalAsyncItemDisplays/AsyncItemDisplays.dll`. To roll back, close
the game and move that DLL outside `BepInEx/plugins`. No original game DLL or EXE is
replaced. Game updates can change these APIs, so rebuild and validate before reusing
the patch on another game version.
