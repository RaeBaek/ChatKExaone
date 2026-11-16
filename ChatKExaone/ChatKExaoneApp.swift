//
//  ChatKExaoneApp.swift
//  ChatKExaone
//
//  Created by 백래훈 on 11/10/26.
//

import SwiftUI

/// 앱의 진입점. 윈도우마다 채팅 화면을 루트 뷰로 표시한다.
@main
struct ChatKExaoneApp: App {
    var body: some Scene {
        WindowGroup {
            ChatView()
        }
    }
}
