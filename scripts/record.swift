// Records Brim's island window (only that window, with transparency) to PNG frames via ScreenCaptureKit.
// Usage: record <output-dir> <seconds>
import AppKit
import CoreImage
import ScreenCaptureKit

final class Recorder: NSObject, SCStreamOutput {
    let folder: URL
    var index = 0
    var times: [Double] = []
    let context = CIContext()
    init(folder: URL) { self.folder = folder }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let pixels = buffer.imageBuffer else { return }
        let image = CIImage(cvPixelBuffer: pixels)
        let url = folder.appendingPathComponent(String(format: "%05d.png", index))
        times.append(buffer.presentationTimeStamp.seconds)
        index += 1
        try? context.writePNGRepresentation(of: image, to: url, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
    }
}

_ = NSApplication.shared // ScreenCaptureKit needs a window-server connection
let arguments = CommandLine.arguments
let folder = URL(fileURLWithPath: arguments[1])
let seconds = Double(arguments[2]) ?? 15

let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
guard let window = content.windows.first(where: { $0.owningApplication?.applicationName == "Brim" && $0.frame.height > 200 }) else {
    FileHandle.standardError.write(Data("Brim's island window isn't on screen\n".utf8))
    exit(1)
}
let filter = SCContentFilter(desktopIndependentWindow: window)
let configuration = SCStreamConfiguration()
configuration.width = Int(window.frame.width * 2)
configuration.height = Int(window.frame.height * 2)
configuration.pixelFormat = kCVPixelFormatType_32BGRA
configuration.showsCursor = false
configuration.ignoreShadowsSingleWindow = true
configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)

let recorder = Recorder(folder: folder)
let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
try stream.addStreamOutput(recorder, type: .screen, sampleHandlerQueue: DispatchQueue(label: "frames"))
try await stream.startCapture()
try await Task.sleep(for: .seconds(seconds))
try await stream.stopCapture()
// Frames only arrive when something changes; their timestamps let the encoder keep the pauses.
let start = recorder.times.first ?? 0
let end = start + seconds
let lines = recorder.times.map { String($0 - start) } + ["end \(end - start)"]
try lines.joined(separator: "\n").write(to: folder.appendingPathComponent("times.txt"), atomically: true, encoding: .utf8)
print("captured \(recorder.index) frames")
