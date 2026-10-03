import AppIntents
import SwiftUI
import WidgetKit

@main
struct TeslaWidgetBundle: WidgetBundle {
    var body: some Widget { TeslaWidget() }
}

struct TeslaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Shared.widgetKind, provider: Provider()) { entry in
            TeslaWidgetView(entry: entry)
                .environment(\.colorScheme, .dark)
                .widgetURL(URL(string: "teslawidget://open-tesla"))
                .containerBackground(for: .widget) {
                    // Tesla's widget is white text on smoked glass.
                    ZStack {
                        Rectangle().fill(.ultraThinMaterial)
                        Color.black.opacity(0.35)
                    }
                }
        }
        .configurationDisplayName("Tesla")
        .description("Battery, location, Sentry and quick controls, like the Tesla app widget.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Timeline

struct Entry: TimelineEntry {
    var date: Date
    var snapshot: VehicleSnapshot?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: Date(), snapshot: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date(), snapshot: Shared.load(VehicleSnapshot.self, VehicleSnapshot.file) ?? .sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // The app reloads timelines whenever it has new data; the extra entries keep "x mins." current.
        let snap = Shared.load(VehicleSnapshot.self, VehicleSnapshot.file)
        let entries = (0..<15).map { Entry(date: Date().addingTimeInterval(Double($0) * 60), snapshot: snap) }
        completion(Timeline(entries: entries, policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

extension VehicleSnapshot {
    static let sample = VehicleSnapshot(
        vin: "SAMPLE", name: "Tesla", state: "online", stateCheckedAt: Date(), dataFetchedAt: Date(),
        batteryLevel: 78, rangeMiles: 241, chargeLimit: 80, chargingState: "Disconnected",
        locked: true, sentry: true, climateOn: false, insideTempC: 21, outsideTempC: 17, address: "Home"
    )
}

// MARK: - Views

struct TeslaWidgetView: View {
    var entry: Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let s = entry.snapshot {
                switch family {
                case .systemSmall: SmallView(s: s, now: entry.date)
                case .systemLarge: LargeView(s: s, now: entry.date)
                default: MediumView(s: s, now: entry.date)
                }
            } else {
                VStack(spacing: 6) {
                    CarImage().frame(height: 50)
                    Text("Open Tesla Widget to set up").font(.caption).multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.white)
    }
}

private struct MediumView: View {
    var s: VehicleSnapshot
    var now: Date

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                Summary(s: s)
                Spacer(minLength: 4)
                CarImage()
                    .frame(maxWidth: 170, maxHeight: 82)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Text(s.ageText(now: now)).font(.system(size: 10, weight: .medium)).opacity(0.8)
            }
            .padding(.bottom, 4)
            ControlBar(s: s)
        }
    }
}

private struct LargeView: View {
    var s: VehicleSnapshot
    var now: Date

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 0) {
                Summary(s: s)
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    if let r = s.rangeText { Text(r).font(.system(size: 13, weight: .medium)) }
                    if let t = s.temperature(s.insideTempC) {
                        Text("\(t) inside").font(.system(size: 11)).opacity(0.75)
                    }
                }
            }
            CarImage().frame(maxWidth: .infinity, maxHeight: 120)
            MapTile(s: s)
            HStack {
                Spacer()
                Text(s.ageText(now: now)).font(.system(size: 10, weight: .medium)).opacity(0.8)
            }
            ControlBar(s: s)
        }
    }
}

private struct SmallView: View {
    var s: VehicleSnapshot
    var now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(s.name.uppercased())
                .font(.system(size: 15, weight: .semibold)).kerning(0.6).lineLimit(1)
            BatteryRow(s: s, size: 14)
            CarImage().frame(maxWidth: .infinity, maxHeight: 54)
            Spacer(minLength: 0)
            HStack {
                StatusRow(s: s, compact: true)
                Spacer()
                Text(s.ageText(now: now)).font(.system(size: 9, weight: .medium)).opacity(0.8)
            }
        }
    }
}

/// Name, battery, address and status, stacked like the Tesla app widget.
private struct Summary: View {
    var s: VehicleSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(s.name.uppercased())
                    .font(.system(size: 21, weight: .semibold)).kerning(0.8).lineLimit(1)
                    .minimumScaleFactor(0.7)
                if s.state == "asleep" || s.state == "offline" {
                    Image(systemName: s.state == "asleep" ? "moon.zzz.fill" : "wifi.slash")
                        .font(.system(size: 11)).opacity(0.7)
                }
            }
            BatteryRow(s: s, size: 15)
            if let a = s.address {
                Text(a).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
            }
            StatusRow(s: s, compact: false)
        }
    }
}

private struct BatteryRow: View {
    var s: VehicleSnapshot
    var size: CGFloat

    var body: some View {
        HStack(spacing: 7) {
            BatteryGlyph(level: s.batteryLevel ?? 0, charging: s.isCharging)
                .frame(width: size * 1.75, height: size * 0.72)
            Text(s.batteryLevel.map { "\($0) %" } ?? "-- %")
                .font(.system(size: size, weight: .regular))
        }
    }
}

/// Tesla-style horizontal battery: white fill, dim remainder, small nub.
private struct BatteryGlyph: View {
    var level: Int
    var charging: Bool

    var body: some View {
        GeometryReader { g in
            let body = g.size.width - 3
            HStack(spacing: 1) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: g.size.height * 0.28).fill(.white.opacity(0.28))
                    RoundedRectangle(cornerRadius: g.size.height * 0.28)
                        .fill(charging ? Color.green : (level <= 20 ? .red : .white))
                        .frame(width: max(2, body * CGFloat(level) / 100))
                }
                .frame(width: body)
                RoundedRectangle(cornerRadius: 1).fill(.white.opacity(0.28))
                    .frame(width: 2, height: g.size.height * 0.45)
            }
        }
        .widgetAccentable()
    }
}

private struct StatusRow: View {
    var s: VehicleSnapshot
    var compact: Bool

    var body: some View {
        let font = Font.system(size: compact ? 10 : 12.5, weight: .medium)
        if let err = s.lastError, let at = s.lastErrorAt, at.timeIntervalSinceNow > -300 {
            Label(err, systemImage: "exclamationmark.triangle.fill")
                .font(font).foregroundStyle(.orange).lineLimit(1)
        } else if s.sentry == true {
            HStack(spacing: 6) {
                Image(nsImage: SentryDot.image)
                    .resizable()
                    .widgetAccentedRenderingMode(.fullColor) // stay red on the tinted desktop
                    .frame(width: compact ? 11 : 15, height: compact ? 11 : 15)
                Text("Sentry").font(font)
            }
        } else {
            HStack(spacing: 4) {
                if s.isCharging { Image(systemName: "bolt.fill").foregroundStyle(.green) }
                Text(compact ? (s.locked == false ? "Unlocked" : "Locked") : statusText).font(font).lineLimit(1)
            }
        }
    }

    private var statusText: String {
        if s.isCharging || s.isDriving || s.state != "online" { return s.statusLine }
        return s.locked == false ? "Unlocked" : "Locked"
    }
}

/// Tesla's Sentry indicator: red dot in a light ring. Drawn as an image so it can opt out of tinting.
private enum SentryDot {
    static let image = NSImage(size: NSSize(width: 30, height: 30), flipped: false) { r in
        let ring = NSBezierPath(ovalIn: r.insetBy(dx: 1.5, dy: 1.5))
        ring.lineWidth = 3
        NSColor(white: 1, alpha: 0.55).setStroke(); ring.stroke()
        NSColor(red: 0.93, green: 0.22, blue: 0.27, alpha: 1).setFill()
        NSBezierPath(ovalIn: r.insetBy(dx: 6, dy: 6)).fill()
        return true
    }
}

/// The official render of this car, generated by the app from Tesla's configurator.
private struct CarImage: View {
    var body: some View {
        if let img = NSImage(contentsOf: Shared.file("car.png")) {
            Image(nsImage: img).resizable().interpolation(.high)
                .widgetAccentedRenderingMode(.fullColor) // keep the real paint on the tinted desktop
                .scaledToFit()
        } else {
            Image(systemName: "car.side.fill").resizable().scaledToFit().opacity(0.5)
        }
    }
}

/// Tesla-style control row: five evenly spaced grey icons, no outline.
/// Uses your own icons from ~/.tesla-widget/overrides (copied in by the app) when present,
/// otherwise Apple's built-in look-alikes.
private struct ControlBar: View {
    var s: VehicleSnapshot

    var body: some View {
        let locked = s.locked != false
        HStack(spacing: 0) {
            Cell(icon: locked ? "lock" : "lock-open", symbol: locked ? "lock.fill" : "lock.open.fill",
                 label: locked ? "Unlock" : "Lock",
                 command: locked ? "unlock" : "lock",
                 pending: s.isPending("lock") || s.isPending("unlock"))
            Cell(icon: "fan", symbol: "fanblades.fill",
                 label: s.climateOn == true ? "Climate off" : "Climate on",
                 command: s.climateOn == true ? "climate_off" : "climate_on",
                 active: s.climateOn == true,
                 pending: s.isPending("climate_on") || s.isPending("climate_off"))
            // Built-in symbols are mirrored so the open frunk and trunk face each other.
            Cell(icon: "frunk", symbol: "car.side.front.open", mirrorSymbol: true,
                 label: "Frunk", command: "frunk", pending: s.isPending("frunk"))
            Cell(icon: "trunk", symbol: "car.side.rear.open", mirrorSymbol: true,
                 label: "Trunk", command: "trunk", pending: s.isPending("trunk"))
            Cell(icon: "homelink", symbol: "av.remote.fill",
                 label: "HomeLink", command: "homelink", pending: s.isPending("homelink"))
        }
        .frame(height: 34)
    }

    private struct Cell: View {
        var icon: String
        var symbol: String
        var mirrorSymbol = false
        var label: String
        var command: String
        var active = false
        var pending = false

        var body: some View {
            Button(intent: CarCommandIntent(command)) {
                glyph
                    .foregroundStyle(active ? Color(red: 0.25, green: 0.55, blue: 1) : Color(white: 0.56))
                    .opacity(pending ? 0.4 : 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(label)
            .accessibilityLabel(label)
        }

        @ViewBuilder private var glyph: some View {
            if let custom = NSImage(contentsOf: Shared.file("override-icon-\(icon).png")) {
                let h = 20 * custom.size.height / max(1, Self.referenceHeight)
                Image(nsImage: custom)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    // Taller icons (e.g. an open padlock) keep the same scale and sit on the same baseline.
                    .frame(height: max(20, h))
                    .offset(y: h > 20 ? -(h - 20) / 2 : 0)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .regular))
                    .scaleEffect(x: mirrorSymbol ? -1 : 1)
            }
        }

        /// Height of the closed-lock override, used as the common scale for all custom icons.
        static var referenceHeight: CGFloat {
            NSImage(contentsOf: Shared.file("override-icon-lock.png"))?.size.height ?? 20
        }
    }
}

private struct MapTile: View {
    var s: VehicleSnapshot

    var body: some View {
        // Fixed-size base so the scaled-to-fill map can't push the address chip out of view.
        Color.white.opacity(0.08)
            .frame(maxWidth: .infinity, minHeight: 70, maxHeight: .infinity)
            .overlay {
                if let img = NSImage(contentsOf: Shared.file("map-dark.png")) {
                    Image(nsImage: img).resizable()
                        .widgetAccentedRenderingMode(.fullColor) // otherwise the desktop tints it to a flat block
                        .scaledToFill()
                } else {
                    Image(systemName: "location.fill").opacity(0.5)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if let a = s.address {
                    // Address chip over the map, like the Tesla app's location card.
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill").font(.system(size: 9))
                        Text(a).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

extension VehicleSnapshot {
    /// "2 secs.", "5 mins.", "3 hrs." like the Tesla widget.
    func isPending(_ command: String) -> Bool {
        pendingCommand == command && (pendingSince?.timeIntervalSinceNow ?? -999) > -45
    }

    func ageText(now: Date) -> String {
        if pendingCommand != nil, let p = pendingSince, now.timeIntervalSince(p) < 45 { return "Sending…" }
        guard let d = dataFetchedAt else { return "" }
        let s = max(0, Int(now.timeIntervalSince(d)))
        switch s {
        case ..<60: return "\(s) sec\(s == 1 ? "" : "s")."
        case ..<3600: return "\(s / 60) min\(s / 60 == 1 ? "" : "s")."
        case ..<86400: return "\(s / 3600) hr\(s / 3600 == 1 ? "" : "s")."
        default: return "\(s / 86400) day\(s / 86400 == 1 ? "" : "s")."
        }
    }
}
