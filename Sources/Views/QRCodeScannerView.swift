//
//  QRCodeScannerView.swift
//  SchoolSpaceApp
//
//  Vue pour scanner un QR code d'établissement
//

import SwiftUI
import AVFoundation

struct QRCodeScannerView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss

    @State private var scannedCode: String?
    @State private var showPINEntry = false
    @State private var pinDigits: [String] = Array(repeating: "", count: 4)
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showError = false
    @FocusState private var focusedField: Int?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                if showPINEntry {
                    pinEntryView
                } else {
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
                        scannedCode = nil
                        showPINEntry = false
                    }
                }
                Button("Réessayer", role: .none) {
                    if errorMessage?.contains("PIN") == true {
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

    private var scannerView: some View {
        ZStack {
            QRScannerView { result in
                handleScanResult(result)
            }
            .ignoresSafeArea()

            VStack {
                Spacer()

                VStack(spacing: 16) {
                    Image(syste
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

    private var pinEntryView: some View {
        VStack(spacing: 32) {
            Spacer()

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

            PrimaryGlassButton(
                title: isProcessing ? "Vérification..." : "Valider",
                isLoading: isProcessing,
                isDisabled: pinDigits.joined().count != 4
            ) {
                validatePIN()
            }
            .padding(.horizontal, 40)

            Spacer()

            Button("Revenir au scanner") {
                showPINEntry = false
                scannedCode = nil
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

        let pinCode = pinDigits.joined()
        isProcessing = true

        Task {
            do {
                let decoded = try QRCodeService.shared.decodeQRCode(scannedCode, pin: pinCode)

                await MainActor.run {
                    isProcessing = false
                    dismiss()

                    Task {
                        do {
                            let loginURL = try await NetworkService.shared.validateEstablishmentURL(decoded.establishmentBaseURL)
                            try await sessionManager.login(at: loginURL)
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

struct PINField: View {
    @Binding var text: String
    let isFocused: Bool
    let onTap: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(co
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
