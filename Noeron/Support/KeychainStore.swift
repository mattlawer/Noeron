//
//  KeychainStore.swift
//  Noeron
//
//  Minimal Keychain wrapper for plugin API credentials. Keys are scoped by
//  plugin id (e.g. "shodan.apiKey") and never written to the SwiftData store.
//
//  IMPORTANT — no Keychain reads during normal browsing. Reading a Keychain item
//  on an unsigned/locally-built app triggers the macOS "<app> wants to use your
//  confidential information" prompt *every time*. The UI only needs to know
//  *whether* a key is set (to draw badges / Run vs Set Up), not its value — so we
//  keep a non-secret index of which keys exist in UserDefaults and answer
//  `has(_:)` from that. The secret is read from the Keychain only when a plugin
//  actually runs (an explicit, user-initiated action), where a one-time prompt is
//  expected and can be dismissed with "Always Allow".
//

import Foundation
import Security

enum KeychainStore {
    private static let service = "com.noeron.app.credentials"
    private static let indexKey = "noeron.credentialIndex.v1"

    // MARK: Non-secret index (UserDefaults)

    private static var index: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: indexKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: indexKey) }
    }

    /// Whether a credential is configured. Reads the index only — never the
    /// Keychain — so it is safe to call freely while rendering the UI.
    static func has(_ key: String) -> Bool { index.contains(key) }

    // MARK: Secret storage (Keychain)

    static func set(_ value: String?, for key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        var idx = index
        guard let value, let data = value.data(using: .utf8), !value.isEmpty else {
            idx.remove(key); index = idx; return
        }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecSuccess { idx.insert(key) } else { idx.remove(key) }
        index = idx
    }

    /// Reads the secret value. Touches the Keychain → may prompt on unsigned
    /// builds, so call this ONLY from an explicit user action (running a plugin),
    /// never during view rendering.
    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
