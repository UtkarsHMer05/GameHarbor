using System;
using RoR2FrameProbe;

var window = new FrameWindow();
window.Add(16.7, 0, 10, 20, 0, 100);
window.Add(48.2, 1, 30, 40, 15, 200);
window.Add(21, 0, 50, 60, 0, 300);
if (window.Frames != 3 || window.SlowFrames != 2 || window.Collections != 1 ||
    window.WorstMs != 48.2 || window.GcNs != 15 || window.MainNs != 30 || window.AllocBytes != 200)
    throw new Exception("Slow-frame summary lost the worst frame or collection count");
window.Reset();
if (window.Frames != 0 || window.WorstMs != 0 || window.Collections != 0 || window.AllocBytes != 0)
    throw new Exception("Summary leaked data between windows");
for (int i = 0; i < 1000; i++) window.Add(16.7, 0, -1, -1, -1, -1);
window.Reset();
long before = GC.GetAllocatedBytesForCurrentThread();
for (int i = 0; i < 10000; i++) window.Add(16.7, 0, -1, -1, -1, -1);
if (GC.GetAllocatedBytesForCurrentThread() != before || window.MainNs != -1 || window.GcNs != -1)
    throw new Exception("Frame accumulation allocated or masked unavailable counters");
Console.WriteLine("PASS: slow frames, worst-frame counters, GC count, window reset, unavailable counters, allocation-free accumulation.");
var call = new CallTiming();
call.Record(12); call.Record(4); call.Record(9);
if (call.Calls != 3 || call.MaxTicks != 12) throw new Exception("Call timing lost the slowest call");
call.Reset();
if (call.Calls != 0 || call.MaxTicks != 0) throw new Exception("Call timing leaked between windows");
before = GC.GetAllocatedBytesForCurrentThread();
for (int i = 0; i < 10000; i++) call.Record(i);
if (GC.GetAllocatedBytesForCurrentThread() != before) throw new Exception("Event timing accumulation allocated");
Console.WriteLine("PASS: event call counts, peak duration, reset and allocation-free event accumulation.");
