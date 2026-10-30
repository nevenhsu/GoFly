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
    var maximumHeight: CGFloat? = nil
    /// Intrinsic content height; the sheet never grows past it, so short
    /// panels do not leave a large empty area under their last row.
    var contentHeight: CGFloat = 0
    /// Fit the currently visible panel without imposing a scrolling container.
    var fitsContent: Bool = false
    /// Grabber row: capsule plus the 20 pt gap before the content, identical for every mode.
    var grabberHeight: CGFloat = GoFlyGrabber.rowHeight
    /// Figma default panel height for the mode (teleport 298, joystick 350 …); content-fitted when nil.
    var preferredHeight: CGFloat? = nil
    var backgroundOpacity: Double = 1
    var onHeightChange: (CGFloat) -> Void = { _ in }
    @ViewBuilder let content: () -> Content

    @GestureState private var drag: CGFloat = 0

    private var minimumHeight: CGFloat {
        fitsContent ? min(availableHeight, collapsedHeight) : collapsedHeight
    }

    private var fittedHeight: CGFloat {
        min(availableHeight, max(minimumHeight, preferredHeight ?? (contentHeight + grabberHeight)))
    }

    private var expandedHeight: CGFloat {
        if fitsContent { return fittedHeight }
        return max(collapsedHeight + 1, min(availableHeight * 0.88, maximumHeight ?? availableHeight))
    }
    private var halfHeight: CGFloat { min(expandedHeight, max(collapsedHeight, availableHeight * 0.5)) }

    private var restingHeight: CGFloat {
        if fitsContent { return fittedHeight }
        return switch detent {
        case .collapsed: collapsedHeight
        case .half: halfHeight
        case .expanded: expandedHeight
        }
    }

    private var settledHeight: CGFloat {
        restingHeight
    }

    private var height: CGFloat {
        max(minimumHeight, min(expandedHeight, settledHeight - drag))
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
        .background(GoFlyStyle.overlayPanelSurface.opacity(backgroundOpacity))
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
        .goFlyShadow(.floating)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: detent)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: onHeightChange)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.sheet")
        .accessibilityValue(detent.rawValue)
    }

    private var grabber: some View {
        Color.clear
            .frame(height: grabberHeight)
            .overlay(alignment: .top) {
                Capsule()
                    .fill(GoFlyStyle.border)
                    .frame(width: 36, height: GoFlyGrabber.capsuleHeight)
                    .padding(.top, GoFlyGrabber.topInset)
                    .opacity(backgroundOpacity)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .updating($drag) { value, state, _ in state = value.translation.height }
                    .onEnded { value in
                        if fitsContent {
                            let translation = value.translation.height + value.predictedEndTranslation.height * 0.2
                            if translation < -20 { detent = .half }
                            if translation > 20 { detent = .collapsed }
                            return
                        }
                        let projected = settledHeight - value.translation.height
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
            .zIndex(1)
    }

    private func nearestDetent(to projected: CGFloat) -> GoFlySheetDetent {
        var candidates: [(GoFlySheetDetent, CGFloat)] = [
            (.collapsed, collapsedHeight), (.half, halfHeight)
        ]
        if expandedHeight > halfHeight + 10 {
            candidates.append((.expanded, expandedHeight))
        }
        return candidates.min { abs($0.1 - projected) < abs($1.1 - projected) }?.0 ?? detent
    }
}
