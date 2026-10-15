import SwiftUI

/// Figma "Text Field" (1:2822). Label (AR/Footnote) above a 52pt field with 14pt radius.
/// Emails/URLs/numbers are LTR runs inside RTL fields (value aligned left, Plex Sans).
struct AppTextField: View {
    enum Kind {
        case name, email, password, newPassword, plain, code, url, multiline
    }

    let label: String
    @Binding var text: String
    var kind: Kind = .plain
    var placeholder: String = ""
    var icon: AppIcon? = nil
    var helper: String? = nil
    var error: String? = nil
    var isDisabled = false
    var submitLabel: SubmitLabel = .next
    var onSubmit: () -> Void = {}

    @FocusState private var focused: Bool
    @State private var revealPassword = false

    private var isLTRValue: Bool {
        switch kind {
        case .email, .password, .newPassword, .code, .url: true
        default: false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !label.isEmpty {
                Text(label)
                    .textStyle(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                input
                    .frame(maxWidth: .infinity)
                if kind == .password || kind == .newPassword {
                    Button {
                        revealPassword.toggle()
                    } label: {
                        Icon(.eye, size: 20, color: error != nil ? .statusError : .textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(revealPassword ? "إخفاء كلمة المرور" : "إظهار كلمة المرور")
                } else if error != nil {
                    Icon(.warning, size: 20, color: .statusError)
                } else if let icon {
                    Icon(icon, size: 20, color: .textTertiary)
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 14)
            .frame(minHeight: kind == .multiline ? 120 : 52)
            .background(isDisabled ? Color.bgSurface2 : Color.bgSurface, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: (focused || error != nil) ? 2 : 1)
            )
            .contentShape(Rectangle())
            .onTapGesture { focused = true }

            if let error {
                Text(error)
                    .textStyle(.caption)
                    .foregroundStyle(Color.statusError)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("خطأ: \(error)")
            } else if let helper {
                Text(helper)
                    .textStyle(.caption)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .disabled(isDisabled)
    }

    private var borderColor: Color {
        if error != nil { return .statusError }
        return focused ? .brandPrimary : .borderDefault
    }

    @ViewBuilder
    private var input: some View {
        Group {
            switch kind {
            case .password, .newPassword:
                if revealPassword {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            case .multiline:
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(4...10)
                    .padding(.vertical, 14)
            default:
                TextField(placeholder, text: $text)
            }
        }
        .focused($focused)
        .font(isLTRValue ? AppTextStyle.enBody.font : AppTextStyle.body.font)
        .foregroundStyle(Color.textPrimary)
        .environment(\.layoutDirection, isLTRValue ? .leftToRight : .rightToLeft)
        .multilineTextAlignment(isLTRValue ? .leading : .leading)
        .textContentType(contentType)
        .keyboardType(keyboard)
        .textInputAutocapitalization(kind == .name || kind == .plain || kind == .multiline ? .sentences : .never)
        .autocorrectionDisabled(isLTRValue)
        .submitLabel(submitLabel)
        .onSubmit(onSubmit)
        .accessibilityLabel(label)
    }

    private var contentType: UITextContentType? {
        switch kind {
        case .name: .name
        case .email: .emailAddress
        case .password: .password
        case .newPassword: .newPassword
        case .code: .oneTimeCode
        case .url: .URL
        default: nil
        }
    }

    private var keyboard: UIKeyboardType {
        switch kind {
        case .email: .emailAddress
        case .url: .URL
        case .code: .asciiCapable
        default: .default
        }
    }
}

/// Checkbox row from the consent rows (22pt box, radius 6, 1.5pt stroke).
struct CheckboxRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isOn ? Color.brandPrimary : Color.bgSurface)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isOn ? Color.brandPrimary : Color.borderStrong, lineWidth: 1.5)
                    if isOn {
                        Icon(.check, size: 16, color: .brandOnPrimary)
                    }
                }
                .frame(width: 22, height: 22)
                Text(title)
                    .textStyle(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

/// Password rule list (bg/surface-2 box, check = met, info = advisory).
struct PasswordRequirementsView: View {
    struct Rule: Identifiable {
        let id = UUID()
        let text: String
        let met: Bool
        var advisory = false
    }

    let rules: [Rule]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(rules) { rule in
                HStack(spacing: 6) {
                    Icon(rule.advisory ? .info : .check, size: 14,
                         color: rule.advisory ? .textSecondary : (rule.met ? .statusSuccess : .textTertiary))
                    Text(rule.text)
                        .textStyle(.caption)
                        .foregroundStyle(rule.advisory ? Color.textSecondary : (rule.met ? Color.statusSuccess : Color.textTertiary))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgSurface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
