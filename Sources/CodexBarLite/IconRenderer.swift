// Extracted from upstream CodexBar IconRenderer.swift at 8ab81e2eb (MIT).
// Static Codex path only. Bitmap context, geometry, face and capsule drawing retained.
import AppKit

enum IconRenderer {
    // Render to an 18×18 pt template (36×36 px at 2×) to match the system menu bar size.
    private static let outputSize = NSSize(width: 18, height: 18)
    private static let outputScale: CGFloat = 2
    private static let canvasPx = Int(outputSize.width * outputScale)

    private struct PixelGrid {
        let scale: CGFloat

        func pt(_ px: Int) -> CGFloat {
            CGFloat(px) / self.scale
        }

        func rect(x: Int, y: Int, w: Int, h: Int) -> CGRect {
            CGRect(x: self.pt(x), y: self.pt(y), width: self.pt(w), height: self.pt(h))
        }

        func snapDelta(_ value: CGFloat) -> CGFloat {
            (value * self.scale).rounded() / self.scale
        }
    }

    private static let grid = PixelGrid(scale: outputScale)

    static func fillWidthPixels(remaining: Double, rectWidth: Int) -> Int {
        let clamped = max(0, min(remaining / 100, 1))
        return max(0, min(rectWidth, Int((CGFloat(rectWidth) * CGFloat(clamped)).rounded())))
    }

    private struct RectPx: Hashable {
        let x: Int
        let y: Int
        let w: Int
        let h: Int

        var midXPx: Int {
            self.x + self.w / 2
        }

        var midYPx: Int {
            self.y + self.h / 2
        }

        func rect() -> CGRect {
            Self.grid.rect(x: self.x, y: self.y, w: self.w, h: self.h)
        }

        private static let grid = IconRenderer.grid
    }

    static func makeIcon(
        primaryRemaining: Double?,
        weeklyRemaining: Double?,
        stale: Bool,
        showFace: Bool = false,
        blink: CGFloat = 0,
        tilt: CGFloat = 0) -> NSImage
    {
        self.renderImage {
            let baseFill = NSColor.labelColor
            let trackFillAlpha: CGFloat = stale ? 0.18 : 0.28
            let trackStrokeAlpha: CGFloat = stale ? 0.28 : 0.44
            let fillColor = baseFill.withAlphaComponent(stale ? 0.55 : 1.0)

            let barWidthPx = 30 // 15 pt at 2×, uses the slot better without touching edges.
            let barXPx = (Self.canvasPx - barWidthPx) / 2

            func drawBar(
                rectPx: RectPx,
                remaining: Double?,
                alpha: CGFloat = 1.0,
                addFace: Bool = false,
                blink: CGFloat = 0)
            {
                let rect = rectPx.rect()
                // Claude reads better as a blockier critter; Codex stays as a capsule.
                // Warp uses small corner radius for rounded rectangle (matching logo style)
                let cornerRadiusPx = rectPx.h / 2
                let radius = Self.grid.pt(cornerRadiusPx)

                let trackPath = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
                do {
                    baseFill.withAlphaComponent(trackFillAlpha * alpha).setFill()
                    trackPath.fill()
                }

                // Crisp outline: stroke an inset path so the stroke stays within pixel bounds.
                let strokeWidthPx = 2 // 1 pt == 2 px at 2×
                let insetPx = strokeWidthPx / 2
                let strokeRect = Self.grid.rect(
                    x: rectPx.x + insetPx,
                    y: rectPx.y + insetPx,
                    w: max(0, rectPx.w - insetPx * 2),
                    h: max(0, rectPx.h - insetPx * 2))
                let strokePath = NSBezierPath(
                    roundedRect: strokeRect,
                    xRadius: Self.grid.pt(max(0, cornerRadiusPx - insetPx)),
                    yRadius: Self.grid.pt(max(0, cornerRadiusPx - insetPx)))
                strokePath.lineWidth = CGFloat(strokeWidthPx) / Self.outputScale
                baseFill.withAlphaComponent(trackStrokeAlpha * alpha).setStroke()
                strokePath.stroke()

                // Fill: clip to the capsule and paint a left-to-right rect so the progress edge is straight.
                if let remaining {
                    let fillWidthPx = Self.fillWidthPixels(remaining: remaining, rectWidth: rectPx.w)
                    if fillWidthPx > 0 {
                        NSGraphicsContext.current?.cgContext.saveGState()
                        trackPath.addClip()
                        fillColor.withAlphaComponent(alpha).setFill()
                        NSBezierPath(
                            rect: Self.grid.rect(
                                x: rectPx.x,
                                y: rectPx.y,
                                w: fillWidthPx,
                                h: rectPx.h)).fill()
                        NSGraphicsContext.current?.cgContext.restoreGState()
                    }
                }

                // Codex face: eye cutouts plus faint eyelids to give the prompt some personality.
                if addFace {
                    let ctx = NSGraphicsContext.current?.cgContext
                    let eyeSizePx = 4
                    let eyeOffsetPx = 7
                    let eyeCenterYPx = rectPx.y + rectPx.h / 2
                    let centerXPx = rectPx.midXPx

                    ctx?.saveGState()
                    ctx?.setShouldAntialias(false)
                    ctx?.clear(Self.grid.rect(
                        x: centerXPx - eyeOffsetPx - eyeSizePx / 2,
                        y: eyeCenterYPx - eyeSizePx / 2,
                        w: eyeSizePx,
                        h: eyeSizePx))
                    ctx?.clear(Self.grid.rect(
                        x: centerXPx + eyeOffsetPx - eyeSizePx / 2,
                        y: eyeCenterYPx - eyeSizePx / 2,
                        w: eyeSizePx,
                        h: eyeSizePx))
                    ctx?.restoreGState()

                    // Blink: refill eyes from the top down using the bar fill color.
                    if blink > 0.001 {
                        let clamped = max(0, min(blink, 1))
                        let blinkHeightPx = Int((CGFloat(eyeSizePx) * clamped).rounded())
                        fillColor.withAlphaComponent(alpha).setFill()
                        let blinkRectLeft = Self.grid.rect(
                            x: centerXPx - eyeOffsetPx - eyeSizePx / 2,
                            y: eyeCenterYPx + eyeSizePx / 2 - blinkHeightPx,
                            w: eyeSizePx,
                            h: blinkHeightPx)
                        let blinkRectRight = Self.grid.rect(
                            x: centerXPx + eyeOffsetPx - eyeSizePx / 2,
                            y: eyeCenterYPx + eyeSizePx / 2 - blinkHeightPx,
                            w: eyeSizePx,
                            h: blinkHeightPx)
                        NSBezierPath(rect: blinkRectLeft).fill()
                        NSBezierPath(rect: blinkRectRight).fill()
                    }

                    // Hat: a tiny cap hovering above the eyes to give the face more character.
                    let hatWidthPx = 18
                    let hatHeightPx = 4
                    let hatRect = Self.grid.rect(
                        x: centerXPx - hatWidthPx / 2,
                        y: rectPx.y + rectPx.h - hatHeightPx,
                        w: hatWidthPx,
                        h: hatHeightPx)
                    ctx?.saveGState()
                    if abs(tilt) > 0.0001 {
                        // Tilt only the hat; keep eyes pixel-crisp and axis-aligned.
                        let faceCenter = CGPoint(x: Self.grid.pt(centerXPx), y: Self.grid.pt(eyeCenterYPx))
                        ctx?.translateBy(x: faceCenter.x, y: faceCenter.y)
                        ctx?.rotate(by: tilt)
                        ctx?.translateBy(x: -faceCenter.x, y: -faceCenter.y - abs(tilt) * 1.2)
                    }
                    fillColor.withAlphaComponent(alpha).setFill()
                    NSBezierPath(rect: hatRect).fill()
                    ctx?.restoreGState()
                }
            }
            let topRectPx = RectPx(x: barXPx, y: 19, w: barWidthPx, h: 12)
            let bottomRectPx = RectPx(x: barXPx, y: 5, w: barWidthPx, h: 8)
            // A lone quota meter is centered in the 36px canvas; dual-meter coordinates stay upstream.
            let singleRectPx = RectPx(x: barXPx, y: (Self.canvasPx - 16) / 2, w: barWidthPx, h: 16)
            let creditsBottomRectPx = RectPx(x: barXPx, y: 4, w: barWidthPx, h: 6)
            if let weeklyRemaining, weeklyRemaining > 0, primaryRemaining == nil {
                drawBar(rectPx: singleRectPx, remaining: weeklyRemaining, addFace: showFace, blink: blink)
            } else if let weeklyRemaining, weeklyRemaining > 0 {
                drawBar(rectPx: topRectPx, remaining: primaryRemaining, addFace: showFace, blink: blink)
                drawBar(rectPx: bottomRectPx, remaining: weeklyRemaining)
            } else if weeklyRemaining == nil {
                if let primaryRemaining {
                    drawBar(rectPx: singleRectPx, remaining: primaryRemaining, addFace: showFace, blink: blink)
                } else {
                    drawBar(rectPx: topRectPx, remaining: primaryRemaining, addFace: showFace, blink: blink)
                    drawBar(rectPx: bottomRectPx, remaining: nil, alpha: 0.45)
                }
            } else {
                drawBar(rectPx: topRectPx, remaining: primaryRemaining, addFace: showFace, blink: blink)
                drawBar(rectPx: creditsBottomRectPx, remaining: weeklyRemaining)
            }
        }
    }

    private static func withScaledContext(_ draw: () -> Void) {
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            draw()
            return
        }
        ctx.saveGState()
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .none
        draw()
        ctx.restoreGState()
    }

    private static func snap(_ value: CGFloat) -> CGFloat {
        (value * self.outputScale).rounded() / self.outputScale
    }

    private static func snapRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(x: self.snap(x), y: self.snap(y), width: self.snap(width), height: self.snap(height))
    }

    private static func renderImage(_ draw: () -> Void) -> NSImage {
        let image = NSImage(size: Self.outputSize)

        if let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(Self.outputSize.width * Self.outputScale),
            pixelsHigh: Int(Self.outputSize.height * Self.outputScale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0)
        {
            rep.size = Self.outputSize // points
            image.addRepresentation(rep)

            NSGraphicsContext.saveGraphicsState()
            if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
                NSGraphicsContext.current = ctx
                Self.withScaledContext(draw)
            }
            NSGraphicsContext.restoreGraphicsState()
        } else {
            // Fallback to legacy focus if the bitmap rep fails for any reason.
            image.lockFocus()
            Self.withScaledContext(draw)
            image.unlockFocus()
        }

        image.isTemplate = true
        return image
    }
}
