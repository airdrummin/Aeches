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

    // Card state — one CardGroup per street (hole pair / flop / turn / river). Each group owns its
    // frames plus a single suit mode (none / bound / footnote / relationship). See `CardGroup`.
    @State private var holeGroup  = CardGroup(capacity: 2)
    @State private var flopGroup  = CardGroup(capacity: 3)
    @State private var turnGroup  = CardGroup(capacity: 1)
    @State private var riverGroup = CardGroup(capacity: 1)

    // Card picker state. `entryStreet` is the open group (nil = picker closed); `focusIndex` is the
    // cursor frame within it — the just-ranked frame that a following suit binds to in bound mode.
    // `entryLocked` is set when a *completed* group is re-opened: its cards are display-only (suits and
    // shortcuts disabled) until the user types a rank, which clears the group and unlocks fresh entry.
    @State private var entryStreet: CardStreet? = nil
    @State private var focusIndex: Int = 0
    @State private var entryLocked: Bool = false

    // Incognito mode (session-wide): hide the HERO's hole-card faces (show card backs) so a neighbor at
    // the table can't read them. The hole caption is readable while the hole bank is selected and blurs
    // otherwise — so "peek" is just re-selecting your cards. Board cards are public, never hidden.
    @State private var incognito = false

    // The bottom transcript: a 1-line sliver pinned at the bottom that expands up into the full hand.
    @State private var transcriptExpanded: Bool = false

    // Hand-close state
    @State private var handCloseSummary: String = ""
    // True from skipHand() until Undo or next deal: lets undoLastAction() restore without peeling an action.
    @State private var lastHandWasSkipped: Bool = false

    @State private var phase: Phase = .selectSeat

    enum Phase { case selectSeat, placingButton, recordingHand, showdown, handClosed }

    init(session: Session, onBack: @escaping () -> Void) {
        self.session = session
        self.onBack = onBack
        _tableSize = State(initialValue: session.tableSize)
    }

    // MARK: - Computed Properties

    private var openBetExists: Bool { betLevelThisStreet > 0 }

    /// The phases that use the play layout — a fixed-size table over the bottom assembly (strip ·
    /// action/picker zone · transcript). Button placement is included so it matches recording (no big
    /// standalone table / void); only seat-select keeps the standalone table + size picker.
    private var isPlayingPhase: Bool {
        phase == .placingButton || phase == .recordingHand || phase == .showdown || phase == .handClosed
    }

    /// Fixed height of the dock's control region — sized to the taller of its two states: the control
    /// bar (~124) plus a 5-line transcript slot (~110). The card picker (~174 natural) is shorter, so
    /// it fills this region with distributed spacing. Holding this constant across both states keeps
    /// the aspect-locked table from shifting when the picker opens. See DisplayLayoutPlan.md.
    private let controlRegionHeight: CGFloat = 234

    private var feltActionText: String? {
        switch phase {
        case .recordingHand where !streetClosedDecisively:
            switch currentStreet {
            case .preflop: return "PREFLOP"
            case .flop:    return "FLOP"
            case .turn:    return "TURN"
            case .river:   return "RIVER"
            }
        case .handClosed where !handCloseSummary.isEmpty:
            return handCloseSummary
        default:
            return nil
        }
    }

    private var tableInstruction: String? {
        switch phase {
        case .selectSeat:    return "TAKE\nYOUR SEAT"
        case .placingButton: return "PLACE\nTHE BUTTON"
        case .handClosed:    return "PLACE\nTHE BUTTON"
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
                .padding(.bottom, 10)

                // ── Table (top half) ──────────────────────────────────
                TableOvalView(
                    tableSize: tableSize,
                    heroSeat: heroSeat,
                    buttonSeat: phase == .handClosed ? nil : buttonSeat,
                    seatStates: phase == .handClosed ? [:] : seatActions,
                    // On a decisive close the ring drops entirely (Option A) — the pulse hands off to
                    // the Next Street button. The data pointer (`highlightedSeat`) stays intact for
                    // tap/rewind logic; only the *visual* highlight is suppressed here.
                    activeSeat: streetClosedDecisively ? nil : highlightedSeat,
                    positions: phase == .handClosed ? [:] : seatPositions,
                    onSeatTap: handleSeatTap,
                    onSeatSwipe: handleSeatSwipe,
                    sizingStrip: sizingStrip(for:),
                    onSeatSize: handleSeatSize,
                    instruction: tableInstruction,
                    actionText: feltActionText,
                    // One consistent table size across every phase (seat-select → showdown). The oval
                    // is aspect-locked (TableOvalView), so these bounds only control the frame margin,
                    // never the oval shape. During play the frame is the flexible element: it absorbs all
                    // device slack as margin around the oval (maxHeight .infinity) while the dock below is
                    // fixed-height — that's what pins the table still and the dock to the bottom with no
                    // void. On seat-select there is no dock, so the frame is clamped (320) and the Spacer
                    // below fills the rest. minHeight guarantees swipe room everywhere.
                    // See DisplayLayoutPlan.md §#1 and §"Layout model".
                    minHeight: 290,
                    maxHeight: isPlayingPhase ? .infinity : 320
                )
                .overlay {
                    if phase == .showdown {
                        ShowdownOverlay(onResolve: resolveShowdown)
                            .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    }
                }
                .overlay(alignment: .topLeading) {
                    if phase == .recordingHand || phase == .showdown {
                        tableActionButton("arrow.forward", "Skip", tint: Color.foldRed) { skipHand() }
                            .padding(.leading, 14)
                            .padding(.top, 10)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isPlayingPhase {
                        tableActionButton("arrow.left.and.right", "Move", tint: Color.textMuted) { moveSeat() }
                            .padding(.trailing, 14)
                            .padding(.top, 10)
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

                // ── Bottom half — card strip + fixed-height control region ──────
                // The dock (strip + control region) is fixed-height and pinned to the bottom; the table
                // above absorbs device slack. The control region is a CONSTANT height whether it holds
                // the control bar (+ transcript beneath) or the card picker — that constancy is what
                // keeps the aspect-locked table from moving when the picker opens. The picker REPLACES
                // the control bar + transcript while a card group is open (they never co-exist).
                // See DisplayLayoutPlan.md §"Layout model".
                if isPlayingPhase {
                    cardStrip
                        .padding(.top, 10)

                    Group {
                        if entryStreet != nil {
                            cardPickerPanel
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else {
                            VStack(spacing: 0) {
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
                                // Fills the region beneath the control bar — 3–5 lines, scrolls to the
                                // newest action; the full hand is the expand drawer.
                                transcriptInline
                            }
                        }
                    }
                    .frame(height: controlRegionHeight)
                } else {
                    Spacer(minLength: 0)
                }
            }

            // ── Transcript drawer — slides up from the sliver to show the full hand. The dim
            // backdrop (tap to collapse) sits behind it; the system tab bar stays on top.
            if transcriptExpanded {
                Color.black.opacity(0.55).ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.25)) { transcriptExpanded = false } }
                VStack(spacing: 0) {
                    Spacer(minLength: 120)
                    transcriptDrawer
                }
                .transition(.move(edge: .bottom))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: entryStreet != nil)
        .animation(.easeInOut(duration: 0.2), value: phase)
        .animation(.easeInOut(duration: 0.25), value: transcriptExpanded)
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
        // outcome (showdown saves a non-nil outcome; a fold-out saves nil; a skip sets the flag).
        if phase == .handClosed {
            let popped = savedHands.popLast()
            handCloseSummary = ""
            if lastHandWasSkipped {
                // Skip undo: all hand state is still live (skipHand never called resetHandState).
                // Just reverse the hand-number advance, clear the flag, and reopen recording.
                // Do NOT fall through to the peel path — there is no erroneous action to remove.
                lastHandWasSkipped = false
                handNumber -= 1
                phase = .recordingHand
                highlightedSeat = actionsThisStreet.last?.seatIndex ?? firstActor(of: currentStreet)
                return
            }
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

    /// Hero hole cards for the saved Hand. Reads the bound per-frame suit only — footnote/relationship
    /// modes collapse to per-card here (the accepted, deferred persistence limitation; the live
    /// transcript via `groupNotation` is the faithful artifact while recording).
    private func buildHeroCards() -> [Card] {
        holeGroup.frames.compactMap { frame in
            guard let rankStr = frame.rank, let rank = Rank(rawValue: rankStr) else { return nil }
            let suit = frame.suit.knownSymbol.flatMap { Suit(rawValue: suitKey($0)) }
            return Card(rank: rank, suit: suit)
        }
    }

    // MARK: - Card Strip

    private var cardStrip: some View {
        HStack(alignment: .top, spacing: 0) {
            groupSection(label: "HOLE",  street: .hole,  isActive: entryStreet == .hole)
            Spacer()
            groupSection(label: "FLOP",  street: .flop,  isActive: entryStreet == .flop)
            Spacer()
            groupSection(label: "TURN",  street: .turn,  isActive: entryStreet == .turn)
            Spacer()
            groupSection(label: "RIVER", street: .river, isActive: entryStreet == .river)
        }
        .padding(.horizontal, 12)
        .animation(.easeInOut(duration: 0.25), value: currentStreet)
    }

    /// When a footnote group is full and every entered letter is the SAME real suit (s/h/d/c — never
    /// `x`), every card is unambiguously that suit. Returns the suit symbol to color the faces with;
    /// nil otherwise (partial, mixed, or contains an explicit unknown). Display-only — see groupSection.
    private func uniformFootnoteSuit(_ g: CardGroup) -> String? {
        guard g.mode == .footnote, g.footnote.count == g.capacity else { return nil }
        let letters = Set(g.footnote)
        guard letters.count == 1, let letter = letters.first else { return nil }
        switch letter {
        case "s": return "♠"; case "h": return "♥"; case "d": return "♦"; case "c": return "♣"
        default:  return nil          // "x" (explicit unknown) is not a suit
        }
    }

    /// The frame to draw on a face: the real frame, or — for a uniform footnote — a copy with the
    /// derived suit injected so the face renders a colored pip like a bound card (no model mutation).
    private func faceFrame(_ frame: CardFrame, footnoteSuit: String?) -> CardFrame {
        guard let s = footnoteSuit else { return frame }
        var f = frame; f.suit = .known(s); return f
    }

    /// A partial footnote's suits as glyphs for the card bottom (Option D, repeated on each card):
    /// the entered letters mapped to suit symbols, padded to capacity with "x". e.g. [d,s] → ["♦","♠"],
    /// [h] (capacity 2) → ["♥","x"]. (The uniform-all-same case is shown on the faces instead.)
    private func footnoteGlyphs(_ g: CardGroup) -> [String] {
        var letters = g.footnote
        while letters.count < g.capacity { letters.append("x") }
        return letters.map { l in
            switch l {
            case "s": return "♠"; case "h": return "♥"; case "d": return "♦"; case "c": return "♣"
            default:  return "x"
            }
        }
    }

    /// The relationship code (s/o/r/m/tt) spelled out for the badge. Words, not letters, so the
    /// abstract texture is unmistakable and "suited" never collides with the spade glyph.
    private func relationshipWord(_ code: String?) -> String? {
        switch code {
        case "s":  return "suited"
        case "o":  return "offsuit"
        case "r":  return "rainbow"
        case "m":  return "mono"
        case "tt": return "two-tone"
        default:   return nil
        }
    }

    /// The group texture pill (Style C): one dark, gold-bordered capsule straddling the bottom edge of
    /// the card row. Holds either the relationship word (gold, one line) or the footnote glyph set
    /// (red ♥♦ / light ♠♣ / muted x — colored for the dark pill). Content-sized and centered.
    @ViewBuilder private func textureBadge(glyphSet: [String]?, relWord: String?) -> some View {
        HStack(spacing: 5) {
            if let word = relWord {
                Text(word)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(Color.goldLight)
                    .lineLimit(1)
            } else if let set = glyphSet {
                ForEach(Array(set.enumerated()), id: \.offset) { _, sym in
                    Text(sym)
                        .font(.system(size: 12, weight: sym == "x" ? .bold : .regular))
                        .foregroundStyle(badgeGlyphColor(sym))
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color(hex: "#222222")))
        .overlay(Capsule().stroke(Color.gold, lineWidth: 0.5))
        .fixedSize()
    }

    /// Suit-glyph colors tuned for the dark badge: red stays red, but spade/club go LIGHT (black would
    /// vanish on the dark pill), and the unknown x is muted.
    private func badgeGlyphColor(_ s: String) -> Color {
        switch s {
        case "♥", "♦": return Color(hex: "#E0524A")
        case "♠", "♣": return Color(hex: "#EDEDED")
        default:        return Color(hex: "#888888")   // x (unknown)
        }
    }

    /// The group's label row. Hole carries the incognito eye toggle (session-wide) right beside it —
    /// the one place to flip hole-card privacy on/off; other streets are just the label.
    @ViewBuilder
    private func groupLabel(_ label: String, street: CardStreet, isActive: Bool) -> some View {
        let title = Text(label)
            .font(.system(size: 9, weight: .bold))
            .tracking(1.5)
            .foregroundStyle(isActive ? Color.gold : Color.textMuted)
        if street == .hole {
            HStack(spacing: 5) {
                title
                Button(action: { incognito.toggle() }) {
                    Image(systemName: incognito ? "eye.slash" : "eye")
                        .font(.system(size: 11))
                        .foregroundStyle(incognito ? Color.gold : Color.textMuted.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        } else {
            title
        }
    }

    /// A street group: rank-forward card faces, with a caption hanging beneath the group. The caption
    /// encodes the unassigned suit info — footnote letters (`dx`, `hhx`) or a relationship word
    /// (`suited`, `two tone`). Bound mode shows its suits ON the faces and has no caption. The caption
    /// row reserves a fixed height so the faces stay baseline-aligned across all four groups.
    @ViewBuilder
    private func groupSection(label: String, street: CardStreet, isActive: Bool) -> some View {
        let g = group(for: street)
        let anyKnown = g.frames.contains { $0.suit.knownSymbol != nil }
        // A footnote whose every entered letter is the SAME real suit means we know each card's suit
        // (QJcc, JThh, Q53hhh) — so color the faces, display-only. The mode stays .footnote and the
        // caption is unchanged; the color simply disappears the moment the footnote stops being uniform.
        let footnoteSuit = uniformFootnoteSuit(g)
        // Group texture badge (additive — the text caption below is untouched). A non-uniform footnote
        // shows its known suits as a glyph set; a relationship shows its word. One pill per group,
        // straddling the bottom edge of the card row. Glyph = a real suit we know; word = an abstract
        // texture. (bound / uniform-footnote stay on the faces; none → no pill.) See DisplayLayoutPlan.md.
        let glyphSet: [String]? = (g.mode == .footnote && footnoteSuit == nil) ? footnoteGlyphs(g) : nil
        let relWord: String? = (g.mode == .relationship) ? relationshipWord(g.relationship) : nil
        let faceDown = incognito && street == .hole   // incognito hides only the hero's hole faces
        // In incognito the hole's caption is the single read-out (the pill is omitted, below). The caption
        // blurs whenever the hole bank isn't selected, and clears again when you re-select your cards.
        let hideReadouts = faceDown && entryStreet != .hole
        VStack(spacing: 6) {
            groupLabel(label, street: street, isActive: isActive)

            HStack(spacing: 4) {
                ForEach(g.frames.indices, id: \.self) { i in
                    // For uniform footnote, render the face with the derived suit injected so it draws the
                    // colored pip exactly like a bound card (display-only — the model is untouched).
                    CardFrameView(
                        frame: faceFrame(g.frames[i], footnoteSuit: footnoteSuit),
                        showBoundSuit: g.mode == .bound || footnoteSuit != nil,
                        // Show the grey "x" for an explicit unknown, or for a blank card whose partner
                        // already carries a real suit (the inferred AhKx case).
                        boundUnknown: g.mode == .bound &&
                            (g.frames[i].suit == .unknown || (g.frames[i].suit == .unspecified && anyKnown)),
                        suitRun: g.suitRun,   // turn/river board count → repeated pips (1 elsewhere)
                        faceDown: faceDown,
                        isActive: entryStreet == street && focusIndex == i
                    )
                    .onTapGesture { openCardEntry(street) }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isActive ? Color.gold.opacity(0.45) : Color.clear, lineWidth: 1.5)
            )
            .overlay(alignment: .bottom) {
                // In incognito the pill is omitted entirely on the hole — it's redundant with the caption
                // text and would leak the suits. The text caption (below) is the single hole read-out.
                if (glyphSet != nil || relWord != nil) && !faceDown {
                    textureBadge(glyphSet: glyphSet, relWord: relWord)
                        .offset(y: 9)   // straddle the bottom edge (tuning dial with the caption padding below)
                }
            }

            // Caption: the group's full shorthand in plain Courier text, shown as soon as ANY rank is
            // entered (groupNotation renders ranks-only too — "5", "55" — then fills in suits). The line
            // is ALWAYS rendered (a blank space when empty) so the strip keeps a constant height — the
            // picker never slides as you type.
            // Incognito: the hole caption is readable while the hole bank is selected (you tapped your
            // cards), and blurs whenever it isn't — so "peek" is just re-selecting hole. Board never hides.
            let notation = groupNotation(street)
            Text(notation.isEmpty ? " " : notation)
                .font(.custom("Courier New", size: 13))
                .fontWeight(.bold)
                .tracking(1)
                .foregroundStyle(Color.goldLight)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: 20)
                .padding(.top, 6)   // clearance for the straddling texture pill above
                .blur(radius: hideReadouts ? 4 : 0)
        }
    }

    /// The footnote letters padded to the group size with "x" (e.g. [d] → "dx", [h,h] → "hhx").
    /// Used by `groupNotation` to render the footnote token.
    private func paddedFootnote(_ g: CardGroup) -> String {
        var letters = g.footnote
        while letters.count < g.capacity { letters.append("x") }
        return letters.joined()
    }

    // MARK: - Card Picker Panel

    // Mutually-exclusive gating. Suits (♠♥♦♣ x) are live once a rank exists, UNLESS the group is
    // committed to a relationship. Relationship shortcuts (s/o, r/m/tt) are live only when all ranks
    // are in AND no specific suit has been committed (mode none or relationship) — and never for a
    // hole pair (no 88s; 88o is assumed, never written). So at "both ranks, nothing chosen" both sets
    // are live; the first suit turns s/o off, the first s/o turns suits off.
    private var entryGroup: CardGroup? { entryStreet.map { group(for: $0) } }

    private var suitsActive: Bool {
        guard !entryLocked, let g = entryGroup else { return false }
        return g.hasAnyRank && g.mode != .relationship
    }

    private var relActive: Bool {
        guard !entryLocked, let street = entryStreet, let g = entryGroup else { return false }
        guard g.isFull, g.mode == .none || g.mode == .relationship else { return false }
        // Hole pair → no suited/offsuit.
        if street == .hole, let r0 = g.frames.first?.rank, let r1 = g.frames.last?.rank, r0 == r1 {
            return false
        }
        return true
    }

    /// Every fully-specified card (rank + a *bound* known suit) already in this hand, across all groups,
    /// keyed `"As"` — excluding one frame (the cursor, so re-binding its own card never blocks itself).
    /// Only bound frames carry a known per-card suit, so this is inherently "bound only": footnote and
    /// relationship suits are unassigned and contribute nothing.
    private func usedCardKeys(excluding street: CardStreet?, index: Int?) -> Set<String> {
        var keys = Set<String>()
        for (s, g) in [(CardStreet.hole, holeGroup), (.flop, flopGroup), (.turn, turnGroup), (.river, riverGroup)] {
            for (i, f) in g.frames.enumerated() {
                if s == street, i == index { continue }
                if let r = f.rank, let sym = f.suit.knownSymbol { keys.insert(r + suitLetter(sym)) }
            }
        }
        return keys
    }

    /// True when binding `suit` to the cursor card would re-create a card already in the hand — so the
    /// suit button is disabled. Only fires on the bound path (a suit that appends to a footnote isn't a
    /// concrete card and can't duplicate).
    private func suitIsDuplicate(_ suit: String) -> Bool {
        guard let street = entryStreet else { return false }
        let g = group(for: street)
        let willBind = g.mode == .bound || (g.mode == .none && (g.capacity == 1 || g.firstEmptyIndex != nil))
        guard willBind, focusIndex < g.frames.count, let rank = g.frames[focusIndex].rank else { return false }
        return usedCardKeys(excluding: street, index: focusIndex).contains(rank + suitLetter(suit))
    }

    // Docked below the strip (not a covering sheet). The strip slots are the frames — they stay
    // visible and highlight the focused one — so the picker shows only the controls, no duplicate cards.
    private var cardPickerPanel: some View {
        // Fills the fixed control region (controlRegionHeight). The picker's natural height is shorter
        // than the region, so the Spacers distribute the surplus as generous spacing between the rows
        // (the handle stays pinned to the top to keep its swipe-down dismiss obvious). The surface
        // background fills the whole region, so there is no visible gap. See DisplayLayoutPlan.md §#3.
        VStack(spacing: 0) {
            if let street = entryStreet {
                // Slim grab handle — tap or swipe down to dismiss ("no more cards / stop here").
                grabHandle

                Spacer(minLength: 10)

                // Rank grid — row 1 (the seven) full width; row 2 (the shorter six) flanked by Clear
                // (trash, left) and Next (›, right), using that row's natural side-space so the suit
                // cluster below gets a full-width row of its own. The six still nests into the gaps of
                // the seven above (both rank rows stay centered).
                VStack(spacing: 6) {
                    rankRow(["A","K","Q","J","T","9","8"])
                    HStack(spacing: 0) {
                        iconButton("trash", tint: Color.foldRed) { clearEntryGroup() }
                        Spacer(minLength: 8)
                        rankRow(["7","6","5","4","3","2"])
                        Spacer(minLength: 8)
                        nextBankButton
                    }
                }

                Spacer(minLength: 12)

                // Suit + shortcut cluster — its own full-width centered row, uncramped even on the
                // wide flop set (♠ ♥ ♦ ♣ x │ r m tt).
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    suitCluster(for: street)
                    Spacer(minLength: 0)
                }

                Spacer(minLength: 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .background(Color.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.borderDark.opacity(0.6)).frame(height: 1)
        }
    }

    /// The dismiss affordance: a slim grabber bar at the top of the picker. Tap or swipe down to
    /// close (reveals the transcript) — the "no more cards / stop here" action, on any bank.
    private var grabHandle: some View {
        Capsule()
            .fill(Color.borderDark)
            .frame(width: 40, height: 5)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { closeEntry() } }
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onEnded { v in
                        if v.translation.height > 12 {
                            withAnimation(.easeInOut(duration: 0.2)) { closeEntry() }
                        }
                    }
            )
    }

    /// The advance control: a 30×40 gold tile, `›` to jump to the next bank (hole → flop → turn →
    /// river), or `✓` on the river (no next bank) to dismiss.
    private var nextBankButton: some View {
        let isRiver = entryStreet == .river
        return Button(action: advanceOrFinishEntry) {
            Image(systemName: isRiver ? "checkmark" : "chevron.right")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(hex: "#0D0D0D"))
                .frame(width: 30, height: 40)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.gold))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.goldLight, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// The centered control cluster: the four suits + "x" (unknown), and — for hole/flop — a
    /// divider followed by the relationship/texture shortcut squares (s/o or r/m). Turn and river
    /// have no shortcuts, so their cluster is just the five suit squares.
    @ViewBuilder
    private func suitCluster(for street: CardStreet) -> some View {
        HStack(spacing: 8) {
            suitSquare("♠"); suitSquare("♥"); suitSquare("♦"); suitSquare("♣")
            unknownSuitSquare()
            if street == .hole || street == .flop {
                Rectangle()
                    .fill(Color.borderDark)
                    .frame(width: 1, height: 30)
                shortcutSquares(for: street)
            } else {
                // Turn/river: the relationship slot instead holds the board-count ×N buttons.
                Rectangle()
                    .fill(Color.borderDark)
                    .frame(width: 1, height: 30)
                multiplierSquares(for: street)
            }
        }
    }

    /// The suit-skinned board-count buttons for turn/river — `count` suit glyphs in the dice-like pip
    /// layout (turn 2–4, river 3–5). They adopt the chosen suit's glyph + color and are disabled until a
    /// real suit is set (an `x` can't be multiplied).
    @ViewBuilder
    private func multiplierSquares(for street: CardStreet) -> some View {
        let suitSym = entryGroup?.frames.first?.suit.knownSymbol
        let cur = entryGroup?.suitRun ?? 1
        ForEach(suitRunCycle(for: street).dropFirst(), id: \.self) { n in
            multiplierSquare(n: n, suitSymbol: suitSym, selected: cur == n)
        }
    }

    private func multiplierSquare(n: Int, suitSymbol: String?, selected: Bool) -> some View {
        let active = !entryLocked && suitSymbol != nil
        let suitColor: Color = suitSymbol.map { ["♥", "♦"].contains($0) ? Color(hex: "#E0524A") : Color.white }
            ?? Color.textMuted
        return Button(action: { multiplierTapped(n) }) {
            SuitPips(symbol: suitSymbol ?? "♠", count: n, color: suitColor, glyphSize: 9)
                .frame(width: 36, height: 40)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.surface2))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Color.gold : Color.borderDark, lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .disabled(!active)
        .opacity(active ? 1.0 : 0.35)
    }

    @ViewBuilder
    private func shortcutSquares(for street: CardStreet) -> some View {
        switch street {
        case .hole:
            shortcutSquare("s")  { shortcutTapped("s") }
            shortcutSquare("o")  { shortcutTapped("o") }
        case .flop:
            shortcutSquare("r")  { shortcutTapped("r") }
            shortcutSquare("m")  { shortcutTapped("m") }
            shortcutSquare("tt") { shortcutTapped("tt") }
        case .turn, .river:
            EmptyView()
        }
    }

    /// A 30×30 utility icon button (the picker's Clear/trash): a surface tile with a tint-colored
    /// glyph and a matching subtle border. Sized to match the suit squares.
    private func iconButton(_ systemName: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 40)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.surface2))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(tint.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom Transcript (inline tail + expand-up drawer)

    /// The inline transcript inside the dock's control region, beneath the control bar: a header (tap the
    /// chevron to expand the full hand up; Copy) over a scrollable tail of the running shorthand. It fills
    /// the region's remaining space below the control bar (~3–5 lines), auto-scrolling to the newest
    /// action; the full hand is the expand drawer. It is hidden while the picker is open (the picker takes
    /// the whole control region), so the two never co-exist. See DisplayLayoutPlan.md §#4.
    private var transcriptInline: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: { withAnimation(.easeInOut(duration: 0.25)) { transcriptExpanded = true } }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.up").font(.system(size: 10, weight: .bold))
                        Text("HAND").font(.system(size: 10, weight: .bold)).tracking(1.5)
                    }
                    .foregroundStyle(Color.gold)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                Button(action: copyShorthand) {
                    Image(systemName: "doc.on.doc").font(.system(size: 12)).foregroundStyle(Color.gold)
                }
                .buttonStyle(.plain)
                .disabled(handShorthand.isEmpty)
                .opacity(handShorthand.isEmpty ? 0.35 : 1.0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 7)
            .padding(.bottom, 4)

            ScrollViewReader { proxy in
                ScrollView {
                    Text(handShorthand.isEmpty ? "No actions yet — record on the table or fill in cards." : handShorthand)
                        .font(.custom("Courier New", size: 12))
                        .foregroundStyle(handShorthand.isEmpty ? Color.textMuted : Color.textBody)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    Color.clear.frame(height: 1).id("tailEnd")
                }
                .onChange(of: handShorthand) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("tailEnd", anchor: .bottom) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.borderDark.opacity(0.6)).frame(height: 1)
        }
    }

    /// The expanded transcript drawer — the full multi-line hand in Courier, with Copy and a collapse
    /// chevron. Presented as a bottom drawer from `body` (sized by the spacer above it there).
    private var transcriptDrawer: some View {
        VStack(spacing: 0) {
            HStack {
                Text("HAND")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(Color.gold)
                Spacer()
                Button(action: copyShorthand) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc").font(.system(size: 12))
                        Text("Copy").font(.custom("Arial", size: 13))
                    }
                    .foregroundStyle(Color.textBody)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .overlay(Capsule().stroke(Color.borderDark, lineWidth: 1))
                }
                .buttonStyle(.plain)
                Button(action: { withAnimation(.easeInOut(duration: 0.25)) { transcriptExpanded = false } }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.gold)
                        .padding(.leading, 12)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            Rectangle().fill(Color.borderDark).frame(height: 1)

            ScrollViewReader { proxy in
                ScrollView {
                    Text(handShorthand)
                        .font(.custom("Courier New", size: 14))
                        .foregroundStyle(Color.textBody)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(18)
                    Color.clear.frame(height: 1).id("drawerEnd")
                }
                .onAppear { proxy.scrollTo("drawerEnd", anchor: .bottom) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.borderDark.opacity(0.6)).frame(height: 1)
        }
    }

    private func copyShorthand() {
        UIPasteboard.general.string = handShorthand
    }

    @ViewBuilder
    private func rankRow(_ ranks: [String]) -> some View {
        HStack(spacing: 8) {
            ForEach(ranks, id: \.self) { r in
                Button(action: { rankTapped(r) }) {
                    Text(r)
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 40, height: 48)
                        .background(Color.surface2)
                        .foregroundStyle(Color.textBody)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderDark, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// A 34×40 suit square. Hearts/diamonds render red; spades/clubs white. Dimmed/disabled until the
    /// open group has at least one rank and isn't committed to a relationship (`suitsActive`).
    private func suitSquare(_ suit: String) -> some View {
        // Disabled when suits aren't live yet, OR when this exact card (rank+suit) is already in the hand.
        let enabled = suitsActive && !suitIsDuplicate(suit)
        return Button(action: { suitTapped(suit) }) {
            Text(suit)
                .font(.system(size: 18))
                .foregroundStyle(["♥", "♦"].contains(suit) ? Color(hex: "#E74C3C") : Color.white)
                .frame(width: 34, height: 40)
                .background(Color.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderDark, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1.0 : 0.35)
    }

    /// The unknown-suit square — renders the shorthand marker "x" (e.g. Ax), suit left unrecorded.
    private func unknownSuitSquare() -> some View {
        Button(action: { suitTapped(nil) }) {
            Text("x")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.textMuted)
                .frame(width: 34, height: 40)
                .background(Color.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderDark, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!suitsActive)
        .opacity(suitsActive ? 1.0 : 0.35)
    }

    /// A 34×40 relationship/texture shortcut square (s/o hole; r/m/tt flop). Dimmed/disabled until the
    /// open group's ranks are all filled and no specific suit is committed (`relActive`).
    private func shortcutSquare(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: label.count > 1 ? 14 : 17, weight: .bold))
                .foregroundStyle(Color.goldLight)
                .frame(width: 34, height: 40)
                .background(Color.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gold.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!relActive)
        .opacity(relActive ? 1.0 : 0.35)
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

    /// The live group for a street.
    private func group(for street: CardStreet) -> CardGroup {
        switch street {
        case .hole:  return holeGroup
        case .flop:  return flopGroup
        case .turn:  return turnGroup
        case .river: return riverGroup
        }
    }

    private func setGroup(_ street: CardStreet, _ g: CardGroup) {
        switch street {
        case .hole:  holeGroup  = g
        case .flop:  flopGroup  = g
        case .turn:  turnGroup  = g
        case .river: riverGroup = g
        }
    }

    /// Opening a group focuses the left-most empty frame (or card 1 if full); entry is always
    /// left-to-right, so the tapped slot index is ignored. Re-opening never mutates the cards — a
    /// finished group is cleared only when you start typing a new rank (see `rankTapped`).
    private func openCardEntry(_ street: CardStreet) {
        entryStreet = street
        let g = group(for: street)
        entryLocked = g.isFull          // re-opening a finished group → display-only until a rank is typed
        focusIndex = g.firstEmptyIndex ?? 0
    }

    private func closeEntry() {
        entryStreet = nil    // no mutation; any blank renders as "x" via notation
    }

    /// The bank that "Next" advances to, in deal order. Nil after the river (Next becomes Done).
    private func nextCardStreet(after street: CardStreet) -> CardStreet? {
        switch street {
        case .hole:  return .flop
        case .flop:  return .turn
        case .turn:  return .river
        case .river: return nil
        }
    }

    /// "Next" / "Done": jump to the next bank for rapid sequential entry, or dismiss on the river.
    /// Advancing never requires the current bank to be full — you can skip cards and tap back.
    private func advanceOrFinishEntry() {
        guard let street = entryStreet else { return }
        if let next = nextCardStreet(after: street) {
            withAnimation(.easeInOut(duration: 0.15)) { openCardEntry(next) }
        } else {
            closeEntry()
        }
    }

    private func clearEntryGroup() {
        guard let street = entryStreet else { return }
        var g = group(for: street); g.reset(); setGroup(street, g)
        focusIndex = 0
    }

    /// Tap a rank. A full group means you're starting a new hand, so it CLEARS and restarts with this
    /// rank as the first card (no jarring in-place edit). Otherwise it fills the left-most empty frame
    /// and parks the cursor there — the cursor is always "the card you just typed," so a following suit
    /// binds to it.
    private func rankTapped(_ r: String) {
        guard let street = entryStreet else { return }
        entryLocked = false             // typing a rank begins fresh entry, releasing the re-open lock
        var g = group(for: street)
        if g.isFull {
            g.reset()
            g.frames[0].rank = r
            focusIndex = 0
        } else {
            let i = g.firstEmptyIndex ?? 0
            g.frames[i].rank = r
            focusIndex = i
        }
        setGroup(street, g)
    }

    /// Tap a suit (`♠♥♦♣`) or the unknown `x` (`symbol == nil`). The first suit of the group sets the
    /// mode via the first-suit rule: an empty rank frame still open → bound (suit binds to the
    /// just-ranked cursor card); all ranks in → footnote (append to the unassigned note).
    private func suitTapped(_ symbol: String?) {
        guard let street = entryStreet else { return }
        var g = group(for: street)
        // Gating disables suits in relationship mode and before any rank; this guard is belt-and-
        // suspenders. The cursor stays put — a suit always binds to the card you're on, and the next
        // rank (which clears a full group) is what starts a new hand.
        guard g.hasAnyRank, g.mode != .relationship else { return }

        if g.mode == .none {
            // First-suit rule: an empty rank frame still open → bound; all ranks in → footnote.
            // Single-frame groups (turn/river) are always bound — there is no "which card" ambiguity.
            g.mode = (g.capacity == 1 || g.firstEmptyIndex != nil) ? .bound : .footnote
        }

        switch g.mode {
        case .bound:
            // Turn/river (single frame) with a real suit: re-tapping the SAME suit cycles the board
            // count (the fast path alongside the ×N buttons). A different suit, or x, resets the run.
            if g.capacity == 1, let sym = symbol {
                if g.frames[0].suit.knownSymbol == sym {
                    let cycle = suitRunCycle(for: street)
                    let idx = cycle.firstIndex(of: g.suitRun) ?? 0
                    g.suitRun = cycle[(idx + 1) % cycle.count]
                } else {
                    g.frames[0].suit = .known(sym)
                    g.suitRun = 1
                }
            } else {
                g.frames[focusIndex].suit = symbol.map(FrameSuit.known) ?? .unknown   // x → explicit unknown
                if g.capacity == 1 { g.suitRun = 1 }   // x / reset on a single card
            }
        case .footnote:
            let letter = symbol.map(suitLetter) ?? "x"
            if g.footnote.count < g.capacity {
                g.footnote.append(letter)
            } else {
                g.footnote[g.footnoteCursor] = letter
                g.footnoteCursor = (g.footnoteCursor + 1) % g.capacity
            }
        case .relationship, .none:
            break
        }
        setGroup(street, g)
    }

    /// Tap a relationship/texture shortcut (`s`/`o` hole; `r`/`m`/`tt` flop). Sets relationship mode,
    /// clearing any bound suits and footnote. Gated to a fully-ranked group.
    private func shortcutTapped(_ value: String) {
        guard let street = entryStreet else { return }
        var g = group(for: street)
        guard g.isFull else { return }   // gating belt-and-suspenders (the button is also dimmed)
        g.mode = .relationship
        g.relationship = value
        g.footnote = []; g.footnoteCursor = 0
        for i in g.frames.indices { g.frames[i].suit = .unspecified }
        setGroup(street, g)
    }

    /// The board-count steps for a street's ×N multipliers and the re-tap cycle. Turn maxes at 4 of a
    /// suit; the river adds 5 but drops 2 (two of a suit can't make/draw a flush on the final card).
    /// The leading 1 is the plain single-suit card. Turn/river only.
    private func suitRunCycle(for street: CardStreet) -> [Int] {
        street == .river ? [1, 3, 4, 5] : [1, 2, 3, 4]
    }

    /// Tap a ×N multiplier on a turn/river card: set the board count directly. Requires a real suit
    /// already chosen (an `x` or blank can't be multiplied).
    private func multiplierTapped(_ n: Int) {
        guard let street = entryStreet, street == .turn || street == .river else { return }
        var g = group(for: street)
        guard g.frames.first?.suit.knownSymbol != nil else { return }
        g.suitRun = n
        setGroup(street, g)
    }

    // MARK: - Card Notation (group readout — see ShorthandReference.md §2)

    private func suitLetter(_ s: String) -> String {
        switch s {
        case "♠": return "s"; case "♥": return "h"; case "♦": return "d"; case "♣": return "c"
        default:  return ""
        }
    }

    /// The group's compact shorthand (see ShorthandReference.md §2), driven by its suit mode:
    /// none `AJ` · bound `AdJx` · footnote `AJdx` (letters padded to N with `x`) · relationship
    /// `AJs`/`Q53tt`. Single-frame groups (turn/river) are bound-only and never mark an unknown.
    private func groupNotation(_ street: CardStreet) -> String {
        let g = group(for: street)
        let ranks = g.frames.compactMap { $0.rank }
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
            // A blank card reads as "x" only when a partner carries a real suit (the inferred AhKx);
            // an explicit unknown always reads as "x" (even alone — Jx, Qx).
            let anyKnown = g.frames.contains { $0.suit.knownSymbol != nil }
            let markUnknown = anyKnown && g.capacity > 1
            return g.frames.compactMap { f -> String? in
                guard let r = f.rank else { return nil }
                switch f.suit {
                // The suit letter repeats by suitRun — the turn/river board count (4h / 4hh / 4hhh).
                // suitRun is 1 everywhere except a multiplied turn/river card, so hole/flop are unchanged.
                case .known(let s): return r + String(repeating: suitLetter(s), count: g.suitRun)
                case .unknown:      return r + "x"
                case .unspecified:  return markUnknown ? r + "x" : r
                }
            }.joined()                                           // AdJx / Qh5h3x / Jh / Jx
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
        holeGroup  = CardGroup(capacity: 2)
        flopGroup  = CardGroup(capacity: 3)
        turnGroup  = CardGroup(capacity: 1)
        riverGroup = CardGroup(capacity: 1)
        entryStreet = nil
        focusIndex  = 0
        entryLocked = false
        currentStreet = .preflop
        streets = []
        actionsThisStreet = []
        betLevelThisStreet = 0
        activeSeatSequence = []
        foldedSeats = []
        highlightedSeat = nil
        handCloseSummary = ""
        streetClosedDecisively = false
        lastHandWasSkipped = false
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

    /// Saves the current hand as incomplete (outcome: nil) and moves to handClosed without clearing
    /// hand state — so Undo can fully restore recording. dealNextHand / moveSeat will reset when the
    /// user actually moves on. Hand number increments; the skip flag lets undoLastAction skip the peel.
    private func skipHand() {
        withAnimation(.easeInOut(duration: 0.2)) {
            saveCurrentHand(outcome: nil)
            handNumber += 1
            lastHandWasSkipped = true
            highlightedSeat = nil
            phase = .handClosed
        }
    }

    /// Saves any in-progress hand as incomplete, increments the hand number, releases the hero seat,
    /// and returns to seat selection. From handClosed (hand already saved) only increments and resets.
    /// From placingButton (nothing started) just resets — no save, no increment.
    private func moveSeat() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if phase == .recordingHand || phase == .showdown {
                saveCurrentHand(outcome: nil)
                handNumber += 1
            } else if phase == .handClosed {
                handNumber += 1
            }
            heroSeat = nil
            resetHandState()
            phase = .selectSeat
        }
    }

    // MARK: - Table Utility Button

    private func tableActionButton(_ icon: String, _ label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.custom("Arial", size: 10))
                    .fontWeight(.semibold)
                    .tracking(0.3)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.surface2.opacity(0.9))
                    .overlay(Capsule().stroke(tint.opacity(0.25), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
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
                .font(.custom("Arial", size: 16))
                .fontWeight(.bold)
                .foregroundStyle(chipForeground(style))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
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

// MARK: - Card Group Model

/// A bound card's suit as a three-state value, so an *explicit* unknown (`x`, deliberately entered)
/// is distinct from a frame that simply hasn't been suited yet. Used only while the group is `.bound`.
enum FrameSuit: Equatable {
    case unspecified            // nothing entered yet (blank)
    case unknown                // explicit "x" — always shows/reads as x, even alone (Jx, Qx)
    case known(String)          // "♠" "♥" "♦" "♣"

    /// The suit symbol when a real suit is set, else nil (both `.unspecified` and `.unknown`).
    var knownSymbol: String? { if case .known(let s) = self { return s } else { return nil } }
}

/// One card frame: a rank, plus a bound suit that is only meaningful while the group is `.bound`.
struct CardFrame: Equatable {
    var rank: String? = nil          // "A","K",…,"2"
    var suit: FrameSuit = .unspecified
    var isEmpty: Bool { rank == nil }
}

/// A street's group of frames plus its single suit mode. Hole = 2 frames, flop = 3, turn/river = 1.
/// The mode determines how suit info is stored and rendered (see `groupNotation`):
/// - `.bound`        per-frame suit (interleaved entry) — `AdJx`
/// - `.footnote`     an unassigned trailing note of suit letters — `AJdx`
/// - `.relationship` an abstract relationship/texture from a shortcut button — `AJs` / `Q53tt`
struct CardGroup: Equatable {
    enum SuitMode: Equatable { case none, bound, footnote, relationship }

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
}

// MARK: - Suit Pips — N copies of a suit glyph in a dice-like layout (board count on turn/river)

/// Arranges `count` suit glyphs in the same pip grammar as the seat raise-pips: 1 single, 2 side-by-
/// side, 3 point-up triangle, 4 a 2×2, 5 a 2-1-2 quincunx. Shared by the card face and the ×N buttons.
struct SuitPips: View {
    let symbol: String
    let count: Int
    let color: Color
    var glyphSize: CGFloat = 9

    var body: some View {
        VStack(spacing: 0) {
            switch max(1, count) {
            case 1:  row(1)
            case 2:  row(2)
            case 3:  row(1); row(2)
            case 4:  row(2); row(2)
            default: row(2); row(1); row(2)   // 5
            }
        }
    }

    private func row(_ n: Int) -> some View {
        HStack(spacing: 1) {
            ForEach(0..<n, id: \.self) { _ in
                Text(symbol).font(.system(size: glyphSize)).foregroundStyle(color)
            }
        }
    }
}

// MARK: - Card Back — incognito hole cards (gold lattice + center diamond crest on dark)

/// The face-down back shown for hero hole cards in incognito mode. Option 8: a fine gold cross-hatch
/// lattice with a small gold diamond crest, framed by a gold rim — reads as a card back, not a bug.
struct CardBackView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(hex: "#15110A"))
            Canvas { ctx, size in
                let gold = GraphicsContext.Shading.color(Color(hex: "#C9A84C").opacity(0.45))
                var path = Path()
                let spacing: CGFloat = 6
                var off = -size.height
                while off < size.width + size.height {
                    path.move(to: CGPoint(x: off, y: 0));            path.addLine(to: CGPoint(x: off + size.height, y: size.height))
                    path.move(to: CGPoint(x: off, y: size.height));  path.addLine(to: CGPoint(x: off + size.height, y: 0))
                    off += spacing
                }
                ctx.stroke(path, with: gold, lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Rectangle()
                .fill(Color(hex: "#15110A"))
                .frame(width: 13, height: 13)
                .overlay(Rectangle().stroke(Color(hex: "#C9A84C"), lineWidth: 1))
                .rotationEffect(.degrees(45))
            RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color(hex: "#8A6E2E"), lineWidth: 1)
        }
        .frame(width: 40, height: 40)
    }
}

// MARK: - Card Frame View — compact card face (rank + bound suit / "x"), thin for the strip band

struct CardFrameView: View {
    let frame: CardFrame
    var showBoundSuit: Bool = false   // true only in .bound mode — draws the suit pip on the face
    var boundUnknown: Bool = false    // bound, suitless, but a partner card is suited → grey "x"
    var suitRun: Int = 1              // turn/river: draw the suit pip this many times (board count)
    var faceDown: Bool = false        // incognito: a filled hole card shows its back instead of the face
    let isActive: Bool

    var body: some View {
        // Incognito: a filled card shows the back. Empty slots stay as the "?" placeholder (no card to hide).
        if faceDown && !frame.isEmpty {
            CardBackView()
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.gold, lineWidth: 2)
                        .opacity(isActive ? 1 : 0)
                )
        } else {
            faceBody
        }
    }

    private var faceBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(frame.isEmpty ? Color.surface2 : Color(hex: "#F5F0E8"))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isActive ? Color.gold : (frame.isEmpty ? Color.borderDark.opacity(0.5) : Color.clear), lineWidth: isActive ? 2 : 1)
                )
                .shadow(color: isActive ? Color.gold.opacity(0.4) : .clear, radius: 6)

            if frame.isEmpty {
                Text("?")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.borderDark)
            } else {
                VStack(spacing: 0) {
                    Text(frame.rank ?? "")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(rankColor)
                    // Per-card suit pip: only in bound / uniform-footnote (showBoundSuit). Footnote-partial
                    // and relationship are shown by the group pill (see groupSection), so the face is
                    // rank-only there.
                    if showBoundSuit, let suit = frame.suit.knownSymbol {
                        // One pip normally; turn/river repeat it by suitRun (board count) in a row — sized
                        // down so up to five fit the 40px card. (The pip *layout* is the picker button only.)
                        HStack(spacing: 1) {
                            ForEach(0..<max(1, suitRun), id: \.self) { _ in
                                Text(suit).foregroundStyle(suitColor)
                            }
                        }
                        .font(.system(size: suitRun >= 4 ? 7 : (suitRun >= 2 ? 8 : 9)))
                    } else if boundUnknown {
                        Text("x")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color(hex: "#888888"))
                    }
                }
            }
        }
        .frame(width: 40, height: 40)
    }

    // The rank takes the suit color only when a bound suit is shown; otherwise it stays neutral black
    // (footnote/relationship/none faces are rank-only, so coloring them by a suit would mislead).
    private var rankColor: Color {
        (showBoundSuit && frame.suit.knownSymbol != nil) ? suitColor : Color(hex: "#1A1A1A")
    }

    private var suitColor: Color {
        switch frame.suit.knownSymbol {
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
