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

nonisolated struct ChatConversation: Codable, Identifiable, Sendable {
    let id: UUID
    let lastQuestionAt: Date
    let messages: [ChatMessage]

    var title: String {
        guard let question = messages.first(where: { $0.role == .user }) else {
            return "새 대화"
        }
        let text = question.content.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let prefix = text.prefix(32)
        return prefix.endIndex == text.endIndex ? String(prefix) : String(prefix) + "…"
    }
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

    func loadConversations() throws -> [ChatConversation] {
        let directory = try historyDirectory()
        do {
            let data = try Data(contentsOf: directory.appendingPathComponent("chat-conversations.json"))
            return try JSONDecoder().decode([ChatConversation].self, from: data)
        } catch CocoaError.fileReadNoSuchFile {
            let legacyURL = directory.appendingPathComponent("chat-history.json")
            let data: Data
            do {
                data = try Data(contentsOf: legacyURL)
            } catch CocoaError.fileReadNoSuchFile {
                return []
            }

            let messages = try JSONDecoder().decode([ChatMessage].self, from: data)
            guard !messages.isEmpty else { return [] }

            let modifiedAt = try? legacyURL.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            let conversations = [
                ChatConversation(id: UUID(), lastQuestionAt: modifiedAt ?? .distantPast, messages: messages)
            ]
            try saveConversations(conversations)
            return conversations
        }
    }

    func saveConversations(_ conversations: [ChatConversation]) throws {
        let data = try JSONEncoder().encode(conversations)
        let url = try historyDirectory().appendingPathComponent("chat-conversations.json")
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func historyDirectory() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }
}
