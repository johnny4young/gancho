import GanchoKit
import SwiftUI

/// Passive, content-free presentation shared by the history surfaces. The
/// caller owns retry and the live search field remains available for editing.
public struct SearchFailureNotice: View {
    public let failure: ClipSearchError
    private let retry: () -> Void

    public init(failure: ClipSearchError, retry: @escaping () -> Void) {
        self.failure = failure
        self.retry = retry
    }

    public var body: some View {
        VStack(spacing: GanchoTokens.Spacing.sm) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if failure != .invalidRegularExpression {
                Button("Try again", action: retry)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("search-retry-button")
            }
        }
        .padding(GanchoTokens.Spacing.lg)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search-failure-notice")
    }

    private var title: LocalizedStringKey {
        switch failure {
        case .invalidRegularExpression: "Invalid regular expression"
        case .timedOut: "Search timed out"
        case .cancelled: "Search cancelled"
        case .readFailed: "Search couldn’t be completed"
        }
    }

    private var detail: LocalizedStringKey {
        switch failure {
        case .invalidRegularExpression: "Check the expression and try again."
        case .timedOut: "Try a simpler search or narrow the filters."
        case .cancelled: "Run the search again when you’re ready."
        case .readFailed: "Your history couldn’t be searched. Try again."
        }
    }

    private var symbol: String {
        switch failure {
        case .invalidRegularExpression, .readFailed: "exclamationmark.circle"
        case .timedOut: "clock"
        case .cancelled: "pause.circle"
        }
    }
}
