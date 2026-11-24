// winrec.swift - record ONLY the given windows (target + Claude Cursor overlay) with ScreenCaptureKit.
// Other apps are excluded, so nothing else on the screen can appear, and the target can stay in the background.
// usage: swift winrec.swift <out.mov> <seconds> <x> <y> <w> <h> <windowID>...
import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia

let a = CommandLine.arguments
let out = URL(fileURLWithPath: a[1]); let secs = Double(a[2])!
let rect = CGRect(x: Double(a[3])!, y: Double(a[4])!, width: Double(a[5])!, height: Double(a[6])!)
let ids = Set(a[7...].compactMap { UInt32($0) })

final class Rec: NSObject, SCStreamOutput {
    let writer: AVAssetWriter; let input: AVAssetWriterInput; var started = false
    init(url: URL, w: Int, h: Int) throws {
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
    }
    func stream(_ s: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sb.isValid,
              let att = (CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first,
              let st = att[.status] as? Int, st == SCFrameStatus.complete.rawValue else { return }
        if !started { writer.startWriting(); writer.startSession(atSourceTime: sb.presentationTimeStamp); started = true }
        if input.isReadyForMoreMediaData { input.append(sb) }
    }
}

let sem = DispatchSemaphore(value: 0)
Task {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let wins = content.windows.filter { ids.contains($0.windowID) || ($0.owningApplication?.applicationName ?? "").contains("claude-ghost") }
        guard !wins.isEmpty, let display = content.displays.first else { print("windows not found"); exit(1) }
        print("capturing:", wins.map { "\($0.windowID) \($0.owningApplication?.applicationName ?? "?")" })
        let filter = SCContentFilter(display: display, including: wins)
        let cfg = SCStreamConfiguration()
        cfg.sourceRect = rect
        cfg.width = Int(rect.width * 2); cfg.height = Int(rect.height * 2)
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        cfg.showsCursor = false
        cfg.backgroundColor = .clear
        let rec = try Rec(url: out, w: cfg.width, h: cfg.height)
        let stream = SCStream(filter: filter, configuration: cfg, delegate: nil)
        try stream.addStreamOutput(rec, type: .screen, sampleHandlerQueue: DispatchQueue(label: "rec"))
        try await stream.startCapture()
        print("recording"); fflush(stdout)
        try await Task.sleep(nanoseconds: UInt64(secs * 1e9))
        try await stream.stopCapture()
        rec.input.markAsFinished()
        await rec.writer.finishWriting()
        print("saved", out.path, rec.writer.status.rawValue)
    } catch { print("error:", error) }
    sem.signal()
}
sem.wait()
