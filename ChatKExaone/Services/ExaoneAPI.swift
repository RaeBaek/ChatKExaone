//
//  ExaoneAPI.swift
//  ChatKExaone
//
//  Created by 백래훈 on 11/10/26.
//

import Foundation

/// 엑사원 채팅 요청을 만들고 SSE 응답에서 답변 본문을 추출한다.
nonisolated enum ExaoneAPI {
    // MARK: - 네트워크 설정

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        // 수신 데이터가 없는 시간과 요청 전체 시간을 별도로 제한한다.
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 600
        return URLSession(configuration: configuration)
    }()

    // MARK: - 요청과 응답 형식

    private struct RequestBody: Encodable {
        let model: String
        let reasoningEffort: String
        let stream: Bool
        let messages: [ChatMessage]
    }

    private struct StreamChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                // 추론 데이터와 메타데이터는 화면에 전달하지 않으므로 본문만 디코딩한다.
                let content: String?
            }

            let delta: Delta
            let finishReason: String?
        }

        let choices: [Choice]
    }

    private enum APIError: LocalizedError {
        case invalidResponse
        case httpStatus(Int)
        case incompleteStream
        case generationLimit
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
            case .incompleteStream:
                return "답변을 끝까지 받지 못했습니다. 다시 시도해 주세요."
            case .generationLimit:
                return "서버의 생성 한도에 도달해 답변이 중단되었습니다."
            case .emptyReply:
                return "최종 답변이 비어 있습니다. 메시지를 다시 보내보세요."
            }
        }
    }

    // MARK: - 답변 스트리밍

    /// 응답을 메인 액터 밖에서 읽고, 누적된 본문을 메인 액터 콜백으로 전달한다.
    @concurrent
    static func reply(
        to messages: [ChatMessage],
        apiKey: String,
        onPartialReply: @MainActor @Sendable (String) -> Void
    ) async throws -> String {
        let url = URL(string: "https://api.exaone.ai/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(
            RequestBody(model: "k-exaone_v2.5", reasoningEffort: "low", stream: true, messages: messages)
        )

        let (bytes, response) = try await session.bytes(for: request)
        // 정상 종료나 오류로 읽기를 마치면 남아 있는 네트워크 작업을 정리한다.
        defer { bytes.task.cancel() }

        guard let response = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw APIError.httpStatus(response.statusCode)
        }
        guard response.mimeType == "text/event-stream" else {
            throw APIError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let clock = ContinuousClock()
        var lastUpdate: ContinuousClock.Instant?
        var reply = ""
        var finishReason: String?

        /*
         엑사원 스트림의 data 행에는 JSON 청크 또는 [DONE]이 들어온다.
         종료 사유가 stop이고 [DONE]을 받았을 때 완성된 답변을 반환한다.
         */
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard !payload.isEmpty else { continue }

            if payload == "[DONE]" {
                if finishReason == "length" {
                    throw APIError.generationLimit
                }
                guard finishReason == "stop" else { throw APIError.incompleteStream }
                let answer = reply.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !answer.isEmpty else { throw APIError.emptyReply }
                await onPartialReply(answer)
                return answer
            }

            guard let chunk = try? decoder.decode(StreamChunk.self, from: Data(payload.utf8)) else {
                throw APIError.invalidResponse
            }
            guard let choice = chunk.choices.first else { continue }
            if let reason = choice.finishReason {
                finishReason = reason
            }
            guard let content = choice.delta.content, !content.isEmpty else { continue }

            // 첫 본문 앞 공백만 제거해 스트리밍 중 여백을 없애고, 이후 줄바꿈은 보존한다.
            let fragment = reply.isEmpty ? content.drop(while: \.isWhitespace) : content[...]
            guard !fragment.isEmpty else { continue }
            reply.append(contentsOf: fragment)
            let now = clock.now
            // 첫 조각은 바로 전달하고, 이후에는 말풍선 갱신 빈도를 줄인다.
            if lastUpdate.map({ $0.duration(to: now) >= .milliseconds(80) }) ?? true {
                await onPartialReply(reply)
                lastUpdate = now
            }
        }
        throw APIError.incompleteStream
    }
}
