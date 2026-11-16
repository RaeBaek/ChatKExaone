//
//  ChatComposer.swift
//  ChatKExaone
//
//  Created by 백래훈 on 11/10/26.
//

import SwiftUI

/// 입력창과 오류를 표시하고, 전송과 복원은 ChatView에 위임한다.
struct ChatComposer: View {
    // ChatView의 초안을 직접 편집하고, 키보드 포커스 제어도 공유한다.
    @Binding var draft: String
    let isFocused: FocusState<Bool>.Binding
    let isSending: Bool
    let canSend: Bool
    let errorMessage: String?
    let historyError: String?
    let isHistoryLoaded: Bool
    let onSend: () -> Void
    let onRestoreHistory: () -> Void

    var body: some View {
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

                // 복원에 실패한 경우에만 다시 불러오기 동작을 제공한다.
                if !isHistoryLoaded {
                    Button("대화 다시 불러오기", action: onRestoreHistory)
                        .font(.footnote)
                }
            }

            HStack(alignment: .bottom) {
                TextField("ChatKEXAONE에게 물어보세요", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .focused(isFocused)
                    .disabled(isSending)

                Button("전송", action: onSend)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSend)
            }
        }
        .padding()
        .background(.background)
    }
}
