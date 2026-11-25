import CoreLocation
import Observation
import SwiftUI

/// Weather from Open-Meteo (open-meteo.com): free, no API key, no account.
/// Location: one CoreLocation fix when the user allows it, or a city the
/// user picks (Open-Meteo geocoding). Only coordinates are sent. Refreshes
/// every 30 minutes while the feature is on. Open-Meteo has no severe
/// weather alerts, so none are shown.
@MainActor @Observable
final class WeatherService: NSObject, CLLocationManagerDelegate {
    struct Place: Codable, Equatable, Sendable { var name: String; var latitude: Double; var longitude: Double }

    struct Current: Equatable, Sendable {
        var temperature: Double, feelsLike: Double, humidity: Int, wind: Double, code: Int, isDay: Bool
    }
    struct Hour: Equatable, Sendable, Identifiable { var id: Date { time }; var time: Date; var temperature: Double; var rain: Int?; var code: Int }
    struct Day: Equatable, Sendable, Identifiable {
        var id: Date { date }
        var date: Date; var high: Double; var low: Double; var rain: Int?; var code: Int
        var sunrise: Date? = nil; var sunset: Date? = nil; var uv: Double? = nil
    }

    enum Status: Equatable { case idle, locating, loading, ready(Date), needsLocation, failed(String) }

    private(set) var status: Status = .idle
    private(set) var place: Place?
    private(set) var current: Current?
    private(set) var hours: [Hour] = []
    private(set) var days: [Day] = []
    private(set) var searchResults: [Place] = []
    @ObservationIgnored var onEvent: ((ActivityEvent) -> Void)?
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastRainAlert: Date?

    init(settings: AppSettings) {
        self.settings = settings
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        place = settings.data(Place.self, key: "weatherPlace")
    }

    var useFahrenheit: Bool { settings.weatherFahrenheit }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        timer?.tolerance = 120
        Task { await refresh() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() async {
        guard let place else {
            status = .needsLocation
            return
        }
        status = current == nil ? .loading : status
        do {
            let parsed = try await Self.fetch(place, fahrenheit: useFahrenheit)
            current = parsed.0
            hours = parsed.1
            days = parsed.2
            status = .ready(Date())
            checkRain()
        } catch {
            status = .failed("Couldn't load weather. Check your connection.")
        }
    }

    /// Dev aid for `--snapshots` renders only.
    func loadPreview(_ data: Data, place p: Place) {
        place = p
        if let parsed = try? Self.parse(data, now: .distantPast) { current = parsed.0; hours = parsed.1; days = parsed.2; status = .ready(Date()) }
    }

    // MARK: Location (explicit, one-shot)

    /// Asks macOS for location once and uses a single coarse fix.
    func useCurrentLocation() {
        status = .locating
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard self.status == .locating else { return }
            if status == .authorizedAlways || status == .authorized { self.manager.requestLocation() }
            else if status == .denied || status == .restricted { self.status = .failed("Location access is off. Pick a city instead.") }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        let lat = (c.latitude * 100).rounded() / 100, lon = (c.longitude * 100).rounded() / 100   // ~1 km is plenty
        Task { @MainActor in
            let name = await Self.reverseName(CLLocation(latitude: lat, longitude: lon)) ?? "Current Location"
            self.setPlace(Place(name: name, latitude: lat, longitude: lon))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.status = .failed("Couldn't get your location. Pick a city instead.") }
    }

    nonisolated private static func reverseName(_ location: CLLocation) async -> String? {
        try? await CLGeocoder().reverseGeocodeLocation(location).first?.locality
    }

    // MARK: Manual city

    func search(_ query: String) async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { searchResults = []; return }
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [.init(name: "name", value: q), .init(name: "count", value: "6"), .init(name: "language", value: "en")]
        guard let (data, _) = try? await URLSession.shared.data(from: c.url!),
              let r = try? JSONDecoder().decode(GeoResponse.self, from: data) else { return }
        searchResults = (r.results ?? []).map {
            Place(name: [$0.name, $0.admin1, $0.country].compactMap { $0 }.joined(separator: ", "), latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    func setPlace(_ p: Place) {
        place = p
        settings.setData(p, key: "weatherPlace")
        searchResults = []
        Task { await refresh() }
    }

    private struct GeoResponse: Decodable {
        struct R: Decodable { let name: String; let latitude: Double; let longitude: Double; let country: String?; let admin1: String? }
        let results: [R]?
    }

    // MARK: Rain heads-up

    /// One alert when rain is likely in the next hour, at most every 3 h.
    private func checkRain() {
        guard settings.weatherAlerts, let next = hours.first(where: { $0.time > Date() }), let p = next.rain, p >= 60 else { return }
        if let last = lastRainAlert, Date().timeIntervalSince(last) < 3 * 3600 { return }
        lastRainAlert = Date()
        onEvent?(ActivityEvent(symbol: "cloud.rain.fill", tint: .cyan, title: "Rain likely soon", detail: "\(p)% chance in the next hour",
                               tab: .weather))
    }

    // MARK: Network + parsing (pure, tested)

    nonisolated static func url(for p: Place, fahrenheit: Bool) -> URL {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(p.latitude)), .init(name: "longitude", value: String(p.longitude)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day"),
            .init(name: "hourly", value: "temperature_2m,precipitation_probability,weather_code"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset,uv_index_max"),
            .init(name: "timezone", value: "auto"), .init(name: "forecast_days", value: "10"),
            .init(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius"),
            .init(name: "wind_speed_unit", value: fahrenheit ? "mph" : "kmh"),
        ]
        return c.url!
    }

    nonisolated static func fetch(_ p: Place, fahrenheit: Bool) async throws -> (Current, [Hour], [Day]) {
        let (data, response) = try await URLSession.shared.data(from: url(for: p, fahrenheit: fahrenheit))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try parse(data, now: Date())
    }

    private struct Response: Decodable {
        struct C: Decodable {
            let temperature_2m: Double, apparent_temperature: Double, relative_humidity_2m: Int, weather_code: Int, wind_speed_10m: Double, is_day: Int
        }
        struct H: Decodable { let time: [String]; let temperature_2m: [Double]; let precipitation_probability: [Int?]?; let weather_code: [Int] }
        struct D: Decodable {
            let time: [String]; let weather_code: [Int]; let temperature_2m_max: [Double]; let temperature_2m_min: [Double]
            let precipitation_probability_max: [Int?]?
            let sunrise: [String]?; let sunset: [String]?; let uv_index_max: [Double?]?
        }
        let utc_offset_seconds: Int
        let current: C; let hourly: H; let daily: D
    }

    nonisolated static func parse(_ data: Data, now: Date) throws -> (Current, [Hour], [Day]) {
        let r = try JSONDecoder().decode(Response.self, from: data)
        let tz = TimeZone(secondsFromGMT: r.utc_offset_seconds) ?? .current
        let hourFmt = DateFormatter(); hourFmt.dateFormat = "yyyy-MM-dd'T'HH:mm"; hourFmt.timeZone = tz; hourFmt.locale = Locale(identifier: "en_US_POSIX")
        let dayFmt = DateFormatter(); dayFmt.dateFormat = "yyyy-MM-dd"; dayFmt.timeZone = tz; dayFmt.locale = Locale(identifier: "en_US_POSIX")
        let c = r.current
        let current = Current(temperature: c.temperature_2m, feelsLike: c.apparent_temperature, humidity: c.relative_humidity_2m,
                              wind: c.wind_speed_10m, code: c.weather_code, isDay: c.is_day == 1)
        let hours = r.hourly.time.indices.compactMap { i -> Hour? in
            guard let t = hourFmt.date(from: r.hourly.time[i]), t > now.addingTimeInterval(-3600) else { return nil }
            return Hour(time: t, temperature: r.hourly.temperature_2m[i], rain: r.hourly.precipitation_probability?[i] ?? nil, code: r.hourly.weather_code[i])
        }.prefix(24)
        let days = r.daily.time.indices.compactMap { i -> Day? in
            guard let d = dayFmt.date(from: r.daily.time[i]) else { return nil }
            return Day(date: d, high: r.daily.temperature_2m_max[i], low: r.daily.temperature_2m_min[i],
                       rain: r.daily.precipitation_probability_max?[i] ?? nil, code: r.daily.weather_code[i],
                       sunrise: r.daily.sunrise.flatMap { i < $0.count ? hourFmt.date(from: $0[i]) : nil },
                       sunset: r.daily.sunset.flatMap { i < $0.count ? hourFmt.date(from: $0[i]) : nil },
                       uv: r.daily.uv_index_max.flatMap { i < $0.count ? $0[i] : nil })
        }
        return (current, Array(hours), days)
    }

    /// Weather.app-style one-line summary for the hourly card.
    nonisolated static func summary(hours: [Hour], current: Current) -> String {
        if let rainy = hours.prefix(12).first(where: { ($0.rain ?? 0) >= 50 }) {
            let f = DateFormatter(); f.dateFormat = "h a"
            return rainy.time <= Date().addingTimeInterval(3600) ? "Rain likely within the hour." : "Rain likely around \(f.string(from: rainy.time))."
        }
        let later = hours.dropFirst(3).first.map { describe($0.code).text.lowercased() } ?? describe(current.code).text.lowercased()
        return "\(describe(current.code, isDay: current.isDay).text) now. \(later.prefix(1).uppercased() + later.dropFirst()) conditions later."
    }

    /// UV index -> Weather.app's words.
    nonisolated static func uvLevel(_ uv: Double) -> String {
        switch uv { case ..<3: "Low"; case ..<6: "Moderate"; case ..<8: "High"; case ..<11: "Very High"; default: "Extreme" }
    }

    /// WMO weather code -> SF Symbol and description.
    nonisolated static func describe(_ code: Int, isDay: Bool = true) -> (symbol: String, text: String) {
        switch code {
        case 0: (isDay ? "sun.max.fill" : "moon.stars.fill", "Clear")
        case 1: (isDay ? "sun.min.fill" : "moon.fill", "Mostly Clear")
        case 2: (isDay ? "cloud.sun.fill" : "cloud.moon.fill", "Partly Cloudy")
        case 3: ("cloud.fill", "Cloudy")
        case 45, 48: ("cloud.fog.fill", "Fog")
        case 51, 53, 55, 56, 57: ("cloud.drizzle.fill", "Drizzle")
        case 61, 63, 66: ("cloud.rain.fill", "Rain")
        case 65, 67: ("cloud.heavyrain.fill", "Heavy Rain")
        case 71, 73, 75, 77: ("cloud.snow.fill", "Snow")
        case 80, 81, 82: ("cloud.sun.rain.fill", "Showers")
        case 85, 86: ("cloud.snow.fill", "Snow Showers")
        case 95: ("cloud.bolt.fill", "Thunderstorm")
        case 96, 99: ("cloud.bolt.rain.fill", "Thunderstorm with Hail")
        default: ("cloud.fill", "—")
        }
    }
}
