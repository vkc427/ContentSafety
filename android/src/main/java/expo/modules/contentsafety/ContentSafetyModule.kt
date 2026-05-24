package expo.modules.contentsafety

import android.content.Context
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

class ContentSafetyModule : Module() {
    private val context: Context
        get() = appContext.reactContext ?: throw IllegalStateException("React context unavailable")

    @Volatile private var imageAnalyzer: ImageAnalyzer? = null
    @Volatile private var textAnalyzer: TextAnalyzer? = null

    private fun getOrCreateAnalyzer(): ImageAnalyzer =
        imageAnalyzer ?: synchronized(this) {
            imageAnalyzer ?: ImageAnalyzer(context).also { imageAnalyzer = it }
        }

    private fun getOrCreateTextAnalyzer(): TextAnalyzer =
        textAnalyzer ?: synchronized(this) {
            textAnalyzer ?: TextAnalyzer(context).also { textAnalyzer = it }
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

        AsyncFunction("detectText") { input: String, options: Map<String, Any?> ->
            val threshold = (options["threshold"] as? Number)?.toDouble() ?: 0.7
            @Suppress("UNCHECKED_CAST")
            val extraTerms = (options["blocklist"] as? List<String>) ?: emptyList()
            val useBlocklist = (options["useBlocklist"] as? Boolean) ?: true
            val useModel = (options["useModel"] as? Boolean) ?: true
            getOrCreateTextAnalyzer().analyze(input, threshold, useBlocklist, useModel, extraTerms)
        }

        AsyncFunction("warmup") {
            getOrCreateAnalyzer().loadModel()
        }

        OnDestroy {
            imageAnalyzer?.close()
            imageAnalyzer = null
            textAnalyzer = null
        }
    }
}
