import AppKit
import SwiftUI
import Testing
@testable import CodexBarLite
@testable import CodexBarLiteCore

@MainActor
struct MenuLayoutTests {
    @Test func `native menu card reserves visible height for quota rows`() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let model = try AppModel(repository: fixture.repository, demo: true)
        model.refreshNow()
        for _ in 0..<100 where model.status?.snapshot == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        _ = try #require(model.status?.snapshot)
        let view = NSHostingView(rootView: MenuView(model: model))
        let size = view.fittingSize
        #expect(size.width == 310)
        // Regression: a maxHeight-only ScrollView collapsed its quota rows to zero.
        #expect(size.height > 120)
        #expect(size.height < 300)
        await model.refresh.stop()
    }
}
