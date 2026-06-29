//
//  ModelSchema.swift
//  Noeron
//
//  Central SwiftData schema + ModelContainer factory (CloudKit-backed).
//

import Foundation
import SwiftData
import Security

enum NoeronSchema {
    /// The iCloud container this app would mirror to when CloudKit is enabled.
    static let cloudKitContainerID = "iCloud.com.noeron.app"

    /// Every persisted model in one place.
    static let models: [any PersistentModel.Type] = [
        Investigation.self,
        Entity.self,
        EntityLink.self,
        NoteItem.self,
        EvidenceItem.self,
        TimelineEvent.self,
        Tag.self,
        PluginRun.self
    ]

    static var schema: Schema { Schema(models) }

    /// Process-wide container shared by the app, App Intents and Spotlight, so a
    /// Shortcut that adds an entity writes to the same store the UI reads from.
    @MainActor static let shared: ModelContainer = makeContainer()

    /// Container factory. CloudKit mirroring is enabled **only** when the process
    /// actually carries the iCloud entitlement — otherwise CloudKit hard-crashes the
    /// process via `_os_crash` (which a `do/catch` cannot rescue). With empty
    /// entitlements the app runs fully on a local store.
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let useCloudKit = !inMemory && hasCloudKitEntitlement()

        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else if useCloudKit {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false,
                                        cloudKitDatabase: .private(cloudKitContainerID))
        } else {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        }

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Last-resort: local-only store so the app always launches.
            let local = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
            do {
                return try ModelContainer(for: schema, configurations: [local])
            } catch {
                fatalError("Unable to create Noeron ModelContainer: \(error)")
            }
        }
    }

    /// True only when CloudKit mirroring should be requested. CloudKit hard-crashes
    /// a process that lacks the iCloud container entitlement, so we must be certain.
    ///
    /// - macOS: read the process's own entitlements from its code signature at
    ///   runtime via the `SecTask` API (macOS-only).
    /// - iOS/iPadOS: `SecTask` entitlement reading is unavailable, and there is no
    ///   public runtime API to inspect your own entitlements. We therefore default
    ///   to a local store (always safe — unsigned/CI builds never crash) and let a
    ///   maintainer who ships an iCloud-entitled build opt in with the
    ///   `NOERON_ICLOUD` compilation condition.
    static func hasCloudKitEntitlement() -> Bool {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let key = "com.apple.developer.icloud-container-identifiers" as CFString
        guard let value = SecTaskCopyValueForEntitlement(task, key, nil) else { return false }
        if let array = value as? [Any] { return !array.isEmpty }
        return false
        #elseif NOERON_ICLOUD
        return true
        #else
        return false
        #endif
    }
}
