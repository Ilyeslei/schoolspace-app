//
//  KeychainService.swift
//  SchoolSpaceApp
//
//  Gestion sécurisée du Keychain iOS pour stocker les tokens de session
//  Protection maximale : kSecAttrAccessibleWhenUnlockedThisDeviceOnly
//

import Foundation
import Security

final class KeychainService {
    static let shared = KeychainService()

    private let serviceIdentifier = "com.example.schoolspace.session"
    private let accountName = "user_session"

    private init() {}

    // MARK: - Sauvegarde

    func save(_ session: UserSession) throws {
        let data = try JSONEncoder().encode(session)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: accountName,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data
        ]

        // Supprimer l'existant s'il y en a un
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SchoolSpaceError.unknown(NSError(domain: "Keychain", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Impossible de sauvegarder la session"]))
        }
    }

    // MARK: - Lecture

    func load() -> UserSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: accountName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let session = try? JSONDecoder().decode(UserSession.self, from: data) else {
            return nil
        }

        return session
    }

    // MARK: - Suppression

    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: accountName
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Mise à jour du token seul

    func updateToken(_ newToken: String, expiresAt: Date) throws {
        guard var session = load() else { return }
        session = UserSession(
            userId: session.userId,
            displayName: session.displayName,
            establishmentId: session.establishmentId,
            establishmentUrl: session.establishmentUrl,
            sessionToken: newToken,
            expiresAt: expiresAt
        )
        try save(session)
    }
}