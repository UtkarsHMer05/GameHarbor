using System;
using System.Collections.Generic;

namespace AsyncItemDisplays
{
    internal sealed class DisplayPrefetch<TKey> : IDisposable
    {
        readonly Dictionary<TKey, (IDisplayLoad[] loads, Func<bool> needed)> pending =
            new Dictionary<TKey, (IDisplayLoad[], Func<bool>)>();
        readonly List<TKey> expired = new List<TKey>();

        public bool IsFull => pending.Count >= 4;
        public bool Contains(TKey key) => pending.ContainsKey(key);

        public bool TryAdd(TKey key, Func<IDisplayLoad[]> load, Func<bool> needed)
        {
            if (IsFull || pending.ContainsKey(key)) return false;
            var loads = load();
            if (loads.Length == 0) return false;
            pending.Add(key, (loads, needed));
            return true;
        }

        public void Prune()
        {
            expired.Clear();
            foreach (var pair in pending)
                if (!pair.Value.needed()) expired.Add(pair.Key);
            foreach (var key in expired)
            {
                foreach (var load in pending[key].loads) load.Dispose();
                pending.Remove(key);
            }
            expired.Clear();
        }

        public void Dispose()
        {
            foreach (var pair in pending)
                foreach (var load in pair.Value.loads) load.Dispose();
            pending.Clear();
            expired.Clear();
        }
    }
}
