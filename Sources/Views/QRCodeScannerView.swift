//
//  QRCodeScannerView.swift
//  SchoolSpaceApp
//
//  Vue pour scanner un QR code d'établissement
//  Inclut la saisie du PIN à 4 chiffres pour le déchiffrement
//

import SwiftUI
import AVFoundation

struct QRCodeScannerView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss

    @State private var scannedCode: String?
    @State private var showPINEntry = false
    @State private var pinCode = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var pinDigits: [String] = Array(repeating: "", count: 4)
    @FocusState private var focusedField: Int?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                if showPINEntry {
                    // Écran saisie PIN
                    pinEntryView
                } else {
                    // Écran scanner
                    scannerView
                }
            }
            .navigationTitle("Scanner QR code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") {
                        dismiss()
                    }
                }
            }
            .alert("Erreur", isPresented: $showError) {
                Button("OK") {
                    if errorMessage?.contains("PIN") == true {
                        // Revenir à la saisie PIN
                    } else {
                        // Revenir au scanner
                        scannedCode = nil
                        showPINEntry = false
                    }
                }
                Button("Réessayer", role: .none) {
                    if errorMessage?.contains("PIN") == true {
                        pinCode = ""
                        pinDigits = Array(repeating: "", count: 4)
                        focusedField = 0
                    } else {
                        scannedCode = nil
                    }
                }
            } message: {
                Text(errorMessage ?? "Une erreur est survenue")
            }
        }
    }

    // MARK: - Vue Scanner

    private var scannerView: some View {
        ZStack {
            // Scanner UIKit via UIViewRepresentable
            QRScannerRepresentable { result in
                handleScanResult(result)
            }
            .ignoresSafeArea()

            // Overlay instructions
            VStack {
                Spacer()

                VStack(spacing: 16) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(Color("AccentColor"))

                    Text("Placez le QR code dans le cadre")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)

                    Text("Le code doit être généré depuis l'espace web de votre établissement")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .padding(.bottom, 100)
            }
        }
    }

    // MARK: - Vue Saisie PIN

    private var pinEntryView: some View {
        VStack(spacing: 32) {
            Spacer()

            // Icône et titre
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color("AccentColor").opacity(0.15))
                        .frame(width: 80, height: 80)

                    Image(systemName: "lock.fill")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(Color("AccentColor"))
                }

                VStack(spacing: 8) {
                    Text("Code PIN à 4 chiffres")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.primary)

                    Text("Entrez le code choisi lors de la génération du QR code")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }

            // 4 champs PIN
            HStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { index in
                    PINField(
                        text: $pinDigits[index],
                        isFocused: focusedField == index,
                        onTap: { focusedField = index }
                    )
                    .focused($focusedField, equals: index)
                }
            }

            // Bouton valider
            PrimaryGlassButton(
                title: isProcessing ? "Vérification..." : "Valider",
                isLoading: isProcessing,
                isDisabled: pinDigits.joined().count != 4
            ) {
                validatePIN()
            }
            .padding(.horizontal, 40)

            Spacer()

            // Lien retour
            Button("Revenir au scanner") {
                showPINEntry = false
                scannedCode = nil
                pinCode = ""
                pinDigits = Array(repeating: "", count: 4)
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.bottom, 40)
        }
        .padding(.horizontal, 20)
        .onAppear {
            focusedField = 0
        }
    }

    // MARK: - Actions

    private func handleScanResult(_ result: Result<String, Error>) {
        switch result {
        case .success(let code):
            scannedCode = code
            showPINEntry = true
        case .failure(let error):
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func validatePIN() {
        guard let scannedCode = scannedCode else { return }

        pinCode = pinDigits.joined()
        isProcessing = true

        Task {
            do {
                let decoded = try QRCodeService.shared.decodeQRCode(scannedCode, pin: pinCode)

                // Naviguer vers la page de connexion de l'établissement
                await MainActor.run {
                    isProcessing = false
                    dismiss()

                    // Lancer la connexion
                    Task {
                        do {
                            let loginURL = try await NetworkService.shared.validateEstablishmentURL(decoded.establishmentBaseURL)
                            try await sessionManager.login(at: loginURL.absoluteString)
                        } catch {
                            await MainActor.run {
                                errorMessage = error.localizedDescription
                                showError = true
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    errorMessage = error.localizedDescription
                    showError = true
                    pinDigits = Array(repeating: "", count: 4)
                    focusedField = 0
                }
            }
        }
    }
}

// MARK: - Champ PIN individuel

struct PINField: View {
    @Binding var text: String
    let isFocused: Bool
    let onTap: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isFocused ? Color("AccentColor") : Color(.separator),
                    lineWidth: isFocused ? 3 : 1
                )
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isFocused ? Color("AccentColor").opacity(0.1) : Color(.systemGray6))
                )

            Text(text)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 60, height: 68)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onChange(of: text) { _, newValue in
            if newValue.count > 1 {
                text = String(newValue.suffix(1))
            }
        }
    }
}

// MARK: - Représentable pour le scanner QR UIKit

struct QRScannerRepresentable: UIViewControllerRepresentable {
    let completion: (Result<String, Error>) -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let scanner = QRScannerViewController()
        scanner.completion = completion
        return scanner
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

// Note: QRScannerViewController est déjà défini dans QRCodeService.swift
// (partagé pour éviter la duplication)