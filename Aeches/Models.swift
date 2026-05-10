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
    var id:         UUID   = UUID()
    var seatIndex:  Int
    var position:   String  // frozen label e.g. "BTN", "UTG" — set at record time
    var actionType: ActionType
    var sizing:     RaiseSizing?  // non-nil for .open and .raise only
}

struct Street: Identifiable, Codable {
    var id:         UUID       = UUID()
    var name:       StreetName
    var boardCards: [Card]     // empty for preflop; 3 for flop; 1 for turn/river
    var actions:    [Action]   = []
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
    var activeSeatIndices: [Int]   // occupied seats this hand — drives position label calculation
    var holeCards:        [Card]   = []   // hero's cards, 0–2
    var streets:          [Street] = []   // only streets that were played
    var outcome:          Outcome?
    var potSize:          Double?
    var potUnit:          PotUnit?
    var effectiveStack:   Double?         // optional, in same unit as potUnit
    var commentary:       String?
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
    case 7:  return ["BTN", "SB", "BB", "UTG", "MP", "HJ", "CO"]
    case 8:  return ["BTN", "SB", "BB", "UTG", "UTG+1", "MP", "HJ", "CO"]
    case 9:  return ["BTN", "SB", "BB", "UTG", "UTG+1", "MP", "MP+1", "HJ", "CO"]
    case 10: return ["BTN", "SB", "BB", "UTG", "UTG+1", "MP", "MP+1", "MP+2", "HJ", "CO"]
    default: return (0..<count).map { "Seat \($0 + 1)" }
    }
}
