using System;
using System.Collections;
using AsyncItemDisplays;

static class Program
{
    sealed class Load : IDisplayLoad
    {
        public bool IsDone { get; set; }
        public bool Succeeded { get; set; } = true;
        public int Releases;
        public void Dispose() => Releases++;
    }
    static void Check(bool ok, string why) { if (!ok) throw new Exception(why); }
    static void Main()
    {
        int frame = 0; bool sceneReady = true;
        using var jobs = new DisplayJobs<int>(() => frame, () => sceneReady);
        bool Next(IEnumerator routine) { frame++; return routine.MoveNext(); }
        int applied = 0;
        var a = new Load(); var b = new Load();
        var routine = jobs.Begin(1, new IDisplayLoad[] { a, b }, () => true, 1, _ => applied++);
        Check(routine.MoveNext() && applied == 0, "Must return control while assets load");
        a.IsDone = true;
        Check(routine.MoveNext() && applied == 0, "Must wait asynchronously for all assets");
        b.IsDone = true;
        Check(!Next(routine) && applied == 1 && a.Releases == 1 && b.Releases == 1, "Ready display must apply once and release temporary references");

        var cancelled = new Load();
        var old = jobs.Begin(2, new IDisplayLoad[] { cancelled }, () => true, 1, _ => applied++);
        Check(old.MoveNext(), "Pending display should yield");
        jobs.Cancel(2);
        cancelled.IsDone = true;
        Check(!Next(old) && applied == 1 && cancelled.Releases == 1, "Removed items must not reappear when loading finishes");

        var replaced = new Load();
        var first = jobs.Begin(3, new IDisplayLoad[] { replaced }, () => true, 1, _ => applied++);
        first.MoveNext();
        var latest = new Load { IsDone = true };
        var second = jobs.Begin(3, new IDisplayLoad[] { latest }, () => true, 1, _ => applied++);
        replaced.IsDone = true;
        Check(second.MoveNext(), "Cached replacements must yield before applying");
        Check(!Next(first) && !Next(second) && applied == 2, "An older request must not duplicate or cancel its replacement");

        var deadModel = new Load();
        var dead = jobs.Begin(4, new IDisplayLoad[] { deadModel }, () => false, 1, _ => applied++);
        Check(dead.MoveNext(), "Even cancelled requests yield out of the spawn frame");
        Check(!Next(dead) && applied == 2 && deadModel.Releases == 1, "Destroyed/replaced models must cancel safely");
        var failed = new Load { IsDone = true, Succeeded = false };
        var failedRoutine = jobs.Begin(5, new IDisplayLoad[] { failed }, () => true, 1, _ => applied++);
        failedRoutine.MoveNext();
        Check(!Next(failedRoutine) && applied == 2 && failed.Releases == 1, "Failed assets must not instantiate broken displays");

        var throwing = new Load { IsDone = true };
        bool preservedException = false;
        var throwingRoutine = jobs.Begin(6, new IDisplayLoad[] { throwing }, () => true, 1, _ => throw new InvalidOperationException());
        throwingRoutine.MoveNext();
        try { Next(throwingRoutine); }
        catch (InvalidOperationException) { preservedException = true; }
        Check(preservedException && throwing.Releases == 1, "An original-method exception must propagate and still release temporary assets");
        int before = applied;
        var cached = new Load { IsDone = true };
        var multi = jobs.Begin(8, new IDisplayLoad[] { cached }, () => true, 3, i =>
        {
            Check(i == applied - before, "Rules must retain their original order");
            applied++;
        });
        var direct = jobs.Begin(9, Array.Empty<IDisplayLoad>(), () => true, 1, _ => applied++);
        Check(multi.MoveNext() && direct.MoveNext() && applied == before, "Cached and direct-prefab displays must leave the pickup frame");
        sceneReady = false;
        Check(Next(multi) && Next(direct) && applied == before, "Scene loading must not instantiate cosmetic displays");
        sceneReady = true;
        Check(Next(multi) && applied == before + 1, "Only the first rule may run in a frame");
        Check(direct.MoveNext() && multi.MoveNext() && applied == before + 1, "All models must share the same one-rule-per-frame budget");
        Check(Next(multi) && applied == before + 2, "Second rule must run in a later frame");
        Check(!Next(multi) && applied == before + 3 && cached.Releases == 1, "Last rule must complete and release its assets");
        Check(direct.MoveNext() && applied == before + 3, "Another model cannot reuse an already-consumed frame");
        Check(!Next(direct) && applied == before + 4, "Direct-prefab displays must eventually attach");

        bool needed = true;
        int partialCalls = 0;
        var partialLoad = new Load { IsDone = true };
        var partial = jobs.Begin(10, new IDisplayLoad[] { partialLoad }, () => needed, 3, _ => partialCalls++);
        partial.MoveNext();
        Check(Next(partial) && partialCalls == 1, "First cosmetic rule should apply");
        needed = false;
        Check(!Next(partial) && partialCalls == 1 && partialLoad.Releases == 1, "Removed items or old-area models must cancel remaining rules");

        var stopped = new Load();
        var stoppedRoutine = jobs.Begin(7, new IDisplayLoad[] { stopped }, () => true, 1, _ => applied++);
        stoppedRoutine.MoveNext();
        jobs.Cancel(7);
        jobs.Dispose();
        ((IDisposable)stoppedRoutine).Dispose();
        Check(stopped.Releases == 1, "Shutdown and coroutine disposal must release cancelled requests exactly once");

        using var prefetch = new DisplayPrefetch<int>();
        var warm = new Load[5];
        bool keepFirst = true;
        int factories = 0;
        for (int i = 0; i < 4; i++)
        {
            int key = i;
            warm[i] = new Load();
            Check(prefetch.TryAdd(key, () => { factories++; return new IDisplayLoad[] { warm[key] }; },
                () => key != 0 || keepFirst), "Four pickup groups should fit without blocking on unfinished loads");
        }
        Check(prefetch.IsFull && prefetch.Contains(0), "Prefetch limit must be enforced");
        Check(!prefetch.TryAdd(0, () => throw new Exception("Duplicate must not load"), () => true), "Duplicate pickups must not take another reference");
        Check(!prefetch.TryAdd(4, () => throw new Exception("Full cache must not load"), () => true) && factories == 4,
            "A fifth pickup must not start loading while all four slots are held");
        prefetch.Prune();
        Check(warm[0].Releases == 0, "Nearby uncollected pickups must retain their references");
        keepFirst = false;
        prefetch.Prune();
        Check(!prefetch.IsFull && !prefetch.Contains(0) && warm[0].Releases == 1,
            "Collected, recycled, distant or old-scene pickups must release their slot");
        bool loadError = false;
        try { prefetch.TryAdd(4, () => throw new InvalidOperationException(), () => true); }
        catch (InvalidOperationException) { loadError = true; }
        Check(loadError && !prefetch.Contains(4), "Failed preparation must not retain a cache slot");
        warm[4] = new Load();
        Check(prefetch.TryAdd(4, () => new IDisplayLoad[] { warm[4] }, () => true), "An expired slot must be reusable");
        prefetch.Dispose();
        prefetch.Prune();
        prefetch.Dispose();
        foreach (var load in warm) Check(load.Releases == 1, "Scene exit/shutdown must release every prefetch exactly once");
        Console.WriteLine("PASS: async loads, cached/direct deferral, shared frame budget, ordered rules, scene-loading gate, partial cancellation, replacement, destroyed models, failed loads, exception propagation and shutdown cleanup.");
        Console.WriteLine("PASS: four-group prefetch cap, no duplicate loads, non-blocking unfinished loads, retained nearby assets, expiration, slot reuse, failed preparation and exactly-once cleanup.");
    }
}
