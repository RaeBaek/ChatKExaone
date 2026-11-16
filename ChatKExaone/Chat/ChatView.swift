//
//  ChatView.swift
//  ChatKExaone
//
//  Created by 백래훈 on 11/10/26.
//

import Foundation
import SwiftUI

/// 대화 선택, 전송, 스트리밍 표시와 로컬 복원을 연결하는 채팅 화면.
struct ChatView: View {
    private static let localStore = LocalChatStore()

    // MARK: - 화면 상태

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

    // MARK: - 대화와 표시 메시지

    private var messages: [ChatMessage] {
        conversations.first(where: { $0.id == activeConversationID })?.messages ?? []
    }

    /// 화면에만 대기 중인 질문과 답변을 합친다. 본문이 비어 있으면 답변 말풍선에 타이머를 표시한다.
    private var visibleMessages: [ChatMessage] {
        guard let pendingMessage else { return messages }
        return messages + [pendingMessage, ChatMessage(role: .assistant, content: partialReply)]
    }

    // MARK: - 화면 구성

    var body: some View {
        NavigationStack {
            transcript
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ChatComposer(
                    draft: $draft,
                    isFocused: $isComposerFocused,
                    isSending: pendingMessage != nil,
                    canSend: canSend,
                    errorMessage: errorMessage,
                    historyError: historyError,
                    isHistoryLoaded: isHistoryLoaded,
                    onSend: submitDraft,
                    onRestoreHistory: { Task { await restoreHistory() } }
                )
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
                ChatConversationList(
                    conversations: conversations,
                    activeConversationID: activeConversationID,
                    onOpen: openConversation
                )
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
            // 질문이 등록되면 화면 수명에 연결된 작업으로 전송을 시작한다.
            .task(id: pendingMessage) {
                guard let pendingMessage else { return }
                await send(pendingMessage)
            }
        }
    }

    private var transcript: some View {
        let visibleMessages = self.visibleMessages

        return ScrollView {
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
        // 화면에 다 들어오는 대화는 상단에 정렬해 큰 제목 아래에서 시작하게 한다.
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
        // 이전 메시지를 읽으려고 위로 스크롤한 경우에는 새 답변을 따라가지 않는다.
        .onChange(of: partialReply) { _, reply in
            if !reply.isEmpty, isNearBottom, scrollPosition.edge != .bottom {
                scrollPosition.scrollTo(edge: .bottom)
            }
        }
    }

    // MARK: - 대화 선택과 전송 준비

    private func openConversation(_ id: UUID) {
        isConversationListPresented = false
        guard id != activeConversationID else { return }
        activeConversationID = id
        isNearBottom = true
        draft = ""
        errorMessage = nil
    }

    private var canSend: Bool {
        !isLoadingLocalData && isHistoryLoaded && !isUpdatingAPIKey
            && pendingMessage == nil && !apiKey.isEmpty && !trimmedDraft.isEmpty
    }

    private func submitDraft() {
        isComposerFocused = false
        thinkingSince = ContinuousClock().now
        pendingMessage = ChatMessage(role: .user, content: trimmedDraft)
        draft = ""
        errorMessage = nil
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 로컬 저장과 복원

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

    // MARK: - 응답 수신

    /// 선택한 대화의 맥락을 보내고, 스트림이 정상 종료되면 질문과 답변을 함께 저장한다.
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
                // 디스크 저장에 실패해도 받은 답변은 현재 화면에서 계속 볼 수 있다.
                historyError = "대화 저장에 실패했습니다."
            }
            conversations = updatedConversations
        } catch {
            // 화면 이탈로 취소된 경우에도 질문은 복원하되 오류 문구는 띄우지 않는다.
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
