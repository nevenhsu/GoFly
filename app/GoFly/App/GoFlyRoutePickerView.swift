import GoFlyCore
import SwiftUI

struct GoFlyRoutePickerView: View {
    let session: RoutePickerSession
    var maximumHeight: CGFloat
    var focusRequest: UUID?
    var onFavorites: () -> Void
    var onConfirm: (UUID, Bool) -> Void
    var onCancel: (UUID) -> Void
    var onStagedCurrentChange: (Bool) -> Void
    @ObservedObject private var candidates: CandidateController
    @State private var usesCurrent: Bool
    @State private var headerHeight: CGFloat = 70
    @State private var actionHeight: CGFloat = 52
    @State private var contentHeight: CGFloat = 240
    @State private var visibleScrollFrame: CGRect = .zero

    init(session: RoutePickerSession, maximumHeight: CGFloat, focusRequest: UUID?,
         onFavorites: @escaping () -> Void, onConfirm: @escaping (UUID, Bool) -> Void,
         onCancel: @escaping (UUID) -> Void, onStagedCurrentChange: @escaping (Bool) -> Void = { _ in }) {
        self.session = session; self.maximumHeight = maximumHeight; self.focusRequest = focusRequest
        self.onFavorites = onFavorites; self.onConfirm = onConfirm; self.onCancel = onCancel
        self.onStagedCurrentChange = onStagedCurrentChange
        _candidates = ObservedObject(wrappedValue: session.candidates)
        _usesCurrent = State(initialValue: session.allowsCurrent && session.initialValue == .current)
    }

    var body: some View {
        VStack(spacing: 12) {
            ScrollView {
                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            Text(goFlyString(session.allowsCurrent ? "route.editOrigin" : "route.editDestination"))
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button(goFlyString("route.picker.cancel")) { onCancel(session.id) }
                                .font(.body.weight(.semibold))
                                .frame(minWidth: 44, minHeight: 44)
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("route.picker.cancel")
                        }
                        if session.allowsCurrent {
                            Toggle(isOn: $usesCurrent) {
                                Label(goFlyString("route.useCurrentLocation"),
                                      systemImage: usesCurrent ? "checkmark.square.fill" : "square")
                                    .font(.body)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .toggleStyle(.button)
                            .buttonStyle(.plain)
                            .accessibilityValue(usesCurrent ? "1" : "0")
                            .accessibilityIdentifier("route.picker.current")
                        }
                    }
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { headerHeight = $0 }
                    GoFlySearchPanel(
                        search: candidates,
                        maximumHeight: max(76, maximumHeight - headerHeight - actionHeight - 56),
                        focusRequest: focusRequest, onFavorites: onFavorites,
                        favoritesVisible: candidates.queryKind == .empty || candidates.results.isEmpty,
                        inputIsEmphasized: true
                    )
                }
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
            }
            .defaultScrollAnchor(.bottom)
            .frame(height: max(0, min(contentHeight, maximumHeight - actionHeight - 44)))
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
                #if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains("-gofly-ui-map-metrics") { visibleScrollFrame = frame }
                #endif
            }
            .accessibilityIdentifier("route.picker.content")
            Button(goFlyString("route.picker.confirm")) { onConfirm(session.id, usesCurrent) }
                .buttonStyle(GoFlyActionStyle(primary: true))
                .disabled(!(usesCurrent && session.allowsCurrent) && !candidates.canGo)
                .accessibilityIdentifier("route.picker.confirm")
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { actionHeight = $0 }
        }
        .padding(16)
        .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: GoFlyStyle.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: GoFlyStyle.cornerRadius).strokeBorder(GoFlyStyle.border, lineWidth: 0.5)
        }
        .overlay(alignment: .topLeading) { viewportMetrics }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("route.picker")
        .onAppear { onStagedCurrentChange(usesCurrent) }
        .onChange(of: usesCurrent) { _, selected in onStagedCurrentChange(selected) }
        .onChange(of: candidates.candidate?.id) { _, _ in usesCurrent = false }
        .onChange(of: candidates.query) { _, _ in usesCurrent = false }
    }
    @ViewBuilder private var viewportMetrics: some View {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-gofly-ui-map-metrics") {
            Text(String(format: "%.2f,%.2f,%.2f,%.2f", visibleScrollFrame.minX, visibleScrollFrame.minY,
                        visibleScrollFrame.width, visibleScrollFrame.height))
                .font(.caption2)
                .foregroundStyle(.clear)
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityIdentifier("route.picker.viewportMetrics")
        }
        #endif
    }

}
