import SwiftUI

struct VerificationCodeField: View {
    @Binding var code: String
    var length: Int = 6
    var onComplete: (() -> Void)? = nil
    @FocusState private var isKeyboardShowing: Bool

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<length, id: \.self) { index in
                ZStack {
                    Text(character(at: index))
                        .font(.title3)
                        .frame(maxWidth: .infinity)
                }
                .frame(width: 46, height: 54)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(borderColor(for: index), lineWidth: isActive(index) ? 2 : 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .background(
            TextField("", text: $code.limit(6))
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .focused($isKeyboardShowing)
        )
        .contentShape(Rectangle())
        .onTapGesture { isKeyboardShowing = true }
        .onAppear { isKeyboardShowing = true }
        .onChange(of: code) { value in
            guard value.count == length else { return }
            isKeyboardShowing = false
            DispatchQueue.main.async {
                onComplete?()
            }
        }
    }

    private func character(at index: Int) -> String {
        guard index < code.count else { return "" }
        let i = code.index(code.startIndex, offsetBy: index)
        return String(code[i])
    }

    private func isActive(_ index: Int) -> Bool {
        isKeyboardShowing && code.count == index
    }

    private func borderColor(for index: Int) -> Color {
        isActive(index) ? .yellow : .gray.opacity(0.6)
    }
}

extension Binding where Value == String {
    func limit(_ length: Int) -> Self {
        if wrappedValue.count > length {
            DispatchQueue.main.async {
                wrappedValue = String(wrappedValue.prefix(length))
            }
        }
        return self
    }
}
