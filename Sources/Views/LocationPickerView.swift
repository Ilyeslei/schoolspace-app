//
//  LocationPickerView.swift
//  SchoolSpaceApp
//
//  Vue pour choisir un établissement via la géolocalisation
//

import SwiftUI
import CoreLocation

struct LocationPickerView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss

    @State private var schools: [School] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var userLocation: CLLocation?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                if isLoading {
                    loadingView
                } else if schools.isEmpty {
                    emptyView
                } else {
                    schoolsList
                }
            }
            .navigationTitle("Établissements proches")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: refresh) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            .alert("Erreur", isPresented: $showError) {
                Button("OK") {}
                Button("Réessayer") { refresh() }
            } message: {
                Text(errorMessage ?? "Une erreur est survenue")
            }
            .task {
                await loadNearbySchools()
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: Color("AccentColor")))
                .scaleEffect(1.5)

            Text("Recherche des établissements...")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "location.slash")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tertiary)

            VStack(spacing: 8) {
                Text("Aucun établissement trouvé")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("Aucun établissement scolaire n'a été trouvé à proximité. Essayez de vous déplacer ou utilisez une autre méthode de connexion.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            PrimaryGlassButton(title: "Réessayer", icon: "arrow.clockwise") {
                refresh()
            }
            .padding(.horizontal, 60)
        }
    }

    private var schoolsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(schools) { school in
                    SchoolRowView(school: school) {
                        selectSchool(school)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func loadNearbySchools() async {
        isLoading = true
        errorMessage = nil

        do {
            let location = try await getCurrentLocation()
            userLocation = location

            let fetchedSchools = try await NetworkService.shared.fetchNearbySchools(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                radiusKm: 15
            )

            var schoolsWithDistance = fetchedSchools
            for i in schoolsWithDistance.indices {
                schoolsWithDistance[i].updateDistance(from: location)
            }
            schoolsWithDistance.sort { ($0.distanceFromUser ?? .infinity) < ($1.distanceFromUser ?? .infinity) }

            await MainActor.run {
                self.schools = schoolsWithDistance
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.showError = true
                self.isLoading = false
            }
        }
    }

    private func getCurrentLocation() async throws -> CLLocation {
        return try await withCheckedThrowingContinuation { continuation in
            let manager = CLLocationManager()
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters

            let delegate = LocationDelegate { result in
                continuation.resume(with: result)
            }
            manager.delegate = delegate

            objc_setAssociatedObject(manager, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

            if manager.authorizationStatus == .authorizedWhenInUse ||
               manager.authorizationStatus == .authorizedAlways {
                manager.requestLocation()
            } else {
                continuation.resume(throwing: SchoolSpaceError.locationPermissionDenied)
            }
        }
    }

    private func selectSchool(_ school: School) {
        dismiss()

        Task {
            do {
                let loginURL = try await NetworkService.shared.validateEstablishmentURL(school.url)
                try await sessionManager.login(at: loginURL)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func refresh() {
        Task { await loadNearbySchools() }
    }
}

struct SchoolRowView: View {
    let school: School
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color("AccentColor").opacity(0.15))
                        .frame(width: 48, height: 48)

                    Image(systemName: "building.2.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Color("AccentColor"))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(school.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    HStack(spacing: 8) {
                        Text(school.city)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.secondary)

                        if let distance = school.distanceFromUser {
                            Text("•")
                                .foregroundStyle(.tertiary)
                            Text(formatDistance(distance))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color("AccentColor"))
                        }
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassButtonStyle())
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func formatDistance(_ meters: CLLocationDistance) -> String {
        if meters < 1000 {
            return "\(Int(meters)) m"
        } else {
            return String(format: "%.1f km", meters / 1000)
        }
    }
}

@MainActor
private class LocationDelegate: NSObject, CLLocationManagerDelegate {
    let completion: (Result<CLLocation, Error>) -> Void

    init(completion: @escaping (Result<CLLocation, Error>) -> Void) {
        self.completion = completion
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            completion(.success(location))
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        completion(.failure(error))
    }
}
