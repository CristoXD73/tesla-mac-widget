import AppKit

/// Fetches the official render of the user's car from Tesla's configurator compositor,
/// trims the transparent margins and saves it as car.png in the App Group.
/// ~/.tesla-widget/overrides/car.png wins if present.
enum CarRender {
    static let overridesDir = Credentials.directory.appendingPathComponent("overrides")

    /// Copies your private icon overrides (icon-*.png) into the App Group so the sandboxed widget can use them.
    static func syncIconOverrides() {
        let fm = FileManager.default
        for old in (try? fm.contentsOfDirectory(at: Shared.container, includingPropertiesForKeys: nil)) ?? []
        where old.lastPathComponent.hasPrefix("override-icon-") {
            try? fm.removeItem(at: old)
        }
        for f in (try? fm.contentsOfDirectory(at: overridesDir, includingPropertiesForKeys: nil)) ?? []
        where f.lastPathComponent.hasPrefix("icon-") && f.pathExtension == "png" {
            try? fm.copyItem(at: f, to: Shared.file("override-" + f.lastPathComponent))
        }
    }

    static let infoURL = Credentials.directory.appendingPathComponent("vehicle-info.json")
    static var overrideURL: URL { overridesDir.appendingPathComponent("car.png") }
    static var outputURL: URL { Shared.file("car.png") }

    static func updateIfNeeded(force: Bool = false) async {
        if let data = try? Data(contentsOf: overrideURL), let img = NSImage(data: data) {
            save(trimmed(img) ?? img)
            return
        }
        guard force || !FileManager.default.fileExists(atPath: outputURL.path),
              let data = try? Data(contentsOf: infoURL),
              let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        for url in candidateURLs(info) {
            var req = URLRequest(url: url, timeoutInterval: 20)
            req.setValue("Mozilla/5.0 (Macintosh)", forHTTPHeaderField: "User-Agent")
            guard let (body, response) = try? await URLSession.shared.data(for: req),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  (response as? HTTPURLResponse)?.mimeType == "image/png",
                  let img = NSImage(data: body)
            else { continue }
            save(trimmed(img) ?? img)
            try? url.absoluteString.write(to: Credentials.directory.appendingPathComponent("car-render-url.txt"), atomically: true, encoding: .utf8)
            return
        }
    }

    // MARK: URL candidates

    static func candidateURLs(_ info: [String: Any]) -> [URL] {
        let config = info["vehicle_config"] as? [String: Any] ?? [:]
        let model = modelCode(config["car_type"] as? String)
        var optionSets: [[String]] = []

        // 1. The car's real option codes, as reported by Tesla.
        let codes = optionCodes(info["options"])
        if !codes.isEmpty { optionSets.append(codes) }
        // 2. Just paint + wheels from vehicle_config.
        let paint = paintCode(config["exterior_color"] as? String)
        let wheels = wheelCode(config["wheel_type"] as? String)
        optionSets.append([paint, wheels].compactMap { $0 })
        // 3. Just the paint.
        if let paint { optionSets.append([paint]) }

        return optionSets.compactMap { set in
            var c = URLComponents(string: "https://static-assets.tesla.com/configurator/compositor")!
            c.queryItems = [
                .init(name: "context", value: "design_studio_2"),
                .init(name: "options", value: set.joined(separator: ",")),
                .init(name: "view", value: "FRONT34"),
                .init(name: "model", value: model),
                .init(name: "size", value: "1400"),
                .init(name: "bkba_opt", value: "1"),
            ]
            return c.url
        }
    }

    static func optionCodes(_ options: Any?) -> [String] {
        let list = (options as? [String: Any])?["codes"] as? [[String: Any]] ?? options as? [[String: Any]] ?? []
        return list.compactMap { o in
            guard o["isActive"] as? Bool != false, let code = o["code"] as? String else { return nil }
            return code.hasPrefix("$") ? code : "$" + code
        }
    }

    static func modelCode(_ carType: String?) -> String {
        switch carType?.lowercased() ?? "" {
        case let t where t.contains("model3"): return "m3"
        case let t where t.contains("models"): return "ms"
        case let t where t.contains("modelx"): return "mx"
        case let t where t.contains("cyber"): return "ct"
        default: return "my"
        }
    }

    static func paintCode(_ color: String?) -> String? {
        let map: [String: String] = [
            "solidblack": "$PBSB", "obsidianblack": "$PMBL", "diamondblack": "$PX02",
            "pearlwhite": "$PPSW", "pearlwhitemulticoat": "$PPSW",
            "deepbluemetallic": "$PPSB", "deepblue": "$PPSB", "marineblue": "$PB02",
            "midnightsilvermetallic": "$PMNG", "midnightsilver": "$PMNG",
            "stealthgrey": "$PN01", "quicksilver": "$PN00",
            "redmulticoat": "$PPMR", "ultrared": "$PR01",
        ]
        guard let c = color?.lowercased().replacingOccurrences(of: " ", with: "") else { return nil }
        return map[c]
    }

    static func wheelCode(_ wheel: String?) -> String? {
        let map: [String: String] = [
            "gemini19": "$WY19B", "apollo19": "$WY19P", "induction20": "$WY20P",
            "uberturbine21": "$WY21P", "photon18": "$WY18P", "helix20": "$WY20A",
        ]
        guard let w = wheel?.lowercased() else { return nil }
        return map.first { w.hasPrefix($0.key) }?.value
    }

    // MARK: Image handling

    /// Crops fully transparent margins so the car fills the widget slot.
    static func trimmed(_ image: NSImage) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where pixels[(y * w + x) * 4 + 3] > 10 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX > minX, maxY > minY,
              let cropped = cg.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
        else { return nil }
        return NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
    }

    static func save(_ image: NSImage) {
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: outputURL, options: .atomic)
    }
}
