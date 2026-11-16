//
//  ChatModels.swift
//  ChatKExaone
//
//  Created by 백래훈 on 11/10/26.
//

import Foundation

/// 채팅 화면, 엑사원 요청 본문, 로컬 대화 파일에서 공유하는 메시지.
nonisolated struct ChatMessage: Codable, Equatable, Sendable {
    enum Role: String, Codable, Sendable {
        case user, assistant
    }

    let role: Role
    let content: String
}

/// 고유 ID로 대화를 구분하고, 마지막 질문 시각으로 목록의 최신순을 결정한다.
nonisolated struct ChatConversation: Codable, Identifiable, Sendable {
    let id: UUID
    let lastQuestionAt: Date
    let messages: [ChatMessage]

    /// 첫 질문의 공백을 정리한 뒤 앞 32자를 목록 제목으로 사용한다.
    var title: String {
        guard let question = messages.first(where: { $0.role == .user }) else {
            return "새 대화"
        }
        let text = question.content.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let prefix = text.prefix(32)
        return prefix.endIndex == text.endIndex ? String(prefix) : String(prefix) + "…"
    }
}
