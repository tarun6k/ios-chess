import Testing
@testable import ChessServices

@Suite("ChessServices scaffold")
struct ChessServicesScaffoldTests {
    @Test("the ChessServices module builds and links into its test target")
    func moduleLinks() {
        #expect(Bool(true))
    }
}
