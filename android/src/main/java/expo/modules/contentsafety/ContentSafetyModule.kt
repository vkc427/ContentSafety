package expo.modules.contentsafety

import android.content.Context
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

class ContentSafetyModule : Module() {
    private val context: Context
        get() = appContext.reactContext ?: throw IllegalStateException("React context unavailable")

    @Volatile private var imageAnalyzer: ImageAnalyzer? = null

    private fun getOrCreateAnalyzer(): ImageAnalyzer =
        imageAnalyzer ?: synchronized(this) {
            imageAnalyzer ?: ImageAnalyzer(context).also { imageAnalyzer = it }
        }

    override fun definition() = ModuleDefinition {
        Name("ContentSafety")

        AsyncFunction("detectImage") { uri: String, options: Map<String, Any?> ->
            val threshold = (options["threshold"] as? Number)?.toDouble() ?: 0.7
            getOrCreateAnalyzer().analyze(uri, threshold)
        }

        AsyncFunction("detectVideo") { _: String, options: Map<String, Any?> ->
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

        AsyncFunction("detectText") { _: String, options: Map<String, Any?> ->
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
            getOrCreateAnalyzer().loadModel()
        }

        OnDestroy {
            imageAnalyzer?.close()
            imageAnalyzer = null
        }
    }
}
