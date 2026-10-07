// Codex-only static rendering extracted from upstream IconRenderer.swift (MIT).
import AppKit
import CodexBarLiteCore

enum CodexStatusIcon {
    static func make(windows: [QuotaWindow], stale: Bool) -> NSImage {
        let primary = windows.first(where: { $0.id == "session" })?.remainingPercent
        let secondary = windows.first(where: { $0.id == "weekly" })?.remainingPercent
        let fallback = windows.first?.remainingPercent
        let image = NSImage(size: NSSize(width: 18, height: 18))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 36,
            pixelsHigh: 36,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: rep) else { return image }
        rep.size = image.size
        image.addRepresentation(rep)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: 2, y: 2)
        context.cgContext.setShouldAntialias(true)
        if let secondary, secondary > 0, primary != nil {
            self.bar(rectPixels: CGRect(x: 3, y: 19, width: 30, height: 12), value: primary, face: true, stale: stale)
            self.bar(rectPixels: CGRect(x: 3, y: 5, width: 30, height: 8), value: secondary, face: false, stale: stale)
        } else if secondary == 0 {
            self.bar(rectPixels: CGRect(x: 3, y: 19, width: 30, height: 12), value: primary, face: true, stale: stale)
            self.bar(rectPixels: CGRect(x: 3, y: 4, width: 30, height: 6), value: secondary, face: false, stale: stale)
        } else {
            self.bar(
                rectPixels: CGRect(x: 3, y: 14, width: 30, height: 16),
                value: primary ?? secondary ?? fallback,
                face: true,
                stale: stale)
        }
        NSGraphicsContext.restoreGraphicsState()
        image.isTemplate = true
        return image
    }

    private static func bar(
        rectPixels: CGRect, value: Double?, face: Bool, stale: Bool)
    {
        let x = rectPixels.minX
        let y = rectPixels.minY
        let width = rectPixels.width
        let height = rectPixels.height
        let rect = NSRect(x: x / 2, y: y / 2, width: width / 2, height: height / 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: height / 4, yRadius: height / 4)
        NSColor.labelColor.withAlphaComponent(stale ? 0.18 : 0.28).setFill()
        path.fill()
        let outline = NSBezierPath(
            roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: height / 4 - 0.5, yRadius: height / 4 - 0.5)
        outline.lineWidth = 1
        NSColor.labelColor.withAlphaComponent(stale ? 0.28 : 0.44).setStroke()
        outline.stroke()
        if let value {
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            NSColor.labelColor.withAlphaComponent(stale ? 0.55 : 1).setFill()
            NSBezierPath(rect: NSRect(
                x: rect.minX,
                y: rect.minY,
                width: (width * max(0, min(value, 100)) / 100).rounded() / 2,
                height: rect.height)).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        if face, let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.setShouldAntialias(false)
            for offset: CGFloat in [-7, 7] {
                context.clear(CGRect(
                    x: (x + width / 2 + offset - 2) / 2,
                    y: (y + height / 2 - 2) / 2,
                    width: 2,
                    height: 2))
            }
            context.restoreGState()
        }
    }
}
