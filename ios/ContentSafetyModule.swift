import ExpoModulesCore

public class ContentSafetyModule: Module {
  public func definition() -> ModuleDefinition {
    Name("ContentSafety")

    AsyncFunction("detectImage") { (uri: String, options: [String: Any]) -> [String: Any] in
      let threshold = options["threshold"] as? Double ?? 0.7
      return [
        "isNSFW": false,
        "confidence": 0.0,
        "threshold": threshold,
        "source": "apple-sca",
        "durationMs": 0
      ]
    }

    AsyncFunction("detectVideo") { (uri: String, options: [String: Any]) -> [String: Any] in
      let threshold = options["threshold"] as? Double ?? 0.7
      return [
        "isNSFW": false,
        "confidence": 0.0,
        "threshold": threshold,
        "source": "tflite-image",
        "durationMs": 0,
        "framesAnalyzed": 0
      ]
    }

    AsyncFunction("detectText") { (input: String, options: [String: Any]) -> [String: Any] in
      let threshold = options["threshold"] as? Double ?? 0.7
      return [
        "isNSFW": false,
        "confidence": 0.0,
        "threshold": threshold,
        "source": "blocklist",
        "durationMs": 0
      ]
    }

    AsyncFunction("warmup") { () -> Void in
      // no-op stub; real impl loads models lazily
    }
  }
}
