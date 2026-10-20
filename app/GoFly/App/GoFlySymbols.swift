import SwiftUI

/// SF Symbols by meaning, shared by controls and their help illustrations.
/// A location arrow is reserved for a position; a pin always represents a place.
enum GoFlySymbols {
    static let recenter = "location.viewfinder"
    static let location = "location"
    static let place = "mappin.and.ellipse"
    static let sample = "circle.fill"
    static let coordinates = "scope"
    static let map = "map"
    static let favorite = "star"
    static let favoriteSelected = "star.fill"
    static let search = "magnifyingglass"
    static let clearSearch = "xmark.circle.fill"
    static let settings = "gearshape"
    static let adjustments = "slider.horizontal.3"
    static let close = "xmark"
    static let disclosure = "chevron.forward"
    static let expand = "chevron.down"
    static let selected = "checkmark"
    static let checked = "checkmark.square.fill"
    static let unchecked = "square"
    static let play = "play.fill"
    static let pause = "pause.fill"
    static let add = "plus"
    static let delete = "trash"
    static let reorder = "line.3.horizontal"
    static let importFile = "square.and.arrow.down"
    static let exportFile = "square.and.arrow.up"
    static let externalLink = "arrow.up.right.square"
    static let retry = "arrow.clockwise"
    static let warning = "exclamationmark.triangle"
    static let success = "checkmark.circle"
    static let information = "info.circle"
    static let help = "questionmark.circle"
    static let network = "network"
    static let device = "iphone"
    static let language = "globe"
    static let appearance = "circle.lefthalf.filled"
    static let background = "arrow.triangle.2.circlepath"
    static let service = "antenna.radiowaves.left.and.right"
    static let storage = "externaldrive"
    static let locked = "lock.shield"
    static let route = "point.topleft.down.to.point.bottomright.curvepath"
    static let importEmpty = "doc.badge.plus"
    static let manualMovement = "hand.draw"
    static let walking = "figure.walk"
    static let heading = "location.north.fill"
    static let waiting = "clock"
    // 2026-10-20 redesign additions.
    static let folder = "folder"
    static let compass = "safari"
    static let followHeading = "location.north.line"
    static let ellipsis = "ellipsis"
    static let selectItems = "checkmark.circle"
    static let undo = "arrow.uturn.backward"
    static let swap = "arrow.up.arrow.down"
    static let addStop = "plus.circle"
    static let recent = "clock.arrow.circlepath"
    static let expandSheet = "chevron.up"
    static let collapseSheet = "chevron.down"
    static let successFilled = "checkmark.circle.fill"
    static let dangerFilled = "exclamationmark.circle.fill"
    static let warningFilled = "exclamationmark.triangle.fill"
}

/// Standalone glyphs grow gently with Dynamic Type without overflowing a 44 pt
/// control. Apply to the Image only so adjacent titles retain their own scaling.
private struct GoFlyControlSymbol: ViewModifier {
    @ScaledMetric private var scaledSize: CGFloat
    let maximum: CGFloat
    let weight: Font.Weight

    init(size: CGFloat, maximum: CGFloat, weight: Font.Weight) {
        _scaledSize = ScaledMetric(wrappedValue: size, relativeTo: .body)
        self.maximum = maximum
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: min(scaledSize, maximum), weight: weight))
            .symbolRenderingMode(.monochrome)
    }
}

extension View {
    func goFlyControlSymbol(size: CGFloat = 20, maximum: CGFloat = 24,
                            weight: Font.Weight = .medium) -> some View {
        modifier(GoFlyControlSymbol(size: size, maximum: maximum, weight: weight))
    }
}
