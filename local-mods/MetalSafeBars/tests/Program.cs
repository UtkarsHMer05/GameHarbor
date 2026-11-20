using System;
using System.Collections;
using System.Collections.Generic;
using System.Reflection;
using MetalSafeBars;
using TMPro;
using UnityEngine;
using UnityEngine.UI;

static class Program
{
    static void Check(bool condition, string message)
    {
        if (!condition) throw new Exception(message);
    }

    static void Main()
    {
        var root = new GameObject();
        var image = new Image { type = Image.Type.Filled };
        var text = new TMP_Text { font = new FontAsset { material = new Material(null) } };
        root.Children.Add(image);
        root.Children.Add(text);
        MetalSafeBarsPlugin.WhiteSprite = new Sprite();
        MetalSafeBarsPlugin.UnlitMat = new Material(null);
        var fixer = new MetalSafeHealthbarFixer();
        fixer.Init(root, new BepInEx.Logging.ManualLogSource());
        var refresh = (Action<bool>)typeof(MetalSafeHealthbarFixer)
            .GetMethod("Refresh", BindingFlags.Instance | BindingFlags.NonPublic)
            .CreateDelegate(typeof(Action<bool>), fixer);
        Check(image.sprite == MetalSafeBarsPlugin.WhiteSprite && !image.maskable,
            "Initial healthbar fix was lost");
        Check(image.material == MetalSafeBarsPlugin.UnlitMat && text.fontMaterial == text.font.material,
            "Original material repair was lost");

        var pooled = new Image { type = Image.Type.Filled, active = false };
        root.Children.Add(pooled);
        refresh(false);
        Check(pooled.sprite != null && pooled.fillOrigin == (int)Image.OriginHorizontal.Left,
            "New inactive pooled children must receive the full patch");
        root.Children.Remove(pooled);
        pooled.sprite = null;
        refresh(false);
        Check(pooled.sprite == null, "Removed children must not remain in the scan buffers");
        root.Children.Add(pooled);
        refresh(false);
        Check(pooled.sprite != null, "Reused pooled children must be repaired again");

        // Warm buffers, JIT and delegates before measuring only the actual refresh path.
        for (int n = 0; n < 1000; n++) refresh(false);
        int scans = root.ScanCount;
        long before = GC.GetAllocatedBytesForCurrentThread();
        for (int n = 0; n < 10000; n++) refresh(false);
        long allocated = GC.GetAllocatedBytesForCurrentThread() - before;
        Check(allocated == 0, $"Unchanged refreshes allocated {allocated} bytes");
        Check(root.ScanCount - scans == 20000, "Each refresh must scan each component type just once");

        var plugin = new MetalSafeBarsPlugin();
        typeof(MetalSafeBarsPlugin).GetMethod("Awake", BindingFlags.Instance | BindingFlags.NonPublic).Invoke(plugin, null);
        int originalCalls = 0;
        var bar = new GameObject();
        var healthbar = new RoR2.UI.HealthBar { gameObject = bar };
        On.RoR2.UI.HealthBar.Raise(healthbar, _ => originalCalls++);
        Check(bar.GetComponent<MetalSafeHealthbarFixer>() != null && originalCalls == 1, "Enable event must call original once and attach a fixer");
        int children = bar.Children.Count;
        On.RoR2.UI.HealthBar.Raise(healthbar, _ => originalCalls++);
        Check(bar.Children.Count == children && originalCalls == 2, "Reused bars must not get duplicate fixers");
        var pooledImage = new Image();
        bar.Children.Add(pooledImage);
        On.RoR2.UI.HealthBar.Raise(healthbar, _ => originalCalls++);
        Check(pooledImage.sprite != null, "Re-enabled pooled bars must repair new children");
        Check(Resources.Scans == 0, "Bar discovery must never scan all loaded Unity objects");
        typeof(MetalSafeBarsPlugin).GetMethod("OnDestroy", BindingFlags.Instance | BindingFlags.NonPublic).Invoke(plugin, null);
        var afterShutdown = new RoR2.UI.HealthBar { gameObject = new GameObject() };
        On.RoR2.UI.HealthBar.Raise(afterShutdown, _ => originalCalls++);
        Check(afterShutdown.gameObject.GetComponent<MetalSafeHealthbarFixer>() == null && originalCalls == 4, "Shutdown must remove the hook and preserve original behavior");
        root.destroyed = true;
        refresh(false);
        Console.WriteLine("PASS: initial, new/inactive, removed, pooled and destroyed bars; event-driven discovery, pooled re-enable, hook cleanup, no global scans; 10,000 steady refreshes: 0 managed bytes, two scans each (stub runtime).");
    }
}

// Small Unity/BepInEx doubles exercise the real plugin source outside the game.
// Unity's native scan implementation and rendered output still require a gameplay check.
namespace UnityEngine
{
    public class Object
    {
        static int nextId;
        readonly int id = ++nextId;
        public bool destroyed;
        public int GetInstanceID() => id;
        public static implicit operator bool(Object value) => value != null && !value.destroyed;
        public static bool operator !(Object value) => !(bool)value;
    }
    public class Component : Object { public GameObject gameObject; }
    public class MonoBehaviour : Component { protected void StartCoroutine(IEnumerator value) { } }
    public class GameObject : Object
    {
        public bool activeInHierarchy = true;
        public readonly List<Component> Children = new List<Component>();
        public int ScanCount;
        public T GetComponent<T>() where T : Component
        { foreach (var c in Children) if (c is T match) return match; return null; }
        public T AddComponent<T>() where T : Component, new()
        { var item = new T { gameObject = this }; Children.Add(item); return item; }
        public T[] GetComponentsInParent<T>(bool inactive) => Array.Empty<T>();
        public void GetComponentsInChildren<T>(bool inactive, List<T> results) where T : Component
        {
            ScanCount++;
            results.Clear();
            foreach (var child in Children)
                if (child is T match && (inactive || !(child is Image image) || image.active)) results.Add(match);
        }
    }
    public class Material : Object { public Material(Shader shader) { } }
    public class Shader : Object { public static Shader Find(string name) => new Shader(); }
    public class Sprite : Object { public static Sprite Create(Texture2D t, Rect r, Vector2 v, float n) => new Sprite(); }
    public class Texture2D : Object
    {
        public Texture2D(int w, int h, TextureFormat f, bool m) { }
        public void SetPixel(int x, int y, Color c) { }
        public void Apply() { }
    }
    public enum TextureFormat { RGBA32 }
    public struct Rect { public Rect(int x, int y, int w, int h) { } }
    public struct Vector2 { public Vector2(float x, float y) { } }
    public struct Color { public float a; public static Color white => new Color { a = 1 }; }
    public static class Time { public static float time; }
    public class WaitForSeconds { public WaitForSeconds(float time) { } }
    public static class Resources
    {
        public static Object[] Objects = Array.Empty<Object>();
        public static int Scans;
        public static Object[] FindObjectsOfTypeAll(Type type) { Scans++; return Objects; }
    }
}
namespace UnityEngine.UI
{
    public class Image : Component
    {
        public enum Type { Simple, Filled }
        public enum FillMethod { Radial360, Horizontal }
        public enum OriginHorizontal { Left, Right }
        public Sprite sprite;
        public Material material;
        public bool maskable = true, useSpriteMesh = true, active = true;
        public Color color;
        public Type type;
        public FillMethod fillMethod;
        public int fillOrigin = (int)OriginHorizontal.Right;
    }
}
namespace TMPro
{
    public class FontAsset : UnityEngine.Object { public Material material; }
    public class TMP_Text : Component { public FontAsset font; public Material fontMaterial; }
}
namespace BepInEx
{
    [AttributeUsage(AttributeTargets.Class)]
    public class BepInPlugin : Attribute { public BepInPlugin(string id, string name, string version) { } }
    public class BaseUnityPlugin : MonoBehaviour { public Logging.ManualLogSource Logger = new Logging.ManualLogSource(); }
}
namespace BepInEx.Logging
{
    public class ManualLogSource
    {
        public void LogInfo(object value) { }
        public void LogDebug(object value) { }
        public void LogWarning(object value) { }
        public void LogError(object value) { }
    }
}

namespace RoR2.UI { public class HealthBar : UnityEngine.MonoBehaviour { } }
namespace On.RoR2.UI
{
    public static class HealthBar
    {
        public delegate void orig_OnEnable(global::RoR2.UI.HealthBar bar);
        public delegate void hook_OnEnable(orig_OnEnable orig, global::RoR2.UI.HealthBar bar);
        public static event hook_OnEnable OnEnable;
        public static void Raise(global::RoR2.UI.HealthBar bar, orig_OnEnable orig)
        {
            if (OnEnable != null) OnEnable(orig, bar); else orig(bar);
        }
    }
}
