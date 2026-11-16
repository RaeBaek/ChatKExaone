# ChatKEXAONE

K-EXAONE 2.5와 대화할 수 있는 SwiftUI iOS 앱입니다. 답변을 스트리밍으로 표시하고, 기기에 저장된 대화를 다시 열어 이어갈 수 있습니다.

SwiftUI와 스트리밍 API 연동을 연습하기 위해 만든 비상업적 개인 프로젝트입니다. LG AI연구원의 공식 ChatEXAONE 서비스와는 별개로 개발했습니다.

## 스트리밍을 도입한 이유

초기 구현에서는 서버가 답변 생성을 끝낼 때까지 기다렸고, 일부 긴 응답에서 요청 타임아웃이 발생했습니다. 이후 [EXAONE API의 SSE 응답 형식](https://docs.exaone.ai/ko/docs/k-exaone-2.5)에 맞춰 `URLSession.bytes(for:)`로 답변을 순차 수신하도록 바꿨습니다.

- 첫 본문이 오기 전에는 질문 아래에 ‘생각 중…’과 경과 시간을 표시합니다. 본문이 도착하면 같은 말풍선에서 답변을 이어서 보여줍니다.
- 응답 청크를 처리하는 작업과 메인 액터의 화면 갱신을 분리하고, 스트리밍 중 말풍선 갱신 빈도를 제한합니다.
- `finish_reason: "stop"`과 `[DONE]`을 확인한 뒤 질문과 답변을 함께 저장합니다. 타임아웃이나 연결 중단이 발생하면 질문을 입력창에 복원해 다시 보낼 수 있게 합니다.

## 주요 기능

- 인라인 Markdown을 적용한 답변 표시
- 새 대화 시작 및 기존 대화 이어가기
- 마지막 질문 시각 기준으로 대화 정렬 및 첫 질문에서 제목 생성
- API 키는 Keychain에, 대화 내역은 앱의 Application Support 디렉터리에 JSON으로 저장
- 이전 버전의 단일 대화 파일을 대화 목록 형식으로 이전

## 실행 방법

- 개발 환경은 Xcode 26.6이며, 최소 지원 버전은 iOS 26.5입니다.
- API 요청에는 본인의 EXAONE API 키와 인터넷 연결이 필요합니다. [EXAONE API 시작 가이드](https://docs.exaone.ai/ko/docs/quick-start)

```sh
git clone https://github.com/RaeBaek/ChatKExaone.git
cd ChatKExaone
open ChatKExaone.xcodeproj
```

1. Xcode에서 `ChatKExaone` 스킴과 iOS 시뮬레이터를 선택해 실행합니다.
2. 앱 오른쪽 상단의 열쇠 버튼에서 EXAONE API 키를 입력하고 **적용**을 누릅니다.
3. 질문을 보내 답변을 확인합니다. 왼쪽 상단의 목록 버튼에서 새 대화를 시작하거나 저장된 대화를 열 수 있습니다.

## 프로젝트 구조

| 경로 | 역할 |
| --- | --- |
| [ChatKExaoneApp.swift](ChatKExaone/ChatKExaoneApp.swift) | 앱 진입점과 루트 화면 |
| [Chat/](ChatKExaone/Chat) | 채팅 상태, 입력창, 대화 목록, 말풍선 |
| [Models/ChatModels.swift](ChatKExaone/Models/ChatModels.swift) | 메시지와 대화 모델 |
| [Services/ExaoneAPI.swift](ChatKExaone/Services/ExaoneAPI.swift) | EXAONE 요청과 SSE 스트림 처리 |
| [Services/LocalChatStore.swift](ChatKExaone/Services/LocalChatStore.swift) | Keychain, 대화 파일 저장 및 이전 |
