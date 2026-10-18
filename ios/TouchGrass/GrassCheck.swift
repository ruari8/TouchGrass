import CoreML
import UIKit
import Vision

/// The judgement of whether a Touch Grass photo really shows grass.
struct GrassVerdict {
    var passed: Bool
    /// The checker's confidence that the photo shows grass, from 0 to 1.
    var confidence: Double
    /// What the checker saw, most confident first, for Developer Settings.
    var labels: [String]
}

protocol GrassChecker {
    func check(_ image: UIImage) async throws -> GrassVerdict
}

enum GrassCheckError: LocalizedError {
    case unreadableImage
    case serverNotConfigured
    case serverFailed(String)
    case noCustomModel

    var errorDescription: String? {
        switch self {
        case .unreadableImage: "That photo couldn't be read. Try again."
        case .serverNotConfigured: "The server Grass Check has no URL. Set one in Developer Settings."
        case let .serverFailed(message): "The server Grass Check failed: \(message)"
        case .noCustomModel: "No custom grass model is bundled yet. Add GrassClassifier.mlmodel to the app target."
        }
    }
}

/// Which Grass Check judges photos. App Store builds always use the on-device check;
/// debug and TestFlight builds can switch in Developer Settings.
enum GrassCheckMode: String, CaseIterable, Identifiable {
    case onDevice
    case server
    case customModel

    var id: Self { self }

    var title: String {
        switch self {
        case .onDevice: "Apple on-device"
        case .server: "Server (OpenAI)"
        case .customModel: "Custom model"
        }
    }
}

/// Developer Settings, kept in the app's own defaults.
enum GrassCheckSettings {
    private static let defaults = UserDefaults.standard

    /// True in debug and TestFlight builds. Set at launch from the App Store transaction.
    nonisolated(unsafe) static var isDeveloperBuild: Bool = {
        #if DEBUG
        true
        #else
        false
        #endif
    }()

    static var mode: GrassCheckMode {
        get { GrassCheckMode(rawValue: defaults.string(forKey: "grassCheck.mode") ?? "") ?? .onDevice }
        set { defaults.set(newValue.rawValue, forKey: "grassCheck.mode") }
    }

    static var serverURL: String {
        get { defaults.string(forKey: "grassCheck.serverURL") ?? "" }
        set { defaults.set(newValue, forKey: "grassCheck.serverURL") }
    }

    static var serverToken: String {
        get { defaults.string(forKey: "grassCheck.serverToken") ?? "" }
        set { defaults.set(newValue, forKey: "grassCheck.serverToken") }
    }

    static var onDeviceThreshold: Double {
        get { defaults.object(forKey: "grassCheck.threshold") as? Double ?? 0.4 }
        set { defaults.set(newValue, forKey: "grassCheck.threshold") }
    }

    /// The checker to use for the next photo.
    static func checker() -> GrassChecker {
        switch isDeveloperBuild ? mode : .onDevice {
        case .onDevice: OnDeviceGrassChecker(threshold: onDeviceThreshold)
        case .server: ServerGrassChecker(baseURL: serverURL.isEmpty ? nil : URL(string: serverURL), token: serverToken)
        case .customModel: CustomModelGrassChecker(threshold: onDeviceThreshold)
        }
    }
}

/// Apple's built-in image classifier, run on the phone. Its taxonomy has a "grass" label;
/// other plants such as trees, moss and houseplants have their own labels and don't count.
struct OnDeviceGrassChecker: GrassChecker {
    var threshold = 0.4

    func check(_ image: UIImage) async throws -> GrassVerdict {
        guard let cgImage = image.cgImage else { throw GrassCheckError.unreadableImage }
        let observations = try await ClassifyImageRequest().perform(
            on: cgImage,
            orientation: CGImagePropertyOrientation(image.imageOrientation)
        )
        let confidence = Double(observations.first { $0.identifier == "grass" }?.confidence ?? 0)
        let labels = observations
            .filter { $0.confidence > 0.1 }
            .sorted { $0.confidence > $1.confidence }
            .prefix(5)
            .map { "\($0.identifier) \(Int($0.confidence * 100))%" }
        return GrassVerdict(passed: confidence >= threshold, confidence: confidence, labels: Array(labels))
    }
}

/// The optional Cloudflare Worker in `backend/`, which asks an OpenAI vision model. Photos are judged
/// in memory and never stored.
struct ServerGrassChecker: GrassChecker {
    var baseURL: URL?
    var token: String

    private struct Response: Decodable {
        var passed: Bool
        var confidence: Double
        var labels: [String]
        var reason: String
    }

    func check(_ image: UIImage) async throws -> GrassVerdict {
        guard let baseURL else { throw GrassCheckError.serverNotConfigured }
        guard let jpeg = image.resized(maxDimension: 1280).jpegData(compressionQuality: 0.8) else {
            throw GrassCheckError.unreadableImage
        }
        var request = URLRequest(url: baseURL.appending(path: "grass-check"))
        request.httpMethod = "POST"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.upload(for: request, from: jpeg)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GrassCheckError.serverFailed(String(data: data, encoding: .utf8) ?? "no response")
        }
        let verdict = try JSONDecoder().decode(Response.self, from: data)
        return GrassVerdict(passed: verdict.passed, confidence: verdict.confidence, labels: verdict.labels + [verdict.reason])
    }
}

/// A grass classifier trained with Create ML and bundled as `GrassClassifier.mlmodel`,
/// with a "grass" class. Not bundled yet; this is the hook for one.
struct CustomModelGrassChecker: GrassChecker {
    var threshold: Double

    static var modelURL: URL? {
        Bundle.main.url(forResource: "GrassClassifier", withExtension: "mlmodelc")
    }

    func check(_ image: UIImage) async throws -> GrassVerdict {
        guard let url = Self.modelURL else { throw GrassCheckError.noCustomModel }
        guard let cgImage = image.cgImage else { throw GrassCheckError.unreadableImage }
        let request = CoreMLRequest(model: try CoreMLModelContainer(model: MLModel(contentsOf: url)))
        let observations = try await request.perform(on: cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation))
            .compactMap { $0 as? ClassificationObservation }
        let confidence = Double(observations.first { $0.identifier == "grass" }?.confidence ?? 0)
        let labels = observations
            .sorted { $0.confidence > $1.confidence }
            .prefix(5)
            .map { "\($0.identifier) \(Int($0.confidence * 100))%" }
        return GrassVerdict(passed: confidence >= threshold, confidence: confidence, labels: Array(labels))
    }
}

private extension UIImage {
    func resized(maxDimension: CGFloat) -> UIImage {
        let scale = min(1, maxDimension / max(size.width, size.height))
        guard scale < 1 else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: size.width * scale, height: size.height * scale), format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: CGSize(width: size.width * scale, height: size.height * scale)))
        }
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
