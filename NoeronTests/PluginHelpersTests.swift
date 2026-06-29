//
//  PluginHelpersTests.swift
//  NoeronTests
//
//  Deterministic, offline unit tests for the pure plugin/intelligence helpers.
//  No network — these exercise parsing, classification and de-duplication logic.
//

import XCTest
@testable import Noeron

final class CryptoAddressTests: XCTestCase {
    func testEthereum() {
        XCTAssertEqual(CryptoAddress.chain(of: "0x" + String(repeating: "a", count: 40)), .ethereum)
        XCTAssertNil(CryptoAddress.chain(of: "0x123"))           // too short
    }
    func testBitcoin() {
        XCTAssertEqual(CryptoAddress.chain(of: "bc1q9d4ywgfnd8h43da5tpcxcn6ajv590cg6d3tg6axemvljvt2k76zs50tv4q"), .bitcoin)
        XCTAssertEqual(CryptoAddress.chain(of: "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"), .bitcoin)
    }
    func testSolana() {
        XCTAssertEqual(CryptoAddress.chain(of: "DRpbCBMxVnDK7maPM5tGv6MvB3v1sRMC86PZ8okm21hy"), .solana)
    }
    func testRejectsJunk() {
        XCTAssertNil(CryptoAddress.chain(of: "hello world"))
        XCTAssertNil(CryptoAddress.chain(of: "not-an-address!!"))
    }
    func testShort() {
        XCTAssertEqual(CryptoAddress.short("0x1234567890abcdef"), "0x123456…cdef")
        XCTAssertEqual(CryptoAddress.short("short"), "short")
    }
}

final class EmailIntelTests: XCTestCase {
    func testParts() {
        let p = EmailIntel.parts(of: "John.Doe+Tag@Example.COM")
        XCTAssertEqual(p?.local, "john.doe+tag")
        XCTAssertEqual(p?.domain, "example.com")
        XCTAssertNil(EmailIntel.parts(of: "not-an-email"))
        XCTAssertNil(EmailIntel.parts(of: "a@b"))                // no dot in domain
    }
    func testBaseLocal() {
        XCTAssertEqual(EmailIntel.baseLocal("john+news"), "john")
        XCTAssertEqual(EmailIntel.baseLocal("jane"), "jane")
    }
    func testMailHost() {
        XCTAssertEqual(EmailIntel.mailHost(forMX: ["aspmx.l.google.com"]), "Google Workspace / Gmail")
        XCTAssertEqual(EmailIntel.mailHost(forMX: ["mx.example.proofpoint.com"]), "Proofpoint (gateway)")
        XCTAssertNil(EmailIntel.mailHost(forMX: ["mail.self-hosted.example"]))
    }
}

final class InfraFilterTests: XCTestCase {
    func testInfrastructure() {
        XCTAssertTrue(InfraFilter.isInfrastructure("ns1.google.com"))
        XCTAssertTrue(InfraFilter.isInfrastructure("aspmx.l.google.com"))
        XCTAssertTrue(InfraFilter.isInfrastructure("ns-123.awsdns-45.org"))
        XCTAssertFalse(InfraFilter.isInfrastructure("mail.acme.com"))
    }
    func testFreeWebmail() {
        XCTAssertTrue(InfraFilter.isFreeWebmail("gmail.com"))
        XCTAssertTrue(InfraFilter.isFreeWebmail("orange.fr"))
        XCTAssertFalse(InfraFilter.isFreeWebmail("acme.com"))
    }
}

final class NormalizerTests: XCTestCase {
    func testUsernameStripsAt() {
        XCTAssertEqual(Normalizer.label(for: .username, "@bob"), "bob")
    }
    func testDomain() {
        XCTAssertEqual(Normalizer.label(for: .domain, "WWW.Example.com."), "example.com")
    }
    func testEmailLowercased() {
        XCTAssertEqual(Normalizer.label(for: .email, "A@B.COM"), "a@b.com")
    }
}

final class EntityExtractorTests: XCTestCase {
    func testExtractsSelectors() {
        let found = EntityExtractor.extract(from: "reach me at jane@acme.com or acme.com, ip 8.8.8.8")
        XCTAssertTrue(found.contains { $0.kind == .email && $0.value == "jane@acme.com" })
        XCTAssertTrue(found.contains { $0.kind == .domain && $0.value == "acme.com" })
        XCTAssertTrue(found.contains { $0.kind == .ipAddress && $0.value == "8.8.8.8" })
    }
}

final class PhoneNumberTests: XCTestCase {
    func testParsesCountry() {
        let p = PhoneNumber.parse("+33 1 23 45 67 89")
        XCTAssertEqual(p?.callingCode, "33")
        XCTAssertEqual(p?.country, "France")
        XCTAssertEqual(p?.e164, "+33123456789")
    }
    func testUnqualifiedHasNoCountry() {
        XCTAssertNil(PhoneNumber.parse("555 0100")?.country)
    }
}

final class EventKeyTests: XCTestCase {
    @MainActor
    func testStableForSameFact() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let a = DiscoveryEngine.eventKey(title: "Account created", date: date, precision: .day, category: "Account")
        let b = DiscoveryEngine.eventKey(title: "account created", date: date, precision: .day, category: "account")
        XCTAssertEqual(a, b, "Event identity should be case-insensitive and stable")
    }
}
