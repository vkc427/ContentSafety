package expo.modules.contentsafety

import android.content.Context
import org.junit.Assert.*
import org.junit.Test
import org.mockito.Mockito.mock

/**
 * JVM unit tests for TextAnalyzer.
 *
 * FakeTextModelBackend replaces the TFLite backend so the tests run on the JVM
 * without any Android framework dependencies.  blocklistLoader is injected as
 * { emptyList() } to bypass asset loading; terms under test are supplied via
 * the extraTerms parameter.
 */
class TextAnalyzerTest {

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    private class FakeTextModelBackend(private val score: Double) : TextModelBackend {
        override fun confidence(text: String): Double = score
    }

    private fun makeAnalyzer(modelScore: Double = 0.0): TextAnalyzer =
        TextAnalyzer(
            context = mock(Context::class.java),
            modelBackend = FakeTextModelBackend(modelScore),
            blocklistLoader = { emptyList() }
        )

    // Convenience wrapper with sensible defaults
    private fun TextAnalyzer.analyze(
        input: String,
        threshold: Double = 0.7,
        useBlocklist: Boolean = true,
        useModel: Boolean = false,
        extraTerms: List<String> = emptyList()
    ): Map<String, Any> = analyze(input, threshold, useBlocklist, useModel, extraTerms)

    // -------------------------------------------------------------------------
    // 1. Empty input -> IllegalArgumentException("INVALID_INPUT: ...")
    // -------------------------------------------------------------------------
    @Test
    fun `empty input throws INVALID_INPUT`() {
        val analyzer = makeAnalyzer()
        val ex = assertThrows(IllegalArgumentException::class.java) {
            analyzer.analyze("")
        }
        assertTrue(
            "Expected INVALID_INPUT prefix, got: ${ex.message}",
            ex.message!!.startsWith("INVALID_INPUT:")
        )
    }

    // -------------------------------------------------------------------------
    // 2. Blocklist match via extraTerms
    //    extraTerms=["porn"], input="I love porn" -> isNSFW=true
    // -------------------------------------------------------------------------
    @Test
    fun `blocklist match via extraTerms returns isNSFW true`() {
        val analyzer = makeAnalyzer()
        val result = analyzer.analyze(
            input = "I love porn",
            extraTerms = listOf("porn")
        )
        assertEquals(true, result["isNSFW"])
    }

    // -------------------------------------------------------------------------
    // 3. Clean text -> isNSFW=false, confidence=0.0
    // -------------------------------------------------------------------------
    @Test
    fun `clean text returns isNSFW false and confidence zero`() {
        val analyzer = makeAnalyzer()
        val result = analyzer.analyze(input = "The weather is lovely today")
        assertEquals(false, result["isNSFW"])
        assertEquals(0.0, result["confidence"] as Double, 1e-9)
    }

    // -------------------------------------------------------------------------
    // 4. Leetspeak match — "p0rn" normalises to "porn", matched as extraTerm
    // -------------------------------------------------------------------------
    @Test
    fun `leetspeak input matches extraTerm after normalisation`() {
        val analyzer = makeAnalyzer()
        val result = analyzer.analyze(
            input = "p0rn",
            extraTerms = listOf("porn")
        )
        assertEquals(true, result["isNSFW"])
    }

    // -------------------------------------------------------------------------
    // 5. useBlocklist=false — even an extraTerm match returns isNSFW=false
    // -------------------------------------------------------------------------
    @Test
    fun `useBlocklist false disables blocklist even with extraTerm match`() {
        val analyzer = makeAnalyzer()
        val result = analyzer.analyze(
            input = "I love porn",
            useBlocklist = false,
            extraTerms = listOf("porn")
        )
        assertEquals(false, result["isNSFW"])
    }

    // -------------------------------------------------------------------------
    // 6. useModel=false — source is always "blocklist"
    // -------------------------------------------------------------------------
    @Test
    fun `useModel false always reports source as blocklist`() {
        // Even with no match the source should be "blocklist"
        val analyzer = makeAnalyzer()
        val result = analyzer.analyze(
            input = "harmless text",
            useModel = false
        )
        assertEquals("blocklist", result["source"])
    }

    // -------------------------------------------------------------------------
    // 7. Model wins — stub returns 0.9, blocklist misses -> source="tflite-text"
    // -------------------------------------------------------------------------
    @Test
    fun `model score above threshold sets source to tflite-text`() {
        val analyzer = makeAnalyzer(modelScore = 0.9)
        val result = analyzer.analyze(
            input = "some text with no blocklist term",
            useModel = true,
            threshold = 0.7
        )
        assertEquals("tflite-text", result["source"])
        assertEquals(0.9, result["confidence"] as Double, 1e-6)
        assertEquals(true, result["isNSFW"])
    }

    // -------------------------------------------------------------------------
    // 8. Blocklist wins over model
    //    blocklist hit -> confidence=1.0, model returns 0.5 -> source="blocklist"
    // -------------------------------------------------------------------------
    @Test
    fun `blocklist hit beats lower model score for source`() {
        val analyzer = makeAnalyzer(modelScore = 0.5)
        val result = analyzer.analyze(
            input = "I love porn",
            useBlocklist = true,
            useModel = true,
            extraTerms = listOf("porn")
        )
        assertEquals("blocklist", result["source"])
        assertEquals(1.0, result["confidence"] as Double, 1e-9)
    }

    // -------------------------------------------------------------------------
    // 9. Threshold echo — result["threshold"] == supplied threshold
    // -------------------------------------------------------------------------
    @Test
    fun `threshold value is echoed in result`() {
        val analyzer = makeAnalyzer()
        val suppliedThreshold = 0.42
        val result = analyzer.analyze(
            input = "harmless",
            threshold = suppliedThreshold
        )
        assertEquals(suppliedThreshold, result["threshold"] as Double, 1e-9)
    }

    // -------------------------------------------------------------------------
    // 10. normalize() unit test
    //     TextAnalyzer.normalize("p0rn h3nt@i") == "porn hentai"
    // -------------------------------------------------------------------------
    @Test
    fun `normalize converts leetspeak substitutions correctly`() {
        val result = TextAnalyzer.normalize("p0rn h3nt@i")
        assertEquals("porn hentai", result)
    }

    // -------------------------------------------------------------------------
    // 11. Multi-word term match — "sexual assault" with extra whitespace
    // -------------------------------------------------------------------------
    @Test
    fun `multi-word extraTerm matches with extra whitespace between tokens`() {
        val analyzer = makeAnalyzer()
        val result = analyzer.analyze(
            input = "committed sexual  assault",
            extraTerms = listOf("sexual assault")
        )
        assertEquals(true, result["isNSFW"])
    }
}
