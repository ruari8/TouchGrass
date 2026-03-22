import Foundation
import BlockOSDomain

struct OnboardingCoachInput: Sendable {
    let feeling: OnboardingFeeling
    let reductionFocus: String
    let idealDailyMinutes: Int
    let socialMediaMinutes: Int
    let everythingElseMinutes: Int
}

struct OnboardingCoachRecommendation: Decodable, Sendable {
    enum Strictness: String, Decodable, Sendable {
        case gentle
        case balanced
        case strict
    }

    let headline: String
    let summary: String
    let firstAction: String
    let recommendedBlockTargets: [String]
    let strictness: Strictness
}

enum OnboardingCoachError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case emptyContent

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenRouter is not configured."
        case .invalidResponse:
            return "The AI recommendation response could not be parsed."
        case .emptyContent:
            return "The AI recommendation came back empty."
        }
    }
}

struct OpenRouterConfiguration: Sendable {
    let apiKey: String
    let appName: String
    let referer: URL?
    let model: String

    static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main
    ) -> OpenRouterConfiguration? {
        let apiKey = sanitizedValue(
            environment["BLOCKOS_OPENROUTER_API_KEY"]
                ?? bundle.object(forInfoDictionaryKey: "BLOCKOS_OPENROUTER_API_KEY") as? String
        )

        guard let apiKey else {
            return nil
        }

        let appName = sanitizedValue(
            environment["BLOCKOS_OPENROUTER_APP_NAME"]
                ?? bundle.object(forInfoDictionaryKey: "BLOCKOS_OPENROUTER_APP_NAME") as? String
        ) ?? "BlockOS"

        let referer = sanitizedValue(
            environment["BLOCKOS_OPENROUTER_SITE_URL"]
                ?? bundle.object(forInfoDictionaryKey: "BLOCKOS_OPENROUTER_SITE_URL") as? String
        ).flatMap(URL.init(string:))

        return OpenRouterConfiguration(
            apiKey: apiKey,
            appName: appName,
            referer: referer,
            model: "minimax/minimax-m2.7"
        )
    }

    private static func sanitizedValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

struct OpenRouterOnboardingCoach {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    var isConfigured: Bool {
        OpenRouterConfiguration.load() != nil
    }

    func recommendation(for input: OnboardingCoachInput) async throws -> OnboardingCoachRecommendation {
        guard let configuration = OpenRouterConfiguration.load() else {
            throw OnboardingCoachError.missingAPIKey
        }

        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.appName, forHTTPHeaderField: "X-Title")

        if let referer = configuration.referer {
            request.setValue(referer.absoluteString, forHTTPHeaderField: "HTTP-Referer")
        }

        request.httpBody = try JSONSerialization.data(
            withJSONObject: makeRequestBody(input: input, configuration: configuration)
        )

        let (data, response) = try await session.data(for: request)
        let httpResponse = response as? HTTPURLResponse

        guard let httpResponse, 200..<300 ~= httpResponse.statusCode else {
            if
                let errorEnvelope = try? JSONDecoder().decode(OpenRouterErrorEnvelope.self, from: data),
                let message = errorEnvelope.error?.message,
                !message.isEmpty
            {
                throw NSError(
                    domain: "OpenRouterOnboardingCoach",
                    code: httpResponse?.statusCode ?? -1,
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
            }

            throw OnboardingCoachError.invalidResponse
        }

        let completion = try JSONDecoder().decode(OpenRouterChatCompletion.self, from: data)
        guard let content = completion.choices.first?.message.textContent else {
            throw OnboardingCoachError.emptyContent
        }

        guard let contentData = content.data(using: .utf8) else {
            throw OnboardingCoachError.invalidResponse
        }

        return try JSONDecoder().decode(OnboardingCoachRecommendation.self, from: contentData)
    }

    private func makeRequestBody(input: OnboardingCoachInput, configuration: OpenRouterConfiguration) -> [String: Any] {
        [
            "model": configuration.model,
            "temperature": 0.4,
            "max_tokens": 400,
            "reasoning": [
                "effort": "low"
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": "blockos_onboarding_recommendation",
                    "schema": [
                        "type": "object",
                        "additionalProperties": false,
                        "properties": [
                            "headline": [
                                "type": "string",
                                "description": "A short headline for the recommendation card."
                            ],
                            "summary": [
                                "type": "string",
                                "description": "Two or three concise coaching sentences."
                            ],
                            "firstAction": [
                                "type": "string",
                                "description": "One practical next action."
                            ],
                            "recommendedBlockTargets": [
                                "type": "array",
                                "items": [
                                    "type": "string"
                                ],
                                "maxItems": 5
                            ],
                            "strictness": [
                                "type": "string",
                                "enum": ["gentle", "balanced", "strict"]
                            ]
                        ],
                        "required": [
                            "headline",
                            "summary",
                            "firstAction",
                            "recommendedBlockTargets",
                            "strictness"
                        ]
                    ]
                ]
            ],
            "messages": [
                [
                    "role": "system",
                    "content": """
                    You are BlockOS Coach, a calm and direct digital-wellbeing coach inside an iPhone app.

                    The user is setting up friction for distracting apps. Your job is to turn their answers into a realistic starting plan that is strict enough to help but still usable in normal life.

                    Rules:
                    - Be concise, concrete, and non-judgmental.
                    - Do not moralize, shame, or make medical claims.
                    - Prefer practical friction over dramatic abstinence unless the user sounds overwhelmed.
                    - Mention the user's daily target and social split when helpful.
                    - Recommend only common consumer apps if you name apps.
                    - Keep the advice grounded in the user's stated problem, not generic productivity cliches.
                    - Return valid JSON only.
                    """
                ],
                [
                    "role": "user",
                    "content": """
                    Create a BlockOS onboarding recommendation from this intake:
                    - Feeling: \(input.feeling.rawValue)
                    - Behavior to reduce: \(normalizedFocus(from: input.reductionFocus))
                    - Ideal daily screen time: \(input.idealDailyMinutes) minutes
                    - Social media allowance: \(input.socialMediaMinutes) minutes
                    - Everything else allowance: \(input.everythingElseMinutes) minutes

                    Keep the recommendation short enough to fit on a mobile card.
                    """
                ]
            ]
        ]
    }

    private func normalizedFocus(from value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "general phone distraction" : trimmed
    }
}

private struct OpenRouterErrorEnvelope: Decodable {
    struct ErrorPayload: Decodable {
        let message: String?
    }

    let error: ErrorPayload?
}

private struct OpenRouterChatCompletion: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: MessageContent?

            var textContent: String? {
                content?.textValue
            }
        }

        let message: Message
    }

    let choices: [Choice]
}

private enum MessageContent: Decodable {
    case text(String)
    case parts([Part])

    struct Part: Decodable {
        let type: String?
        let text: String?
    }

    var textValue: String? {
        switch self {
        case let .text(value):
            return value
        case let .parts(parts):
            let text = parts
                .filter { $0.type == nil || $0.type == "text" }
                .compactMap(\.text)
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let text = try? container.decode(String.self) {
            self = .text(text)
            return
        }

        self = .parts(try container.decode([Part].self))
    }
}
