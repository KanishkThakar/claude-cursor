// ghost.cs - Claude's own on-screen cursor for Windows (opt-in indicator), v3 "window-bound".
// Copyright (c) 2026 Kanishk Thakar. MIT License - https://github.com/KanishkThakar/claude-cursor
//
// The cursor lives INSIDE one target window. Its overlay is a per-pixel-alpha layered window with
// the target's exact frame, OWNED by the target, so Windows keeps it directly above that window
// only: other windows that cover the target cover the cursor too; it follows moves and resizes;
// it hides when the target is minimised, closed or on another virtual desktop.
//
// It never moves the system pointer, never takes focus (WS_EX_NOACTIVATE), is click-through
// (WS_EX_TRANSPARENT), has no taskbar button (WS_EX_TOOLWINDOW) and needs no special rights.
//
// Effects (GDI+, 60 fps while moving): spring glide with overshoot, tilt toward travel, comet
// trail, sparks, breathing glow, double ripple + spark burst + press squish on clicks, edge-aware
// label pill, fade in/out.
//
// State file line: "x|y|label|click|stamp|hwnd"   (x,y = global screen pixels, same as UI Automation
// BoundingRectangle; hwnd 0 = whole-screen mode, opt-in only).  "quit" fades out and exits.
// It also exits by itself after 20 minutes without updates.
//
// Build: %WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /optimize /target:winexe
//        /out:claude-ghost.exe /r:System.Drawing.dll /r:System.Windows.Forms.dll ghost.cs
// Run:   claude-ghost.exe <state-file> [x y [hwnd]]
//        claude-ghost.exe --find-window "App" ["title contains"]   -> "hwnd x y w h title"
//        claude-ghost.exe --window-info HWND                        -> "hwnd x y w h title"
// (C# 5 syntax on purpose, so the compiler built into Windows can build it.)

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

static class N
{
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; public POINT(int x, int y) { X = x; Y = y; } }
    [StructLayout(LayoutKind.Sequential)] public struct SIZE { public int W, H; public SIZE(int w, int h) { W = w; H = h; } }
    [StructLayout(LayoutKind.Sequential, Pack = 1)] public struct BLEND { public byte Op, Flags, Alpha, Format; }
    [StructLayout(LayoutKind.Sequential)]
    public struct BITMAPINFOHEADER
    {
        public int biSize, biWidth, biHeight; public short biPlanes, biBitCount;
        public int biCompression, biSizeImage, biXPelsPerMeter, biYPelsPerMeter, biClrUsed, biClrImportant;
    }
    public delegate bool EnumProc(IntPtr h, IntPtr l);

    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
    [DllImport("user32.dll", EntryPoint = "SetWindowLong")] static extern int SetWindowLong32(IntPtr h, int i, int v);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtr")] static extern IntPtr SetWindowLongPtr64(IntPtr h, int i, IntPtr v);
    public static void SetOwner(IntPtr h, IntPtr owner)
    {
        if (IntPtr.Size == 8) SetWindowLongPtr64(h, -8, owner); else SetWindowLong32(h, -8, owner.ToInt32());
    }
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int hh, uint f);
    [DllImport("user32.dll")] public static extern bool UpdateLayeredWindow(IntPtr h, IntPtr dst, ref POINT pt, ref SIZE sz, IntPtr src, ref POINT sp, int key, ref BLEND b, int flags);
    [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr h);
    [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr h, IntPtr dc);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
    [DllImport("gdi32.dll")] public static extern IntPtr CreateCompatibleDC(IntPtr dc);
    [DllImport("gdi32.dll")] public static extern bool DeleteDC(IntPtr dc);
    [DllImport("gdi32.dll")] public static extern IntPtr SelectObject(IntPtr dc, IntPtr o);
    [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr o);
    [DllImport("gdi32.dll")] public static extern IntPtr CreateDIBSection(IntPtr dc, ref BITMAPINFOHEADER bi, uint usage, out IntPtr bits, IntPtr sec, uint off);
    [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out RECT r, int size);
    [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int size);

    public static void DpiAware()
    {
        try { if (SetProcessDpiAwarenessContext(new IntPtr(-4))) return; } catch (Exception) { }
        try { SetProcessDPIAware(); } catch (Exception) { }
    }
    // Visible frame (without the invisible resize borders of Windows 10/11).
    public static bool Frame(IntPtr h, out RECT r)
    {
        try { if (DwmGetWindowAttribute(h, 9, out r, Marshal.SizeOf(typeof(RECT))) == 0) return true; } catch (Exception) { }
        return GetWindowRect(h, out r);
    }
    public static bool Cloaked(IntPtr h)
    {
        int v = 0;
        try { DwmGetWindowAttribute(h, 14, out v, 4); } catch (Exception) { }
        return v != 0;
    }
    public static string Title(IntPtr h)
    {
        var sb = new StringBuilder(512); GetWindowText(h, sb, 512); return sb.ToString();
    }
    public static string ProcName(IntPtr h)
    {
        int pid; GetWindowThreadProcessId(h, out pid);
        try { return Process.GetProcessById(pid).ProcessName; } catch (Exception) { return ""; }
    }
}

static class Program
{
    static string Info(IntPtr h)
    {
        N.RECT r; N.Frame(h, out r);
        return h.ToInt64() + " " + r.L + " " + r.T + " " + (r.R - r.L) + " " + (r.B - r.T) + " " + N.Title(h).Replace('\n', ' ');
    }

    static IntPtr Find(string app, string title)
    {
        string a = app.ToLowerInvariant().Replace(".exe", ""), aNoSpace = a.Replace(" ", "");
        string t = (title ?? "").ToLowerInvariant();
        IntPtr byProc = IntPtr.Zero, byTitle = IntPtr.Zero;
        N.EnumWindows(delegate(IntPtr h, IntPtr l)
        {
            if (!N.IsWindowVisible(h) || N.Cloaked(h)) return true;
            if ((N.GetWindowLong(h, -20) & 0x80) != 0) return true; // tool windows
            N.RECT r; if (!N.Frame(h, out r) || r.R - r.L < 80 || r.B - r.T < 60) return true;
            string name = N.Title(h); if (name.Length == 0) return true;
            string ln = name.ToLowerInvariant();
            if (t.Length > 0 && !ln.Contains(t)) return true;
            string p = N.ProcName(h).ToLowerInvariant();
            if (byProc == IntPtr.Zero && (p == a || p == aNoSpace || p.Contains(aNoSpace))) byProc = h;
            if (byTitle == IntPtr.Zero && ln.Contains(a)) byTitle = h; // e.g. Calculator (ApplicationFrameHost)
            return byProc == IntPtr.Zero;
        }, IntPtr.Zero);
        return byProc != IntPtr.Zero ? byProc : byTitle;
    }

    [STAThread]
    static int Main(string[] args)
    {
        N.DpiAware();
        if (args.Length > 1 && args[0] == "--find-window")
        {
            IntPtr h = Find(args[1], args.Length > 2 ? args[2] : "");
            if (h == IntPtr.Zero) { Console.Error.WriteLine("no visible window for \"" + args[1] + "\""); return 1; }
            Console.WriteLine(Info(h)); return 0;
        }
        if (args.Length > 1 && args[0] == "--window-info")
        {
            long v; if (!long.TryParse(args[1], out v) || !N.IsWindow(new IntPtr(v))) return 1;
            Console.WriteLine(Info(new IntPtr(v))); return 0;
        }
        string state = args.Length > 0 ? args[0] :
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "claude-ghost\\state.txt");
        float x = 400, y = 300; long wid = 0;
        if (args.Length > 2) { float.TryParse(args[1], out x); float.TryParse(args[2], out y); }
        if (args.Length > 3) long.TryParse(args[3], out wid);
        Application.EnableVisualStyles();
        Application.Run(new Ghost(state, x, y, new IntPtr(wid)));
        return 0;
    }
}

class Spark { public float X, Y, VX, VY, Life, Max, Size; }
class Ripple { public float X, Y, T; }

class Ghost : Form
{
    static readonly Color Accent = Color.FromArgb(217, 119, 87);
    static readonly Color Hot = Color.FromArgb(255, 168, 115);
    static readonly PointF[] Arrow = {
        new PointF(0, 0), new PointF(0, 17), new PointF(4.2f, 13.2f), new PointF(7, 19.5f),
        new PointF(9.6f, 18.4f), new PointF(6.9f, 12.3f), new PointF(12.2f, 12.3f) };

    readonly string statePath;
    IntPtr target;
    N.RECT rect;                 // overlay rect, global pixels
    bool shown;
    float cx, cy, vx, vy, tx, ty, angle;
    string label = "Claude";
    string lastStamp = "";
    bool pendingClick;
    float squishT = 99, fade = 0, time;
    bool quitting;
    DateTime lastUpdate = DateTime.Now, lastFileTime;
    readonly List<PointF> trail = new List<PointF>();
    readonly List<Spark> sparks = new List<Spark>();
    readonly List<Ripple> ripples = new List<Ripple>();
    readonly Random rnd = new Random();
    readonly Stopwatch clock = Stopwatch.StartNew();
    double lastTick, lastPoll, lastBind;
    readonly Timer timer = new Timer();

    IntPtr memDC, dib, oldObj, bits; Bitmap canvas; int cw, ch;

    public Ghost(string statePath, float x, float y, IntPtr wid)
    {
        this.statePath = statePath;
        cx = tx = x; cy = ty = y; target = wid;
        FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = false; StartPosition = FormStartPosition.Manual;
        Bounds = new Rectangle(-32000, -32000, 1, 1);
        timer.Interval = 15; timer.Tick += delegate { Tick(); }; timer.Start();
    }

    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams
    {
        get
        {
            var cp = base.CreateParams;
            cp.ExStyle |= 0x80000 | 0x20 | 0x8000000 | 0x80; // LAYERED | TRANSPARENT | NOACTIVATE | TOOLWINDOW
            return cp;
        }
    }
    protected override void OnHandleCreated(EventArgs e) { base.OnHandleCreated(e); Bind(); }

    void Bind()
    {
        if (target == IntPtr.Zero)
        {
            var v = SystemInformation.VirtualScreen;
            rect.L = v.Left; rect.T = v.Top; rect.R = v.Right; rect.B = v.Bottom;
            N.SetOwner(Handle, IntPtr.Zero); TopMost = true;
        }
        else { TopMost = false; N.SetOwner(Handle, target); }
    }

    void Poll()
    {
        try
        {
            if (!File.Exists(statePath)) return;
            var ft = File.GetLastWriteTimeUtc(statePath);
            if (ft == lastFileTime) return;
            lastFileTime = ft;
            string line;
            using (var fs = new FileStream(statePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            using (var sr = new StreamReader(fs, Encoding.UTF8)) line = (sr.ReadLine() ?? "").Trim();
            if (line == "quit") { quitting = true; return; }
            var p = line.Split('|');
            if (p.Length < 5 || p[4] == lastStamp) return;
            lastStamp = p[4]; lastUpdate = DateTime.Now;
            float.TryParse(p[0], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out tx);
            float.TryParse(p[1], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out ty);
            label = p[2].Length == 0 ? "Claude" : p[2];
            if (p[3] == "1") pendingClick = true;
            long w = 0; if (p.Length > 5) long.TryParse(p[5], out w);
            if (new IntPtr(w) != target) { target = new IntPtr(w); Bind(); }
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    bool TargetVisible()
    {
        if (target == IntPtr.Zero) return true;
        if (!N.IsWindow(target)) return false;
        if (!N.IsWindowVisible(target) || N.IsIconic(target) || N.Cloaked(target)) return false;
        N.RECT r; if (!N.Frame(target, out r)) return false;
        rect = r; return r.R - r.L > 10 && r.B - r.T > 10;
    }

    void Tick()
    {
        double now = clock.Elapsed.TotalSeconds;
        float dt = (float)Math.Min(0.05, now - lastTick); lastTick = now; time += dt;
        if (now - lastPoll > 0.04) { lastPoll = now; Poll(); }
        if (!quitting && (DateTime.Now - lastUpdate).TotalMinutes > 20) quitting = true;

        bool vis = true;
        if (now - lastBind > 0.08 || !shown) { lastBind = now; vis = TargetVisible(); if (!vis && target != IntPtr.Zero && !N.IsWindow(target)) quitting = true; }
        fade = quitting ? Math.Max(0, fade - dt * 4) : Math.Min(1, fade + dt * 4);
        if (quitting && fade <= 0) { timer.Stop(); Close(); return; }

        // Spring glide (critically under-damped: a little overshoot).
        float k = 210f, d = 19f;
        vx += ((tx - cx) * k - vx * d) * dt; vy += ((ty - cy) * k - vy * d) * dt;
        cx += vx * dt; cy += vy * dt;
        float speed = (float)Math.Sqrt(vx * vx + vy * vy);
        float wantAngle = Math.Max(-28, Math.Min(28, vx * 0.03f));
        angle += (wantAngle - angle) * Math.Min(1, dt * 12);
        trail.Add(new PointF(cx, cy)); while (trail.Count > 16) trail.RemoveAt(0);
        if (speed > 260 && rnd.NextDouble() < 0.6) Spawn(cx, cy, 1, 60, 0.45f);

        float dist = (float)Math.Sqrt((tx - cx) * (tx - cx) + (ty - cy) * (ty - cy));
        if (pendingClick && dist < 6)
        {
            pendingClick = false; squishT = 0;
            ripples.Add(new Ripple { X = tx, Y = ty, T = 0 }); ripples.Add(new Ripple { X = tx, Y = ty, T = -0.14f });
            Spawn(tx, ty, 16, 220, 0.6f);
        }
        squishT += dt;
        for (int i = ripples.Count - 1; i >= 0; i--) { ripples[i].T += dt; if (ripples[i].T > 0.7f) ripples.RemoveAt(i); }
        for (int i = sparks.Count - 1; i >= 0; i--)
        {
            var s = sparks[i]; s.Life += dt; s.X += s.VX * dt; s.Y += s.VY * dt; s.VY += 220 * dt; s.VX *= 0.97f;
            if (s.Life > s.Max) sparks.RemoveAt(i);
        }

        if (!vis) { if (shown) { Hide(); shown = false; } return; }
        if (!shown) { Show(); shown = true; Bind(); }
        Render();
    }

    void Spawn(float x, float y, int n, float v, float life)
    {
        for (int i = 0; i < n; i++)
        {
            double a = rnd.NextDouble() * Math.PI * 2; float sp = (float)(v * (0.35 + rnd.NextDouble() * 0.65));
            sparks.Add(new Spark { X = x, Y = y, VX = (float)Math.Cos(a) * sp, VY = (float)Math.Sin(a) * sp - 40,
                Max = life * (float)(0.6 + rnd.NextDouble() * 0.4), Size = (float)(1.5 + rnd.NextDouble() * 2.5) });
        }
    }

    void EnsureCanvas(int w, int h)
    {
        if (canvas != null && w == cw && h == ch) return;
        FreeCanvas();
        cw = w; ch = h;
        var bi = new N.BITMAPINFOHEADER { biSize = Marshal.SizeOf(typeof(N.BITMAPINFOHEADER)), biWidth = w, biHeight = -h, biPlanes = 1, biBitCount = 32 };
        IntPtr screen = N.GetDC(IntPtr.Zero);
        memDC = N.CreateCompatibleDC(screen);
        dib = N.CreateDIBSection(screen, ref bi, 0, out bits, IntPtr.Zero, 0);
        N.ReleaseDC(IntPtr.Zero, screen);
        oldObj = N.SelectObject(memDC, dib);
        canvas = new Bitmap(w, h, w * 4, PixelFormat.Format32bppPArgb, bits);
    }
    void FreeCanvas()
    {
        if (canvas != null) { canvas.Dispose(); canvas = null; }
        if (memDC != IntPtr.Zero) { N.SelectObject(memDC, oldObj); N.DeleteObject(dib); N.DeleteDC(memDC); memDC = IntPtr.Zero; }
    }

    void Render()
    {
        int w = Math.Max(1, rect.R - rect.L), h = Math.Max(1, rect.B - rect.T);
        EnsureCanvas(w, h);
        float ox = rect.L, oy = rect.T, a = fade;
        using (var g = Graphics.FromImage(canvas))
        {
            g.Clear(Color.Transparent);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
            g.TranslateTransform(-ox, -oy);

            // Comet trail
            for (int i = 1; i < trail.Count; i++)
            {
                float f = (float)i / trail.Count;
                using (var pen = new Pen(Color.FromArgb((int)(150 * f * f * a), Hot), 1 + 7 * f))
                { pen.StartCap = pen.EndCap = LineCap.Round; g.DrawLine(pen, trail[i - 1], trail[i]); }
            }
            // Ripples
            foreach (var r in ripples)
            {
                if (r.T < 0) continue;
                float p = r.T / 0.7f, rad = 6 + 46 * (float)(1 - Math.Pow(1 - p, 3));
                using (var pen = new Pen(Color.FromArgb((int)(230 * (1 - p) * a), Accent), 3.5f * (1 - p) + 1))
                    g.DrawEllipse(pen, r.X - rad, r.Y - rad, rad * 2, rad * 2);
            }
            // Sparks
            foreach (var s in sparks)
            {
                float p = 1 - s.Life / s.Max;
                using (var b = new SolidBrush(Color.FromArgb((int)(255 * p * a), p > 0.5f ? Color.White : Hot)))
                    g.FillEllipse(b, s.X - s.Size * p, s.Y - s.Size * p, s.Size * 2 * p, s.Size * 2 * p);
            }

            // Breathing glow
            float breathe = 0.5f + 0.5f * (float)Math.Sin(time * 2.4);
            float gr = 24 + 6 * breathe;
            using (var path = new GraphicsPath())
            {
                path.AddEllipse(cx + 4 - gr, cy + 8 - gr, gr * 2, gr * 2);
                using (var pb = new PathGradientBrush(path))
                {
                    pb.CenterColor = Color.FromArgb((int)((70 + 40 * breathe) * a), Accent);
                    pb.SurroundColors = new[] { Color.FromArgb(0, Accent) };
                    g.FillPath(pb, path);
                }
            }

            // Arrow (tilt + press squish)
            float sq = 1;
            if (squishT < 0.22f) sq = 1 - 0.2f * (float)Math.Sin(Math.PI * squishT / 0.22f);
            var st = g.Save();
            g.TranslateTransform(cx, cy); g.RotateTransform(angle); g.ScaleTransform(1.45f * sq, 1.45f * sq);
            using (var path = new GraphicsPath())
            {
                path.AddPolygon(Arrow);
                var shadow = g.Save(); g.TranslateTransform(0.8f, 1.2f);
                using (var b = new SolidBrush(Color.FromArgb((int)(70 * a), 0, 0, 0))) g.FillPath(b, path);
                g.Restore(shadow);
                using (var b = new LinearGradientBrush(new PointF(0, 0), new PointF(8, 20), Color.FromArgb((int)(255 * a), Hot), Color.FromArgb((int)(255 * a), Accent)))
                    g.FillPath(b, path);
                using (var pen = new Pen(Color.FromArgb((int)(255 * a), Color.White), 1.3f)) { pen.LineJoin = LineJoin.Round; g.DrawPath(pen, path); }
            }
            g.Restore(st);

            // Label pill, flipped to stay inside the window
            using (var font = new Font("Segoe UI Semibold", 9.5f, FontStyle.Regular, GraphicsUnit.Point))
            {
                var sz = g.MeasureString(label, font);
                float pw = sz.Width + 16, ph = sz.Height + 6;
                float lx = cx + 20, ly = cy + 26;
                if (lx + pw > rect.R - 4) lx = cx - 8 - pw;
                if (ly + ph > rect.B - 4) ly = cy - 8 - ph;
                lx = Math.Max(rect.L + 4, lx); ly = Math.Max(rect.T + 4, ly);
                using (var pill = Rounded(lx, ly, pw, ph, ph / 2))
                {
                    using (var b = new SolidBrush(Color.FromArgb((int)(240 * a), Accent))) g.FillPath(b, pill);
                    using (var pen = new Pen(Color.FromArgb((int)(120 * a), Color.White), 1)) g.DrawPath(pen, pill);
                }
                using (var b = new SolidBrush(Color.FromArgb((int)(255 * a), Color.White))) g.DrawString(label, font, b, lx + 8, ly + 3);
            }
        }

        var dst = new N.POINT(rect.L, rect.T); var size = new N.SIZE(w, h); var src = new N.POINT(0, 0);
        var blend = new N.BLEND { Op = 0, Flags = 0, Alpha = 255, Format = 1 };
        N.UpdateLayeredWindow(Handle, IntPtr.Zero, ref dst, ref size, memDC, ref src, 0, ref blend, 2);
    }

    static GraphicsPath Rounded(float x, float y, float w, float h, float r)
    {
        var p = new GraphicsPath(); float d = r * 2;
        p.AddArc(x, y, d, d, 180, 90); p.AddArc(x + w - d, y, d, d, 270, 90);
        p.AddArc(x + w - d, y + h - d, d, d, 0, 90); p.AddArc(x, y + h - d, d, d, 90, 90);
        p.CloseFigure(); return p;
    }

    protected override void Dispose(bool disposing) { FreeCanvas(); base.Dispose(disposing); }
}
