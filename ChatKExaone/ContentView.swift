//
//  ContentView.swift
//  ChatKExaone
//
//  Created by 백래훈 on 11/10/26.
//

import Foundation
import SwiftUI

struct ContentView: View {
    @State private var apiKey = ""
    @State private var apiKeyDraft = ""
    @State private var isAPIKeyAlertPresented = false
    @State private var draft = ""
    @State private var messages: [ChatMessage] = []
    @State private var pendingMessage: ChatMessage?
    @State private var errorMessage: String?

    private var visibleMessages: [ChatMessage] {
        messages + (pendingMessage.map { [$0] } ?? [])
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(visibleMessages.indices, id: \.self) { index in
                            ChatMessageBubble(message: visibleMessages[index])
                        }
                    }
                    .padding()
                }
                .onChange(of: visibleMessages.count) { _, count in
                    if count > 0 {
                        proxy.scrollTo(count - 1, anchor: .bottom)
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    composer
                }
                .navigationTitle("ChatKEXAONE")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            apiKeyDraft = apiKey
                            isAPIKeyAlertPresented = true
                        } label: {
                            Image(systemName: "key")
                                .accessibilityLabel("API 키 입력")
                        }
                        .disabled(pendingMessage != nil)
                    }
                }
                .alert("API 키 입력", isPresented: $isAPIKeyAlertPresented) {
                    SecureField("API 키", text: $apiKeyDraft)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button("취소", role: .cancel) {
                        apiKeyDraft = ""
                    }
                    Button("적용") {
                        apiKey = apiKeyDraft
                        apiKeyDraft = ""
                    }
                }
            }
            .task(id: pendingMessage) {
                guard let pendingMessage else { return }
                await send(pendingMessage)
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 12) {
            if pendingMessage != nil {
                ProgressView("답변 생성 중")
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack(alignment: .bottom) {
                TextField("메시지", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .disabled(pendingMessage != nil)

                Button("전송") {
                    pendingMessage = ChatMessage(role: .user, content: trimmedDraft)
                    draft = ""
                    errorMessage = nil
                }
                .buttonStyle(.borderedProminent)
                .disabled(pendingMessage != nil || trimmedKey.isEmpty || trimmedDraft.isEmpty)
            }
        }
        .padding()
        .background(.background)
    }

    private var trimmedKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func send(_ message: ChatMessage) async {
        do {
            let answer = try await ExaoneAPI.reply(to: messages + [message], apiKey: trimmedKey)
            try Task.checkCancellation()
            messages.append(contentsOf: [message, ChatMessage(role: .assistant, content: answer)])
        } catch {
            guard !Task.isCancelled else { return }
            draft = message.content
            errorMessage = error.localizedDescription
        }
        pendingMessage = nil
    }
}

private struct ChatMessage: Encodable, Equatable {
    enum Role: String, Encodable {
        case user, assistant
    }

    let role: Role
    let content: String
}

private struct ChatMessageBubble: View {
    let message: ChatMessage

    var body: some View {
        let isUser = message.role == .user
        let content = displayContent
        let speaker = isUser ? Text("나") : Text("엑사원")

        Text(content)
            .padding(12)
            .background(
                isUser ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            .accessibilityLabel(Text("\(speaker), \(String(content.characters))"))
    }

    private var displayContent: AttributedString {
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

private enum ExaoneAPI {
    private struct RequestBody: Encodable {
        let model: String
        let reasoningEffort: String
        let stream: Bool
        let messages: [ChatMessage]
    }

    private struct ResponseBody: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }

            let message: Message
        }

        let choices: [Choice]
    }

    private enum APIError: LocalizedError {
        case invalidResponse
        case httpStatus(Int)
        case emptyReply

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "서버 응답을 확인할 수 없습니다."
            case .httpStatus(401):
                return "인증에 실패했습니다. API 키를 확인하세요."
            case .httpStatus(429):
                return "요청 한도에 도달했습니다. 잠시 후 다시 시도하세요."
            case .httpStatus(let status):
                return "API 요청에 실패했습니다 (HTTP \(status))."
            case .emptyReply:
                return "최종 답변이 비어 있습니다. 메시지를 다시 보내보세요."
            }
        }
    }

    static func reply(to messages: [ChatMessage], apiKey: String) async throws -> String {
        let url = URL(string: "https://api.exaone.ai/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(
            RequestBody(model: "k-exaone_v2.5", reasoningEffort: "low", stream: false, messages: messages)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw APIError.httpStatus(response.statusCode)
        }

        let result = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard let reply = result.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reply.isEmpty else {
            throw APIError.emptyReply
        }

        return reply
    }
}
