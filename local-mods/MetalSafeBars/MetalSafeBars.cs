using BepInEx;
using System;
using System.Collections.Generic;
using TMPro;
using UnityEngine;
using UnityEngine.UI;

namespace MetalSafeBars
{
    [BepInPlugin("me.metalfix.ror2.healthbars", "MetalSafeBars", "1.0.2")]
    public class MetalSafeBarsPlugin : BaseUnityPlugin
    {
        internal static Sprite WhiteSprite;
        internal static Material UnlitMat;
        internal static Material UiDefaultMat;

        private void Awake()
        {
            Logger.LogInfo("[MetalSafeBars] Loaded local fix 1.0.2: event-driven healthbar discovery");
            EnsureWhiteSprite();
            EnsureMaterials();
            On.RoR2.UI.HealthBar.OnEnable += EnableBar;
        }

        private void OnDestroy() => On.RoR2.UI.HealthBar.OnEnable -= EnableBar;

        private void EnableBar(On.RoR2.UI.HealthBar.orig_OnEnable orig, RoR2.UI.HealthBar bar)
        {
            orig(bar);
            try
            {
                var go = bar.gameObject;
                if (!go || HasComponentTypeInParents(go, "BossHealthBar")) return;
                var fixer = go.GetComponent<MetalSafeHealthbarFixer>();
                if (!fixer) fixer = go.AddComponent<MetalSafeHealthbarFixer>();
                fixer.Init(go, Logger);
            }
            catch (Exception error) { Logger.LogError(error); }
        }

        private void EnsureMaterials()
        {
            try { var sh = Shader.Find("Unlit/Color"); if (sh) UnlitMat = new Material(sh); } catch {}
            try { var sh = Shader.Find("UI/Default");   if (sh) UiDefaultMat = new Material(sh); } catch {}
        }

        private static void EnsureWhiteSprite()
        {
            if (WhiteSprite) return;
            var tex = new Texture2D(1, 1, TextureFormat.RGBA32, false);
            tex.SetPixel(0, 0, Color.white);
            tex.Apply();
            WhiteSprite = Sprite.Create(tex, new Rect(0, 0, 1, 1), new Vector2(0.5f, 0.5f), 1f);
        }

        private static bool HasComponentTypeInParents(GameObject go, string typeName)
        {
            var comps = go.GetComponentsInParent<Component>(true);
            foreach (var c in comps)
                if (c != null && c.GetType().Name == typeName) return true;
            return false;
        }
    }

    // СТОРОЖ: не рисует свой UI, только чинит материалы/спрайты у нативных картинок
    internal class MetalSafeHealthbarFixer : MonoBehaviour
    {
        private GameObject _root;
        private BepInEx.Logging.ManualLogSource _log;
        private float _nextScan;
        private int _lastChildrenHash;
        private readonly List<Image> _images = new List<Image>();
        private readonly List<TMP_Text> _texts = new List<TMP_Text>();

        public void Init(GameObject root, BepInEx.Logging.ManualLogSource log)
        {
            _root = root;
            _log = log;
            ForcePatch("Init");
        }

        private void OnEnable() => ForcePatch("OnEnable");
        private void OnTransformChildrenChanged() => ForcePatch("ChildrenChanged");

        private void LateUpdate()
        {
            if (Time.time >= _nextScan)
            {
                _nextScan = Time.time + 0.33f;
                Refresh(false);
            }
        }

        private int ChildrenHash()
        {
            if (!_root) return 0;
            unchecked
            {
                int h = 17;
                foreach (var i in _images) if (i) h = h * 31 + i.GetInstanceID();
                foreach (var t in _texts) if (t) h = h * 31 + t.GetInstanceID();
                return h;
            }
        }

        private void ForcePatch(string reason)
        {
            try
            {
                Refresh(true);
                _log?.LogDebug($"[MetalSafeBars] Patched HB ({reason})");
            }
            catch (Exception e)
            {
                _log?.LogError(e);
            }
        }

        private void Refresh(bool full)
        {
            if (!_root) return;

            // Reuse buffers and scan each hierarchy once, including pooled inactive children.
            _root.GetComponentsInChildren(true, _images);
            _root.GetComponentsInChildren(true, _texts);
            int hash = ChildrenHash();
            PatchOnce(full || hash != _lastChildrenHash);
            _lastChildrenHash = hash;
        }

        private void PatchOnce(bool full)
        {
            if (!_root) return;

            // Images
            foreach (var img in _images)
            {
                if (!img) continue;

                if (!img.sprite && MetalSafeBarsPlugin.WhiteSprite)
                    img.sprite = MetalSafeBarsPlugin.WhiteSprite;

                if (MetalSafeBarsPlugin.UnlitMat) img.material = MetalSafeBarsPlugin.UnlitMat;
                else if (MetalSafeBarsPlugin.UiDefaultMat) img.material = MetalSafeBarsPlugin.UiDefaultMat;
                else img.material = null;

                img.maskable = false;
                img.useSpriteMesh = false;

                var c = img.color; if (c.a <= 0f) { c.a = 1f; img.color = c; }

                if (full && img.type == Image.Type.Filled)
                {
                    img.fillMethod = Image.FillMethod.Horizontal;
                    img.fillOrigin = (int)Image.OriginHorizontal.Left;
                }
            }

            // TMP
            foreach (var t in _texts)
            {
                if (!t) continue;
                try
                {
                    if (t.font) t.fontMaterial = t.font.material;
                }
                catch { }
            }
        }
    }
}
