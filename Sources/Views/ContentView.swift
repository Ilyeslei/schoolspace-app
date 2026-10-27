//
//  ContentView.swift
//  SchoolSpaceApp
//
//  Vue principale : route entre l'écran de connexion et l'écran post-connexion
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var sessionManager: SessionManager

    var body: some View {
        Group {
            if let session = sessionManager.currentSession, session.isValid {
                // Écran 2 : Après connexion
                MainView(session: session)
            } else {
                // Écran 1 : Choix de connexion
                ConnectionChoiceView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: sessionManager.currentSession?.isValid ?? false)
        .alert("Erreur", isPresented: $sessionManager.showError) {
            Button("OK") { sessionManager.dismissError() }
        } message: {
            Text(sessionManager.errorMessage ?? "Une erreur est survenue")
        }
    }
}

// MARK: - Vue principale après connexion

struct MainView: View {
    let session: UserSession
    @EnvironmentObject var sessionManager: SessionManager

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                VStack(spacing: 32) {
                    Spacer()

                    // Icône de bienvenue
                    ZStack {
                        Circle()
                            .fill(Color("AccentColor").opacity(0.15))
                            .frame(width: 100, height: 100)

                        Image(systemName: "person.crop.circle.fill.badge.checkmark")
                            .font(.system(size: 50, weight: .light))
                            .foregroundStyle(Color("AccentColor"))
                    }

                    // Message de bienvenue
                    VStack(spacing: 12) {
                        Text("Bonjour, \(session.displayName)")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)

                        Text("Vous êtes connecté à votre espace personnel")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }

                    // Infos établissement
                    VStack(spacing: 8) {
                        Text(session.establishmentId)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.tertiary)

                        Text(session.establishmentUrl)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.quaternary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.horizontal, 40)
                    }

                    Spacer()

                    // Bouton déconnexion
                    Button(role: .destructive) {
                        sessionManager.logout()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 17, weight: .semibold))
                            Text("Se déconnecter")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }
                    .glassEffect(.regular.tint(Color.red.opacity(0.15)), in: .rect(cornerRadius: 16))
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Espace Personnel")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

// MARK: - Preview

#Preview("Écran connexion") {
    ContentView()
        .environmentObject(SessionManager.shared)
}

#Preview("Écran principal") {
    let session = UserSession(
        userId: "test_user",
        displayName: "Prénom Nom",
        establishmentId: "Établissement Exemple",
        establishmentUrl: "https://etab.index-education.net/pronote/",
        sessionToken: "test_token",
        expiresAt: Date().addingTimeInterval(86400)
    )
    MainView(session: session)
        .environmentObject(SessionManager.shared)
}