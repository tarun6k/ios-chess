import Testing
@testable import AdaptiveChess

@Suite("AdaptiveChess scaffold")
struct AdaptiveChessScaffoldTests {
    @Test("the app target builds and links into its test target")
    func moduleLinks() {
        #expect(Bool(true))
    }
}
