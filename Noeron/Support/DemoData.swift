//
//  DemoData.swift
//  Noeron
//
//  Builds a self-contained, offline demo investigation for screenshots and UI
//  tests. Activated only when the process is launched with the NOERON_DEMO
//  environment variable (see NoeronApp). No network is used.
//

import Foundation
import SwiftData

enum DemoData {
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["NOERON_DEMO"] == "1" }

    /// Which screen the demo should open on: "graph", "overview", "timeline".
    static var screen: String { ProcessInfo.processInfo.environment["NOERON_DEMO_SCREEN"] ?? "graph" }

    /// Seeds a believable investigation around the demo selectors and returns it.
    @MainActor
    @discardableResult
    static func seed(into context: ModelContext) -> Investigation {
        let inv = Investigation(title: "Mathieu BOLARD", summary: "Demo investigation",
                                caseNumber: "DEMO-001", classification: "Investigation")
        inv.colorHex = "#21C7BC"
        context.insert(inv)

        func node(_ kind: EntityKind, _ label: String, _ subtitle: String = "",
                  _ confidence: Double = 0.9, seed: Bool = false, source: String = "", url: String = "") -> Entity {
            let e = Entity(kind: kind, label: label, subtitle: subtitle, confidence: confidence,
                           isSeed: seed, sourcePlugin: source, sourceURL: url)
            context.insert(e); e.investigation = inv
            return e
        }
        func link(_ k: LinkKind, _ a: Entity, _ b: Entity, _ c: Double = 0.9, _ plugin: String = "") {
            let l = EntityLink(kind: k, source: a, target: b, confidence: c, sourcePlugin: plugin)
            context.insert(l); l.investigation = inv
        }
        func event(_ title: String, _ y: Int, _ m: Int, _ d: Int, _ category: String) {
            var c = DateComponents(); c.year = y; c.month = m; c.day = d
            let date = Calendar.current.date(from: c) ?? Date()
            let te = TimelineEvent(title: title, date: date, precision: .day, category: category, sourcePlugin: "Demo")
            context.insert(te); te.investigation = inv
        }

        // Seeds
        let person = node(.person, "Mathieu BOLARD", "Subject", 1.0, seed: true, source: "Manual entry")
        let email  = node(.email, "mathieu.bolard@gmail.com", "Free webmail", 1.0, seed: true, source: "Manual entry")
        let userA  = node(.username, "mattlawer", "Derived / linked", 0.85, seed: true, source: "Manual entry")
        let userB  = node(.username, "mathieu.bolard", "Email local part", 0.5, seed: true, source: "Manual entry")

        // Email Intelligence + Gravatar fan-out
        let gravatar = node(.person, "Mathieu Bolard", "Gravatar profile", 0.75, source: "Gravatar",
                            url: "https://gravatar.com/mattlawer")
        let location = node(.location, "Tours, France", "Self-reported", 0.5, source: "Gravatar")
        let breach   = node(.breach, "Tumblr", "tumblr.com · 2013", 0.85, source: "XposedOrNot")

        // Username sweep / GitHub
        let github   = node(.url, "https://github.com/mattlawer", "GitHub · Dev", 0.85, source: "GitHub")
        let reddit   = node(.url, "https://reddit.com/u/mattlawer", "Reddit · Social", 0.7, source: "Username Sweep")
        let spotify  = node(.url, "https://open.spotify.com", "Spotify account exists", 0.75, source: "Account Existence")
        let company  = node(.company, "LaCentralePharma", "Employer (LinkedIn)", 0.6, source: "Company Registry")
        let domain   = node(.domain, "lacentralepharma.fr", "Company website", 0.6, source: "Company Registry")

        // Links
        link(.hasEmail, person, email, 0.95)
        link(.hasUsername, email, userA, 0.6)
        link(.hasUsername, email, userB, 0.45)
        link(.hasUsername, person, userA, 0.7)
        link(.hasEmail, gravatar, email, 0.75, "Gravatar")
        link(.relatedTo, email, location, 0.5, "Gravatar")
        link(.appearsIn, email, breach, 0.85, "XposedOrNot")
        link(.relatedTo, userA, github, 0.8)
        link(.relatedTo, userA, reddit, 0.7)
        link(.relatedTo, email, spotify, 0.75)
        link(.memberOf, person, company, 0.6)
        link(.relatedTo, company, domain, 0.6)

        // Timeline
        event("GitHub account created: @mattlawer", 2010, 1, 11, "Account")
        event("Email in breach: Tumblr", 2013, 2, 28, "Breach")
        event("Most recent activity", 2024, 9, 3, "On-chain")

        try? context.save()
        return inv
    }
}
