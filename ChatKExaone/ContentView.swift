//
//  ContentView.swift
//  ChatKExaone
//
//  Created by 백래훈 on 11/10/26.
//

import Foundation
import SwiftUI

struct ContentView: View {
    private static let localStore = LocalChatStore()

    @State private var apiKey = ""
    @State private var apiKeyDraft = ""
    @State private var isAPIKeyAlertPresented = false
    @State private var isUpdatingAPIKey = false
    @State private var isLoadingLocalData = true
    @State private var isHistoryLoaded = false
    @State private var historyError: String?
    @State private var draft = ""
    @State private var messages: [ChatMessage] = []
    @State private var pendingMessage: ChatMessage?
    @State private var thinkingSince: ContinuousClock.Instant?
    @State private var partialReply = ""
    @State private var isSending = false
    @State private var isNearBottom = true
    @State private var errorMessage: String?

    private var visibleMessages: [ChatMessage] {
        guard let pendingMessage else { return messages }
        return messages + [pendingMessage, ChatMessage(role: .assistant, content: partialReply)]
    }

    var body: some View {
        let visibleMessages = self.visibleMessages

        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(visibleMessages.indices, id: \.self) { index in
                            ChatMessageBubble(
                                message: visibleMessages[index],
                                thinkingSince: index == visibleMessages.count - 1 ? thinkingSince : nil
                            )
                        }
                    }
                    .padding()
                }
                .onChange(of: visibleMessages.count) { _, count in
                    if count > 0, partialReply.isEmpty {
                        proxy.scrollTo(count - 1, anchor: .bottom)
                    }
                }
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentSize.height - geometry.visibleRect.maxY < 100
                } action: { _, nearBottom in
                    isNearBottom = nearBottom
                }
                .onChange(of: partialReply) { _, reply in
                    if !reply.isEmpty, isNearBottom {
                        proxy.scrollTo(visibleMessages.count - 1, anchor: .bottom)
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
                        .disabled(isLoadingLocalData || isUpdatingAPIKey || pendingMessage != nil)
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
                        let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        apiKeyDraft = ""
                        isUpdatingAPIKey = true
                        Task { await applyAPIKey(key) }
                    }
                }
            }
            .task {
                guard isLoadingLocalData else { return }
                do {
                    apiKey = try await Self.localStore.loadAPIKey()
                } catch {
                    errorMessage = "저장된 API 키를 불러오지 못했습니다."
                }
                await restoreHistory()
                isLoadingLocalData = false
            }
            .task(id: pendingMessage) {
                guard let pendingMessage else { return }
                await send(pendingMessage)
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 12) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if let historyError {
                Text(historyError)
                    .font(.footnote)
                    .foregroundStyle(.red)

                if !isHistoryLoaded {
                    Button("대화 다시 불러오기") {
                        Task { await restoreHistory() }
                    }
                    .font(.footnote)
                }
            }

            HStack(alignment: .bottom) {
                TextField("ChatKEXAONE에게 물어보세요", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .disabled(pendingMessage != nil)

                Button("전송") {
                    thinkingSince = ContinuousClock().now
                    pendingMessage = ChatMessage(role: .user, content: trimmedDraft)
                    draft = ""
                    errorMessage = nil
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    isLoadingLocalData || !isHistoryLoaded || isUpdatingAPIKey
                        || pendingMessage != nil || apiKey.isEmpty || trimmedDraft.isEmpty
                )
            }
        }
        .padding()
        .background(.background)
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func applyAPIKey(_ key: String) async {
        defer { isUpdatingAPIKey = false }
        do {
            try await Self.localStore.saveAPIKey(key)
            apiKey = key
            errorMessage = nil
        } catch {
            errorMessage = "API 키 변경 내용을 저장하지 못했습니다."
        }
    }

    private func restoreHistory() async {
        historyError = nil
        do {
            messages = try await Self.localStore.loadMessages()
            isHistoryLoaded = true
        } catch {
            historyError = "저장된 대화를 불러오지 못했습니다."
        }
    }

    @MainActor
    private func send(_ message: ChatMessage) async {
        guard !isSending else { return }
        isSending = true
        defer {
            thinkingSince = nil
            partialReply = ""
            pendingMessage = nil
            isSending = false
        }

        do {
            let answer = try await ExaoneAPI.reply(to: messages + [message], apiKey: apiKey) { reply in
                if partialReply.isEmpty, reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return
                }
                partialReply = reply
            }
            try Task.checkCancellation()

            let updatedMessages = messages + [message, ChatMessage(role: .assistant, content: answer)]
            do {
                try await Self.localStore.saveMessages(updatedMessages)
                historyError = nil
            } catch {
                historyError = "대화 저장에 실패했습니다."
            }
            messages = updatedMessages
        } catch {
            draft = message.content
            guard !Task.isCancelled else { return }
            if (error as? URLError)?.code == .timedOut {
                errorMessage = "응답 대기 시간이 초과되었습니다. 다시 시도해 주세요."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct ChatMessageBubble: View {
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

private struct ThinkingIndicator: View {
    let startedAt: ContinuousClock.Instant

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .accessibilityHidden(true)

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let elapsed = startedAt.duration(to: ContinuousClock().now)
                let duration = Duration.seconds(elapsed.components.seconds)
                Text("생각 중… \(duration, format: .units(allowed: [.hours, .minutes, .seconds], width: .wide))")
                    .monospacedDigit()
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
}
