import Foundation

// MARK: - Pure renderers (the DRY core)
//
// Table visuals and the shorthand transcript as pure functions of hand data — no live `@State`. The
// live `HandEntryView` calls these with its current state; History rows and Replay call them with a
// saved `Hand`. One implementation draws all three. (See HistoryFeature Phase 3.)
//
// `SeatState` and the seat render components are unchanged — this file only moves *derivation*.

// MARK: Seat-state deriver

/// Each seat's `SeatState` for one rendered street: fold ghosts, per-seat action histories with frozen
/// bet-level pips, the owes-fresh-response center demotion, size pills, and the cross-street all-in
/// amber badge. Pure — every input is passed in.
///
/// - Parameters:
///   - streetActions: the actions of the street being rendered (live: the display street; replay: the
///     hand's per-street slice).
///   - foldedBefore: every seat folded so far (folds on the rendered street are detected from
///     `streetActions` and shown as their fold, not a ghost).
///   - allIn: seats that are all-in — drives the amber badge across streets.
///   - allActions: every action in the hand — recovers HOW an all-in seat got committed on a street
///     where it took no action of its own.
///   - highlighted: the cue seat while recording; `nil` for replay / a closed hand.
///   - owes: re-aggression test for the cue seat (acted earlier, now owes a fresh response); pass a
///     constant-false closure for replay.
func seatStates(
    streetActions: [Action],
    foldedBefore:  Set<Int>,
    allIn:         Set<Int>,
    allActions:    [Action],
    highlighted:   Int?,
    owes:          (Int) -> Bool
) -> [Int: SeatState] {
    var result: [Int: SeatState] = [:]

    // Ghost seats for folds that happened on prior streets (relative to the displayed street).
    let foldedThisStreet = Set(streetActions.filter { $0.actionType == .fold }.map { $0.seatIndex })
    for seat in foldedBefore where !foldedThisStreet.contains(seat) {
        result[seat] = SeatState(action: .foldedOut)
    }

    // Build each seat's action history this street in log order, capturing the bet level frozen at
    // each entry so prior aggression keeps its pip layout.
    var histories: [Int: [(action: SeatState.Action, betLevel: Int)]] = [:]
    for action in streetActions {
        let seatAction: SeatState.Action
        switch action.actionType {
        case .fold:  seatAction = .fold
        case .call:  seatAction = .call
        case .check: seatAction = .check
        case .open:  seatAction = .open
        case .raise: seatAction = .raise
        }
        let levelAtThisPoint = streetActions
            .prefix(while: { $0.id != action.id })
            .filter { $0.actionType == .open || $0.actionType == .raise }
            .count + (action.actionType == .open || action.actionType == .raise ? 1 : 0)
        histories[action.seatIndex, default: []].append((seatAction, levelAtThisPoint))
    }

    // The most recent entry is the seat's current state; everything before it is prior-action badges.
    for (seat, history) in histories {
        // The on-clock seat that owes a FRESH response (acted earlier, then a bet/raise was logged
        // after) has not made its current decision — demote its whole history to prior pills and leave
        // the center empty so it reads like any other on-the-clock seat.
        if seat == highlighted, owes(seat) {
            result[seat] = SeatState(action: nil, priorActions: history.map { $0.action })
            continue
        }
        let current = history.last!
        let prior = history.dropLast().map { $0.action }
        let sizeLabel = streetActions.last { $0.seatIndex == seat }?.sizing?.label
        result[seat] = SeatState(
            action: current.action,
            betLevel: current.betLevel,
            priorActions: Array(prior),
            sizeLabel: sizeLabel,
            isAllIn: allIn.contains(seat)
        )
    }

    // All-in badge persists across streets. On a street where an all-in seat has no action of its
    // own, surface it with the symbol of HOW it got all-in (jam-bet →, jam-raise ↑↑, call-all-in ✓).
    for seat in allIn {
        if var existing = result[seat] {
            existing.isAllIn = true
            result[seat] = existing
        } else if let mark = allActions.last(where: { $0.seatIndex == seat && $0.sizing?.label == "All-in" }) {
            let sym: SeatState.Action
            switch mark.actionType {
            case .call:  sym = .call
            case .open:  sym = .open
            case .raise: sym = .raise
            default:     sym = .call
            }
            result[seat] = SeatState(action: sym, isAllIn: true)
        }
    }
    return result
}

// MARK: - Card notation (see ShorthandReference.md §2)

/// Shorthand for a card group — used for hero streets, board streets, and villain hole groups.
func groupNotation(_ g: CardGroup) -> String {
    let ranks = g.frames.compactMap { $0.rank?.rawValue }
    guard !ranks.isEmpty else { return "" }
    let rankStr = ranks.joined()

    switch g.mode {
    case .none:
        return rankStr                                       // AJ / Q53 / J
    case .relationship:
        return rankStr + (g.relationship ?? "")              // AJs / Q53r / Q53tt
    case .footnote:
        return rankStr + paddedFootnote(g)                   // AJ+[d] -> AJdx; Q53+[h,h] -> Q53hhx
    case .bound:
        // A blank card reads as "x" only when a partner carries a real suit (the inferred AhKx); an
        // explicit unknown always reads as "x" (even alone — Jx, Qx).
        let anyKnown = g.frames.contains { $0.suit.knownSymbol != nil }
        let markUnknown = anyKnown && g.capacity > 1
        return g.frames.compactMap { f -> String? in
            guard let r = f.rank?.rawValue else { return nil }
            switch f.suit {
            // The suit letter repeats by suitRun — the turn/river board count (4h / 4hh / 4hhh).
            case .known(let s): return r + String(repeating: s.rawValue, count: g.suitRun)
            case .unknown:      return r + "x"
            case .unspecified:  return markUnknown ? r + "x" : r
            }
        }.joined()                                           // AdJx / Qh5h3x / Jh / Jx
    }
}

// MARK: - Dead-card detection (duplicate block)

/// Every *known dead card* across the given groups, keyed `"Qh"` (rank letter + suit letter). A card is
/// known-dead only when its rank is unambiguous:
/// - a **bound** frame carries a known per-card suit (`Qh`), or
/// - a **footnote** suit on a group whose rank-bearing frames all share one rank — a pair (`QQhd`) or
///   trips (`QQQhdc`) — pins each suit to that rank even though we don't know which physical card.
/// A mixed-rank footnote (`QJdh`) stays ambiguous and contributes nothing. Drives the picker's
/// duplicate-suit block (see `suitIsDuplicate`).
func deadCardKeys(in groups: [CardGroup]) -> Set<String> {
    var keys = Set<String>()
    for g in groups {
        for f in g.frames {
            if let r = f.rank, let s = f.suit.knownSuit { keys.insert(r.rawValue + s.rawValue) }
        }
        if g.mode == .footnote {
            let ranks = Set(g.frames.compactMap { $0.rank })
            if ranks.count == 1, let r = ranks.first {
                for letter in g.footnote where letter != "x" { keys.insert(r.rawValue + letter) }
            }
        }
    }
    return keys
}

/// Default any ranked, suitless card in a group to explicit `x` (`.unknown`) — applied when a bank is
/// left, so a card typed without a suit reads as "rank, unknown suit" rather than looking incomplete.
/// No-ops when the group should keep its texture option (`keepsTexture`, a full no-suit hole/flop group
/// the caller decides) or carries suit info off the frame (footnote/relationship). A `.none` group with
/// any card x'd becomes `.bound` (it now holds explicit per-card suits).
func normalizingUnsuited(_ g: CardGroup, keepsTexture: Bool) -> CardGroup {
    guard !keepsTexture, g.mode == .none || g.mode == .bound else { return g }
    var out = g
    var changed = false
    for i in out.frames.indices where out.frames[i].rank != nil && out.frames[i].suit == .unspecified {
        out.frames[i].suit = .unknown
        changed = true
    }
    if changed, out.mode == .none { out.mode = .bound }
    return out
}

/// The footnote token: ordered suit letters padded to the group's capacity with `x`.
private func paddedFootnote(_ g: CardGroup) -> String {
    var letters = g.footnote
    while letters.count < g.capacity { letters.append("x") }
    return letters.joined()
}

// MARK: - Shorthand transcript (see ShorthandReference.md)

/// The render order of streets and the canonical board-token source.
private let streetOrder: [StreetName] = [.preflop, .flop, .turn, .river]

/// Build the shorthand transcript from a saved `Hand`. A saved hand is self-describing, so terminal
/// state (`showdownReached`) is derived from it; pass an override only when rendering a live,
/// not-yet-terminal snapshot.
func transcript(for hand: Hand, showdownReached: Bool? = nil) -> String {
    transcript(
        handNumber:      hand.handNumber,
        heroSeat:        hand.heroSeatIndex,
        buttonSeat:      hand.buttonSeatIndex,
        occupiedSeats:   hand.occupiedSeatIndices,
        holeGroup:       hand.holeGroup,
        boardGroups:     (hand.flopGroup, hand.turnGroup, hand.riverGroup),
        villainGroups:   hand.villainGroups,
        effectiveStack:  hand.effectiveStack.map { Int($0) },
        streets:         hand.streets,
        throughStreet:   hand.lastStreet,
        showdownVillains: hand.showdownSeatIndices,
        showdownReached:  showdownReached ?? hand.reachedShowdown,
        outcome:          hand.outcome
    )
}

/// The pieces-based transcript builder. Both consumers feed it: the live recorder passes its `@State`
/// (with `buttonSeat: nil` before the button is placed and the live `currentStreet`/phase), History
/// and Replay pass a saved hand via `transcript(for:)`.
///
/// `streets` must already contain the rendered streets' actions (the live caller folds its
/// in-progress `actionsThisStreet` into the current street). `throughStreet` is the furthest street to
/// read out. The result line is gated by `outcome`; the villain "shows" lines by `showdownReached`.
func transcript(
    handNumber:       Int,
    heroSeat:         Int,
    buttonSeat:       Int?,
    occupiedSeats:    [Int],
    holeGroup:        CardGroup,
    boardGroups:      (flop: CardGroup?, turn: CardGroup?, river: CardGroup?),
    villainGroups:    [Int: CardGroup],
    effectiveStack:   Int?,
    streets:          [Street],
    throughStreet:    StreetName,
    showdownVillains: [Int],
    showdownReached:  Bool,
    outcome:          Outcome?
) -> String {
    var lines: [String] = []

    // Header: Hand #N - [cards] - [position], building from what is currently known.
    var header = "Hand #\(handNumber)"
    if let btn = buttonSeat, heroSeat >= 0 {
        let pos = calculatePositions(buttonSeatIndex: btn, activeSeatIndices: occupiedSeats)[heroSeat] ?? ""
        let cards = groupNotation(holeGroup)
        if !pos.isEmpty {
            header += cards.isEmpty ? " - \(pos)" : " - \(cards) - \(pos)"
        }
    }
    // Effective stack trails the header, independent of cards/position so it shows the moment it's set.
    if let eff = effectiveStack { header += " - \(eff)bb eff" }
    lines.append(header)
    lines.append("")   // blank line separates the header from the action lines

    let throughIdx = streetOrder.firstIndex(of: throughStreet) ?? 0
    for street in streetOrder.prefix(throughIdx + 1) {
        let acts = streets.first(where: { $0.name == street })?.actions ?? []
        let board = boardToken(street, boardGroups)
        if acts.isEmpty && board.isEmpty { continue }

        var segments: [String] = []
        if !board.isEmpty { segments.append(board) }

        let isPreflop = (street == .preflop)
        var aggCount = 0
        var sawAgg = false
        var pairs: [(actor: String, token: String)] = []

        for a in acts {
            // Preflop: suppress a fold if it is that player's only action on this street — they were
            // never voluntarily in the hand (a pure pre-action folder).
            if isPreflop && a.actionType == .fold {
                let seatActs = acts.filter { $0.seatIndex == a.seatIndex }
                if seatActs.count == 1 { continue }
            }

            let isAgg = (a.actionType == .open || a.actionType == .raise)
            if isAgg { aggCount += 1 }
            let token = actionToken(a, isPreflop: isPreflop, aggIndex: aggCount, priorAggression: sawAgg)
            if isAgg { sawAgg = true }

            let actor = (a.seatIndex == heroSeat) ? "Hero" : a.position
            pairs.append((actor: actor, token: token))
        }

        segments += collapsedSegments(pairs)
        if !segments.isEmpty { lines.append(segments.joined(separator: ". ") + ".") }
    }

    // Villain shown cards (showdown) — "CO shows AQs." lines, before any result line (§9).
    if showdownReached {
        for seat in showdownVillains {
            let note = villainGroups[seat].map(groupNotation) ?? ""
            if !note.isEmpty {
                let pos = buttonSeat.map { calculatePositions(buttonSeatIndex: $0, activeSeatIndices: occupiedSeats)[seat] ?? "?" } ?? "?"
                lines.append("\(pos) shows \(note).")
            }
        }
    }

    // Showdown result line (fold-out has no tag — the final fold ends it).
    if let outcome = outcome {
        switch outcome {
        case .win:  lines.append("Hero wins.")
        case .lose: lines.append("Hero loses.")
        case .chop: lines.append("Chop.")
        }
    }

    return lines.joined(separator: "\n")
}

/// The bare board token leading a post-flop line (empty preflop).
private func boardToken(_ street: StreetName, _ groups: (flop: CardGroup?, turn: CardGroup?, river: CardGroup?)) -> String {
    switch street {
    case .preflop: return ""
    case .flop:    return groups.flop.map(groupNotation) ?? ""
    case .turn:    return groups.turn.map(groupNotation) ?? ""
    case .river:   return groups.river.map(groupNotation) ?? ""
    }
}

/// The verb-or-size token for one action. Elision: a sized wager shows just the size (All-in → jam).
private func actionToken(_ a: Action, isPreflop: Bool, aggIndex: Int, priorAggression: Bool) -> String {
    switch a.actionType {
    case .fold:  return "fold"
    case .check: return "chk"
    case .call:
        if a.sizing?.label == "All-in" { return "call (all-in)" }   // a call that committed the rest
        return (isPreflop && !priorAggression) ? "limp" : "call"
    case .open:
        // The opening wager of a street (post-flop bet). When sized it elides to the bare size; the
        // All-in marker becomes the verb `jam`.
        if let label = a.sizing?.label { return label == "All-in" ? "jam" : label }
        return isPreflop ? "R" : "bet"
    case .raise:
        if a.sizing?.label == "All-in" { return "jam" }
        // aggIndex 1 is the pre-flop open (recorded as a `.raise` by the Raise button) — the opening
        // wager, so it behaves like `.open` above. (Post-flop the open is an `.open`, so a `.raise`
        // there is always aggIndex 2+.)
        if aggIndex <= 1 { return a.sizing?.label ?? "R" }
        // A genuine re-raise. Escalation ladder, unified across streets: `level` counts wagers
        // including the implied pre-flop blind, so a pre-flop open and a post-flop first raise are both
        // level 2 → "R"; level 3+ → "3b", "4b", "5b" … A size, when entered, is appended.
        let level = aggIndex + (isPreflop ? 1 : 0)
        let verb = level <= 2 ? "R" : "\(level)b"
        if let label = a.sizing?.label { return "\(verb) \(label)" }
        return verb
    }
}

/// Collapses consecutive (actor, token) pairs that share the same token into "A & B verb" or
/// "A, B & C verb". Non-consecutive same-token pairs are not collapsed.
private func collapsedSegments(_ pairs: [(actor: String, token: String)]) -> [String] {
    var result: [String] = []
    var i = 0
    while i < pairs.count {
        let token = pairs[i].token
        var group = [pairs[i].actor]
        while i + 1 < pairs.count && pairs[i + 1].token == token {
            i += 1
            group.append(pairs[i].actor)
        }
        if group.count == 1 {
            result.append("\(group[0]) \(token)")
        } else {
            let joined = group.dropLast().joined(separator: ", ") + " & " + group.last!
            result.append("\(joined) \(token)")
        }
        i += 1
    }
    return result
}
