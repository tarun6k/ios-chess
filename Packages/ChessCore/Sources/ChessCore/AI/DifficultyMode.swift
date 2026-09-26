// TS `DifficultyMode` from src/ai/adaptation.ts. The rest of adaptation.ts lives in Adaptation.swift;
// the mode has its own file because `SavedGame` persists it (Phase 2).

/// Learn / Match / Challenge: the rubber-band difficulty the player picked.
public enum DifficultyMode: String, Codable, Hashable, Sendable, CaseIterable {
    case learn
    case match
    case challenge
}
