// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct WeatherView: View {
    @Environment(WeatherService.self) private var weather
    @Environment(AppSettings.self) private var settings
    @State private var choosing = false

    var body: some View {
        Group {
            if !settings.weatherEnabled || weather.place == nil || choosing {
                LocationPicker(done: { choosing = false })
            } else if let c = weather.current {
                forecast(c)
            } else if case .failed(let m) = weather.status {
                VStack(spacing: 8) {
                    Text(m).font(.system(size: 12)).foregroundStyle(Color.secondaryText)
                    PillButton(title: "Try Again") { Task { await weather.refresh() } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func forecast(_ c: WeatherService.Current) -> some View {
        WeatherPanel(current: c, choose: { choosing = true })
    }
}

/// Weather in Stitchy's style: the temperature large on the left, the next
/// hours in a well, a 7-day strip and a line of details. Fits without scrolling.
private struct WeatherPanel: View {
    let current: WeatherService.Current
    let choose: () -> Void
    @Environment(WeatherService.self) private var weather
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let d = WeatherService.describe(current.code, isDay: current.isDay)
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(alignment: .top, spacing: DS.Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Button(action: choose) {
                        HStack(spacing: 3) {
                            Text(weather.place?.name.components(separatedBy: ",").first ?? "").font(DS.title).lineLimit(1)
                            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(Color.tertiaryText)
                        }
                    }
                    .buttonStyle(.plainHit)
                    .help("Change location")
                    HStack(alignment: .center, spacing: 6) {
                        Text("\(Int(current.temperature.rounded()))°").font(DS.numerals(50, weight: .medium))
                        Image(systemName: d.symbol).symbolRenderingMode(.multicolor).font(.system(size: 26))
                    }
                    Text(d.text).font(DS.body).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                    if let today = weather.days.first {
                        Text("H \(Int(today.high.rounded()))°  ·  L \(Int(today.low.rounded()))°")
                            .font(DS.caption).foregroundStyle(Color.secondaryText)
                    }
                }
                .frame(width: 160, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Next hours")
                    Text(WeatherService.summary(hours: weather.hours, current: current))
                        .font(DS.caption).foregroundStyle(Color.secondaryText).lineLimit(1)
                    HStack(spacing: 0) {
                        ForEach(Array(weather.hours.prefix(6).enumerated()), id: \.offset) { i, h in
                            VStack(spacing: 3) {
                                Text(i == 0 ? "Now" : h.time.formatted(.dateTime.hour()))
                                    .font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Color.secondaryText)
                                Image(systemName: WeatherService.describe(h.code).symbol).symbolRenderingMode(.multicolor)
                                    .font(.system(size: 13)).frame(height: 17)
                                Text(h.rain.map { $0 >= 30 ? "\($0)%" : " " } ?? " ")
                                    .font(.system(size: 8.5, weight: .bold)).foregroundStyle(.cyan).frame(height: 10)
                                Text("\(Int(h.temperature.rounded()))°").font(DS.numerals(12, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .well(padding: 10)
            }

            HStack(spacing: 0) {
                ForEach(Array(weather.days.prefix(7).enumerated()), id: \.offset) { i, day in
                    VStack(spacing: 3) {
                        Text(i == 0 ? "Today" : day.date.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.system(size: 9.5, weight: .semibold)).foregroundStyle(i == 0 ? .white : Color.secondaryText)
                        Image(systemName: WeatherService.describe(day.code).symbol).symbolRenderingMode(.multicolor)
                            .font(.system(size: 13)).frame(height: 17)
                        HStack(spacing: 3) {
                            Text("\(Int(day.high.rounded()))°")
                            Text("\(Int(day.low.rounded()))°").foregroundStyle(Color.tertiaryText)
                        }
                        .font(DS.numerals(10.5, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .well(padding: 8)

            HStack(spacing: DS.Space.m) {
                stat("thermometer.medium", "Feels \(Int(current.feelsLike.rounded()))°")
                stat("humidity", "\(current.humidity)%")
                stat("wind", "\(Int(current.wind.rounded())) \(settings.weatherFahrenheit ? "mph" : "km/h")")
                if let uv = weather.days.first?.uv { stat("sun.max", "UV \(Int(uv.rounded()))") }
                if let set = weather.days.first?.sunset { stat("sunset.fill", set.formatted(date: .omitted, time: .shortened)) }
                Spacer(minLength: 0)
                Text("Open-Meteo").font(.system(size: 9)).foregroundStyle(Color.tertiaryText)
            }
        }
        .foregroundStyle(.white)
    }

    private func stat(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(DS.caption).foregroundStyle(Color.secondaryText)
            .labelStyle(.titleAndIcon).lineLimit(1)
    }
}

/// Explicit location choice: one-shot current location, or a city.
private struct LocationPicker: View {
    let done: () -> Void
    @Environment(WeatherService.self) private var weather
    @Environment(AppSettings.self) private var settings
    @State private var query = ""

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                SearchField(text: $query, prompt: "Search for a city", focusToken: 0) { Task { await weather.search(query) } }
                    .onChange(of: query) { _, q in Task { try? await Task.sleep(for: .milliseconds(300)); if q == query { await weather.search(q) } } }
                PillButton(title: weather.status == .locating ? "Locating…" : "Use My Location", symbol: "location.fill") {
                    settings.weatherEnabled = true
                    weather.useCurrentLocation()
                }
            }
            if weather.searchResults.isEmpty {
                VStack(spacing: 4) {
                    EmptyState(symbol: "cloud.sun.fill", tint: .yellow, title: "Weather",
                               message: "Search for a city, or use your location once (sent only as rounded coordinates). Data from Open-Meteo.")
                    if case .failed(let m) = weather.status { Text(m).font(DS.caption).foregroundStyle(.orange) }
                }
            } else {
                IslandScroll(axis: .vertical) {
                    VStack(spacing: 2) {
                        ForEach(weather.searchResults, id: \.name) { p in
                            Button {
                                settings.weatherEnabled = true
                                weather.setPlace(p)
                                done()
                            } label: {
                                Text(p.name).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8).padding(.vertical, 5).modifier(HoverHighlight(cornerRadius: 8))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plainHit)
                        }
                    }
                }
            }
        }
        .onChange(of: weather.place) { _, p in if p != nil { done() } }
    }
}
