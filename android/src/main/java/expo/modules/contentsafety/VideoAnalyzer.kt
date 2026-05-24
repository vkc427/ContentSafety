package expo.modules.contentsafety

import android.graphics.Bitmap
import android.os.SystemClock
import java.io.Closeable

interface FrameExtractor : Closeable {
    fun durationMs(): Long
    fun frameAt(timeUs: Long): Bitmap?
}

class RetrieverFrameExtractor(path: String) : FrameExtractor {
    private val retriever = android.media.MediaMetadataRetriever()

    init {
        try {
            retriever.setDataSource(path)
        } catch (e: Exception) {
            retriever.release()
            throw IllegalArgumentException("INVALID_INPUT: cannot open video: ${e.message}")
        }
    }

    override fun durationMs(): Long =
        retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)
            ?.toLong() ?: 0L

    override fun frameAt(timeUs: Long): Bitmap? =
        retriever.getFrameAtTime(timeUs, android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC)

    override fun close() = retriever.release()
}

class VideoAnalyzer(
    private val imageAnalyzer: ImageAnalyzer,
    private val extractorFactory: (path: String) -> FrameExtractor = { RetrieverFrameExtractor(it) }
) {
    fun analyze(
        uri: String,
        threshold: Double,
        sampleRate: Double,
        maxFrames: Int,
        stopOnFirstHit: Boolean
    ): Map<String, Any> {
        if (uri.isEmpty()) throw IllegalArgumentException("INVALID_INPUT: uri must be a non-empty string")

        val parsed = try { java.net.URI(uri) } catch (e: Exception) {
            throw IllegalArgumentException("INVALID_INPUT: malformed uri: $uri")
        }
        if (parsed.scheme != "file") throw IllegalArgumentException("INVALID_INPUT: uri must be a file:// URL, got: $uri")
        val path = parsed.path ?: throw IllegalArgumentException("INVALID_INPUT: uri has no path: $uri")

        val extractor = try {
            extractorFactory(path)
        } catch (e: IllegalArgumentException) {
            throw e
        } catch (e: Exception) {
            throw RuntimeException("INFERENCE_FAILED: ${e.message}", e)
        }

        return extractor.use { ext ->
            val durationMs = ext.durationMs()
            val frameIntervalMs = (1000.0 / sampleRate).toLong().coerceAtLeast(1L)

            val frameTimes = mutableListOf<Long>()
            var t = 0L
            while (t < durationMs * 1000L && frameTimes.size < maxFrames) {
                frameTimes.add(t)
                t += frameIntervalMs * 1000L
            }

            var maxConfidence = 0.0
            var isNSFW = false
            var framesAnalyzed = 0
            val start = SystemClock.elapsedRealtime()

            for (timeUs in frameTimes) {
                val bitmap = ext.frameAt(timeUs) ?: continue
                try {
                    val result = imageAnalyzer.analyzeBitmap(bitmap, threshold)
                    framesAnalyzed++
                    val conf = (result["confidence"] as? Double) ?: 0.0
                    if (conf > maxConfidence) maxConfidence = conf
                    if (conf >= threshold) {
                        isNSFW = true
                        if (stopOnFirstHit) break
                    }
                } finally {
                    bitmap.recycle()
                }
            }

            val durationAnalyzedMs = (SystemClock.elapsedRealtime() - start).toInt()

            mapOf(
                "isNSFW"         to isNSFW,
                "confidence"     to maxConfidence,
                "threshold"      to threshold,
                "source"         to "tflite-image",
                "durationMs"     to durationAnalyzedMs,
                "framesAnalyzed" to framesAnalyzed,
            )
        }
    }
}
