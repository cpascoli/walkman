import AppKit
import CoreGraphics

/// Renders the Walkman app icon: a cassette, drawn at 1024pt.
/// Three variants — the standard icon, a darker one for dark mode, and a
/// grayscale one the system tints itself.
enum Variant { case standard, dark, tinted }

func render(_ variant: Variant, to path: String) {
    let size = 1024
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8,
        bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("no context") }

    func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
        if case .tinted = variant {
            // Tinted icons are grayscale; the system supplies the hue.
            let l = 0.299 * r + 0.587 * g + 0.114 * b
            return CGColor(red: l, green: l, blue: l, alpha: a)
        }
        return CGColor(red: r, green: g, blue: b, alpha: a)
    }

    let W = Double(size)

    // MARK: Background
    let bgTop: CGColor
    let bgBottom: CGColor
    switch variant {
    case .standard:
        bgTop = CGColor(red: 0.20, green: 0.20, blue: 0.23, alpha: 1)
        bgBottom = CGColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
    case .dark:
        bgTop = CGColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1)
        bgBottom = CGColor(red: 0.03, green: 0.03, blue: 0.04, alpha: 1)
    case .tinted:
        bgTop = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        bgBottom = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
    }
    // Only the standard icon carries its own background. The dark and tinted
    // variants are composited onto a system-supplied backdrop, so they stay
    // transparent behind the cassette.
    if case .standard = variant,
       let grad = CGGradient(colorsSpace: cs, colors: [bgTop, bgBottom] as CFArray, locations: [0, 1]) {
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: W), end: CGPoint(x: 0, y: 0), options: [])
    }

    // MARK: Cassette body
    let inset = W * 0.10
    let body = CGRect(x: inset, y: W * 0.185, width: W - inset * 2, height: W * 0.63)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: W * 0.045, cornerHeight: W * 0.045, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -W * 0.012), blur: W * 0.03,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.55))
    ctx.addPath(bodyPath)
    switch variant {
    case .dark: ctx.setFillColor(rgb(0.24, 0.24, 0.27))
    default: ctx.setFillColor(rgb(0.16, 0.16, 0.18))
    }
    ctx.fillPath()
    ctx.restoreGState()

    // Body sheen along the top edge.
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    if let sheen = CGGradient(
        colorsSpace: cs,
        colors: [rgb(1, 1, 1, 0.16), rgb(1, 1, 1, 0)] as CFArray,
        locations: [0, 1]
    ) {
        ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: body.maxY),
                               end: CGPoint(x: 0, y: body.midY), options: [])
    }
    ctx.restoreGState()

    // MARK: Paper label
    let label = CGRect(x: body.minX + W * 0.042, y: body.midY + W * 0.012,
                       width: body.width - W * 0.084, height: W * 0.175)
    ctx.addPath(CGPath(roundedRect: label, cornerWidth: W * 0.012, cornerHeight: W * 0.012, transform: nil))
    ctx.setFillColor(rgb(0.90, 0.87, 0.80))
    ctx.fillPath()

    // The orange band across the top of the insert.
    let band = CGRect(x: label.minX, y: label.maxY - W * 0.046, width: label.width, height: W * 0.046)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: label, cornerWidth: W * 0.012, cornerHeight: W * 0.012, transform: nil))
    ctx.clip()
    ctx.setFillColor(rgb(0.96, 0.45, 0.09))
    ctx.fill(band)
    ctx.restoreGState()

    // Ruled lines, as on a handwritten label.
    ctx.setStrokeColor(rgb(0.12, 0.12, 0.12, 0.28))
    ctx.setLineWidth(W * 0.005)
    for i in 0..<2 {
        let y = label.minY + W * 0.045 + Double(i) * W * 0.045
        ctx.move(to: CGPoint(x: label.minX + W * 0.03, y: y))
        ctx.addLine(to: CGPoint(x: label.maxX - W * 0.03, y: y))
    }
    ctx.strokePath()

    // MARK: Hubs
    let hubY = body.minY + W * 0.205
    let hubDX = W * 0.135
    let hubR = W * 0.092

    // Exposed tape running between the hubs, behind them.
    let tape = CGRect(x: W / 2 - hubDX, y: hubY - W * 0.030, width: hubDX * 2, height: W * 0.060)
    ctx.setFillColor(rgb(0.07, 0.07, 0.08))
    ctx.fill(tape)

    for cx in [W / 2 - hubDX, W / 2 + hubDX] {
        let centre = CGPoint(x: cx, y: hubY)

        // Wound tape.
        ctx.setFillColor(rgb(0.09, 0.09, 0.10))
        ctx.fillEllipse(in: CGRect(x: centre.x - hubR, y: centre.y - hubR, width: hubR * 2, height: hubR * 2))

        // Amber ring.
        ctx.setStrokeColor(rgb(0.96, 0.45, 0.09))
        ctx.setLineWidth(W * 0.011)
        ctx.strokeEllipse(in: CGRect(x: centre.x - hubR * 0.62, y: centre.y - hubR * 0.62,
                                     width: hubR * 1.24, height: hubR * 1.24))

        // Drive teeth.
        ctx.setFillColor(rgb(0.62, 0.62, 0.66))
        for i in 0..<6 {
            let angle = Double(i) / 6 * 2 * .pi
            let tooth = CGRect(x: -W * 0.006, y: hubR * 0.22, width: W * 0.012, height: hubR * 0.26)
            ctx.saveGState()
            ctx.translateBy(x: centre.x, y: centre.y)
            ctx.rotate(by: angle)
            ctx.addPath(CGPath(roundedRect: tooth, cornerWidth: W * 0.004, cornerHeight: W * 0.004, transform: nil))
            ctx.fillPath()
            ctx.restoreGState()
        }
    }

    // MARK: Head cutout along the bottom edge
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()

    let cut = CGMutablePath()
    let cutW = W * 0.30, cutH = W * 0.052
    let cutY = body.minY - W * 0.01   // clipped, so it sits flush with the shell edge
    cut.move(to: CGPoint(x: W / 2 - cutW / 2, y: cutY + cutH))
    cut.addLine(to: CGPoint(x: W / 2 - cutW / 2 + cutH * 0.8, y: cutY))
    cut.addLine(to: CGPoint(x: W / 2 + cutW / 2 - cutH * 0.8, y: cutY))
    cut.addLine(to: CGPoint(x: W / 2 + cutW / 2, y: cutY + cutH))
    cut.closeSubpath()
    ctx.addPath(cut)
    ctx.setFillColor(rgb(0.06, 0.06, 0.07))
    ctx.fillPath()

    // Capstan holes either side of the opening.
    ctx.setFillColor(rgb(0.06, 0.06, 0.07))
    for cx in [W / 2 - W * 0.215, W / 2 + W * 0.215] {
        let hole = CGRect(x: cx - W * 0.020, y: cutY, width: W * 0.040, height: cutH * 0.85)
        ctx.addPath(CGPath(roundedRect: hole, cornerWidth: W * 0.006, cornerHeight: W * 0.006, transform: nil))
        ctx.fillPath()
    }
    ctx.restoreGState()

    guard let image = ctx.makeImage() else { fatalError("no image") }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("no png") }
    try! data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

let out = CommandLine.arguments[1]
render(.standard, to: "\(out)/Icon-1024.png")
render(.dark, to: "\(out)/Icon-1024-Dark.png")
render(.tinted, to: "\(out)/Icon-1024-Tinted.png")
