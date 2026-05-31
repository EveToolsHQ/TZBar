import Foundation

struct SavedLocation: Codable, Equatable {
    var displayName: String
    var timeZoneIdentifier: String
    var countryCode: String?
}

final class LocationStore {
    static let shared = LocationStore()

    private let defaultsKey = "savedLocations"
    private(set) var locations: [SavedLocation] = []

    private init() {
        load()
    }

    func add(_ location: SavedLocation) {
        guard !locations.contains(where: { $0.timeZoneIdentifier == location.timeZoneIdentifier && $0.displayName == location.displayName }) else {
            return
        }
        locations.append(location)
        save()
    }

    func remove(_ location: SavedLocation) {
        let before = locations.count
        locations.removeAll { $0 == location }
        guard locations.count != before else { return }
        save()
    }

    func sortedByOffset() -> [SavedLocation] {
        let now = Date()
        return locations.sorted { lhs, rhs in
            let left = TimeZone(identifier: lhs.timeZoneIdentifier)?.secondsFromGMT(for: now) ?? 0
            let right = TimeZone(identifier: rhs.timeZoneIdentifier)?.secondsFromGMT(for: now) ?? 0
            if left != right { return left < right }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([SavedLocation].self, from: data)
        else {
            locations = []
            return
        }
        locations = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(locations) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}

func flagEmoji(for countryCode: String?) -> String {
    guard let countryCode, countryCode.count == 2 else { return "🌐" }
    let base: UInt32 = 127397
    return countryCode.uppercased().unicodeScalars.compactMap { scalar in
        UnicodeScalar(base + scalar.value).map(String.init)
    }.joined()
}

func shortDisplayName(_ displayName: String) -> String {
    displayName.components(separatedBy: ",").first?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? displayName
}

func formattedTime(in timeZoneIdentifier: String, at date: Date = Date()) -> String {
    guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else { return "--:--" }
    let formatter = DateFormatter()
    formatter.timeZone = timeZone
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
}

enum DayPhase {
    case night
    case morning
    case day
    case evening

    var symbolName: String {
        switch self {
        case .night: "moon.stars.fill"
        case .morning: "sunrise.fill"
        case .day: "sun.max.fill"
        case .evening: "sunset.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .night: "Night"
        case .morning: "Morning"
        case .day: "Daytime"
        case .evening: "Evening"
        }
    }
}

func dayPhase(in timeZoneIdentifier: String, at date: Date = Date()) -> DayPhase {
    guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else { return .night }
    var calendar = Calendar.current
    calendar.timeZone = timeZone
    let hour = calendar.component(.hour, from: date)
    switch hour {
    case 5 ..< 8: return .morning
    case 8 ..< 17: return .day
    case 17 ..< 22: return .evening
    default: return .night
    }
}
