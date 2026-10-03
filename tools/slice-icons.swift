// Cuts the five control icons out of a screenshot of the Tesla app's widget/button row
// (lock, fan, frunk, trunk, HomeLink, left to right, light icons on a dark background)
// and saves them as ~/.tesla-widget/overrides/icon-*.png, plus an "unlocked" padlock.
// Usage: swift tools/slice-icons.swift ~/Desktop/tesla-buttons.png
import AppKit

let args = CommandLine.arguments
guard args.count >= 2, let image = NSImage(contentsOfFile: (args[1] as NSString).expandingTildeInPath),
      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("usage: swift tools/slice-icons.swift screenshot.png"); exit(1)
}
let out = args.count >= 3 ? URL(fileURLWithPath: args[2])
    : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".tesla-widget/overrides")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let W = cg.width, H = cg.height
var px = [UInt8](repeating: 0, count: W * H * 4)
let ctx = CGContext(data: &px, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))
func lum(_ x: Int, _ y: Int) -> Double { let i = (y * W + x) * 4; return (Double(px[i]) + Double(px[i+1]) + Double(px[i+2])) / 3 }

let bg = lum(2, 2)
var peak = bg
for y in 0..<H { for x in 0..<W { peak = max(peak, lum(x, y)) } }
let threshold = bg + (peak - bg) * 0.15
func ink(_ x: Int, _ y: Int) -> Bool { lum(x, y) > threshold }

// Group columns that contain icon pixels into icons (small gaps belong to the same icon).
var groups: [(Int, Int)] = []
var start: Int?
for x in 0...W {
    let has = x < W && (0..<H).contains { ink(x, $0) }
    if has, start == nil { start = x }
    if !has, let s = start {
        if let last = groups.last, s - last.1 < max(6, W / 100) { groups[groups.count - 1].1 = x } else { groups.append((s, x)) }
        start = nil
    }
}
guard groups.count == 5 else {
    print("Found \(groups.count) icons instead of 5. Crop the screenshot to just the row of five buttons and try again."); exit(1)
}
let rows = (0..<H).filter { y in (0..<W).contains { ink($0, y) } }
let y0 = max(0, rows.first! - 2), y1 = min(H, rows.last! + 3)

func save(_ name: String, x0: Int, x1: Int, transform: ((inout [UInt8], Int, Int) -> Void)? = nil) throws {
    let w = x1 - x0, h = y1 - y0
    var outPx = [UInt8](repeating: 0, count: w * h * 4)
    for y in 0..<h { for x in 0..<w {
        let a = UInt8(max(0, min(255, (lum(x0 + x, y0 + y) - bg) / (peak - bg) * 255)))
        let i = (y * w + x) * 4
        outPx[i] = a; outPx[i+1] = a; outPx[i+2] = a; outPx[i+3] = a // white, premultiplied
    } }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: w * 4, bitsPerPixel: 32)!
    outPx.withUnsafeBufferPointer { memcpy(rep.bitmapData!, $0.baseAddress!, w * h * 4) }
    try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("icon-\(name).png"))
    print("saved icon-\(name).png")
}

let names = ["lock", "fan", "frunk", "trunk", "homelink"]
for (name, g) in zip(names, groups) { try save(name, x0: max(0, g.0 - 2), x1: min(W, g.1 + 2)) }

// Unlocked padlock: lift the shackle and open its right leg.
if let lock = NSImage(contentsOf: out.appendingPathComponent("icon-lock.png")),
   let lcg = lock.cgImage(forProposedRect: nil, context: nil, hints: nil) {
    let w = lcg.width, h = lcg.height, lift = max(4, h / 7)
    var a = [UInt8](repeating: 0, count: w * h * 4)
    let c = CGContext(data: &a, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.draw(lcg, in: CGRect(x: 0, y: 0, width: w, height: h))
    // CGContext rows are top-down in memory here; find where the wide body starts.
    let fill = (0..<h).map { y in (0..<w).filter { a[(y * w + $0) * 4 + 3] > 128 }.count }
    let bodyTop = fill.firstIndex { $0 > fill.max()! * 8 / 10 } ?? h / 2
    let H2 = h + lift
    var o = [UInt8](repeating: 0, count: w * H2 * 4)
    func copyRow(_ from: Int, _ to: Int, maxX: Int = Int.max) {
        for x in 0..<min(w, maxX) { for k in 0..<4 { o[(to * w + x) * 4 + k] = max(o[(to * w + x) * 4 + k], a[(from * w + x) * 4 + k]) } }
    }
    for y in 0..<bodyTop { copyRow(y, y) }                       // shackle stays high
    for y in bodyTop..<h { copyRow(y, y + lift) }                // body moves down
    for d in 0...lift { copyRow(bodyTop - 1, bodyTop - 1 + d, maxX: w / 2) } // left leg only
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: H2, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: w * 4, bitsPerPixel: 32)!
    o.withUnsafeBufferPointer { memcpy(rep.bitmapData!, $0.baseAddress!, w * H2 * 4) }
    try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("icon-lock-open.png"))
    print("saved icon-lock-open.png")
}
print("Done. In the menu bar: 🚗 → Reload Car Image & Icons.")
