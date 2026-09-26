// TS src/app/aiClient.ts: `requestAiMove`, `requestHint` and `requestAnalysis` were promise wrappers
// around the AI Web Worker. Here they are the three requirements of `AIService`; the production
// service is the `AIEngine` actor itself (no worker, no message ids), tests script a stand-in.
// Requests honour Task cancellation: `AIEngine` throws `CancellationError` when the awaiting task is
// cancelled mid-search, and the controller treats that as "reply no longer wanted".

import ChessCore

public protocol AIService: Sendable {
    /// `requestAiMove(opts)`.
    func move(_ request: MoveRequest) async throws -> MoveResponse
    /// `requestHint(fen, historyKeys)`.
    func hint(_ request: HintRequest) async throws -> HintResponse
    /// `requestAnalysis(startFen, uciMoves, perMoveMs)`.
    func analyze(_ request: AnalyzeRequest) async throws -> AnalyzeResponse
}

extension AIEngine: AIService {}
