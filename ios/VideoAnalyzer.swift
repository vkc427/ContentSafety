import Foundation
import SensitiveContentAnalysis

// MARK: - Protocol for dependency injection / testability

@available(iOS 17.0, *)
protocol VideoSensitivityAnalyzing {
    func isSensitive(url: URL) async throws -> Bool
}

// MARK: - Production implementation backed by SCSensitivityAnalyzer

@available(iOS 17.0, *)
final class SCAVideoAnalyzing: VideoSensitivityAnalyzing {
    private let analyzer = SCSensitivityAnalyzer()

    func isSensitive(url: URL) async throws -> Bool {
        guard scaEntitlementPresent() else { return false }
        do {
            let handler = analyzer.videoAnalysis(forFileAt: url)
            let result = try await handler.hasSensitiveContent()
            return result.isSensitive
        } catch {
            throw VideoAnalyzerError.inferenceFailed(error.localizedDescription)
        }
    }
}

// MARK: - Error types

enum VideoAnalyzerError: Error, LocalizedError {
    case invalidInput(String)
    case inferenceFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidInput(let msg):    return "INVALID_INPUT: \(msg)"
        case .inferenceFailed(let msg): return "INFERENCE_FAILED: \(msg)"
        }
    }
}

// MARK: - VideoAnalyzer

@available(iOS 17.0, *)
final class VideoAnalyzer {
    private let underlying: VideoSensitivityAnalyzing

    init(underlying: VideoSensitivityAnalyzing = SCAVideoAnalyzing()) {
        self.underlying = underlying
    }

    func analyze(
        uri: String,
        threshold: Double,
        sampleRate: Double,
        maxFrames: Int,
        stopOnFirstHit: Bool
    ) async throws -> [String: Any] {
        let start = ProcessInfo.processInfo.systemUptime

        guard !uri.isEmpty, let url = URL(string: uri), url.isFileURL else {
            throw VideoAnalyzerError.invalidInput("uri must be a file:// URL, got: \(uri)")
        }
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw VideoAnalyzerError.invalidInput("File not found at: \(url.path(percentEncoded: false))")
        }

        let sensitive: Bool
        do {
            // sampleRate / maxFrames / stopOnFirstHit are informational on iOS — SCA handles frame sampling internally
            sensitive = try await underlying.isSensitive(url: url)
        } catch let err as VideoAnalyzerError {
            throw err
        } catch {
            throw VideoAnalyzerError.inferenceFailed(error.localizedDescription)
        }

        let durationMs = Int((ProcessInfo.processInfo.systemUptime - start) * 1000)

        return [
            "isNSFW":          sensitive,
            "confidence":      sensitive ? 1.0 : 0.0,
            "threshold":       threshold,
            "source":          "apple-sca",
            "durationMs":      durationMs,
            "framesAnalyzed":  0,
        ]
    }
}
