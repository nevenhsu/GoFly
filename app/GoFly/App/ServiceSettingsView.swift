import GoFlyCore
import SwiftUI

struct ServiceSettingsView: View {
    @ObservedObject var service: ServiceController
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    serviceCard
                    if let error = service.error, service.preparedOperation == nil {
                        Label {
                            Text(goFlyString(error.rawValue))
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                        }
                        .font(.body)
                        .foregroundStyle(GoFlyStyle.errorForeground)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(GoFlyStyle.errorSurface, in: RoundedRectangle(cornerRadius: GoFlyStyle.cornerRadius))
                        .accessibilityIdentifier("service.error")
                    }
                }
                .padding(16)
            }
            .safeAreaInset(edge: .bottom) {
                if let operation = service.preparedOperation {
                    GoFlyOperationPanel(
                        operation: operation, unconfirmedFailure: nil,
                        nativeBusy: service.nativeBusy, maximumHeight: geometry.size.height * 0.45,
                        reasonIdentifier: "service.error",
                        onCancel: { _ = service.cancelPreparation(id: $0) },
                        onRetry: { _ = service.retryPreparedOperation(id: $0) },
                        onReturn: { }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
        }
        .background(GoFlyStyle.canvas)
        .navigationTitle(goFlyString("settings.title"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
    }

    private var serviceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text(goFlyString("service.title")).font(.headline)
                    Spacer(minLength: 12)
                    status
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(goFlyString("service.title")).font(.headline)
                    status
                }
            }

            Button {
                if offersStop {
                    _ = service.stop()
                } else {
                    _ = service.start()
                }
            } label: {
                HStack(spacing: 8) {
                    if service.nativeBusy { ProgressView() }
                    Text(goFlyString(offersStop ? "service.stop" : "service.start"))
                }
            }
            .buttonStyle(GoFlyActionStyle(primary: true))
            .disabled(offersStop ? !service.canStop : !service.canStart)
            .accessibilityIdentifier("service.primary")

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 12) { repairButtons }
            } else {
                HStack(spacing: 12) { repairButtons }
            }

            if service.phase == .ready || service.phase == .preparing {
                Text(goFlyString("service.stopBeforeRepair"))
                    .font(.footnote)
                    .foregroundStyle(GoFlyStyle.secondary)
            }

            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text(goFlyString("gps.title"))
                    .font(.subheadline.weight(.semibold))
                Text(goFlyString(service.gpsStatusKey))
                    .font(.subheadline)
                    .foregroundStyle(GoFlyStyle.secondary)
                    .accessibilityIdentifier("service.gpsStatus")
                if let date = service.clearConfirmedAt {
                    HStack(spacing: 4) {
                        Text(goFlyString("gps.clearConfirmedAt"))
                        Text(date, style: .time)
                    }
                    .font(.caption)
                    .foregroundStyle(GoFlyStyle.secondary)
                }
            }
        }
        .padding(16)
        .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: GoFlyStyle.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: GoFlyStyle.cornerRadius)
                .strokeBorder(GoFlyStyle.border, lineWidth: 0.5)
        }
    }

    private var status: some View {
        Text(goFlyString(service.statusKey))
            .font(.subheadline)
            .foregroundStyle(GoFlyStyle.secondary)
            .accessibilityIdentifier("service.status")
    }

    @ViewBuilder
    private var repairButtons: some View {
        Button {
            _ = service.restoreGPS()
        } label: {
            Text(goFlyString("service.restoreGPS"))
        }
        .buttonStyle(GoFlyActionStyle())
        .disabled(!service.canRestoreGPS)
        .accessibilityHint(goFlyString("service.repairHint"))
        .accessibilityIdentifier("service.restoreGPS")

        Button {
            _ = service.resetTunnel()
        } label: {
            Text(goFlyString("service.resetTunnel"))
        }
        .buttonStyle(GoFlyActionStyle())
        .disabled(!service.canResetTunnel)
        .accessibilityHint(goFlyString("service.repairHint"))
        .accessibilityIdentifier("service.resetTunnel")
    }

    private var offersStop: Bool {
        service.phase == .ready || service.phase == .preparing
            || service.phase == .repairRequired || service.phase == .stopping
    }
}
