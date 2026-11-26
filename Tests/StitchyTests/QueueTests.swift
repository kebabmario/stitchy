// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import Stitchy

struct SpotifyAuthTests {
    @Test func pkceMatchesRFC7636Vector() {
        #expect(SpotifyAuth.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func callbackParsing() {
        let ok = SpotifyAuth.parseCallback("GET /callback?code=abc123&state=S1 HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n", expectedState: "S1")
        #expect(ok.code == "abc123" && ok.error == nil)
        #expect(SpotifyAuth.parseCallback("GET /callback?code=abc&state=EVIL HTTP/1.1\r\n", expectedState: "S1").code == nil)
        #expect(SpotifyAuth.parseCallback("GET /callback?error=access_denied&state=S1 HTTP/1.1\r\n", expectedState: "S1").error == "access_denied")
    }

    @Test func authorizeURLUsesPKCEAndLoopback() {
        let url = SpotifyAuth(clientID: "abc").authorizeURL().absoluteString
        #expect(url.contains("code_challenge_method=S256") && url.contains("client_id=abc"))
        #expect(url.contains("redirect_uri=http://127.0.0.1:43117/callback") || url.contains("redirect_uri=http%3A%2F%2F127.0.0.1%3A43117%2Fcallback"))
        #expect(!url.contains("client_secret"))
    }
}

struct SpotifyQueueParsingTests {
    @Test func parsesQueue() throws {
        let json = """
        {"currently_playing":{"name":"Now"},"queue":[
          {"name":"Next One","artists":[{"name":"A"},{"name":"B"}],"album":{"images":[{"url":"https://i.scdn.co/big","width":640},{"url":"https://i.scdn.co/small","width":64}]}},
          {"name":"Podcast Ep","show":{"name":"The Show"}}]}
        """
        let items = try QueueService.parseSpotifyQueue(Data(json.utf8))
        #expect(items.map(\.title) == ["Next One", "Podcast Ep"])
        #expect(items[0].artist == "A, B" && items[0].artworkURL?.absoluteString == "https://i.scdn.co/small")
        #expect(items[1].artist == "The Show" && items[1].artworkURL == nil)
    }
}

struct WeatherDailyFieldsTests {
    @Test func parsesSunriseSunsetUV() throws {
        let json = """
        {"utc_offset_seconds":0,"current":{"temperature_2m":10,"apparent_temperature":9,"relative_humidity_2m":50,"weather_code":0,"wind_speed_10m":5,"is_day":1},
         "hourly":{"time":["2030-01-01T10:00"],"temperature_2m":[10],"precipitation_probability":[0],"weather_code":[0]},
         "daily":{"time":["2030-01-01"],"weather_code":[0],"temperature_2m_max":[12],"temperature_2m_min":[4],"precipitation_probability_max":[0],
                  "sunrise":["2030-01-01T07:51"],"sunset":["2030-01-01T17:26"],"uv_index_max":[2.5]}}
        """
        let (_, _, days) = try WeatherService.parse(Data(json.utf8), now: .distantPast)
        #expect(days.first?.uv == 2.5 && days.first?.sunrise != nil && days.first?.sunset != nil)
        #expect(WeatherService.uvLevel(2.5) == "Low" && WeatherService.uvLevel(7) == "High")
    }
}
