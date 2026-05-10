import SwiftUI

struct NewSessionView: View {
    var onSessionCreated: (Session) -> Void
    var onBack: (() -> Void)? = nil

    @State private var selectedType: SessionType? = nil

    // Cash fields
    @State private var cashName       = ""
    @State private var stakes         = ""
    @State private var startingStack  = ""

    // Tournament fields
    @State private var tourneyName    = ""
    @State private var buyIn          = ""
    @State private var bullet         = 1

    @State private var sessionDate    = Date()

    private var canContinue: Bool {
        switch selectedType {
        case .cash:       return !stakes.isEmpty
        case .tournament: return !tourneyName.isEmpty && !buyIn.isEmpty
        case nil:         return false
        }
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {

                    // ── Nav Bar ───────────────────────────────────────
                    HStack {
                        if let onBack {
                            Button(action: onBack) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Color.gold)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                    // ── Header ────────────────────────────────────────
                    VStack(spacing: 6) {
                        Text("New Session")
                            .font(.custom("Georgia", size: 26))
                            .foregroundStyle(Color.textBody)
                        Text("Select a session type to begin")
                            .font(.custom("Arial", size: 14))
                            .foregroundStyle(Color.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
                    .padding(.bottom, 28)

                    // ── Session Type Cards ────────────────────────────
                    VStack(spacing: 12) {
                        SessionTypeCard(
                            icon: "💵",
                            title: "Cash Game",
                            isSelected: selectedType == .cash,
                            onTap: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedType = selectedType == .cash ? nil : .cash
                                }
                            }
                        )

                        SessionTypeCard(
                            icon: "🏆",
                            title: "Tournament",
                            isSelected: selectedType == .tournament,
                            onTap: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedType = selectedType == .tournament ? nil : .tournament
                                }
                            }
                        )
                    }
                    .padding(.horizontal, 24)

                    // ── Form Fields ───────────────────────────────────
                    if selectedType == .cash {
                        CashFields(
                            name: $cashName,
                            stakes: $stakes,
                            startingStack: $startingStack,
                            date: $sessionDate
                        )
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if selectedType == .tournament {
                        TournamentFields(
                            name: $tourneyName,
                            buyIn: $buyIn,
                            bullet: $bullet,
                            date: $sessionDate
                        )
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // ── Continue Button ───────────────────────────────
                    if selectedType != nil {
                        Button(action: createSession) {
                            Text("Continue →")
                                .font(.custom("Arial", size: 17))
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 17)
                                .background(
                                    canContinue
                                        ? LinearGradient(colors: [Color.gold, Color(hex: "#9A6820")], startPoint: .topLeading, endPoint: .bottomTrailing)
                                        : LinearGradient(colors: [Color.borderDark, Color.borderDark], startPoint: .topLeading, endPoint: .bottomTrailing)
                                )
                                .foregroundStyle(canContinue ? Color(hex: "#0D0D0D") : Color.textMuted)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .disabled(!canContinue)
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                        .transition(.opacity)
                    }

                    Spacer(minLength: 48)
                }
            }
        }
    }

    private func createSession() {
        guard let type = selectedType else { return }

        let session = Session(
            type: type,
            name: type == .cash ? (cashName.isEmpty ? "Cash Game" : cashName) : tourneyName,
            date: sessionDate,
            tableSize: 9,
            heroSeatIndex: 0,
            stakes:        type == .cash ? (stakes.isEmpty ? nil : stakes) : nil,
            buyIn:         type == .tournament ? Double(buyIn.replacingOccurrences(of: ",", with: "")) : nil,
            bullet:        type == .tournament ? bullet : nil,
            startingStack: type == .cash ? Double(startingStack.replacingOccurrences(of: ",", with: "")) : nil
        )
        onSessionCreated(session)
    }
}

// MARK: - Session Type Card

private struct SessionTypeCard: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.feltGreen)
                        .frame(width: 46, height: 46)
                    Text(icon)
                        .font(.system(size: 22))
                }

                Text(title)
                    .font(.custom("Arial", size: 16))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.textBody)

                Spacer()

                Image(systemName: isSelected ? "checkmark" : "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.gold : Color.textMuted)
            }
            .padding(18)
            .background(isSelected ? Color.feltGreen.opacity(0.4) : Color.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.gold : Color.borderDark, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Cash Fields

private struct CashFields: View {
    @Binding var name: String
    @Binding var stakes: String
    @Binding var startingStack: String
    @Binding var date: Date

    var body: some View {
        VStack(spacing: 14) {
            SessionField(label: "NAME", placeholder: "e.g. Bellagio 2/5") {
                TextField("", text: $name)
                    .fieldStyle()
            }

            SessionField(label: "DATE") {
                DatePicker("", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .colorScheme(.dark)
                    .tint(Color.gold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(Color.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack(spacing: 12) {
                SessionField(label: "STAKES", placeholder: "e.g. 2/5") {
                    TextField("", text: $stakes)
                        .fieldStyle()
                }

                SessionField(label: "STARTING ROLL") {
                    CurrencyField(value: $startingStack, prefix: "$")
                }
            }
        }
    }
}

// MARK: - Tournament Fields

private struct TournamentFields: View {
    @Binding var name: String
    @Binding var buyIn: String
    @Binding var bullet: Int
    @Binding var date: Date

    var body: some View {
        VStack(spacing: 14) {
            SessionField(label: "NAME", placeholder: "e.g. WSOP Main Event") {
                TextField("", text: $name)
                    .fieldStyle()
            }

            SessionField(label: "DATE") {
                DatePicker("", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .colorScheme(.dark)
                    .tint(Color.gold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(Color.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack(spacing: 12) {
                SessionField(label: "BUY-IN") {
                    CurrencyField(value: $buyIn, prefix: "$")
                }

                SessionField(label: "BULLET") {
                    Picker("", selection: $bullet) {
                        ForEach(1...6, id: \.self) { n in
                            Text("\(n)").tag(n)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Color.textBody)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(Color.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }
}

// MARK: - Reusable Field Components

private struct SessionField<Content: View>: View {
    let label: String
    var placeholder: String = ""
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.custom("Arial", size: 11))
                .fontWeight(.bold)
                .tracking(1.2)
                .foregroundStyle(Color.textMuted)
            content()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CurrencyField: View {
    @Binding var value: String
    let prefix: String

    var body: some View {
        HStack(spacing: 0) {
            Text(prefix)
                .foregroundStyle(Color.textMuted)
                .padding(.leading, 14)
            TextField("", text: $value)
                .keyboardType(.numberPad)
                .foregroundStyle(Color.textBody)
                .padding(.leading, 4)
                .padding(.vertical, 13)
                .padding(.trailing, 14)
        }
        .background(Color.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.borderDark, lineWidth: 1)
        )
    }
}

// MARK: - TextField Style Helper

private extension View {
    func fieldStyle() -> some View {
        self
            .foregroundStyle(Color.textBody)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.borderDark, lineWidth: 1)
            )
    }
}

#Preview {
    NewSessionView(onSessionCreated: { _ in })
}
