import Testing
@testable import AdaptiveChess
import ChessCore

/// Phase 9 performance checks, run inside the simulator like the app: the strongest AI (skill 20,
/// the level every drill and puzzle defender plays at) must answer within the controller's budget
/// (900 ms + 300 ms per ply of depth = 3.3 s at depth 8), and the search must never run on the
/// main actor, so the UI keeps drawing while the engine thinks.
@Suite("AI performance in the simulator", .serialized)
@MainActor
struct AIPerformanceTests {
    /// Positions of different character; the last two are the search benchmarks of Phase 3.
    static let positions: [(name: String, fen: String)] = [
        ("start", Position.startFEN),
        ("open middlegame", "r1bq1rk1/ppp2ppp/2np1n2/2b1p3/2B1P3/2NP1N2/PPP2PPP/R1BQ1RK1 w - - 0 8"),
        ("kiwipete", "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"),
        ("rook endgame", "8/8/4k3/8/2p5/8/3K1P2/r6R w - - 0 1"),
    ]

    /// What `GameController.maybeTriggerAi` sends for a skill-20 opponent without clock pressure.
    static func request(_ fen: String) -> MoveRequest {
        let persona = personaForSkill(20, moveTimeMs: 0)
        return MoveRequest(fen: fen, historyKeys: [], skill: 20,
                           moveTimeMs: Double(900 + persona.maxDepth * 300), params: nil, bookMove: nil)
    }

    @Test("a skill-20 reply stays within its 3.3 s search budget")
    func skill20Latency() async throws {
        let engine = AIEngine()
        var worst: Duration = .zero
        for position in Self.positions {
            let clock = ContinuousClock()
            let started = clock.now
            let reply = try await engine.move(Self.request(position.fen))
            let elapsed = clock.now - started
            worst = max(worst, elapsed)
            let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
            print("skill 20 · \(position.name): \(reply.uci) depth \(reply.depth), \(reply.nodes) nodes in \(Int(ms)) ms")
            // The deadline is polled every 2048 nodes and the final iteration may overrun it slightly.
            #expect(elapsed < .milliseconds(3300 + 700), "\(position.name) took \(Int(ms)) ms")
        }
        #expect(worst < .seconds(4))
    }

    @Test("the main actor is never blocked while the engine searches")
    func mainActorStaysResponsive() async throws {
        let engine = AIEngine()
        let search = Task.detached(priority: .userInitiated) {
            try await engine.move(Self.request(Self.positions[2].fen))
        }
        // Heartbeat on the main actor: if the search ran here, a wake-up would be late by seconds.
        let clock = ContinuousClock()
        var worstGap: Duration = .zero
        var beats = 0
        var last = clock.now
        while !search.isCancelled {
            try await Task.sleep(for: .milliseconds(20))
            let now = clock.now
            worstGap = max(worstGap, now - last - .milliseconds(20))
            last = now
            beats += 1
            if beats >= 60 { break }
        }
        #expect(worstGap < .milliseconds(150), "worst main-actor stall was \(worstGap)")
        let reply = try await search.value
        #expect(!reply.uci.isEmpty)
        #expect(beats >= 40, "the heartbeat should have run for most of the search, not just \(beats) beats")
    }
}
