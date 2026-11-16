//
//  LocalChatStore.swift
//  ChatKExaone
//
//  Created by 백래훈 on 11/10/26.
//

import Foundation
import Security

/// Keychain과 로컬 대화 파일에 대한 접근을 직렬화한다.
actor LocalChatStore {
    // MARK: - API 키

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

    /// 저장된 키를 갱신한다. 빈 문자열을 받으면 Keychain 항목을 삭제한다.
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

    // MARK: - 대화 내역

    /// 목록 파일이 없으면 이전 버전의 단일 대화 파일을 읽어 목록 형식으로 저장한다.
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

            // 이전 파일에는 질문 시각이 없으므로 파일 수정 시각을 정렬 기준으로 사용한다.
            let modifiedAt = try? legacyURL.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            let conversations = [
                ChatConversation(id: UUID(), lastQuestionAt: modifiedAt ?? .distantPast, messages: messages)
            ]
            try saveConversations(conversations)
            return conversations
        }
    }

    /// 대화 목록 전체를 원자적으로 교체해 쓰기가 중단돼도 일부만 기록된 파일이 남지 않게 한다.
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
