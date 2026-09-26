// TS `DifficultyMode` from src/ai/adaptation.ts. The rest of adaptation.ts is ported in Phase 4;
// the mode lives here already because `SavedGame` persists it.

/// Learn / Match / Challenge: the rubber-band difficulty the player picked.
public enum DifficultyMode: String, Codable, Hashable, Sendable, CaseIterable {
    case learn
    case match
    case challenge
}
