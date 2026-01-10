//
//  Navigators.swift
//  SMCController
//

import SwiftUI
import Combine

@MainActor
final class Navigator: ObservableObject {
    @Published var path = NavigationPath()

    var canPop: Bool { !path.isEmpty }

    func push<T: Hashable>(_ value: T) {
        path.append(value)
    }

    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func popToRoot() {
        path = NavigationPath()
    }
}
