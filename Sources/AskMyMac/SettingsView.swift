import EventKit
import SwiftUI

/// Endpoint and model. The model list comes from GET <endpoint>/models.
struct SettingsView: View {
    @ObservedObject var settings: Settings
    @Environment(\.dismiss) private var dismiss
    @State private var client = OsaurusClient()
    @State private var models: [String] = []
    @State private var loading = false
    @State private var problem: String?
    @State private var eventCalendars: [EKCalendar] = []
    @State private var calendarAccessNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings")
                .font(.title2.weight(.semibold))
            Text("Chat stays on this Mac. Raptor runs in Osaurus; Spark and Bonsai run on their own, without Osaurus.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Engine")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Engine", selection: $settings.engine) {
                ForEach(Engine.allCases) { engine in
                    Text(engine.label).tag(engine)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: settings.engine) { _, picked in
                // Free memory right away; the chosen built-in loads on the next question.
                BuiltinEngine.select(picked)
            }
            if settings.engine == .picker {
                Text("Uses whatever model is picked in Model Picker (http://127.0.0.1:7777/v1). Model Picker starts the right engine for you. To go back to Raptor in Osaurus, choose \"Raptor (Osaurus)\" above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if settings.engine == .bonsai {
                Text("Bonsai uses about 9 GB of memory and answers around 11 words a second. Close big apps first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if settings.engine == .osaurus {
            Text("Endpoint")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(Settings.defaultBaseURL, text: $settings.baseURL)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .onSubmit { Task { await load() } }
            Text("Model")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Model", selection: $settings.model) {
                ForEach(choices, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let problem, settings.engine == .osaurus {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Calendars to read")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let calendarAccessNote {
                Text(calendarAccessNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(eventCalendars, id: \.calendarIdentifier) { calendar in
                    Toggle(isOn: calendarBinding(calendar)) {
                        Text(calendarTitle(calendar))
                    }
                    .toggleStyle(.checkbox)
                }
            }

            HStack {
                Button {
                    Task {
                        await load()
                        refreshCalendars()
                    }
                } label: {
                    if loading {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Refresh")
                    }
                }
                .disabled(loading)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(AskPalette.teal)
            }
        }
        .padding(20)
        .frame(width: 460)
        .task {
            if settings.engine == .osaurus { await load() }
            refreshCalendars()
        }
    }

    /// Current model stays selectable even before Refresh returns.
    private var choices: [String] {
        var list = Self.uniqueModels(models)
        let current = settings.resolvedModel
        if !list.contains(current) {
            list.insert(current, at: 0)
        }
        return list
    }

    private static func uniqueModels(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var list: [String] = []
        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            list.append(trimmed)
        }
        return list
    }

    private func load() async {
        guard !loading else { return }
        guard settings.engine == .osaurus else { return }
        loading = true
        defer { loading = false }
        problem = nil
        do {
            let found = Self.uniqueModels(try await client.listModels(baseURL: settings.resolvedBaseURL))
            models = found
            if found.isEmpty {
                problem = "That endpoint returned no models."
            } else if !found.contains(settings.resolvedModel) {
                settings.model = found[0]
            }
        } catch {
            models = []
            problem = "Couldn't reach that endpoint. Is Osaurus running?"
        }
    }

    private func refreshCalendars() {
        let status = EKEventStore.authorizationStatus(for: .event)
        guard status == .fullAccess else {
            eventCalendars = []
            calendarAccessNote = "Ask My Mac needs calendar access before it can list calendars. Turn it on in System Settings > Privacy & Security > Calendars."
            return
        }
        calendarAccessNote = nil
        let store = CalendarTools.store
        let list = store.calendars(for: .event).sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        settings.mergeNewCalendars(list.map(\.calendarIdentifier))
        eventCalendars = list
    }

    private func calendarTitle(_ calendar: EKCalendar) -> String {
        let title = calendar.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "(Untitled calendar)" : title
    }

    private func calendarBinding(_ calendar: EKCalendar) -> Binding<Bool> {
        let id = calendar.calendarIdentifier
        return Binding(
            get: { settings.isCalendarEnabled(id) },
            set: { isOn in
                let all = eventCalendars.map(\.calendarIdentifier)
                settings.setCalendarEnabled(id, isOn: isOn, allIdentifiers: all)
            }
        )
    }
}
