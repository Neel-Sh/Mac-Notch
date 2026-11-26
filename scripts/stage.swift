// Stages Brim on a clean desktop and captures it: a wallpaper and a plain menu bar go up behind the island,
// Brim launches in demo mode, and only those two are captured, so nothing else on your Mac is in the picture.
//
//   stage shot   <out.png> --view top:960x600 [--wait 3] [--wallpaper <image>] -- <Brim launch arguments>
//   stage record <out.mov> --view full --seconds 18 -- <Brim launch arguments>
//
// --view is the part of the screen to capture, in points: `top:WxH` (centred under the notch),
// `left:WxH` or `right:WxH` (against that edge, where a docked island sits), `full`, or `window:P`
// (Brim's Settings window with P points of desktop around it).
import AppKit
import ScreenCaptureKit
import SwiftUI

// MARK: Arguments

var arguments = Array(CommandLine.arguments.dropFirst())
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
var brimArguments: [String] = []
if let split = arguments.firstIndex(of: "--") {
    brimArguments = Array(arguments[(split + 1)...])
    arguments = Array(arguments[..<split])
}
func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}
guard arguments.count >= 2, ["shot", "record"].contains(arguments[0]) else {
    fail("usage: stage shot|record <output> --view top:WxH|left:WxH|right:WxH|window:P|full [--wait s] [--seconds s] -- <Brim arguments>")
}
let recording = arguments[0] == "record"
let output = URL(fileURLWithPath: arguments[1])
let wait = Double(option("--wait") ?? "") ?? 3
let seconds = Double(option("--seconds") ?? "") ?? 15
let wallpaperPath = option("--wallpaper") ?? "/System/Library/Desktop Pictures/Sonoma.heic"
let appPath = option("--app") ?? "build/DerivedData/Build/Products/Debug/Brim.app"

// MARK: The view

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
guard let screen = NSScreen.screens.first(where: { ($0.auxiliaryTopLeftArea?.width ?? 0) > 0 }) ?? NSScreen.main else {
    fail("no screen")
}
let screenSize = screen.frame.size
let notchMidX: CGFloat = if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea, left.width > 0 {
    (left.maxX + right.minX) / 2 - screen.frame.minX
} else {
    screenSize.width / 2
}
let menuBarHeight = max(screen.safeAreaInsets.top, 24)

/// The part of the screen dressed as a desktop, in points from the screen's top-left corner.
/// It's also what gets captured, except for `window:P`, which dresses the whole screen and crops to the window.
let spec = option("--view") ?? "full"
let windowPadding: CGFloat? = spec.hasPrefix("window:") ? CGFloat(Double(spec.dropFirst(7)) ?? 60) : nil
let view: CGRect = {
    guard spec != "full", windowPadding == nil else { return CGRect(origin: .zero, size: screenSize) }
    let parts = spec.split(separator: ":")
    let size = parts.last?.split(separator: "x").compactMap { Double($0) } ?? []
    guard parts.count == 2, size.count == 2 else { fail("bad --view \(spec)") }
    let width = min(size[0], screenSize.width), height = min(size[1], screenSize.height)
    // A docked island is centred in the space between the menu bar and the Dock.
    let visible = screen.visibleFrame
    let sideY = max(0, screen.frame.maxY - visible.midY - height / 2)
    switch parts[0] {
    case "top": return CGRect(x: max(0, notchMidX - width / 2), y: 0, width: width, height: height)
    case "left": return CGRect(x: 0, y: sideY, width: width, height: height)
    case "right": return CGRect(x: screenSize.width - width, y: sideY, width: width, height: height)
    default: fail("bad --view \(spec)")
    }
}()

// MARK: Backdrop

struct MenuBar: View {
    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 19) {
                Text("Finder").fontWeight(.bold)
                ForEach(["File", "Edit", "View", "Go", "Window", "Help"], id: \.self) { Text($0) }
            }
            Spacer(minLength: 0)
            HStack(spacing: 17) {
                Image(systemName: "battery.100percent").font(.system(size: 17))
                Image(systemName: "wifi")
                Image(systemName: "magnifyingglass")
                Image(systemName: "switch.2")
                Text(Date.now, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                Text(Date.now, format: .dateTime.hour().minute())
                    .padding(.leading, -9)
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.25), radius: 2, y: 0.5)
        .lineLimit(1)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 22)
    }
}

struct Backdrop: View {
    let wallpaper: NSImage
    let view: CGRect
    let menuBarHeight: CGFloat
    let showsMenuBar: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            Image(nsImage: wallpaper)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: view.width, height: view.height)
                .clipped()
                .overlay(alignment: .top) {
                    if showsMenuBar { MenuBar().frame(width: view.width, height: menuBarHeight) }
                }
                .offset(x: view.minX, y: view.minY)
        }
        .ignoresSafeArea()
    }
}

guard let wallpaper = NSImage(contentsOfFile: wallpaperPath) else { fail("can't read wallpaper at \(wallpaperPath)") }
let backdrop = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
backdrop.title = "Brim Stage"
backdrop.isReleasedWhenClosed = false
backdrop.ignoresMouseEvents = true
backdrop.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
backdrop.contentView = NSHostingView(rootView: Backdrop(wallpaper: wallpaper, view: view, menuBarHeight: menuBarHeight,
                                                         showsMenuBar: view.minY == 0))
backdrop.setFrame(screen.frame, display: true)
backdrop.orderFrontRegardless()

// MARK: Brim, then the capture

final class Finish: NSObject, SCRecordingOutputDelegate, SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {}
}

/// In a function, so the calls below pick ScreenCaptureKit's async forms rather than its completion handlers.
@MainActor func capture() async throws {
    for running in NSRunningApplication.runningApplications(withBundleIdentifier: "com.neelsharma.brim") { running.terminate() }
    try await Task.sleep(for: .seconds(0.8))
    let launch = NSWorkspace.OpenConfiguration()
    launch.arguments = ["-demo", "YES"] + brimArguments
    launch.createsNewApplicationInstance = true
    _ = try await NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: appPath), configuration: launch)
    try await Task.sleep(for: .seconds(recording ? 1.0 : wait))

    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    guard let display = content.displays.first(where: { $0.displayID == screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID }) else {
        fail("the screen isn't shareable; allow Screen Recording for your terminal")
    }
    let me = ProcessInfo.processInfo.processIdentifier
    let windows = content.windows.filter { window in
        if window.owningApplication?.processID == me { return true }
        // Brim's island and Settings, not its menu bar icon.
        return window.owningApplication?.bundleIdentifier == "com.neelsharma.brim" && window.frame.height > 60
    }
    guard windows.count >= 2 else { fail("Brim's window isn't on screen") }

    var shown = view
    if let windowPadding {
        guard let settings = windows.first(where: { $0.owningApplication?.processID != me && $0.windowLayer == 0 }) else {
            fail("Brim's Settings window isn't on screen; launch with -openSettings YES")
        }
        shown = settings.frame.insetBy(dx: -windowPadding, dy: -windowPadding).intersection(view)
    }
    let scale = screen.backingScaleFactor
    let configuration = SCStreamConfiguration()
    configuration.sourceRect = shown
    configuration.width = Int(shown.width * scale)
    configuration.height = Int(shown.height * scale)
    configuration.showsCursor = false
    configuration.captureResolution = .best
    configuration.colorSpaceName = CGColorSpace.sRGB
    configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
    let filter = SCContentFilter(display: display, including: windows)

    if recording {
        try? FileManager.default.removeItem(at: output)
        let finish = Finish()
        let recordingConfiguration = SCRecordingOutputConfiguration()
        recordingConfiguration.outputURL = output
        recordingConfiguration.outputFileType = .mov
        recordingConfiguration.videoCodecType = .hevc
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(finish, type: .screen, sampleHandlerQueue: DispatchQueue(label: "frames"))
        try stream.addRecordingOutput(SCRecordingOutput(configuration: recordingConfiguration, delegate: finish))
        try await stream.startCapture()
        try await Task.sleep(for: .seconds(seconds))
        try await stream.stopCapture()
    } else {
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fail("couldn't encode the screenshot") }
        try png.write(to: output)
    }

    for running in NSRunningApplication.runningApplications(withBundleIdentifier: "com.neelsharma.brim") { running.terminate() }
    print("wrote \(output.path)")
}

do { try await capture() } catch { fail("\(error)") }
exit(0)
