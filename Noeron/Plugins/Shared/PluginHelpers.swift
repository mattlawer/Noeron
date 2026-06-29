//
//  PluginHelpers.swift
//  Noeron
//
//  Small helpers shared across plugins: tolerant date parsing, URL/credential
//  string helpers, a defensive JSON decode, and a safe array subscript.
//

import Foundation

/// Tolerant date parsing for the many shapes public services return.
enum ISO8601Date {
    static func day(_ s: String) -> Date? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(s.prefix(10)))
    }
    static func parse(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        if let d = ISO8601DateFormatter().date(from: s) { return d }
        for fmt in ["yyyy-MM-dd'T'HH:mm:ss'Z'", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", "yyyy"] {
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return day(s)
    }
}

extension String {
    var pathEncoded: String { addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? self }
    func basicAuthHeader(password: String = "") -> String {
        "Basic " + Data("\(self):\(password)".utf8).base64EncodedString()
    }
}

extension Array {
    /// Bounds-checked subscript: returns nil instead of trapping.
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// Defensive JSON decode that surfaces a readable `PluginError.decoding`.
func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
    do { return try JSONDecoder().decode(T.self, from: data) }
    catch { throw PluginError.decoding("\(T.self): \(error.localizedDescription)") }
}
