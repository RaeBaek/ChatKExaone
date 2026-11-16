//
//  ChatConversationList.swift
//  ChatKExaone
//
//  Created by 백래훈 on 11/10/26.
//

import Foundation
import SwiftUI

/// ChatView에서 최신순으로 정렬한 대화를 표시하는 시트.
struct ChatConversationList: View {
    @Environment(\.dismiss) private var dismiss

    let conversations: [ChatConversation]
    let activeConversationID: UUID
    let onOpen: (UUID) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if conversations.isEmpty {
                    ContentUnavailableView("저장된 채팅이 없습니다", systemImage: "bubble.left.and.bubble.right")
                } else {
                    List(conversations) { conversation in
                        Button {
                            onOpen(conversation.id)
                        } label: {
                            HStack {
                                Text(verbatim: conversation.title)
                                Spacer()
                                if conversation.id == activeConversationID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                        .accessibilityHidden(true)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(conversation.id == activeConversationID ? .isSelected : [])
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("채팅 목록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    // 새 ID만 선택하고, 첫 답변이 완료되면 ChatView에서 목록에 추가한다.
                    Button("새 대화") {
                        onOpen(UUID())
                    }
                }
            }
        }
    }
}
