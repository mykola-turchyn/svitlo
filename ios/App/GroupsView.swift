import SwiftUI

/// "Мої групи": cards with today's/tomorrow's schedule.
/// Long-press and drag to reorder, swipe right to edit, swipe left to delete.
struct GroupsView: View {
    @Environment(AppModel.self) private var model
    @State private var day: Day = .today
    @State private var isAdding = false
    @State private var editing: SavedGroup?
    @State private var pendingDelete: SavedGroup?

    enum Day: Hashable { case today, tomorrow }

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                ScrollViewReader { proxy in
                    List {
                        header
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 4, trailing: 20))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)

                        ForEach(model.groups) { group in
                            GroupCard(
                                group: group,
                                schedule: model.schedule(for: group),
                                problem: model.problem(for: group),
                                isLoading: model.isRefreshing,
                                showsToday: day == .today,
                                now: context.date,
                                isHighlighted: model.highlightedGroup == group.id,
                                onEdit: { editing = group },
                                onDelete: { pendingDelete = group }
                            )
                            .id(group.id)
                            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) { pendingDelete = group } label: {
                                    Label("Видалити", systemImage: "trash")
                                }
                                // The app-wide tint is the text colour (cream in dark mode); keep delete red.
                                .tint(Theme.danger)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button { editing = group } label: {
                                    Label("Змінити", systemImage: "pencil")
                                }
                                .tint(Theme.off)
                            }
                        }
                        .onMove { model.move(from: $0, to: $1) }

                        if !model.groups.isEmpty {
                            TimelineLegend()
                                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 24, trailing: 20))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .onChange(of: model.highlightedGroup) { _, id in
                        if let id { withAnimation { proxy.scrollTo(id, anchor: .top) } }
                    }
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .overlay { if model.groups.isEmpty { emptyState } }
            .navigationTitle("Світло")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if model.isRefreshing { ProgressView() }
                }
            }
            .refreshable { await model.refresh() }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .sheet(isPresented: $isAdding) { GroupEditorView(mode: .add) }
            .sheet(item: $editing) { GroupEditorView(mode: .edit($0)) }
            .alert(
                deleteTitle,
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                presenting: pendingDelete
            ) { group in
                Button("Видалити", role: .destructive) { withAnimation { model.delete(group) } }
                Button("Скасувати", role: .cancel) {}
            } message: { group in
                Text("Зникнуть графік і сповіщення для групи \(group.group). Віджети покажуть інші ваші групи.")
            }
        }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(Theme.subtle)

            Picker("День", selection: $day) {
                Text("Сьогодні").tag(Day.today)
                Text("Завтра").tag(Day.tomorrow)
            }
            .pickerStyle(.segmented)

            if let error = model.errorMessage {
                Label(error, systemImage: "wifi.exclamationmark")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            } else if model.groups.count > 1 {
                Label("Утримуйте картку, щоб змінити порядок. Свайп вправо — змінити, вліво — видалити.",
                      systemImage: "arrow.up.and.down")
                    .font(.footnote)
                    .foregroundStyle(Theme.subtle)
            }
        }
    }

    private var subtitle: String {
        let date = Date.now.formatted(.dateTime.weekday(.abbreviated).day().month(.wide).locale(Locale(identifier: "uk_UA")))
        guard let fetchedAt = model.fetchedAt else { return date }
        return "\(date) · оновлено \(ScheduleMath.hhmm(fetchedAt))"
    }

    private var deleteTitle: String {
        pendingDelete.map { "Видалити «\($0.name)»?" } ?? ""
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if let deleted = model.recentlyDeleted {
                UndoBar(name: deleted.group.name) { withAnimation { model.undoDelete() } }
                    .task(id: deleted.group.id) {
                        try? await Task.sleep(for: .seconds(5))
                        withAnimation { model.clearUndo() }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Button { isAdding = true } label: {
                Label("Додати групу", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.primaryFg)
            .background(Theme.primary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Theme.bg.opacity(0.95))
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Додайте першу групу", systemImage: "lightbulb")
        } description: {
            Text("Оберіть регіон і свою групу відключень, щоб бачити графік, віджет і отримувати сповіщення.")
        }
    }
}

private struct UndoBar: View {
    var name: String
    var undo: () -> Void

    var body: some View {
        HStack {
            Text("Групу «\(name)» видалено").font(.subheadline)
            Spacer()
            Button("Повернути", action: undo)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.on)
                .frame(minHeight: 44)
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .foregroundStyle(Theme.surface)
        .background(Theme.fg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
