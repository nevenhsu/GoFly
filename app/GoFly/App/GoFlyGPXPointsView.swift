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
                pointRow(0, compact: true)
                Divider()
                pointRow(1, compact: true)
                Divider()
                Text(goFlyLocalizedFormat(goFlyString("imports.points.middle"), points.count - 3))
                    .font(.subheadline)
                    .foregroundStyle(GoFlyStyle.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 12)
                Divider()
                pointRow(points.count - 1, compact: true)
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
                    pointRow(index, compact: true)
                    if index < points.count - 1 { Divider() }
                }
            }
        }
        .background(GoFlyStyle.secondarySurface, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(GoFlyStyle.border, lineWidth: 0.5) }
        .accessibilityIdentifier("imports.points.list")
    }

    private func pointRow(_ index: Int, compact: Bool = false) -> some View {
        Button { onFocus(points[index]) } label: {
            HStack(spacing: 12) {
                Text("\(index + 1)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(GoFlyStyle.secondary)
                    .frame(width: 24, alignment: .leading)
                Text(points[index].displayText)
                    .font(.body.monospacedDigit())
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if index == 0 || index == points.count - 1 {
                    Text(goFlyString(index == 0 ? "route.origin" : "route.destination"))
                        .font(.subheadline)
                        .foregroundStyle(GoFlyStyle.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: compact ? 46 : 52, alignment: .leading)
            .padding(.horizontal, 12)
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
            VStack(alignment: .leading, spacing: 12) {
                Text(title + " · " + goFlyLocalizedFormat(goFlyString("imports.metadata"),
                                                            goFlyString("imports.kind.tracks"), document.pointCount))
                    .font(.footnote)
                    .foregroundStyle(GoFlyStyle.secondary)
                    .padding(.horizontal, 16)
                GoFlyGPXPointList(points: document.segments.flatMap { $0 }, onFocus: { coordinate in
                    dismiss()
                    onFocus(coordinate)
                })
            }
            .padding(.vertical, 10)
        }
        .background(GoFlyStyle.canvas)
        .navigationTitle(goFlyString("imports.points.all"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("imports.points.content")
    }
}
