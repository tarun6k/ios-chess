import Testing
@testable import ChessCore

@Suite("ChessCore scaffold")
struct ChessCoreScaffoldTests {
    @Test("the ChessCore module builds and links into its test target")
    func moduleLinks() {
        #expect(Bool(true))
    }
}
