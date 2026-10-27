//
//  URLEntryView.swift
//  SchoolSpaceApp
//
//  Vue pour saisir manuellement l'URL de l'établissement
//

import SwiftUI

struct URLEntryView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss

    @State private var urlString = ""
    @State private var isValidating = false
    @State private var errorMessage: String?
    @State private var showError = false
    @FocusState private var isFocused: Bool

    var isValidURL: Bool {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") else { return false }

        guard trimmed.contains(".index-education.net") else { return false }

        guard let url = URL(string: trimmed), url.host != nil else { return false }

        return true
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                ScrollView {
                    GlassContainer {
                        VStack(spacing: 28) {
                            VStack(spacing: 16) {
                                ZStack {
                                    Circle()
                                        .fill(Color("AccentColor").opacity(0.15))
                                        .frame(width: 80, height: 80)

                                    Image(systemName: "link")
                                        .font(.system(size: 36, weight: .medium))
                                        .foregroundStyle(Color("AccentColor"))
                                }

                                VStack(spacing: 8) {
                                    Text("Saisir l'URL de votre espace")
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.center)

                                    Text("Entrez l'adresse web de votre établissement (ex: https://etab.index-education.net/pronote/)")
                                        .font(.system(size: 15, weight: .regular))
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 32)
                                }
                            }
                            .padding(.top, 20)

                            VStack(alignment: .leading, spacing: 12) {
                                Text("Adresse de l'établissement")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.secondary)

                                GlassTextField(
                                    placeholder: "https://etab.index-education.net/pronote/",
                                    text: $urlString,
                                    icon: "link",
                                    keyboardType: .URL,
                                    autocapitalization: .never
                                ) {
                                    validateAndContinue()
                                }
                                .focused($isFocused)
                            }
                            .padding(.horizontal, 20)

                            VStack(spacing: 8) {
                                Label("L'URL doit contenir .index-education.net", systemImage: "info.circle")
                                Label("Le https:// est obligatoire", systemImage: "lock.fill")
                            }
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)

                            PrimaryGlassButton(
                                title: isValidating ? "Vérification..." : "Continuer",
                                icon: "arrow.right",
                                isLoading: isValidating,
                                isDisabled: !isValidURL
                            ) {
                                validateAndContinue()
                            }
                            .padding(.horizontal, 40)
                            .padding(.top, 8)

                            Spacer(minLength: 40)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .navigationTitle("URL de l'établissement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .alert("Erreur", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "Une erreur est survenue")
            }
            .onAppear {
                isFocused = true
            }
        }
    }

    private func validateAndContinue() {
        guard isValidURL else {
            errorMessage = "L'URL n'est pas valide. Elle doit commencer par https:// et contenir .index-education.net"
            showError = true
            return
        }

        isValidating = true
        errorMessage = nil

        Task {
            do {
                let loginURL = try await NetworkService.shared.validateEstablishmentURL(urlString)

                await MainActor.run {
                    isValidating = false
                    dismiss()

                    Task {
                        do {
                            try await sessionManager.login(at: loginURL)
                        } catch {
                            await MainActor.run {
                                errorMessage = error.localizedDescription
                                showError = true
                            }
                        }
                    }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isValidating = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}
