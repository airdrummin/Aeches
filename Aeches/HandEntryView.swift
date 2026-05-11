import SwiftUI

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
    @State private var seatActions: [Int: SeatState] = [:]

    // Phase 01 — Street state engine
    @State private var currentStreet: StreetName = .preflop
    @State private var streets: [Street] = []
    @State private var actionsThisStreet: [Action] = []
    @State private var betLevelThisStreet: Int = 0
    @State private var activeSeatSequence: [Int] = []
    @State private var foldedSeats: Set<Int> = []
    @State private var highlightedSeat: Int? = nil
    @State private var savedHands: [Hand] = []

    // Card state
    @State private var heroCards: [CardSlot]  = [CardSlot(), CardSlot()]
    @State private var flopCards: [CardSlot]  = [CardSlot(), CardSlot(), CardSlot()]
    @State private var turnCard:  CardSlot    = CardSlot()
    @State private var riverCard: CardSlot    = CardSlot()

    // Card picker state
    @State private var activeSlot: SlotID? = nil
    @State private var pickingRank: String? = nil

    // Phase
    @State private var phase: Phase = .selectSeat

    enum Phase { case selectSeat, placingButton, recordingHand, showdown, handClosed }

    init(session: Session, onBack: @escaping () -> Void) {
        self.session = session
        self.onBack = onBack
        _tableSize = State(initialValue: session.tableSize)
    }

    // MARK: - Phase 01 Computed Properties

    private var openBetExists: Bool { betLevelThisStreet > 0 }

    private var seatActionsFromStreet: [Int: SeatState] {
        var result: [Int: SeatState] = [:]
        for action in actionsThisStreet {
            result[action.seatIndex] = SeatState(
                action: seatStateAction(from: action.actionType),
                sizeLabel: nil
            )
        }
        return result
    }

    // True when all active seats have acted and the bet/check sequence is closed.
    // Wired to UI triggers in Phase 02/03 — computed here as the data contract.
    private var streetIsClosed: Bool {
        guard !actionsThisStreet.isEmpty else { return false }
        let aggressors = actionsThisStreet.filter { $0.actionType == .open || $0.actionType == .raise }
        if aggressors.isEmpty {
            let checkedSeats = Set(actionsThisStreet.filter { $0.actionType == .check }.map { $0.seatIndex })
            return activeSeatSequence.allSatisfy { checkedSeats.contains($0) }
        }
        guard let lastAggressor = aggressors.last else { return false }
        let respondedSeats = Set(
            actionsThisStreet.filter { $0.actionType == .call || $0.actionType == .fold }.map { $0.seatIndex }
        )
        return activeSeatSequence
            .filter { $0 != lastAggressor.seatIndex }
            .allSatisfy { respondedSeats.contains($0) }
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
                    // Balance
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
                    activeSeat: highlightedSeat,
                    onSeatTap: handleSeatTap
                )
                .padding(.horizontal, 8)

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
                    .padding(.top, 10)

                // ── Bottom half — Card strip ───────────────────────────
                if phase == .recordingHand || phase == .showdown {
                    cardStrip
                        .padding(.top, 10)
                }

                Spacer()

                // ── Save hand button ───────────────────────────────────
                if phase == .recordingHand || phase == .showdown {
                    saveBar
                }
            }
        }
        // ── Card picker overlay ────────────────────────────────────────
        .overlay(alignment: .bottom) {
            if activeSlot != nil {
                cardPickerPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: activeSlot != nil)
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
        case .selectSeat:   return Color.textMuted
        case .placingButton: return Color.gold
        case .recordingHand: return Color.winGreen
        case .showdown:      return Color.gold
        case .handClosed:    return Color.textMuted
        }
    }

    private var statusText: String {
        switch phase {
        case .selectSeat:    return "Tap your seat to begin"
        case .placingButton: return "Tap any seat to place the dealer button"
        case .recordingHand:
            if let btn = buttonSeat { return "Dealer: Seat \(btn + 1)  ·  Record action or fill in cards" }
            return "Recording Hand #\(handNumber)"
        case .showdown:      return "Showdown — select winner"
        case .handClosed:    return "Hand complete — tap New Hand to continue"
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
            let positions = calculatePositions(
                buttonSeatIndex: seat,
                activeSeatIndices: activeSeatSequence
            )
            // Highlight UTG (first to act preflop); fall back to SB on short-handed tables
            highlightedSeat = positions.first(where: { $0.value == "UTG" })?.key
                ?? positions.first(where: { $0.value == "SB" })?.key
            phase = .recordingHand

        case .recordingHand:
            recordAction(for: seat)

        case .showdown, .handClosed:
            break
        }
    }

    // MARK: - Action Recording

    private func recordAction(for seat: Int) {
        let currentSeatAction = seatActionsFromStreet[seat]?.action
        // Preflop always behaves as if a bet is open (forced BB acts as the open bet)
        let isBetContext = currentStreet == .preflop || openBetExists

        let nextActionType: ActionType?
        if isBetContext {
            switch currentSeatAction {
            case nil:           nextActionType = .call
            case .call:         nextActionType = .raise
            case .raise, .open: nextActionType = .fold
            case .fold:         nextActionType = nil   // 4th tap = clear
            case .check:        nextActionType = .call // edge: checked then faced a bet
            }
        } else {
            // Post-flop, no open bet
            switch currentSeatAction {
            case nil:    nextActionType = .check
            case .check: nextActionType = .open
            default:     nextActionType = nil          // clear any other state
            }
        }

        let prevAction = seatActionsFromStreet[seat]?.action

        withAnimation(.easeInOut(duration: 0.15)) {
            if let actionType = nextActionType {
                // Replace any existing action for this seat with the new one
                actionsThisStreet.removeAll { $0.seatIndex == seat }
                actionsThisStreet.append(Action(
                    seatIndex: seat,
                    position: positionFor(seat: seat),
                    actionType: actionType,
                    sizing: nil
                ))

                // Fold tracking
                if actionType == .fold {
                    foldedSeats.insert(seat)
                    activeSeatSequence.removeAll { $0 == seat }
                } else if prevAction == .fold {
                    // Seat cycled off fold — restore to active sequence
                    foldedSeats.remove(seat)
                    if !activeSeatSequence.contains(seat) {
                        activeSeatSequence.append(seat)
                        activeSeatSequence.sort()
                    }
                }
            } else {
                // Clear: remove all actions for this seat
                actionsThisStreet.removeAll { $0.seatIndex == seat }
                if prevAction == .fold {
                    foldedSeats.remove(seat)
                    if !activeSeatSequence.contains(seat) {
                        activeSeatSequence.append(seat)
                        activeSeatSequence.sort()
                    }
                }
            }

            // Derive bet level from source of truth rather than incrementing
            betLevelThisStreet = actionsThisStreet.filter {
                $0.actionType == .open || $0.actionType == .raise
            }.count

            seatActions = seatActionsFromStreet
        }
    }

    // MARK: - Street Management

    private func closeStreet() {
        let completed = Street(name: currentStreet, boardCards: [], actions: actionsThisStreet)
        streets.append(completed)
        actionsThisStreet = []
        betLevelThisStreet = 0
        seatActions = [:]
        if let next = currentStreet.next() {
            currentStreet = next
        }
    }

    // MARK: - Phase 01 Helpers

    private func seatStateAction(from actionType: ActionType) -> SeatState.Action {
        switch actionType {
        case .fold:  return .fold
        case .check: return .check
        case .call:  return .call
        case .open:  return .open
        case .raise: return .raise
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
        VStack(spacing: 12) {
            // Labels row
            HStack(spacing: 0) {
                Text("HOLE")
                    .frame(width: cardSlotWidth * 2 + 6)
                Spacer()
                Text("FLOP")
                    .frame(width: cardSlotWidth * 3 + 8)
                Spacer()
                Text("TURN")
                    .frame(width: cardSlotWidth)
                Spacer()
                Text("RIVER")
                    .frame(width: cardSlotWidth)
            }
            .font(.system(size: 9, weight: .bold))
            .tracking(1.5)
            .foregroundStyle(Color.textMuted)
            .padding(.horizontal, 16)

            // Card slots row
            HStack(spacing: 4) {
                // Hero hole cards
                ForEach(0..<2, id: \.self) { i in
                    CardSlotView(slot: heroCards[i], isActive: activeSlot == .hero(i))
                        .onTapGesture { openPicker(for: .hero(i)) }
                }

                Spacer().frame(width: 8)

                // Flop
                ForEach(0..<3, id: \.self) { i in
                    CardSlotView(slot: flopCards[i], isActive: activeSlot == .flop(i))
                        .onTapGesture { openPicker(for: .flop(i)) }
                }

                Spacer().frame(width: 8)

                // Turn
                CardSlotView(slot: turnCard, isActive: activeSlot == .turn)
                    .onTapGesture { openPicker(for: .turn) }

                Spacer().frame(width: 8)

                // River
                CardSlotView(slot: riverCard, isActive: activeSlot == .river)
                    .onTapGesture { openPicker(for: .river) }
            }
            .padding(.horizontal, 12)
        }
    }

    private var cardSlotWidth: CGFloat { 44 }

    // MARK: - Card Picker Panel

    private var cardPickerPanel: some View {
        VStack(spacing: 0) {
            // Drag handle
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.borderDark)
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 14)

            // Current notation display
            let notation = currentSlotNotation
            Text(notation.isEmpty ? "· · ·" : notation)
                .font(.custom("Courier New", size: 18))
                .fontWeight(.bold)
                .tracking(3)
                .foregroundStyle(notation.isEmpty ? Color.textMuted : Color.goldLight)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 14)

            if let rank = pickingRank {
                // Suit picker
                HStack(spacing: 12) {
                    ForEach(["♠", "♥", "♦", "♣"], id: \.self) { suit in
                        Button(action: { commitCard(rank: rank, suit: suit) }) {
                            Text(suit)
                                .font(.system(size: 28))
                                .foregroundStyle(["♥", "♦"].contains(suit) ? Color(hex: "#E74C3C") : Color.white)
                                .frame(width: 64, height: 64)
                                .background(Color.surface2)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.borderDark, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    // Unknown suit
                    Button(action: { commitCard(rank: rank, suit: nil) }) {
                        Text("?")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color.textMuted)
                            .frame(width: 64, height: 64)
                            .background(Color.surface2)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.borderDark, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 16)
            } else {
                // Rank grid
                VStack(spacing: 6) {
                    rankRow(["A","K","Q","J","T","9","8"])
                    rankRow(["7","6","5","4","3","2"])
                }
                .padding(.bottom, 8)

                // Suited / offsuit shortcuts (hole cards only)
                if isHoleCardSlot {
                    HStack(spacing: 10) {
                        qualifierButton("s", label: "Suited")
                        qualifierButton("o", label: "Offsuit")
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }

                // Clear / dismiss
                HStack {
                    Button("Clear") { clearCurrentSlot() }
                        .font(.custom("Arial", size: 13))
                        .foregroundStyle(Color.foldRed)
                    Spacer()
                    Button("Done") { closePicker() }
                        .font(.custom("Arial", size: 13))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.gold)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
        .background(Color.surface.ignoresSafeArea(edges: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 20, y: -4)
    }

    @ViewBuilder
    private func rankRow(_ ranks: [String]) -> some View {
        HStack(spacing: 6) {
            ForEach(ranks, id: \.self) { r in
                Button(action: { pickingRank = r }) {
                    Text(r)
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 40, height: 42)
                        .background(Color.surface2)
                        .foregroundStyle(Color.textBody)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderDark, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func qualifierButton(_ key: String, label: String) -> some View {
        Button(action: {
            if let slot = activeSlot, let rank = currentFirstRank {
                setSlot(slot, to: CardSlot(rank: rank, suit: nil, qualifier: key))
                closePicker()
            }
        }) {
            Text("\(label) (\(key))")
                .font(.custom("Arial", size: 14))
                .fontWeight(.semibold)
                .foregroundStyle(Color.goldLight)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gold.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Save Bar

    private var saveBar: some View {
        HStack(spacing: 12) {
            Button(action: resetHand) {
                Text("Clear Hand")
                    .font(.custom("Arial", size: 14))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            Button(action: saveHand) {
                Text("Save Hand →")
                    .font(.custom("Arial", size: 15))
                    .fontWeight(.bold)
                    .foregroundStyle(Color(hex: "#0D0D0D"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(colors: [Color.gold, Color(hex: "#9A6820")],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    // MARK: - Slot Helpers

    enum SlotID: Equatable {
        case hero(Int), flop(Int), turn, river
    }

    private var isHoleCardSlot: Bool {
        if case .hero(_) = activeSlot { return true }
        return false
    }

    private var currentFirstRank: String? {
        guard case .hero(let i) = activeSlot else { return nil }
        return i == 1 ? heroCards[0].rank : nil
    }

    private var currentSlotNotation: String {
        guard let slot = activeSlot else { return "" }
        switch slot {
        case .hero(let i): return heroCards[i].notation
        case .flop(let i): return flopCards[i].notation
        case .turn:        return turnCard.notation
        case .river:       return riverCard.notation
        }
    }

    private func openPicker(for slot: SlotID) {
        pickingRank = nil
        activeSlot = slot
    }

    private func closePicker() {
        pickingRank = nil
        activeSlot = nil
    }

    private func commitCard(rank: String, suit: String?) {
        guard let slot = activeSlot else { return }
        setSlot(slot, to: CardSlot(rank: rank, suit: suit, qualifier: nil))
        pickingRank = nil
        // Auto-advance to next empty slot
        if let next = nextEmptySlot(after: slot) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                openPicker(for: next)
            }
        } else {
            closePicker()
        }
    }

    private func setSlot(_ slot: SlotID, to card: CardSlot) {
        switch slot {
        case .hero(let i): heroCards[i] = card
        case .flop(let i): flopCards[i] = card
        case .turn:        turnCard = card
        case .river:       riverCard = card
        }
    }

    private func clearCurrentSlot() {
        guard let slot = activeSlot else { return }
        setSlot(slot, to: CardSlot())
        pickingRank = nil
    }

    private func nextEmptySlot(after slot: SlotID) -> SlotID? {
        let order: [SlotID] = [.hero(0), .hero(1), .flop(0), .flop(1), .flop(2), .turn, .river]
        guard let idx = order.firstIndex(of: slot) else { return nil }
        for i in (idx+1)..<order.count {
            let s = order[i]
            switch s {
            case .hero(let j): if heroCards[j].rank == nil { return s }
            case .flop(let j): if flopCards[j].rank == nil { return s }
            case .turn:        if turnCard.rank == nil { return s }
            case .river:       if riverCard.rank == nil { return s }
            }
        }
        return nil
    }

    // MARK: - Hand Lifecycle

    private func resetHand() {
        seatActions = [:]
        buttonSeat = nil
        heroCards  = [CardSlot(), CardSlot()]
        flopCards  = [CardSlot(), CardSlot(), CardSlot()]
        turnCard   = CardSlot()
        riverCard  = CardSlot()
        pickingRank = nil
        activeSlot  = nil
        currentStreet = .preflop
        streets = []
        actionsThisStreet = []
        betLevelThisStreet = 0
        activeSeatSequence = []
        foldedSeats = []
        highlightedSeat = nil
        phase = .placingButton
    }

    private func saveHand() {
        let hand = Hand(
            sessionId: session.id,
            handNumber: handNumber,
            title: nil,
            heroSeatIndex: heroSeat ?? 0,
            buttonSeatIndex: buttonSeat ?? 0,
            activeSeatIndices: activeSeatSequence,
            holeCards: buildHeroCards(),
            streets: streets,
            outcome: nil,
            potSize: nil,
            potUnit: session.potUnit,
            effectiveStack: nil,
            commentary: nil
        )
        savedHands.append(hand)
        handNumber += 1
        resetHand()
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
