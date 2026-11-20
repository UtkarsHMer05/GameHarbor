using System;
using System.Collections.Generic;
using BepInEx;
using BepInEx.Logging;
using RoR2;
using RoR2.ContentManagement;
using UnityEngine;
using UnityEngine.AddressableAssets;

namespace AsyncItemDisplays
{
    [BepInPlugin("local.ror2.asyncitemdisplays", "Async Item Displays", "1.2.0")]
    public sealed class Plugin : BaseUnityPlugin
    {
        readonly DisplayJobs<(CharacterModel, ItemIndex)> jobs = new DisplayJobs<(CharacterModel, ItemIndex)>(
            () => Time.frameCount, () => !UnityEngine.Networking.NetworkManager.IsSceneLoadingAsynchronously);
        readonly DisplayPrefetch<(GenericPickupController, CharacterModel, ItemIndex)> prefetch =
            new DisplayPrefetch<(GenericPickupController, CharacterModel, ItemIndex)>();
        bool deferredLogged, attachedLogged, streamingLogged, budgetActive, prefetchLogged, prefetchErrorLogged;
        float nextPrefetch;
        ThreadPriority previousPriority;
        int previousUploadSlice;

        void Awake()
        {
            On.RoR2.CharacterModel.InstantiateDisplayRuleGroup += InstantiateGroup;
            On.RoR2.CharacterModel.DisableItemDisplay += DisableDisplay;
            Logger.LogInfo("Async item displays 1.2.0 enabled: one cosmetic rule per frame, area streaming budget, and up to four nearby pickup display preloads. No frame profiling is active.");
        }

        void InstantiateGroup(On.RoR2.CharacterModel.orig_InstantiateDisplayRuleGroup orig, CharacterModel model,
            DisplayRuleGroup group, ItemIndex item, EquipmentIndex equipment, KeyItemIndex keyItem)
        {
            if (!Run.instance || !model || !model.body || !model.itemDisplayRuleSet ||
                item == ItemIndex.None || equipment != EquipmentIndex.None ||
                keyItem != KeyItemIndex.None || group.rules == null || group.rules.Length == 0)
            {
                orig(model, group, item, equipment, keyItem);
                return;
            }

            IDisplayLoad[] loads;
            try
            {
                loads = LoadGroup(group);
            }
            catch (Exception error)
            {
                Logger.LogWarning("Could not prepare async display: " + error.GetType().Name);
                orig(model, group, item, equipment, keyItem);
                return;
            }

            var run = Run.instance;
            var ruleSet = model.itemDisplayRuleSet;
            var singleRule = new ItemDisplayRule[1];
            bool deferred = false;
            foreach (var load in loads) if (!load.IsDone) deferred = true;
            if (deferred && !deferredLogged)
            {
                deferredLogged = true;
                Logger.LogInfo("First item-display asset load deferred without a synchronous wait.");
            }
            StartCoroutine(jobs.Begin((model, item), loads,
                () => Run.instance == run && model && model.itemDisplayRuleSet == ruleSet && model.body && model.body.inventory &&
                      model.body.inventory.GetItemCountTotal(item) > 0 &&
                      ReferenceEquals(ruleSet.GetItemDisplayRuleGroup(item).rules, group.rules),
                group.rules.Length, rule =>
                {
                    singleRule[0] = group.rules[rule];
                    orig(model, new DisplayRuleGroup { rules = singleRule }, item, equipment, keyItem);
                    if (deferred && !attachedLogged)
                    {
                        attachedLogged = true;
                        Logger.LogInfo("First deferred item display attached successfully.");
                    }
                }));
        }

        void Update()
        {
            bool playing = Run.instance && SceneInfo.instance &&
                !UnityEngine.Networking.NetworkManager.IsSceneLoadingAsynchronously;
            if (!playing)
            {
                prefetch.Dispose();
                RestoreStreamingBudget();
                return;
            }
            if (!budgetActive)
            {
                previousPriority = Application.backgroundLoadingPriority;
                previousUploadSlice = QualitySettings.asyncUploadTimeSlice;
                budgetActive = true;
                if (!streamingLogged)
                {
                    streamingLogged = true;
                    Logger.LogInfo($"Gameplay streaming budget: loading priority {previousPriority} -> Low; upload slice {previousUploadSlice} -> {Math.Min(previousUploadSlice, 2)} ms. Original settings resume during scene loading.");
                }
            }
            if (Application.backgroundLoadingPriority != ThreadPriority.Low)
            {
                previousPriority = Application.backgroundLoadingPriority;
                Application.backgroundLoadingPriority = ThreadPriority.Low;
            }
            if (QualitySettings.asyncUploadTimeSlice > 2)
            {
                previousUploadSlice = QualitySettings.asyncUploadTimeSlice;
                QualitySettings.asyncUploadTimeSlice = 2;
            }
            if (Time.unscaledTime >= nextPrefetch)
            {
                nextPrefetch = Time.unscaledTime + 0.25f;
                try { PrefetchNearbyDisplays(); }
                catch (Exception error)
                {
                    if (!prefetchErrorLogged)
                    {
                        prefetchErrorLogged = true;
                        Logger.LogWarning("Nearby display preload unavailable: " + error.GetType().Name);
                    }
                }
            }
        }

        IDisplayLoad[] LoadGroup(DisplayRuleGroup group)
        {
            var loads = new List<IDisplayLoad>();
            try
            {
                if (group.rules != null)
                    foreach (var rule in group.rules)
                        if (rule.ruleType == ItemDisplayRuleType.ParentedPrefab &&
                            rule.followerPrefabAddress != null && rule.followerPrefabAddress.RuntimeKeyIsValid())
                            loads.Add(new AssetLoad(rule.followerPrefabAddress, Logger));
                return loads.ToArray();
            }
            catch
            {
                foreach (var load in loads) load.Dispose();
                throw;
            }
        }

        void PrefetchNearbyDisplays()
        {
            prefetch.Prune();
            if (prefetch.IsFull) return;
            // shortcut: prefetch serves the first local player, extend only if tuning split-screen.
            var user = LocalUserManager.GetFirstLocalUser();
            var body = user?.cachedBody;
            if (!body || !body.inventory || !body.modelLocator || !body.modelLocator.modelTransform) return;
            var model = body.modelLocator.modelTransform.GetComponent<CharacterModel>();
            if (!model || !model.itemDisplayRuleSet) return;
            var ruleSet = model.itemDisplayRuleSet;
            GenericPickupController nearest = null;
            ItemIndex item = ItemIndex.None;
            DisplayRuleGroup group = default;
            float distance = 30f * 30f;
            foreach (var pickup in InstanceTracker.GetInstancesList<GenericPickupController>())
            {
                if (!pickup || !pickup.pickupDisplay || !pickup.pickupDisplay.isModelReady) continue;
                var definition = PickupCatalog.GetPickupDef(pickup.pickup.pickupIndex);
                if (definition == null || definition.itemIndex == ItemIndex.None ||
                    body.inventory.GetItemCountTotal(definition.itemIndex) > 0 ||
                    prefetch.Contains((pickup, model, definition.itemIndex))) continue;
                float candidateDistance = (pickup.transform.position - body.corePosition).sqrMagnitude;
                if (candidateDistance >= distance) continue;
                var candidateGroup = ruleSet.GetItemDisplayRuleGroup(definition.itemIndex);
                bool hasAddress = false;
                if (candidateGroup.rules != null)
                    foreach (var rule in candidateGroup.rules)
                        if (rule.ruleType == ItemDisplayRuleType.ParentedPrefab && rule.followerPrefabAddress != null &&
                            rule.followerPrefabAddress.RuntimeKeyIsValid()) { hasAddress = true; break; }
                if (!hasAddress) continue;
                nearest = pickup; item = definition.itemIndex; group = candidateGroup; distance = candidateDistance;
            }
            if (!nearest) return;
            var run = Run.instance;
            var pickupIndex = nearest.pickup.pickupIndex;
            bool added = prefetch.TryAdd((nearest, model, item), () => LoadGroup(group),
                () => Run.instance == run && user.cachedBody == body && body && body.inventory &&
                      model && model.itemDisplayRuleSet == ruleSet &&
                      ReferenceEquals(ruleSet.GetItemDisplayRuleGroup(item).rules, group.rules) &&
                      nearest && nearest.isActiveAndEnabled && nearest.pickup.pickupIndex == pickupIndex &&
                      body.inventory.GetItemCountTotal(item) == 0 &&
                      (nearest.transform.position - body.corePosition).sqrMagnitude < 30f * 30f);
            if (added && !prefetchLogged)
            {
                prefetchLogged = true;
                Logger.LogInfo("First nearby pickup display preload started before collection; maximum four pickup groups within 30 metres, released when no longer needed.");
            }
        }

        void RestoreStreamingBudget()
        {
            if (!budgetActive) return;
            if (Application.backgroundLoadingPriority == ThreadPriority.Low)
                Application.backgroundLoadingPriority = previousPriority;
            if (QualitySettings.asyncUploadTimeSlice == 2)
                QualitySettings.asyncUploadTimeSlice = previousUploadSlice;
            budgetActive = false;
        }

        void DisableDisplay(On.RoR2.CharacterModel.orig_DisableItemDisplay orig, CharacterModel model, ItemIndex item)
        {
            jobs.Cancel((model, item));
            orig(model, item);
        }

        void OnDestroy()
        {
            RestoreStreamingBudget();
            prefetch.Dispose();
            StopAllCoroutines();
            jobs.Dispose();
            On.RoR2.CharacterModel.InstantiateDisplayRuleGroup -= InstantiateGroup;
            On.RoR2.CharacterModel.DisableItemDisplay -= DisableDisplay;
        }

        sealed class AssetLoad : IDisplayLoad
        {
            readonly AssetOrDirectReference<GameObject> reference;
            readonly ManualLogSource log;
            public AssetLoad(AssetReferenceT<GameObject> address, ManualLogSource logger)
            {
                log = logger;
                reference = new AssetOrDirectReference<GameObject> { loadOnAssigned = false, address = address };
                try { reference.LoadAsync(); }
                catch { Dispose(); throw; }
            }
            public bool IsDone => !reference.loadHandle.IsValid() || reference.IsDone;
            public bool Succeeded
            {
                get
                {
                    bool success = reference.loadHandle.IsValid() && reference.IsDone && reference.Result;
                    if (!success) log.LogWarning("An item-display asset failed to load; the item remains in the inventory.");
                    return success;
                }
            }
            public void Dispose()
            {
                try { reference.Release(false); }
                catch (Exception error) { log.LogWarning("Item-display reference release failed: " + error.GetType().Name); }
            }
        }
    }
}
