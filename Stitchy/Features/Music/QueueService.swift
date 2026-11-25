import AppKit
import CryptoKit
import Network
import Observation
import Security

/// "Up Next" for the music player.
///  - Apple Music: Music's scripting dictionary exposes the current playlist,
///    so the next tracks in playlist order are listed. Music doesn't expose its
///    shuffled order or its own Up Next list; the UI says so.
///  - Spotify: the desktop app exposes no queue. The supported source is the
///    Spotify Web API (GET /v1/me/player/queue), which needs the user's own
///    Spotify developer app (Client ID) and a one-time sign-in in the browser
///    (OAuth with PKCE; no client secret). The refresh token is kept in the
///    Keychain; nothing else is stored.
@MainActor @Observable
final class QueueService {
    struct Item: Identifiable, Equatable, Sendable {
        let id = UUID()
        let title: String
        let artist: String
        let artworkURL: URL?
    }

    enum State: Equatable { case idle, loading, loaded, needsSpotifyLogin, unavailable(String) }

    private(set) var items: [Item] = []
    private(set) var state: State = .idle
    private(set) var spotifyConnected = SpotifyAuth.hasRefreshToken
    private(set) var signInError: String?
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var auth: SpotifyAuth?

    init(settings: AppSettings) { self.settings = settings }

    func refresh(player: NowPlayingService.Player?, shuffle: Bool?) async {
        guard let player else { items = []; state = .idle; return }
        state = .loading
        switch player {
        case .music:
            let r = await AppleScriptRunner.run(Self.musicScript) { d -> [[String]]? in
                guard d.numberOfItems > 0 else { return [] }
                return (1...d.numberOfItems).compactMap { i in
                    guard let row = d.item(i) else { return nil }
                    return [row.item(1)?.stringValue ?? "", row.item(2)?.stringValue ?? ""]
                }
            }
            switch r {
            case .success(let rows?):
                items = rows.map { Item(title: $0[0], artist: $0[1], artworkURL: nil) }
                state = items.isEmpty ? .unavailable("Nothing after this song in the playlist.") : .loaded
            case .failure(.notPermitted): state = .unavailable("Allow Stitchy to control Music in Privacy settings.")
            default: state = .unavailable("Music didn't return the playlist.")
            }
        case .spotify:
            guard spotifyConnected, !settings.spotifyClientID.isEmpty else { state = .needsSpotifyLogin; return }
            do {
                let token = try await SpotifyAuth.accessToken(clientID: settings.spotifyClientID)
                items = try await Self.fetchSpotifyQueue(token: token)
                state = items.isEmpty ? .unavailable("Your Spotify queue is empty.") : .loaded
            } catch SpotifyAuth.AuthError.notSignedIn {
                spotifyConnected = false
                state = .needsSpotifyLogin
            } catch {
                state = .unavailable("Spotify didn't return the queue. Check your connection.")
            }
        }
    }

    // MARK: Spotify sign-in

    func connectSpotify() async {
        signInError = nil
        guard !settings.spotifyClientID.isEmpty else { signInError = "Add your Spotify Client ID first."; return }
        let auth = SpotifyAuth(clientID: settings.spotifyClientID)
        self.auth = auth
        do {
            try await auth.signIn()
            spotifyConnected = true
        } catch {
            signInError = (error as? SpotifyAuth.AuthError)?.message ?? error.localizedDescription
        }
        self.auth = nil
    }

    func disconnectSpotify() {
        SpotifyAuth.deleteRefreshToken()
        spotifyConnected = false
        items = []
    }

    // MARK: Fetching

    nonisolated static let musicScript = """
    tell application "Music"
        set pl to current playlist
        set idx to index of current track
        set n to count of tracks of pl
        set out to {}
        repeat with i from (idx + 1) to (idx + 15)
            if i > n then exit repeat
            set t to track i of pl
            set end of out to {name of t, artist of t}
        end repeat
        return out
    end tell
    """

    nonisolated static func fetchSpotifyQueue(token: String) async throws -> [Item] {
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/queue")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 401 { throw SpotifyAuth.AuthError.notSignedIn }
        guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try parseSpotifyQueue(data)
    }

    /// Pure; tested.
    nonisolated static func parseSpotifyQueue(_ data: Data) throws -> [Item] {
        struct Image: Decodable { let url: String; let width: Int? }
        struct Artist: Decodable { let name: String }
        struct Album: Decodable { let images: [Image]? }
        struct Track: Decodable { let name: String; let artists: [Artist]?; let album: Album?; let show: Artist? }
        struct Response: Decodable { let queue: [Track] }
        return try JSONDecoder().decode(Response.self, from: data).queue.prefix(20).map { t in
            let image = t.album?.images?.sorted { ($0.width ?? 0) < ($1.width ?? 0) }.first(where: { ($0.width ?? 0) >= 64 }) ?? t.album?.images?.first
            return Item(title: t.name, artist: t.artists?.map(\.name).joined(separator: ", ") ?? t.show?.name ?? "",
                        artworkURL: image.flatMap { URL(string: $0.url) })
        }
    }
}

/// Spotify Authorization Code + PKCE with a one-time loopback redirect
/// (http://127.0.0.1:43117/callback, which the user registers in their
/// Spotify app). Only the refresh token is stored, in the Keychain.
final class SpotifyAuth: @unchecked Sendable {
    enum AuthError: Error { case notSignedIn, cancelled, failed(String)
        var message: String {
            switch self { case .notSignedIn: "Not signed in to Spotify."; case .cancelled: "Sign-in cancelled."; case .failed(let m): m }
        }
    }

    static let port: UInt16 = 43117
    static let redirectURI = "http://127.0.0.1:43117/callback"
    static let scopes = "user-read-playback-state user-read-currently-playing"

    private let clientID: String
    private let verifier: String
    private let state = UUID().uuidString
    private var listener: NWListener?

    init(clientID: String) {
        self.clientID = clientID
        var bytes = [UInt8](repeating: 0, count: 48)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        verifier = Self.base64URL(Data(bytes))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func challenge(for verifier: String) -> String { base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))) }

    func authorizeURL() -> URL {
        var c = URLComponents(string: "https://accounts.spotify.com/authorize")!
        c.queryItems = [
            .init(name: "client_id", value: clientID), .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirectURI), .init(name: "scope", value: Self.scopes),
            .init(name: "code_challenge_method", value: "S256"), .init(name: "code_challenge", value: Self.challenge(for: verifier)),
            .init(name: "state", value: state),
        ]
        return c.url!
    }

    /// Opens the browser, waits (up to 3 minutes) for the redirect, exchanges the code.
    func signIn() async throws {
        let code = try await withCheckedThrowingContinuation { (c: CheckedContinuation<String, Error>) in
            let once = OSAllocatedFlag()
            do {
                let params = NWParameters.tcp
                params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .init(rawValue: Self.port)!)
                let listener = try NWListener(using: params)
                self.listener = listener
                listener.newConnectionHandler = { [state] conn in
                    conn.start(queue: .global())
                    conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                        let request = String(decoding: data ?? Data(), as: UTF8.self)
                        let result = Self.parseCallback(request, expectedState: state)
                        let body = result.code != nil ? "Stitchy is connected to Spotify. You can close this tab." : "Stitchy couldn't connect: \(result.error ?? "unknown error")."
                        let reply = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n<html><body style=\"font-family:-apple-system;padding:40px\">\(body)</body></html>"
                        conn.send(content: Data(reply.utf8), completion: .contentProcessed { _ in conn.cancel() })
                        guard once.set() else { return }
                        listener.cancel()
                        if let code = result.code { c.resume(returning: code) } else { c.resume(throwing: AuthError.failed(result.error ?? "Sign-in failed.")) }
                    }
                }
                listener.start(queue: .global())
                DispatchQueue.global().asyncAfter(deadline: .now() + 180) {
                    if once.set() { listener.cancel(); c.resume(throwing: AuthError.cancelled) }
                }
                let url = authorizeURL()
                DispatchQueue.main.async { NSWorkspace.shared.open(url) }
            } catch {
                if once.set() { c.resume(throwing: AuthError.failed("Port \(Self.port) is busy. Try again.")) }
            }
        }
        let tokens = try await Self.token(["grant_type": "authorization_code", "code": code, "redirect_uri": Self.redirectURI,
                                           "client_id": clientID, "code_verifier": verifier])
        guard let refresh = tokens.refresh_token else { throw AuthError.failed("Spotify didn't return a refresh token.") }
        Self.saveRefreshToken(refresh)
        Self.cache = (tokens.access_token, Date().addingTimeInterval(TimeInterval(tokens.expires_in - 60)))
    }

    /// `/callback?code=…&state=…` from the raw HTTP request line. Pure; tested.
    static func parseCallback(_ request: String, expectedState: String) -> (code: String?, error: String?) {
        guard let line = request.split(separator: "\r\n").first ?? request.split(separator: "\n").first,
              let path = line.split(separator: " ").dropFirst().first,
              let comps = URLComponents(string: "http://127.0.0.1" + path) else { return (nil, "Malformed redirect") }
        let q = Dictionary((comps.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        if let e = q["error"] { return (nil, e) }
        guard q["state"] == expectedState else { return (nil, "State mismatch") }
        return (q["code"], q["code"] == nil ? "No code" : nil)
    }

    // MARK: Tokens

    private struct TokenResponse: Decodable { let access_token: String; let expires_in: Int; let refresh_token: String? }
    nonisolated(unsafe) private static var cache: (String, Date)?

    static func accessToken(clientID: String) async throws -> String {
        if let (token, expiry) = cache, expiry > Date() { return token }
        guard let refresh = loadRefreshToken() else { throw AuthError.notSignedIn }
        let t = try await token(["grant_type": "refresh_token", "refresh_token": refresh, "client_id": clientID])
        if let newRefresh = t.refresh_token { saveRefreshToken(newRefresh) }
        cache = (t.access_token, Date().addingTimeInterval(TimeInterval(t.expires_in - 60)))
        return t.access_token
    }

    private static func token(_ form: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var c = URLComponents()
        c.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((c.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            if (response as? HTTPURLResponse)?.statusCode == 400 { deleteRefreshToken(); throw AuthError.notSignedIn }
            throw AuthError.failed("Spotify sign-in failed.")
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    // MARK: Keychain

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.stitchy.spotify", kSecAttrAccount as String: "refresh"]
    }

    static var hasRefreshToken: Bool { loadRefreshToken() != nil }

    static func saveRefreshToken(_ token: String) {
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    static func loadRefreshToken() -> String? {
        if ProcessInfo.processInfo.processName.hasSuffix("PackageTests") { return nil }
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(decoding: d, as: UTF8.self)
    }

    static func deleteRefreshToken() {
        SecItemDelete(query as CFDictionary)
        cache = nil
    }
}
