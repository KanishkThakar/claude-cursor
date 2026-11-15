// ghost.swift - Claude's own on-screen cursor for macOS (opt-in indicator), v3 "window-bound".
// Copyright (c) 2026 Kanishk Thakar. MIT License - https://github.com/KanishkThakar/claude-cursor
//
// The cursor lives INSIDE one target window (the app Claude is working in), not over the whole
// screen. Its overlay panel has the target window's exact frame, is clipped to it, and is ordered
// directly above that window only: when another window covers the target, it covers the cursor
// too; when the target moves or resizes, the cursor follows; when the target is minimised, closed
// or on another Space, the cursor is hidden. It works while the target app is in the background.
//
// It never moves the system pointer, never takes keyboard focus, is click-through, has no Dock
// icon and needs no Accessibility permission. It is only an indicator: real actions go through
// the Mac's background controller (AX actions), never through this window.
//
// Effects (Core Animation): spring glide with slight overshoot, tilt toward travel, comet trail,
// sparks while moving, breathing glow, double ripple + spark burst + press squish on clicks,
// edge-aware label, fade in/out.
//
// State file line: "x|y|label|click|stamp|wid"
//   x,y  = global top-left points (same space as AX AXPosition and CGWindow bounds)
//   click= 1 shows the click effect;  wid = target CGWindowID (0 = whole-screen mode, opt-in only)
//   "quit" fades out and exits. It also exits by itself after 20 minutes without updates.
//
// Build:  swiftc -O -o claude-ghost ghost.swift -framework AppKit -framework QuartzCore
// Run:    ./claude-ghost <state-file> [x y [wid]]         (normally via claude-cursor.sh)
//         ./claude-ghost --find-window "App name" ["title contains"]
//              prints "wid x y w h title" for the frontmost on-screen matching window.

import AppKit
import QuartzCore

let args = CommandLine.arguments

// ---------- window lookup helper (no UI) ----------
func windowInfo(_ wid: CGWindowID) -> [String: Any]? {
    (CGWindowListCopyWindowInfo([.optionIncludingWindow], wid) as? [[String: Any]])?.first
}
func bounds(of info: [String: Any]) -> CGRect? {
    guard let b = info[kCGWindowBounds as String] as? [String: Any] else { return nil }
    return CGRect(dictionaryRepresentation: b as CFDictionary)
}

if args.count > 2 && args[1] == "--window-info" {
    guard let w = UInt32(args[2]), let info = windowInfo(w), let b = bounds(of: info) else { exit(1) }
    let owner = info[kCGWindowOwnerName as String] as? String ?? "window"
    print("\(w) \(Int(b.minX)) \(Int(b.minY)) \(Int(b.width)) \(Int(b.height)) \(owner)")
    exit(0)
}

if args.count > 2 && args[1] == "--find-window" {
    let app = args[2].lowercased()
    let title = args.count > 3 ? args[3].lowercased() : ""
    // Prefer on-screen windows (front-to-back), then windows on other Spaces / behind full-screen apps.
    let onScreen = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    let all = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    for w in onScreen + all {
        let owner = (w[kCGWindowOwnerName as String] as? String ?? "").lowercased()
        let name = w[kCGWindowName as String] as? String ?? ""
        let layer = w[kCGWindowLayer as String] as? Int ?? 0
        guard owner == app || owner.contains(app), layer == 0, let b = bounds(of: w),
              b.width > 80, b.height > 80 else { continue }
        if !title.isEmpty && !name.lowercased().contains(title) { continue }
        let wid = w[kCGWindowNumber as String] as? Int ?? 0
        print("\(wid) \(Int(b.minX)) \(Int(b.minY)) \(Int(b.width)) \(Int(b.height)) \(name)")
        exit(0)
    }
    FileHandle.standardError.write("no on-screen window for \"\(args[2])\"\(title.isEmpty ? "" : " titled *\(args[3])*")\n".data(using: .utf8)!)
    exit(1)
}

let statePath = args.count > 1 ? args[1] : NSHomeDirectory() + "/Library/Caches/claude-ghost/state.txt"

let accent = CGColor(srgbRed: 217.0 / 255, green: 119.0 / 255, blue: 87.0 / 255, alpha: 1)
let accentHot = CGColor(srgbRed: 1.0, green: 0.66, blue: 0.45, alpha: 1)
let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }
// Global top-left rect -> AppKit bottom-left rect.
func appKitRect(_ r: CGRect) -> NSRect { NSRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height) }

let arrowPath: CGPath = {
    let k: CGFloat = 1.2
    let pts: [(CGFloat, CGFloat)] = [(0, 0), (0, 24), (6, 18), (11, 28), (15, 26), (10, 16), (18, 16)]
    let p = CGMutablePath()
    p.move(to: CGPoint(x: pts[0].0 * k, y: -pts[0].1 * k))
    for q in pts.dropFirst() { p.addLine(to: CGPoint(x: q.0 * k, y: -q.1 * k)) }
    p.closeSubpath()
    return p
}()

let sparkImage: CGImage = {
    let s = 32
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let g = CGGradient(colorsSpace: cs, colors: [white, accentHot, accentHot.copy(alpha: 0)!] as CFArray, locations: [0, 0.35, 1])!
    let c = CGPoint(x: s / 2, y: s / 2)
    ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(s) / 2, options: [])
    return ctx.makeImage()!
}()

final class Overlay {
    let panel: NSPanel
    let root = CALayer()
    let trailGlow = CAShapeLayer()
    let trail = CAShapeLayer()
    let sparks = CAEmitterLayer()
    let cursor = CALayer()
    let glow = CAShapeLayer()
    let arrow = CAShapeLayer()
    let pill = CAShapeLayer()
    let text = CATextLayer()
    var frameTL: CGRect           // this overlay's frame in global top-left coordinates
    var labelKey = ""

    init(frameTL: CGRect, scale: CGFloat, bound: Bool) {
        self.frameTL = frameTL
        panel = NSPanel(contentRect: appKitRect(frameTL), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.setFrame(appKitRect(frameTL), display: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true                       // clicks pass straight through
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        if bound {
            // Lives in the target window's stack. It may exist on every Space so it can follow the
            // target wherever it is, but it is hidden whenever the target is not on screen.
            panel.level = .normal
            panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        } else {
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        }

        let view = NSView(frame: NSRect(origin: .zero, size: frameTL.size))
        view.autoresizingMask = [.width, .height]
        root.frame = view.bounds
        root.contentsScale = scale
        root.masksToBounds = true                             // never draw outside the target
        view.layer = root
        view.wantsLayer = true
        panel.contentView = view

        for t in [trailGlow, trail] { t.fillColor = nil; t.lineCap = .round; t.lineJoin = .round; root.addSublayer(t) }
        trailGlow.strokeColor = accent.copy(alpha: 0.22); trailGlow.lineWidth = 10
        trail.strokeColor = accentHot.copy(alpha: 0.75); trail.lineWidth = 2.5

        let cell = CAEmitterCell()
        cell.contents = sparkImage
        cell.birthRate = 90; cell.lifetime = 0.55; cell.lifetimeRange = 0.25
        cell.velocity = 55; cell.velocityRange = 45; cell.emissionRange = .pi * 2
        cell.scale = 0.32; cell.scaleRange = 0.15; cell.scaleSpeed = -0.45; cell.alphaSpeed = -1.7
        cell.spin = 2; cell.spinRange = 4
        sparks.emitterCells = [cell]; sparks.emitterShape = .point; sparks.renderMode = .additive; sparks.birthRate = 0
        root.addSublayer(sparks)

        glow.path = arrowPath; glow.fillColor = accent; glow.shadowColor = accent
        glow.shadowOffset = .zero; glow.shadowRadius = 12; glow.shadowOpacity = 0.9
        let breathe = CABasicAnimation(keyPath: "shadowRadius")
        breathe.fromValue = 7; breathe.toValue = 18; breathe.duration = 1.1
        breathe.autoreverses = true; breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glow.add(breathe, forKey: "breathe")

        arrow.path = arrowPath; arrow.fillColor = accent; arrow.strokeColor = white
        arrow.lineWidth = 2; arrow.lineJoin = .round

        pill.fillColor = accent; pill.strokeColor = white; pill.lineWidth = 1.2
        pill.shadowColor = CGColor(gray: 0, alpha: 1); pill.shadowOpacity = 0.35
        pill.shadowRadius = 4; pill.shadowOffset = CGSize(width: 0, height: -1)

        text.font = NSFont.boldSystemFont(ofSize: 12); text.fontSize = 12
        text.foregroundColor = white; text.alignmentMode = .left

        for l in [glow, arrow, pill, text] as [CALayer] { l.contentsScale = scale; cursor.addSublayer(l) }
        root.addSublayer(cursor)
        root.opacity = 0
    }

    func setFrame(_ r: CGRect) {
        // Compare with the panel's real frame too: Space switches can shift it behind our back.
        guard r != frameTL || panel.frame != appKitRect(r) else { return }
        frameTL = r
        panel.setFrame(appKitRect(r), display: false)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        root.frame = CGRect(origin: .zero, size: r.size)
        CATransaction.commit()
    }

    // Global top-left point -> local bottom-left layer point.
    func local(_ g: CGPoint) -> CGPoint { CGPoint(x: g.x - frameTL.minX, y: frameTL.maxY - g.y) }

    func setLabel(_ s: String, tip p: CGPoint) {
        let size = (s as NSString).size(withAttributes: [.font: NSFont.boldSystemFont(ofSize: 12)])
        let w = ceil(size.width) + 14, h = ceil(size.height) + 5
        let left = p.x + 26 + w > frameTL.width - 4
        let up = p.y - 34 - h < 2
        let key = "\(s)|\(left)|\(up)"
        if key == labelKey { return }
        labelKey = key
        let x: CGFloat = left ? -(w + 8) : 24
        let y: CGFloat = up ? 6 : -30 - h
        let r = CGRect(x: x, y: y, width: w, height: h)
        pill.path = CGPath(roundedRect: r, cornerWidth: h / 2, cornerHeight: h / 2, transform: nil)
        text.string = s
        text.frame = CGRect(x: r.minX + 7, y: r.minY + 2, width: w - 10, height: h - 3)
    }

    func update(tip g: CGPoint, angle: CGFloat, scale: CGFloat, label: String,
                trailPts: [CGPoint], speed: CGFloat, burst: Bool) {
        let p = local(g)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        cursor.position = p
        cursor.transform = CATransform3DScale(CATransform3DMakeRotation(angle, 0, 0, 1), scale, scale, 1)
        setLabel(label, tip: p)
        let path = CGMutablePath()
        if trailPts.count > 1 { path.addLines(between: trailPts.map(local)) }
        trail.path = path; trailGlow.path = path
        sparks.emitterPosition = CGPoint(x: p.x + 4, y: p.y - 6)
        let rate: Float = burst ? 8 : (speed > 3 ? min(Float(speed) / 18, 1.6) : 0)
        if rate > 0 && sparks.birthRate == 0 { sparks.beginTime = CACurrentMediaTime() }
        sparks.birthRate = rate
        CATransaction.commit()
    }

    func ripple(at g: CGPoint) {
        let p = local(g)
        guard root.bounds.insetBy(dx: -60, dy: -60).contains(p) else { return }
        func ring(_ delay: CFTimeInterval, _ width: CGFloat, _ color: CGColor, _ filled: Bool, _ maxScale: CGFloat) {
            let r: CGFloat = 26
            let l = CAShapeLayer()
            l.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2), transform: nil)
            l.position = p
            l.fillColor = filled ? color : nil
            l.strokeColor = filled ? nil : color
            l.lineWidth = width
            l.opacity = 0
            root.insertSublayer(l, below: cursor)
            let s = CABasicAnimation(keyPath: "transform.scale"); s.fromValue = 0.15; s.toValue = maxScale
            let o = CAKeyframeAnimation(keyPath: "opacity"); o.values = [0.0, 1.0, 0.0]; o.keyTimes = [0, 0.15, 1]
            let grp = CAAnimationGroup()
            grp.animations = [s, o]; grp.duration = 0.6
            grp.beginTime = CACurrentMediaTime() + delay
            grp.timingFunction = CAMediaTimingFunction(controlPoints: 0.1, 0.8, 0.3, 1)
            grp.fillMode = .both; grp.isRemovedOnCompletion = false
            l.add(grp, forKey: "ripple")
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.7) { l.removeFromSuperlayer() }
        }
        ring(0, 0, accentHot.copy(alpha: 0.45)!, true, 0.9)
        ring(0, 3.5, accent, false, 1.5)
        ring(0.12, 2, accentHot, false, 2.1)
    }

    func fade(to v: Float, duration: CFTimeInterval) {
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = root.presentation()?.opacity ?? root.opacity
        a.toValue = v; a.duration = duration
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        root.opacity = v
        root.add(a, forKey: "fade")
    }

    func close() { panel.orderOut(nil) }
}

final class Ghost: NSObject {
    var overlays: [Overlay] = []
    var wid: CGWindowID = 0          // 0 = whole-screen mode
    var targetVisible = false
    var cur: CGPoint
    var vel = CGPoint.zero
    var target: CGPoint
    var label = "Claude"
    var trailPts: [CGPoint] = []
    var squish: CGFloat = 1
    var angle: CGFloat = 0
    var burstFrames = 0
    var pendingClick = false
    var frameCount = 0
    var lastMod: Date?
    var lastUpdate = Date()
    var quitting = false
    var timer: Timer?

    init(start: CGPoint, wid: CGWindowID) {
        cur = start; target = start
        super.init()
        rebind(wid)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func scale(for r: CGRect) -> CGFloat {
        let ak = appKitRect(r)
        return (NSScreen.screens.first { $0.frame.intersects(ak) } ?? NSScreen.main)?.backingScaleFactor ?? 2
    }

    func rebind(_ newWid: CGWindowID) {
        overlays.forEach { $0.close() }
        overlays = []
        wid = newWid
        targetVisible = false
        if wid == 0 {
            for s in NSScreen.screens {
                let tl = CGRect(x: s.frame.minX, y: primaryHeight - s.frame.maxY, width: s.frame.width, height: s.frame.height)
                let o = Overlay(frameTL: tl, scale: s.backingScaleFactor, bound: false)
                overlays.append(o)
                o.panel.orderFrontRegardless(); o.fade(to: 1, duration: 0.35)
            }
        } else {
            let r = windowInfo(wid).flatMap(bounds(of:)) ?? CGRect(x: 0, y: 0, width: 400, height: 300)
            overlays = [Overlay(frameTL: r, scale: scale(for: r), bound: true)]
            trackTarget(force: true)
        }
    }

    // Keep the bound overlay glued to the target window: same frame, ordered right above it,
    // hidden whenever the target is not on screen.
    func trackTarget(force: Bool = false) {
        guard wid != 0, let o = overlays.first else { return }
        guard let info = windowInfo(wid), let r = bounds(of: info) else {
            if targetVisible { o.panel.orderOut(nil); targetVisible = false }
            return
        }
        let onScreen = (info[kCGWindowIsOnscreen as String] as? Bool) ?? false
        if !onScreen {
            if targetVisible { o.panel.orderOut(nil); targetVisible = false }
            return
        }
        o.setFrame(r)
        let layer = info[kCGWindowLayer as String] as? Int ?? 0
        if o.panel.level.rawValue != layer { o.panel.level = NSWindow.Level(rawValue: layer) }
        if !targetVisible || force || !isDirectlyAbove(o) {
            o.panel.order(.above, relativeTo: Int(wid))
            if !targetVisible { targetVisible = true; o.fade(to: 1, duration: 0.3) }
        }
    }

    func isDirectlyAbove(_ o: Overlay) -> Bool {
        let above = CGWindowListCopyWindowInfo([.optionOnScreenAboveWindow], wid) as? [[String: Any]] ?? []
        // The list is front-to-back; the window immediately above the target is the last entry.
        return (above.last?[kCGWindowNumber as String] as? Int) == o.panel.windowNumber
    }

    @objc func screensChanged() { rebind(wid) }

    func quit() {
        guard !quitting else { return }
        quitting = true
        overlays.forEach { $0.fade(to: 0, duration: 0.3) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { NSApp.terminate(nil) }
    }

    func readState() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: statePath),
              let mod = attrs[.modificationDate] as? Date, mod != lastMod,
              let raw = try? String(contentsOfFile: statePath, encoding: .utf8) else { return }
        lastMod = mod
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if line == "quit" { quit(); return }
        let p = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard p.count >= 4, let x = Double(p[0]), let y = Double(p[1]) else { return }
        if p.count >= 6, let w = UInt32(p[5]), w != wid {
            rebind(w)
            cur = CGPoint(x: x, y: y); vel = .zero; trailPts = []   // jump into the new window
        }
        target = CGPoint(x: x, y: y)
        label = p[2].isEmpty ? "Claude" : p[2]
        if p[3] == "1" { pendingClick = true }
        lastUpdate = Date()
    }

    func tick() {
        frameCount += 1
        if !quitting { readState() }
        if !quitting && Date().timeIntervalSince(lastUpdate) > 20 * 60 { quit() }
        if frameCount % 6 == 0 { trackTarget() }       // ~10 checks per second

        let k: CGFloat = 0.16, damping: CGFloat = 0.70
        vel.x = (vel.x + (target.x - cur.x) * k) * damping
        vel.y = (vel.y + (target.y - cur.y) * k) * damping
        cur.x += vel.x; cur.y += vel.y
        let dist = hypot(target.x - cur.x, target.y - cur.y)
        let speed = hypot(vel.x, vel.y)
        if dist < 0.4 && speed < 0.4 { cur = target; vel = .zero }

        if pendingClick && dist < 6 {
            pendingClick = false
            squish = 0.72
            burstFrames = 5
            overlays.forEach { $0.ripple(at: target) }
        }
        squish += (1 - squish) * 0.18
        let wantAngle = max(-0.45, min(0.45, -vel.x * 0.012))
        angle += (wantAngle - angle) * 0.25

        trailPts.append(cur)
        if trailPts.count > 16 { trailPts.removeFirst(trailPts.count - 16) }
        if speed < 0.5 && trailPts.count > 1 { trailPts.removeFirst(min(2, trailPts.count - 1)) }

        let burst = burstFrames > 0
        if burstFrames > 0 { burstFrames -= 1 }
        for o in overlays {
            o.update(tip: cur, angle: angle, scale: squish, label: label, trailPts: trailPts, speed: speed, burst: burst)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)                          // no Dock icon, never becomes active
var startPoint = CGPoint(x: 400, y: 300)
if args.count > 3, let x = Double(args[2]), let y = Double(args[3]) { startPoint = CGPoint(x: x, y: y) }
let startWid: CGWindowID = args.count > 4 ? (UInt32(args[4]) ?? 0) : 0
let ghost = Ghost(start: startPoint, wid: startWid)
app.run()
