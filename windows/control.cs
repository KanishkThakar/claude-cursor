// control.cs - claude-control: background computer use for Windows via native UI Automation (COM).
// Copyright (c) 2026 Kanishk Thakar. MIT License - https://github.com/KanishkThakar/claude-cursor
//
//   claude-control windows                                  list top-level windows
//   claude-control ui   --app APP [--title T] [--window HWND] [--max N] [--all]
//   claude-control find --app APP [--name TEXT] [--type ControlType] [--id AutomationId]
//   claude-control click REF          invoke / toggle / select / expand (in the background)
//   claude-control type  REF TEXT [--append]
//   claude-control read  [REF] [--app APP ...]
//   claude-control focus REF          keyboard focus (can bring the window forward)
//
// Uses the native IUIAutomation COM API (UIAutomationCore.dll), which includes the system's
// proxies for classic Win32 controls. Never moves the pointer, never sends global keystrokes.
// If the Claude Cursor is running, it glides to each element first and narrates the step.
//
// Build: csc /nologo /optimize /target:exe /out:claude-control.exe control.cs   (C# 5)

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace ClaudeControl
{
    enum TreeScope { Element = 1, Children = 2, Descendants = 4, Subtree = 7 }

    [ComImport, Guid("352ffba8-0973-437c-a61f-f64cafd81df9"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IUIAutomationCondition { }

    [ComImport, Guid("14314595-b4bc-4055-95f2-58f2e42c9855"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IUIAutomationElementArray
    {
        int Length { get; }
        IUIAutomationElement GetElement(int index);
    }

    [ComImport, Guid("d22108aa-8ac5-49a5-837b-37bbb3d7591e"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IUIAutomationElement
    {
        void SetFocus();
        [return: MarshalAs(UnmanagedType.SafeArray, SafeArraySubType = VarEnum.VT_I4)] int[] GetRuntimeId();
        IUIAutomationElement FindFirst(TreeScope scope, IUIAutomationCondition condition);
        IUIAutomationElementArray FindAll(TreeScope scope, IUIAutomationCondition condition);
        void _FindFirstBuildCache();
        void _FindAllBuildCache();
        void _BuildUpdatedCache();
        [return: MarshalAs(UnmanagedType.Struct)] object GetCurrentPropertyValue(int propertyId);
        void _GetCurrentPropertyValueEx();
        void _GetCachedPropertyValue();
        void _GetCachedPropertyValueEx();
        void _GetCurrentPatternAs();
        void _GetCachedPatternAs();
        [return: MarshalAs(UnmanagedType.IUnknown)] object GetCurrentPattern(int patternId);
    }

    [ComImport, Guid("30cbe57d-d9d0-452a-ab13-7ac5ac4825ee"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IUIAutomation
    {
        void _CompareElements();
        void _CompareRuntimeIds();
        IUIAutomationElement GetRootElement();
        IUIAutomationElement ElementFromHandle(IntPtr hwnd);
        void _ElementFromPoint();
        void _GetFocusedElement();
        void _GetRootElementBuildCache();
        void _ElementFromHandleBuildCache();
        void _ElementFromPointBuildCache();
        void _GetFocusedElementBuildCache();
        void _CreateTreeWalker();
        void _ControlViewWalker();
        void _ContentViewWalker();
        void _RawViewWalker();
        IUIAutomationCondition RawViewCondition { get; }
        IUIAutomationCondition ControlViewCondition { get; }
        IUIAutomationCondition ContentViewCondition { get; }
        void _CreateCacheRequest();
        IUIAutomationCondition CreateTrueCondition();
    }

    [ComImport, Guid("fb377fbe-8ea6-46d5-9c73-6499642d3059"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IUIAutomationInvokePattern { void Invoke(); }

    [ComImport, Guid("a94cd8b1-0844-4cd6-9d2d-640537ab39e9"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IUIAutomationValuePattern { void SetValue([MarshalAs(UnmanagedType.BStr)] string val); }

    [ComImport, Guid("94cf8058-9b8d-4ab9-8bfd-4cd0a33c8c70"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IUIAutomationTogglePattern { void Toggle(); }

    [ComImport, Guid("a8efa66a-0fda-421a-9194-38021f3578ea"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IUIAutomationSelectionItemPattern { void Select(); }

    [ComImport, Guid("619be086-1f4e-4ee4-bafa-210128738730"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IUIAutomationExpandCollapsePattern { void Expand(); void Collapse(); }

    [ComImport, Guid("a543cc6a-f4ae-494b-8239-c814481187a8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IUIAutomationTextRange
    {
        void _Clone(); void _Compare(); void _CompareEndpoints(); void _ExpandToEnclosingUnit();
        void _FindAttribute(); void _FindText(); void _GetAttributeValue(); void _GetBoundingRectangles();
        void _GetEnclosingElement();
        [return: MarshalAs(UnmanagedType.BStr)] string GetText(int maxLength);
    }

    [ComImport, Guid("32eba289-3583-42c9-9c59-3b6d9a1e9b6a"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IUIAutomationTextPattern
    {
        void _RangeFromPoint(); void _RangeFromChild(); void _GetSelection(); void _GetVisibleRanges();
        IUIAutomationTextRange DocumentRange { get; }
    }

    static class P
    {
        public const int BoundingRectangle = 30001, ProcessId = 30002, ControlType = 30003, Name = 30005,
            IsEnabled = 30010, AutomationId = 30011, ClassName = 30012, NativeWindowHandle = 30020, IsOffscreen = 30022,
            IsExpandCollapse = 30028, IsInvoke = 30031, IsSelectionItem = 30036, IsText = 30040, IsToggle = 30041,
            IsValue = 30043, Value = 30045, ValueIsReadOnly = 30046, ExpandCollapseState = 30070, ToggleState = 30086;
        public const int PInvoke = 10000, PValue = 10002, PExpandCollapse = 10005, PSelectionItem = 10010, PText = 10014, PToggle = 10015;
    }

    static class W
    {
        public delegate bool EnumProc(IntPtr h, IntPtr l);
        [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
        [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
        [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
        [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
        [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
        [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
        [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
        [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
        [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out RECT r, int size);
        [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int size);
        public static string Title(IntPtr h) { var sb = new StringBuilder(512); GetWindowText(h, sb, 512); return sb.ToString(); }
        public static string Proc(IntPtr h)
        {
            int pid; GetWindowThreadProcessId(h, out pid);
            try { return Process.GetProcessById(pid).ProcessName; } catch (Exception) { return ""; }
        }
        public static bool Cloaked(IntPtr h) { int v = 0; try { DwmGetWindowAttribute(h, 14, out v, 4); } catch (Exception) { } return v != 0; }
        public static RECT Frame(IntPtr h) { RECT r; DwmGetWindowAttribute(h, 9, out r, 16); return r; }
    }

    class Item { public string Ref, Rid, Type, Name, Id, Value; public List<string> Pats = new List<string>(); public int X, Y, Wd, Ht; }

    static class Program
    {
        static IUIAutomation uia;
        static readonly string Dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "claude-ghost");
        static readonly string RefsF = Path.Combine(Dir, "refs.txt");
        static readonly UTF8Encoding Utf8 = new UTF8Encoding(false);
        static readonly string Dot = "·";

        static readonly Dictionary<int, string> Types = new Dictionary<int, string>();
        static Program()
        {
            string[] n = { "Button", "Calendar", "CheckBox", "ComboBox", "Edit", "Hyperlink", "Image", "ListItem", "List", "Menu",
                "MenuBar", "MenuItem", "ProgressBar", "RadioButton", "ScrollBar", "Slider", "Spinner", "StatusBar", "Tab", "TabItem",
                "Text", "ToolBar", "ToolTip", "Tree", "TreeItem", "Custom", "Group", "Thumb", "DataGrid", "DataItem", "Document",
                "SplitButton", "Window", "Pane", "Header", "HeaderItem", "Table", "TitleBar", "Separator", "SemanticZoom", "AppBar" };
            for (int i = 0; i < n.Length; i++) Types[50000 + i] = n[i];
        }

        static int Fail(string msg) { Console.WriteLine(msg); return 1; }

        [MTAThread]
        static int Main(string[] argv)
        {
            Console.OutputEncoding = Utf8;
            try { if (!W.SetProcessDpiAwarenessContext(new IntPtr(-4))) W.SetProcessDPIAware(); } catch (Exception) { try { W.SetProcessDPIAware(); } catch (Exception) { } }
            Directory.CreateDirectory(Dir);
            var o = Parse(argv);
            string cmd = o.Pos.Count > 0 ? o.Pos[0] : "help";
            if (o.Pos.Count > 0) o.Pos.RemoveAt(0);
            try
            {
                uia = (IUIAutomation)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("ff48dba4-60ef-4201-aa87-54103eef594e")));
                switch (cmd)
                {
                    case "windows": return ListWindows();
                    case "ui": case "find": return Ui(cmd, o);
                    case "click": return Click(o);
                    case "type": return TypeText(o);
                    case "read": return Read(o);
                    case "focus": return Focus(o);
                    default:
                        Console.WriteLine("usage: claude-control windows | ui --app APP [--title T] [--window HWND] [--max N] [--all] | find --app APP [--name X] [--type T] [--id ID] | click REF | type REF TEXT [--append] | read [REF] | focus REF");
                        return cmd == "help" ? 0 : 2;
                }
            }
            catch (COMException e) { return Fail("UI Automation error: " + e.Message); }
        }

        class Opts { public List<string> Pos = new List<string>(); public Dictionary<string, string> Kv = new Dictionary<string, string>(); }
        static Opts Parse(string[] a)
        {
            var o = new Opts();
            for (int i = 0; i < a.Length; i++)
            {
                if (a[i].StartsWith("--"))
                {
                    string k = a[i].Substring(2);
                    if (k == "append" || k == "all") o.Kv[k] = "1";
                    else o.Kv[k] = i + 1 < a.Length ? a[++i] : "";
                }
                else o.Pos.Add(a[i]);
            }
            return o;
        }
        static string Get(Opts o, string k) { string v; return o.Kv.TryGetValue(k, out v) ? v : null; }

        // ---------- windows ----------
        static List<IntPtr> TopWindows()
        {
            var list = new List<IntPtr>();
            W.EnumWindows(delegate(IntPtr h, IntPtr l)
            {
                if (!W.IsWindowVisible(h) || W.Cloaked(h) || (W.GetWindowLong(h, -20) & 0x80) != 0) return true;
                var r = W.Frame(h); if (r.R - r.L < 80 || r.B - r.T < 60) return true;
                if (W.Title(h).Length == 0) return true;
                list.Add(h); return true;
            }, IntPtr.Zero);
            return list;
        }
        static int ListWindows()
        {
            foreach (var h in TopWindows())
            {
                var r = W.Frame(h);
                Console.WriteLine(string.Format("{0,-10} {1,-18} \"{2}\" {3},{4} {5}x{6}", h.ToInt64(), W.Proc(h), Short(W.Title(h), 60), r.L, r.T, r.R - r.L, r.B - r.T));
            }
            return 0;
        }
        static IntPtr FindWindow(Opts o)
        {
            string wid = Get(o, "window");
            if (wid != null) { long v; if (long.TryParse(wid, out v) && W.IsWindow(new IntPtr(v))) return new IntPtr(v); return IntPtr.Zero; }
            string app = (Get(o, "app") ?? "").ToLowerInvariant().Replace(".exe", ""), ns = app.Replace(" ", "");
            string t = (Get(o, "title") ?? "").ToLowerInvariant();
            if (app.Length == 0) return IntPtr.Zero;
            IntPtr byTitle = IntPtr.Zero, loose = IntPtr.Zero;
            foreach (var h in TopWindows())
            {
                string title = W.Title(h).ToLowerInvariant(), p = W.Proc(h).ToLowerInvariant();
                if (t.Length > 0 && !title.Contains(t)) continue;
                if (p == app || p == ns) return h;
                if (loose == IntPtr.Zero && p.Contains(ns)) loose = h;
                if (byTitle == IntPtr.Zero && title.Contains(app)) byTitle = h;
            }
            return loose != IntPtr.Zero ? loose : byTitle;
        }

        // ---------- tree ----------
        static object Prop(IUIAutomationElement e, int id) { try { return e.GetCurrentPropertyValue(id); } catch (Exception) { return null; } }
        static string S(object v) { return v as string ?? ""; }
        static bool B(object v) { return v is bool && (bool)v; }

        static Item Describe(IUIAutomationElement e)
        {
            var it = new Item();
            object ct = Prop(e, P.ControlType); string tn;
            it.Type = ct is int && Types.TryGetValue((int)ct, out tn) ? tn : "Unknown";
            it.Name = S(Prop(e, P.Name)); it.Id = S(Prop(e, P.AutomationId));
            if (B(Prop(e, P.IsInvoke))) it.Pats.Add("invoke");
            if (B(Prop(e, P.IsValue))) it.Pats.Add("value");
            if (B(Prop(e, P.IsToggle))) it.Pats.Add("toggle");
            if (B(Prop(e, P.IsSelectionItem))) it.Pats.Add("select");
            if (B(Prop(e, P.IsExpandCollapse))) it.Pats.Add("expand");
            if (B(Prop(e, P.IsText))) it.Pats.Add("text");
            if (it.Pats.Contains("value")) it.Value = S(Prop(e, P.Value));
            var r = Prop(e, P.BoundingRectangle) as double[];
            if (r != null && r.Length == 4) { it.X = (int)r[0]; it.Y = (int)r[1]; it.Wd = (int)r[2]; it.Ht = (int)r[3]; }
            try { it.Rid = string.Join(".", e.GetRuntimeId()); } catch (Exception) { it.Rid = ""; }
            return it;
        }

        static List<KeyValuePair<Item, IUIAutomationElement>> Walk(IntPtr hwnd, int max, bool all)
        {
            var res = new List<KeyValuePair<Item, IUIAutomationElement>>();
            var win = uia.ElementFromHandle(hwnd);
            var arr = win.FindAll(TreeScope.Descendants, uia.ControlViewCondition);
            int n = 0;
            for (int i = 0; i < arr.Length && n < max; i++)
            {
                IUIAutomationElement e;
                try { e = arr.GetElement(i); } catch (Exception) { continue; }
                var it = Describe(e);
                if (!all)
                {
                    if (B(Prop(e, P.IsOffscreen)) && it.Pats.Count == 0) continue;
                    if (it.Name.Length == 0 && it.Pats.Count == 0) continue;
                }
                it.Ref = "e" + (++n);
                res.Add(new KeyValuePair<Item, IUIAutomationElement>(it, e));
            }
            return res;
        }

        static string Short(string s, int n)
        {
            if (string.IsNullOrEmpty(s)) return "";
            s = System.Text.RegularExpressions.Regex.Replace(s, @"\s+", " ");
            return s.Length > n ? s.Substring(0, n - 1) + "~" : s;
        }
        static string Line(Item x)
        {
            var sb = new StringBuilder(string.Format("{0,-5} {1,-12} \"{2}\"", x.Ref, x.Type, Short(x.Name, 50)));
            if (x.Id.Length > 0) sb.Append(" [id=" + x.Id + "]");
            if (!string.IsNullOrEmpty(x.Value)) sb.Append(" = \"" + Short(x.Value, 40) + "\"");
            sb.Append(string.Format(" @{0},{1} {2}x{3}", x.X, x.Y, x.Wd, x.Ht));
            if (x.Pats.Count > 0) sb.Append(" {" + string.Join(",", x.Pats) + "}");
            return sb.ToString();
        }
        static string Clean(string s) { return (s ?? "").Replace("\t", " ").Replace("\r", " ").Replace("\n", " "); }

        static int Ui(string cmd, Opts o)
        {
            IntPtr h = FindWindow(o);
            if (h == IntPtr.Zero) return Fail(Get(o, "app") == null && Get(o, "window") == null ? "name the target: --app APP [--title T] or --window HWND" : "no visible window for that target (open it first)");
            int max = 300; string m = Get(o, "max"); if (m != null) int.TryParse(m, out max);
            var items = Walk(h, cmd == "find" ? 5000 : max, Get(o, "all") != null);
            if (cmd == "find")
            {
                string name = Get(o, "name"), type = Get(o, "type"), id = Get(o, "id");
                items = items.FindAll(delegate(KeyValuePair<Item, IUIAutomationElement> kv)
                {
                    var x = kv.Key;
                    if (name != null && x.Name.IndexOf(name, StringComparison.OrdinalIgnoreCase) < 0) return false;
                    if (type != null && !string.Equals(x.Type, type, StringComparison.OrdinalIgnoreCase)) return false;
                    if (id != null && x.Id != id) return false;
                    return true;
                });
                for (int i = 0; i < items.Count; i++) items[i].Key.Ref = "e" + (i + 1);
            }
            var sb = new StringBuilder(h.ToInt64() + "\n");
            foreach (var kv in items) { var x = kv.Key; sb.Append(x.Ref + "\t" + x.Rid + "\t" + x.Type + "\t" + Clean(x.Id) + "\t" + Clean(x.Name) + "\n"); }
            File.WriteAllText(RefsF, sb.ToString(), Utf8);
            Console.WriteLine("window " + h.ToInt64() + " \"" + W.Title(h) + "\" - " + items.Count + " elements");
            foreach (var kv in items) Console.WriteLine(Line(kv.Key));
            return 0;
        }

        // ---------- refs ----------
        class Target { public IUIAutomationElement El; public IntPtr Hwnd; public string Ref, Type, Name; }
        static Target Resolve(string r)
        {
            if (r == null) { Console.WriteLine("give an element ref, e.g. e12 (from: claude-control ui --app APP)"); return null; }
            if (!File.Exists(RefsF)) { Console.WriteLine("no refs yet: run  claude-control ui --app APP  first"); return null; }
            var lines = File.ReadAllLines(RefsF, Utf8);
            long hv; long.TryParse(lines[0], out hv); var hwnd = new IntPtr(hv);
            if (!W.IsWindow(hwnd)) { Console.WriteLine("that window is gone (run ui again)"); return null; }
            string[] f = null;
            for (int i = 1; i < lines.Length; i++) { var p = lines[i].Split('\t'); if (p.Length >= 5 && p[0] == r) { f = p; break; } }
            if (f == null) { Console.WriteLine("unknown ref " + r + " (run ui again)"); return null; }
            var arr = uia.ElementFromHandle(hwnd).FindAll(TreeScope.Descendants, uia.ControlViewCondition);
            IUIAutomationElement byRid = null, byId = null, byName = null;
            for (int i = 0; i < arr.Length; i++)
            {
                var e = arr.GetElement(i);
                string rid = ""; try { rid = string.Join(".", e.GetRuntimeId()); } catch (Exception) { }
                if (rid.Length > 0 && rid == f[1]) { byRid = e; break; }
                if (byId == null && f[3].Length > 0 && S(Prop(e, P.AutomationId)) == f[3]) byId = e;
                if (byName == null && f[4].Length > 0 && S(Prop(e, P.Name)) == f[4]) byName = e;
            }
            var el = byRid ?? byId ?? byName;
            if (el == null) { Console.WriteLine(r + " is stale (the UI changed): run ui again"); return null; }
            return new Target { El = el, Hwnd = hwnd, Ref = r, Type = f[2], Name = f[4] };
        }

        static T Pattern<T>(IUIAutomationElement e, int id) where T : class
        {
            try { return e.GetCurrentPattern(id) as T; } catch (Exception) { return null; }
        }

        // ---------- Claude Cursor (only if running) ----------
        static bool CursorOn()
        {
            string pf = Path.Combine(Dir, "pid");
            if (!File.Exists(pf)) return false;
            int pid; if (!int.TryParse(File.ReadAllText(pf).Trim(), out pid)) return false;
            try { return Process.GetProcessById(pid).ProcessName == "claude-ghost"; } catch (Exception) { return false; }
        }
        static void CursorState(int x, int y, string label, bool click, long wid)
        {
            File.WriteAllText(Path.Combine(Dir, "label"), label, Utf8);
            File.WriteAllText(Path.Combine(Dir, "last"), x + " " + y, Utf8);
            string state = Path.Combine(Dir, "state.txt");
            File.WriteAllText(state + ".tmp", x + "|" + y + "|" + label.Replace("|", "") + "|" + (click ? 1 : 0) + "|" + Guid.NewGuid().ToString("N") + "|" + wid + "\n", Utf8);
            if (File.Exists(state)) File.Delete(state);
            File.Move(state + ".tmp", state);
        }
        static void Point(Target t, string verb, bool click)
        {
            if (!CursorOn()) return;
            long wid = t.Hwnd.ToInt64();
            string wf = Path.Combine(Dir, "wid");
            string cur = File.Exists(wf) ? File.ReadAllText(wf).Trim() : "0";
            if (cur != wid.ToString())
            {
                File.WriteAllText(wf, wid.ToString(), Utf8);
                var fr = W.Frame(t.Hwnd);
                File.WriteAllText(Path.Combine(Dir, "rect"), fr.L + " " + fr.T + " " + (fr.R - fr.L) + " " + (fr.B - fr.T), Utf8);
            }
            var r = Prop(t.El, P.BoundingRectangle) as double[];
            if (r == null || r.Length != 4) return;
            int x = (int)(r[0] + r[2] / 2), y = (int)(r[1] + r[3] / 2);
            CursorState(x, y, "Claude " + Dot + " " + verb, click, wid);
            System.Threading.Thread.Sleep(click ? 500 : 420);
        }
        static void Rest(Target t)
        {
            if (!CursorOn()) return;
            string lf = Path.Combine(Dir, "last");
            int x = 400, y = 300;
            try { var p = File.ReadAllText(lf).Trim().Split(' '); x = int.Parse(p[0]); y = int.Parse(p[1]); } catch (Exception) { }
            CursorState(x, y, "Claude", false, t.Hwnd.ToInt64());
        }

        // ---------- actions ----------
        static int Click(Opts o)
        {
            var t = Resolve(o.Pos.Count > 0 ? o.Pos[0] : null); if (t == null) return 1;
            Point(t, "clicking", true);
            string done = null;
            var inv = Pattern<IUIAutomationInvokePattern>(t.El, P.PInvoke);
            if (inv != null) { inv.Invoke(); done = "invoked"; }
            else
            {
                var tg = Pattern<IUIAutomationTogglePattern>(t.El, P.PToggle);
                if (tg != null) { tg.Toggle(); done = "toggled"; }
                else
                {
                    var si = Pattern<IUIAutomationSelectionItemPattern>(t.El, P.PSelectionItem);
                    if (si != null) { si.Select(); done = "selected"; }
                    else
                    {
                        var ec = Pattern<IUIAutomationExpandCollapsePattern>(t.El, P.PExpandCollapse);
                        if (ec != null)
                        {
                            object st = Prop(t.El, P.ExpandCollapseState);
                            if (st is int && (int)st == 1) { ec.Collapse(); done = "collapsed"; } else { ec.Expand(); done = "expanded"; }
                        }
                    }
                }
            }
            Rest(t);
            if (done == null) return Fail(t.Ref + " has no clickable pattern (invoke/toggle/select/expand); it can't be clicked in the background");
            Console.WriteLine(done + " " + t.Ref + " " + t.Type + " \"" + t.Name + "\"");
            return 0;
        }

        static int TypeText(Opts o)
        {
            var t = Resolve(o.Pos.Count > 0 ? o.Pos[0] : null); if (t == null) return 1;
            string text = string.Join(" ", o.Pos.GetRange(1, Math.Max(0, o.Pos.Count - 1)).ToArray());
            var vp = Pattern<IUIAutomationValuePattern>(t.El, P.PValue);
            if (vp == null) return Fail(t.Ref + " is not an editable field (no ValuePattern)");
            if (B(Prop(t.El, P.ValueIsReadOnly))) return Fail(t.Ref + " is read-only");
            Point(t, "typing", false);
            string nv = Get(o, "append") != null ? S(Prop(t.El, P.Value)) + text : text;
            vp.SetValue(nv);
            Rest(t);
            Console.WriteLine("typed into " + t.Ref + ": \"" + Short(S(Prop(t.El, P.Value)), 80) + "\"");
            return 0;
        }

        static int Read(Opts o)
        {
            if (o.Pos.Count > 0)
            {
                var t = Resolve(o.Pos[0]); if (t == null) return 1;
                Point(t, "reading", false);
                string txt = null;
                var tp = Pattern<IUIAutomationTextPattern>(t.El, P.PText);
                if (tp != null) { try { txt = tp.DocumentRange.GetText(20000); } catch (Exception) { } }
                if (txt == null && B(Prop(t.El, P.IsValue))) txt = S(Prop(t.El, P.Value));
                if (txt == null) txt = S(Prop(t.El, P.Name));
                Rest(t);
                Console.WriteLine(txt);
                return 0;
            }
            IntPtr h = FindWindow(o);
            if (h == IntPtr.Zero) return Fail("give a ref, or a window: read --app APP");
            foreach (var kv in Walk(h, 600, false))
            {
                var x = kv.Key;
                if (!string.IsNullOrEmpty(x.Value)) Console.WriteLine(x.Type + " \"" + x.Name + "\": " + x.Value);
                else if (x.Name.Length > 0) Console.WriteLine(x.Type + ": " + x.Name);
            }
            return 0;
        }

        static int Focus(Opts o)
        {
            var t = Resolve(o.Pos.Count > 0 ? o.Pos[0] : null); if (t == null) return 1;
            Point(t, "focusing", false);
            t.El.SetFocus();
            Rest(t);
            Console.WriteLine("focused " + t.Ref + " (this can bring its window to the front)");
            return 0;
        }
    }
}
