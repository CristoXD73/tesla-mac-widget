// Renders the README images from the widget's own views with made-up sample data.
// Run through tools/render-media.sh, which compiles this together with the widget code.
import AppKit
import MapKit
import SwiftUI

@main
struct RenderMedia {
    static let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/images")
    // Tesla's Palo Alto HQ, so no real person's location appears in the docs.
    static let coord = CLLocationCoordinate2D(latitude: 37.3947, longitude: -122.1503)

    static let sample: VehicleSnapshot = {
        var s = VehicleSnapshot(vin: "SAMPLE", name: "Model Y", state: "online",
                                stateCheckedAt: Date(), dataFetchedAt: Date().addingTimeInterval(-120))
        s.batteryLevel = 78; s.rangeMiles = 268; s.chargeLimit = 80; s.chargingState = "Disconnected"
        s.locked = true; s.sentry = true; s.climateOn = false; s.insideTempC = 21; s.outsideTempC = 17
        s.latitude = coord.latitude; s.longitude = coord.longitude; s.address = "1501 Page Mill Road"
        return s
    }()

    @MainActor
    static func main() async throws {
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: Shared.container, withIntermediateDirectories: true)
        // The public look: no private icon overrides.
        for f in (try? FileManager.default.contentsOfDirectory(at: Shared.container, includingPropertiesForKeys: nil)) ?? []
        where f.lastPathComponent.hasPrefix("override-icon-") { try? FileManager.default.removeItem(at: f) }

        try await fetchCar()
        try await renderMap()

        let now = Date()
        let small = tile(170, 170) { SmallView(s: sample, now: now) }
        let medium = tile(364, 170) { MediumView(s: sample, now: now) }
        let large = tile(364, 382) { LargeView(s: sample, now: now) }
        try save(small, "widget-small.png")
        try save(medium, "widget-medium.png")
        try save(large, "widget-large.png")

        let hero = HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 24) {
                medium
                small
            }
            large
        }
        .padding(36)
        .background(LinearGradient(colors: [Color(red: 0.16, green: 0.20, blue: 0.24), Color(red: 0.07, green: 0.09, blue: 0.11)],
                                   startPoint: .top, endPoint: .bottom))
        try save(AnyView(hero), "hero.png")
        print("Wrote images to \(out.path)")
    }

    /// One desktop widget: smoked-glass tile with the standard 16 pt margins.
    static func tile<V: View>(_ w: CGFloat, _ h: CGFloat, @ViewBuilder _ content: () -> V) -> AnyView {
        AnyView(
            content()
                .padding(16)
                .frame(width: w, height: h, alignment: .topLeading)
                .foregroundStyle(.white)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(white: 0.11).opacity(0.94)))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.08)))
                .environment(\.colorScheme, .dark)
        )
    }

    @MainActor
    static func save(_ view: AnyView, _ name: String) throws {
        let r = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        r.scale = 2
        guard let cg = r.cgImage else { throw NSError(domain: "render", code: 1) }
        let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
        try png.write(to: out.appendingPathComponent(name))
    }

    /// Official render of an Ultra Red Model Y from Tesla's configurator, trimmed like the app does.
    static func fetchCar() async throws {
        let url = URL(string: "https://static-assets.tesla.com/configurator/compositor?context=design_studio_2&options=$IPB8,$PR01,$WY19P,$MTY67,$STY5S&view=FRONT34&model=my&size=1400&bkba_opt=1")!
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (Macintosh)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let img = NSImage(data: data) else { throw NSError(domain: "car", code: 1) }
        CarRender.save(CarRender.trimmed(img) ?? img)
    }

    static func renderMap() async throws {
        let o = MKMapSnapshotter.Options()
        o.region = MKCoordinateRegion(center: coord, latitudinalMeters: 500, longitudinalMeters: 500)
        o.size = NSSize(width: 640, height: 300)
        o.appearance = NSAppearance(named: .darkAqua)
        o.pointOfInterestFilter = .excludingAll
        let shot = try await MKMapSnapshotter(options: o).start()
        let p = shot.point(for: coord), size = shot.image.size
        let img = NSImage(size: size, flipped: false) { rect in
            shot.image.draw(in: rect)
            let c = NSPoint(x: p.x, y: size.height - p.y), r: CGFloat = 9
            NSColor.white.setFill(); NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)).fill()
            NSColor.systemRed.setFill(); NSBezierPath(ovalIn: NSRect(x: c.x - r + 3, y: c.y - r + 3, width: (r - 3) * 2, height: (r - 3) * 2)).fill()
            return true
        }
        let png = NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        try png.write(to: Shared.file("map-dark.png"))
    }
}
