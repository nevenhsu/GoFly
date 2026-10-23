import SwiftUI

/// Keep long status values readable at accessibility sizes without shrinking text.
struct GoFlySettingsValueRow<Title: View, Value: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: Title
    let value: Value

    init(@ViewBuilder title: () -> Title, @ViewBuilder value: () -> Value) {
        self.title = title()
        self.value = value()
    }

    var body: some View {
        layout {
            title
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            value
                .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var layout: AnyLayout {
        if dynamicTypeSize.isAccessibilitySize {
            AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
        } else {
            AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        }
    }
}
