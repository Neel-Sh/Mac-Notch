// Prints the CGWindowID of Brim's island panel, for `screencapture -l`.
import CoreGraphics
import Foundation

let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
let panel = windows.first {
    ($0[kCGWindowOwnerName as String] as? String) == "Brim"
        && (($0[kCGWindowBounds as String] as? [String: Double])?["Height"] ?? 0) > 200
}
if let id = panel?[kCGWindowNumber as String] as? Int { print(id) } else { exit(1) }
