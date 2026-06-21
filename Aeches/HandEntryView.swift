import SwiftUI
import UIKit

// MARK: - StreetName Extension

extension StreetName {
    func next() -> StreetName? {
        switch self {
        case .preflop: return .flop
        case .flop:    return .turn
        case .turn:    return .river
        case .river:   return nil
        }
    }
}

// MARK: - Main Hand Entry View

struct HandEntryView: View {
    let session: Session
    var onBack: () -> Void

    // Hero seat — locked for the session
    @State private var heroSeat: Int? = nil
    @State private var tableSize: Int

    // Hand state
    @State private var handNumber: Int = 1
    @State private var buttonSeat: Int? = nil

    // Street state
    @State private var currentStreet: StreetName = .preflop
    @State private var streets: [Street] = []
    @State private var actionsThisStreet: [Action] = []
    @State private var betLevelThisStreet: Int = 0
    @State private var activeSeatSequence: [Int] = []
    @State private var foldedSeats: Set<Int> = []
    @State private var highlightedSeat: Int? = nil
    @State private var savedHands: [Hand] = []

    /// True only when a decisive input (swipe / action button) on the last actor completed the
    /// betting round, so the ring is held on that seat awaiting a Next Street tap. In this state the
    /// seat drops its highlight/pulse entirely and the Next Street button pulses instead. Reset to
    /// false by every record/tap/rewind/advance/deal via `recomputeDerivedState` + `resetHandState`.
    @State private var streetClosedDecisively: Bool = false

    // Card state
    @State private var heroCards: [CardSlot]  = [CardSlot(), CardSlot()]
    @State private var flopCards: [CardSlot]  = [CardSlot(), CardSlot(), CardSlot()]
    @State private var turnCard:  CardSlot    = CardSlot()
    @State private var riverCard: CardSlot    = CardSlot()

    // Card picker state
    // Card entry is per-street group (hole pair / flop / turn / river), not a single slot. `entryStreet`
    // is the open group (nil = picker closed); `focusIndex` is the frame within it being edited.
    @State private var entryStreet: CardStreet? = nil
    @State private var focusIndex: Int = 0

    // Hand-close state
    @State private var handCloseSummary: String = ""

    @State private var phase: Phase = .selectSeat

    enum Phase { case selectSeat, placingButton, recordingHand, showdown, handClosed }

    init(session: Session, onBack: @escaping () -> Void) {
        self.session = session
        self.onBack = onBack
        _tableSize = State(initialValue: session.tableSize)
    }

    // MARK: - Computed Properties

    private var openBetExists: Bool { betLevelThisStreet > 0 }

    private var feltActionText: String? {
        guard phase == .recordingHand, !streetClosedDecisively, let seat = highlightedSeat else { return nil }
        let pos = seatPositions[seat] ?? "?"
        return "Action on \(pos)"
    }

    private var tableInstruction: String? {
        switch phase {
        case .selectSeat:    return "TAKE\nYOUR SEAT"
        case .placingButton: return "PLACE\nTHE BUTTON"
        case .handClosed:    return "TAP A SEAT\nTO DEAL"
        default:             return nil
        }
    }

    private var seatPositions: [Int: String] {
        guard let btn = buttonSeat else { return [:] }
        return calculatePositions(
            buttonSeatIndex: btn,
            activeSeatIndices: Array(0..<tableSize)
        )
    }

    /// A fold-out is set up but not yet committed: every seat but one has folded (only reachable
    /// via direct-tap cycle folds, which don't auto-end the hand). The button commits it.
    private var pendingFoldOut: Bool {
        phase == .recordingHand && activeSeatSequence.count == 1
    }

    /// True only when the street is genuinely closed, or (preflop only) when a fast-forward is
    /// safe: a raise exists, no committed player faces unresolved aggression, BB has acted (so
    /// limped pots are excluded), and at least 2 players have committed chips.
    private var canAdvanceStreet: Bool {
        guard phase == .recordingHand, !pendingFoldOut else { return false }
        if streetIsClosed() { return true }
        guard currentStreet == .preflop else { return false }
        guard betLevelThisStreet > 0 else { return false }  // limped pot — BB must act first
        let actedSeats = Set(actionsThisStreet.map { $0.seatIndex })
        let anyActedOwes = activeSeatSequence.contains { actedSeats.contains($0) && owesAction($0) }
        if anyActedOwes { return false }
        let committed = activeSeatSequence.filter { actedSeats.contains($0) }
        return committed.count >= 2
    }

    /// The button is live either to advance the street or to commit a pending fold-out.
    private var nextStreetButtonEnabled: Bool {
        canAdvanceStreet || pendingFoldOut
    }

    /// Button label: "End Hand" when committing a fold-out, otherwise the next street (River → Showdown).
    private var nextStreetLabel: String {
        if pendingFoldOut { return "End Hand" }
        switch currentStreet {
        case .preflop: return "Flop"
        case .flop:    return "Turn"
        case .turn:    return "River"
        case .river:   return "Showdown"
        }
    }

    // MARK: - Rewind Button (top-left of table)

    /// Live whenever there is something to undo: an action on this/earlier street, or a closed
    /// hand to re-open (showdown overlay or hand-closed state are both reversible).
    private var rewindButtonEnabled: Bool {
        // During recording there is always at least the button placement to undo (pick the button
        // back up), so Undo is live the moment a hand starts — even before any action is recorded.
        phase == .showdown || phase == .handClosed || phase == .recordingHand
            || !actionsThisStreet.isEmpty || !streets.isEmpty
    }

    // MARK: - Next Street action (top-right of control row)

    /// The Next-Street / End-Hand button's action: commit a pending fold-out, run the preflop
    /// fast-forward (auto-fold unacted seats), then advance the street or open the showdown. This
    /// is the ONLY path that advances a street — taps, swipes, and action buttons never do.
    private func handleNextStreet() {
        withAnimation(.easeInOut(duration: 0.15)) {
            // Advancing leaves the decisive-close state. Required for the river→showdown path, which
            // sets phase without a recompute and would otherwise leak the flag into showdown.
            streetClosedDecisively = false
            if pendingFoldOut {
                triggerFoldOut()
                return
            }
            if !streetIsClosed() {
                // Preflop fast-forward: auto-fold all unacted active seats.
                let actedSeats = Set(actionsThisStreet.map { $0.seatIndex })
                let unacted = activeSeatSequence.filter { !actedSeats.contains($0) }
                let didFoldOut = autoFoldSeats(unacted, autoFolded: true)
                guard !didFoldOut else { return }
            }
            advanceStreetOrShowdown()
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Nav bar ───────────────────────────────────────────
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.gold)
                    }
                    Spacer()
                    Text(phase == .selectSeat ? "Select Your Seat" : "Hand #\(handNumber)")
                        .font(.custom("Arial", size: 17))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.textBody)
                    Spacer()
                    Image(systemName: "chevron.left").foregroundStyle(.clear)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 4)

                // ── Status line ───────────────────────────────────────
                statusLine
                    .padding(.bottom, 6)

                // ── Table (top half) ──────────────────────────────────
                TableOvalView(
                    tableSize: tableSize,
                    heroSeat: heroSeat,
                    buttonSeat: buttonSeat,
                    seatStates: seatActions,
                    // On a decisive close the ring drops entirely (Option A) — the pulse hands off to
                    // the Next Street button. The data pointer (`highlightedSeat`) stays intact for
                    // tap/rewind logic; only the *visual* highlight is suppressed here.
                    activeSeat: streetClosedDecisively ? nil : highlightedSeat,
                    positions: seatPositions,
                    onSeatTap: handleSeatTap,
                    onSeatSwipe: handleSeatSwipe,
                    sizingStrip: sizingStrip(for:),
                    onSeatSize: handleSeatSize,
                    instruction: tableInstruction,
                    actionText: feltActionText
                )
                .overlay {
                    if phase == .showdown {
                        ShowdownOverlay(onResolve: resolveShowdown)
                            .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    }
                }
                .padding(.horizontal, 8)
                .animation(.easeInOut(duration: 0.25), value: phase == .showdown)

                // ── Table size picker (seat select only) ──────────────
                if phase == .selectSeat {
                    HStack(spacing: 6) {
                        Text("Table Size")
                            .font(.custom("Arial", size: 11))
                            .fontWeight(.semibold)
                            .tracking(0.8)
                            .foregroundStyle(Color.textMuted)
                        Spacer()
                        ForEach([6, 8, 9, 10], id: \.self) { size in
                            Button(action: { tableSize = size }) {
                                Text("\(size)")
                                    .font(.custom("Arial", size: 11))
                                    .fontWeight(.bold)
                                    .frame(width: 28, height: 20)
                                    .background(tableSize == size ? Color.gold : Color.surface3)
                                    .foregroundStyle(tableSize == size ? Color(hex: "#0D0D0D") : Color.textMuted)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
                }

                Divider()
                    .background(Color.borderDark)
                    .padding(.top, 8)

                // ── Bottom half — Card strip ───────────────────────────
                if phase == .recordingHand || phase == .showdown || phase == .handClosed {
                    cardStrip
                        .padding(.top, 10)
                }

                // ── Gap zone — the shorthand transcript by default, or the card picker while a card
                // group is open. The strip slots stay visible above either way; the two never show
                // at once (you're either reading the line or entering a card).
                if entryStreet != nil {
                    Spacer(minLength: 0)
                    cardPickerPanel
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    if (phase == .recordingHand || phase == .showdown || phase == .handClosed),
                       !handShorthand.isEmpty {
                        transcriptPanel
                            .padding(.top, 12)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        // ── Unified control row (Rewind · actions · Next Street) ────────
        .safeAreaInset(edge: .bottom) {
            if phase == .recordingHand || phase == .showdown || phase == .handClosed {
                ControlBar(
                    isRecording: phase == .recordingHand,
                    currentStreet: currentStreet,
                    openBetExists: openBetExists,
                    highlightedSeat: highlightedSeat,
                    rewindEnabled: rewindButtonEnabled,
                    nextStreetEnabled: nextStreetButtonEnabled,
                    nextStreetPulsing: streetClosedDecisively,
                    nextStreetLabel: nextStreetLabel,
                    onAction: { commitAction($0) },
                    onRewind: { withAnimation(.easeInOut(duration: 0.15)) { undoLastAction() } },
                    onNextStreet: handleNextStreet
                )
            }
        }
        .animation(.easeInOut(duration: 0.2), value: entryStreet != nil)
        .animation(.easeInOut(duration: 0.2), value: phase)
    }

    // MARK: - Status Line

    @ViewBuilder private var statusLine: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusDotColor)
                .frame(width: 6, height: 6)
                .shadow(color: statusDotColor.opacity(0.8), radius: 4)
            Text(statusText)
                .font(.custom("Arial", size: 12))
                .fontWeight(phase == .selectSeat ? .regular : .semibold)
                .foregroundStyle(statusDotColor)
        }
    }

    private var statusDotColor: Color {
        switch phase {
        case .selectSeat:    return Color.textMuted
        case .placingButton: return Color.gold
        case .recordingHand: return Color.winGreen
        case .showdown:      return Color.gold
        case .handClosed:
            switch handCloseSummary {
            case "You win":  return Color.winGreen
            case "You lose": return Color.foldRed
            case "Chop":     return Color.gold
            default:         return Color.textMuted
            }
        }
    }

    private var statusText: String {
        switch phase {
        case .selectSeat:    return "Tap your seat to begin"
        case .placingButton: return "Tap any seat to place the dealer button"
        case .recordingHand:
            if let btn = buttonSeat { return "Dealer: Seat \(btn + 1)  ·  Record action or fill in cards" }
            return "Recording Hand #\(handNumber)"
        case .showdown:      return "Showdown — select a winner"
        case .handClosed:
            return handCloseSummary.isEmpty
                ? "Hand saved · Tap New Hand to continue"
                : "\(handCloseSummary) · Tap New Hand to continue"
        }
    }

    // MARK: - Seat Tap Handler

    private func handleSeatTap(_ seat: Int) {
        switch phase {
        case .selectSeat:
            heroSeat = seat
            phase = .placingButton

        case .placingButton:
            buttonSeat = seat
            activeSeatSequence = Array(0..<tableSize)
            highlightedSeat = firstActor(of: .preflop)
            phase = .recordingHand

        case .recordingHand:
            // Preflop and post-flop are two different interaction models. Keep them fully
            // separate so a tap can never fall through into the other street's logic.
            if currentStreet == .preflop {
                handlePreflopTap(seat)
            } else {
                handlePostflopTap(seat)
            }

        case .showdown:
            break

        case .handClosed:
            // The hand is over — tapping any seat places the dealer button there and deals the
            // next hand. Reuses the exact gesture used to place the button on hand #1.
            withAnimation(.easeInOut(duration: 0.2)) { dealNextHand(buttonAt: seat) }
        }
    }

    // MARK: - Seat Tap Routing — Preflop (navigation model)

    /// Preflop, a tap moves the action TO the seat you point at, folding the seats you skip past.
    /// The tapped seat is always the destination.
    private func handlePreflopTap(_ seat: Int) {
        // The seat on the clock cycles its own action in place.
        if seat == highlightedSeat { cycleSeat(seat); return }
        // Folded or empty seats are dead. (Hero is a normal active seat — no special-casing.)
        guard activeSeatSequence.contains(seat) else { return }
        // A seat that has acted and faces no new aggression is resolved — cannot be retouched.
        if hasActed(seat) && !owesAction(seat) { return }
        // Re-aggression block: if the seat on the clock has acted but owes a response to new
        // aggression, it must decide first — no tap can move the action forward past it.
        if let hs = highlightedSeat, hasActed(hs) && owesAction(hs) { return }
        // Cannot skip over a seat that has already acted this street — it must respond in sequence
        // and cannot be auto-folded.
        let between = seatsStrictlyBetween(from: highlightedSeat ?? seat, to: seat, in: activeSeatSequence)
        if between.contains(where: { hasActed($0) }) { return }
        // Otherwise jump the action here, folding everyone skipped clockwise. This covers both
        // never-acted seats and seats that acted but owe again after a raise (e.g. UTG facing a
        // 3-bet) — they are all just "act on this seat next".
        withAnimation(.easeInOut(duration: 0.15)) { preflopJump(to: seat) }
    }

    /// Auto-folds the seat being left (if it never acted) and every active seat skipped over
    /// clockwise, then records the tapped seat's default (a call/limp) and leaves it on the clock.
    /// If the auto-folds leave a single player the hand ends as a fold-out.
    private func preflopJump(to seat: Int) {
        if autoResolveSkipped(to: seat) { return }   // fold-out ended the hand
        highlightedSeat = seat
        recordAction(.call, for: seat)
    }

    /// Auto-resolves the seats skipped going clockwise from the highlight to `seat`: preflop they
    /// FOLD, post-flop (no wager) they CHECK. The on-clock seat is included if it never acted. All
    /// are flagged isAutoFolded so one Rewind press removes the batch. Returns true if a fold-out
    /// ended the hand (caller must stop). Shared by the tap jumps and the swipe jumps.
    @discardableResult
    private func autoResolveSkipped(to seat: Int) -> Bool {
        var skipped: [Int] = []
        if let from = highlightedSeat, activeSeatSequence.contains(from), !hasActed(from) {
            skipped.append(from)
        }
        skipped += seatsStrictlyBetween(from: highlightedSeat ?? seat, to: seat, in: activeSeatSequence)
            .filter { !hasActed($0) }

        if currentStreet == .preflop {
            return autoFoldSeats(skipped, autoFolded: true)    // may trigger a fold-out
        } else {
            for s in skipped { recordAction(.check, for: s, autoFolded: true) }
            return false                                       // checks never reduce the active count
        }
    }

    // MARK: - Seat Tap Routing — Post-flop (commit model)

    /// Post-flop, a tap commits whoever is on the clock and advances to the next seat that owes
    /// action. The tapped seat is only a trigger, not a destination — there is no fold-by-skipping
    /// post-flop (a skipped seat checks, it does not fold).
    private func handlePostflopTap(_ seat: Int) {
        // The seat on the clock cycles its own action in place.
        if seat == highlightedSeat { cycleSeat(seat); return }
        // Folded or empty seats are dead.
        guard activeSeatSequence.contains(seat) else { return }
        // A seat that has acted and faces no new aggression is resolved.
        if hasActed(seat) && !owesAction(seat) { return }
        // Re-aggression block: the seat on the clock must respond to new aggression before the
        // action can move forward.
        if let hs = highlightedSeat, hasActed(hs) && owesAction(hs) { return }

        if openBetExists {
            // Bet context: strict order only. Only the exact next seat that owes action can be
            // tapped — no auto-actions, no fold-by-skipping.
            guard seat == nextOwingSeat(after: highlightedSeat ?? seat) else { return }
            withAnimation(.easeInOut(duration: 0.15)) { stepToNextPostflopActor(to: seat) }
        } else {
            // No-bet context: auto-check jump, mirroring preflop auto-fold. Cannot skip a seat that
            // has already checked.
            let between = seatsStrictlyBetween(from: highlightedSeat ?? seat, to: seat, in: activeSeatSequence)
            if between.contains(where: { hasActed($0) }) { return }
            withAnimation(.easeInOut(duration: 0.15)) { postflopJump(to: seat) }
        }
    }

    /// Post-flop no-bet equivalent of `preflopJump`. Auto-checks the seat on the clock (if it
    /// never acted) and every unacted seat strictly between, then lands the destination at Check.
    /// Auto-checks reuse the `isAutoFolded` batch flag so a single Rewind press removes them. No
    /// fold-out guard is needed — checks never reduce the active-seat count.
    private func postflopJump(to seat: Int) {
        _ = autoResolveSkipped(to: seat)
        // Land on the destination at Check immediately. Not auto-flagged, so Rewind pops this
        // Check first, then strips the auto-check batch behind it in the same press.
        highlightedSeat = seat
        recordAction(.check, for: seat)
    }

    /// Post-flop bet context: commits the seat on the clock (its default if it never cycled one),
    /// then lands the destination at Call immediately. The caller guarantees `seat` is the next
    /// seat that owes action, so this both records the response and advances in one tap.
    private func stepToNextPostflopActor(to seat: Int) {
        guard let current = highlightedSeat else { return }
        if owesAction(current) {
            recordAction(seatFacesBet(current) ? .call : .check, for: current)
        }
        highlightedSeat = seat
        recordAction(.call, for: seat)
    }

    /// The next active seat clockwise from `seat` that still owes an action. Returns nil when every
    /// active seat is square with the current bet — i.e. the round is ready to close.
    private func nextOwingSeat(after seat: Int) -> Int? {
        let ring = clockwiseOrder(from: seat, seats: Array(0..<tableSize))
        return ring.dropFirst().first { owesAction($0) }
    }

    // MARK: - Seat Swipe Routing (decisive: record a specific action + advance)

    /// Maps a swipe direction to the action it records for `seat`, or nil when the direction is
    /// illegal in the current context (strict — caller treats nil as a no-op).
    private func swipeAction(_ dir: SwipeDirection, for seat: Int) -> ActionType? {
        let betContext = currentStreet == .preflop || seatFacesBet(seat)
        switch dir {
        case .left:  return .fold
        case .down:  return betContext ? .call : .check
        case .up:    return betContext ? .raise : nil    // raise only when a wager exists
        case .right: return betContext ? nil   : .open    // bet only when no wager exists
        }
    }

    /// A directional swipe on a seat — decisive: record the resolved action and advance.
    private func handleSeatSwipe(_ seat: Int, _ dir: SwipeDirection) {
        guard phase == .recordingHand else { return }
        guard let action = swipeAction(dir, for: seat) else { return }   // illegal direction → no-op
        routeDecisive(action, to: seat, sizing: nil)
    }

    /// Shared decisive routing for swipes and sized holds — mirrors the tap routing but always
    /// lands a specific action and advances. `sizing` (Phase 2) is attached to the landed action.
    private func routeDecisive(_ action: ActionType, to seat: Int, sizing: RaiseSizing?) {
        withAnimation(.easeInOut(duration: 0.15)) {
            // On-clock seat → record + move to the next player. Routed through finishSwipe (not
            // commitAction) so a swipe never auto-advances the street — only the Next Street button does.
            if seat == highlightedSeat {
                // A decisive gesture SETS this seat's current decision. If the seat already has a
                // standing turn-action (e.g. it was cycled to Call), supersede it rather than stack a
                // second action. owesAction == true means it owes a fresh response (never acted, or
                // facing new aggression) — that's a genuinely separate action, so don't remove it.
                if hasActed(seat) && !owesAction(seat) { removeLastAction(of: seat) }
                finishSwipe(on: seat, action: action, sizing: sizing)
                return
            }
            // Dead seats (folded / not in hand).
            guard activeSeatSequence.contains(seat) else { return }
            // Resolved: acted and owes nothing.
            if hasActed(seat) && !owesAction(seat) { return }
            // Re-aggression: the on-clock seat must respond before any other seat is actionable.
            if let hs = highlightedSeat, hasActed(hs) && owesAction(hs) { return }

            if currentStreet != .preflop && openBetExists {
                // Bet context: strict — only the exact next owing seat, no skip-jumping into a bet.
                guard seat == nextOwingSeat(after: highlightedSeat ?? seat) else { return }
                commitSwipeStrict(to: seat, action: action, sizing: sizing)
            } else {
                // Navigation context: cannot skip an already-acted seat.
                let between = seatsStrictlyBetween(from: highlightedSeat ?? seat, to: seat, in: activeSeatSequence)
                if between.contains(where: { hasActed($0) }) { return }
                commitSwipeJump(to: seat, action: action, sizing: sizing)
            }
        }
    }

    /// Navigation-context swipe: auto-resolve skipped seats, then land `action` on the destination.
    private func commitSwipeJump(to seat: Int, action: ActionType, sizing: RaiseSizing? = nil) {
        if autoResolveSkipped(to: seat) { return }   // fold-out already ended the hand
        finishSwipe(on: seat, action: action, sizing: sizing)
    }

    /// Strict bet-context swipe (the seat IS the next owing seat): commit the on-clock seat's
    /// default response first, then land `action` on the destination.
    private func commitSwipeStrict(to seat: Int, action: ActionType, sizing: RaiseSizing? = nil) {
        if let cur = highlightedSeat, owesAction(cur) {
            recordAction(seatFacesBet(cur) ? .call : .check, for: cur)
        }
        finishSwipe(on: seat, action: action, sizing: sizing)
    }

    /// Shared tail for swipes: record the action on `seat`, then settle (see `settleAfterCommit`).
    /// A swipe picks the action directly instead of cycling to it, then advances the ring to the
    /// next player WITHOUT seeding any action there — identical to an action-button press.
    private func finishSwipe(on seat: Int, action: ActionType, sizing: RaiseSizing? = nil) {
        recordAction(action, for: seat, sizing: sizing)
        settleAfterCommit(on: seat, justFolded: action == .fold)
    }

    // MARK: - Seat Sizing (hold-to-size, Phase 2)

    /// The ordered sizing strip for `seat` (floor → All-in), or [] when sizing isn't applicable.
    /// Multiple strip for any raise/open (preflop is always a bet context); percent strip for a
    /// post-flop opening bet.
    private func sizingStrip(for seat: Int) -> [String] {
        guard phase == .recordingHand, activeSeatSequence.contains(seat) else { return [] }
        let betContext = currentStreet == .preflop || seatFacesBet(seat)
        return betContext ? Self.multipleStrip : Self.betStrip
    }

    /// A completed hold-to-size on `seat`: records the aggressive action (bet/raise by context)
    /// with the chosen size, routed exactly like a swipe.
    private func handleSeatSize(_ seat: Int, _ label: String) {
        guard phase == .recordingHand, activeSeatSequence.contains(seat) else { return }
        let betContext = currentStreet == .preflop || seatFacesBet(seat)
        let action: ActionType = betContext ? .raise : .open
        routeDecisive(action, to: seat, sizing: makeSizing(label))
    }

    /// Builds a RaiseSizing from a strip label — notation only, no chip math.
    private func makeSizing(_ label: String) -> RaiseSizing {
        if label == "All-in" { return RaiseSizing(type: .multiple, value: nil, label: label) }
        if label == "Pot"    { return RaiseSizing(type: .potFraction, value: 1.0, label: label) }
        if label.hasSuffix("x") {
            return RaiseSizing(type: .multiple, value: Double(label.dropLast()), label: label)
        }
        if label.hasSuffix("%") {
            return RaiseSizing(type: .potFraction, value: Double(label.dropLast()).map { $0 / 100 }, label: label)
        }
        return RaiseSizing(type: .multiple, value: nil, label: label)
    }

    /// 2.0x … 5.0x (0.1x steps) then All-in — preflop opens, re-raises, post-flop raises.
    private static let multipleStrip: [String] =
        (20...50).map { String(format: "%.1fx", Double($0) / 10) } + ["All-in"]

    /// 5% … 95% (5% steps), Pot, then 1.1x … 5.0x (0.1x steps) ×pot, then All-in — post-flop bet.
    private static let betStrip: [String] =
        stride(from: 5, through: 95, by: 5).map { "\($0)%" }
        + ["Pot"]
        + (11...50).map { String(format: "%.1fx", Double($0) / 10) }
        + ["All-in"]

    // MARK: - Action Cycling (shared by both streets)

    /// Cycles the seat on the clock through its actions in place. A fresh turn appends the default
    /// (Call facing a bet, Check otherwise); thereafter it rotates Call→Raise→Fold→clear (bet
    /// context) or Check→Bet→clear (no-bet context). Only ever touches this seat's most recent log
    /// entry, so earlier aggression keeps its frozen bet level. Never advances the hand.
    private func cycleSeat(_ seat: Int) {
        highlightedSeat = seat
        let betContext = currentStreet == .preflop || seatFacesBet(seat)
        withAnimation(.easeInOut(duration: 0.15)) {
            if owesAction(seat) {
                // First action this turn — append the default and stop.
                recordAction(betContext ? .call : .check, for: seat)
            } else {
                // Live action already present — rotate it, editing only this seat's latest entry.
                let current = actionsThisStreet.last { $0.seatIndex == seat }?.actionType
                removeLastAction(of: seat)
                if let next = nextCycleAction(after: current, betContext: betContext) {
                    recordAction(next, for: seat)
                } else {
                    recomputeDerivedState()   // cleared — state falls out of the shorter log
                }
            }
        }
    }

    /// The next action in a seat's in-place cycle, or nil to clear it.
    private func nextCycleAction(after current: ActionType?, betContext: Bool) -> ActionType? {
        if betContext {
            switch current {
            case .call:         return .raise
            case .raise, .open: return .fold
            case .fold:         return .call   // wraps back to start — cycle loops forever
            default:            return .call
            }
        } else {
            switch current {
            case .check: return .open
            case .open:  return .check          // wraps back to start — cycle loops forever
            default:     return .check
            }
        }
    }

    // MARK: - Action Application

    /// The single low-level mutation: append one action to the current street's log, then rebuild
    /// every piece of derived state from it. All recording paths funnel through here, so the log
    /// stays the one source of truth. Does not move the highlight or close the street.
    private func recordAction(_ type: ActionType, for seat: Int, autoFolded: Bool = false, sizing: RaiseSizing? = nil) {
        actionsThisStreet.append(Action(
            seatIndex: seat,
            position: positionFor(seat: seat),
            actionType: type,
            sizing: sizing,
            isAutoFolded: autoFolded
        ))
        recomputeDerivedState()
    }

    /// An action-button press: record it for the seat on the clock, then settle. Identical tail to a
    /// swipe (`settleAfterCommit`) — the button just always targets the highlighted seat. Like the
    /// swipe path, it supersedes a standing live action (e.g. a cycled Call) rather than stacking a
    /// second action; a seat that owes a fresh response (never acted, or facing new aggression) keeps
    /// its earlier action as a genuine prior.
    private func commitAction(_ type: ActionType) {
        guard let seat = highlightedSeat else { return }
        // Wrapped in withAnimation to match the swipe path — gives the highlight transition a finite
        // animation transaction (smooth ring move; also belt-and-suspenders for the pulse cancel).
        withAnimation(.easeInOut(duration: 0.15)) {
            if hasActed(seat) && !owesAction(seat) { removeLastAction(of: seat) }
            recordAction(type, for: seat)
            settleAfterCommit(on: seat, justFolded: type == .fold)
        }
    }

    /// Shared post-record settle for COMMITTED inputs (action buttons + swipes). Ends the hand on a
    /// fold-out; otherwise either holds on the acting seat and lets the Next-Street button light
    /// (street closed), or advances the ring to the next actor WITHOUT seeding any action there.
    /// This is the single source of truth that keeps buttons and swipes behaviorally identical.
    private func settleAfterCommit(on seat: Int, justFolded: Bool) {
        if justFolded && activeSeatSequence.count == 1 { triggerFoldOut(); return }
        highlightedSeat = seat
        guard !streetIsClosed() else {
            // Decisive close: the round is complete via a committed input. Hand the pulse off to the
            // Next Street button — the acted seat drops its highlight. (Taps never reach here.)
            streetClosedDecisively = true
            return
        }
        if let next = nextActiveSeat(after: seat) {
            highlightedSeat = next                 // advance the ring only — no recordAction (no seed)
        }
    }

    /// Next active seat clockwise from `seat` — the next player to act in linear order. Single source
    /// of truth for ring advancement (used by both committed-input settling). Anchored on the FULL
    /// table ring so it is correct even when `seat` has just folded out of `activeSeatSequence` (a
    /// just-folded seat is no longer in the active subset, so we cannot rotate from it there).
    private func nextActiveSeat(after seat: Int) -> Int? {
        let ring = clockwiseOrder(from: seat, seats: Array(0..<tableSize))
        return ring.dropFirst().first { activeSeatSequence.contains($0) }
    }

    private func triggerFoldOut() {
        if let winner = activeSeatSequence.first {
            handCloseSummary = (winner == heroSeat) ? "You win" : "Seat \(winner + 1) wins"
        }
        saveCurrentHand(outcome: nil)
        phase = .handClosed
        highlightedSeat = nil
    }

    private func resolveShowdown(outcome: Outcome) {
        switch outcome {
        case .win:  handCloseSummary = "You win"
        case .lose: handCloseSummary = "You lose"
        case .chop: handCloseSummary = "Chop"
        }
        saveCurrentHand(outcome: outcome)
        phase = .handClosed
        highlightedSeat = nil
    }

    /// Seat visuals, derived purely from the append-only log plus the current cue. Computed (not
    /// stored) so it always reflects the latest `highlightedSeat` — the moment a committed input
    /// advances the cue, the seat it lands on re-derives, with no resync plumbing.
    private var seatActions: [Int: SeatState] {
        var result: [Int: SeatState] = [:]

        // Ghost seats for folds that happened on prior streets
        let foldedThisStreet = Set(actionsThisStreet.filter { $0.actionType == .fold }.map { $0.seatIndex })
        for seat in foldedSeats where !foldedThisStreet.contains(seat) {
            result[seat] = SeatState(action: .foldedOut)
        }

        // Build each seat's action history this street in log order, capturing the bet level frozen
        // at each entry so prior aggression keeps its pip layout.
        var histories: [Int: [(action: SeatState.Action, betLevel: Int)]] = [:]
        for action in actionsThisStreet {
            let seatAction: SeatState.Action
            switch action.actionType {
            case .fold:  seatAction = .fold
            case .call:  seatAction = .call
            case .check: seatAction = .check
            case .open:  seatAction = .open
            case .raise: seatAction = .raise
            }
            let levelAtThisPoint = actionsThisStreet
                .prefix(while: { $0.id != action.id })
                .filter { $0.actionType == .open || $0.actionType == .raise }
                .count + (action.actionType == .open || action.actionType == .raise ? 1 : 0)
            histories[action.seatIndex, default: []].append((seatAction, levelAtThisPoint))
        }

        // The most recent entry is the seat's current state; everything before it is shown as
        // prior-action badges (oldest first).
        for (seat, history) in histories {
            // The seat on the clock that owes a FRESH response — it acted earlier this street but a
            // bet/raise was logged after (e.g. an opener facing a 3-bet, or a checker facing a bet) —
            // has not made its current decision yet. Demote its whole history to prior pills and leave
            // the center empty, so it reads like any other on-the-clock seat. Only the on-clock seat
            // does this; other owing seats keep their last action shown until the cue reaches them.
            if seat == highlightedSeat, owesAction(seat) {
                result[seat] = SeatState(action: nil, priorActions: history.map { $0.action })
                continue
            }
            let current = history.last!
            let prior = history.dropLast().map { $0.action }
            let sizeLabel = actionsThisStreet.last { $0.seatIndex == seat }?.sizing?.label
            result[seat] = SeatState(
                action: current.action,
                betLevel: current.betLevel,
                priorActions: Array(prior),
                sizeLabel: sizeLabel
            )
        }
        return result
    }

    // MARK: - Undo

    /// Undoes the most recent action, peeling back across street boundaries when the current
    /// street has no actions yet. The highlight lands on the new most-recent actor so it can be
    /// re-cycled, or on the street's opener (first to act) when nothing remains — so undoing a
    /// jump returns to "first to act", not the seat that was tapped. Card slots are left
    /// untouched — rewind only affects recorded action.
    private func undoLastAction() {
        // A finished hand is reversible. Un-close it first, discriminating by the saved hand's
        // outcome (showdown saves a non-nil outcome; a fold-out saves nil).
        if phase == .handClosed {
            let popped = savedHands.popLast()
            handCloseSummary = ""
            if popped?.outcome != nil {
                phase = .showdown        // re-open the Win/Lose/Chop overlay to re-pick — no peel
                highlightedSeat = nil
                return
            }
            phase = .recordingHand       // fold-out → re-open recording, then peel the fold below
        } else if phase == .showdown {
            phase = .recordingHand       // unresolved showdown → back to the river, peel below
        }

        // A decisive close moved the cue to the Next Street button without adding a log entry. The
        // first Rewind reverses THAT step — return the pulse to the last actor (already the held
        // seat) without deleting; a further press then undoes that actor's action. Same principle as
        // the ahead-ring re-home below, for the other representation of "cue ahead of the log".
        if streetClosedDecisively {
            streetClosedDecisively = false
            return
        }

        // Nothing on this street yet — step back into the previous street and land the highlight on
        // its last actor (kept, re-armed for cycling). The action itself stays; a further press
        // then undoes within that street. This is what makes Rewind cross a boundary cleanly:
        // empty flop + BB highlighted → reopen preflop with BB (its last actor) still highlighted.
        if actionsThisStreet.isEmpty {
            if let prev = streets.popLast() {
                currentStreet = prev.name
                actionsThisStreet = prev.actions
                recomputeDerivedState()
                highlightedSeat = actionsThisStreet.last?.seatIndex ?? firstActor(of: currentStreet)
                return
            }
            // Nothing recorded this hand and no earlier street to reopen — the only thing left to
            // undo is the button placement. Pick the button back up and return to placingButton so
            // the user can re-drop it on another seat. Hand number is unchanged (same hand).
            buttonSeat = nil
            activeSeatSequence = []
            highlightedSeat = nil
            streetClosedDecisively = false
            phase = .placingButton
            return
        }

        // Re-home an "ahead" ring first. After an advance-no-seed (action button or swipe) the cue
        // sits one step ahead of the log's last entry, on a seat that owes a fresh action but hasn't
        // recorded it yet. The first Rewind returns the ring to the last actor (showing their action)
        // WITHOUT deleting — visually identical to undoing a tap, whose landing seat carried an
        // action. A further press then undoes that action. Recording is two kinds of step (a bare
        // advance, and an action); Rewind peels the advance before the action.
        //
        // The test is `owesAction(hs)`, NOT `!hasActed(hs)`: the cue is also "ahead of the log" when
        // it advanced onto a seat that acted earlier this street but now owes a response to new
        // aggression (e.g. an opener facing a 3-bet, or a checker facing a bet). `!hasActed` missed
        // that case and deleted the last action instead of re-homing. `owesAction` is the same
        // predicate the tap/swipe routing uses for "on the clock, awaiting a fresh action".
        if let hs = highlightedSeat, owesAction(hs),
           let lastActor = actionsThisStreet.last?.seatIndex, lastActor != hs {
            highlightedSeat = lastActor
            return
        }

        // Remove the most recent action, then strip any trailing system-generated auto-action batch
        // (preflop auto-folds via preflopJump, post-flop auto-checks via postflopJump). They're not
        // player decisions, so one Rewind press removes the whole jump.
        actionsThisStreet.removeLast()
        while actionsThisStreet.last?.isAutoFolded == true {
            actionsThisStreet.removeLast()
        }

        recomputeDerivedState()
        // Land on the new most-recent actor, or — when the street is now empty (a jump was undone) —
        // on the street's opener, so a jump rewinds back to "first to act" rather than the seat tapped.
        highlightedSeat = actionsThisStreet.last?.seatIndex ?? firstActor(of: currentStreet)
    }

    /// Rebuilds derived state (folds, active seats, bet level, seat visuals) from the append-only
    /// logs after a structural edit. Folds are gathered from ALL streets plus the current one so a
    /// fold recorded on an earlier street stays in effect.
    private func recomputeDerivedState() {
        // Any structural edit returns the ring to a live decision; only settleAfterCommit's decisive
        // close re-sets this (it runs after the recordAction that lands here).
        streetClosedDecisively = false
        let allActions = streets.flatMap { $0.actions } + actionsThisStreet
        foldedSeats = Set(allActions.filter { $0.actionType == .fold }.map { $0.seatIndex })
        activeSeatSequence = Array(0..<tableSize).filter { !foldedSeats.contains($0) }.sorted()
        betLevelThisStreet = actionsThisStreet.filter {
            $0.actionType == .open || $0.actionType == .raise
        }.count
    }

    // MARK: - Street Close Detection

    /// Pure predicate — has the current betting round completed? Does NOT mutate state.
    /// Preflop: BB is the last voluntary actor. In an unraised (limped) pot the street
    /// closes once BB has acted; in a raised pot every active seat except the last
    /// aggressor must have called or folded after that aggressor's raise (BB included,
    /// since BB is active and acts last).
    private func streetIsClosed() -> Bool {
        let activePlayers = activeSeatSequence

        // One player left is a fold-out, handled separately — not a street close.
        if activePlayers.count <= 1 { return false }

        let aggressorIndices = actionsThisStreet.indices.filter {
            actionsThisStreet[$0].actionType == .open || actionsThisStreet[$0].actionType == .raise
        }

        if aggressorIndices.isEmpty {
            // No aggression this street.
            if currentStreet == .preflop {
                // Limped pot: closes once BB (last to act) has acted.
                guard let bb = bbSeat() else { return false }
                return actionsThisStreet.contains { $0.seatIndex == bb }
            } else {
                // Post-flop check-around: every active player must have acted.
                let actedSeats = Set(actionsThisStreet.map { $0.seatIndex })
                return activePlayers.allSatisfy { actedSeats.contains($0) }
            }
        } else {
            // Bet/raise present: every active seat except the last aggressor must have
            // called or folded after the last aggressive action.
            let lastIdx = aggressorIndices.last!
            let lastAggressor = actionsThisStreet[lastIdx]
            let respondedAfter = Set(
                actionsThisStreet[(lastIdx + 1)...]
                    .filter { $0.actionType == .call || $0.actionType == .fold }
                    .map { $0.seatIndex }
            )
            return activePlayers
                .filter { $0 != lastAggressor.seatIndex }
                .allSatisfy { respondedAfter.contains($0) }
        }
    }

    /// Close the current street (or open the showdown on a completed river).
    private func advanceStreetOrShowdown() {
        if currentStreet == .river {
            if activeSeatSequence.count >= 2 {
                phase = .showdown
            }
        } else {
            closeStreet()
        }
    }

    // Returns the BB's seat index based on the full table layout (position-stable across folds).
    private func bbSeat() -> Int? {
        guard let btn = buttonSeat else { return nil }
        let positions = calculatePositions(
            buttonSeatIndex: btn,
            activeSeatIndices: Array(0..<tableSize)
        )
        return positions.first(where: { $0.value == "BB" })?.key
    }

    // MARK: - Street Management

    /// First active seat clockwise from the button — the opener of the next post-flop street.
    private func firstActorAfterClose() -> Int? {
        let btn = buttonSeat ?? 0
        let all = Array(0..<tableSize)
        let btnIdx = all.firstIndex(of: btn) ?? 0
        let rotated = Array(all[(btnIdx + 1)...]) + Array(all[...btnIdx])
        return rotated.first { activeSeatSequence.contains($0) }
    }

    /// The opener of a street: UTG (or BB short-handed) preflop, else the first active seat left of
    /// the button. Single source of truth for "who is first to act" — used at button placement and
    /// as the highlight fallback when Rewind empties a street.
    private func firstActor(of street: StreetName) -> Int? {
        guard street == .preflop else { return firstActorAfterClose() }
        guard let btn = buttonSeat else { return nil }
        let positions = calculatePositions(buttonSeatIndex: btn, activeSeatIndices: activeSeatSequence)
        return positions.first { $0.value == "UTG" }?.key
            ?? positions.first { $0.value == "BB" }?.key
    }

    private func closeStreet() {
        streets.append(Street(name: currentStreet, boardCards: [], actions: actionsThisStreet))
        actionsThisStreet = []
        if let next = currentStreet.next() {
            currentStreet = next
            highlightedSeat = firstActorAfterClose()
        }
        recomputeDerivedState()
    }

    // MARK: - Clockwise Ordering & Auto-Fold

    private func clockwiseOrder(from startSeat: Int, seats: [Int]) -> [Int] {
        let sorted = seats.sorted()
        guard let offset = sorted.firstIndex(of: startSeat) else { return sorted }
        return Array(sorted[offset...]) + Array(sorted[..<offset])
    }

    /// Seats from `seats` that lie strictly clockwise-between `from` and `to`.
    /// Anchored on the FULL table ring so it is safe even when `from` has already
    /// folded out of `seats` (clockwise position is defined by the table, not the
    /// active subset). Avoids the `1..<0` range crash when `from` is not in `seats`.
    private func seatsStrictlyBetween(from: Int, to: Int, in seats: [Int]) -> [Int] {
        guard from != to else { return [] }
        let ring = clockwiseOrder(from: from, seats: Array(0..<tableSize))
        guard let toIdx = ring.firstIndex(of: to), toIdx >= 1 else { return [] }
        return ring[1..<toIdx].filter { seats.contains($0) }
    }

    /// Folds the given seats in one batch and triggers a fold-out if only one active player
    /// remains. Returns true if the hand ended via fold-out so callers skip further street logic.
    @discardableResult
    private func autoFoldSeats(_ seats: [Int], autoFolded: Bool = false) -> Bool {
        for seat in seats where !foldedSeats.contains(seat) {
            actionsThisStreet.append(Action(
                seatIndex: seat,
                position: positionFor(seat: seat),
                actionType: .fold,
                sizing: nil,
                isAutoFolded: autoFolded
            ))
        }
        recomputeDerivedState()
        if activeSeatSequence.count == 1 {
            triggerFoldOut()
            return true
        }
        return false
    }

    // MARK: - Helpers

    /// True when the seat has at least one action on the current street.
    private func hasActed(_ seat: Int) -> Bool {
        actionsThisStreet.contains { $0.seatIndex == seat }
    }

    /// True when the seat must make a NEW action rather than edit a live one: it is active and
    /// either has not acted on this street, or a bet/raise was recorded after its most recent
    /// action (it faces aggression and owes a response — e.g. an opener facing a 3-bet). Derived
    /// purely from the append-only log, the single source of truth.
    private func owesAction(_ seat: Int) -> Bool {
        guard activeSeatSequence.contains(seat) else { return false }
        guard let lastIdx = actionsThisStreet.lastIndex(where: { $0.seatIndex == seat }) else {
            return true   // active and yet to act this street
        }
        return actionsThisStreet[(lastIdx + 1)...].contains {
            $0.actionType == .open || $0.actionType == .raise
        }
    }

    /// Removes a seat's most recent action from the current street's log, preserving any earlier
    /// actions it took (e.g. an open-raise is kept when editing a later response). Used by the
    /// in-place edit/clear path so append-only history — and frozen bet levels — stay intact.
    private func removeLastAction(of seat: Int) {
        if let idx = actionsThisStreet.lastIndex(where: { $0.seatIndex == seat }) {
            actionsThisStreet.remove(at: idx)
        }
    }

    /// True when `seat` is responding to a wager made by ANOTHER seat on this street, so its cycle
    /// is call → raise → fold. False when no one else has bet — `seat` is the opener and cycles
    /// check → bet. Ignores `seat`'s own bet on purpose: opening the betting must never flip the
    /// seat into facing-a-bet, which would fold it on the following cycle step.
    private func seatFacesBet(_ seat: Int) -> Bool {
        actionsThisStreet.contains {
            ($0.actionType == .open || $0.actionType == .raise) && $0.seatIndex != seat
        }
    }

    private func positionFor(seat: Int) -> String {
        guard let btn = buttonSeat else { return "?" }
        return calculatePositions(
            buttonSeatIndex: btn,
            activeSeatIndices: activeSeatSequence
        )[seat] ?? "?"
    }

    private func suitKey(_ symbol: String) -> String {
        switch symbol {
        case "♠": return "s"
        case "♥": return "h"
        case "♦": return "d"
        case "♣": return "c"
        default:  return ""
        }
    }

    private func buildHeroCards() -> [Card] {
        heroCards.compactMap { slot in
            guard let rankStr = slot.rank, let rank = Rank(rawValue: rankStr) else { return nil }
            let suit = slot.suit.flatMap { Suit(rawValue: suitKey($0)) }
            return Card(rank: rank, suit: suit)
        }
    }

    // MARK: - Card Strip

    private var cardStrip: some View {
        HStack(alignment: .top, spacing: 0) {
            streetSection(label: "HOLE", isActive: entryStreet == .hole || currentStreet == .preflop) {
                HStack(spacing: 4) {
                    ForEach(0..<2, id: \.self) { i in
                        CardSlotView(slot: heroCards[i], isActive: entryStreet == .hole && focusIndex == i)
                            .onTapGesture { openCardEntry(.hole, focus: i) }
                    }
                }
            }

            Spacer()

            streetSection(label: "FLOP", isActive: entryStreet == .flop || currentStreet == .flop) {
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { i in
                        CardSlotView(slot: flopCards[i], isActive: entryStreet == .flop && focusIndex == i)
                            .onTapGesture { openCardEntry(.flop, focus: i) }
                    }
                }
            }

            Spacer()

            streetSection(label: "TURN", isActive: entryStreet == .turn || currentStreet == .turn) {
                CardSlotView(slot: turnCard, isActive: entryStreet == .turn)
                    .onTapGesture { openCardEntry(.turn) }
            }

            Spacer()

            streetSection(label: "RIVER", isActive: entryStreet == .river || currentStreet == .river) {
                CardSlotView(slot: riverCard, isActive: entryStreet == .river)
                    .onTapGesture { openCardEntry(.river) }
            }
        }
        .padding(.horizontal, 12)
        .animation(.easeInOut(duration: 0.25), value: currentStreet)
    }

    @ViewBuilder
    private func streetSection<Content: View>(
        label: String,
        isActive: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(isActive ? Color.gold : Color.textMuted)

            content()
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isActive ? Color.gold.opacity(0.45) : Color.clear, lineWidth: 1.5)
                )
        }
    }

    private var cardSlotWidth: CGFloat { 44 }

    // MARK: - Card Picker Panel

    // Docked below the strip (not a covering sheet). The strip slots are the frames — they stay
    // visible and highlight the focused one — so the picker shows only the controls, no duplicate cards.
    private var cardPickerPanel: some View {
        VStack(spacing: 0) {
            if let street = entryStreet {
                let notation = groupNotation(street)

                // Header: Clear · live shorthand notation · Done
                HStack {
                    Button("Clear") { clearEntryGroup() }
                        .font(.custom("Arial", size: 13))
                        .foregroundStyle(Color.foldRed)
                    Spacer()
                    Text(notation.isEmpty ? "· · ·" : notation)
                        .font(.custom("Courier New", size: 16))
                        .fontWeight(.bold)
                        .tracking(2)
                        .foregroundStyle(notation.isEmpty ? Color.textMuted : Color.goldLight)
                    Spacer()
                    Button("Done") { closeEntry() }
                        .font(.custom("Arial", size: 13))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.gold)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 12)

                // Rank grid — 7, then a centered 6 that nests into the gaps above.
                VStack(spacing: 6) {
                    rankRow(["A","K","Q","J","T","9","8"])
                    rankRow(["7","6","5","4","3","2"])
                }
                .padding(.bottom, 12)

                // Suit row — five separate taps; "?" leaves the suit unknown.
                HStack(spacing: 7) {
                    suitButton("♠"); suitButton("♥"); suitButton("♦"); suitButton("♣")
                    unknownSuitButton()
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

                // Shortcut row — suited/offsuit (hole) or rainbow/mono (flop); none for turn/river.
                shortcutRow(for: street)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.borderDark.opacity(0.6)).frame(height: 1)
        }
    }

    // MARK: - Shorthand Transcript Panel

    /// Fills the gap below the strip (when the picker is closed): the live shorthand, Courier, with a
    /// Copy button and auto-scroll to the newest line.
    private var transcriptPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("HAND")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(Color.gold)
                Spacer()
                Button(action: copyShorthand) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc").font(.system(size: 11))
                        Text("Copy").font(.custom("Arial", size: 12))
                    }
                    .foregroundStyle(Color.textBody)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .overlay(Capsule().stroke(Color.borderDark, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Text(handShorthand)
                        .font(.custom("Courier New", size: 13))
                        .foregroundStyle(Color.textBody)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    Color.clear.frame(height: 1).id("transcriptEnd")
                }
                .frame(height: 112)
                .onChange(of: handShorthand) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("transcriptEnd", anchor: .bottom)
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "#121212")))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#2A2A2A"), lineWidth: 1))
        .padding(.horizontal, 12)
    }

    private func copyShorthand() {
        UIPasteboard.general.string = handShorthand
    }

    @ViewBuilder
    private func rankRow(_ ranks: [String]) -> some View {
        HStack(spacing: 6) {
            ForEach(ranks, id: \.self) { r in
                Button(action: { rankTapped(r) }) {
                    Text(r)
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 40, height: 40)
                        .background(Color.surface2)
                        .foregroundStyle(Color.textBody)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderDark, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func suitButton(_ suit: String) -> some View {
        Button(action: { suitTapped(suit) }) {
            Text(suit)
                .font(.system(size: 22))
                .foregroundStyle(["♥", "♦"].contains(suit) ? Color(hex: "#E74C3C") : Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.borderDark, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func unknownSuitButton() -> some View {
        Button(action: { suitTapped(nil) }) {
            Text("?")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.textMuted)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.borderDark, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func shortcutRow(for street: CardStreet) -> some View {
        switch street {
        case .hole:
            HStack(spacing: 7) {
                shortcutButton("Suited")  { relationshipTapped("s") }
                shortcutButton("Offsuit") { relationshipTapped("o") }
            }
        case .flop:
            HStack(spacing: 7) {
                shortcutButton("Rainbow") { textureTapped("r") }
                shortcutButton("Mono")    { textureTapped("m") }
            }
        case .turn, .river:
            EmptyView()
        }
    }

    private func shortcutButton(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.custom("Arial", size: 13))
                .fontWeight(.semibold)
                .foregroundStyle(Color.goldLight)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Color.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gold.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Card Entry (per-street group)

    /// A street's group of card frames: hole = 2, flop = 3, turn/river = 1.
    enum CardStreet: Equatable {
        case hole, flop, turn, river
        var count: Int {
            switch self {
            case .hole: return 2
            case .flop: return 3
            case .turn, .river: return 1
            }
        }
    }

    /// The live card slots for a group (turn/river wrap their single slot in an array).
    private func groupCards(_ street: CardStreet) -> [CardSlot] {
        switch street {
        case .hole:  return heroCards
        case .flop:  return flopCards
        case .turn:  return [turnCard]
        case .river: return [riverCard]
        }
    }

    private func setGroupCard(_ street: CardStreet, _ i: Int, _ card: CardSlot) {
        switch street {
        case .hole:  heroCards[i] = card
        case .flop:  flopCards[i] = card
        case .turn:  turnCard = card
        case .river: riverCard = card
        }
    }

    private func openCardEntry(_ street: CardStreet, focus: Int? = nil) {
        entryStreet = street
        focusIndex = focus ?? (groupCards(street).firstIndex(where: { $0.isEmpty }) ?? 0)
    }

    private func closeEntry() {
        entryStreet = nil
    }

    private func clearEntryGroup() {
        guard let street = entryStreet else { return }
        for i in 0..<street.count { setGroupCard(street, i, CardSlot()) }
        focusIndex = 0
    }

    /// Tap a rank → fill the focused frame, then advance focus to the next frame still missing a rank
    /// (or back to the first frame once the group is full, ready for suiting).
    private func rankTapped(_ r: String) {
        guard let street = entryStreet else { return }
        var card = groupCards(street)[focusIndex]
        card.rank = r
        card.qualifier = nil
        setGroupCard(street, focusIndex, card)
        focusIndex = groupCards(street).firstIndex(where: { $0.isEmpty }) ?? 0
    }

    /// Tap a suit (or "?" → nil) → set the focused frame's suit, then advance to the next frame.
    private func suitTapped(_ suit: String?) {
        guard let street = entryStreet else { return }
        guard groupCards(street)[focusIndex].rank != nil else { return }   // nothing to suit yet
        var card = groupCards(street)[focusIndex]
        card.suit = suit
        card.qualifier = nil
        setGroupCard(street, focusIndex, card)
        focusIndex = (focusIndex + 1) % street.count
    }

    /// Hole-only: suited / offsuit relationship — applies to both cards, clearing any explicit suits.
    private func relationshipTapped(_ q: String) {
        guard entryStreet == .hole else { return }
        for i in 0..<2 where heroCards[i].rank != nil {
            heroCards[i].suit = nil
            heroCards[i].qualifier = q
        }
    }

    /// Flop-only: rainbow ("r") / monotone ("m") texture — a group flag, no specific suits assigned.
    private func textureTapped(_ t: String) {
        guard entryStreet == .flop else { return }
        for i in 0..<3 where flopCards[i].rank != nil {
            flopCards[i].suit = nil
            flopCards[i].qualifier = t
        }
    }

    // MARK: - Card Notation (group readout — see ShorthandReference.md §2)

    private func suitLetter(_ s: String) -> String {
        switch s {
        case "♠": return "s"; case "♥": return "h"; case "♦": return "d"; case "♣": return "c"
        default:  return ""
        }
    }

    /// One card's token: rank + suit-letter, or rank + "x" when the suit is unknown but worth marking.
    private func cardToken(_ c: CardSlot, markUnknown: Bool) -> String {
        guard let r = c.rank else { return "" }
        if let s = c.suit { return r + suitLetter(s) }
        return markUnknown ? r + "x" : r
    }

    /// The group's shorthand for the picker readout: AJs / AsJx / Q53r / Qh5h3x / Jh / 5x.
    private func groupNotation(_ street: CardStreet) -> String {
        let cards = groupCards(street)
        switch street {
        case .hole:
            if cards.count == 2, let r0 = cards[0].rank, let r1 = cards[1].rank,
               let q = cards[0].qualifier, q == cards[1].qualifier {
                return r0 + r1 + q                                  // AJs / AJo
            }
            let anySuit = cards.contains { $0.suit != nil }
            return cards.map { cardToken($0, markUnknown: anySuit) }.joined()
        case .flop:
            if cards.allSatisfy({ $0.rank != nil }),
               let t = cards[0].qualifier, cards.allSatisfy({ $0.qualifier == t }) {
                return cards.compactMap { $0.rank }.joined() + t    // Q53r / Q53m
            }
            let anySuit = cards.contains { $0.suit != nil }
            return cards.map { cardToken($0, markUnknown: anySuit) }.joined()
        case .turn, .river:
            return cards.map { cardToken($0, markUnknown: false) }.joined()
        }
    }

    // MARK: - Hand Shorthand (see ShorthandReference.md)

    /// The running shorthand transcript — a pure render of the action log + board + hero cards.
    /// Computed (like `seatActions`) so it tracks Rewind/edits automatically.
    private var handShorthand: String {
        let hero = heroSeat ?? -1
        let order: [StreetName] = [.preflop, .flop, .turn, .river]
        let currentIdx = order.firstIndex(of: currentStreet) ?? 0

        var lines: [String] = []
        var heroDeclared = false

        for street in order.prefix(currentIdx + 1) {
            let acts = actions(on: street)
            let board = boardToken(for: street)
            if acts.isEmpty && board.isEmpty { continue }

            var segments: [String] = []
            if !board.isEmpty { segments.append(board) }   // bare board leads post-flop lines

            let isPreflop = (street == .preflop)
            if !acts.isEmpty && acts.allSatisfy({ $0.actionType == .check }) {
                // Pure check-around → bare checks, no names.
                segments.append(acts.map { _ in "chk" }.joined(separator: " "))
            } else {
                var aggCount = 0
                var sawAgg = false
                for a in acts {
                    let isAgg = (a.actionType == .open || a.actionType == .raise)
                    if isAgg { aggCount += 1 }
                    let token = actionToken(a, isPreflop: isPreflop, aggIndex: aggCount, priorAggression: sawAgg)
                    if isAgg { sawAgg = true }
                    segments.append(actorSegment(a, token: token, hero: hero, heroDeclared: &heroDeclared))
                }
            }

            if !segments.isEmpty { lines.append(segments.joined(separator: ". ") + ".") }
        }

        // Showdown gets a result line (the outcome isn't derivable from the action); a fold-out implies
        // the winner with no tag. savedHands.last carries this hand's outcome at close (nil = fold-out).
        if phase == .handClosed, let outcome = savedHands.last?.outcome {
            switch outcome {
            case .win:  lines.append("Hero wins.")
            case .lose: lines.append("Hero loses.")
            case .chop: lines.append("Chop.")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Recorded actions on a street: completed streets live in `streets`, the live one in `actionsThisStreet`.
    private func actions(on street: StreetName) -> [Action] {
        if let s = streets.first(where: { $0.name == street }) { return s.actions }
        if street == currentStreet { return actionsThisStreet }
        return []
    }

    /// The bare board token leading a post-flop line (empty preflop). Reuses the card-notation formatter.
    private func boardToken(for street: StreetName) -> String {
        switch street {
        case .preflop: return ""
        case .flop:    return groupNotation(.flop)
        case .turn:    return groupNotation(.turn)
        case .river:   return groupNotation(.river)
        }
    }

    /// The verb-or-size token for one action. Elision: a sized wager shows just the size (All-in → jam).
    private func actionToken(_ a: Action, isPreflop: Bool, aggIndex: Int, priorAggression: Bool) -> String {
        switch a.actionType {
        case .fold:  return "fold"
        case .check: return "chk"
        case .call:  return (isPreflop && !priorAggression) ? "limp" : "call"
        case .open:
            if let label = a.sizing?.label { return label == "All-in" ? "jam" : label }
            return isPreflop ? "raise" : "bet"
        case .raise:
            if let label = a.sizing?.label { return label == "All-in" ? "jam" : label }
            return isPreflop ? "\(aggIndex + 1)-bet" : "raise"   // 1st reraise (aggIndex 2) → 3-bet
        }
    }

    /// "<actor> <token>", declaring Hero once (with position + hole cards) at Hero's first action.
    private func actorSegment(_ a: Action, token: String, hero: Int, heroDeclared: inout Bool) -> String {
        guard a.seatIndex == hero else { return "\(a.position) \(token)" }
        if heroDeclared { return "Hero \(token)" }
        heroDeclared = true
        let cards = groupNotation(.hole)
        let base = "Hero - \(a.position) \(token)"
        return cards.isEmpty ? base : "\(base) \(cards)"
    }

    // MARK: - Hand Lifecycle

    /// Clears all per-hand state (actions, streets, cards) while preserving the session-locked hero
    /// seat and table size. Does NOT set `phase` — the caller decides the next phase.
    private func resetHandState() {
        buttonSeat = nil
        heroCards  = [CardSlot(), CardSlot()]
        flopCards  = [CardSlot(), CardSlot(), CardSlot()]
        turnCard   = CardSlot()
        riverCard  = CardSlot()
        entryStreet = nil
        focusIndex  = 0
        currentStreet = .preflop
        streets = []
        actionsThisStreet = []
        betLevelThisStreet = 0
        activeSeatSequence = []
        foldedSeats = []
        highlightedSeat = nil
        handCloseSummary = ""
        streetClosedDecisively = false
    }

    private func saveCurrentHand(outcome: Outcome?) {
        var streetsToSave = streets
        if !actionsThisStreet.isEmpty {
            streetsToSave.append(Street(name: currentStreet, boardCards: [], actions: actionsThisStreet))
        }
        let hand = Hand(
            sessionId: session.id,
            handNumber: handNumber,
            title: nil,
            heroSeatIndex: heroSeat ?? 0,
            buttonSeatIndex: buttonSeat ?? 0,
            activeSeatIndices: activeSeatSequence,
            holeCards: buildHeroCards(),
            streets: streetsToSave,
            outcome: outcome,
            potSize: nil,
            potUnit: session.potUnit,
            effectiveStack: nil,
            commentary: nil
        )
        savedHands.append(hand)
    }

    /// Deals the next hand from the hand-closed state: place the dealer button on the tapped seat,
    /// reset per-hand state, highlight the first actor, and start recording. The hand that just
    /// finished was already saved at close, so nothing is persisted here.
    private func dealNextHand(buttonAt seat: Int) {
        handNumber += 1
        resetHandState()
        buttonSeat = seat
        activeSeatSequence = Array(0..<tableSize)
        highlightedSeat = firstActor(of: .preflop)
        phase = .recordingHand
    }
}

// MARK: - Control Bar (single bottom row: Rewind · actions · Next Street)

/// The one home for all recording controls. Morphs by phase:
/// - recording:  [ Rewind ]  [ Fold/Call/Raise · Check/Bet ]  [ Flop › ]
/// - showdown / hand-closed:  [ Rewind ]  (the table overlay / "tap a seat to deal" drives the rest)
private struct ControlBar: View {
    let isRecording: Bool
    let currentStreet: StreetName
    let openBetExists: Bool
    let highlightedSeat: Int?
    let rewindEnabled: Bool
    let nextStreetEnabled: Bool
    let nextStreetPulsing: Bool
    let nextStreetLabel: String
    let onAction: (ActionType) -> Void
    let onRewind: () -> Void
    let onNextStreet: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.borderDark)
                .frame(height: 1)

            VStack(spacing: 10) {
                // Utility row — Undo (left) · Next Street (right). Stays visible when the hand is
                // closed (Undo only); Next Street and the action row are recording-only.
                HStack(spacing: 0) {
                    undoButton
                    Spacer()
                    if isRecording { nextStreetButton }
                }
                // Primary row — full-width action buttons, the most-used controls in the thumb zone.
                if isRecording {
                    actionButtons
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .background(Color.surface)
    }

    // MARK: Undo (utility row, left)

    private var undoButton: some View {
        Button(action: onRewind) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .bold))
                Text("Undo")
                    .font(.custom("Arial", size: 11))
                    .fontWeight(.bold)
                    .tracking(0.5)
            }
            .foregroundStyle(rewindEnabled ? Color.gold : Color.textMuted.opacity(0.5))
            .padding(.horizontal, 11)
            .padding(.vertical, 11)
            .background(Capsule().fill(Color.surface2))
            .overlay(
                Capsule().stroke(
                    rewindEnabled ? Color.gold.opacity(0.5) : Color.borderDark.opacity(0.5),
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
        .disabled(!rewindEnabled)
        .opacity(rewindEnabled ? 1.0 : 0.55)
    }

    // MARK: Next Street / End Hand (right)

    private var nextStreetButton: some View {
        // Pulses only on a decisive street close — the cue hands off here from the seat ring.
        Pulse(isActive: nextStreetPulsing) { phase in
            nextStreetButtonBody.scaleEffect(1.0 + 0.05 * phase)
        }
    }

    private var nextStreetButtonBody: some View {
        Button(action: onNextStreet) {
            HStack(spacing: 3) {
                Text(nextStreetLabel)
                    .font(.custom("Arial", size: 11))
                    .fontWeight(.bold)
                    .tracking(0.5)
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(nextStreetEnabled ? Color(hex: "#0D0D0D") : Color.textMuted.opacity(0.5))
            .padding(.horizontal, 11)
            .padding(.vertical, 11)
            .background {
                if nextStreetEnabled {
                    Capsule().fill(
                        LinearGradient(
                            colors: [Color.gold, Color(hex: "#9A6820")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                } else {
                    Capsule().fill(Color.surface2)
                }
            }
            .overlay(
                Capsule().stroke(
                    nextStreetEnabled ? Color.goldLight.opacity(0.6) : Color.borderDark.opacity(0.5),
                    lineWidth: 1
                )
            )
            .shadow(color: nextStreetPulsing ? Color.gold.opacity(0.55) : (nextStreetEnabled ? Color.gold.opacity(0.4) : .clear),
                    radius: nextStreetPulsing ? 12 : 6)
        }
        .buttonStyle(.plain)
        .disabled(!nextStreetEnabled)
        .opacity(nextStreetEnabled ? 1.0 : 0.55)
    }

    // MARK: Context-aware action buttons (middle)

    @ViewBuilder
    private var actionButtons: some View {
        let isBetContext = currentStreet == .preflop || openBetExists
        if isBetContext {
            HStack(spacing: 10) {
                actionChip("Fold",  type: .fold,  style: .destructive)
                actionChip("Call",  type: .call,  style: .neutral)
                actionChip("Raise", type: .raise, style: .aggressive)
            }
        } else {
            HStack(spacing: 10) {
                actionChip("Check", type: .check, style: .neutral)
                actionChip("Bet",   type: .open,  style: .aggressive)
            }
        }
    }

    // Each chip fills its share of the row so Fold/Call/Raise span the full width.

    private enum ChipStyle { case neutral, aggressive, destructive }

    @ViewBuilder
    private func actionChip(_ label: String, type: ActionType, style: ChipStyle) -> some View {
        let isDisabled = highlightedSeat == nil
        Button(action: { onAction(type) }) {
            Text(label)
                .font(.custom("Arial", size: 14))
                .fontWeight(.bold)
                .foregroundStyle(chipForeground(style))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(chipBackground(style))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(chipBorder(style), lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .opacity(isDisabled ? 0.35 : 1.0)
        .disabled(isDisabled)
    }

    private func chipForeground(_ style: ChipStyle) -> Color {
        switch style {
        case .neutral:     return Color.textBody
        case .aggressive:  return Color.gold
        case .destructive: return Color.foldRed
        }
    }

    private func chipBackground(_ style: ChipStyle) -> Color {
        switch style {
        case .neutral:     return Color.surface2
        case .aggressive:  return Color(hex: "#1A1508")
        case .destructive: return Color(hex: "#1A0808")
        }
    }

    private func chipBorder(_ style: ChipStyle) -> Color {
        switch style {
        case .neutral:     return Color.borderDark
        case .aggressive:  return Color.gold.opacity(0.5)
        case .destructive: return Color.foldRed.opacity(0.4)
        }
    }
}

// MARK: - Card Slot Model

struct CardSlot: Equatable {
    var rank:      String? = nil
    var suit:      String? = nil   // "♠" "♥" "♦" "♣" or nil
    var qualifier: String? = nil   // "s" or "o" (hole cards only)

    var notation: String {
        guard let r = rank else { return "" }
        if let q = qualifier { return r + q }
        if let s = suit { return r + suitKey(s) }
        return r
    }

    var isEmpty: Bool { rank == nil }

    private func suitKey(_ s: String) -> String {
        switch s { case "♠": return "s"; case "♥": return "h"; case "♦": return "d"; case "♣": return "c"; default: return "" }
    }
}

// MARK: - Card Slot View

struct CardSlotView: View {
    let slot: CardSlot
    let isActive: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(slot.isEmpty ? Color.surface2 : Color(hex: "#F5F0E8"))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isActive ? Color.gold : (slot.isEmpty ? Color.borderDark.opacity(0.5) : Color.clear), lineWidth: isActive ? 2 : 1)
                )
                .shadow(color: isActive ? Color.gold.opacity(0.4) : .clear, radius: 6)

            if slot.isEmpty {
                Text("?")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.borderDark)
            } else {
                VStack(spacing: 1) {
                    Text(slot.rank ?? "")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(suitColor)
                    if let suit = slot.suit {
                        Text(suit)
                            .font(.system(size: 11))
                            .foregroundStyle(suitColor)
                    } else if let q = slot.qualifier {
                        Text(q)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(hex: "#666666"))
                    }
                }
            }
        }
        .frame(width: 44, height: 60)
    }

    private var suitColor: Color {
        switch slot.suit {
        case "♥", "♦": return Color(hex: "#C0392B")
        default: return Color(hex: "#1A1A1A")
        }
    }
}

#Preview {
    HandEntryView(
        session: Session(type: .cash, name: "Bellagio 2/5", date: Date(), tableSize: 9, heroSeatIndex: 0),
        onBack: {}
    )
}

// MARK: - Showdown Overlay

private struct ShowdownOverlay: View {
    let onResolve: (Outcome) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("SHOWDOWN")
                    .font(.custom("Georgia", size: 22))
                    .fontWeight(.black)
                    .foregroundStyle(Color.gold)
                    .tracking(2)

                HStack(spacing: 12) {
                    Button(action: { onResolve(.win) }) {
                        Text("Win")
                            .font(.custom("Arial", size: 14))
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.winGreen)
                            .foregroundStyle(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    Button(action: { onResolve(.lose) }) {
                        Text("Lose")
                            .font(.custom("Arial", size: 14))
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.foldRed)
                            .foregroundStyle(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    Button(action: { onResolve(.chop) }) {
                        Text("Chop")
                            .font(.custom("Arial", size: 14))
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.surface2)
                            .foregroundStyle(Color.gold)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gold.opacity(0.5), lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.surface)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.borderDark, lineWidth: 1))
            )
            .padding(24)
        }
    }
}
