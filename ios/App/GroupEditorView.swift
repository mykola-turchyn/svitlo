import SwiftUI

/// Add a new group or edit an existing one (same screen, as in the design).
struct GroupEditorView: View {
    enum Mode {
        case add
        case edit(SavedGroup)
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    @State private var draft: SavedGroup
    @State private var availableGroups = KnownRegions.defaultGroups
    @State private var preview: GroupSchedule?
    @State private var isLoadingPreview = false
    @State private var confirmDelete = false

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .add: _draft = State(initialValue: SavedGroup(name: "", regionId: KnownRegions.all[0].id, group: "1.1"))
        case .edit(let group): _draft = State(initialValue: group)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Назва") {
                    TextField("Наприклад, Дім або Офіс", text: $draft.name)
                        .textInputAutocapitalization(.sentences)
                }

                Section("Регіон") {
                    NavigationLink {
                        RegionPickerView(regions: model.regions, selection: $draft.regionId)
                    } label: {
                        LabeledContent("Регіон", value: model.regions.first { $0.id == draft.regionId }?.name ?? draft.regionId)
                    }
                }

                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(availableGroups, id: \.self) { group in
                            GroupChoice(title: group, isSelected: draft.group == group) { draft.group = group }
                        }
                    }
                    .padding(.vertical, 4)

                    Link(destination: URL(string: "https://www.yasno.ua")!) {
                        Label("Не знаєте групу? Знайти за адресою", systemImage: "mappin.and.ellipse")
                    }
                } header: {
                    Text("Група відключень")
                } footer: {
                    Text("Групу можна дізнатися на сайті постачальника за адресою.")
                }

                Section("Група \(draft.group) сьогодні") {
                    if let preview {
                        TimelineBar(day: preview.today, height: 14, showsHours: true, now: .now)
                            .padding(.vertical, 4)
                        let off = ScheduleMath.ranges(preview.today, kind: .off)
                        Text("Вимкнення: \(off.isEmpty ? "немає" : off)")
                            .font(.subheadline).monospacedDigit()
                    } else if isLoadingPreview {
                        ProgressView()
                    } else {
                        Text("Графік недоступний").foregroundStyle(Theme.muted)
                    }
                }

                Section("Сповіщення") {
                    Toggle(isOn: $draft.notifyBeforeOff) {
                        VStack(alignment: .leading) {
                            Text("Перед вимкненням")
                            Text("За 30 хвилин").font(.footnote).foregroundStyle(Theme.subtle)
                        }
                    }
                    Toggle(isOn: $draft.notifyOnReturn) {
                        VStack(alignment: .leading) {
                            Text("Коли світло повернеться")
                            Text("За графіком").font(.footnote).foregroundStyle(Theme.subtle)
                        }
                    }
                }
                .tint(Theme.on)

                if isEditing {
                    Section {
                        Button("Видалити групу", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(isEditing ? "Редагувати групу" : "Нова група")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Скасувати") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Зберегти" : "Додати") { save() }
                        .disabled(!canSave)
                }
            }
            .task(id: draft.regionId) {
                availableGroups = await model.availableGroups(region: draft.regionId)
                if !availableGroups.contains(draft.group), let first = availableGroups.first { draft.group = first }
            }
            .task(id: draft.scheduleKey) {
                isLoadingPreview = true
                preview = await model.preview(region: draft.regionId, group: draft.group)
                isLoadingPreview = false
            }
            .alert("Видалити «\(draft.name)»?", isPresented: $confirmDelete) {
                Button("Видалити", role: .destructive) {
                    if case .edit(let original) = mode { model.delete(original) }
                    dismiss()
                }
                Button("Скасувати", role: .cancel) {}
            } message: {
                Text("Зникнуть графік і сповіщення для групи \(draft.group).")
            }
        }
    }

    private func save() {
        draft.name = draft.name.trimmingCharacters(in: .whitespaces)
        let group = draft
        if isEditing { model.update(group) } else { model.add(group) }
        if group.notifyBeforeOff || group.notifyOnReturn {
            Task { await NotificationScheduler.requestAuthorization() }
        }
        dismiss()
    }
}

private struct GroupChoice: View {
    var title: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(isSelected ? Theme.primaryFg : Theme.fg)
                .background(isSelected ? Theme.primary : Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isSelected ? Theme.primary : Theme.border)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Група \(title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
