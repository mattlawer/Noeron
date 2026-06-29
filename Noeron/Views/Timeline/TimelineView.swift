//
//  TimelineView.swift
//  Noeron
//
//  Chronological view of every dated fact plugins contributed, grouped by year.
//

import SwiftUI
import SwiftData

struct TimelineView: View {
    @Bindable var investigation: Investigation
    @Environment(\.modelContext) private var modelContext
    @State private var showAdd = false

    private struct YearGroup: Identifiable {
        let year: Int
        let events: [TimelineEvent]
        var id: Int { year }
    }

    private var grouped: [YearGroup] {
        let groups = Dictionary(grouping: investigation.eventsArray, by: \.year)
        return groups.keys.sorted().map { YearGroup(year: $0, events: groups[$0]!.sorted { $0.date < $1.date }) }
    }

    var body: some View {
        ScrollView {
            if investigation.eventsArray.isEmpty {
                ContentUnavailableView("No timeline events", systemImage: "calendar.day.timeline.left",
                                       description: Text("Run discovery — WHOIS, certificates, breaches and accounts add dated events automatically."))
                    .padding(.top, 80)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(grouped) { group in
                        yearHeader(group.year)
                        ForEach(group.events) { event in
                            TimelineRow(event: event)
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
            }
        }
        .navigationTitle("Timeline")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: { Label("Add Event", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) { AddEventSheet(investigation: investigation) }
    }

    private func yearHeader(_ year: Int) -> some View {
        Text(String(year))
            .font(.title3.bold().monospacedDigit())
            .foregroundStyle(Theme.accent)
            .padding(.top, 18).padding(.bottom, 6)
    }
}

private struct TimelineRow: View {
    let event: TimelineEvent
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Circle().fill(Theme.accent).frame(width: 10, height: 10).padding(.top, 4)
                Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: 1.5)
            }
            .frame(width: 12)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.displayDate).font(.caption.monospaced()).foregroundStyle(.secondary)
                content
            }
            .padding(.bottom, 14)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var content: some View {
        let body = VStack(alignment: .leading, spacing: 4) {
            Text(event.title).font(.subheadline.weight(.medium))
            HStack(spacing: 6) {
                if !event.category.isEmpty {
                    Text(event.category).font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.accent.opacity(0.18)))
                        .foregroundStyle(Theme.accent)
                }
                if !event.sourcePlugin.isEmpty {
                    Text(event.sourcePlugin).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            if !event.detail.isEmpty {
                Text(event.detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        if let entity = event.entity {
            NavigationLink(value: entity) { body }.buttonStyle(.plain)
        } else {
            body
        }
    }
}

struct AddEventSheet: View {
    @Bindable var investigation: Investigation
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var date = Date()
    @State private var category = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                DatePicker("Date", selection: $date, displayedComponents: .date)
                TextField("Category", text: $category)
            }
            .formStyle(.grouped)
            .navigationTitle("Add Event")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let e = TimelineEvent(title: title, date: date, category: category, sourcePlugin: "Manual")
                        modelContext.insert(e); e.investigation = investigation
                        try? modelContext.save(); dismiss()
                    }.disabled(title.isEmpty)
                }
            }
        }
        .frame(minWidth: 380, minHeight: 280)
    }
}
