package expo.modules.contentsafety

import android.content.Context
import android.os.SystemClock
import android.util.Log

private const val TAG = "TextAnalyzer"

interface TextModelBackend {
    fun confidence(text: String): Double
}

class NoOpTextModelBackend : TextModelBackend {
    override fun confidence(text: String): Double = 0.0
}

class TextAnalyzer(
    private val context: Context,
    private val modelBackend: TextModelBackend = NoOpTextModelBackend(),
    private val blocklistLoader: (Context) -> List<Regex> = { loadBlocklist(it) }
) {
    private val blocklistPatterns: List<Regex> by lazy { blocklistLoader(context) }

    fun analyze(
        input: String,
        threshold: Double,
        useBlocklist: Boolean,
        useModel: Boolean,
        extraTerms: List<String>
    ): Map<String, Any> {
        if (input.isEmpty()) throw IllegalArgumentException("INVALID_INPUT: input must be a non-empty string")

        val start = SystemClock.elapsedRealtime()
        val normalized = normalize(input)

        val blocklistScore = if (useBlocklist) {
            val extraPatterns = extraTerms.map { termToRegex(it) }
            val allPatterns = blocklistPatterns + extraPatterns
            if (allPatterns.any { it.containsMatchIn(normalized) }) 1.0 else 0.0
        } else 0.0

        val modelScore = if (useModel) modelBackend.confidence(normalized) else 0.0

        val confidence = maxOf(blocklistScore, modelScore)
        val source = if (useModel && modelScore > blocklistScore) "tflite-text" else "blocklist"

        val durationMs = (SystemClock.elapsedRealtime() - start).toInt()

        return mapOf(
            "isNSFW"     to (confidence >= threshold),
            "confidence" to confidence,
            "threshold"  to threshold,
            "source"     to source,
            "durationMs" to durationMs,
        )
    }

    companion object {
        fun normalize(text: String): String {
            return text.lowercase()
                .replace('0', 'o')
                .replace('1', 'i')
                .replace('3', 'e')
                .replace('4', 'a')
                .replace('5', 's')
                .replace('@', 'a')
                .replace('$', 's')
        }

        fun termToRegex(term: String): Regex {
            val pattern = term.lowercase()
                .split(Regex("\\s+"))
                .joinToString("\\s+") { Regex.escape(it) }
            return Regex("\\b$pattern\\b", RegexOption.IGNORE_CASE)
        }

        fun loadBlocklist(context: Context): List<Regex> {
            return try {
                context.assets.open("blocklist.txt")
                    .bufferedReader()
                    .lineSequence()
                    .map { it.trim() }
                    .filter { it.isNotEmpty() && !it.startsWith("#") }
                    .map { termToRegex(it) }
                    .toList()
            } catch (e: Exception) {
                Log.w(TAG, "Failed to load blocklist.txt: ${e.message}")
                emptyList()
            }
        }
    }
}
