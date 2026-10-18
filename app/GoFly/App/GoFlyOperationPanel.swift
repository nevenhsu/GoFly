import GoFlyCore
import SwiftUI

/// The same preparation presentation is used by map Go and service Start.
struct GoFlyOperationPanel: View {
    var operation: PreparedOperationSnapshot?
    var unconfirmedFailure: DeviceServiceFailure?
    var nativeBusy: Bool
    var maximumHeight: CGFloat
    var reasonIdentifier: String
    var cancelIdentifier = "operation.cancel"
    var onCancel: (UUID) -> Void
    var onRetry: (UUID) -> Void
    var onSettings: (() -> Void)?
    var onReturn: () -> Void
    @State private var contentHeight: CGFloat = 180

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let operation {
                    preparedContent(operation)
                    operationMetrics(operation)
                } else if let failure = unconfirmedFailure {
                    Text(goFlyString("teleport.unconfirmed")).font(.headline)
                    reason(failure)
                    Text(goFlyString("teleport.positionUnconfirmed"))
                        .font(.footnote)
                        .foregroundStyle(GoFlyStyle.secondary)
                    if let onSettings {
                        Button(goFlyString("operation.settings"), action: onSettings)
                            .buttonStyle(GoFlyActionStyle(primary: true))
                            .accessibilityIdentifier("operation.settings")
                    }
                    Button(goFlyString("operation.return"), action: onReturn)
                        .buttonStyle(GoFlyActionStyle())
                        .accessibilityIdentifier("operation.return")
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
        }
        .frame(height: min(contentHeight, max(100, maximumHeight)))
        .goFlyCard(floating: true)
        .accessibilityIdentifier("operation.panel")
    }

    @ViewBuilder private func preparedContent(_ operation: PreparedOperationSnapshot) -> some View {
        switch operation.state {
        case .preparing:
            HStack(alignment: .top, spacing: 8) {
                ProgressView().accessibilityHidden(true)
                Text(goFlyString(operation.attempt.value == 1 ? preparationTitle(operation.source) : "operation.retrying"))
                    .font(.headline)
            }
            Text(goFlyLocalizedFormat(goFlyString("operation.attempt"), operation.attempt.value))
                .font(.subheadline)
                .foregroundStyle(GoFlyStyle.secondary)
                .accessibilityIdentifier("operation.attempt")
            sourceSummary(operation.source)
            Button(goFlyString("operation.cancel")) { onCancel(operation.id) }
                .buttonStyle(GoFlyActionStyle())
                .accessibilityIdentifier("operation.cancel")
        case .failed(let failure):
            Text(goFlyString("operation.failed")).font(.headline)
            sourceSummary(operation.source)
            reason(failure)
            Button(goFlyString("operation.retry")) { onRetry(operation.id) }
                .buttonStyle(GoFlyActionStyle(primary: true))
                .disabled(nativeBusy)
                .accessibilityIdentifier("operation.retry")
            Button(goFlyString("operation.cancel")) { onCancel(operation.id) }
                .buttonStyle(GoFlyActionStyle())
                .disabled(nativeBusy)
                .accessibilityIdentifier(cancelIdentifier)
        case .cancelled:
            ProgressView(goFlyString("operation.cancelling")).font(.headline)
            Text(goFlyString("operation.waitForReturn"))
                .font(.footnote)
                .foregroundStyle(GoFlyStyle.secondary)
            Button(goFlyString("operation.cancel")) { }
                .buttonStyle(GoFlyActionStyle())
                .disabled(true)
                .accessibilityIdentifier("operation.cancel")
        }
    }

    private func preparationTitle(_ source: PreparedOperationSource) -> String {
        switch source {
        case .start: "operation.preparingService"
        case .point, .route, .joystick: "operation.preparingMove"
        }
    }

    private func sourceSummary(_ source: PreparedOperationSource) -> some View {
        let text: String
        switch source {
        case .start: text = goFlyString("operation.startSummary")
        case .point(let intent):
            text = goFlyLocalizedFormat(goFlyString("operation.destination"), intent.candidate.place.title)
        case .route(let intent):
            let destination: String
            if case .place(let place) = intent.draft.destination?.value { destination = place.title }
            else { destination = intent.route.end.displayText }
            text = goFlyLocalizedFormat(goFlyString("operation.destination"), destination)
        case .joystick: text = goFlyString("operation.joystickSummary")
        }
        return Text(text)
            .font(.subheadline)
            .foregroundStyle(GoFlyStyle.secondary)
            .accessibilityIdentifier("operation.source")
    }

    @ViewBuilder private func operationMetrics(_ operation: PreparedOperationSnapshot) -> some View {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-gofly-ui-operation-metrics") {
            Text(metricsText(operation))
                .font(.caption2)
                .foregroundStyle(.clear)
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityIdentifier("operation.sourceMetrics")
        }
        #endif
    }

    #if DEBUG && targetEnvironment(simulator)
    private func metricsText(_ operation: PreparedOperationSnapshot) -> String {
        let source: String
        switch operation.source {
        case .start: source = "start"
        case .point(let intent):
            source = "point|\(intent.id)|\(intent.candidate.id)|\(intent.candidate.place.coordinate.displayText)"
        case .route(let intent):
            source = "route|\(intent.id)|\(intent.lease.id)|\(intent.route.start.displayText)|\(intent.route.end.displayText)"
        case .joystick(let intent):
            source = "joystick|\(intent.id)|\(intent.lease.id)"
        }
        return "\(operation.id)|\(source)|\(operation.attempt.value)"
    }
    #endif

    private func reason(_ failure: DeviceServiceFailure) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: GoFlySymbols.warning).accessibilityHidden(true)
            Text(goFlyString(failure.rawValue))
                .accessibilityIdentifier(reasonIdentifier)
        }
        .font(.footnote)
        .foregroundStyle(GoFlyStyle.errorForeground)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GoFlyStyle.errorSurface, in: RoundedRectangle(cornerRadius: 12))
    }
}
