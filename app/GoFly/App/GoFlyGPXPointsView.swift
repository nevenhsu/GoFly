import GoFlyCore
import SwiftUI

/// GPX samples retain their original order; tapping only changes the map camera.
struct GoFlyGPXPointList: View {
    let points: [GeoCoordinate]
    var summarized = false
    var onFocus: (GeoCoordinate) -> Void
    var onShowAll: () -> Void = {}

    var body: some View {
        LazyVStack(spacing: 0) {
            if summarized && points.count > 10 {
                pointRow(0)
                Divider()
                pointRow(1)
                Divider()
                Text(goFlyLocalizedFormat(goFlyString("imports.points.middle"), points.count - 3))
                    .font(.subheadline)
                    .foregroundStyle(GoFlyStyle.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 12)
                Divider()
                pointRow(points.count - 1)
                Divider()
                Button(action: onShowAll) {
                    Label(goFlyLocalizedFormat(goFlyString("imports.points.allCount"), points.count), systemImage: "list.bullet")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("imports.points.showAll")
            } else {
                ForEach(points.indices, id: \.self) { index in
                    pointRow(index)
                    if index < points.count - 1 { Divider() }
                }
            }
        }
        .background(GoFlyStyle.secondarySurface, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("imports.points.list")
    }

    private func pointRow(_ index: Int) -> some View {
        Button { onFocus(points[index]) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(goFlyString(index == 0 ? "route.origin" : index == points.count - 1 ? "route.destination" : "imports.points.point") +
                     (index > 0 && index < points.count - 1 ? " \(index + 1)" : ""))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(GoFlyStyle.secondary)
                Text(points[index].displayText).font(.body.monospacedDigit())
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("imports.point.\(index)")
    }
}

struct GoFlyGPXPointsView: View {
    let document: GPXDocument
    let title: String
    var onFocus: (GeoCoordinate) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            GoFlyGPXPointList(points: document.segments.flatMap { $0 }, onFocus: { coordinate in
                dismiss()
                onFocus(coordinate)
            })
            .padding(16)
        }
        .background(GoFlyStyle.canvas)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("imports.points.content")
    }
}
