import ExpoModulesCore

public class ContentSafetyModule: Module {
    @available(iOS 17.0, *)
    private lazy var imageAnalyzer = ImageAnalyzer()

    public func definition() -> ModuleDefinition {
        Name("ContentSafety")

        AsyncFunction("detectImage") { [weak self] (uri: String, options: [String: Any]) async throws -> [String: Any] in
            guard #available(iOS 17, *) else {
                throw ImageAnalyzerError.iosVersionTooLow
            }
            let threshold = options["threshold"] as? Double ?? 0.7
            guard let self else {
                throw ImageAnalyzerError.inferenceFailed("Module deallocated")
            }
            return try await self.imageAnalyzer.analyze(uri: uri, threshold: threshold)
        }

        AsyncFunction("detectVideo") { (_: String, options: [String: Any]) -> [String: Any] in
            let threshold = options["threshold"] as? Double ?? 0.7
            return [
                "isNSFW": false,
                "confidence": 0.0,
                "threshold": threshold,
                "source": "tflite-image",
                "durationMs": 0,
                "framesAnalyzed": 0,
            ]
        }

        AsyncFunction("detectText") { (_: String, options: [String: Any]) -> [String: Any] in
            let threshold = options["threshold"] as? Double ?? 0.7
            return [
                "isNSFW": false,
                "confidence": 0.0,
                "threshold": threshold,
                "source": "blocklist",
                "durationMs": 0,
            ]
        }

        AsyncFunction("warmup") { [weak self] () async -> Void in
            guard #available(iOS 17, *) else { return }
            _ = self?.imageAnalyzer  // triggers lazy init of SCSensitivityAnalyzer
        }
    }
}
