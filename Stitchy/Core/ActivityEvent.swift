import AppKit
import SwiftUI

/// Something that happened in Stitchy. Events are recorded in the Activity
/// feed and, when `showsAlert` is set, briefly shown as a live alert in the
/// compact island (like a Dynamic Island alert).
struct ActivityEvent: Identifiable {
    let id = UUID()
    let date = Date()
    var symbol: String
    var tint: Color
    var title: String
    var detail: String?
    /// Short value shown on the trailing side of a live alert ("54%").
    var trailing: String?
    var artwork: NSImage?
    /// Tab opened when the user clicks the live alert.
    var tab: IslandTab?
    var recordsInFeed = true
    var showsAlert = true
    var alertDuration: TimeInterval = 2.8
}
