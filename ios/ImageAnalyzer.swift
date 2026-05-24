import Foundation
import SensitiveContentAnalysis

// MARK: - Protocol for dependency injection / testability

protocol ImageSensitivityAnalyzing {
    func isSensitive(url: URL) async throws -> Bool
}

// MARK: - Production implementation backed by SCSensitivityAnalyzer

@available(iOS 17.0, *)
final class SCAImageAnalyzing: ImageSensitivityAnalyzing {
    private let analyzer = SCSensitivityAnalyzer()

    func isSensitive(url: URL) async throws -> Bool {
        do {
            let result = try await analyzer.analyzeImage(at: url)
            return result.isSensitive
        } catch {
            throw ImageAnalyzerError.inferenceFailed(error.localizedDescription)
        }
    }
}

// MARK: - Error types

enum ImageAnalyzerError: Error, LocalizedError {
    case invalidInput(String)
    case inferenceFailed(String)
    case iosVersionTooLow
    case modelLoadFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidInput(let msg):   return "INVALID_INPUT: \(msg)"
        case .inferenceFailed(let msg): return "INFERENCE_FAILED: \(msg)"
        case .iosVersionTooLow:        return "IOS_VERSION_TOO_LOW: iOS 17.0+ is required"
        case .modelLoadFailed(let msg): return "MODEL_LOAD_FAILED: \(msg)"
        }
    }
}

// MARK: - ImageAnalyzer

@available(iOS 17.0, *)
final class ImageAnalyzer {
    private let underlying: ImageSensitivityAnalyzing

    init(underlying: ImageSensitivityAnalyzing = SCAImageAnalyzing()) {
        self.underlying = underlying
    }

    func analyze(uri: String, threshold: Double) async throws -> [String: Any] {
        let start = ProcessInfo.processInfo.systemUptime

        guard !uri.isEmpty, let url = URL(string: uri), url.isFileURL else {
            throw ImageAnalyzerError.invalidInput("uri must be a file:// URL, got: \(uri)")
        }
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw ImageAnalyzerError.invalidInput("File not found at: \(url.path(percentEncoded: false))")
        }

        let sensitive: Bool
        do {
            sensitive = try await underlying.isSensitive(url: url)
        } catch let err as ImageAnalyzerError {
            throw err
        } catch {
            throw ImageAnalyzerError.inferenceFailed(error.localizedDescription)
        }

        let durationMs = Int((ProcessInfo.processInfo.systemUptime - start) * 1000)

        return [
            "isNSFW": sensitive,
            "confidence": sensitive ? 1.0 : 0.0,
            "threshold": threshold,
            "source": "apple-sca",
            "durationMs": durationMs,
        ]
    }
}
