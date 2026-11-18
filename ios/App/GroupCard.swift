import SwiftUI

struct GroupCard: View {
    var group: SavedGroup
    var schedule: GroupSchedule?
    var problem: String? = nil
    var isLoading = false
    var showsToday: Bool
    var now: Date
    var isHighlighted = false
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text(group.name).font(.title3.weight(.bold)).foregroundStyle(Theme.fg)
                GroupChip(text: "група \(group.group)")
                Spacer(minLength: 0)
                Menu {
                    Button { onEdit() } label: { Label("Редагувати", systemImage: "pencil") }
                    Button(role: .destructive) { onDelete() } label: {
                        // Menus draw SF Symbols in the label colour; an always-original red image keeps the icon red
                        // like the title.
                        Label {
                            Text("Видалити")
                        } icon: {
                            Image(uiImage: UIImage(systemName: "trash")!.withTintColor(.systemRed, renderingMode: .alwaysOriginal))
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.subtle)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Дії з групою \(group.name)")
                .padding(.vertical, -10)
                .padding(.trailing, -10)
            }

            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
            if let schedule {
                content(schedule)
            } else if problem == nil {
                HStack(spacing: 8) {
                    if isLoading { ProgressView() }
                    Text(isLoading ? "Завантажуємо графік…" : "Графік ще не завантажено. Потягніть вниз, щоб оновити.")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(isHighlighted ? Theme.fg : Theme.border, lineWidth: isHighlighted ? 1.5 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private func content(_ schedule: GroupSchedule) -> some View {
        let day = showsToday ? schedule.today : schedule.tomorrow

        if showsToday, StatusText(schedule: schedule, now: now).hasData {
            let status = StatusText(schedule: schedule, now: now)
            HStack(spacing: 12) {
                PowerIcon(isOn: status.isOn, size: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.title).font(.headline).foregroundStyle(Theme.fg)
                    Text([status.next, status.countdown].filter { !$0.isEmpty }.joined(separator: ", "))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(Theme.muted)
                }
            }
            .accessibilityElement(children: .combine)
        }

        switch day.status {
        case .waiting:
            Label("Графік ще не опубліковано. Зазвичай він зʼявляється ввечері.", systemImage: "clock")
                .font(.subheadline).foregroundStyle(Theme.muted)
        case .emergency:
            Label("Екстрені вимкнення — графік зараз не діє.", systemImage: "exclamationmark.triangle")
                .font(.subheadline).foregroundStyle(Theme.danger)
        case .none:
            Label("Графіка на цей день немає. Оператор його ще не опублікував.", systemImage: "calendar.badge.exclamationmark")
                .font(.subheadline).foregroundStyle(Theme.muted)
        case .scheduled:
            TimelineBar(day: day, height: 16, showsHours: true, now: showsToday ? now : nil)
            details(day)
        }
    }

    private func details(_ day: DaySchedule) -> some View {
        let off = ScheduleMath.ranges(day, kind: .off)
        let maybe = ScheduleMath.ranges(day, kind: .maybe)
        return Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow {
                Text("Вимкнення").foregroundStyle(Theme.subtle)
                Text(off.isEmpty ? "немає" : off).fontWeight(.semibold).foregroundStyle(Theme.fg)
            }
            if !maybe.isEmpty {
                GridRow {
                    Text("Можливо").foregroundStyle(Theme.subtle)
                    Text(maybe).foregroundStyle(Theme.fg)
                }
            }
        }
        .font(.subheadline)
        .monospacedDigit()
    }
}

struct GroupChip: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

#Preview {
    VStack {
        GroupCard(group: DemoData.groups[0], schedule: DemoData.schedule(group: "3.2"), showsToday: true, now: .now)
        GroupCard(group: DemoData.groups[1], schedule: DemoData.schedule(group: "1.1"), showsToday: false, now: .now)
    }
    .padding()
    .background(Theme.bg)
}
