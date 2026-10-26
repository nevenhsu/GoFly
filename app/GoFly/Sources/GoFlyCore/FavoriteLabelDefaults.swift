import Foundation

public enum FavoriteLabelDefaults {
    public static func defaultName(at date: Date = .now, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = timeZone
        formatter.dateFormat = "d MMM yyyy HH:mm"
        return formatter.string(from: date)
    }

    public static func resolved(_ draft: String, fallback: String) -> String {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
