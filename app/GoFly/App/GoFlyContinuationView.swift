import GoFlyCore
import SwiftUI

/// The settings projection for the actual system continuation request.
///
/// This view deliberately reports the request state supplied by Core. In
/// particular, an accepted request remains visibly different from a running
/// request; the app does not infer either state from map or service activity.
struct GoFlyContinuationStatus: View {
    @ObservedObject var continuation: MovementContinuationController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    title
                    Spacer(minLength: 12)
                    status
                }
                VStack(alignment: .leading, spacing: 8) {
                    title
                    status
                }
            }

            Text(goFlyString("background.description"))
                .font(.subheadline)
                .foregroundStyle(GoFlyStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("background.description")

            Text(goFlyString("background.systemDecidesRuntime"))
                .font(.footnote)
                .foregroundStyle(GoFlyStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("background.systemDecides")

            if continuation.hasRuntime {
                Label {
                    Text(goFlyString("background.runtimeAvailable"))
                } icon: {
                    Image(systemName: GoFlySymbols.success)
                }
                .font(.footnote)
                .foregroundStyle(GoFlyStyle.secondary)
                .accessibilityIdentifier("background.runtimeAvailable")
            }

            if let key = continuation.noticeKey {
                Label {
                    Text(goFlyString(key))
                } icon: {
                    Image(systemName: GoFlySymbols.warning)
                }
                .font(.footnote)
                .foregroundStyle(GoFlyStyle.errorForeground)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("background.notice")
            }
        }
        .padding(16)
        .goFlyCard(floating: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("background.card")
    }

    private var title: some View {
        Text(goFlyString("background.title"))
            .font(.headline)
            .accessibilityIdentifier("background.title")
    }

    private var status: some View {
        Text(goFlyString(stateKey))
            .font(.subheadline)
            .foregroundStyle(GoFlyStyle.secondary)
            .accessibilityIdentifier("background.status")
    }

    private var stateKey: String {
        switch continuation.state {
        case .idle: return "background.state.idle"
        case .submitting: return "background.state.submitting"
        case .accepted: return "background.state.accepted"
        case .running: return "background.state.running"
        case .rejected: return "background.state.rejected"
        case .expired: return "background.state.expired"
        case .finished: return "background.state.finished"
        }
    }
}

/// A compact map notice for a concrete continuation reason. The map decides
/// whether to show it after higher-priority recovery and cold-state notices.
struct GoFlyContinuationNotice: View {
    @ObservedObject var continuation: MovementContinuationController
    var onSettings: () -> Void = { }

    var hasContent: Bool {
        continuation.noticeKey != nil
    }

    var body: some View {
        if let key = continuation.noticeKey {
            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text(goFlyString(key))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: GoFlySymbols.warning)
                }
                .font(.subheadline)
                .accessibilityIdentifier("background.notice")

                Button(action: onSettings) {
                    Text(goFlyString("operation.settings"))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(GoFlyActionStyle())
                .accessibilityIdentifier("background.settings")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .goFlyCard(floating: true)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("background.notice.panel")
        }
    }
}
