package expo.modules.contentsafety

import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

class ContentSafetyModule : Module() {
  override fun definition() = ModuleDefinition {
    Name("ContentSafety")

    AsyncFunction("detectImage") { uri: String, options: Map<String, Any?> ->
      val threshold = (options["threshold"] as? Number)?.toDouble() ?: 0.7
      mapOf(
        "isNSFW" to false,
        "confidence" to 0.0,
        "threshold" to threshold,
        "source" to "tflite-image",
        "durationMs" to 0,
      )
    }

    AsyncFunction("detectVideo") { uri: String, options: Map<String, Any?> ->
      val threshold = (options["threshold"] as? Number)?.toDouble() ?: 0.7
      mapOf(
        "isNSFW" to false,
        "confidence" to 0.0,
        "threshold" to threshold,
        "source" to "tflite-image",
        "durationMs" to 0,
        "framesAnalyzed" to 0,
      )
    }

    AsyncFunction("detectText") { input: String, options: Map<String, Any?> ->
      val threshold = (options["threshold"] as? Number)?.toDouble() ?: 0.7
      mapOf(
        "isNSFW" to false,
        "confidence" to 0.0,
        "threshold" to threshold,
        "source" to "blocklist",
        "durationMs" to 0,
      )
    }

    AsyncFunction("warmup") {
      // no-op stub
    }
  }
}
