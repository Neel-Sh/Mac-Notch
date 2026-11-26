import SwiftUI

struct WeatherPage: View {
    let service: WeatherService

    var body: some View {
        switch service.state {
        case .loaded(let forecast):
            ForecastView(forecast: forecast)
        case .needsLocation:
            message("location.slash", "Brim can't see your location",
                    "Allow it in System Settings › Privacy & Security › Location Services.") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocationServices") {
                    NSWorkspace.shared.open(url)
                }
            }
        case .failed(let reason):
            message("cloud.slash", reason, "Brim will try again in a moment.", action: service.refresh)
        case .idle, .locating:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking the sky…")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func message(_ symbol: String, _ title: String, _ detail: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.tertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.title(12.5))
                Text(detail).font(Theme.body(11)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            Button("Open", action: action).buttonStyle(PillButtonStyle(kind: .secondary))
        }
        .frame(maxHeight: .infinity)
    }
}

private struct ForecastView: View {
    let forecast: Forecast

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    now
                    metrics
                }
                .frame(width: 214, alignment: .leading)
                days
            }
            hours
        }
    }

    private var now: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(forecast.place).font(Theme.title(12.5))
                Text("as of \(forecast.fetchedAt.formatted(date: .omitted, time: .shortened))")
                    .font(Theme.body(10.5))
                    .foregroundStyle(Theme.tertiary)
            }
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: WeatherCode.symbol(forecast.code, isDay: forecast.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 26))
                    .frame(width: 30)
                Text("\(Int(forecast.temperature.rounded()))°")
                    .font(.system(size: 44, weight: .light, design: .rounded))
                    .tracking(-1.2)
                    .contentTransition(.numericText(value: forecast.temperature))
                VStack(alignment: .leading, spacing: 2) {
                    Text(WeatherCode.name(forecast.code))
                        .font(Theme.title(12))
                        .lineLimit(1)
                    if let today = forecast.days.first {
                        Text("H:\(Int(today.high.rounded()))°  L:\(Int(today.low.rounded()))°")
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(Theme.secondary)
                    }
                }
            }
        }
    }

    private var metrics: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
            GridRow {
                Metric(label: "Rain", value: "\(forecast.rainChanceNow)%")
                Metric(label: "Humidity", value: "\(forecast.humidity)%")
            }
            GridRow {
                Metric(label: "Feels like", value: "\(Int(forecast.feelsLike.rounded()))°")
                Metric(label: "Wind", value: "\(Int(forecast.windKmh.rounded())) km/h")
            }
        }
    }

    /// Each day's range on one shared scale, in the colours of its temperatures. Today marks where it is now.
    private var days: some View {
        let week = Array(forecast.days.prefix(5))
        let low = week.map(\.low).min() ?? 0
        let high = week.map(\.high).max() ?? 1
        return VStack(spacing: 5) {
            ForEach(Array(week.enumerated()), id: \.element.id) { index, day in
                HStack(spacing: 8) {
                    Text(index == 0 ? "Today" : day.date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.system(size: 11.5, weight: .semibold))
                        .frame(width: 42, alignment: .leading)
                    Image(systemName: WeatherCode.symbol(day.code))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 11.5))
                        .frame(width: 18)
                    Text(day.rainChance >= 20 ? "\(day.rainChance)%" : "")
                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color(red: 0.45, green: 0.75, blue: 1))
                        .frame(width: 30, alignment: .leading)
                    Text("\(Int(day.low.rounded()))°")
                        .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.secondary)
                        .frame(width: 26, alignment: .trailing)
                    RangeBar(low: day.low, high: day.high, scaleLow: low, scaleHigh: high,
                             now: index == 0 ? forecast.temperature : nil)
                    Text("\(Int(day.high.rounded()))°")
                        .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                        .frame(width: 26, alignment: .trailing)
                }
                .frame(height: 19)
            }
        }
    }

    private var hours: some View {
        HStack(spacing: 0) {
            ForEach(Array(forecast.hours.enumerated()), id: \.element.id) { index, hour in
                VStack(spacing: 4) {
                    Text(index == 0 ? "Now" : hour.time.formatted(.dateTime.hour()))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(index == 0 ? Theme.primary : Theme.secondary)
                    Image(systemName: WeatherCode.symbol(hour.code, isDay: hour.isDay))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 13))
                        .frame(height: 15)
                    Text("\(Int(hour.temperature.rounded()))°")
                        .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
    }
}

private struct Metric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.tertiary)
            Text(value)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
        }
        .frame(minWidth: 80, alignment: .leading)
    }
}

private struct RangeBar: View {
    let low: Double, high: Double, scaleLow: Double, scaleHigh: Double
    var now: Double?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let mid = geometry.size.height / 2
            let span = max(scaleHigh - scaleLow, 1)
            let x = { (value: Double) in min(max((value - scaleLow) / span, 0), 1) * width }
            let start = x(low), end = max(x(high), x(low) + 5)
            ZStack {
                Capsule().fill(Color.white.opacity(0.08))
                    .frame(width: width, height: 4)
                    .position(x: width / 2, y: mid)
                Capsule()
                    .fill(LinearGradient(colors: [Self.color(low), Self.color(high)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: end - start, height: 4)
                    .position(x: (start + end) / 2, y: mid)
                if let now {
                    Circle()
                        .fill(.white)
                        .overlay(Circle().stroke(.black, lineWidth: 1.5))
                        .frame(width: 7, height: 7)
                        .position(x: min(max(x(now), 3.5), width - 3.5), y: mid)
                }
            }
        }
        .frame(height: 7)
    }

    static func color(_ celsius: Double) -> Color {
        switch celsius {
        case ..<0: Color(red: 0.45, green: 0.68, blue: 1.0)
        case ..<10: Color(red: 0.38, green: 0.84, blue: 0.90)
        case ..<18: Color(red: 0.52, green: 0.88, blue: 0.48)
        case ..<26: Color(red: 1.0, green: 0.82, blue: 0.30)
        default: Color(red: 1.0, green: 0.50, blue: 0.28)
        }
    }
}

// MARK: - The sky inside the island

/// The weather, drawn into the island itself: rain that lands on the bottom edge, drifting snow,
/// a warm sun glow, stars at night. Decorative, behind the content, and still under Reduce Motion.
struct SkyBackdrop: View {
    let forecast: Forecast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let sky = WeatherCode.sky(forecast.code)
        ZStack {
            glow(sky)
            TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { context in
                Canvas { canvas, size in
                    let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                    switch sky {
                    case .rain, .storm:
                        Self.rain(in: &canvas, size: size, t: t, intensity: WeatherCode.intensity(forecast.code))
                    case .snow:
                        Self.snow(in: &canvas, size: size, t: t, intensity: WeatherCode.intensity(forecast.code))
                    case .clear where !forecast.isDay:
                        Self.stars(in: &canvas, size: size, t: t)
                    case .cloudy, .fog:
                        Self.mist(in: &canvas, size: size, t: t, dense: sky == .fog)
                    default:
                        break
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func glow(_ sky: WeatherCode.Sky) -> some View {
        switch sky {
        case .clear where forecast.isDay:
            RadialGradient(colors: [Color(red: 1, green: 0.78, blue: 0.35).opacity(0.22), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 360)
        case .rain, .storm:
            LinearGradient(colors: [.clear, Color(red: 0.3, green: 0.45, blue: 0.7).opacity(0.16)],
                           startPoint: .top, endPoint: .bottom)
        case .snow:
            LinearGradient(colors: [.clear, Color.white.opacity(0.07)], startPoint: .top, endPoint: .bottom)
        case .clear:
            RadialGradient(colors: [Color(red: 0.4, green: 0.45, blue: 0.9).opacity(0.14), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 360)
        default:
            Color.clear
        }
    }

    /// Deterministic per-particle randomness, so nothing is stored and nothing jumps between frames.
    private static func hash(_ i: Int, _ salt: Double) -> Double {
        let x = sin(Double(i) * 12.9898 + salt * 78.233) * 43758.5453
        return x - x.rounded(.down)
    }

    private static func rain(in canvas: inout GraphicsContext, size: CGSize, t: Double, intensity: Double) {
        let count = Int(40 + 90 * intensity)
        let slant = 0.18
        for i in 0..<count {
            let speed = 380 + hash(i, 1) * 260
            let length = 9 + hash(i, 2) * 12
            let travel = size.height + length
            let y = (hash(i, 3) * travel + t * speed).truncatingRemainder(dividingBy: travel) - length
            let x = hash(i, 4) * (size.width + 40) - 20 + y * slant
            var path = Path()
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x + length * slant, y: y + length))
            canvas.stroke(path, with: .color(.white.opacity(0.10 + 0.16 * hash(i, 5))), lineWidth: 1)
            // Drops that reach the bottom edge splash instead of vanishing.
            if y + length > size.height - 6 {
                let splash = CGRect(x: x + length * slant - 3, y: size.height - 3, width: 6, height: 2)
                canvas.fill(Path(ellipseIn: splash), with: .color(.white.opacity(0.12)))
            }
        }
    }

    private static func snow(in canvas: inout GraphicsContext, size: CGSize, t: Double, intensity: Double) {
        let count = Int(30 + 60 * intensity)
        for i in 0..<count {
            let speed = 18 + hash(i, 1) * 26
            let radius = 1 + hash(i, 2) * 1.8
            let travel = size.height + 10
            let y = (hash(i, 3) * travel + t * speed).truncatingRemainder(dividingBy: travel) - 5
            let x = hash(i, 4) * size.width + sin(t * (0.6 + hash(i, 5)) + Double(i)) * 8
            canvas.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)),
                        with: .color(.white.opacity(0.25 + 0.35 * hash(i, 6))))
        }
    }

    private static func stars(in canvas: inout GraphicsContext, size: CGSize, t: Double) {
        for i in 0..<40 {
            let x = hash(i, 1) * size.width
            let y = hash(i, 2) * size.height * 0.75
            let twinkle = 0.5 + 0.5 * sin(t * (0.5 + hash(i, 3)) + Double(i))
            let r = 0.6 + hash(i, 4) * 0.8
            canvas.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)),
                        with: .color(.white.opacity(0.08 + 0.28 * twinkle)))
        }
    }

    private static func mist(in canvas: inout GraphicsContext, size: CGSize, t: Double, dense: Bool) {
        canvas.addFilter(.blur(radius: 22))
        for i in 0..<5 {
            let width = size.width * (0.5 + hash(i, 1) * 0.4)
            let x = (hash(i, 2) * size.width + t * (6 + hash(i, 3) * 8)).truncatingRemainder(dividingBy: size.width + width) - width
            let y = size.height * (0.35 + hash(i, 4) * 0.6)
            let rect = CGRect(x: x, y: y - 30, width: width, height: 60)
            canvas.fill(Path(ellipseIn: rect), with: .color(.white.opacity(dense ? 0.10 : 0.06)))
        }
    }
}
