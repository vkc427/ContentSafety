package expo.modules.contentsafety

import android.graphics.Bitmap
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.mockito.Mockito.*

class VideoAnalyzerTest {

    private lateinit var mockImageAnalyzer: ImageAnalyzer
    private lateinit var mockExtractor: FrameExtractor
    private lateinit var mockBitmap: Bitmap

    @Before
    fun setUp() {
        mockImageAnalyzer = mock(ImageAnalyzer::class.java)
        mockExtractor = mock(FrameExtractor::class.java)
        mockBitmap = mock(Bitmap::class.java)

        `when`(mockBitmap.width).thenReturn(224)
        `when`(mockBitmap.height).thenReturn(224)

        // Default: 5-second video
        `when`(mockExtractor.durationMs()).thenReturn(5_000L)
        `when`(mockExtractor.frameAt(anyLong())).thenReturn(mockBitmap)

        // Default: SFW result
        `when`(mockImageAnalyzer.analyzeBitmap(any(), anyDouble())).thenReturn(
            mapOf("isNSFW" to false, "confidence" to 0.1, "threshold" to 0.7,
                  "source" to "tflite-image", "durationMs" to 5)
        )
    }

    private fun makeAnalyzer() = VideoAnalyzer(
        imageAnalyzer = mockImageAnalyzer,
        extractorFactory = { mockExtractor }
    )

    private val fakeUri = "file:///tmp/fake_video.mp4"

    @Test
    fun `empty URI throws INVALID_INPUT`() {
        val ex = assertThrows(IllegalArgumentException::class.java) {
            makeAnalyzer().analyze("", 0.7, 1.0, 30, true)
        }
        assertTrue(ex.message!!.startsWith("INVALID_INPUT:"))
    }

    @Test
    fun `non-file URI throws INVALID_INPUT`() {
        val ex = assertThrows(IllegalArgumentException::class.java) {
            makeAnalyzer().analyze("https://example.com/v.mp4", 0.7, 1.0, 30, true)
        }
        assertTrue(ex.message!!.startsWith("INVALID_INPUT:"))
    }

    @Test
    fun `SFW frames return isNSFW false with correct framesAnalyzed`() {
        // sampleRate=1, durationMs=5000 → frames at 0,1000,2000,3000,4000 ms (5 frames)
        `when`(mockExtractor.durationMs()).thenReturn(5_000L)

        val result = makeAnalyzer().analyze(fakeUri, 0.7, 1.0, 30, false)

        assertEquals(false, result["isNSFW"])
        assertEquals(5, result["framesAnalyzed"])
        assertEquals("tflite-image", result["source"])
    }

    @Test
    fun `NSFW frame sets isNSFW true`() {
        `when`(mockImageAnalyzer.analyzeBitmap(any(), anyDouble())).thenReturn(
            mapOf("isNSFW" to true, "confidence" to 0.9, "threshold" to 0.7,
                  "source" to "tflite-image", "durationMs" to 5)
        )

        val result = makeAnalyzer().analyze(fakeUri, 0.7, 1.0, 30, false)

        assertEquals(true, result["isNSFW"])
        assertEquals(0.9, result["confidence"] as Double, 1e-6)
    }

    @Test
    fun `stopOnFirstHit stops analysis after first NSFW frame`() {
        `when`(mockExtractor.durationMs()).thenReturn(10_000L)
        `when`(mockImageAnalyzer.analyzeBitmap(any(), anyDouble())).thenReturn(
            mapOf("isNSFW" to true, "confidence" to 0.9, "threshold" to 0.7,
                  "source" to "tflite-image", "durationMs" to 5)
        )

        val result = makeAnalyzer().analyze(fakeUri, 0.7, 1.0, 30, stopOnFirstHit = true)

        assertEquals(true, result["isNSFW"])
        assertEquals(1, result["framesAnalyzed"])
    }

    @Test
    fun `maxFrames caps frame count`() {
        `when`(mockExtractor.durationMs()).thenReturn(60_000L)

        val result = makeAnalyzer().analyze(fakeUri, 0.7, 1.0, maxFrames = 5, stopOnFirstHit = false)

        assertEquals(5, result["framesAnalyzed"])
    }

    @Test
    fun `null frame from extractor is skipped`() {
        `when`(mockExtractor.durationMs()).thenReturn(3_000L)
        `when`(mockExtractor.frameAt(anyLong()))
            .thenReturn(null)
            .thenReturn(mockBitmap)
            .thenReturn(mockBitmap)

        val result = makeAnalyzer().analyze(fakeUri, 0.7, 1.0, 30, false)

        assertEquals(2, result["framesAnalyzed"])
    }

    @Test
    fun `threshold is echoed in result`() {
        val result = makeAnalyzer().analyze(fakeUri, 0.85, 1.0, 30, false)
        assertEquals(0.85, result["threshold"] as Double, 1e-9)
    }

    @Test
    fun `confidence is max across all frames`() {
        `when`(mockExtractor.durationMs()).thenReturn(2_000L)
        val results = listOf(
            mapOf("isNSFW" to false, "confidence" to 0.3, "threshold" to 0.7, "source" to "tflite-image", "durationMs" to 5),
            mapOf("isNSFW" to false, "confidence" to 0.6, "threshold" to 0.7, "source" to "tflite-image", "durationMs" to 5),
        )
        var callIndex = 0
        `when`(mockImageAnalyzer.analyzeBitmap(any(), anyDouble())).thenAnswer {
            results[callIndex++]
        }

        val result = makeAnalyzer().analyze(fakeUri, 0.7, 1.0, 30, false)
        assertEquals(0.6, result["confidence"] as Double, 1e-6)
    }
}
