import SwiftUI

/// All regions of Ukraine with search. Regions without an open schedule source are shown but cannot be chosen.
struct RegionPickerView: View {
    let regions: [Region]
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [Region] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return regions }
        return regions.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.operator.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        List {
            let available = filtered.filter(\.available)
            let unavailable = filtered.filter { !$0.available }

            if !available.isEmpty {
                Section {
                    ForEach(available) { region in
                        Button {
                            selection = region.id
                            dismiss()
                        } label: {
                            row(region, selected: region.id == selection)
                        }
                        .foregroundStyle(Theme.fg)
                    }
                }
            }

            if !unavailable.isEmpty {
                Section {
                    ForEach(unavailable) { region in
                        row(region, selected: false)
                            .opacity(0.5)
                            .accessibilityHint("Графік для цього регіону поки недоступний")
                    }
                } header: {
                    Text("Поки без графіка")
                } footer: {
                    Text("Для цих областей ще немає відкритого джерела графіків. Ми додамо їх, щойно воно зʼявиться.")
                }
            }
        }
        .overlay {
            if filtered.isEmpty { ContentUnavailableView.search(text: query) }
        }
        .searchable(text: $query, prompt: "Область або оператор")
        .navigationTitle("Регіон")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ region: Region, selected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(region.name)
                Text(region.operator).font(.footnote).foregroundStyle(Theme.subtle)
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark").fontWeight(.semibold).accessibilityLabel("Вибрано")
            }
        }
        .contentShape(Rectangle())
    }
}
