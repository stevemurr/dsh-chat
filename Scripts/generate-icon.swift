#!/usr/bin/env swift
import AppKit
import Foundation

// Generate every macOS icon representation from the same small vector drawing.
let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.icns")

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: red, green: green, blue: blue, alpha: alpha)
}

func render(_ size: Int) throws -> Data {
    let space = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                            bytesPerRow: size * 4, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let tile = CGPath(roundedRect: CGRect(x: 64, y: 64, width: 896, height: 896),
                      cornerWidth: 198, cornerHeight: 198, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 34,
                      color: color(0, 0, 0, 0.28))
    context.addPath(tile)
    context.setFillColor(color(0.075, 0.1, 0.14))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tile)
    context.clip()
    let background = CGGradient(colorsSpace: space,
        colors: [color(0.14, 0.20, 0.26), color(0.065, 0.09, 0.13)] as CFArray,
        locations: [0, 1])!
    context.drawLinearGradient(background, start: CGPoint(x: 512, y: 960),
                               end: CGPoint(x: 512, y: 64), options: [])
    let glow = CGGradient(colorsSpace: space,
        colors: [color(0.20, 0.85, 0.91, 0.14), color(0.20, 0.85, 0.91, 0)] as CFArray,
        locations: [0, 1])!
    context.drawRadialGradient(glow, startCenter: CGPoint(x: 800, y: 900), startRadius: 0,
                               endCenter: CGPoint(x: 800, y: 900), endRadius: 720, options: [])
    context.restoreGState()
    context.addPath(tile)
    context.setStrokeColor(color(1, 1, 1, 0.10))
    context.setLineWidth(2)
    context.strokePath()

    let bubble = CGMutablePath()
    bubble.move(to: CGPoint(x: 330, y: 728))
    bubble.addLine(to: CGPoint(x: 694, y: 728))
    bubble.addQuadCurve(to: CGPoint(x: 796, y: 626), control: CGPoint(x: 796, y: 728))
    bubble.addLine(to: CGPoint(x: 796, y: 422))
    bubble.addQuadCurve(to: CGPoint(x: 694, y: 320), control: CGPoint(x: 796, y: 320))
    bubble.addLine(to: CGPoint(x: 432, y: 320))
    bubble.addLine(to: CGPoint(x: 296, y: 224))
    bubble.addQuadCurve(to: CGPoint(x: 278, y: 236), control: CGPoint(x: 278, y: 212))
    bubble.addLine(to: CGPoint(x: 278, y: 334))
    bubble.addQuadCurve(to: CGPoint(x: 228, y: 422), control: CGPoint(x: 228, y: 352))
    bubble.addLine(to: CGPoint(x: 228, y: 626))
    bubble.addQuadCurve(to: CGPoint(x: 330, y: 728), control: CGPoint(x: 228, y: 728))
    bubble.closeSubpath()

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28,
                      color: color(0, 0, 0, 0.22))
    context.addPath(bubble)
    context.setFillColor(color(0.35, 0.88, 0.90))
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(bubble)
    context.clip()
    let foreground = CGGradient(colorsSpace: space,
        colors: [color(0.66, 0.98, 0.95), color(0.27, 0.80, 0.86)] as CFArray,
        locations: [0, 1])!
    context.drawLinearGradient(foreground, start: CGPoint(x: 360, y: 760),
                               end: CGPoint(x: 660, y: 220), options: [])
    context.restoreGState()

    context.setFillColor(color(0.075, 0.17, 0.21, 0.88))
    for center in [376, 512, 648] {
        context.fillEllipse(in: CGRect(x: center - 28, y: 496, width: 56, height: 56))
    }
    let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
    return bitmap.representation(using: .png, properties: [:])!
}

if output.pathExtension == "iconset" {
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for base in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let suffix = scale == 2 ? "@2x" : ""
            let name = "icon_\(base)x\(base)\(suffix).png"
            try render(base * scale).write(to: output.appendingPathComponent(name))
        }
    }
} else {
    func length(_ value: Int) -> Data {
        var integer = UInt32(value).bigEndian
        return withUnsafeBytes(of: &integer) { Data($0) }
    }
    var elements = Data()
    for (type, size) in [("icp4", 16), ("ic11", 32), ("icp5", 32), ("ic12", 64),
                         ("ic07", 128), ("ic13", 256), ("ic08", 256), ("ic14", 512),
                         ("ic09", 512), ("ic10", 1024)] {
        let png = try render(size)
        elements.append(Data(type.utf8))
        elements.append(length(png.count + 8))
        elements.append(png)
    }
    var icon = Data("icns".utf8)
    icon.append(length(elements.count + 8))
    icon.append(elements)
    try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
    try icon.write(to: output)
}
