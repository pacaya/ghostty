import AppKit
import Combine
import SwiftUI

/// A view model driving the `BrowserChromeView` chrome strip.
///
/// Holds only the chrome's own state — omnibar focus and text. Navigation
/// state (canGoBack/canGoForward/isLoading/url) is read directly from the
/// owning `BrowserPaneView` instead of being shadowed here, so there is
/// only one source of truth.
final class BrowserChromeModel: ObservableObject {
    /// Whether the omnibar currently holds focus. Exposed so the container can
    /// gate first-responder behavior.
    @Published var addressBarFocused: Bool = false

    /// The text currently displayed in the omnibar. Kept in sync with the
    /// owning pane's URL when the bar is not focused.
    @Published var addressText: String = ""

    /// Actions invoked by the chrome. Wired up by the container.
    var onBack: () -> Void = {}
    var onForward: () -> Void = {}
    var onReload: () -> Void = {}
    var onSubmit: (URL) -> Void = { _ in }
    var onClose: () -> Void = {}

    /// Resolves a user-entered string into a URL.
    ///
    /// - If it parses as a URL with a scheme, use it directly.
    /// - Otherwise prepend `https://` and try again, so bare hostnames work.
    /// - If that still doesn't parse or doesn't look like a hostname, fall
    ///   back to a Google search.
    static func resolve(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), let scheme = url.scheme, !scheme.isEmpty {
            return url
        }

        // Treat as a bare host only if it contains a dot and no spaces.
        if trimmed.contains("."), !trimmed.contains(" "),
           let url = URL(string: "https://\(trimmed)"),
           url.host?.isEmpty == false {
            return url
        }

        // Fall back to Google search.
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        return components?.url
    }

    func submit() {
        guard let url = Self.resolve(addressText) else { return }
        addressBarFocused = false
        onSubmit(url)
    }
}

/// Layout (left to right): back, forward, reload, then a rounded omnibar pill
/// containing the URL field. Always visible at ~30pt tall.
struct BrowserChromeView: View {
    @ObservedObject var model: BrowserChromeModel
    @ObservedObject var pane: BrowserPaneView
    @FocusState private var addressFieldFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            navButton(symbol: "xmark", enabled: true, action: model.onClose)
            navButton(symbol: "chevron.left", enabled: pane.canGoBack, action: model.onBack)
            navButton(symbol: "chevron.right", enabled: pane.canGoForward, action: model.onForward)
            navButton(symbol: "arrow.clockwise", enabled: true, action: model.onReload)
            OmnibarPill(
                text: $model.addressText,
                isFocused: $addressFieldFocused,
                onSubmit: model.submit
            )
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(.regularMaterial)
        .onChange(of: addressFieldFocused) { newValue in
            if model.addressBarFocused != newValue {
                model.addressBarFocused = newValue
            }
        }
        .onChange(of: model.addressBarFocused) { newValue in
            if newValue != addressFieldFocused {
                addressFieldFocused = newValue
            }
        }
        .onReceive(pane.$url) { newURL in
            // Don't clobber the user's typing while the bar is focused.
            guard !addressFieldFocused else { return }
            let text = newURL?.absoluteString ?? ""
            if model.addressText != text {
                model.addressText = text
            }
        }
    }

    @ViewBuilder
    private func navButton(symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1.0 : 0.35)
    }
}

/// Rounded pill containing the editable URL field. Shows a focus ring while
/// the address field is focused.
private struct OmnibarPill: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    var body: some View {
        TextField("Search or enter address", text: $text)
            .textFieldStyle(.plain)
            .focused(isFocused)
            .onSubmit(onSubmit)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(
                        isFocused.wrappedValue
                            ? Color.accentColor
                            : Color.secondary.opacity(0.3),
                        lineWidth: isFocused.wrappedValue ? 2 : 1
                    )
            )
    }
}
