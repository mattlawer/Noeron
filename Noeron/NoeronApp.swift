//
//  NoeronApp.swift
//  Noeron — The intelligence workspace for digital investigations.
//
//  Universal SwiftUI app (macOS · iPadOS · iOS) backed by SwiftData + CloudKit.
//

import SwiftUI
import SwiftData
import CoreSpotlight

@main
struct NoeronApp: App {
    /// Shared SwiftData container (CloudKit-mirrored private database).
    let container: ModelContainer

    @StateObject private var appState = AppState()
    @StateObject private var registry = PluginRegistry.shared
    @StateObject private var engine = DiscoveryEngine()

    init() {
        // Demo mode (screenshots / UI tests) runs on a clean in-memory store.
        let container = DemoData.isEnabled ? NoeronSchema.makeContainer(inMemory: true) : NoeronSchema.shared
        self.container = container
        // Keep Spotlight in sync with the store in the background.
        if !DemoData.isEnabled { SpotlightIndexer.shared.attach(container: container) }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(registry)
                .environmentObject(engine)
                .tint(Theme.accent)
                .task { await SpotlightIndexer.shared.reindexAll() }
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    handleSpotlight(activity)
                }
                .onContinueUserActivity("com.noeron.app.openInvestigation") { activity in
                    if let id = (activity.userInfo?["id"] as? String).flatMap(UUID.init) {
                        appState.open(.investigation(id))
                    }
                }
                .onContinueUserActivity("com.noeron.app.openEntity") { activity in
                    if let id = (activity.userInfo?["id"] as? String).flatMap(UUID.init) {
                        appState.open(.entity(id))
                    }
                }
        }
        .modelContainer(container)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Investigation") { appState.showingNewInvestigation = true }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Button("Open Graph") { appState.selectedSection = .graph }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
            }
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(registry)
                .environmentObject(engine)
                .frame(minWidth: 640, minHeight: 480)
        }
        #endif
    }

    private func handleSpotlight(_ activity: NSUserActivity) {
        guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
        if let id = SpotlightIndexer.entityID(from: identifier) {
            appState.open(.entity(id))
        } else if let id = SpotlightIndexer.investigationID(from: identifier) {
            appState.open(.investigation(id))
        }
    }
}
