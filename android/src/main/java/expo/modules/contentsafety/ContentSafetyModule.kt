package expo.modules.contentsafety

import android.content.Context
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

class ContentSafetyModule : Module() {
    private val context: Context
        get() = appContext.reactContext ?: throw IllegalStateException("React context unavailable")

    @Volatile private var imageAnalyzer: ImageAnalyzer? = null
    @Volatile private var videoAnalyzer: VideoAnalyzer? = null
    @Volatile private var textAnalyzer: TextAnalyzer? = null

    private fun getOrCreateAnalyzer(): ImageAnalyzer =
        imageAnalyzer ?: synchronized(this) {
            imageAnalyzer ?: ImageAnalyzer(context).also { imageAnalyzer = it }
        }

    private fun getOrCreateVideoAnalyzer(): VideoAnalyzer =
        videoAnalyzer ?: synchronized(this) {
            videoAnalyzer ?: VideoAnalyzer(getOrCreateAnalyzer()).also { videoAnalyzer = it }
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

        AsyncFunction("detectVideo") { uri: String, options: Map<String, Any?> ->
            val threshold      = (options["threshold"]      as? Number)?.toDouble()  ?: 0.7
            val sampleRate     = (options["sampleRate"]     as? Number)?.toDouble()  ?: 1.0
            val maxFrames      = (options["maxFrames"]      as? Number)?.toInt()     ?: 30
            val stopOnFirstHit = (options["stopOnFirstHit"] as? Boolean)             ?: true
            getOrCreateVideoAnalyzer().analyze(uri, threshold, sampleRate, maxFrames, stopOnFirstHit)
        }

        AsyncFunction("detectText") { input: String, options: Map<String, Any?> ->
            val threshold    = (options["threshold"]    as? Number)?.toDouble()  ?: 0.7
            @Suppress("UNCHECKED_CAST")
            val extraTerms   = (options["blocklist"]    as? List<String>)        ?: emptyList()
            val useBlocklist = (options["useBlocklist"] as? Boolean)             ?: true
            val useModel     = (options["useModel"]     as? Boolean)             ?: true
            getOrCreateTextAnalyzer().analyze(input, threshold, useBlocklist, useModel, extraTerms)
        }

        AsyncFunction("warmup") {
            getOrCreateAnalyzer().loadModel()
            getOrCreateVideoAnalyzer()
            getOrCreateTextAnalyzer()
        }

        OnDestroy {
            imageAnalyzer?.close()
            imageAnalyzer = null
            videoAnalyzer = null
            textAnalyzer  = null
        }
    }
}
