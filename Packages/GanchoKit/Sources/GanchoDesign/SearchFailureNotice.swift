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
            Image(systemName: "exclamationmark.circle")
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
        case .readFailed: "Search couldn’t be completed"
        }
    }

    private var detail: LocalizedStringKey {
        switch failure {
        case .invalidRegularExpression: "Check the expression and try again."
        case .readFailed: "Your history couldn’t be searched. Try again."
        }
    }
}
