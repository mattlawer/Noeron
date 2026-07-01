//
//  EntityMergeTests.swift
//  NoeronTests
//
//  Verifies EntityMerge re-points links, unions attributes, and removes the source.
//

import XCTest
import SwiftData
@testable import Noeron

@MainActor
final class EntityMergeTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(NoeronSchema.makeContainer(inMemory: true))
    }

    func testMergeRepointsLinksAndUnionsAttributes() throws {
        let ctx = try makeContext()
        let inv = Investigation(title: "T"); ctx.insert(inv)

        let a = Entity(kind: .person, label: "Mathieu Bolard", confidence: 0.6); ctx.insert(a); a.investigation = inv
        let b = Entity(kind: .person, label: "mattlawer", confidence: 0.8); ctx.insert(b); b.investigation = inv
        let email = Entity(kind: .email, label: "x@y.com"); ctx.insert(email); email.investigation = inv

        // a —hasEmail→ email ; a has a fact.
        let link = EntityLink(kind: .hasEmail, source: a, target: email); ctx.insert(link); link.investigation = inv
        a.setAttribute("GitHub", "https://github.com/mattlawer", kind: .url)
        try? ctx.save()

        EntityMerge.merge(a, into: b, in: inv, context: ctx)

        // Source gone, target kept.
        XCTAssertFalse(inv.entitiesArray.contains { $0.id == a.id })
        XCTAssertTrue(inv.entitiesArray.contains { $0.id == b.id })
        // The email link now belongs to b.
        XCTAssertEqual(link.source?.id, b.id)
        XCTAssertTrue(b.outgoing.contains { $0.target?.id == email.id })
        // Attribute carried over, and the stronger confidence kept.
        XCTAssertTrue(b.attributes.contains { $0.key == "GitHub" })
        XCTAssertEqual(b.confidence, 0.8, accuracy: 0.001)
    }
}
