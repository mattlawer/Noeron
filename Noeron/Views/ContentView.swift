//
//  ContentView.swift
//  Noeron
//
//  Three-column workspace: investigations · section navigator · section content.
//  Collapses to stack navigation on iPhone automatically.
//

import SwiftUI
import SwiftData
import Combine

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \Investigation.updatedAt, order: .reverse) private var investigations: [Investigation]

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var dedupedInvestigationIDs: Set<UUID> = []

    private var selectedInvestigation: Investigation? {
        investigations.first { $0.id == appState.selectedInvestigationID }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            InvestigationListView(selection: $appState.selectedInvestigationID)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        } content: {
            if let investigation = selectedInvestigation {
                WorkspaceNavigator(investigation: investigation, selection: $appState.selectedSection)
                    .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            } else {
                ContentUnavailableView("No Investigation",
                                       systemImage: "folder.badge.questionmark",
                                       description: Text("Select or create an investigation to begin."))
            }
        } detail: {
            if let investigation = selectedInvestigation, let section = appState.selectedSection {
                SectionDetailView(investigation: investigation, section: section)
                    .id(section.id + (appState.selectedInvestigationID?.uuidString ?? ""))
            } else if selectedInvestigation != nil {
                ContentUnavailableView("Select a section",
                                       systemImage: "square.grid.2x2",
                                       description: Text("Pick a section to view."))
            } else {
                WelcomeView()
            }
        }
        .overlay(alignment: .bottom) { undoToast }
        .sheet(isPresented: $appState.showingNewInvestigation) {
            NewInvestigationSheet { newID in
                appState.selectedInvestigationID = newID
                appState.selectedSection = .overview
            }
        }
        #if !os(macOS)
        .sheet(isPresented: $appState.showingSettings) {
            NavigationStack { SettingsView() }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        #endif
        .onChange(of: appState.pendingDeepLink) { _, link in
            if let link { resolve(link); appState.pendingDeepLink = nil }
        }
        .onReceive(IntentRouter.shared.deepLinks) { link in resolve(link) }
        .onChange(of: appState.selectedInvestigationID) { _, _ in dedupeTimelineIfNeeded() }
        .onAppear {
            if DemoData.isEnabled { setUpDemoIfNeeded() }
            if appState.selectedInvestigationID == nil { appState.selectedInvestigationID = investigations.first?.id }
            dedupeTimelineIfNeeded()
        }
    }

    /// Seeds the demo investigation and opens the requested screen (screenshots / UI tests).
    private func setUpDemoIfNeeded() {
        let inv = investigations.first ?? DemoData.seed(into: modelContext)
        appState.selectedInvestigationID = inv.id
        switch DemoData.screen {
        case "overview": appState.selectedSection = .overview
        case "timeline": appState.selectedSection = .timeline
        default: appState.selectedSection = .graph
        }
    }

    /// Run the one-time timeline cleanup the first time each investigation is opened
    /// this session (removes duplicate events persisted before dedup existed).
    private func dedupeTimelineIfNeeded() {
        guard let investigation = selectedInvestigation,
              dedupedInvestigationIDs.insert(investigation.id).inserted else { return }
        DiscoveryEngine.dedupeTimeline(investigation, modelContext: modelContext)
    }

    // MARK: Undo toast for discards

    @ViewBuilder
    private var undoToast: some View {
        if let e = appState.lastDiscarded {
            HStack(spacing: 12) {
                Image(systemName: "trash").foregroundStyle(.secondary)
                Text("Discarded “\(e.label)”").lineLimit(1)
                Button("Undo") { undoDiscard(e) }.fontWeight(.semibold)
                Button { withAnimation { appState.lastDiscarded = nil } } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(radius: 5, y: 2)
            .padding(.bottom, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: e.id) {
                try? await Task.sleep(for: .seconds(6))
                if appState.lastDiscarded?.id == e.id { withAnimation { appState.lastDiscarded = nil } }
            }
        }
    }

    private func undoDiscard(_ e: Entity) {
        e.discarded = false
        e.updatedAt = Date()
        try? modelContext.save()
        withAnimation { appState.lastDiscarded = nil }
    }

    private func resolve(_ link: DeepLink) {
        switch link {
        case .investigation(let id):
            appState.selectedInvestigationID = id
            appState.selectedSection = .overview
        case .entity(let id):
            if let entity = fetchEntity(id) {
                appState.selectedInvestigationID = entity.investigation?.id
                appState.selectedSection = .kind(entity.kind)
                appState.selectedEntityID = id
            }
        }
    }

    private func fetchEntity(_ id: UUID) -> Entity? {
        let descriptor = FetchDescriptor<Entity>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    @EnvironmentObject private var appState: AppState
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                .font(.system(size: 56))
                .foregroundStyle(Theme.accent)
            Text("Noeron").font(.largeTitle.bold())
            Text("The intelligence workspace for digital investigations.")
                .foregroundStyle(.secondary)
            Button {
                appState.showingNewInvestigation = true
            } label: {
                Label("New Investigation", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
