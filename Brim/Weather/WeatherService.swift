import CoreLocation
import Foundation
import Observation

struct Forecast: Equatable {
    struct Hour: Equatable, Identifiable {
        var id: Date { time }
        let time: Date
        let temperature: Double
        let code: Int
        let isDay: Bool
        let rainChance: Int
    }

    struct Day: Equatable, Identifiable {
        var id: Date { date }
        let date: Date
        let low: Double
        let high: Double
        let code: Int
        let rainChance: Int
    }

    let place: String
    let temperature: Double
    let feelsLike: Double
    let humidity: Int
    let windKmh: Double
    let rainChanceNow: Int
    let sunrise: Date?
    let sunset: Date?
    let code: Int
    let isDay: Bool
    let hours: [Hour]
    let days: [Day]
    let fetchedAt: Date
}

/// Current conditions from Open-Meteo (free, no key) for wherever this Mac is.
@Observable
final class WeatherService: NSObject, CLLocationManagerDelegate {
    enum State: Equatable {
        case idle
        case locating
        case loaded(Forecast)
        case needsLocation
        case failed(String)
    }

    private(set) var state: State = .idle

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var lastLocation: CLLocation?
    @ObservationIgnored private var timer: Timer?

    var forecast: Forecast? {
        if case .loaded(let forecast) = state { return forecast }
        return nil
    }

    func start() {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        timer = Timer.scheduledTimer(withTimeInterval: 20 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshIfAllowed() }
        }
        refreshIfAllowed()
    }

    /// Background refreshes never prompt; only opening the weather page does.
    private func refreshIfAllowed() {
        guard [.authorizedAlways, .authorized].contains(manager.authorizationStatus) else { return }
        manager.requestLocation()
    }

    /// Ask for location only when the person looks at weather, never at launch out of nowhere.
    func refresh() {
        switch manager.authorizationStatus {
        case .notDetermined:
            state = .locating
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            state = .needsLocation
        default:
            if forecast == nil { state = .locating }
            manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .denied, .restricted: self.state = .needsLocation
            case .notDetermined: break
            default: self.manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in await self.load(for: location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if self.forecast == nil { self.state = .failed("Couldn't find your location.") }
        }
    }

    private func load(for location: CLLocation) async {
        lastLocation = location
        let c = location.coordinate
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(format: "%.2f", c.latitude)),
            .init(name: "longitude", value: String(format: "%.2f", c.longitude)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day,relative_humidity_2m,wind_speed_10m"),
            .init(name: "hourly", value: "temperature_2m,weather_code,is_day,precipitation_probability"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "6"),
            .init(name: "timeformat", value: "unixtime"),
        ]
        do {
            let (data, _) = try await URLSession.shared.data(from: components.url!)
            let place = await Self.placeName(for: location)
            guard let forecast = Self.parse(data, place: place) else {
                state = .failed("Weather is unavailable right now.")
                return
            }
            state = .loaded(forecast)
        } catch {
            if forecast == nil { state = .failed("Weather is unavailable right now.") }
        }
    }

    private static func placeName(for location: CLLocation) async -> String {
        let marks = try? await CLGeocoder().reverseGeocodeLocation(location)
        return marks?.first?.locality ?? marks?.first?.name ?? "Here"
    }

    private static func parse(_ data: Data, place: String) -> Forecast? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let current = root["current"] as? [String: Any],
            let hourly = root["hourly"] as? [String: Any],
            let daily = root["daily"] as? [String: Any]
        else { return nil }

        func numbers(_ object: [String: Any], _ key: String) -> [Double] {
            (object[key] as? [Any] ?? []).map { ($0 as? NSNumber)?.doubleValue ?? 0 }
        }

        let now = Date.now
        let hourTimes = numbers(hourly, "time").map { Date(timeIntervalSince1970: $0) }
        let hourTemps = numbers(hourly, "temperature_2m")
        let hourCodes = numbers(hourly, "weather_code")
        let hourDay = numbers(hourly, "is_day")
        let hourRain = numbers(hourly, "precipitation_probability")
        let start = hourTimes.firstIndex { $0 > now.addingTimeInterval(-3600) } ?? 0
        let hours = (start..<min(start + 7, hourTimes.count)).map {
            Forecast.Hour(time: hourTimes[$0], temperature: hourTemps[$0], code: Int(hourCodes[$0]),
                          isDay: hourDay[$0] > 0, rainChance: $0 < hourRain.count ? Int(hourRain[$0]) : 0)
        }

        let dayTimes = numbers(daily, "time").map { Date(timeIntervalSince1970: $0) }
        let highs = numbers(daily, "temperature_2m_max")
        let lows = numbers(daily, "temperature_2m_min")
        let dayCodes = numbers(daily, "weather_code")
        let rain = numbers(daily, "precipitation_probability_max")
        let days = dayTimes.indices.map {
            Forecast.Day(date: dayTimes[$0], low: lows[$0], high: highs[$0], code: Int(dayCodes[$0]), rainChance: Int(rain[$0]))
        }

        let sunrises = numbers(daily, "sunrise").map { Date(timeIntervalSince1970: $0) }
        let sunsets = numbers(daily, "sunset").map { Date(timeIntervalSince1970: $0) }

        return Forecast(
            place: place,
            temperature: (current["temperature_2m"] as? NSNumber)?.doubleValue ?? 0,
            feelsLike: (current["apparent_temperature"] as? NSNumber)?.doubleValue ?? 0,
            humidity: (current["relative_humidity_2m"] as? NSNumber)?.intValue ?? 0,
            windKmh: (current["wind_speed_10m"] as? NSNumber)?.doubleValue ?? 0,
            rainChanceNow: hours.first?.rainChance ?? 0,
            sunrise: sunrises.first,
            sunset: sunsets.first,
            code: (current["weather_code"] as? NSNumber)?.intValue ?? 0,
            isDay: ((current["is_day"] as? NSNumber)?.intValue ?? 1) > 0,
            hours: hours,
            days: days,
            fetchedAt: now
        )
    }
}

/// WMO weather codes, as Open-Meteo reports them.
enum WeatherCode {
    enum Sky { case clear, cloudy, fog, rain, snow, storm }

    static func sky(_ code: Int) -> Sky {
        switch code {
        case 0, 1: .clear
        case 2, 3: .cloudy
        case 45, 48: .fog
        case 51...67, 80...82: .rain
        case 71...77, 85, 86: .snow
        case 95...99: .storm
        default: .cloudy
        }
    }

    /// 0...1, how hard it's coming down, for the island's rain and snow.
    static func intensity(_ code: Int) -> Double {
        switch code {
        case 51, 56, 61, 66, 71, 80, 85: 0.35
        case 53, 63, 73, 81: 0.65
        case 55, 57, 65, 67, 75, 82, 86, 95...99: 1
        default: 0.5
        }
    }

    static func symbol(_ code: Int, isDay: Bool = true) -> String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...57: "cloud.drizzle.fill"
        case 61...67, 80...82: "cloud.rain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    static func name(_ code: Int) -> String {
        switch code {
        case 0: "Clear"
        case 1: "Mostly Clear"
        case 2: "Partly Cloudy"
        case 3: "Cloudy"
        case 45, 48: "Fog"
        case 51...57: "Drizzle"
        case 61...67: "Rain"
        case 80...82: "Showers"
        case 71...77, 85, 86: "Snow"
        case 95...99: "Thunderstorms"
        default: "Cloudy"
        }
    }
}
