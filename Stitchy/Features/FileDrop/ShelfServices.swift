// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

/// Finder › right-click › Services (Quick Actions) › "Add to Stitchy Shelf".
/// Declared under NSServices in Info.plist; macOS calls `addToShelf`.
@MainActor
final class ShelfServiceProvider: NSObject {
    private let shelf: FileShelf
    private let island: IslandModel

    init(shelf: FileShelf, island: IslandModel) {
        self.shelf = shelf
        self.island = island
    }

    @objc func addToShelf(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { error.pointee = "No files to add." as NSString; return }
        shelf.add(urls)
        island.expand(.menu, tab: .shelf)
    }

    /// Any app › select text › Services › "Translate with Stitchy".
    @objc func translateText(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard #available(macOS 15.0, *) else { error.pointee = "Translation needs macOS 15 or later." as NSString; return }
        guard let text = pboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error.pointee = "No text selected." as NSString
            return
        }
        island.translateRequest = text
        island.expand(.menu, tab: .tools)
    }
}
