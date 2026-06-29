//
//  AppState.swift
//  Noeron
//
//  Cross-view navigation state: which investigation, which workspace section, and
//  pending deep links arriving from Spotlight or App Intents.
//

import SwiftUI

/// The sections of an investigation workspace shown in the navigator.
enum WorkspaceSection: Hashable, Identifiable {
    case overview
    case kind(EntityKind)
    case timeline
    case graph
    case evidence
    case notes
    case reports
    case pluginLog

    var id: String {
        switch self {
        case .overview: "overview"
        case .kind(let k): "kind.\(k.rawValue)"
        case .timeline: "timeline"
        case .graph: "graph"
        case .evidence: "evidence"
        case .notes: "notes"
        case .reports: "reports"
        case .pluginLog: "pluginLog"
        }
    }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .kind(let k): k.pluralName
        case .timeline: "Timeline"
        case .graph: "Graph"
        case .evidence: "Evidence"
        case .notes: "Notes"
        case .reports: "Reports"
        case .pluginLog: "Plugin Log"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .kind(let k): k.symbolName
        case .timeline: "calendar.day.timeline.left"
        case .graph: "point.3.filled.connected.trianglepath.dotted"
        case .evidence: "tray.full"
        case .notes: "note.text"
        case .reports: "doc.richtext"
        case .pluginLog: "list.bullet.rectangle"
        }
    }
}

/// Deep link payload from Spotlight / App Intents / Handoff.
enum DeepLink: Equatable {
    case investigation(UUID)
    case entity(UUID)
}

@MainActor
final class AppState: ObservableObject {
    @Published var selectedInvestigationID: UUID?
    // Optional so the section list can deselect — on iPhone, returning from a
    // section pushed via NavigationSplitView must clear the selection, otherwise
    // re-tapping the same row does nothing (the binding never changes).
    @Published var selectedSection: WorkspaceSection? = .overview
    @Published var selectedEntityID: UUID?
    @Published var pendingDeepLink: DeepLink?
    @Published var showingNewInvestigation = false
    @Published var showingSettings = false

    func open(_ link: DeepLink) {
        pendingDeepLink = link
    }
}
