import AppKit
import Testing
@testable import CodexBarLite

@MainActor
struct IconAlignmentTests {
    @Test func `single quota is vertically centered for full partial and exhausted fills`() throws {
        for remaining: Double in [0, 54, 100] {
            for stale in [false, true] {
                let image = IconRenderer.makeIcon(primaryRemaining: remaining, weeklyRemaining: nil, stale: stale)
                let bitmap = try #require(image.representations.first as? NSBitmapImageRep)
                let visibleRows = (0..<bitmap.pixelsHigh).filter { y in
                    (0..<bitmap.pixelsWide).contains { x in
                        (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05
                    }
                }
                let top = try #require(visibleRows.first)
                let bottom = try #require(visibleRows.last)
                #expect(abs(top + bottom - (bitmap.pixelsHigh - 1)) <= 1)
            }
        }
    }
}
