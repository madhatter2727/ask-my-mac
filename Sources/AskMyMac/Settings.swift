import Combine
import EventKit
import Foundation

/// Local Osaurus endpoint and model. Persisted in UserDefaults.
@MainActor
final class Settings: ObservableObject {
    static let defaultBaseURL = "http://127.0.0.1:1337/v1"
    static let defaultModel = "raptor-0.6-4b-jang_6m"

    private static let baseURLKey = "askmymac.baseURL"
    private static let modelKey = "askmymac.model"
    private static let engineKey = "askmymac.engine"
    private static let enabledCalendarIDsKey = "askmymac.enabledCalendarIDs"
    private static let knownCalendarIDsKey = "askmymac.knownCalendarIDs"

    /// Raptor in Osaurus is the default. `--engine spark|bonsai|osaurus` overrides for one run without saving.
    @Published var engine: Engine {
        didSet {
            guard !overridden else { return }
            defaults.set(engine.rawValue, forKey: Self.engineKey)
        }
    }
    private var overridden = false

    @Published var baseURL: String {
        didSet { defaults.set(baseURL, forKey: Self.baseURLKey) }
    }

    @Published var model: String {
        didSet { defaults.set(model, forKey: Self.modelKey) }
    }

    /// `nil` means every calendar (preference never set). A list means only those identifiers.
    @Published private(set) var enabledCalendarIdentifiers: [String]? {
        didSet {
            if let ids = enabledCalendarIdentifiers {
                defaults.set(ids, forKey: Self.enabledCalendarIDsKey)
            } else {
                defaults.removeObject(forKey: Self.enabledCalendarIDsKey)
            }
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        baseURL = Self.stored(defaults.string(forKey: Self.baseURLKey), fallback: Self.defaultBaseURL)
        model = Self.stored(defaults.string(forKey: Self.modelKey), fallback: Self.defaultModel)
        engine = Engine(rawValue: defaults.string(forKey: Self.engineKey) ?? "") ?? .picker
        if defaults.object(forKey: Self.enabledCalendarIDsKey) == nil {
            enabledCalendarIdentifiers = nil
        } else {
            enabledCalendarIdentifiers = defaults.stringArray(forKey: Self.enabledCalendarIDsKey) ?? []
        }
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--engine"), i + 1 < args.count, let picked = Engine(rawValue: args[i + 1]) {
            overridden = true
            engine = picked
        }
    }

    /// Empty storage falls back to the default. The client trims a trailing slash.
    var resolvedBaseURL: String {
        if engine.isBuiltin || engine == .picker { return engine.baseURL }
        return Self.stored(baseURL, fallback: Self.defaultBaseURL)
    }

    var resolvedModel: String {
        if engine.isBuiltin || engine == .picker { return engine.modelID }
        return Self.stored(model, fallback: Self.defaultModel)
    }

    func isCalendarEnabled(_ id: String) -> Bool {
        guard let enabled = enabledCalendarIdentifiers else { return true }
        return enabled.contains(id)
    }

    /// First toggle materializes every current calendar, then applies the change.
    func setCalendarEnabled(_ id: String, isOn: Bool, allIdentifiers: [String]) {
        var set: Set<String>
        if let existing = enabledCalendarIdentifiers {
            set = Set(existing)
        } else {
            set = Set(allIdentifiers)
            rememberKnown(allIdentifiers)
        }
        if isOn {
            set.insert(id)
        } else {
            set.remove(id)
        }
        enabledCalendarIdentifiers = Array(set).sorted()
    }

    /// Calendars that appear after a filter was saved default to on.
    func mergeNewCalendars(_ identifiers: [String]) {
        guard enabledCalendarIdentifiers != nil else {
            rememberKnown(identifiers)
            return
        }
        let current = Set(identifiers)
        let known = Set(defaults.stringArray(forKey: Self.knownCalendarIDsKey) ?? [])
        let newcomers = current.subtracting(known)
        if !newcomers.isEmpty {
            var enabled = Set(enabledCalendarIdentifiers ?? [])
            enabled.formUnion(newcomers)
            enabledCalendarIdentifiers = Array(enabled).sorted()
        }
        rememberKnown(Array(known.union(current)))
    }

    /// `nil` → every calendar (EventKit `calendars: nil`). Otherwise only the enabled ones that still exist.
    static func calendarsForEventQuery(
        store: EKEventStore,
        defaults: UserDefaults = .standard
    ) -> [EKCalendar]? {
        guard defaults.object(forKey: enabledCalendarIDsKey) != nil else { return nil }
        let enabled = Set(defaults.stringArray(forKey: enabledCalendarIDsKey) ?? [])
        let known = Set(defaults.stringArray(forKey: knownCalendarIDsKey) ?? [])
        // A calendar never seen when the list was saved counts as on.
        return store.calendars(for: .event).filter {
            enabled.contains($0.calendarIdentifier) || !known.contains($0.calendarIdentifier)
        }
    }

    private func rememberKnown(_ identifiers: [String]) {
        defaults.set(Array(Set(identifiers)).sorted(), forKey: Self.knownCalendarIDsKey)
    }

    private static func stored(_ raw: String?, fallback: String) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }
}
