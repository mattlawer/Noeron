//
//  EntityKind.swift
//  Noeron
//
//  The taxonomy of entities that can live inside an investigation graph.
//  Foundation-only so it can be shared across the model, plugin, and report layers.
//

import Foundation

/// Every node on the Noeron graph is an `Entity` of one `EntityKind`.
/// Kinds are grouped into the investigation sidebar and drive icon / colour / extraction.
enum EntityKind: String, Codable, CaseIterable, Sendable, Identifiable {

    // People & orgs
    case person
    case company
    case organization

    // Selectors / identifiers
    case email
    case phone
    case username
    case socialProfile

    // Network
    case domain
    case subdomain
    case url
    case ipAddress
    case asn
    case certificate

    // Finance
    case cryptoWallet

    // Physical
    case vehicle
    case location

    // Findings
    case breach

    // Content (file-backed)
    case image
    case document
    case note

    var id: String { rawValue }

    /// Singular, human readable.
    var displayName: String {
        switch self {
        case .person: "Person"
        case .company: "Company"
        case .organization: "Organization"
        case .email: "Email"
        case .phone: "Phone"
        case .username: "Username"
        case .socialProfile: "Social Profile"
        case .domain: "Domain"
        case .subdomain: "Subdomain"
        case .url: "URL"
        case .ipAddress: "IP Address"
        case .asn: "ASN"
        case .certificate: "Certificate"
        case .cryptoWallet: "Crypto Wallet"
        case .vehicle: "Vehicle"
        case .location: "Location"
        case .breach: "Breach"
        case .image: "Image"
        case .document: "Document"
        case .note: "Note"
        }
    }

    /// Plural, for sidebar section headers.
    var pluralName: String {
        switch self {
        case .person: "Persons"
        case .company: "Companies"
        case .organization: "Organizations"
        case .email: "Emails"
        case .phone: "Phones"
        case .username: "Usernames"
        case .socialProfile: "Social Profiles"
        case .domain: "Domains"
        case .subdomain: "Subdomains"
        case .url: "URLs"
        case .ipAddress: "IP Addresses"
        case .asn: "ASNs"
        case .certificate: "Certificates"
        case .cryptoWallet: "Crypto Wallets"
        case .vehicle: "Vehicles"
        case .location: "Locations"
        case .breach: "Breaches"
        case .image: "Images"
        case .document: "Documents"
        case .note: "Notes"
        }
    }

    /// SF Symbol used on nodes, lists and the sidebar.
    var symbolName: String {
        switch self {
        case .person: "person.fill"
        case .company: "building.2.fill"
        case .organization: "building.columns.fill"
        case .email: "envelope.fill"
        case .phone: "phone.fill"
        case .username: "at"
        case .socialProfile: "person.crop.square.filled.and.at.rectangle"
        case .domain: "globe"
        case .subdomain: "globe.badge.chevron.backward"
        case .url: "link"
        case .ipAddress: "network"
        case .asn: "point.3.connected.trianglepath.dotted"
        case .certificate: "checkmark.seal.fill"
        case .cryptoWallet: "bitcoinsign.circle.fill"
        case .vehicle: "car.fill"
        case .location: "mappin.and.ellipse"
        case .breach: "exclamationmark.shield.fill"
        case .image: "photo.fill"
        case .document: "doc.fill"
        case .note: "note.text"
        }
    }

    /// Stable accent colour as a hex string; the UI layer resolves it to a `Color`.
    var colorHex: String {
        switch self {
        case .person: "#21C7BC"
        case .company, .organization: "#5B8DEF"
        case .email: "#E8A13A"
        case .phone: "#7C5CFC"
        case .username, .socialProfile: "#36C5B0"
        case .domain, .subdomain, .url: "#3FB950"
        case .ipAddress, .asn: "#DB6D28"
        case .certificate: "#2EA043"
        case .cryptoWallet: "#F2A900"
        case .vehicle: "#9AA5B1"
        case .location: "#EC6A5E"
        case .breach: "#F85149"
        case .image: "#BC8CFF"
        case .document: "#8B949E"
        case .note: "#C9D1D9"
        }
    }

    /// Sidebar grouping used by the workspace navigator.
    enum Section: String, CaseIterable, Sendable {
        case people = "People & Orgs"
        case selectors = "Selectors"
        case network = "Network"
        case finance = "Finance"
        case physical = "Physical"
        case findings = "Findings"
        case content = "Content"
    }

    var section: Section {
        switch self {
        case .person, .company, .organization: .people
        case .email, .phone, .username, .socialProfile: .selectors
        case .domain, .subdomain, .url, .ipAddress, .asn, .certificate: .network
        case .cryptoWallet: .finance
        case .vehicle, .location: .physical
        case .breach: .findings
        case .image, .document, .note: .content
        }
    }

    /// Kinds that are user-facing "first class" sidebar tabs, in display order.
    static var sidebarOrder: [EntityKind] {
        [.person, .company, .email, .phone, .domain, .ipAddress,
         .cryptoWallet, .vehicle, .username, .certificate, .breach,
         .image, .document]
    }

    /// True for kinds backed by a file on disk (`EvidenceItem`).
    var isFileBacked: Bool { self == .image || self == .document }
}
