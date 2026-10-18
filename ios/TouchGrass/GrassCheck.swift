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

    var errorDescription: String? {
        "That photo couldn't be read. Try again."
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
