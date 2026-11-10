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
    @State private var isConversationListPresented = false
    @State private var conversations: [ChatConversation] = []
    @State private var activeConversationID = UUID()
    @FocusState private var isComposerFocused: Bool
    @State private var draft = ""
    @State private var pendingMessage: ChatMessage?
    @State private var thinkingSince: ContinuousClock.Instant?
    @State private var partialReply = ""
    @State private var isSending = false
    @State private var scrollPosition = ScrollPosition()
    @State private var isNearBottom = true
    @State private var errorMessage: String?

    private var messages: [ChatMessage] {
        conversations.first(where: { $0.id == activeConversationID })?.messages ?? []
    }

    private var visibleMessages: [ChatMessage] {
        guard let pendingMessage else { return messages }
        return messages + [pendingMessage, ChatMessage(role: .assistant, content: partialReply)]
    }

    var body: some View {
        let visibleMessages = self.visibleMessages

        NavigationStack {
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
            .defaultScrollAnchor(.top, for: .alignment)
            .scrollPosition($scrollPosition)
            .onChange(of: visibleMessages.count) { _, count in
                if count > 0, partialReply.isEmpty {
                    scrollPosition.scrollTo(edge: .bottom)
                }
            }
            .onChange(of: activeConversationID) {
                scrollPosition.scrollTo(edge: visibleMessages.isEmpty ? .top : .bottom)
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentSize.height - geometry.visibleRect.maxY < 100
            } action: { _, nearBottom in
                isNearBottom = nearBottom
            }
            .onChange(of: partialReply) { _, reply in
                if !reply.isEmpty, isNearBottom, scrollPosition.edge != .bottom {
                    scrollPosition.scrollTo(edge: .bottom)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                composer
            }
            .navigationTitle("ChatKEXAONE")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isComposerFocused = false
                        isConversationListPresented = true
                    } label: {
                        Label("채팅 목록", systemImage: "list.bullet")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(!isHistoryLoaded || pendingMessage != nil)
                }

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
            .sheet(isPresented: $isConversationListPresented) {
                conversationList
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

    private var conversationList: some View {
        NavigationStack {
            Group {
                if conversations.isEmpty {
                    ContentUnavailableView("저장된 채팅이 없습니다", systemImage: "bubble.left.and.bubble.right")
                } else {
                    List(conversations) { conversation in
                        Button {
                            openConversation(conversation.id)
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
                    Button("닫기") { isConversationListPresented = false }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("새 대화") {
                        openConversation(UUID())
                    }
                }
            }
        }
    }

    private func openConversation(_ id: UUID) {
        isConversationListPresented = false
        guard id != activeConversationID else { return }
        activeConversationID = id
        isNearBottom = true
        draft = ""
        errorMessage = nil
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
                    .focused($isComposerFocused)
                    .disabled(pendingMessage != nil)

                Button("전송") {
                    isComposerFocused = false
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
            conversations = try await Self.localStore.loadConversations()
                .sorted { $0.lastQuestionAt > $1.lastQuestionAt }
            if let mostRecent = conversations.first {
                activeConversationID = mostRecent.id
            }
            isHistoryLoaded = true
        } catch {
            historyError = "저장된 대화를 불러오지 못했습니다."
        }
    }

    @MainActor
    private func send(_ message: ChatMessage) async {
        guard !isSending else { return }
        isSending = true
        let conversationID = activeConversationID
        let questionDate = Date()
        let requestMessages = messages + [message]
        defer {
            thinkingSince = nil
            partialReply = ""
            pendingMessage = nil
            isSending = false
        }

        do {
            let answer = try await ExaoneAPI.reply(to: requestMessages, apiKey: apiKey) { reply in
                partialReply = reply
            }
            try Task.checkCancellation()

            let conversation = ChatConversation(
                id: conversationID,
                lastQuestionAt: questionDate,
                messages: requestMessages + [ChatMessage(role: .assistant, content: answer)]
            )
            let updatedConversations = ([conversation] + conversations.filter { $0.id != conversationID })
                .sorted { $0.lastQuestionAt > $1.lastQuestionAt }
            do {
                try await Self.localStore.saveConversations(updatedConversations)
                historyError = nil
            } catch {
                historyError = "대화 저장에 실패했습니다."
            }
            conversations = updatedConversations
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
                let seconds = elapsed.components.seconds
                let duration = Duration.seconds(seconds)
                Text("생각 중… \(shortTime(seconds))")
                    .monospacedDigit()
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
