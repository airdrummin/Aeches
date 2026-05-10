import SwiftUI

struct LoginView: View {
    var onAuthenticated: () -> Void

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {

                Spacer()

                // ── Logo ──────────────────────────────────────────────
                VStack(spacing: 16) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 315, height: 315)

                    Text("Hand History. Elevated.")
                        .font(.custom("Arial", size: 14))
                        .foregroundStyle(Color.textMuted)
                }

                Spacer()

                // ── Auth Buttons ──────────────────────────────────────
                VStack(spacing: 12) {
                    AuthButton(
                        label: "Continue with Apple",
                        icon: "apple.logo",
                        style: .primary,
                        action: onAuthenticated
                    )

                    AuthButton(
                        label: "Continue with Google",
                        icon: "globe",
                        style: .secondary,
                        action: onAuthenticated
                    )

                    AuthButton(
                        label: "Continue with Email",
                        icon: "envelope",
                        style: .secondary,
                        action: onAuthenticated
                    )
                }
                .padding(.horizontal, 28)

                // ── Footer ────────────────────────────────────────────
                VStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Text("Don't have an account?")
                            .font(.custom("Arial", size: 13))
                            .foregroundStyle(Color.textMuted)
                        Button("Create one") {
                            onAuthenticated()
                        }
                        .font(.custom("Arial", size: 13))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.gold)
                    }

                    Text("By continuing, you agree to our Terms & Privacy Policy.")
                        .font(.custom("Arial", size: 11))
                        .foregroundStyle(Color.textMuted.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .padding(.top, 24)
                .padding(.bottom, 48)
            }
        }
    }
}

// MARK: - Auth Button

private struct AuthButton: View {
    enum Style { case primary, secondary }

    let label: String
    let icon: String
    let style: Style
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                Text(label)
                    .font(.custom("Arial", size: 16))
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(background)
            .foregroundStyle(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(borderColor, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var background: Color {
        style == .primary ? Color.gold : Color.surface2
    }

    private var foregroundColor: Color {
        style == .primary ? Color(hex: "#0D0D0D") : Color.textBody
    }

    private var borderColor: Color {
        style == .primary ? Color.gold : Color.borderDark
    }
}

#Preview {
    LoginView(onAuthenticated: {})
}
