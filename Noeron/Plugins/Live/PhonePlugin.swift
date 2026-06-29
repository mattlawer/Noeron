//
//  PhonePlugin.swift
//  Noeron
//
//  Keyless phone-number intelligence. Parses an E.164-ish number, identifies the
//  country from its calling code, normalises it, and emits the country as a
//  location plus a few investigative pivots (WhatsApp wa.me, web search). No key.
//
//  Carrier / line-type lookup needs a paid HLR/numbering API; this plugin sticks
//  to what is derivable offline plus public link pivots.
//

import Foundation

struct PhoneIntelPlugin: Plugin {
    var metadata: PluginMetadata {
        PluginMetadata(
            id: "phone-intel",
            name: "Phone Intelligence",
            summary: "Parses a phone number, identifies its country from the calling code, normalises it to E.164 and emits country + investigative pivots (WhatsApp, web search). No key.",
            category: .knowledge,
            acceptedKinds: [.phone],
            producesKinds: [.location, .url],
            requiresAPIKey: false,
            isLive: true,
            symbol: "phone.badge.waveform.fill"
        )
    }

    func run(on entity: EntitySnapshot, context: PluginContext) async throws -> PluginResult {
        guard let parsed = PhoneNumber.parse(entity.label) else { throw PluginError.unsupportedEntity }
        var result = PluginResult(rawExcerpt: "E.164=\(parsed.e164) cc=\(parsed.callingCode ?? "?") country=\(parsed.country ?? "unknown")")

        result.inputAttributes.append(.init(key: "E.164", value: parsed.e164, source: "Phone Intelligence"))
        if let code = parsed.callingCode {
            result.inputAttributes.append(.init(key: "Calling code", value: "+\(code)", source: "Phone Intelligence"))
        }
        result.inputAttributes.append(.init(key: "National number", value: parsed.national, source: "Phone Intelligence"))
        if let country = parsed.country {
            result.inputAttributes.append(.init(key: "Country", value: country, source: "Phone Intelligence"))
            result.entities.append(.init(
                kind: .location, label: country, subtitle: "Number's country (calling code)",
                confidence: 0.55, linkKind: .relatedTo, linkDirection: .fromInput
            ))
        }

        // Investigative pivots — passive links an analyst can open.
        let intlDigits = parsed.e164.replacingOccurrences(of: "+", with: "")
        result.entities.append(.init(
            kind: .url, label: "https://wa.me/\(intlDigits)",
            subtitle: "WhatsApp (opens if the number is registered)",
            confidence: 0.4, linkKind: .relatedTo, linkDirection: .fromInput
        ))
        if let q = parsed.e164.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            result.entities.append(.init(
                kind: .url, label: "https://www.google.com/search?q=%22\(q)%22",
                subtitle: "Web search for this number",
                confidence: 0.35, linkKind: .relatedTo, linkDirection: .fromInput
            ))
        }
        return result
    }
}

// MARK: - Lightweight phone parser (offline)

struct PhoneNumber {
    let e164: String
    let callingCode: String?
    let national: String
    let country: String?

    static func parse(_ raw: String) -> PhoneNumber? {
        // Keep digits; honour a leading "+" or international "00" prefix.
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var digits = trimmed.filter(\.isNumber)
        let hasPlus = trimmed.hasPrefix("+") || trimmed.hasPrefix("00")
        if trimmed.hasPrefix("00") { digits = String(digits.dropFirst(2)) }
        guard digits.count >= 6, digits.count <= 15 else { return nil }

        // Only resolve the country when the number is internationally qualified.
        if hasPlus, let (code, country) = matchCallingCode(digits) {
            let national = String(digits.dropFirst(code.count))
            return PhoneNumber(e164: "+\(digits)", callingCode: code, national: national, country: country)
        }
        // Otherwise present it as-is (country unknown without a + prefix).
        return PhoneNumber(e164: hasPlus ? "+\(digits)" : digits, callingCode: nil, national: digits, country: nil)
    }

    /// Longest-prefix match of the digits against known calling codes.
    private static func matchCallingCode(_ digits: String) -> (code: String, country: String)? {
        for len in stride(from: 4, through: 1, by: -1) where digits.count > len {
            let prefix = String(digits.prefix(len))
            if let country = callingCodes[prefix] { return (prefix, country) }
        }
        return nil
    }

    /// Calling code → country. Curated subset of common codes (NANP shares +1).
    static let callingCodes: [String: String] = [
        "1": "United States / Canada (NANP)", "7": "Russia / Kazakhstan",
        "20": "Egypt", "27": "South Africa", "30": "Greece", "31": "Netherlands",
        "32": "Belgium", "33": "France", "34": "Spain", "36": "Hungary", "39": "Italy",
        "40": "Romania", "41": "Switzerland", "43": "Austria", "44": "United Kingdom",
        "45": "Denmark", "46": "Sweden", "47": "Norway", "48": "Poland", "49": "Germany",
        "51": "Peru", "52": "Mexico", "53": "Cuba", "54": "Argentina", "55": "Brazil",
        "56": "Chile", "57": "Colombia", "58": "Venezuela", "60": "Malaysia",
        "61": "Australia", "62": "Indonesia", "63": "Philippines", "64": "New Zealand",
        "65": "Singapore", "66": "Thailand", "81": "Japan", "82": "South Korea",
        "84": "Vietnam", "86": "China", "90": "Turkey", "91": "India", "92": "Pakistan",
        "93": "Afghanistan", "94": "Sri Lanka", "95": "Myanmar", "98": "Iran",
        "211": "South Sudan", "212": "Morocco", "213": "Algeria", "216": "Tunisia",
        "218": "Libya", "220": "Gambia", "221": "Senegal", "233": "Ghana",
        "234": "Nigeria", "251": "Ethiopia", "254": "Kenya", "255": "Tanzania",
        "256": "Uganda", "260": "Zambia", "263": "Zimbabwe", "351": "Portugal",
        "352": "Luxembourg", "353": "Ireland", "354": "Iceland", "355": "Albania",
        "356": "Malta", "358": "Finland", "359": "Bulgaria", "370": "Lithuania",
        "371": "Latvia", "372": "Estonia", "380": "Ukraine", "381": "Serbia",
        "385": "Croatia", "386": "Slovenia", "420": "Czechia", "421": "Slovakia",
        "852": "Hong Kong", "853": "Macau", "855": "Cambodia", "856": "Laos",
        "880": "Bangladesh", "886": "Taiwan", "960": "Maldives", "961": "Lebanon",
        "962": "Jordan", "963": "Syria", "964": "Iraq", "965": "Kuwait",
        "966": "Saudi Arabia", "971": "United Arab Emirates", "972": "Israel",
        "973": "Bahrain", "974": "Qatar", "977": "Nepal", "992": "Tajikistan",
        "994": "Azerbaijan", "995": "Georgia", "998": "Uzbekistan"
    ]
}
