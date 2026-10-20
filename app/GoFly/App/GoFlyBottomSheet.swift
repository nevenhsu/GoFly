import SwiftUI

enum GoFlySheetDetent: String, CaseIterable, Sendable {
    case collapsed
    case half
    case expanded
}

/// The shared three-height bottom sheet skeleton (plan 3).
///
/// The parent owns the detent so it can measure the visible map band. Content
/// only scrolls once the sheet is taller than collapsed, which keeps the map
/// usable while the sheet is only a summary.
struct GoFlyBottomSheet<Content: View>: View {
    @Binding var detent: GoFlySheetDetent
    let availableHeight: CGFloat
    let collapsedHeight: CGFloat
    var onHeightChange: (CGFloat) -> Void = { _ in }
    @ViewBuilder let content: () -> Content

    @GestureState private var drag: CGFloat = 0

    private var expandedHeight: CGFloat { max(collapsedHeight + 1, availableHeight * 0.88) }
    private var halfHeight: CGFloat { max(collapsedHeight, availableHeight * 0.46) }

    private var restingHeight: CGFloat {
        switch detent {
        case .collapsed: collapsedHeight
        case .half: halfHeight
        case .expanded: expandedHeight
        }
    }

    private var height: CGFloat {
        max(collapsedHeight, min(expandedHeight, restingHeight - drag))
    }

    var body: some View {
        VStack(spacing: 0) {
            grabber
            // Content owns its scrolling: each panel keeps its own keyboard and
            // scroll behaviour, so the sheet only provides chrome and height.
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
        }
        .frame(height: height, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(GoFlyStyle.surface)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: GoFlyStyle.sheetCornerRadius,
                                          topTrailingRadius: GoFlyStyle.sheetCornerRadius,
                                          style: .continuous))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: GoFlyStyle.sheetCornerRadius,
                                   topTrailingRadius: GoFlyStyle.sheetCornerRadius,
                                   style: .continuous)
                .strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: -4)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: detent)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: onHeightChange)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.sheet")
        .accessibilityValue(detent.rawValue)
    }

    private var grabber: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(GoFlyStyle.border)
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .top)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4)
                .updating($drag) { value, state, _ in state = value.translation.height }
                .onEnded { value in
                    let projected = restingHeight - value.translation.height
                        - value.predictedEndTranslation.height * 0.2
                    detent = nearestDetent(to: projected)
                }
        )
        .onTapGesture { detent = detent == .collapsed ? .half : .collapsed }
        .accessibilityElement()
        .accessibilityLabel(goFlyString("sheet.grabber"))
        .accessibilityValue(goFlyString("sheet.detent.\(detent.rawValue)"))
        .accessibilityHint(goFlyString("sheet.grabber.hint"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("map.sheet.grabber")
    }

    private func nearestDetent(to projected: CGFloat) -> GoFlySheetDetent {
        let candidates: [(GoFlySheetDetent, CGFloat)] = [
            (.collapsed, collapsedHeight), (.half, halfHeight), (.expanded, expandedHeight)
        ]
        return candidates.min { abs($0.1 - projected) < abs($1.1 - projected) }?.0 ?? detent
    }
}
