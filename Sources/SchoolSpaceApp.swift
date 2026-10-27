//
//  SchoolSpaceApp.swift
//  SchoolSpaceApp
//
//  Application native iOS pour accéder à son espace personnel d'établissement
//  Architecture : SwiftUI, iOS 26+, mode sombre uniquement, Liquid Glass
//

import SwiftUI

@main
struct SchoolSpaceApp: App {
    @StateObject private var sessionManager = SessionManager.shared

    init() {
        // Forcer le mode sombre globalement
        UIView.appearance().overrideUserInterfaceStyle = .dark
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sessionManager)
                .preferredColorScheme(.dark)
                .accentColor(Color("AccentColor"))
        }
    }
}