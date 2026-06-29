//
//  IntentRouter.swift
//  Noeron
//
//  Bridges App Intents (which run outside the view hierarchy) to in-app navigation.
//

import Foundation
import Combine

@MainActor
final class IntentRouter: ObservableObject {
    static let shared = IntentRouter()
    let deepLinks = PassthroughSubject<DeepLink, Never>()
    func route(_ link: DeepLink) { deepLinks.send(link) }
}
