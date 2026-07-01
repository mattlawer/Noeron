//
//  ReportModelTests.swift
//  NoeronTests
//
//  Verifies report scoping (full vs. subgraph), discard inclusion, the
//  confidence floor, and that links/events are induced by the included set.
//

import XCTest
import SwiftData
@testable import Noeron

@MainActor
final class ReportModelTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(NoeronSchema.makeContainer(inMemory: true))
    }

    /// person —hasEmail→ email —relatedTo→ domain, plus a discarded low-conf node.
    private func seed(_ ctx: ModelContext) -> (Investigation, Entity, Entity, Entity, Entity) {
        let inv = Investigation(title: "T"); ctx.insert(inv)
        let person = Entity(kind: .person, label: "Mathieu", confidence: 0.9); ctx.insert(person); person.investigation = inv
        let email = Entity(kind: .email, label: "m@x.com", confidence: 0.8); ctx.insert(email); email.investigation = inv
        let domain = Entity(kind: .domain, label: "x.com", confidence: 0.4); ctx.insert(domain); domain.investigation = inv
        let noise = Entity(kind: .username, label: "noise", confidence: 0.2); ctx.insert(noise)
        noise.investigation = inv; noise.discarded = true

        let l1 = EntityLink(kind: .hasEmail, source: person, target: email); ctx.insert(l1); l1.investigation = inv
        let l2 = EntityLink(kind: .relatedTo, source: email, target: domain); ctx.insert(l2); l2.investigation = inv

        let ev = TimelineEvent(title: "seen", date: Date(timeIntervalSince1970: 1), entity: email)
        ctx.insert(ev); ev.investigation = inv
        try? ctx.save()
        return (inv, person, email, domain, noise)
    }

    func testFullScopeHidesDiscardedByDefault() throws {
        let ctx = try makeContext()
        let (inv, _, _, _, _) = seed(ctx)
        let m = ReportModel(inv)
        XCTAssertEqual(m.totalEntities, 3)              // discarded excluded
        XCTAssertEqual(m.discardedCount, 0)
        XCTAssertEqual(m.links.count, 2)
    }

    func testIncludeDiscardedFlagsThem() throws {
        let ctx = try makeContext()
        let (inv, _, _, _, _) = seed(ctx)
        let m = ReportModel(inv, options: ReportOptions(includeDiscarded: true))
        XCTAssertEqual(m.totalEntities, 4)
        XCTAssertEqual(m.discardedCount, 1)
    }

    func testMinConfidenceDropsWeakActiveNodes() throws {
        let ctx = try makeContext()
        let (inv, _, _, _, _) = seed(ctx)
        let m = ReportModel(inv, options: ReportOptions(minConfidence: 0.5))
        // domain (0.4) dropped; person + email remain.
        XCTAssertEqual(m.totalEntities, 2)
        // The email→domain link is no longer induced (domain gone).
        XCTAssertEqual(m.links.count, 1)
    }

    func testSubgraphInducesLinksAndEvents() throws {
        let ctx = try makeContext()
        let (inv, person, email, _, _) = seed(ctx)
        let m = ReportModel(inv, options: ReportOptions(scope: .subgraph([person.id, email.id])))
        XCTAssertEqual(m.totalEntities, 2)
        // Only person—email survives; email—domain excluded (domain not selected).
        XCTAssertEqual(m.links.count, 1)
        // The event is tied to email, which is in scope.
        XCTAssertEqual(m.events.count, 1)
    }

    func testSubgraphExcludesOutOfScopeEvents() throws {
        let ctx = try makeContext()
        let (inv, person, _, domain, _) = seed(ctx)
        let m = ReportModel(inv, options: ReportOptions(scope: .subgraph([person.id, domain.id])))
        XCTAssertEqual(m.totalEntities, 2)
        XCTAssertEqual(m.links.count, 0)   // no direct person—domain link
        XCTAssertEqual(m.events.count, 0)  // the only event belongs to email
    }

    func testAverageConfidenceIgnoresDiscarded() throws {
        let ctx = try makeContext()
        let (inv, _, _, _, _) = seed(ctx)
        let m = ReportModel(inv, options: ReportOptions(includeDiscarded: true))
        // Average over active only: (0.9 + 0.8 + 0.4) / 3 = 0.7
        XCTAssertEqual(m.averageConfidence, 0.7, accuracy: 0.001)
    }
}
