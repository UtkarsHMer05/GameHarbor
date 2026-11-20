namespace RoR2FrameProbe
{
    internal sealed class CallTiming
    {
        public int Calls;
        public long MaxTicks;
        public void Record(long ticks)
        {
            Calls++;
            if (ticks > MaxTicks) MaxTicks = ticks;
        }
        public void Reset() { Calls = 0; MaxTicks = 0; }
    }

    internal sealed class FrameWindow
    {
        public int Frames, SlowFrames, Collections;
        public double WorstMs;
        public long MainNs, RenderNs, GcNs, AllocBytes;

        public void Add(double ms, int collections, long mainNs, long renderNs, long gcNs, long allocBytes)
        {
            Frames++;
            if (ms > 20) SlowFrames++;
            Collections += collections;
            // Counters are approximate previous-frame samples; retain those at the worst observed frame.
            if (ms > WorstMs)
            {
                WorstMs = ms;
                MainNs = mainNs; RenderNs = renderNs; GcNs = gcNs; AllocBytes = allocBytes;
            }
        }

        public void Reset()
        {
            Frames = SlowFrames = Collections = 0;
            WorstMs = 0;
            MainNs = RenderNs = GcNs = AllocBytes = 0;
        }
    }
}
