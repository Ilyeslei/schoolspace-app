//
//  NetworkService.swift
//  SchoolSpaceApp
//
//  Services réseau : géolocalisation établissements, validation URL, etc.
//

import Foundation
import CoreLocation

@MainActor
final class NetworkService: Sendable {
    static let shared = NetworkService()

    private let educationAPIBase = "https://data.education.gouv.fr/api/explore/v2.1/catalog/datasets/fr-en-adresse-et-geolocalisation-etablissements-premier-et-second-degre/records"
    private let session = URLSession.shared
    private let decoder = JSONDecoder()

    private init() {
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    // MARK: - Recherche établissements par géolocalisation

    func fetchNearbySchools(latitude: Double, longitude: Double, radiusKm: Double = 10) async throws -> [School] {
        let distanceMeters = Int(radiusKm * 1000)
        let geosearch = "\(latitude),\(longitude),\(distanceMeters)"

        var components = URLComponents(string: educationAPIBase)!
        components.queryItems = [
            URLQueryItem(name: "geosearch", value: geosearch),
            URLQueryItem(name: "limit", value: "50"),
            URLQueryItem(name: "select", value: "numero_uai,appellation_officielle,commune,code_postal,latitude,longitude"),
            URLQueryItem(name: "where", value: "nature_uai_libelle IN ('Collège', 'Lycée', 'École élémentaire', 'École maternelle', 'Lycée professionnel', 'Établissement régional d\'enseignement adapté')")
        ]

        guard let url = components.url else {
            throw SchoolSpaceError.invalidURL("URL de recherche invalide")
        }

        do {
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw SchoolSpaceError.networkError(URLError(.badServerResponse))
            }

            struct EducationAPIResponse: Codable {
                let results: [EducationSchoolRecord]
                let totalCount: Int
            }

            struct EducationSchoolRecord: Codable {
                let numeroUai: String
                let appellationOfficielle: String
                let commune: String
                let codePostal: String
                let latitude: Double
                let longitude: Double
            }

            let apiResponse = try decoder.decode(EducationAPIResponse.self, from: data)

            return apiResponse.results.compactMap { record in
                guard !record.numeroUai.isEmpty else { return nil }
                let baseURL = "https://\(record.numeroUai.lowercased()).index-education.net/pronote/"
                return School(
                    id: record.numeroUai,
                    name: record.appellationOfficielle,
                    city: record.commune,
                    postalCode: record.codePostal,
                    latitude: record.latitude,
                    longitude: record.longitude,
                    url: baseURL
                )
            }
        } catch let error as SchoolSpaceError {
            throw error
        } catch {
            throw SchoolSpaceError.networkError(error)
        }
    }

    // MARK: - Recherche établissements par code postal / ville (fallback)

    func searchSchools(query: String) async throws -> [School] {
        var components = URLComponents(string: educationAPIBase)!
        components.queryItems = [
            URLQueryItem(name: "where", value: "appellation_officielle LIKE '%\(query)%' OR commune LIKE '%\(query)%' OR code_postal = '\(query)'"),
            URLQueryItem(name: "limit", value: "30"),
            URLQueryItem(name: "select", value: "numero_uai,appellation_officielle,commune,code_postal,latitude,longitude")
        ]

        guard let url = components.url else {
            throw SchoolSpaceError.invalidURL("URL de recherche invalide")
        }

        do {
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw SchoolSpaceError.networkError(URLError(.badServerResponse))
            }

            struct EducationAPIResponse: Codable {
                let results: [EducationSchoolRecord]
            }

            struct EducationSchoolRecord: Codable {
                let numeroUai: String
                let appellationOfficielle: String
                let commune: String
                let codePostal: String
                let latitude: Double
                let longitude: Double
            }

            let apiResponse = try decoder.decode(EducationAPIResponse.self, from: data)

            return apiResponse.results.compactMap { record in
                guard !record.numeroUai.isEmpty else { return nil }
                let baseURL = "https://\(record.numeroUai.lowercased()).index-education.net/pronote/"
                return School(
                    id: record.numeroUai,
                    name: record.appellationOfficielle,
                    city: record.commune,
                    postalCode: record.codePostal,
                    latitude: record.latitude,
                    longitude: record.longitude,
                    url: baseURL
                )
            }
        } catch let error as SchoolSpaceError {
            throw error
        } catch {
            throw SchoolSpaceError.networkError(error)
        }
    }

    // MARK: - Validation URL établissement

    func validateEstablishmentURL(_ urlString: String) async throws -> String {
        let normalized = normalizeURL(urlString)

        guard normalized.hasPrefix("https://"),
              normalized.contains(".index-education.net") else {
            throw SchoolSpaceError.invalidURL(urlString)
        }

        let baseURL = extractBaseURL(from: normalized)
        let loginURL = baseURL + "mobile.eleve.html"

        var request = URLRequest(url: URL(string: loginURL)!)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...399).contains(httpResponse.statusCode) else {
                throw SchoolSpaceError.schoolNotFound
            }
            return loginURL
        } catch let error as SchoolSpaceError {
            throw error
        } catch {
            throw SchoolSpaceError.networkError(error)
        }
    }

    // MARK: - Utilitaires URL

    private func normalizeURL(_ urlString: String) -> String {
        var url = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
            url = "https://" + url
        }

        while url.hasSuffix("/") && !url.hasSuffix("://") {
            url.removeLast()
        }

        return url
    }

    private func extractBaseURL(from url: String) -> String {
        let pattern = #"(https://[^/]+\.index-education\.net/pronote/)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
           let range = Range(match.range(at: 1), in: url) {
            return String(url[range])
        }
        return url + "/"
    }
}
