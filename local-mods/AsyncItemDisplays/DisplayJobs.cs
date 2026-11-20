using System;
using System.Collections;
using System.Collections.Generic;

namespace AsyncItemDisplays
{
    internal interface IDisplayLoad : IDisposable
    {
        bool IsDone { get; }
        bool Succeeded { get; }
    }

    internal sealed class DisplayJobs<TKey> : IDisposable
    {
        sealed class Request
        {
            public IDisplayLoad[] Loads;
            bool released;
            public void Release()
            {
                if (released) return;
                released = true;
                foreach (var load in Loads) load.Dispose();
            }
        }

        readonly Dictionary<TKey, Request> pending = new Dictionary<TKey, Request>();
        readonly HashSet<Request> active = new HashSet<Request>();
        readonly Func<int> frame;
        readonly Func<bool> canApply;
        int lastApplyFrame = -1;

        public DisplayJobs(Func<int> frame, Func<bool> canApply)
        {
            this.frame = frame;
            this.canApply = canApply;
        }

        public IEnumerator Begin(TKey key, IDisplayLoad[] loads, Func<bool> needed, int ruleCount, Action<int> apply)
        {
            var request = new Request { Loads = loads };
            pending[key] = request;
            active.Add(request);
            return Run(key, request, needed, ruleCount, apply);
        }

        bool IsCurrent(TKey key, Request request) =>
            pending.TryGetValue(key, out var current) && ReferenceEquals(current, request);

        IEnumerator Run(TKey key, Request request, Func<bool> needed, int ruleCount, Action<int> apply)
        {
            try
            {
                // Even cached prefabs must leave the pickup/spawn frame before instantiation.
                yield return null;
                foreach (var load in request.Loads)
                {
                    while (!load.IsDone)
                    {
                        if (!IsCurrent(key, request) || !needed()) yield break;
                        yield return null;
                    }
                    if (!load.Succeeded) yield break;
                }
                for (int rule = 0; rule < ruleCount; rule++)
                {
                    while (true)
                    {
                        if (!IsCurrent(key, request) || !needed()) yield break;
                        if (lastApplyFrame != frame() && canApply()) break;
                        yield return null;
                    }
                    lastApplyFrame = frame();
                    // shortcut: a single prefab is indivisible, investigate native instantiation if it still hitches.
                    apply(rule);
                }
            }
            finally
            {
                request.Release();
                active.Remove(request);
                if (IsCurrent(key, request)) pending.Remove(key);
            }
        }

        public void Cancel(TKey key) => pending.Remove(key);

        public void Dispose()
        {
            // Includes superseded requests even if Unity stops a coroutine without disposing it.
            foreach (var request in active) request.Release();
            active.Clear();
            pending.Clear();
        }
    }
}
