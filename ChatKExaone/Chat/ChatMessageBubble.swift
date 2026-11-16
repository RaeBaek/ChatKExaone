//
//  ChatMessageBubble.swift
//  ChatKExaone
//
//  Created by 백래훈 on 11/10/26.
//

import Foundation
import SwiftUI

/// 질문, 답변 또는 첫 답변을 기다리는 상태를 말풍선에 표시한다.
struct ChatMessageBubble: View {
    let message: ChatMessage
    let thinkingSince: ContinuousClock.Instant?

    var body: some View {
        let isUser = message.role == .user

        Group {
            if let thinkingSince, !isUser, message.content.isEmpty {
                ThinkingIndicator(startedAt: thinkingSince)
            } else {
                let content = displayContent
                let speaker = isUser ? Text("나") : Text("엑사원")

                Text(content)
                    .accessibilityLabel(Text("\(speaker), \(String(content.characters))"))
            }
        }
        .padding(12)
        .background(
            isUser ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private var displayContent: AttributedString {
        // 답변의 인라인 Markdown을 해석하면서 원래 줄바꿈을 보존한다.
        if message.role == .assistant,
           let markdown = try? AttributedString(
               markdown: message.content,
               options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
           ) {
            return markdown
        }
        return AttributedString(message.content)
    }
}

// MARK: - 답변 대기 표시

private struct ThinkingIndicator: View {
    let startedAt: ContinuousClock.Instant

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .accessibilityHidden(true)

            // TimelineView로 매초 다시 그리고, 경과 시간은 시스템 시각 변경의 영향을 받지 않는 시계로 잰다.
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let elapsed = startedAt.duration(to: ContinuousClock().now)
                let seconds = elapsed.components.seconds
                let duration = Duration.seconds(seconds)
                Text("생각 중… \(shortTime(seconds))")
                    .monospacedDigit()
                    // 화면에는 단위를 축약하고 VoiceOver에는 전체 단위 이름을 제공한다.
                    .accessibilityLabel(
                        Text("생각 중… \(duration, format: .units(allowed: [.hours, .minutes, .seconds], width: .wide))")
                    )
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private func shortTime(_ seconds: Int64) -> String {
        let hours = seconds / 3600
        let minutes = seconds / 60 % 60
        let remainingSeconds = seconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m \(remainingSeconds)s"
        }
        if minutes > 0 {
            return "\(minutes)m \(remainingSeconds)s"
        }
        return "\(remainingSeconds)s"
    }
}
