//
//  SchoolModels.swift
//  SchoolSpaceApp
//
//  Modèles de données pour l'application
//

import Foundation
import CoreLocation

// MARK: - Établissement scolaire

struct School: Identifiable, Codable, Equatable {
    let id: String // UAI / RNE
    let name: String
    let city: String
    let postalCode: String
    let latitude: Double
    let longitude: Double
    let url: String // URL de base de l'instance (ex: https://xxx.index-education.net/pronote)

    var displayName: String {
        "\(name), \(city)"
    }

    var distanceFromUser: CLLocationDistance?

    mutating func updateDistance(from userLocation: CLLocation) {
        let schoolLocation = CLLocation(latitude: latitude, longitude: longitude)
        distanceFromUser = userLocation.distance(from: schoolLocation)
    }
}

// MARK: - Résultat géolocalisation

struct NearbySchoolsResponse: Codable {
    let schools: [School]
}

// MARK: - Session utilisateur

struct UserSession: Codable {
    let userId: String
    let displayName: String // "Prénom Nom"
    let establishmentId: String
    let establishmentUrl: String
    let sessionToken: String // Cookie / token de session
    let expiresAt: Date

    var isExpired: Bool {
        Date() >= expiresAt
    }

    var isValid: Bool {
        !sessionToken.isEmpty && !isExpired
    }
}

// MARK: - QR Code décodé

struct DecodedQRCode: Codable {
    let jeton: String
    let login: String
    let url: String

    /// Extrait l'URL de base de l'établissement à partir de l'URL mobile
    var establishmentBaseURL: String {
        // Transforme https://xxx.index-education.net/pronote/mobile.eleve.html
        // en https://xxx.index-education.net/pronote/
        let pattern = #"(https://[^/]+\.index-education\.net/pronote/)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
           let range = Range(match.range(at: 1), in: url) {
            return String(url[range])
        }
        return url
    }
}

// MARK: - Erreurs de l'application

enum SchoolSpaceError: LocalizedError {
    case cameraPermissionDenied
    case locationPermissionDenied
    case invalidQRCode
    case qrCodeDecryptionFailed
    case invalidURL(String)
    case networkError(Error)
    case schoolNotFound
    case sessionExpired
    case loginFailed
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .cameraPermissionDenied:
            return "L'accès à la caméra est nécessaire pour scanner le QR code. Autorisez-le dans les Réglages."
        case .locationPermissionDenied:
            return "La localisation est nécessaire pour trouver les établissements proches. Autorisez-la dans les Réglages."
        case .invalidQRCode:
            return "Ce QR code n'est pas valide. Vérifiez qu'il s'agit bien d'un QR code d'établissement."
        case .qrCodeDecryptionFailed:
            return "Impossible de déchiffrer le QR code. Le code PIN à 4 chiffres est peut-être incorrect."
        case .invalidURL(let url):
            return "L'URL « \(url) » n'est pas valide. Elle doit commencer par https:// et correspondre à un établissement."
        case .networkError(let error):
            return "Erreur de connexion : \(error.localizedDescription)"
        case .schoolNotFound:
            return "Aucun établissement trouvé à cette adresse."
        case .sessionExpired:
            return "Votre session a expiré. Veuillez vous reconnecter."
        case .loginFailed:
            return "La connexion a échoué. Vérifiez vos identifiants."
        case .unknown(let error):
            return "Une erreur inattendue s'est produite : \(error.localizedDescription)"
        }
    }
}