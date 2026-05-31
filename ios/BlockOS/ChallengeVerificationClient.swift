import Foundation
import UIKit

struct TouchGrassPrompt: Codable, Hashable {
    let id: String
    let text: String
}

struct ChallengeAttemptStart: Codable, Hashable {
    let attemptId: String
    let prompt: String
    let promptText: String
    let uploadUrl: URL
    let submitUrl: URL
    let expiresAt: Date

    var touchGrassPrompt: TouchGrassPrompt {
        TouchGrassPrompt(id: prompt, text: promptText)
    }
}

struct ChallengeVerificationResult: Codable, Hashable {
    let passed: Bool
    let confidence: Double
    let labels: [String]
    let reason: String
    let redFlags: [String]
}

struct ChallengeAttemptStatus: Codable, Hashable {
    let id: String
    let sessionId: String
    let prompt: String
    let promptText: String
    let status: String
    let result: ChallengeVerificationResult?
    let createdAt: Date
    let expiresAt: Date
}

struct ChallengeAttemptStatusEnvelope: Codable, Hashable {
    let attempt: ChallengeAttemptStatus
}

struct ChallengeVerificationConfiguration {
    let baseURL: URL?
    let apiToken: String?

    var isEnabled: Bool {
        baseURL != nil
    }

    static func load(
        bundle: Bundle = .main,
        defaults: UserDefaults = .standard
    ) -> ChallengeVerificationConfiguration {
        let baseURLText = sanitized(
            defaults.string(forKey: Keys.baseURL)
                ?? bundle.object(forInfoDictionaryKey: Keys.baseURL) as? String
        )
        let apiToken = sanitized(
            defaults.string(forKey: Keys.apiToken)
                ?? bundle.object(forInfoDictionaryKey: Keys.apiToken) as? String
        )

        return ChallengeVerificationConfiguration(
            baseURL: baseURLText.flatMap(URL.init(string:)),
            apiToken: apiToken
        )
    }

    private static func sanitized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else {
            return nil
        }

        return trimmed
    }

    private enum Keys {
        static let baseURL = "BLOCKOS_CHALLENGE_API_BASE_URL"
        static let apiToken = "BLOCKOS_CHALLENGE_API_TOKEN"
    }
}

enum ChallengeVerificationError: LocalizedError {
    case disabled
    case invalidImage
    case requestFailed(String)
    case failedValidation(String)

    var errorDescription: String? {
        switch self {
        case .disabled:
            return "Challenge verification is not configured."
        case .invalidImage:
            return "The photo could not be prepared for verification."
        case let .requestFailed(message):
            return message
        case let .failedValidation(reason):
            return reason
        }
    }
}

final class ChallengeVerificationClient {
    private let configuration: ChallengeVerificationConfiguration
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder = JSONEncoder()

    init(
        configuration: ChallengeVerificationConfiguration = .load(),
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(Self.decodeISO8601Date)
        self.decoder = decoder
    }

    var isEnabled: Bool {
        configuration.isEnabled
    }

    func createAttempt(sessionID: UUID) async throws -> ChallengeAttemptStart {
        guard let baseURL = configuration.baseURL else {
            throw ChallengeVerificationError.disabled
        }

        var request = URLRequest(url: baseURL.appending(path: "challenge-attempts"))
        request.httpMethod = "POST"
        applyHeaders(to: &request)
        request.httpBody = try encoder.encode(
            CreateAttemptBody(
                deviceId: ChallengeDeviceIdentity.deviceID,
                sessionId: sessionID.uuidString
            )
        )

        let data = try await perform(request)
        return try decoder.decode(ChallengeAttemptStart.self, from: data)
    }

    func verify(image: UIImage, attempt: ChallengeAttemptStart) async throws -> ChallengeAttemptStatus {
        guard let imageData = image.challengeJPEGData() else {
            throw ChallengeVerificationError.invalidImage
        }

        var uploadRequest = URLRequest(url: attempt.uploadUrl)
        uploadRequest.httpMethod = "PUT"
        uploadRequest.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        uploadRequest.setValue("\(imageData.count)", forHTTPHeaderField: "Content-Length")
        applyAuth(to: &uploadRequest)

        _ = try await perform(uploadRequest, body: imageData)

        var submitRequest = URLRequest(url: attempt.submitUrl)
        submitRequest.httpMethod = "POST"
        applyHeaders(to: &submitRequest)

        let submitData = try await perform(submitRequest)
        let envelope = try decoder.decode(ChallengeAttemptStatusEnvelope.self, from: submitData)

        guard envelope.attempt.result?.passed == true else {
            throw ChallengeVerificationError.failedValidation(
                envelope.attempt.result?.reason ?? "The photo did not pass verification."
            )
        }

        return envelope.attempt
    }

    private func perform(_ request: URLRequest, body: Data? = nil) async throws -> Data {
        var uploadRequest = request
        let uploadBody = body ?? request.httpBody ?? Data()
        uploadRequest.httpBody = nil
        let (data, response) = try await session.upload(for: uploadRequest, from: uploadBody)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChallengeVerificationError.requestFailed("Challenge service returned an invalid response.")
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let message = String(data: data, encoding: .utf8)
                ?? "Challenge service returned HTTP \(httpResponse.statusCode)."
            throw ChallengeVerificationError.requestFailed(message)
        }

        return data
    }

    private func applyHeaders(to request: inout URLRequest) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(to: &request)
    }

    private func applyAuth(to request: inout URLRequest) {
        guard let apiToken = configuration.apiToken else {
            return
        }

        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
    }

    private struct CreateAttemptBody: Encodable {
        let deviceId: String
        let sessionId: String
    }

    private static func decodeISO8601Date(from decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) {
            return date
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Invalid ISO 8601 date: \(value)"
        )
    }
}

private enum ChallengeDeviceIdentity {
    private static let key = "blockos.challenge-device-id"

    static var deviceID: String {
        let defaults = UserDefaults.standard

        if let existing = defaults.string(forKey: key), !existing.isEmpty {
            return existing
        }

        let newID = UUID().uuidString
        defaults.set(newID, forKey: key)
        return newID
    }
}

private extension UIImage {
    func challengeJPEGData(maxDimension: CGFloat = 1280, compressionQuality: CGFloat = 0.82) -> Data? {
        let scale = min(1, maxDimension / max(size.width, size.height))
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let image = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }

        return image.jpegData(compressionQuality: compressionQuality)
    }
}
