using System;
using System.Globalization;
using System.Diagnostics;
using BepInEx;
using RoR2;
using Unity.Profiling;
using UnityEngine;
using UnityEngine.Profiling;
using UnityEngine.SceneManagement;

namespace RoR2FrameProbe
{
    [BepInPlugin("local.ror2.frameprobe", "Local Frame Probe", "1.0.2")]
    public sealed class Probe : BaseUnityPlugin
    {
        readonly FrameWindow window = new FrameWindow();
        readonly CallTiming effects = new CallTiming(), inventory = new CallTiming(), purchases = new CallTiming();
        static readonly double TickMs = 1000.0 / Stopwatch.Frequency;
        ProfilerRecorder main, render, gc, allocated;
        int lastCollections;
        float nextReport;

        void Awake()
        {
            main = CreateRecorder(ProfilerCategory.Internal, "Main Thread");
            render = CreateRecorder(ProfilerCategory.Internal, "Render Thread");
            gc = CreateRecorder(ProfilerCategory.Scripts, "GC.Collect");
            allocated = CreateRecorder(ProfilerCategory.Memory, "GC Allocated In Frame");
            lastCollections = GC.CollectionCount(0);
            On.RoR2.EffectManager.SpawnEffect_EffectIndex_EffectData_bool += Effect;
            On.RoR2.CharacterBody.OnInventoryChanged += InventoryChanged;
            On.RoR2.PurchaseInteraction.OnInteractionBegin += Purchase;
            Logger.LogInfo($"Frame probe ready: main={main.Valid}, render={render.Valid}, gc={gc.Valid}, allocations={allocated.Valid}; unavailable samples are -1. Graphics and GC behavior are unchanged.");
            Logger.LogInfo("Event timing active: effect spawning, inventory changes and purchases; original calls run unchanged.");
        }

        void Effect(On.RoR2.EffectManager.orig_SpawnEffect_EffectIndex_EffectData_bool orig, EffectIndex index, EffectData data, bool transmit)
        {
            long start = Stopwatch.GetTimestamp();
            try { orig(index, data, transmit); }
            finally { effects.Record(Stopwatch.GetTimestamp() - start); }
        }

        void InventoryChanged(On.RoR2.CharacterBody.orig_OnInventoryChanged orig, CharacterBody body)
        {
            long start = Stopwatch.GetTimestamp();
            try { orig(body); }
            finally { inventory.Record(Stopwatch.GetTimestamp() - start); }
        }

        void Purchase(On.RoR2.PurchaseInteraction.orig_OnInteractionBegin orig, PurchaseInteraction purchase, Interactor interactor)
        {
            long start = Stopwatch.GetTimestamp();
            try { orig(purchase, interactor); }
            finally { purchases.Record(Stopwatch.GetTimestamp() - start); }
        }

        void ResetWindow()
        {
            window.Reset(); effects.Reset(); inventory.Reset(); purchases.Reset();
        }

        ProfilerRecorder CreateRecorder(ProfilerCategory category, string name)
        {
            try { return ProfilerRecorder.StartNew(category, name, 1); }
            catch (Exception error) { Logger.LogWarning(name + " unavailable: " + error.GetType().Name); return default; }
        }

        static long Read(ProfilerRecorder recorder) => recorder.Valid && recorder.Count > 0 ? recorder.LastValue : -1;

        void LateUpdate()
        {
            int count = GC.CollectionCount(0);
            int collections = Math.Max(0, count - lastCollections);
            lastCollections = count;
            float now = Time.unscaledTime;
            if (!Run.instance || !Application.isFocused)
            {
                ResetWindow();
                nextReport = now + 2;
                return;
            }
            window.Add(Time.unscaledDeltaTime * 1000.0, collections, Read(main), Read(render), Read(gc), Read(allocated));
            if (now < nextReport) return;
            nextReport = now + 2;
            // At most one line per two seconds, with no strings or collections allocated per frame.
            Logger.LogInfo(string.Format(CultureInfo.InvariantCulture,
                "FRAMEWINDOW time={0:F2} frame={1} scene={2} frames={3} over20ms={4} worstMs={5:F2} collections={6} mainNs={7} renderNs={8} gcNs={9} allocBytes={10} monoUsedMB={11:F1} monoHeapMB={12:F1} effectCalls={13} effectMaxMs={14:F3} inventoryCalls={15} inventoryMaxMs={16:F3} purchaseCalls={17} purchaseMaxMs={18:F3}",
                now, Time.frameCount, SceneManager.GetActiveScene().name, window.Frames, window.SlowFrames,
                window.WorstMs, window.Collections, window.MainNs, window.RenderNs, window.GcNs, window.AllocBytes,
                Profiler.GetMonoUsedSizeLong() / 1048576.0, Profiler.GetMonoHeapSizeLong() / 1048576.0,
                effects.Calls, effects.MaxTicks * TickMs, inventory.Calls, inventory.MaxTicks * TickMs,
                purchases.Calls, purchases.MaxTicks * TickMs));
            ResetWindow();
        }

        void OnDestroy()
        {
            On.RoR2.EffectManager.SpawnEffect_EffectIndex_EffectData_bool -= Effect;
            On.RoR2.CharacterBody.OnInventoryChanged -= InventoryChanged;
            On.RoR2.PurchaseInteraction.OnInteractionBegin -= Purchase;
            main.Dispose(); render.Dispose(); gc.Dispose(); allocated.Dispose();
        }
    }
}
