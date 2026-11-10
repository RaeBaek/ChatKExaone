//
//  LocalChatStore.swift
//  ChatKExaone
//
//  Created by 백래훈 on 11/10/26.
//

import Foundation
import Security

nonisolated struct ChatMessage: Codable, Equatable, Sendable {
    enum Role: String, Codable, Sendable {
        case user, assistant
    }

    let role: Role
    let content: String
}

actor LocalChatStore {
    private enum KeychainError: Error {
        case status(OSStatus)
        case invalidData
    }

    private var keyQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.raebaek.ChatKExaone",
            kSecAttrAccount as String: "exaone-api-key"
        ]
    }

    func loadAPIKey() throws -> String {
        var query = keyQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return ""
        }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        guard let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return key
    }

    func saveAPIKey(_ key: String) throws {
        let query = keyQuery
        if key.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError.status(status)
            }
            return
        }

        let data = Data(key.utf8)
        let changes = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    func loadMessages() throws -> [ChatMessage] {
        let url = try historyURL()
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([ChatMessage].self, from: data)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        }
    }

    func saveMessages(_ messages: [ChatMessage]) throws {
        let data = try JSONEncoder().encode(messages)
        try data.write(to: historyURL(), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func historyURL() throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return directory.appendingPathComponent("chat-history.json")
    }
}
