import AppKit
import Observation

/// Apple Notes integration through the Notes AppleScript interface
/// (Apple's supported automation API for Notes; needs Automation consent).
///
/// What the interface supports and Stitchy uses: listing accounts, folders
/// and notes (id, name, modification date, locked state), reading a note's
/// plain text and HTML body, creating notes, replacing a note's body, and
/// showing a note in the Notes app. There is no change-notification API, so
/// Stitchy re-reads on demand (opening the tab, Refresh, after edits).
/// Notes stay in Apple Notes; Stitchy keeps no copy.
@MainActor @Observable
final class AppleNotesService {
    struct Folder: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let account: String
    }

    struct Note: Identifiable, Equatable, Sendable {
        let id: String
        var name: String
        let folderID: String
        let folder: String
        let account: String
        var modified: Date
        let locked: Bool
    }

    struct Detail: Equatable, Sendable {
        let id: String
        var text: String
        var modified: Date
        let locked: Bool
        /// Why the note can't be edited here (nil = editable).
        let readOnlyReason: String?
        let titleIsHeading: Bool
    }

    enum Status: Equatable {
        case notConnected, loading, ready(Date), denied, failed(String)
    }

    private(set) var status: Status = .notConnected
    private(set) var folders: [Folder] = []
    private(set) var notes: [Note] = []
    private(set) var detail: Detail?
    private(set) var isLoadingDetail = false
    private(set) var saveState: SaveState = .idle
    var selectedID: String?
    var isComposing = false

    enum SaveState: Equatable { case idle, saving, saved(Date), conflict, failed(String) }

    @ObservationIgnored private var lastRefresh: Date?

    var isConnected: Bool {
        switch status { case .ready, .loading: true; default: false }
    }

    func startCompose() {
        isComposing = true
        selectedID = nil
        detail = nil
        saveState = .idle
    }

    // MARK: Listing

    /// Reads folders and note metadata. `force` skips the 20 s throttle.
    func refresh(force: Bool = false) async {
        if !force, let lastRefresh, Date().timeIntervalSince(lastRefresh) < 20, case .ready = status { return }
        if case .ready = status {} else { status = .loading }
        // Large libraries take a while to list; allow longer than the default.
        let result = await AppleScriptRunner.run(Self.listScript, timeout: 30) { Self.parseList($0) }
        switch result {
        case .success(let parsed?):
            folders = parsed.0
            notes = parsed.1.sorted { $0.modified > $1.modified }
            lastRefresh = Date()
            status = .ready(Date())
            if let selectedID, !notes.contains(where: { $0.id == selectedID }) { self.selectedID = nil; detail = nil }
        case .success(nil): status = .failed("Notes returned data Stitchy couldn't read.")
        case .failure(.notPermitted): status = .denied
        case .failure(.notRunning): status = .failed("Notes isn't available.")
        case .failure(.timedOut): status = .failed("Notes didn't respond. Try again in a moment.")
        case .failure(.other(let code)): status = .failed("Notes reported error \(code).")
        }
    }

    // MARK: Reading one note

    func select(_ id: String) async {
        selectedID = id
        isComposing = false
        saveState = .idle
        isLoadingDetail = true
        defer { isLoadingDetail = false }
        let result = await AppleScriptRunner.run(Self.detailScript(id)) { Self.parseDetail($0, id: id) }
        guard selectedID == id else { return }
        switch result {
        case .success(let d?): detail = d
        case .failure(.notPermitted): status = .denied
        default: detail = nil; saveState = .failed("Couldn't read this note. It may have been deleted.")
        }
    }

    // MARK: Writing

    /// Replaces the selected note's body. Refuses if the note changed in
    /// Apple Notes since it was loaded, instead of overwriting it.
    func save(text: String) async {
        guard let current = detail, current.readOnlyReason == nil, text != current.text else { return }
        saveState = .saving
        let check = await AppleScriptRunner.run(Self.modifiedScript(current.id)) { $0.dateValue }
        if case .success(let modified?) = check, modified.timeIntervalSince(current.modified) > 1 {
            saveState = .conflict
            return
        }
        let html = Self.html(from: text, titleIsHeading: current.titleIsHeading)
        let result = await AppleScriptRunner.run(Self.updateScript(current.id, html: html)) { $0.dateValue }
        switch result {
        case .success(let modified):
            let date = modified ?? Date()
            detail?.text = text
            detail?.modified = date
            if let i = notes.firstIndex(where: { $0.id == current.id }) {
                notes[i].modified = date
                notes[i].name = Self.title(of: text)
            }
            saveState = .saved(Date())
        case .failure(.notPermitted): status = .denied; saveState = .failed("Automation access was revoked.")
        case .failure: saveState = .failed("Apple Notes didn't accept the change.")
        }
    }

    /// Creates a note in Apple Notes (chosen folder or Notes' default folder).
    @discardableResult
    func create(text: String, folderID: String?) async -> String? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        saveState = .saving
        let html = Self.html(from: text, titleIsHeading: false)
        let result = await AppleScriptRunner.run(Self.createScript(folderID: folderID, html: html)) { $0.stringValue }
        switch result {
        case .success(let id?):
            saveState = .saved(Date())
            isComposing = false
            await refresh(force: true)
            await select(id)
            return id
        case .failure(.notPermitted): status = .denied; saveState = .failed("Automation access is needed.")
        default: saveState = .failed("Apple Notes couldn't create the note. Check the folder still exists.")
        }
        return nil
    }

    /// Opens the note in the Notes app.
    func open(_ id: String) {
        Task { _ = await AppleScriptRunner.run(Self.showScript(id)) { _ in true } }
    }

    func search(_ query: String, folderID: String?) -> [Note] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return notes.filter { note in
            (folderID == nil || note.folderID == folderID) && (q.isEmpty || note.name.localizedCaseInsensitiveContains(q))
        }
    }

    // MARK: Scripts (validated with osacompile against the Notes dictionary)

    nonisolated static func literal(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    nonisolated static let listScript = """
    tell application "Notes"
        set out to {}
        repeat with a in accounts
            set accName to name of a
            repeat with f in folders of a
                set end of out to {id of f, name of f, accName, id of notes of f, name of notes of f, modification date of notes of f, password protected of notes of f}
            end repeat
        end repeat
        return out
    end tell
    """

    nonisolated static func detailScript(_ id: String) -> String {
        """
        tell application "Notes"
            set n to note id \(literal(id))
            if password protected of n then return {"", "", modification date of n, 0, true}
            return {plaintext of n, body of n, modification date of n, count of attachments of n, false}
        end tell
        """
    }

    nonisolated static func modifiedScript(_ id: String) -> String {
        "tell application \"Notes\" to get modification date of note id \(literal(id))"
    }

    nonisolated static func updateScript(_ id: String, html: String) -> String {
        """
        tell application "Notes"
            set body of note id \(literal(id)) to \(literal(html))
            return modification date of note id \(literal(id))
        end tell
        """
    }

    nonisolated static func createScript(folderID: String?, html: String) -> String {
        let location = folderID.map { "folder id \(literal($0))" } ?? "(default folder of default account)"
        return """
        tell application "Notes"
            set n to make new note at \(location) with properties {body:\(literal(html))}
            return id of n
        end tell
        """
    }

    nonisolated static func showScript(_ id: String) -> String {
        """
        tell application "Notes"
            show note id \(literal(id))
            activate
        end tell
        """
    }

    // MARK: Parsing and conversion (pure, tested)

    nonisolated static func parseList(_ d: NSAppleEventDescriptor) -> ([Folder], [Note])? {
        guard d.numberOfItems >= 0 else { return nil }
        var folders: [Folder] = []
        var notes: [Note] = []
        for i in stride(from: 1, through: d.numberOfItems, by: 1) {
            guard let row = d.item(i), row.numberOfItems >= 7,
                  let fid = row.item(1)?.stringValue, let fname = row.item(2)?.stringValue,
                  let account = row.item(3)?.stringValue else { continue }
            // Apple's own trash folder isn't useful to browse.
            if fname == "Recently Deleted" { continue }
            folders.append(Folder(id: fid, name: fname, account: account))
            let ids = list(row.item(4)), names = list(row.item(5)), mods = list(row.item(6)), locks = list(row.item(7))
            for j in ids.indices {
                guard let id = ids[j].stringValue else { continue }
                notes.append(Note(id: id, name: j < names.count ? names[j].stringValue ?? "Untitled" : "Untitled",
                                  folderID: fid, folder: fname, account: account,
                                  modified: j < mods.count ? mods[j].dateValue ?? .distantPast : .distantPast,
                                  locked: j < locks.count ? locks[j].booleanValue : false))
            }
        }
        return (folders, notes)
    }

    nonisolated private static func list(_ d: NSAppleEventDescriptor?) -> [NSAppleEventDescriptor] {
        guard let d, d.numberOfItems > 0 else { return [] }
        return (1...d.numberOfItems).compactMap { d.atIndex($0) }
    }

    nonisolated static func parseDetail(_ d: NSAppleEventDescriptor, id: String) -> Detail? {
        guard d.numberOfItems >= 5 else { return nil }
        let locked = d.item(5)?.booleanValue ?? false
        let html = d.item(2)?.stringValue ?? ""
        let attachments = d.item(4)?.int32Value ?? 0
        var reason: String?
        if locked { reason = "This note is locked. Open it in Notes to unlock." }
        else if attachments > 0 { reason = "This note has attachments. Edit it in Notes so nothing is lost." }
        else if !isSimple(html) { reason = "This note has formatting Stitchy can't preserve. Edit it in Notes." }
        return Detail(id: id, text: d.item(1)?.stringValue ?? "", modified: d.item(3)?.dateValue ?? Date(),
                      locked: locked, readOnlyReason: reason,
                      titleIsHeading: html.range(of: "<h1", options: .caseInsensitive) != nil)
    }

    /// True when the HTML only uses tags that plain-text editing round-trips.
    nonisolated static func isSimple(_ html: String) -> Bool {
        let allowed: Set<String> = ["div", "br", "h1", "p", "span", "html", "head", "body"]
        guard let regex = try? NSRegularExpression(pattern: "</?\\s*([a-zA-Z0-9]+)") else { return false }
        let range = NSRange(html.startIndex..., in: html)
        for m in regex.matches(in: html, range: range) {
            guard let r = Range(m.range(at: 1), in: html) else { continue }
            if !allowed.contains(html[r].lowercased()) { return false }
        }
        return true
    }

    nonisolated static func html(from text: String, titleIsHeading: Bool) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        let lines = text.components(separatedBy: "\n")
        return lines.enumerated().map { i, line in
            if line.isEmpty { return "<div><br></div>" }
            return i == 0 && titleIsHeading ? "<div><h1>\(esc(line))</h1></div>" : "<div>\(esc(line))</div>"
        }.joined()
    }

    nonisolated static func title(of text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? "New Note"
    }
}
