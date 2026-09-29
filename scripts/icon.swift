// Draws Popnote's icons from code, so they stay crisp at every size.
//
//   swift scripts/icon.swift <output-dir>
//
// Writes AppIcon.png (1024², full bleed, for tools that apply the shape
// themselves), AppIcon-rounded.png (the same art in Apple's standard icon
// shape and shadow, which is what goes in the app: macOS before 26 shows
// icons as they are), AppIcon-background.png and AppIcon-foreground.png (the
// full-bleed icon split in two layers), and MenuBarIcon.pdf (a black vector
// template).
import AppKit

let args = CommandLine.arguments
let outDir = URL(fileURLWithPath: args.count > 1 ? args[1] : ".")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: Int, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [
        CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, alpha,
    ])!
}

func gradient(_ stops: [(CGColor, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: stops.map(\.0) as CFArray, locations: stops.map(\.1))!
}

// MARK: Shapes (in a y-down space, card-relative where noted)

/// The note, with its bottom-right corner peeled away.
struct Card {
    let rect: CGRect
    var radius: CGFloat { rect.width * 0.15 }
    var fold: CGFloat { rect.width * 0.29 }

    /// Where the fold meets the right and bottom edges.
    var foldTop: CGPoint { CGPoint(x: rect.maxX, y: rect.maxY - fold) }
    var foldBottom: CGPoint { CGPoint(x: rect.maxX - fold, y: rect.maxY) }

    /// The fold line: nearly straight, with a barely visible bow towards the corner.
    var foldControl: CGPoint { CGPoint(x: rect.maxX - fold * 0.46, y: rect.maxY - fold * 0.46) }

    var body: CGPath {
        let r = radius, path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: foldTop, radius: r)
        path.addLine(to: foldTop)
        path.addQuadCurve(to: foldBottom, control: foldControl)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: r)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: r)
        path.closeSubpath()
        return path
    }

    /// The peeled corner folded back over the note: the missing corner
    /// mirrored across the fold line, with a rounded tip.
    var flap: CGPath {
        let tip = CGPoint(x: rect.maxX - fold, y: rect.maxY - fold)
        let path = CGMutablePath()
        path.move(to: foldTop)
        path.addArc(tangent1End: tip, tangent2End: foldBottom, radius: fold * 0.3)
        path.addLine(to: foldBottom)
        path.addQuadCurve(to: foldTop, control: foldControl)
        path.closeSubpath()
        return path
    }

    func point(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + u * rect.width, y: rect.minY + v * rect.height)
    }

    /// A quick pen stroke through points: straight runs, tight rounded turns.
    func stroke(_ points: [(CGFloat, CGFloat)], turn: CGFloat = 0.006) -> CGPath {
        let p = points.map { point($0.0, $0.1) }
        let path = CGMutablePath()
        path.move(to: p[0])
        for i in 1..<p.count - 1 {
            path.addArc(tangent1End: p[i], tangent2End: p[i + 1], radius: rect.width * turn)
        }
        path.addLine(to: p[p.count - 1])
        return path
    }

    /// A chunky, flat-topped lightning bolt.
    static let bolt: [(CGFloat, CGFloat)] = [
        (0.47, 0.11), (0.74, 0.11), (0.57, 0.40), (0.77, 0.40), (0.37, 0.90), (0.46, 0.54), (0.24, 0.54),
    ]

    var boltShape: CGPath {
        let path = CGMutablePath()
        path.addLines(between: Card.bolt.map { point($0.0, $0.1) })
        path.closeSubpath()
        return path
    }

    /// The bolt scribbled in: one pen stroke going back and forth across it,
    /// in passes slanted like handwriting, from the top down to the tip.
    var scribbledBolt: CGPath {
        let step: CGFloat = 0.05, jitter: CGFloat = 0.012, slope: CGFloat = 0.35
        // A fixed seed, so the wobble is the same on every run.
        var seed: UInt64 = 7
        func wobble() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return (CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1) - 0.5) * jitter
        }
        func dot(_ p: (CGFloat, CGFloat), _ q: (CGFloat, CGFloat)) -> CGFloat { p.0 * q.0 + p.1 * q.1 }
        let length = (1 + slope * slope).squareRoot()
        let along: (CGFloat, CGFloat) = (1 / length, -slope / length)
        let across: (CGFloat, CGFloat) = (slope / length, 1 / length)

        let poly = Card.bolt
        let depths = poly.map { dot($0, across) }
        var points: [(CGFloat, CGFloat)] = []
        var depth = depths.min()! + step * 0.4
        var fromLeft = false
        while depth < depths.max()! - step * 0.3 {
            // Where this pass enters and leaves the bolt.
            var hits: [CGFloat] = []
            for i in poly.indices {
                let a = poly[i], b = poly[(i + 1) % poly.count]
                let da = dot(a, across), db = dot(b, across)
                guard (da - depth) * (db - depth) <= 0, da != db else { continue }
                let f = (depth - da) / (db - da)
                hits.append(dot((a.0 + f * (b.0 - a.0), a.1 + f * (b.1 - a.1)), along))
            }
            if let lo = hits.min(), let hi = hits.max() {
                let inset = min(0.02, (hi - lo) / 4)
                let t = (fromLeft ? lo + inset : hi - inset) + wobble()
                let d = depth + wobble() * 0.4
                points.append((t * along.0 + d * across.0, t * along.1 + d * across.1))
            }
            fromLeft.toggle()
            depth += step
        }
        return stroke(points, turn: 0.005)
    }
}

// MARK: App icon

enum Layer { case all, background, foreground }

func drawAppIcon(_ ctx: CGContext, size s: CGFloat, layer: Layer) {
    ctx.translateBy(x: 0, y: s)
    ctx.scaleBy(x: 1, y: -1)
    let card = Card(rect: CGRect(x: s * 0.13, y: s * 0.13, width: s * 0.74, height: s * 0.74))

    if layer != .foreground {
        // Tokyo Night navy, a little lighter behind the note.
        ctx.drawLinearGradient(gradient([(color(0x1E2030), 0), (color(0x16161E), 1)]),
                               start: .zero, end: CGPoint(x: 0, y: s), options: [])
        ctx.drawRadialGradient(gradient([(color(0x7AA2F7, 0.16), 0), (color(0x7AA2F7, 0), 1)]),
                               startCenter: CGPoint(x: s / 2, y: s / 2), startRadius: 0,
                               endCenter: CGPoint(x: s / 2, y: s / 2), endRadius: s * 0.55, options: [])
    }
    guard layer != .background else { return }

    // Soft blue glow around the note.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.08, color: color(0x7AA2F7, 0.5))
    ctx.addPath(card.body)
    ctx.setFillColor(color(0x8FA9F0))
    ctx.fillPath()
    ctx.restoreGState()

    // Frosted-glass body: lighter at the top left.
    ctx.saveGState()
    ctx.addPath(card.body)
    ctx.clip()
    let r = card.rect
    ctx.drawLinearGradient(gradient([(color(0xB3C0F4), 0), (color(0x93AAF2), 0.5), (color(0x7A98E8), 1)]),
                           start: CGPoint(x: r.minX, y: r.minY), end: CGPoint(x: r.maxX, y: r.maxY), options: [])
    ctx.drawRadialGradient(gradient([(color(0xFFFFFF, 0.28), 0), (color(0xFFFFFF, 0), 1)]),
                           startCenter: card.point(0.22, 0.12), startRadius: 0,
                           endCenter: card.point(0.22, 0.12), endRadius: r.width * 0.6, options: [])
    // Shade where the flap lifts off.
    ctx.drawRadialGradient(gradient([(color(0x3D59A8, 0.35), 0), (color(0x3D59A8, 0), 1)]),
                           startCenter: CGPoint(x: r.maxX, y: r.maxY), startRadius: card.fold * 0.7,
                           endCenter: CGPoint(x: r.maxX, y: r.maxY), endRadius: card.fold * 1.6, options: [])
    // Bright rim, like the edge of a glass pane.
    ctx.addPath(card.body)
    ctx.setStrokeColor(color(0xFFFFFF, 0.45))
    ctx.setLineWidth(s * 0.006)
    ctx.strokePath()
    ctx.restoreGState()

    // The scribbled bolt.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.003), blur: s * 0.008, color: color(0x2A3F7A, 0.35))
    ctx.setStrokeColor(color(0xE4E8FF))
    ctx.setLineWidth(s * 0.024)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.addPath(card.scribbledBolt)
    ctx.strokePath()
    ctx.restoreGState()

    // The flap, casting a small shadow back onto the note.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: -s * 0.008, height: s * 0.008), blur: s * 0.02, color: color(0x1A2550, 0.45))
    ctx.addPath(card.flap)
    ctx.setFillColor(color(0xC9D2FA))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(card.flap)
    ctx.clip()
    ctx.drawLinearGradient(gradient([(color(0xB4C2F4), 0), (color(0xD6DDFB), 0.6), (color(0xF4F6FF), 1)]),
                           start: CGPoint(x: r.maxX - card.fold, y: r.maxY - card.fold),
                           end: CGPoint(x: r.maxX - card.fold * 0.4, y: r.maxY - card.fold * 0.4), options: [])
    ctx.restoreGState()
}

func writePNG(_ name: String, size: Int, layer: Layer) throws {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    drawAppIcon(ctx, size: CGFloat(size), layer: layer)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(name))
}

/// Apple's macOS icon grid: an 824pt rounded square centred on a 1024pt
/// canvas, with a soft drop shadow.
func writeRoundedPNG(_ name: String) throws {
    let size = 1024, s = CGFloat(size)
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: tile, cornerWidth: 185.4, cornerHeight: 185.4, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(0x000000, 0.3))
    ctx.addPath(shape)
    ctx.setFillColor(color(0x16161E))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.translateBy(x: tile.minX, y: tile.minY)
    ctx.scaleBy(x: tile.width / s, y: tile.height / s)
    drawAppIcon(ctx, size: s, layer: .all)
    ctx.restoreGState()

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(name))
}

// MARK: Menu bar icon

/// Black on transparent; AppKit tints it for light and dark menu bars.
func writeMenuBarPDF(_ name: String) {
    let s: CGFloat = 18
    var box = CGRect(x: 0, y: 0, width: s, height: s)
    let url = outDir.appendingPathComponent(name) as CFURL
    let ctx = CGContext(url, mediaBox: &box, nil)!
    ctx.beginPDFPage(nil)
    ctx.translateBy(x: 0, y: s)
    ctx.scaleBy(x: 1, y: -1)

    let line: CGFloat = 1.6
    let card = Card(rect: CGRect(x: 2 + line / 2, y: 2 + line / 2, width: 14 - line, height: 14 - line))
    ctx.setFillColor(color(0x000000))
    ctx.setStrokeColor(color(0x000000))
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    ctx.setLineWidth(line)
    ctx.addPath(card.body)
    ctx.strokePath()
    ctx.addPath(card.flap)
    ctx.fillPath()
    // A scribble turns to mush at 18pt, so the menu bar gets a solid bolt.
    ctx.addPath(card.boltShape)
    ctx.fillPath()

    ctx.endPDFPage()
    ctx.closePDF()
}

try writePNG("AppIcon.png", size: 1024, layer: .all)
try writeRoundedPNG("AppIcon-rounded.png")
try writePNG("AppIcon-background.png", size: 1024, layer: .background)
try writePNG("AppIcon-foreground.png", size: 1024, layer: .foreground)
writeMenuBarPDF("MenuBarIcon.pdf")
print("Wrote icons to \(outDir.path)")
