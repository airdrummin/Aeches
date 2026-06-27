import Foundation

// MARK: - Enums

enum Suit: String, Codable, CaseIterable {
    case spades   = "s"
    case hearts   = "h"
    case diamonds = "d"
    case clubs    = "c"

    var symbol: String {
        switch self {
        case .spades:   return "♠"
        case .hearts:   return "♥"
        case .diamonds: return "♦"
        case .clubs:    return "♣"
        }
    }

    /// Reverse of `symbol` — build a Suit from a glyph the picker UI passes around (`"♠"` → `.spades`).
    /// Returns nil for anything that isn't a real suit glyph (e.g. the explicit-unknown `x`).
    init?(symbol: String) {
        switch symbol {
        case "♠": self = .spades
        case "♥": self = .hearts
        case "♦": self = .diamonds
        case "♣": self = .clubs
        default:  return nil
        }
    }
}

enum Rank: String, Codable, CaseIterable {
    case ace   = "A"
    case king  = "K"
    case queen = "Q"
    case jack  = "J"
    case ten   = "T"
    case nine  = "9"
    case eight = "8"
    case seven = "7"
    case six   = "6"
    case five  = "5"
    case four  = "4"
    case three = "3"
    case two   = "2"
}

enum ActionType: String, Codable {
    case fold
    case check
    case call   // includes preflop limps — display layer labels contextually
    case open   // first raise preflop
    case raise  // re-raise or post-flop aggression
}

enum VillainTag: String, Codable, CaseIterable {
    case omc     = "OMC"
    case lag     = "LAG"
    case tag     = "TAG"
    case fish    = "Fish"
    case reg     = "Reg"
    case unknown = "Unknown"
}

enum StreetName: String, Codable, CaseIterable {
    case preflop
    case flop
    case turn
    case river
}

enum Outcome: String, Codable {
    case win
    case lose
    case chop
}

/// Hero's outcome for display (the History chip). A superset of `Outcome`: showdowns map straight from
/// `Outcome`, plus `.folded` (hero mucked — the hand ended or went on without them) and `.incomplete`
/// (set aside via Skip with hero still contesting). Derived from a `Hand`, never stored.
enum HandResult {
    case win, lose, chop, folded, incomplete

    var label: String {
        switch self {
        case .win:        return "Won"
        case .lose:       return "Lost"
        case .chop:       return "Chop"
        case .folded:     return "Folded"
        case .incomplete: return "Incomplete"
        }
    }
}

enum PotUnit: String, Codable {
    case bigBlinds  // display as "BB"
    case dollars    // cash games — display with "$" prefix
    case chips      // tournaments — display as plain number, no "$"
}

enum SizingType: String, Codable {
    case multiple       // e.g. 2x, 2.5x, 3x
    case potFraction    // e.g. ½ pot, pot
    case bigBlinds      // flat BB amount e.g. 14BB
    case dollars        // flat dollar amount (cash games)
    case chips          // flat chip amount (tournaments)
}

enum SessionType: String, Codable {
    case cash
    case tournament
}

// MARK: - Supporting Structs

struct Card: Identifiable, Codable, Equatable {
    var id   = UUID()
    var rank: Rank
    var suit: Suit?     // nil = suit not recorded

    var notation: String {
        rank.rawValue + (suit?.rawValue ?? "")
    }
}

struct RaiseSizing: Codable {
    var type:  SizingType
    var value: Double?  // nil for named presets like "Pot"
    var label: String   // display string e.g. "2x", "½ Pot", "14BB", "$120"
}

// MARK: - Core Models

struct Action: Identifiable, Codable {
    var id:           UUID   = UUID()
    var seatIndex:    Int
    var position:     String  // frozen label e.g. "BTN", "UTG" — set at record time
    var actionType:   ActionType
    var sizing:       RaiseSizing?  // non-nil for .open and .raise only
    var isAutoFolded: Bool = false  // true when the fold was system-generated (preflop jump skip)
}

struct Street: Identifiable, Codable {
    var id:      UUID       = UUID()
    var name:    StreetName
    var actions: [Action]   = []
    // Board cards are NOT stored here. They live on the hand's canonical card groups
    // (`flopGroup`/`turnGroup`/`riverGroup`), the single source of truth; derive `Hand.board` from those.
}

struct Villain: Identifiable, Codable {
    var id:         UUID        = UUID()
    var seatIndex:  Int
    var tag:        VillainTag? = .unknown
    var descriptor: String?     // e.g. "middle aged guy with headphones"
    var notes:      String?     // running reads, updated during session
    var isActive:   Bool        = true  // false = busted out or left the table
}

struct Hand: Identifiable, Codable {
    var id:               UUID     = UUID()
    var sessionId:        UUID
    var handNumber:       Int
    var title:            String?
    var timestamp:        Date     = Date()
    var heroSeatIndex:    Int
    var buttonSeatIndex:  Int

    // Table composition — drives position labels. `occupiedSeatIndices` are the seats with a player
    // this hand (empties excluded); positions are computed over these. `tableSize` lets a replayed
    // hand reconstruct the physical table shape.
    var tableSize:           Int
    var occupiedSeatIndices: [Int]

    // Canonical, lossless card storage. The `CardGroup` is the faithful artifact the transcript renders
    // from (bound / footnote / relationship suit modes, explicit `x`, board-suit counts all survive).
    // A board group is nil until that street was entered.
    var holeGroup:     CardGroup
    var flopGroup:     CardGroup?        = nil
    var turnGroup:     CardGroup?        = nil
    var riverGroup:    CardGroup?        = nil
    var villainGroups: [Int: CardGroup]  = [:]   // seatIndex → that villain's shown cards; showdown only

    var streets:          [Street] = []   // only streets that were played (actions only — no board)
    /// The furthest street the hand reached (the live `currentStreet` at close). Stored because it
    /// can't be recovered from `streets`: a run-out records an empty `turn` street and never records
    /// the `river` at all, and a fold-out can carry a stray later-street card from post-hoc entry.
    /// This is the transcript/replay upper bound — how far the board is read out.
    var lastStreet:       StreetName = .preflop
    var outcome:          Outcome?
    var potSize:          Double?
    var potUnit:          PotUnit?
    var effectiveStack:   Double?         // optional, in same unit as potUnit
    var commentary:       String?

    // MARK: Derived (computed, not stored) — keep the flat `[Card]` API for simple consumers.
    var holeCards: [Card] { holeGroup.asCards }
    var villainCards: [Int: [Card]] { villainGroups.mapValues { $0.asCards } }
    var board: [Card] { [flopGroup, turnGroup, riverGroup].compactMap { $0 }.flatMap { $0.asCards } }

    /// Seats that folded at any point this hand (across all streets) — the shared fold-log scan behind
    /// the derived membership properties below.
    private var foldedSeatIndices: Set<Int> {
        Set(streets.flatMap { $0.actions }.filter { $0.actionType == .fold }.map { $0.seatIndex })
    }

    /// Occupied seats still in the hand at the end (hero included) — derived from the fold log, so it
    /// can't drift from the actions.
    var stillInSeatIndices: [Int] { occupiedSeatIndices.filter { !foldedSeatIndices.contains($0) } }

    /// Seats still in at the end, hero excluded (the showdown villains).
    var showdownSeatIndices: [Int] { stillInSeatIndices.filter { $0 != heroSeatIndex } }

    /// True when the hand went to a contested end (a showdown / run-out), i.e. ≥2 seats — hero
    /// included — were unfolded at the end. A fold-out leaves exactly one, so it's false. Gates the
    /// villain "shows" lines in the transcript for a saved hand.
    var reachedShowdown: Bool { stillInSeatIndices.count >= 2 }

    /// Hero's result for the History chip — derived, never stored. A showdown maps straight from
    /// `outcome`; with none recorded, the fold log recovers a fold-out win (hero the sole survivor), a
    /// fold (hero mucked), or an incomplete hand (Skip with hero still in).
    var result: HandResult {
        switch outcome {
        case .win:  return .win
        case .lose: return .lose
        case .chop: return .chop
        case nil:
            let stillIn = stillInSeatIndices
            if !stillIn.contains(heroSeatIndex) { return .folded }   // hero mucked
            return stillIn.count == 1 ? .win : .incomplete           // sole survivor vs set aside
        }
    }
}

struct Session: Identifiable, Codable {
    var id:            UUID        = UUID()
    var type:          SessionType
    var name:          String
    var date:          Date
    var tableSize:     Int         // 6, 8, 9, or 10 — fixed for the session
    var heroSeatIndex: Int
    var stakes:        String?     // cash only e.g. "2/5"
    var buyIn:         Double?     // tournament only
    var bullet:        Int?        // tournament only — rebuy count
    var startingStack: Double?     // cash only, optional
    var villains:      [Villain]   = []   // session-scoped, keyed by seatIndex
    var hands:         [Hand]      = []
    var startedAt:     Date        = Date()
    var endedAt:       Date?

    // The correct PotUnit for this session type
    var potUnit: PotUnit {
        type == .cash ? .dollars : .chips
    }
}

// MARK: - Position Label Calculation

/// Calculates position labels for all active seats in a hand.
/// Labels are assigned based on active seat count only — empty seats are skipped entirely.
/// Returns a dictionary mapping seatIndex → position label (e.g. [3: "BTN", 4: "SB", 5: "BB"]).
func calculatePositions(buttonSeatIndex: Int, activeSeatIndices: [Int]) -> [Int: String] {
    guard !activeSeatIndices.isEmpty else { return [:] }

    // Sort active seats clockwise starting from the button
    let sorted = activeSeatIndices.sorted()
    guard let btnOffset = sorted.firstIndex(of: buttonSeatIndex) else { return [:] }

    var clockwise: [Int] = []
    for i in 0..<sorted.count {
        clockwise.append(sorted[(btnOffset + i) % sorted.count])
    }
    // clockwise[0] = BTN, clockwise[1] = SB, clockwise[2] = BB, ...

    let labels = positionLabels(for: clockwise.count)
    var result: [Int: String] = [:]
    for (i, seat) in clockwise.enumerated() {
        result[seat] = labels[i]
    }
    return result
}

/// Returns the ordered position label set for a given active player count.
private func positionLabels(for count: Int) -> [String] {
    switch count {
    case 2:  return ["BTN", "BB"]
    case 3:  return ["BTN", "SB", "BB"]
    case 4:  return ["BTN", "SB", "BB", "UTG"]
    case 5:  return ["BTN", "SB", "BB", "UTG", "CO"]
    case 6:  return ["BTN", "SB", "BB", "UTG", "HJ", "CO"]
    case 7:  return ["BTN", "SB", "BB", "UTG", "LJ", "HJ", "CO"]
    case 8:  return ["BTN", "SB", "BB", "UTG", "UTG+1", "LJ", "HJ", "CO"]
    case 9:  return ["BTN", "SB", "BB", "UTG", "UTG+1", "MP", "LJ", "HJ", "CO"]
    case 10: return ["BTN", "SB", "BB", "UTG", "UTG+1", "MP", "MP+1", "LJ", "HJ", "CO"]
    default: return (0..<count).map { "Seat \($0 + 1)" }
    }
}

// MARK: - Card Entry Model (canonical, lossless)
//
// These types ARE the faithful card record — the live picker mutates them and the transcript renders
// from them, and a saved `Hand` stores them verbatim (no flat-card collapse). They live here (not in
// the view) so they are part of the persisted model. A rank is never fuzzy → `Rank`; a *known* suit is
// never fuzzy → `Suit`. All the fuzziness (no suit yet, explicit `x`, footnote letters, relationship
// texture) is carried by `FrameSuit` + the group's suit mode.

/// One frame's suit state. `.known` is the only concrete suit (typed `Suit`); the rest is fuzziness.
enum FrameSuit: Equatable, Codable {
    case unspecified        // nothing entered yet (blank)
    case unknown            // explicit "x" — always shows/reads as x, even alone (Jx, Qx)
    case known(Suit)        // a real, bound suit

    /// The bound `Suit` when one is set, else nil (both `.unspecified` and `.unknown`).
    var knownSuit: Suit? { if case .known(let s) = self { return s } else { return nil } }
    /// The suit glyph for the display layer, derived from `knownSuit` (keeps glyph-based UI unchanged).
    var knownSymbol: String? { knownSuit?.symbol }
}

/// One card frame: a rank, plus a bound suit that is only meaningful while the group is `.bound`.
struct CardFrame: Equatable, Codable {
    var rank: Rank?            = nil
    var suit: FrameSuit        = .unspecified
    var isEmpty: Bool { rank == nil }
}

/// A street's group of frames plus its single suit mode. Hole = 2 frames, flop = 3, turn/river = 1.
/// The mode determines how suit info is stored and rendered (see `groupNotation` in the view):
/// - `.bound`        per-frame suit (interleaved entry) — `AdJx`
/// - `.footnote`     an unassigned trailing note of suit letters — `AJdx`
/// - `.relationship` an abstract relationship/texture from a shortcut button — `AJs` / `Q53tt`
struct CardGroup: Equatable, Codable {
    enum SuitMode: Equatable, Codable { case none, bound, footnote, relationship }

    var frames: [CardFrame]
    var mode: SuitMode = .none
    var footnote: [String] = []      // ordered suit letters ("s/h/d/c" or "x"); used only in .footnote
    var footnoteCursor: Int = 0      // wrap-replace pointer once the footnote is full
    var relationship: String? = nil  // "s","o" (hole) | "r","m","tt" (flop); used only in .relationship
    var suitRun: Int = 1             // turn/river only: count of this card's suit on the board (4h=1, 4hhh=3)

    var capacity: Int { frames.count }
    var ranksFilled: Int { frames.filter { $0.rank != nil }.count }
    var isFull: Bool { ranksFilled == capacity }
    var hasAnyRank: Bool { ranksFilled > 0 }
    var firstEmptyIndex: Int? { frames.firstIndex(where: { $0.isEmpty }) }

    init(capacity: Int) { self.frames = Array(repeating: CardFrame(), count: capacity) }

    mutating func reset() {
        frames = Array(repeating: CardFrame(), count: capacity)
        mode = .none; footnote = []; footnoteCursor = 0; relationship = nil; suitRun = 1
    }

    /// Flat `[Card]` collapse for simple consumers — rank + the bound suit (nil suit when unknown/footnote/
    /// relationship). The lossless detail stays in the group; this is the lossy convenience derivation.
    var asCards: [Card] {
        frames.compactMap { f in
            guard let rank = f.rank else { return nil }
            return Card(rank: rank, suit: f.suit.knownSuit)
        }
    }
}
