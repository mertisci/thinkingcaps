#!/usr/bin/env swift
// Generates Resources/AppIcon.icns from scratch.
//
// Run with: swift Scripts/make_icon.swift
//
// Draws a macOS Big Sur+ style rounded-square tile (dark graphite gradient)
// with a centered "capslock.fill" SF Symbol glyph and a small green LED
// accent pill underneath, at every size macOS expects in an .iconset,
// then packs it into Resources/AppIcon.icns via `iconutil`.

import AppKit
import Foundation

// MARK: - Drawing

/// Draws the icon artwork into a bitmap of exactly `pixelSize` x `pixelSize`
/// pixels and returns it as an NSBitmapImageRep (no @Nx scaling tricks —
/// every requested size is rendered from the same vector drawing code at
/// its own pixel dimensions so edges stay crisp).
func drawIcon(pixelSize: Int) -> NSBitmapImageRep {
    let size = CGFloat(pixelSize)

    guard
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
    else {
        fatalError("Could not allocate NSBitmapImageRep for size \(pixelSize)")
    }
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }

    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("Could not create graphics context for size \(pixelSize)")
    }
    NSGraphicsContext.current = context

    // Transparent canvas.
    NSColor.clear.set()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    // Scale factor relative to the 1024px design canvas the brief's
    // measurements (margins, radius, pill dims) were specified against.
    let scale = size / 1024.0

    // --- Tile: centered rounded square, ~824px side, ~100px margins, ~185px radius.
    let margin = 100.0 * scale
    let tileSide = 824.0 * scale
    let cornerRadius = 185.0 * scale
    let tileRect = NSRect(x: margin, y: margin, width: tileSide, height: tileSide)
    let tilePath = NSBezierPath(roundedRect: tileRect, xRadius: cornerRadius, yRadius: cornerRadius)

    let gradient = NSGradient(
        colors: [
            NSColor(srgbRed: 0x2E / 255.0, green: 0x31 / 255.0, blue: 0x40 / 255.0, alpha: 1.0),
            NSColor(srgbRed: 0x16 / 255.0, green: 0x17 / 255.0, blue: 0x1F / 255.0, alpha: 1.0),
        ]
    )!
    gradient.draw(in: tilePath, angle: 90.0)  // top -> bottom

    // --- Glyph: capslock.fill SF Symbol, white, ~55% of tile width, centered,
    // nudged slightly above dead-center to leave room for the LED pill below it
    // and to visually balance the glyph's own internal weight (the symbol's
    // bounding box is not perfectly centered inside its reported frame).
    let symbolTargetWidth = tileSide * 0.55
    let symbolPointSize = 480.0 * scale

    let symbolConfig = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .medium)
    if let symbolImage = NSImage(systemSymbolName: "capslock.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(symbolConfig)
    {
        // Scale the rendered symbol image so its width matches the target,
        // preserving aspect ratio.
        let naturalSize = symbolImage.size
        let symbolScale = naturalSize.width > 0 ? symbolTargetWidth / naturalSize.width : 1.0
        let drawSize = NSSize(width: naturalSize.width * symbolScale, height: naturalSize.height * symbolScale)

        let glyphCenterY = margin + tileSide * 0.56
        let drawOrigin = NSPoint(
            x: (size - drawSize.width) / 2.0,
            y: glyphCenterY - drawSize.height / 2.0
        )
        let drawRect = NSRect(origin: drawOrigin, size: drawSize)

        // Tint the glyph white by clipping the current (single, consistent
        // colorspace) context to the symbol's own alpha mask, then filling
        // white — this avoids the faint bounding-box fringe that an
        // intermediate lockFocus-based NSImage composite (a second,
        // separately color-managed context) introduces at its edges.
        var proposedRect = NSRect(origin: .zero, size: drawSize)
        if let cgMask = symbolImage.cgImage(forProposedRect: &proposedRect, context: NSGraphicsContext.current, hints: nil) {
            let cgContext = context.cgContext
            cgContext.saveGState()
            cgContext.clip(to: drawRect, mask: cgMask)
            NSColor.white.setFill()
            cgContext.fill(drawRect)
            cgContext.restoreGState()
        }

        // --- LED accent: small green pill, ~140x28px, ~120px under the glyph's
        // visual baseline, corner radius 14.
        let pillWidth = 140.0 * scale
        let pillHeight = 28.0 * scale
        let pillGap = 120.0 * scale
        let pillCenterX = size / 2.0
        let pillTop = drawOrigin.y - pillGap
        let pillRect = NSRect(
            x: pillCenterX - pillWidth / 2.0,
            y: pillTop - pillHeight,
            width: pillWidth,
            height: pillHeight
        )
        let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: 14.0 * scale, yRadius: 14.0 * scale)
        NSColor(srgbRed: 0x63 / 255.0, green: 0xE2 / 255.0, blue: 0x7F / 255.0, alpha: 1.0).setFill()
        pillPath.fill()
    } else {
        FileHandle.standardError.write("warning: could not load SF Symbol capslock.fill\n".data(using: .utf8)!)
    }

    NSGraphicsContext.current?.flushGraphics()
    return rep
}

func pngData(pixelSize: Int) -> Data {
    let rep = drawIcon(pixelSize: pixelSize)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode PNG for size \(pixelSize)")
    }
    return data
}

// MARK: - Iconset assembly

struct IconsetEntry {
    let filename: String
    let pixelSize: Int
}

let entries: [IconsetEntry] = [
    IconsetEntry(filename: "icon_16x16.png", pixelSize: 16),
    IconsetEntry(filename: "icon_16x16@2x.png", pixelSize: 32),
    IconsetEntry(filename: "icon_32x32.png", pixelSize: 32),
    IconsetEntry(filename: "icon_32x32@2x.png", pixelSize: 64),
    IconsetEntry(filename: "icon_128x128.png", pixelSize: 128),
    IconsetEntry(filename: "icon_128x128@2x.png", pixelSize: 256),
    IconsetEntry(filename: "icon_256x256.png", pixelSize: 256),
    IconsetEntry(filename: "icon_256x256@2x.png", pixelSize: 512),
    IconsetEntry(filename: "icon_512x512.png", pixelSize: 512),
    IconsetEntry(filename: "icon_512x512@2x.png", pixelSize: 1024),
]

let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let rootDir = scriptDir.deletingLastPathComponent()
let resourcesDir = rootDir.appendingPathComponent("Resources")
let outputIcns = resourcesDir.appendingPathComponent("AppIcon.icns")

let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("thinkingcaps-icon-\(UUID().uuidString)")
let iconsetDir = tmpDir.appendingPathComponent("AppIcon.iconset")

let fm = FileManager.default
try fm.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

for entry in entries {
    let data = pngData(pixelSize: entry.pixelSize)
    let fileURL = iconsetDir.appendingPathComponent(entry.filename)
    try data.write(to: fileURL)
    print("wrote \(fileURL.path) (\(entry.pixelSize)x\(entry.pixelSize))")
}

// Also drop a plain 512px PNG next to the iconset for visual inspection
// without needing to unpack the .icns afterwards.
let previewPNG = tmpDir.appendingPathComponent("preview_512.png")
try pngData(pixelSize: 512).write(to: previewPNG)
print("wrote \(previewPNG.path)")

try fm.createDirectory(at: resourcesDir, withIntermediateDirectories: true)

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetDir.path, "-o", outputIcns.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil failed with status \(process.terminationStatus)\n".data(using: .utf8)!)
    exit(process.terminationStatus)
}

print("Wrote \(outputIcns.path)")
print("iconset temp dir kept at \(tmpDir.path)")
