import SwiftUI
import TouchGrassCore

struct ScheduleEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Schedule
    private let isNew: Bool

    init(schedule: Schedule?, defaultBlockListID: UUID) {
        _draft = State(initialValue: schedule ?? Schedule(
            name: "",
            blockListID: defaultBlockListID,
            start: TimeOfDay(hour: 22),
            end: TimeOfDay(hour: 7)
        ))
        isNew = schedule == nil
    }

    var body: some View {
        let frozen = model.settingsFrozen()
        Form {
            Section("Name") {
                TextField("Bedtime", text: $draft.name)
            }
            Section {
                Picker("Block List", selection: $draft.blockListID) {
                    ForEach(model.state.upcomingRules.blockLists) { list in
                        Text(list.name).tag(list.id)
                    }
                }
                DatePicker("Starts", selection: $draft.start.date, displayedComponents: .hourAndMinute)
                DatePicker("Ends", selection: $draft.end.date, displayedComponents: .hourAndMinute)
                WeekdayPicker(weekdays: $draft.weekdays)
                Toggle("On", isOn: $draft.isEnabled)
            } footer: {
                if draft.crossesMidnight {
                    Text("Ends the next morning.")
                }
            }
            if !isNew {
                Section {
                    Button("Delete Schedule", role: .destructive) {
                        let id = draft.id
                        model.changeRules { $0.schedules.removeAll { $0.id == id } }
                        dismiss()
                    }
                }
            }
        }
        .disabled(frozen)
        .navigationTitle(isNew ? "New Schedule" : draft.name)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let schedule = draft
                    model.changeRules { rules in
                        if let index = rules.schedules.firstIndex(where: { $0.id == schedule.id }) {
                            rules.schedules[index] = schedule
                        } else {
                            rules.schedules.append(schedule)
                        }
                    }
                    dismiss()
                }
                .disabled(frozen || !isValid)
            }
        }
    }

    /// DeviceActivity needs windows of at least 15 minutes.
    private var isValid: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
            && !draft.weekdays.isEmpty
            && draft.start != draft.end
            && draft.durationMinutes >= 15
    }
}

private struct WeekdayPicker: View {
    @Binding var weekdays: Set<Int>
    private let symbols = Calendar.current.veryShortWeekdaySymbols

    var body: some View {
        HStack {
            ForEach(Self.orderedWeekdays, id: \.self) { weekday in
                let isOn = weekdays.contains(weekday)
                Button(symbols[weekday - 1]) {
                    if isOn { weekdays.remove(weekday) } else { weekdays.insert(weekday) }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(isOn ? Theme.grass : Color.secondary.opacity(0.2), in: .circle)
                .foregroundStyle(isOn ? Theme.soil : .primary)
            }
        }
    }

    /// Weekdays in the order the user's calendar starts the week.
    private static var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }
}

extension TimeOfDay {
    /// Bridges to `DatePicker`, which edits a full date.
    var date: Date {
        get { Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now }
        set {
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            self = TimeOfDay(hour: components.hour ?? 0, minute: components.minute ?? 0)
        }
    }

    var formatted: String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

extension Schedule {
    var summary: String {
        let days: String
        switch weekdays {
        case Schedule.everyDay: days = "Every day"
        case [2, 3, 4, 5, 6]: days = "Weekdays"
        case [1, 7]: days = "Weekends"
        default:
            let symbols = Calendar.current.shortWeekdaySymbols
            days = weekdays.sorted().map { symbols[$0 - 1] }.joined(separator: ", ")
        }
        return "\(start.formatted)–\(end.formatted) · \(days)"
    }
}
