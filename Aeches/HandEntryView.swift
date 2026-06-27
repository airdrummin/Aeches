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

    /// The app-wide persisted source of truth. Closed hands are written here (upsert by id); nothing
    /// reads live `@State` to render a saved hand.
    @EnvironmentObject private var store: SessionStore

    /// The in-progress hand's durable identity. Stable across re-close (Undo→re-close) and post-close
    /// card edits, so `store.saveHand` updates one record instead of duplicating. Regenerated only when
    /// a NEW hand begins (`resetHandState`), never on Undo-reopen.
    @State private var currentHandID = UUID()
    /// The closed hand's outcome, set at each close — lets post-close edits rebuild via `buildHand`
    /// without reading a saved-hand array. Reset in `resetHandState`.
    @State private var currentOutcome: Outcome? = nil

    // Hero seat — locked for the session
    @State private var heroSeat: Int? = nil
    @State private var tableSize: Int

    /// Seats with no player (busted, not yet filled). Table composition, NOT per-hand action: it
    /// persists across hands (NOT cleared by resetHandState) until edited again, and a hand simply
    /// plays as if those seats don't exist (excluded from positions, the ring, and street close).
    /// Edited only at `placingButton` via the Edit-Seats toggle. Hero's seat can never be empty.
    @State private var emptySeats: Set<Int> = []
    /// True while the place-button screen is in "tap a seat to toggle empty" mode (vs. place button).
    @State private var seatEditMode: Bool = false

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

    /// True only when a decisive input (swipe / action button) on the last actor completed the
    /// betting round, so the ring is held on that seat awaiting a Next Street tap. In this state the
    /// seat drops its highlight/pulse entirely and the Next Street button pulses instead. Reset to
    /// false by every record/tap/rewind/advance/deal via `recomputeDerivedState` + `resetHandState`.
    @State private var streetClosedDecisively: Bool = false

    /// True while the control-bar sizing chip row is showing — armed by a 0.3s hold on the Raise/Bet
    /// button, which records the aggressive action UNSIZED immediately (like cycling). Tapping a chip
    /// re-records it sized and advances; any other committed input / undo / tap dismisses the row. The
    /// held action is a normal log entry, so Undo peels it with no special case (see SizingOverhaul.md).
    @State private var sizingRowVisible: Bool = false

    // Card state — one CardGroup per street (hole pair / flop / turn / river). Each group owns its
    // frames plus a single suit mode (none / bound / footnote / relationship). See `CardGroup`.
    @State private var holeGroup  = CardGroup(capacity: 2)
    @State private var flopGroup  = CardGroup(capacity: 3)
    @State private var turnGroup  = CardGroup(capacity: 1)
    @State private var riverGroup = CardGroup(capacity: 1)
    // Villain hole groups, keyed by seat — entered in the card strip at showdown/close (the seats still
    // in the hand). Per-hand; cleared on reset. Saved verbatim to `Hand.villainGroups` (lossless);
    // `Hand.villainCards` is the computed flat-card view of them.
    @State private var villainGroups: [Int: CardGroup] = [:]

    // Card picker state. `entryTarget` is the open group (nil = picker closed): a hero street or a
    // villain seat. `focusIndex` is the cursor frame within it — the just-ranked frame a following suit
    // binds to in bound mode. `entryLocked` is set when a *completed* group is re-opened: its cards are
    // display-only (suits and shortcuts disabled) until the user types a rank, which clears and unlocks.
    @State private var entryTarget: CardTarget? = nil
    /// Behavior context for the open group (villain → `.hole`). Every street-keyed picker helper reads
    /// this, so villain entry reuses the hole logic with no special-casing; identity checks use `entryTarget`.
    private var entryStreet: CardStreet? { entryTarget?.behaviorStreet }
    @State private var focusIndex: Int = 0
    @State private var entryLocked: Bool = false

    // Incognito mode (session-wide): hide the HERO's hole-card faces (show card backs) so a neighbor at
    // the table can't read them. The hole caption is readable while the hole bank is selected and blurs
    // otherwise — so "peek" is just re-selecting your cards. Board cards are public, never hidden.
    @State private var incognito = false

    // The bottom transcript: a tail pinned at the bottom that expands up into the full hand. It is one
    // height-animated panel (collapsed ↔ full section), so expand and collapse are the same animation
    // run forward and backward. The collapsed height is the measured freed space under the control bar
    // (which shrinks when the action row is absent — place-button / hand-closed — so the tail grows to
    // fill it); the expanded height is the measured section. Both carry fallbacks for the first frame.
    @State private var transcriptExpanded: Bool = false
    @State private var transcriptCopied: Bool = false
    @State private var bottomSectionHeight: CGFloat = 320      // full card-strip + control region (measured)
    @State private var collapsedTranscriptHeight: CGFloat = 110 // freed space under the control bar (measured)

    // Hand-close state
    @State private var handCloseSummary: String = ""
    // True from skipHand() until Undo or next deal: lets undoLastAction() restore without peeling an action.
    @State private var lastHandWasSkipped: Bool = false

    // Effective stack (per-hand, in big blinds) — set via the "Eff" chip beside the transcript title,
    // entered on a docked numeric keypad. Like the card groups it is hand metadata, not part of the
    // action log: untouched by Undo, fixed only in the keypad, cleared on New Hand. nil = unset.
    @State private var effectiveStack: Int? = nil
    @State private var effEntryVisible: Bool = false   // keypad shown as a bottom overlay over the dock (like the transcript drawer)
    @State private var effDraft: String = ""           // digits being typed (≤3); committed to effectiveStack on ✓
    @State private var effReplaceOnInput: Bool = false // re-opened a set value → the next digit clears it and starts fresh

    @State private var phase: Phase = .selectSeat

    enum Phase { case selectSeat, placingButton, recordingHand, showdown, handClosed }

    init(session: Session, onBack: @escaping () -> Void) {
        self.session = session
        self.onBack = onBack
        _tableSize = State(initialValue: session.tableSize)
    }

    // MARK: - Computed Properties

    private var openBetExists: Bool { betLevelThisStreet > 0 }

    /// The seats that actually have a player this hand (all seats minus the empty ones), ascending.
    /// Drives position labels and the active-seat sequence so an N-seat table with K empties plays
    /// exactly like an (N−K)-handed game. Stable across folds (folding doesn't change occupancy).
    private var occupiedSeats: [Int] {
        Array(0..<tableSize).filter { !emptySeats.contains($0) }
    }

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
        case .recordingHand where isRunOut:
            return "ALL IN"                 // run-out — board is dealt out, no more betting
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
        case .placingButton: return seatEditMode ? "TAP SEATS\nTO EMPTY" : "PLACE\nTHE BUTTON"
        // handClosed shows only the outcome (feltActionText) over the frozen table — the
        // "place the button" instruction now belongs to the post–New-Hand placingButton screen.
        default:             return nil
        }
    }

    private var seatPositions: [Int: String] {
        guard let btn = buttonSeat else { return [:] }
        return calculatePositions(
            buttonSeatIndex: btn,
            activeSeatIndices: occupiedSeats
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

    /// Button label: "End Hand" when committing a fold-out, "Showdown" in a run-out (it jumps
    /// straight to the result — no street-by-street walk), otherwise the next street.
    private var nextStreetLabel: String {
        if pendingFoldOut { return "End Hand" }
        if isRunOut { return "Showdown" }
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
            sizingRowVisible = false
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
                    // The table stays FROZEN on the finished hand at close — seat actions, positions,
                    // and the dealer button all remain on screen so the just-played hand reads clearly
                    // (e.g. the river action stays visible). New Hand is what clears it. (placingButton
                    // has no buttonSeat yet, so the puck naturally hides there.)
                    buttonSeat: buttonSeat,
                    seatStates: seatActions,
                    // On a decisive close the ring drops entirely (Option A) — the pulse hands off to
                    // the Next Street button. The data pointer (`highlightedSeat`) stays intact for
                    // tap/rewind logic; only the *visual* highlight is suppressed here. A run-out also
                    // drops the ring — no one can act while the board is dealt out.
                    activeSeat: (streetClosedDecisively || isRunOut) ? nil : highlightedSeat,
                    positions: seatPositions,
                    emptySeats: emptySeats,
                    onSeatTap: handleSeatTap,
                    onSeatSwipe: handleSeatSwipe,
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
                    // Upper-left corner: Skip (end this hand) while recording; Edit-Seats / Done at
                    // place-button (mark empty seats before the hand starts).
                    if phase == .recordingHand || phase == .showdown {
                        tableActionButton("arrow.forward", "Skip", tint: Color.foldRed) { skipHand() }
                            .padding(.leading, 14)
                            .padding(.top, 10)
                    } else if phase == .placingButton {
                        if seatEditMode {
                            tableActionButton("checkmark", "Done", tint: Color.gold) {
                                withAnimation(.easeInOut(duration: 0.2)) { seatEditMode = false }
                            }
                            .padding(.leading, 14)
                            .padding(.top, 10)
                        } else {
                            tableActionButton("person.crop.circle.badge.minus", "Edit Seats", tint: Color.textMuted) {
                                withAnimation(.easeInOut(duration: 0.2)) { seatEditMode = true }
                            }
                            .padding(.leading, 14)
                            .padding(.top, 10)
                        }
                    }
                }
                .overlay(alignment: .topTrailing) {
                    // Move is "next hand, new seat" — only at the ended state (handClosed) and the
                    // pre-hand seat-fix state (placingButton, but not while editing seats). Mid-hand
                    // you end via Skip first.
                    if phase == .handClosed || (phase == .placingButton && !seatEditMode) {
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
                            Button(action: { tableSize = size; emptySeats = [] }) {
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
                    // ── Bottom assembly: card strip + fixed-height control region, with the transcript
                    // as a single height-animated overlay over this section only (never the table above
                    // the divider). Collapsed, the panel rests in the tail slot under the control bar;
                    // expanded, its height grows to cover the whole section — the same animation run
                    // forward and backward, so expand and collapse are symmetric. `.clipped()` keeps it
                    // from ever drawing past the section (e.g. beneath the tab bar). The control bar's
                    // height varies (two rows recording, one closed), so both the section height and the
                    // collapsed-slot height are measured rather than hardcoded. See DisplayLayoutPlan.md
                    // §"Layout model" and §#4.
                    ZStack(alignment: .bottom) {
                        VStack(spacing: 0) {
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
                                            // The acting seat's own context (matches cycleSeat/swipe/
                                            // hold logic), NOT the global bet level. A seat that has
                                            // opened the betting still reads "no bet faced" — so its
                                            // Check/Bet row never flips to Fold/Call/Raise mid-action.
                                            facesBet: highlightedSeat.map(seatFacesBet) ?? false,
                                            highlightedSeat: highlightedSeat,
                                            rewindEnabled: rewindButtonEnabled,
                                            nextStreetEnabled: nextStreetButtonEnabled,
                                            nextStreetPulsing: streetClosedDecisively || isRunOut,
                                            nextStreetLabel: nextStreetLabel,
                                            sizingActive: sizingRowVisible,
                                            sizingChips: sizingChips,
                                            sizingSelectedType: sizingSelectedType,
                                            isRunOut: isRunOut,
                                            showNewHand: phase == .handClosed,
                                            onAction: { commitAction($0) },
                                            onRewind: { withAnimation(.easeInOut(duration: 0.15)) { undoLastAction() } },
                                            onNextStreet: handleNextStreet,
                                            onAggressiveHold: handleAggressiveHold,
                                            onCallHold: handleCallHold,
                                            onSizingChip: handleSizingChip,
                                            onNewHand: startNewHand
                                        )
                                        // Greedy filler: takes all space below the control bar (it grows
                                        // when the action row is absent — place-button / hand-closed),
                                        // reports that height so the transcript overlay matches it
                                        // exactly, and is surface-colored so any 1-frame measurement
                                        // mismatch shows surface, never the black background.
                                        Color.surface
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                            .background(GeometryReader { g in
                                                Color.clear.preference(key: TranscriptSlotHeightKey.self,
                                                                       value: g.size.height)
                                            })
                                    }
                                }
                            }
                            .frame(height: controlRegionHeight)
                        }
                        .background(GeometryReader { g in
                            Color.clear.preference(key: BottomSectionHeightKey.self, value: g.size.height)
                        })

                        // Single transcript panel — one view, height-animated between the collapsed slot
                        // and the full section, so expand/collapse are symmetric. Hidden while the card
                        // picker owns the region (the two never co-exist).
                        if entryStreet == nil {
                            transcriptPanel(expanded: transcriptExpanded)
                                .frame(height: transcriptExpanded ? bottomSectionHeight : collapsedTranscriptHeight)
                                .clipped()
                                .transition(.opacity)
                        }

                        // Eff-stack keypad — slides up over the bottom section only (cards + control
                        // region), so it has room for full-size keys and the table above never shifts.
                        // Tapping the table / strip behind it still works.
                        if effEntryVisible {
                            effStackPanel
                                .transition(.move(edge: .bottom))
                        }
                    }
                    .clipped()
                    .onPreferenceChange(BottomSectionHeightKey.self) { if $0 > 0 { bottomSectionHeight = $0 } }
                    .onPreferenceChange(TranscriptSlotHeightKey.self) { if $0 > 0 { collapsedTranscriptHeight = $0 } }
                } else {
                    Spacer(minLength: 0)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: entryStreet != nil)
        .animation(.easeInOut(duration: 0.2), value: effEntryVisible)
        .animation(.easeInOut(duration: 0.2), value: phase)
    }

    // MARK: - Seat Tap Handler

    private func handleSeatTap(_ seat: Int) {
        // Any seat interaction dismisses a pending sizing row (the staged raise/bet stays in the log).
        if sizingRowVisible { withAnimation(.easeInOut(duration: 0.15)) { sizingRowVisible = false } }
        switch phase {
        case .selectSeat:
            heroSeat = seat
            emptySeats.remove(seat)        // you can't take an empty seat — sitting there fills it
            phase = .placingButton

        case .placingButton:
            // In Edit-Seats mode a tap toggles the seat empty/occupied; otherwise it places the
            // button (never on an empty seat) and starts the hand over the occupied seats only.
            if seatEditMode {
                toggleEmptySeat(seat)
                return
            }
            guard !emptySeats.contains(seat) else { return }
            buttonSeat = seat
            activeSeatSequence = occupiedSeats
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
            // The table is frozen on the finished hand — tapping a seat does nothing. The explicit
            // New Hand button (in the Control Bar) is the only way forward.
            break
        }
    }

    /// Toggle a seat empty/occupied in Edit-Seats mode. The hero's seat can never be emptied, and we
    /// keep at least two occupied seats (a hand needs heads-up minimum). Restoring an empty seat is
    /// the same tap. `emptySeats` is table composition and persists across hands.
    private func toggleEmptySeat(_ seat: Int) {
        guard seat != heroSeat else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            if emptySeats.contains(seat) {
                emptySeats.remove(seat)
            } else if occupiedSeats.count > 2 {
                emptySeats.insert(seat)
            }
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
        // All-in seats have no chips and can't act — tapping one is a no-op.
        if allInSeats.contains(seat) { return }
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
        if let from = highlightedSeat, activeSeatSequence.contains(from), !hasActed(from), !allInSeats.contains(from) {
            skipped.append(from)
        }
        skipped += seatsStrictlyBetween(from: highlightedSeat ?? seat, to: seat, in: activeSeatSequence)
            .filter { !hasActed($0) && !allInSeats.contains($0) }

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
        // All-in seats have no chips and can't act — tapping one is a no-op.
        if allInSeats.contains(seat) { return }
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
        if sizingRowVisible { sizingRowVisible = false }   // a decisive swipe dismisses the sizing row
        routeDecisive(action, to: seat)
    }

    /// Shared decisive routing for swipes — mirrors the tap routing but always lands a specific
    /// action and advances. Swipes are always unsized (sizing lives on the Raise/Bet button hold).
    private func routeDecisive(_ action: ActionType, to seat: Int) {
        withAnimation(.easeInOut(duration: 0.15)) {
            // On-clock seat → record + move to the next player. Routed through finishSwipe (not
            // commitAction) so a swipe never auto-advances the street — only the Next Street button does.
            if seat == highlightedSeat {
                // A decisive gesture SETS this seat's current decision. If the seat already has a
                // standing turn-action (e.g. it was cycled to Call), supersede it rather than stack a
                // second action. owesAction == true means it owes a fresh response (never acted, or
                // facing new aggression) — that's a genuinely separate action, so don't remove it.
                if hasActed(seat) && !owesAction(seat) { removeLastAction(of: seat) }
                finishSwipe(on: seat, action: action)
                return
            }
            // Dead seats (folded / not in hand).
            guard activeSeatSequence.contains(seat) else { return }
            // All-in seats have no chips and can't act.
            if allInSeats.contains(seat) { return }
            // Resolved: acted and owes nothing.
            if hasActed(seat) && !owesAction(seat) { return }
            // Re-aggression: the on-clock seat must respond before any other seat is actionable.
            if let hs = highlightedSeat, hasActed(hs) && owesAction(hs) { return }

            if currentStreet != .preflop && openBetExists {
                // Bet context: strict — only the exact next owing seat, no skip-jumping into a bet.
                guard seat == nextOwingSeat(after: highlightedSeat ?? seat) else { return }
                commitSwipeStrict(to: seat, action: action)
            } else {
                // Navigation context: cannot skip an already-acted seat.
                let between = seatsStrictlyBetween(from: highlightedSeat ?? seat, to: seat, in: activeSeatSequence)
                if between.contains(where: { hasActed($0) }) { return }
                commitSwipeJump(to: seat, action: action)
            }
        }
    }

    /// Navigation-context swipe: auto-resolve skipped seats, then land `action` on the destination.
    private func commitSwipeJump(to seat: Int, action: ActionType) {
        if autoResolveSkipped(to: seat) { return }   // fold-out already ended the hand
        finishSwipe(on: seat, action: action)
    }

    /// Strict bet-context swipe (the seat IS the next owing seat): commit the on-clock seat's
    /// default response first, then land `action` on the destination.
    private func commitSwipeStrict(to seat: Int, action: ActionType) {
        if let cur = highlightedSeat, owesAction(cur) {
            recordAction(seatFacesBet(cur) ? .call : .check, for: cur)
        }
        finishSwipe(on: seat, action: action)
    }

    /// Shared tail for swipes: record the action on `seat`, then settle (see `settleAfterCommit`).
    /// A swipe picks the action directly instead of cycling to it, then advances the ring to the
    /// next player WITHOUT seeding any action there — identical to an action-button press.
    private func finishSwipe(on seat: Int, action: ActionType) {
        recordAction(action, for: seat)
        settleAfterCommit(on: seat, justFolded: action == .fold)
    }

    // MARK: - Action-button hold-to-size

    /// The aggressive action for the seat on the clock: a raise in a bet context (preflop, or any
    /// street facing a wager), an open (first bet) in a no-bet post-flop context.
    private var aggressiveActionType: ActionType {
        guard let seat = highlightedSeat else { return .raise }
        let betContext = currentStreet == .preflop || seatFacesBet(seat)
        return betContext ? .raise : .open
    }

    /// The action type the sizing row is currently sizing (the held seat's last logged action), or
    /// nil when no row is up. Drives which action button renders "selected" — Raise/Bet for a wager,
    /// Call for a call-all-in.
    private var sizingSelectedType: ActionType? {
        guard sizingRowVisible, let seat = highlightedSeat else { return nil }
        return actionsThisStreet.last(where: { $0.seatIndex == seat })?.actionType
    }

    /// The sizing chip strip for the currently-staged action: multiples for a raise, pot fractions
    /// for an opening bet, and the single "All-in" chip for a call (the call-all-in marker). Derived
    /// from the last logged action so it stays correct after the hold records.
    private var sizingChips: [String] {
        switch sizingSelectedType {
        case .open: return Self.betStrip
        case .call: return ["All-in"]
        default:    return Self.multipleStrip   // .raise (or fallback)
        }
    }

    /// A 0.3s hold on the Raise/Bet button: record the aggressive action UNSIZED right now (identical
    /// to cycling, which also writes immediately), then reveal the sizing row. Because the action is a
    /// real log entry, Undo needs no special case — it peels the raise/bet like any other action; we
    /// only also hide the row. The ring is NOT advanced — the seat stays on the clock until a chip is
    /// tapped (or the row is dismissed by another input).
    private func handleAggressiveHold() {
        guard phase == .recordingHand, let seat = highlightedSeat else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            if hasActed(seat) && !owesAction(seat) { removeLastAction(of: seat) }
            recordAction(aggressiveActionType, for: seat)
            sizingRowVisible = true
        }
    }

    /// A 0.3s hold on the Call button: record an (unsized) call now and reveal a single "All-in"
    /// chip, so the user can flag that this call put the player all-in. Mirrors the aggressive hold;
    /// tapping the chip routes through `handleSizingChip` (re-records the call with the All-in
    /// marker). Only meaningful when facing a wager — a limp can't be all-in.
    private func handleCallHold() {
        guard phase == .recordingHand, let seat = highlightedSeat, seatFacesBet(seat) else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            if hasActed(seat) && !owesAction(seat) { removeLastAction(of: seat) }
            recordAction(.call, for: seat)
            sizingRowVisible = true
        }
    }

    /// A sizing chip tapped: replace the staged unsized raise/bet with a sized one (same action type,
    /// read back from the log), then settle exactly like a committed input (advance the ring, light
    /// Next Street on a close). Dismisses the sizing row.
    private func handleSizingChip(_ label: String) {
        guard phase == .recordingHand, let seat = highlightedSeat,
              let type = actionsThisStreet.last(where: { $0.seatIndex == seat })?.actionType
        else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            removeLastAction(of: seat)
            recordAction(type, for: seat, sizing: makeSizing(label))
            sizingRowVisible = false
            settleAfterCommit(on: seat, justFolded: false)
        }
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

    /// Curated raise multiples then All-in — preflop opens, re-raises, post-flop raises.
    private static let multipleStrip: [String] = [
        "2x", "2.2x", "2.5x", "2.8x", "3x", "3.2x", "3.5x", "4x", "5x", "All-in"
    ]

    /// Curated pot fractions, Pot, a few overbets (as % of pot), then All-in — post-flop opening bet.
    private static let betStrip: [String] = [
        "10%", "25%", "33%", "50%", "67%", "75%", "90%",
        "Pot",
        "110%", "120%", "150%", "200%",
        "All-in"
    ]

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
            // A quick tap on Raise/Bet while the sizing row is up means "commit unsized" — supersede
            // the staged action and advance. The flag clears here so the row dismisses with it.
            sizingRowVisible = false
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
        return ring.dropFirst().first { playersWithChips.contains($0) }   // skip all-in seats
    }

    private func triggerFoldOut() {
        if let winner = activeSeatSequence.first {
            handCloseSummary = (winner == heroSeat) ? "You win" : "Seat \(winner + 1) wins"
        }
        saveCurrentHand(outcome: nil)
        phase = .handClosed
        highlightedSeat = nil
    }

    /// Whether the hero is still contesting the hand (not folded).
    private var heroInHand: Bool { activeSeatSequence.contains(heroSeat ?? -1) }

    /// The hand reached a showdown (2+ players contested the end). If hero is among them, surface the
    /// Win/Lose/Chop overlay to record the result. If hero already folded, there's no hero outcome to
    /// pick — close the hand directly with no overlay; the still-in villains' cards stay enterable in
    /// the showdown row.
    private func reachShowdown() {
        if heroInHand {
            phase = .showdown
        } else {
            handCloseSummary = "Showdown"
            saveCurrentHand(outcome: nil)
            phase = .handClosed
            highlightedSeat = nil
        }
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
        // The street whose actions the table renders. Normally the live street (`actionsThisStreet`).
        // But a run-out fast-forwards `currentStreet` to the river and empties `actionsThisStreet`
        // (advanceStreetOrShowdown → closeStreet), burying the last contested street's actions in
        // `streets` — so a non-all-in caller would render actionless at the frozen table. At a closed
        // hand we therefore fall back to the last street that actually had action, matching the
        // transcript. The fallback is gated on a terminal phase: an empty live street is also the
        // normal state right after a street advances, and there we must keep it empty (a fresh street).
        // This is recording-only — Replay passes the explicit per-street slice.
        let displayStreetActions: [Action] = {
            if !actionsThisStreet.isEmpty { return actionsThisStreet }
            if phase == .showdown || phase == .handClosed {
                return streets.last(where: { !$0.actions.isEmpty })?.actions ?? []
            }
            return actionsThisStreet   // empty + recording → genuinely fresh street, keep it empty
        }()

        return seatStates(
            streetActions: displayStreetActions,
            foldedBefore:  foldedSeats,
            allIn:         allInSeats,
            allActions:    streets.flatMap { $0.actions } + actionsThisStreet,
            highlighted:   highlightedSeat,
            owes:          owesAction
        )
    }

    // MARK: - Undo

    /// Undoes the most recent action, peeling back across street boundaries when the current
    /// street has no actions yet. The highlight lands on the new most-recent actor so it can be
    /// re-cycled, or on the street's opener (first to act) when nothing remains — so undoing a
    /// jump returns to "first to act", not the seat that was tapped. Card slots are left
    /// untouched — rewind only affects recorded action.
    private func undoLastAction() {
        // Dismiss a pending sizing row. The staged raise/bet is a normal log entry, so we do NOT
        // return here — flow continues to the peel path below and removes it, returning the seat to
        // its previous state. One press both hides the row and undoes the raise (see SizingOverhaul.md).
        sizingRowVisible = false

        // A finished hand is reversible. Un-close it first, discriminating by the saved hand's
        // outcome (showdown saves a non-nil outcome; a fold-out saves nil; a skip sets the flag).
        // We read the saved snapshot from the store rather than removing it — the persisted copy stays
        // put (overwritten on re-close), so an Undo-then-quit keeps the last-closed hand. The live
        // `@State` below is what reopens for editing.
        if phase == .handClosed {
            let closed = store.hand(id: currentHandID)
            handCloseSummary = ""
            if lastHandWasSkipped {
                // Skip undo: all hand state is still live (skipHand never called resetHandState) and
                // the number was never advanced (New Hand does that). Just clear the flag and reopen
                // recording at the last action. Do NOT fall through to the peel path — there is no
                // erroneous action to remove.
                lastHandWasSkipped = false
                phase = .recordingHand
                highlightedSeat = actionsThisStreet.last?.seatIndex ?? firstActor(of: currentStreet)
                return
            }
            if closed?.outcome != nil {
                phase = .showdown        // re-open the Win/Lose/Chop overlay to re-pick — no peel
                highlightedSeat = nil
                return
            }
            // Hero-folded villain showdown: closed with no Win/Lose/Chop, and the action log is intact
            // (the close was the Showdown button, not an erroneous fold). Reopen recording at the last
            // actor — no peel. A genuine fold-out leaves exactly one seat and falls through to the peel.
            if (closed?.showdownSeatIndices.count ?? 0) >= 2 {
                phase = .recordingHand
                highlightedSeat = actionsThisStreet.last?.seatIndex ?? firstActor(of: currentStreet)
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
        activeSeatSequence = occupiedSeats.filter { !foldedSeats.contains($0) }.sorted()
        betLevelThisStreet = actionsThisStreet.filter {
            $0.actionType == .open || $0.actionType == .raise
        }.count
    }

    // MARK: - All-In State (derived from the log)

    /// Seats that are all-in this hand — any action (any street) carrying the "All-in" size marker.
    /// An all-in is recorded as an `.open`/`.raise`/`.call` whose `sizing.label == "All-in"`, so this
    /// is pure-derived (no stored flag) and tracks Undo automatically. All-in persists across streets.
    private var allInSeats: Set<Int> {
        let allActions = streets.flatMap { $0.actions } + actionsThisStreet
        return Set(allActions.filter { $0.sizing?.label == "All-in" }.map { $0.seatIndex })
    }

    /// Seats still in the hand AND holding chips — the only seats that can still make a betting
    /// decision. Folded seats and all-in seats are both excluded (folds leave the hand; all-ins keep
    /// their seat for showdown but can never act again). This is the acting set for close detection,
    /// the highlight ring, and `owesAction` — the all-in equivalent of "who's left to act."
    private var playersWithChips: [Int] {
        activeSeatSequence.filter { !allInSeats.contains($0) }
    }

    /// True when betting can no longer continue: ≥2 players remain in the hand but ≤1 still has
    /// chips, so the board just runs out to showdown with no further action. Drives run-out mode
    /// (no action buttons, the felt reads ALL IN, Next Street walks the board to showdown).
    ///
    /// Gated on the current betting being SETTLED — if the lone chip-holder still owes a response to
    /// an all-in just made (e.g. they must call or fold the jam), it is NOT yet a run-out: they keep
    /// their action buttons until they respond. Only once that's resolved does the board run out.
    private var isRunOut: Bool {
        guard phase == .recordingHand, activeSeatSequence.count >= 2, playersWithChips.count <= 1 else {
            return false
        }
        if let lone = playersWithChips.first, facesUnansweredBet(lone) { return false }
        return true
    }

    /// True when `seat` still owes a response to an unanswered bet/raise made by ANOTHER seat this
    /// street (so it must act before the street can close). Distinct from `owesAction`: a fresh
    /// run-out street where the lone chip-holder simply hasn't acted does NOT face a bet, so the
    /// board can be run out without forcing a pointless check.
    private func facesUnansweredBet(_ seat: Int) -> Bool {
        guard let lastAggIdx = actionsThisStreet.lastIndex(where: {
            ($0.actionType == .open || $0.actionType == .raise) && $0.seatIndex != seat
        }) else { return false }
        if let mineIdx = actionsThisStreet.lastIndex(where: { $0.seatIndex == seat }) {
            return mineIdx < lastAggIdx   // their last action predates the aggression → still owe
        }
        return true                       // never acted but a bet stands → facing it
    }

    // MARK: - Street Close Detection

    /// Pure predicate — has the current betting round completed? Does NOT mutate state.
    /// Preflop: BB is the last voluntary actor. In an unraised (limped) pot the street
    /// closes once BB has acted; in a raised pot every active seat except the last
    /// aggressor must have called or folded after that aggressor's raise (BB included,
    /// since BB is active and acts last).
    private func streetIsClosed() -> Bool {
        // One player left in the hand is a fold-out, handled separately — not a street close.
        if activeSeatSequence.count <= 1 { return false }

        // The acting set is players who still have chips (folded + all-in both excluded). All-in
        // seats can't respond, so they never hold a street open.
        let activePlayers = playersWithChips

        // At most one chip-holder → no betting contest is possible. The street is closed UNLESS that
        // lone player still owes a response to an all-in made this street (they must call/fold it
        // first). Zero chip-holders (everyone all-in) is always closed → straight to the run-out.
        if activePlayers.count <= 1 {
            if let lone = activePlayers.first, facesUnansweredBet(lone) { return false }
            return true
        }

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
        // Run-out: betting is settled and ≤1 player has chips, so there are no more decisions — the
        // board just gets dealt out. Skip the street-by-street walk and jump straight to the showdown
        // overlay in one move (closing each remaining street so the transcript renders the full board
        // — it shows streets up to `currentStreet`). The run-out board is entered in the always-live
        // card strip, before or after picking the result. This is the same showdown the river reaches.
        if isRunOut {
            while currentStreet != .river { closeStreet() }
            if activeSeatSequence.count >= 2 { reachShowdown() }
            return
        }
        if currentStreet == .river {
            if activeSeatSequence.count >= 2 {
                reachShowdown()
            }
        } else {
            closeStreet()
        }
    }

    // Returns the BB's seat index over the occupied seats (position-stable across folds, and empty
    // seats are excluded so BB lands on a real player).
    private func bbSeat() -> Int? {
        guard let btn = buttonSeat else { return nil }
        let positions = calculatePositions(
            buttonSeatIndex: btn,
            activeSeatIndices: occupiedSeats
        )
        return positions.first(where: { $0.value == "BB" })?.key
    }

    // MARK: - Street Management

    /// First chip-holding seat clockwise from the button — the opener of the next post-flop street.
    /// Skips all-in seats (they can't open) as well as folded seats.
    private func firstActorAfterClose() -> Int? {
        let btn = buttonSeat ?? 0
        let all = Array(0..<tableSize)
        let btnIdx = all.firstIndex(of: btn) ?? 0
        let rotated = Array(all[(btnIdx + 1)...]) + Array(all[...btnIdx])
        return rotated.first { playersWithChips.contains($0) }
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
        streets.append(Street(name: currentStreet, actions: actionsThisStreet))
        actionsThisStreet = []
        if let next = currentStreet.next() {
            currentStreet = next
            // Run-out (≤1 chip-holder): no one acts this street — drop the ring entirely; the user
            // just enters board cards and taps through to showdown. Otherwise open on the first
            // chip-holder left of the button.
            highlightedSeat = isRunOut ? nil : firstActorAfterClose()
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
        guard playersWithChips.contains(seat) else { return false }   // folded or all-in → never owes
        guard let lastIdx = actionsThisStreet.lastIndex(where: { $0.seatIndex == seat }) else {
            return true   // has chips and yet to act this street
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
        // Use the occupied-seat ring so positions are stable across folds (occupancy doesn't change
        // when a player folds) while excluding empty seats. Using activeSeatSequence here would
        // exclude a folded BTN, causing calculatePositions to return [:] and every post-flop
        // position to render as "?".
        return calculatePositions(
            buttonSeatIndex: btn,
            activeSeatIndices: occupiedSeats
        )[seat] ?? "?"
    }

    /// Cards are entered *after* the hand is saved at close (villain showdown cards, a hero hole fix, a
    /// board correction), so re-sync the canonical groups onto the stored Hand whenever a card group is
    /// dismissed while closed — keeping the saved record faithful. Writes hole, villain, AND board
    /// groups; the flat `holeCards`/`villainCards`/`board` on `Hand` are computed from these, so there
    /// is nothing else to collapse. A board group is stored only once it has a rank (else nil).
    private func syncClosedHandCards() {
        guard phase == .handClosed else { return }
        // Rebuild from live state and upsert — `buildHand` already reads the current card groups, so a
        // post-close edit is just another save of the same `currentHandID` (no field-by-field patch).
        store.saveHand(buildHand(outcome: currentOutcome), in: session.id)
    }

    // MARK: - Card Strip

    /// Villains still in the hand at the end (hero excluded) — the seats offered a card group in the
    /// showdown row. `activeSeatSequence` holds exactly the not-folded seats and stays intact through
    /// showdown/close.
    private var showdownVillains: [Int] {
        activeSeatSequence.filter { $0 != heroSeat }
    }

    /// The showdown villain row shows only when 2+ seats contested the end: live at the showdown
    /// overlay, and after close whenever the hand reached a showdown — a hero showdown *or* a
    /// hero-folded villain showdown (both leave ≥2 in `activeSeatSequence`). A fold-out / skip leaves
    /// one seat, so nothing shows — there's no one to reveal.
    private var showdownVillainsVisible: Bool {
        guard !showdownVillains.isEmpty else { return false }
        if phase == .showdown { return true }
        if phase == .handClosed { return activeSeatSequence.count >= 2 }
        return false
    }

    private var cardStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    // Hero hole + board — spread edge-to-edge across one screen width, exactly as before
                    // (when there are no villains the content fits the viewport and never scrolls).
                    HStack(alignment: .top, spacing: 0) {
                        groupSection(label: "HOLE",  target: .street(.hole),  isActive: entryTarget == .street(.hole))
                        Spacer()
                        groupSection(label: "FLOP",  target: .street(.flop),  isActive: entryTarget == .street(.flop))
                        Spacer()
                        groupSection(label: "TURN",  target: .street(.turn),  isActive: entryTarget == .street(.turn))
                        Spacer()
                        groupSection(label: "RIVER", target: .street(.river), isActive: entryTarget == .street(.river))
                    }
                    .frame(width: UIScreen.main.bounds.width - 24)
                    .id("heroStrip")

                    // Showdown only: the still-in villains, appended to the right and scrollable into view.
                    if showdownVillainsVisible {
                        ForEach(showdownVillains, id: \.self) { seat in
                            groupSection(label: positionFor(seat: seat),
                                         target: .villain(seat),
                                         isActive: entryTarget == .villain(seat))
                                .id("villain-\(seat)")
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            .scrollDisabled(!showdownVillainsVisible)
            // Peek-nudge: when the villain row appears, reveal the first villain, then settle back to the
            // hero strip — a one-time cue that there's something to add off to the right.
            .onChange(of: showdownVillainsVisible) { _, visible in
                guard visible, let first = showdownVillains.first else { return }
                withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo("villain-\(first)", anchor: .trailing) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo("heroStrip", anchor: .leading) }
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: currentStreet)
    }

    /// When a footnote group is full and every entered letter is the SAME real suit (s/h/d/c — never
    /// `x`), every card is unambiguously that suit. Returns the suit symbol to color the faces with;
    /// nil otherwise (partial, mixed, or contains an explicit unknown). Display-only — see groupSection.
    /// The group's label row. Hole carries the incognito eye toggle (session-wide) right beside it —
    /// the one place to flip hole-card privacy on/off; other streets are just the label.
    @ViewBuilder
    private func groupLabel(_ label: String, target: CardTarget, isActive: Bool) -> some View {
        let title = Text(label)
            .font(.system(size: 9, weight: .bold))
            .tracking(1.5)
            .foregroundStyle(isActive ? Color.gold : Color.textMuted)
        if target == .street(.hole) {
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

    /// True when the hand reached this card street, so its cards were actually dealt. Hole is always
    /// reached; a board street is reached once `currentStreet` is at or past it. (A run-out forces
    /// `currentStreet` to river, so the full board counts.)
    private func streetWasReached(_ street: CardStreet) -> Bool {
        switch street {
        case .hole:  return true
        case .flop:  return currentStreet == .flop || currentStreet == .turn || currentStreet == .river
        case .turn:  return currentStreet == .turn || currentStreet == .river
        case .river: return currentStreet == .river
        }
    }

    /// At showdown / a closed hand, empty slots for streets the hand reached get a gold "enter these
    /// now" border — a nudge to fill the board/hole cards while looking at the result. Unreached
    /// streets (e.g. the river after a flop fold-out) stay plain, though they remain enterable.
    private func promptCardEntry(for street: CardStreet) -> Bool {
        (phase == .showdown || phase == .handClosed) && streetWasReached(street)
    }

    /// Gold "enter now" cue for any entry target. Hero streets reuse the per-street rule; a villain's
    /// empty slots are cued whenever the showdown villain row is showing (they reached showdown).
    private func promptCardEntry(for target: CardTarget) -> Bool {
        switch target {
        case .street(let s): return promptCardEntry(for: s)
        case .villain:       return showdownVillainsVisible
        }
    }

    /// A street group: rank-forward card faces, with a caption hanging beneath the group. The caption
    /// encodes the unassigned suit info — footnote letters (`dx`, `hhx`) or a relationship word
    /// (`suited`, `two tone`). Bound mode shows its suits ON the faces and has no caption. The caption
    /// row reserves a fixed height so the faces stay baseline-aligned across all four groups.
    @ViewBuilder
    private func groupSection(label: String, target: CardTarget, isActive: Bool) -> some View {
        let g = group(for: target)
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
        // Villain "enter now" cues are red to distinguish them from the hero's gold board/hole cues.
        let cueColor: Color = { if case .villain = target { return .foldRed } else { return .gold } }()
        let faceDown = incognito && target == .street(.hole)   // incognito hides only the hero's hole faces
        // In incognito the hole's caption is the single read-out (the pill is omitted, below). The caption
        // blurs whenever the hole bank isn't selected, and clears again when you re-select your cards.
        let hideReadouts = faceDown && entryTarget != .street(.hole)
        VStack(spacing: 6) {
            groupLabel(label, target: target, isActive: isActive)

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
                        isActive: entryTarget == target && focusIndex == i,
                        promptEmpty: promptCardEntry(for: target),
                        promptColor: cueColor
                    )
                    .onTapGesture { openCardEntry(target) }
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
                    CardTextureBadge(glyphSet: glyphSet, relWord: relWord)
                        .offset(y: 9)   // straddle the bottom edge (tuning dial with the caption padding below)
                }
            }

            // Caption: the group's full shorthand in plain Courier text, shown as soon as ANY rank is
            // entered (groupNotation renders ranks-only too — "5", "55" — then fills in suits). The line
            // is ALWAYS rendered (a blank space when empty) so the strip keeps a constant height — the
            // picker never slides as you type.
            // Incognito: the hole caption is readable while the hole bank is selected (you tapped your
            // cards), and blurs whenever it isn't — so "peek" is just re-selecting hole. Board never hides.
            let notation = groupNotation(g)
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


    // MARK: - Card Picker Panel

    // Mutually-exclusive gating. Suits (♠♥♦♣ x) are live once a rank exists, UNLESS the group is
    // committed to a relationship. Relationship shortcuts (s/o, r/m/tt) are live only when all ranks
    // are in AND no specific suit has been committed (mode none or relationship) — and never for a
    // hole pair (no 88s; 88o is assumed, never written). So at "both ranks, nothing chosen" both sets
    // are live; the first suit turns s/o off, the first s/o turns suits off.
    private var entryGroup: CardGroup? { entryTarget.map { group(for: $0) } }
    private func setEntryGroup(_ g: CardGroup) { if let t = entryTarget { setGroup(t, g) } }

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

    /// Every *known dead card* already in this hand, across all groups, keyed `"Qh"` — excluding one
    /// frame (the cursor, so re-binding its own card never blocks itself). The dead-card logic is the
    /// pure `deadCardKeys(in:)`; here we just gather the live groups and blank the cursor frame's bound
    /// suit before delegating. (Footnote letters aren't frame-tied, so a pair's footnote stays in —
    /// catching a repeated suit within the pair.)
    private func usedCardKeys(excluding exclude: CardTarget?, index: Int?) -> Set<String> {
        var groups: [(CardTarget, CardGroup)] = [
            (.street(.hole), holeGroup), (.street(.flop), flopGroup),
            (.street(.turn), turnGroup), (.street(.river), riverGroup)
        ]
        for (seat, g) in villainGroups { groups.append((.villain(seat), g)) }
        if let exclude, let index,
           let gi = groups.firstIndex(where: { $0.0 == exclude }), index < groups[gi].1.frames.count {
            groups[gi].1.frames[index].suit = .unspecified
        }
        return deadCardKeys(in: groups.map(\.1))
    }

    /// True when choosing `suit` would re-create a card already known to be in the hand — so the suit
    /// button is disabled. Spans hero, board, and villain groups. Fires on two paths:
    /// - **bound**: the suit binds to the cursor frame, pinning `cursorRank + suit`;
    /// - **footnote on a pair/trips**: every rank-bearing frame shares one rank, so the suit pins
    ///   `pairRank + suit` even unassigned — this blocks a repeat within the pair (`QQc` → 2nd ♣) and a
    ///   suit already dead elsewhere. A mixed-rank footnote (`QJ`) is ambiguous and never blocks.
    private func suitIsDuplicate(_ suit: String) -> Bool {
        guard let g = entryGroup else { return false }
        let willBind = g.mode == .bound || (g.mode == .none && (g.capacity == 1 || g.firstEmptyIndex != nil))
        let rank: Rank?
        if willBind {
            rank = (focusIndex < g.frames.count) ? g.frames[focusIndex].rank : nil
        } else {
            let ranks = Set(g.frames.compactMap { $0.rank })
            rank = ranks.count == 1 ? ranks.first : nil   // footnote is concrete only on a single rank
        }
        guard let r = rank else { return false }
        // index: focusIndex excludes only a bound cursor frame; the current group's footnote letters
        // stay in the set, so a repeated suit within a pair is caught.
        return usedCardKeys(excluding: entryTarget, index: focusIndex).contains(r.rawValue + suitLetter(suit))
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

    /// The dismiss affordance: a gold down-chevron at the top of the picker — the same idiom the
    /// transcript header uses, so "tap the chevron to collapse this dock" reads the same everywhere.
    /// Tap or swipe down to close (reveals the transcript) — the "no more cards / stop here" action,
    /// on any bank. The bare glyph is small; a reserved 44pt tap target keeps it thumb-friendly, and
    /// it won't read as the gold Next *tile* (that one is filled).
    private var grabHandle: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Color.gold)
            .frame(width: 44, height: 24)
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
        // Done (✓) on the last bank — the river, or any villain group (a single hole bank).
        let isLastBank: Bool = {
            if case .villain = entryTarget { return true }
            return entryStreet == .river
        }()
        return Button(action: advanceOrFinishEntry) {
            Image(systemName: isLastBank ? "checkmark" : "chevron.right")
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

    // MARK: - Bottom Transcript (one height-animated panel: tail ↔ full hand)

    /// Toggle the transcript between its collapsed tail and the full-hand view. Driving the panel's
    /// frame height inside one `withAnimation` is what makes expand and collapse the same animation
    /// run forward and backward (it replaced a slide-in drawer whose collapse looked unseamless).
    private func toggleTranscript() {
        withAnimation(.easeInOut(duration: 0.25)) { transcriptExpanded.toggle() }
    }

    /// The transcript panel — one view used both collapsed and expanded. Mounted as a bottom-anchored
    /// overlay in the bottom section, its height animates between the collapsed tail slot (under the
    /// control bar) and the full section; the content is identical in both states (same header, font,
    /// padding) so nothing reflows — only how many lines are visible changes. `expanded` flips only
    /// cosmetics: the chevron direction. Hidden while the card picker owns the region. See
    /// DisplayLayoutPlan.md §#4.
    private func transcriptPanel(expanded: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("HAND HISTORY")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(Color.gold)
                effChip
                Spacer()
                Button(action: copyShorthand) {
                    HStack(spacing: 4) {
                        Image(systemName: transcriptCopied ? "checkmark" : "doc.on.doc").font(.system(size: 11))
                        Text(transcriptCopied ? "Copied" : "Copy").font(.custom("Arial", size: 11))
                    }
                    .foregroundStyle(transcriptCopied ? Color.winGreen : Color.gold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .overlay(Capsule().stroke(transcriptCopied ? Color.winGreen.opacity(0.4) : Color.clear, lineWidth: 1))
                    .frame(minWidth: 44, minHeight: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(handShorthand.isEmpty)
                .opacity(handShorthand.isEmpty ? 0.35 : 1.0)
                Button(action: toggleTranscript) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.gold)
                        .frame(minWidth: 44, minHeight: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 7)
            .padding(.bottom, 4)

            ScrollViewReader { proxy in
                ScrollView {
                    Text(handShorthand.isEmpty ? "No actions yet — record on the table or fill in cards." : handShorthand)
                        .font(.custom("Courier New", size: 13))
                        .foregroundStyle(handShorthand.isEmpty ? Color.textMuted : Color.textBody)
                        .lineSpacing(3.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    Color.clear.frame(height: 1).id("tailEnd")
                }
                .onChange(of: handShorthand) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("tailEnd", anchor: .bottom) }
                }
                .onChange(of: transcriptExpanded) { _, _ in
                    proxy.scrollTo("tailEnd", anchor: .bottom)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.borderDark.opacity(0.6)).frame(height: 1)
        }
    }

    private func copyShorthand() {
        UIPasteboard.general.string = handShorthand
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.15)) { transcriptCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.15)) { transcriptCopied = false }
        }
    }

    // MARK: - Effective Stack (chip + docked keypad)

    /// The eff-stack chip beside the HAND HISTORY title. Empty → a dashed "+ Eff" (tap to add — the
    /// same plus/empty-slot language as +New Hand and the empty card frames); set → a solid gold
    /// "Nbb". Either way it opens the docked keypad. Available in every playing phase the transcript
    /// header is (recording, showdown, hand-closed) — i.e. whenever the picker/keypad isn't already up.
    private var effChip: some View {
        Button(action: openEffEntry) {
            if let eff = effectiveStack {
                Text("\(eff)bb")
                    .font(.custom("Arial", size: 11))
                    .fontWeight(.bold)
                    .foregroundStyle(Color.goldLight)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color(hex: "#14110A")))
                    .overlay(Capsule().stroke(Color.gold, lineWidth: 1))
            } else {
                Text("+ Eff")
                    .font(.custom("Arial", size: 11))
                    .fontWeight(.bold)
                    .foregroundStyle(Color(hex: "#B5A36A"))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .overlay(Capsule().stroke(Color(hex: "#7A6A3A"),
                                              style: StrokeStyle(lineWidth: 1, dash: [3, 2.5])))
            }
        }
        .buttonStyle(.plain)
    }

    /// Opening the keypad: dismiss the card picker + sizing row (so nothing competes in the dock),
    /// seed the draft from any existing value (so re-tapping edits in place), and show the keypad.
    private func openEffEntry() {
        withAnimation(.easeInOut(duration: 0.2)) {
            entryTarget = nil
            sizingRowVisible = false
            effDraft = effectiveStack.map(String.init) ?? ""
            // A re-opened set value is shown as a preview but is display-only: the first digit clears
            // it and starts a fresh number (same as typing a rank into a full card group). Backspacing
            // instead keeps the value and edits it in place. Nothing to replace when opening empty.
            effReplaceOnInput = !effDraft.isEmpty
            effEntryVisible = true
        }
    }

    private func closeEffEntry() {
        withAnimation(.easeInOut(duration: 0.2)) { effEntryVisible = false }
    }

    /// Commit the draft: an empty draft clears the stack (nil); otherwise set it. Then dismiss.
    private func commitEffEntry() {
        effectiveStack = effDraft.isEmpty ? nil : Int(effDraft)
        closeEffEntry()
    }

    private func effDigit(_ d: String) {
        if effReplaceOnInput { effDraft = ""; effReplaceOnInput = false }   // first digit replaces the re-opened value
        if d == "0" && effDraft.isEmpty { return }   // no leading zero
        guard effDraft.count < 3 else { return }      // capped at 3 digits (≤999bb)
        effDraft.append(d)
    }

    private func effBackspace() {
        effReplaceOnInput = false                     // editing in place now — keep the value, don't replace
        if !effDraft.isEmpty { effDraft.removeLast() }
    }

    /// The docked eff-stack keypad — same grab-handle pattern as the card picker, but presented (in
    /// `body`) as a bottom overlay over the strip + control region (like the transcript drawer), so it
    /// has room for full-size keys and the table above never shifts. Grab handle (tap / swipe down)
    /// cancels without committing; ✓ commits; ⌫ deletes; digits build the draft (live preview above).
    private var effStackPanel: some View {
        VStack(spacing: 0) {
            effGrabHandle

            Spacer(minLength: 8)

            VStack(spacing: 2) {
                Text("EFFECTIVE STACK")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Color.textMuted)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(effDraft.isEmpty ? "—" : effDraft)
                        .font(.custom("Georgia", size: 30))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.goldLight)
                    Text("bb")
                        .font(.custom("Arial", size: 14))
                        .foregroundStyle(Color.textMuted)
                }
            }

            Spacer(minLength: 10)

            VStack(spacing: 8) {
                effRow(["1", "2", "3"])
                effRow(["4", "5", "6"])
                effRow(["7", "8", "9"])
                HStack(spacing: 8) {
                    effActionKey(system: "delete.left", tint: Color.foldRed) { effBackspace() }
                    effDigitKey("0")
                    effActionKey(system: "checkmark", tint: Color.gold, filled: true) { commitEffEntry() }
                }
            }

            Spacer(minLength: 6)
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

    /// Dismiss affordance for the eff keypad — a gold down-chevron, identical to the card picker's
    /// handle so the two docks share one vocabulary. Tap or swipe down to dismiss WITHOUT committing;
    /// the value only changes via ✓.
    private var effGrabHandle: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Color.gold)
            .frame(width: 44, height: 24)
            .contentShape(Rectangle())
            .onTapGesture { closeEffEntry() }
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onEnded { v in if v.translation.height > 12 { closeEffEntry() } }
            )
    }

    private func effRow(_ digits: [String]) -> some View {
        HStack(spacing: 8) {
            ForEach(digits, id: \.self) { effDigitKey($0) }
        }
    }

    private func effDigitKey(_ d: String) -> some View {
        Button(action: { effDigit(d) }) {
            Text(d)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.textBody)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Color.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderDark, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func effActionKey(system: String, tint: Color, filled: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(filled ? Color(hex: "#0D0D0D") : tint)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(filled ? Color.gold : Color.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(filled ? Color.goldLight : tint.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
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

    /// What the card picker is currently editing: a hero street (hole/board) or a villain's hole cards
    /// (by seat). A villain entry *behaves* exactly like hole entry — 2 frames, `s`/`o`, bound/footnote,
    /// no board-count — so `behaviorStreet` maps it to `.hole` and every street-keyed helper works
    /// unchanged; only group routing and identity (which slot is highlighted) key off the target.
    enum CardTarget: Equatable {
        case street(CardStreet)
        case villain(Int)        // seat index
        var behaviorStreet: CardStreet {
            switch self {
            case .street(let s): return s
            case .villain:       return .hole
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

    /// The live group for any entry target — hero street or villain seat.
    private func group(for target: CardTarget) -> CardGroup {
        switch target {
        case .street(let s):    return group(for: s)
        case .villain(let seat): return villainGroups[seat] ?? CardGroup(capacity: 2)
        }
    }

    private func setGroup(_ target: CardTarget, _ g: CardGroup) {
        switch target {
        case .street(let s):    setGroup(s, g)
        case .villain(let seat): villainGroups[seat] = g
        }
    }

    /// Opening a group focuses the left-most empty frame (or card 1 if full); entry is always
    /// left-to-right, so the tapped slot index is ignored. Re-opening never mutates the cards — a
    /// finished group is cleared only when you start typing a new rank (see `rankTapped`).
    private func openCardEntry(_ street: CardStreet) { openCardEntry(.street(street)) }

    private func openCardEntry(_ target: CardTarget) {
        if let current = entryTarget, current != target { normalizeUnsuited(current) }
        entryTarget = target
        effEntryVisible = false         // close the eff keypad so the two never show at once
        let g = group(for: target)
        entryLocked = g.isFull          // re-opening a finished group → display-only until a rank is typed
        focusIndex = g.firstEmptyIndex ?? 0
    }

    private func closeEntry() {
        if let current = entryTarget { normalizeUnsuited(current) }
        entryTarget = nil
        syncClosedHandCards()   // post-close card edits (hero or villain) re-sync onto the saved Hand
    }

    /// On leaving a bank, default any ranked card with no chosen suit to explicit `x` — so a card you
    /// typed but didn't suit reads as "rank, unknown suit" (`Qx`) rather than looking incomplete.
    /// Skips footnote/relationship groups (their suit info lives off the frame, not on it) and a full,
    /// untouched hole/flop/villain group (left bare so its one-tap texture shortcuts stay available).
    private func normalizeUnsuited(_ target: CardTarget) {
        let g = group(for: target)
        let keepsTexture = keepsTextureOption(g, street: target.behaviorStreet)
        let normalized = normalizingUnsuited(g, keepsTexture: keepsTexture)
        if normalized != g { setGroup(target, normalized) }
    }

    /// A full, no-suit hole/flop/villain group still offers the one-tap texture shortcuts
    /// (suited/offsuit, rainbow/mono/two-tone), so it's left bare on exit to keep them — and the
    /// shorthand clean. Single cards, pairs, and turn/river have no texture and take the `x` default.
    private func keepsTextureOption(_ g: CardGroup, street: CardStreet) -> Bool {
        guard g.isFull, g.mode == .none else { return false }
        switch street {
        case .hole:
            let ranks = g.frames.compactMap { $0.rank }
            return !(ranks.count == 2 && ranks[0] == ranks[1])   // a pair has no suited/offsuit
        case .flop:         return true
        case .turn, .river: return false
        }
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
        // Only hero streets have a "next bank"; a villain group is a single bank, so Next = Done.
        if case .street(let street) = entryTarget, let next = nextCardStreet(after: street) {
            withAnimation(.easeInOut(duration: 0.15)) { openCardEntry(next) }
        } else {
            closeEntry()
        }
    }

    private func clearEntryGroup() {
        guard var g = entryGroup else { return }
        g.reset(); setEntryGroup(g)
        focusIndex = 0
    }

    /// Tap a rank. A full group means you're starting a new hand, so it CLEARS and restarts with this
    /// rank as the first card (no jarring in-place edit). Otherwise it fills the left-most empty frame
    /// and parks the cursor there — the cursor is always "the card you just typed," so a following suit
    /// binds to it.
    private func rankTapped(_ r: String) {
        guard var g = entryGroup, let rank = Rank(rawValue: r) else { return }
        entryLocked = false             // typing a rank begins fresh entry, releasing the re-open lock
        if g.isFull {
            g.reset()
            g.frames[0].rank = rank
            focusIndex = 0
        } else {
            let i = g.firstEmptyIndex ?? 0
            g.frames[i].rank = rank
            focusIndex = i
        }
        setEntryGroup(g)
    }

    /// Tap a suit (`♠♥♦♣`) or the unknown `x` (`symbol == nil`). The first suit of the group sets the
    /// mode via the first-suit rule: an empty rank frame still open → bound (suit binds to the
    /// just-ranked cursor card); all ranks in → footnote (append to the unassigned note).
    private func suitTapped(_ symbol: String?) {
        guard let street = entryStreet, var g = entryGroup else { return }
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
                    g.frames[0].suit = Suit(symbol: sym).map(FrameSuit.known) ?? .unknown
                    g.suitRun = 1
                }
            } else {
                // x (nil symbol) → explicit unknown; a real glyph → the typed bound suit.
                g.frames[focusIndex].suit = symbol.flatMap { Suit(symbol: $0) }.map(FrameSuit.known) ?? .unknown
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
        setEntryGroup(g)
    }

    /// Tap a relationship/texture shortcut (`s`/`o` hole; `r`/`m`/`tt` flop). Sets relationship mode,
    /// clearing any bound suits and footnote. Gated to a fully-ranked group.
    private func shortcutTapped(_ value: String) {
        guard var g = entryGroup else { return }
        guard g.isFull else { return }   // gating belt-and-suspenders (the button is also dimmed)
        g.mode = .relationship
        g.relationship = value
        g.footnote = []; g.footnoteCursor = 0
        for i in g.frames.indices { g.frames[i].suit = .unspecified }
        setEntryGroup(g)
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
        guard let street = entryStreet, street == .turn || street == .river, var g = entryGroup else { return }
        guard g.frames.first?.suit.knownSymbol != nil else { return }
        g.suitRun = n
        setEntryGroup(g)
    }

    // MARK: - Card Notation (group readout — see ShorthandReference.md §2)

    private func suitLetter(_ s: String) -> String {
        switch s {
        case "♠": return "s"; case "♥": return "h"; case "♦": return "d"; case "♣": return "c"
        default:  return ""
        }
    }

    // Card-group shorthand (`groupNotation(_ g: CardGroup)`, see ShorthandReference.md §2) lives in
    // Rendering/HandRendering.swift. Call it with a live group via `group(for:)`.

    // MARK: - Hand Shorthand (see ShorthandReference.md)

    /// The running shorthand transcript — a pure render of the action log + board + hero cards.
    /// Computed (like `seatActions`) so it tracks Rewind/edits automatically.
    private var handShorthand: String {
        // Fold the in-progress current street's actions into the streets list so the pure builder reads
        // every street uniformly (a saved hand already carries them in `streets`). `buttonSeat` is
        // passed as-is — nil before it's placed, so the header omits the position. Terminal-state
        // signals are mapped from `phase`: villain "shows" lines reveal at showdown / a 2+ close, the
        // result line only once an outcome exists.
        var streetsForRender = streets
        if !actionsThisStreet.isEmpty {
            streetsForRender.append(Street(name: currentStreet, actions: actionsThisStreet))
        }
        return transcript(
            handNumber:       handNumber,
            heroSeat:         heroSeat ?? -1,
            buttonSeat:       buttonSeat,
            occupiedSeats:    occupiedSeats,
            holeGroup:        holeGroup,
            boardGroups:      (flopGroup.hasAnyRank  ? flopGroup  : nil,
                               turnGroup.hasAnyRank  ? turnGroup  : nil,
                               riverGroup.hasAnyRank ? riverGroup : nil),
            villainGroups:    villainGroups,
            effectiveStack:   effectiveStack,
            streets:          streetsForRender,
            throughStreet:    currentStreet,
            showdownVillains: showdownVillains,
            showdownReached:  (phase == .showdown || phase == .handClosed) && activeSeatSequence.count >= 2,
            outcome:          phase == .handClosed ? currentOutcome : nil
        )
    }

    // `collapsedSegments`, `actions(on:in:)`, `boardToken`, and `actionToken` are pure transcript
    // helpers — they live in Rendering/HandRendering.swift, fed by `handShorthand` above.

    // MARK: - Hand Lifecycle

    /// Clears all per-hand state (actions, streets, cards) while preserving the session-locked hero
    /// seat and table size. Does NOT set `phase` — the caller decides the next phase.
    private func resetHandState() {
        currentHandID = UUID()     // a new hand gets a fresh durable identity (Undo-reopen keeps its own)
        currentOutcome = nil
        buttonSeat = nil
        holeGroup  = CardGroup(capacity: 2)
        flopGroup  = CardGroup(capacity: 3)
        turnGroup  = CardGroup(capacity: 1)
        riverGroup = CardGroup(capacity: 1)
        villainGroups = [:]
        entryTarget = nil
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
        seatEditMode = false       // emptySeats itself persists — it's table composition, not per-hand
        lastHandWasSkipped = false
        effectiveStack = nil       // blank every hand (no carry-forward)
        effEntryVisible = false
        effDraft = ""
        effReplaceOnInput = false
    }

    /// Builds a `Hand` from the current live state. Pure snapshot — appends/replaces are the caller's
    /// job. Used both for the initial save at close and for the move-on re-snapshot.
    private func buildHand(outcome: Outcome?) -> Hand {
        var streetsToSave = streets
        if !actionsThisStreet.isEmpty {
            streetsToSave.append(Street(name: currentStreet, actions: actionsThisStreet))
        }
        return Hand(
            id: currentHandID,                  // stable across re-close + post-close edits (upsert key)
            sessionId: session.id,
            handNumber: handNumber,
            title: nil,
            heroSeatIndex: heroSeat ?? 0,
            buttonSeatIndex: buttonSeat ?? 0,
            // Positions are computed over OCCUPIED seats (empties excluded), stable across folds —
            // this is the set `calculatePositions` expects, fixing the old activeSeatSequence drift.
            tableSize: tableSize,
            occupiedSeatIndices: occupiedSeats,
            // Canonical, lossless card groups. A board street is stored only once it has a rank; the
            // flat holeCards/villainCards/board on Hand are computed from these.
            holeGroup: holeGroup,
            flopGroup:  flopGroup.hasAnyRank  ? flopGroup  : nil,
            turnGroup:  turnGroup.hasAnyRank  ? turnGroup  : nil,
            riverGroup: riverGroup.hasAnyRank ? riverGroup : nil,
            villainGroups: villainGroups,
            streets: streetsToSave,
            lastStreet: currentStreet,   // furthest street reached — the transcript/replay read-out bound
            outcome: outcome,
            potSize: nil,
            potUnit: session.potUnit,
            effectiveStack: effectiveStack.map(Double.init),   // hand metadata, in big blinds
            commentary: nil
        )
    }

    /// Persist the current hand at close. Single write path: records the outcome (so post-close edits
    /// can rebuild) and upserts by `currentHandID` — re-closing after Undo updates the same record.
    private func saveCurrentHand(outcome: Outcome?) {
        currentOutcome = outcome
        store.saveHand(buildHand(outcome: outcome), in: session.id)
    }

    /// Deals the next hand from the hand-closed state: place the dealer button on the tapped seat,
    /// reset per-hand state, highlight the first actor, and start recording. The hand that just
    /// finished was already saved at close, so nothing is persisted here.
    /// New Hand — a clean break from the finished hand. Advances the hand number, clears all hand
    /// state, and returns to the "place the button" screen (the same fresh start as hand #1). Every
    /// close (showdown, fold-out, skip) leaves the number un-advanced, so New Hand always increments.
    private func startNewHand() {
        withAnimation(.easeInOut(duration: 0.2)) {
            handNumber += 1
            resetHandState()           // also clears lastHandWasSkipped
            phase = .placingButton
        }
    }

    /// Skip = freeze the current hand exactly like a showdown/fold-out close, but with no outcome —
    /// a "set this aside and move on" close. Stays on the SAME hand number (New Hand advances it,
    /// like any close); saves the hand as incomplete; keeps all live state so Undo can reopen
    /// recording at the last action. `lastHandWasSkipped` marks the close-kind for undoLastAction
    /// (a skip reopens without peeling, distinguishing it from a fold-out which also saves nil).
    private func skipHand() {
        withAnimation(.easeInOut(duration: 0.2)) {
            handCloseSummary = "SKIPPED"
            saveCurrentHand(outcome: nil)
            lastHandWasSkipped = true
            highlightedSeat = nil
            phase = .handClosed
        }
    }

    /// Move = "next hand, new seat." Releases the hero seat and returns to seat selection ("TAKE
    /// YOUR SEAT" → "PLACE THE BUTTON"). Only reachable from two phases (the button is hidden
    /// elsewhere): from `handClosed` it deals the next hand, so the number advances (the finished
    /// hand was already saved at close); from `placingButton` it just re-picks the seat for the
    /// same, not-yet-started hand, so the number is unchanged. To change seats mid-hand, end the
    /// hand with Skip first, then Move from the frozen state.
    private func moveSeat() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if phase == .handClosed { handNumber += 1 }
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
/// Measures the bottom section's full height (card strip + control region) — the transcript panel's
/// expanded height.
private struct BottomSectionHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Measures the freed space under the control bar (the collapsed transcript's resting slot). It grows
/// when the control bar's action row is absent (place-button / hand-closed), so the transcript fills it.
private struct TranscriptSlotHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct ControlBar: View {
    let isRecording: Bool
    let currentStreet: StreetName
    let facesBet: Bool                      // does the seat ON THE CLOCK face a wager? (per-seat
                                            // context, like the engine — NOT the global bet level)
    let highlightedSeat: Int?
    let rewindEnabled: Bool
    let nextStreetEnabled: Bool
    let nextStreetPulsing: Bool
    let nextStreetLabel: String
    let sizingActive: Bool                 // sizing chip row showing (Raise/Bet/Call was held)
    let sizingChips: [String]              // the strip to render in that row
    let sizingSelectedType: ActionType?    // which action is being sized (drives "selected" chip)
    let isRunOut: Bool                     // ≤1 player with chips — no betting, board runs out
    let showNewHand: Bool                  // hand closed — show the New Hand button (forward action)
    let onAction: (ActionType) -> Void
    let onRewind: () -> Void
    let onNextStreet: () -> Void
    let onAggressiveHold: () -> Void        // 0.3s hold fired on the Raise/Bet button
    let onCallHold: () -> Void              // 0.3s hold fired on the Call button → call-all-in
    let onSizingChip: (String) -> Void      // a size chip was tapped
    let onNewHand: () -> Void               // start the next hand (clears to the place-button screen)

    // Hold classification for the Raise/Bet button — same proven single-DragGesture pattern as the
    // seats: a stationary press past 0.3s is a hold (→ sizing), anything shorter is a quick tap.
    @State private var holdFired: Bool = false
    @State private var holdTimer: DispatchWorkItem? = nil

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.borderDark)
                .frame(height: 1)

            VStack(spacing: 10) {
                // Utility row — Undo (left) · Next Street (right). When Raise/Bet is held the sizing
                // chips take the whole row to the right of Undo: Next Street is hidden (a staged
                // raise/bet never closes the street, so it would be disabled anyway), giving the chips
                // full width. The action row below never shifts. Undo only when the hand is closed.
                HStack(spacing: 8) {
                    undoButton
                    if isRecording && sizingActive {
                        sizingScroll
                            .transition(.opacity)
                    } else {
                        Spacer(minLength: 0)
                        if isRecording { nextStreetButton }
                        else if showNewHand { newHandButton }   // forward action when the hand is closed
                    }
                }
                // Primary row — full-width action buttons, the most-used controls in the thumb zone.
                // Hidden whenever the Next Street button is pulsing (`nextStreetPulsing` ==
                // streetClosedDecisively || isRunOut): a decisive street close or a run-out leaves no
                // seat to act on, so the only valid move is Next Street. (Acting on the resolved last
                // seat would re-commit it — or a Raise would re-open the closed round.) Fix a mistake
                // with Undo, which stays live. The bar goes quiet, like the hand-closed state.
                if isRecording && !nextStreetPulsing {
                    actionButtons
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .background(Color.surface)
    }

    // MARK: Sizing chips (fill the utility row between Undo and Next Street on a Raise/Bet hold)

    /// Horizontally-scrolling chip strip that occupies the flexible middle of the utility row. Undo
    /// and Next Street stay pinned at the edges; only the chips scroll, so the action row never moves.
    private var sizingScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(sizingChips, id: \.self) { chip in
                    sizingChipButton(chip)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func sizingChipButton(_ label: String) -> some View {
        let c = sizeChipColors(label)
        return Button(action: { onSizingChip(label) }) {
            Text(label)
                .font(.custom("Arial", size: 13))
                .fontWeight(.bold)
                .foregroundStyle(c.text)
                .padding(.horizontal, 11)
                .frame(height: 38)
                .background(c.bg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(c.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// Chip colors by kind: light gold for All-in, gold for Pot, green for every `%` chip (sub-pot
    /// AND overbets like 110%), purple for raise multiples (the `x` chips — only the raise strip has
    /// them). Purple keeps the raises distinct from the gold Raise button and the gold All-in.
    private func sizeChipColors(_ label: String) -> (bg: Color, border: Color, text: Color) {
        if label == "All-in" {
            return (Color(hex: "#2A1A05"), Color(hex: "#E8D5A3"), Color(hex: "#E8D5A3"))
        }
        if label == "Pot" {
            return (Color(hex: "#252010"), Color(hex: "#C9A84C"), Color(hex: "#E8D5A3"))
        }
        if label.hasSuffix("%") {
            return (Color(hex: "#111A0D"), Color(hex: "#3A6020"), Color(hex: "#7AB840"))
        }
        return (Color(hex: "#16101A"), Color(hex: "#7A3FA0"), Color(hex: "#B07AD0"))   // raise multiple
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

    // MARK: New Hand (forward action when the hand is closed)

    /// Gold capsule in the Next Street slot, shown only once the hand is closed. Pulses to draw the
    /// eye to the next step now that tapping a seat no longer deals — this is the only way forward.
    private var newHandButton: some View {
        Pulse(isActive: true) { phase in
            newHandButtonBody.scaleEffect(1.0 + 0.04 * phase)
        }
    }

    private var newHandButtonBody: some View {
        Button(action: onNewHand) {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                Text("New Hand")
                    .font(.custom("Arial", size: 11))
                    .fontWeight(.bold)
                    .tracking(0.5)
            }
            .foregroundStyle(Color(hex: "#0D0D0D"))
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                Capsule().fill(
                    LinearGradient(
                        colors: [Color.gold, Color(hex: "#9A6820")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            )
            .overlay(Capsule().stroke(Color.goldLight.opacity(0.6), lineWidth: 1))
            .shadow(color: Color.gold.opacity(0.4), radius: 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: Context-aware action buttons (middle)

    @ViewBuilder
    private var actionButtons: some View {
        // Bet context = preflop, or the seat on the clock faces a wager. Using the per-seat `facesBet`
        // (not a global bet-level flag) means a seat that has just opened the betting keeps its own
        // Check/Bet row — it never flips to Fold/Call/Raise while that player is still acting, so the
        // held Bet button is never torn out mid-gesture. Matches the engine's context everywhere else.
        let isBetContext = currentStreet == .preflop || facesBet
        if isBetContext {
            HStack(spacing: 10) {
                actionChip("Fold",  type: .fold,  style: .destructive)
                // Facing a wager, Call is holdable → mark it all-in; a limp (no bet faced) stays plain.
                if facesBet {
                    callChip
                } else {
                    actionChip("Call", type: .call, style: .neutral)
                }
                aggressiveChip("Raise", type: .raise)
            }
        } else {
            HStack(spacing: 10) {
                actionChip("Check", type: .check, style: .neutral)
                aggressiveChip("Bet",   type: .open)
            }
        }
    }

    /// The Raise/Bet button: a quick tap commits unsized (decisive, like any action chip); a 0.3s
    /// hold opens the sizing row. Renders "selected" (solid gold) while its own sizing row is up.
    private func aggressiveChip(_ label: String, type: ActionType) -> some View {
        holdableChip(label, type: type,
                     fg: Color.gold, bg: Color(hex: "#1A1508"), border: Color.gold.opacity(0.5),
                     selFg: Color(hex: "#0D0D0D"), selBg: Color.gold,
                     onHold: onAggressiveHold)
    }

    /// The Call button when facing a wager: a quick tap commits a normal call; a 0.3s hold opens the
    /// single "All-in" chip to mark the call all-in. Renders "selected" (solid green) while its row
    /// is up. (A limp uses the plain `actionChip` — a limp can't be all-in.)
    private var callChip: some View {
        holdableChip("Call", type: .call,
                     fg: Color.textBody, bg: Color.surface2, border: Color.borderDark,
                     selFg: Color(hex: "#07140A"), selBg: Color.winGreen,
                     onHold: onCallHold)
    }

    /// A tap-or-hold action button. Quick tap → `onAction(type)` (decisive, unsized). 0.3s hold →
    /// `onHold` (opens the sizing/all-in row). Tap and hold share one DragGesture(minimumDistance: 0)
    /// — the same pattern the seats use — so they never fight over a layered recognizer. The button
    /// shows its `sel*` colors while ITS action is the one being sized (`sizingSelectedType == type`).
    @ViewBuilder
    private func holdableChip(_ label: String, type: ActionType,
                              fg: Color, bg: Color, border: Color,
                              selFg: Color, selBg: Color,
                              onHold: @escaping () -> Void) -> some View {
        let isDisabled = highlightedSeat == nil
        let selected = sizingActive && sizingSelectedType == type
        Text(label)
            .font(.custom("Arial", size: 16))
            .fontWeight(.bold)
            .foregroundStyle(selected ? selFg : fg)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(selected ? selBg : bg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? selBg : border, lineWidth: 1.5)
            )
            .opacity(isDisabled ? 0.35 : 1.0)
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        // Arm the hold timer once on touch-down (onChanged fires immediately at
                        // minimumDistance 0). A second arm is blocked until this press ends.
                        if holdTimer == nil && !holdFired {
                            let work = DispatchWorkItem {
                                holdFired = true
                                onHold()
                            }
                            holdTimer = work
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
                        }
                    }
                    .onEnded { _ in
                        holdTimer?.cancel()
                        holdTimer = nil
                        let wasHold = holdFired
                        holdFired = false
                        if !wasHold { onAction(type) }   // released before 0.3s → quick tap, unsized
                    }
            )
            .disabled(isDisabled)
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
// `FrameSuit`, `CardFrame`, and `CardGroup` now live in `Models.swift` (they are part of the persisted,
// lossless card model — see "Card Entry Model" there). The view only mutates and renders them.

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

/// The group texture pill (Style C): one dark, gold-bordered capsule straddling the bottom edge of a
/// card row. Holds either the relationship word (gold) or the footnote glyph set (red ♥♦ / light ♠♣ /
/// muted x). Shared by the recording strip (`groupSection`) and Replay's read-only card row.
struct CardTextureBadge: View {
    let glyphSet: [String]?
    let relWord: String?

    var body: some View {
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
                        .foregroundStyle(Self.glyphColor(sym))
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color(hex: "#222222")))
        .overlay(Capsule().stroke(Color.gold, lineWidth: 0.5))
        .fixedSize()
    }

    /// Suit-glyph colors tuned for the dark badge: red stays red, spade/club go LIGHT (black would
    /// vanish), the unknown x is muted.
    static func glyphColor(_ s: String) -> Color {
        switch s {
        case "♥", "♦": return Color(hex: "#E0524A")
        case "♠", "♣": return Color(hex: "#EDEDED")
        default:        return Color(hex: "#888888")   // x (unknown)
        }
    }
}

struct CardFrameView: View {
    let frame: CardFrame
    var showBoundSuit: Bool = false   // true only in .bound mode — draws the suit pip on the face
    var boundUnknown: Bool = false    // bound, suitless, but a partner card is suited → grey "x"
    var suitRun: Int = 1              // turn/river: draw the suit pip this many times (board count)
    var faceDown: Bool = false        // incognito: a filled hole card shows its back instead of the face
    let isActive: Bool
    var promptEmpty: Bool = false     // showdown/closed: "enter this now" border on an empty slot
    var promptColor: Color = .gold    // color of that cue border — red for villain groups, gold for hero

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
                        .stroke(strokeColor, lineWidth: isActive ? 2 : (frame.isEmpty && promptEmpty ? 1.5 : 1))
                )
                .shadow(color: isActive ? Color.gold.opacity(0.4) : .clear, radius: 6)

            if frame.isEmpty {
                Text("?")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.borderDark)
            } else {
                VStack(spacing: 0) {
                    Text(frame.rank?.rawValue ?? "")
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

    /// Border: gold when focused (active); the cue color (gold for hero, red for villains) when an empty
    /// slot is being prompted for entry (showdown/closed); a faint outline for a plain empty slot;
    /// invisible for a filled face.
    private var strokeColor: Color {
        if isActive { return Color.gold }
        if frame.isEmpty { return promptEmpty ? promptColor : Color.borderDark.opacity(0.5) }
        return Color.clear
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
    .environmentObject(SessionStore(backing: InMemoryHandStore()))
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
