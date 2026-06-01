import Foundation

struct SavedLocation: Equatable {
    var id: UUID
    var displayName: String
    var timeZoneIdentifier: String
    var emoji: String
    var locationName: String?
    var countryCode: String?
    var mapItemID: String?

    init(
        id: UUID = UUID(),
        displayName: String,
        timeZoneIdentifier: String,
        emoji: String,
        locationName: String? = nil,
        countryCode: String? = nil,
        mapItemID: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.timeZoneIdentifier = timeZoneIdentifier
        self.emoji = emoji
        self.locationName = locationName
        self.countryCode = countryCode
        self.mapItemID = mapItemID
    }

    init?(plist: [String: Any]) {
        guard let idString = plist["id"] as? String,
              let id = UUID(uuidString: idString),
              let displayName = plist["displayName"] as? String,
              let timeZoneIdentifier = plist["timeZoneIdentifier"] as? String,
              let emoji = plist["emoji"] as? String
        else { return nil }
        self.id = id
        self.displayName = displayName
        self.timeZoneIdentifier = timeZoneIdentifier
        self.emoji = emoji
        locationName = plist["locationName"] as? String
        countryCode = plist["countryCode"] as? String
        mapItemID = plist["mapItemID"] as? String
    }

    var plistDictionary: [String: Any] {
        var dict: [String: Any] = [
            "id": id.uuidString,
            "displayName": displayName,
            "timeZoneIdentifier": timeZoneIdentifier,
            "emoji": emoji,
        ]
        if let locationName {
            dict["locationName"] = locationName
        }
        if let countryCode {
            dict["countryCode"] = countryCode
        }
        if let mapItemID {
            dict["mapItemID"] = mapItemID
        }
        return dict
    }
}

enum AppPreferences {
    private static let showDayPhaseIconsKey = "showDayPhaseIcons"

    static var showDayPhaseIcons: Bool {
        get {
            if UserDefaults.standard.object(forKey: showDayPhaseIconsKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: showDayPhaseIconsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: showDayPhaseIconsKey)
        }
    }
}

final class LocationStore {
    static let shared = LocationStore()

    private let defaultsKey = "savedLocations"
    private let pinnedIDsDefaultsKey = "pinnedLocationIDs"
    private(set) var locations: [SavedLocation] = []
    private var pinnedIDs: Set<UUID> = []

    private init() {
        load()
    }

    func add(_ location: SavedLocation) {
        locations.append(location)
        save()
    }

    func remove(_ location: SavedLocation) {
        let before = locations.count
        locations.removeAll { $0.id == location.id }
        guard locations.count != before else { return }
        pinnedIDs.remove(location.id)
        save()
        savePinnedIDs()
    }

    func setEmoji(_ emoji: String, for location: SavedLocation) {
        guard let index = index(of: location) else { return }
        locations[index].emoji = emoji
        save()
    }

    func setDisplayName(_ name: String, for location: SavedLocation) {
        guard let index = index(of: location) else { return }
        locations[index].displayName = name
        save()
    }

    func isPinned(_ location: SavedLocation) -> Bool {
        pinnedIDs.contains(location.id)
    }

    func setPinned(_ location: SavedLocation, pinned: Bool) {
        if pinned {
            pinnedIDs.insert(location.id)
        } else {
            pinnedIDs.remove(location.id)
        }
        savePinnedIDs()
    }

    func pinnedLocations() -> [SavedLocation] {
        locations.filter { pinnedIDs.contains($0.id) }
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

    private func index(of location: SavedLocation) -> Int? {
        locations.firstIndex { $0.id == location.id }
    }

    private func load() {
        if let array = UserDefaults.standard.array(forKey: defaultsKey) as? [[String: Any]] {
            locations = array.compactMap(SavedLocation.init(plist:))
        } else {
            locations = []
        }
        loadPinnedIDs()
    }

    private func save() {
        UserDefaults.standard.set(locations.map(\.plistDictionary), forKey: defaultsKey)
    }

    private func loadPinnedIDs() {
        if let ids = UserDefaults.standard.array(forKey: pinnedIDsDefaultsKey) as? [String] {
            pinnedIDs = Set(ids.compactMap(UUID.init(uuidString:)))
        } else {
            pinnedIDs = []
        }
        pruneOrphanedPins()
    }

    private func savePinnedIDs() {
        UserDefaults.standard.set(pinnedIDs.map(\.uuidString), forKey: pinnedIDsDefaultsKey)
    }

    private func pruneOrphanedPins() {
        let valid = Set(locations.map(\.id))
        let pruned = pinnedIDs.intersection(valid)
        guard pruned != pinnedIDs else { return }
        pinnedIDs = pruned
        savePinnedIDs()
    }
}

func flagEmoji(for countryCode: String?) -> String {
    guard let countryCode, countryCode.count == 2 else { return "🌐" }
    let base: UInt32 = 127_397
    return countryCode.uppercased().unicodeScalars.compactMap { scalar in
        UnicodeScalar(base + scalar.value).map(String.init)
    }.joined()
}

func shortDisplayName(_ displayName: String) -> String {
    displayName.components(separatedBy: ",").first?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? displayName
}

private enum TimeFormatterCache {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func string(from date: Date, timeZone: TimeZone) -> String {
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }
}

func formattedTime(in timeZoneIdentifier: String, at date: Date = Date()) -> String {
    guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else { return "--:--" }
    return TimeFormatterCache.string(from: date, timeZone: timeZone)
}

func minutesSinceMidnight(in timeZone: TimeZone, at date: Date = Date()) -> Int {
    var calendar = Calendar.current
    calendar.timeZone = timeZone
    let hour = calendar.component(.hour, from: date)
    let minute = calendar.component(.minute, from: date)
    return hour * 60 + minute
}

func date(atMinutesSinceMidnight minutes: Int, in timeZone: TimeZone, onDayContaining date: Date = Date()) -> Date {
    var calendar = Calendar.current
    calendar.timeZone = timeZone
    let startOfDay = calendar.startOfDay(for: date)
    return calendar.date(byAdding: .minute, value: minutes, to: startOfDay) ?? date
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
