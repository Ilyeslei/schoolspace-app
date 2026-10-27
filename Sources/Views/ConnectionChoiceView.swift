//
//  ConnectionChoiceView.swift
//  SchoolSpaceApp
//
//  Écran 1 : Choix de la méthode de connexion
//

import SwiftUI
import CoreLocation

@MainActor
final class LocationManager: NSObject, CLLocationManagerDelegate, ObservableObject, Sendable {
    nonisolated(unsafe) static let shared = LocationManager()

    private let manager = CLLocationManager()
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = manager.authorizationStatus
    }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
        }
    }
}

struct ConnectionChoiceView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @State private var showQRScanner = false
    @State private var showLocationPicker = false
    @State private var showURLEntry = false
    @State private var locationError: String?
    @State private var showLocationError = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                ScrollView {
                    GlassContainer {
                        VStack(
                            VStack(spacing: 10) {
                                Text("Comment souhaitez-vous vous connecter à votre espace personnel ?")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)

                                Text("Choisissez une méthode pour accéder à votre établissement")
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)
                            }
                            .padding(.top, 40)

                            VStack(spacing: 16) {
                                GlassButton(
                                    icon: "qrcode.viewfinder",
                                    title: "Avec un QR code",
                                    subtitle: "Scannez le code de votre établissement"
                                ) {
                                    showQRScanner = true
                                }


                                    icon: "location.fill",
                                    title: "Avec la géolocalisation",
                                    subtitle: "Trouvez les établissements près de chez vous"
                                ) {
                                    requestLocationPermission()
                                }

                                GlassButton(
                                    icon: "link",
                                    title: "Saisir l'URL de votre espace",
                                    subtitle: "Entrez l'adresse de votre établissement"
                                ) {
                                    showURLEntry = true
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 40)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showQRScanner) {
                QRCodeScannerView()
            }
            .sheet(isPresented: $showLocationPicker) {
                LocationPickerView()
            }
            .sheet(isPresented: $showURLEntry) {
                URLEntryView()
            }
            .alert("Localisation requise", isPresented: $showLocationError) {
                Button("Ouvrir les Réglages") {
                    openSettings()
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text(locationError ?? "L'accès à la localisation est nécessaire pour trouver les établissements proches.")
            }
        }
    }

    private func requestLocationPermission() {
        let status = CLLocationManager().authorizationStatus

        switch status {
        case .notDetermined:
            LocationManager.shared.requestWhenInUseAuthorization()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showLocationPicker = true
            }
        case .authorizedWhenInUse, .authorizedAlways:
            showLocationPicker = true
        case .denied, .restricted:
            locationError = "L'accès à la localisation a été refusé. Veuillez l'autoriser dans les Réglages pour utiliser cette fonctionnalité."
            showLocationError = true
        @unknown default:
            locationError = "Impossible de déterminer l'autorisation de localisation."
            showLocationError = true
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

#Preview {
    ConnectionChoiceView()
        .environmentObject(SessionManager.shared)
}
