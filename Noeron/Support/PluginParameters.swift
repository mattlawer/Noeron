//
//  PluginParameters.swift
//  Noeron
//
//  Non-secret, user-editable plugin parameters (e.g. a custom RPC endpoint),
//  stored in UserDefaults. Secrets belong in `KeychainStore`, not here.
//

import Foundation

enum PluginParameters {
    private static func defaultsKey(_ key: String) -> String { "noeron.param.\(key)" }

    static func get(_ key: String) -> String? {
        let v = UserDefaults.standard.string(forKey: defaultsKey(key))
        return (v?.isEmpty == false) ? v : nil
    }

    static func set(_ value: String?, for key: String) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            UserDefaults.standard.set(trimmed, forKey: defaultsKey(key))
        } else {
            UserDefaults.standard.removeObject(forKey: defaultsKey(key))
        }
    }

    static func has(_ key: String) -> Bool { get(key) != nil }
}
