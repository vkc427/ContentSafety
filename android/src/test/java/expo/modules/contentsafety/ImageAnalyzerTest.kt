package expo.modules.contentsafety

import android.content.Context
import org.junit.Assert.*
import org.junit.Before
import org.junit.After
import org.junit.Test
import org.mockito.Mockito.*
import java.io.File
import java.nio.ByteBuffer

class ImageAnalyzerTest {

    private lateinit var mockContext: Context
    private lateinit var mockBackend: ImageInferenceBackend
    private lateinit var tempFile: File

    // A minimal valid 1x1 RGB PNG
    private val MINIMAL_PNG: ByteArray = byteArrayOf(
        0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x02, 0x00, 0x00, 0x00, 0x90.toByte(), 0x77, 0x53, 0xDE.toByte(),
        0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, 0x54,
        0x08, 0xD7.toByte(), 0x63, 0xF8.toByte(), 0xCF.toByte(), 0xC0.toByte(), 0x00, 0x00, 0x00,
        0x05, 0x00, 0x01, 0xA2.toByte(), 0x6A, 0xE3.toByte(), 0x8D.toByte(),
        0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44,
        0xAE.toByte(), 0x42, 0x60, 0x82.toByte()
    )

    @Before
    fun setUp() {
        mockContext = mock(Context::class.java)
        mockBackend = mock(ImageInferenceBackend::class.java)
        tempFile = File.createTempFile("test_img_", ".png")
        tempFile.writeBytes(MINIMAL_PNG)
    }

    @After
    fun tearDown() {
        tempFile.delete()
    }

    private fun makeAnalyzer() = ImageAnalyzer(mockContext) { mockBackend }
    private fun sfwUri() = "file://${tempFile.absolutePath}"

    // -------------------------------------------------------------------------
    // 1. Empty URI -> INVALID_INPUT
    // -------------------------------------------------------------------------
    @Test
    fun `empty URI throws INVALID_INPUT`() {
        // Even with an empty URI the factory is still invoked by loadModel()
        val analyzer = makeAnalyzer()
        val ex = assertThrows(IllegalArgumentException::class.java) {
            analyzer.analyze("", 0.7)
        }
        assertTrue(
            "Expected INVALID_INPUT prefix, got: ${ex.message}",
            ex.message!!.startsWith("INVALID_INPUT:")
        )
    }

    // -------------------------------------------------------------------------
    // 2. Non-file URI -> INVALID_INPUT
    // -------------------------------------------------------------------------
    @Test
    fun `non-file URI throws INVALID_INPUT`() {
        val analyzer = makeAnalyzer()
        val ex = assertThrows(IllegalArgumentException::class.java) {
            analyzer.analyze("https://example.com/img.jpg", 0.7)
        }
        assertTrue(
            "Expected INVALID_INPUT prefix, got: ${ex.message}",
            ex.message!!.startsWith("INVALID_INPUT:")
        )
    }

    // -------------------------------------------------------------------------
    // 3. SFW result shape
    // scores: drawings=0.8, hentai=0.05, neutral=0.9, porn=0.02, sexy=0.03
    // nsfwScore = max(porn=0.02, hentai=0.05, sexy=0.03) = 0.05
    // threshold=0.7 => isNSFW=false
    // -------------------------------------------------------------------------
    @Test
    fun `SFW scores produce correct result shape`() {
        `when`(mockBackend.runInference(any())).thenReturn(
            floatArrayOf(0.8f, 0.05f, 0.9f, 0.02f, 0.03f)
        )

        val analyzer = makeAnalyzer()
        val result = analyzer.analyze(sfwUri(), 0.7)

        assertEquals(false, result["isNSFW"])
        assertEquals(0.05, result["confidence"] as Double, 1e-6)
        assertEquals("tflite-image", result["source"])

        @Suppress("UNCHECKED_CAST")
        val categories = result["categories"] as Map<String, Double>
        assertTrue("categories should have 5 keys", categories.size == 5)
        assertTrue("categories should contain 'drawings'", categories.containsKey("drawings"))
        assertTrue("categories should contain 'hentai'", categories.containsKey("hentai"))
        assertTrue("categories should contain 'neutral'", categories.containsKey("neutral"))
        assertTrue("categories should contain 'porn'", categories.containsKey("porn"))
        assertTrue("categories should contain 'sexy'", categories.containsKey("sexy"))

        val durationMs = result["durationMs"] as Int
        assertTrue("durationMs should be >= 0", durationMs >= 0)
    }

    // -------------------------------------------------------------------------
    // 4. NSFW result
    // scores: drawings=0.01, hentai=0.02, neutral=0.05, porn=0.85, sexy=0.07
    // nsfwScore = max(porn=0.85, hentai=0.02, sexy=0.07) = 0.85
    // threshold=0.7 => isNSFW=true
    // -------------------------------------------------------------------------
    @Test
    fun `NSFW scores produce isNSFW true and correct confidence`() {
        `when`(mockBackend.runInference(any())).thenReturn(
            floatArrayOf(0.01f, 0.02f, 0.05f, 0.85f, 0.07f)
        )

        val analyzer = makeAnalyzer()
        val result = analyzer.analyze(sfwUri(), 0.7)

        assertEquals(true, result["isNSFW"])
        assertEquals(0.85, result["confidence"] as Double, 1e-6)
    }

    // -------------------------------------------------------------------------
    // 5. Threshold echo — result["threshold"] == supplied threshold
    // -------------------------------------------------------------------------
    @Test
    fun `threshold value is echoed in result`() {
        `when`(mockBackend.runInference(any())).thenReturn(
            floatArrayOf(0.8f, 0.05f, 0.9f, 0.02f, 0.03f)
        )

        val analyzer = makeAnalyzer()
        val result = analyzer.analyze(sfwUri(), 0.9)

        assertEquals(0.9, result["threshold"] as Double, 1e-9)
        // With nsfwScore=0.05 and threshold=0.9 => isNSFW=false
        assertEquals(false, result["isNSFW"])
    }

    // -------------------------------------------------------------------------
    // 6. Backend receives ByteBuffer of correct capacity: 4 * 224 * 224 * 3
    // -------------------------------------------------------------------------
    @Test
    fun `backend receives ByteBuffer with correct capacity`() {
        val expectedCapacity = 4 * 224 * 224 * 3
        val capturedBuffers = mutableListOf<ByteBuffer>()

        `when`(mockBackend.runInference(any())).thenAnswer { invocation ->
            capturedBuffers.add(invocation.getArgument(0))
            floatArrayOf(0.8f, 0.05f, 0.9f, 0.02f, 0.03f)
        }

        val analyzer = makeAnalyzer()
        analyzer.analyze(sfwUri(), 0.7)

        assertEquals("runInference should be called exactly once", 1, capturedBuffers.size)
        assertEquals(
            "ByteBuffer capacity should be 4*224*224*3",
            expectedCapacity,
            capturedBuffers[0].capacity()
        )
    }

    // -------------------------------------------------------------------------
    // 7. Model load failure -> RuntimeException with MODEL_LOAD_FAILED prefix
    // The factory throws before the backend is created
    // -------------------------------------------------------------------------
    @Test
    fun `backendFactory failure throws MODEL_LOAD_FAILED`() {
        val failingFactory: (Context) -> ImageInferenceBackend = {
            throw RuntimeException("asset not found")
        }
        val analyzer = ImageAnalyzer(mockContext, failingFactory)

        val ex = assertThrows(RuntimeException::class.java) {
            analyzer.analyze(sfwUri(), 0.7)
        }
        assertTrue(
            "Expected MODEL_LOAD_FAILED prefix, got: ${ex.message}",
            ex.message!!.startsWith("MODEL_LOAD_FAILED:")
        )
    }

    // -------------------------------------------------------------------------
    // 8. Inference failure -> RuntimeException with INFERENCE_FAILED prefix
    // -------------------------------------------------------------------------
    @Test
    fun `runInference failure throws INFERENCE_FAILED`() {
        `when`(mockBackend.runInference(any())).thenThrow(RuntimeException("GPU error"))

        val analyzer = makeAnalyzer()
        val ex = assertThrows(RuntimeException::class.java) {
            analyzer.analyze(sfwUri(), 0.7)
        }
        assertTrue(
            "Expected INFERENCE_FAILED prefix, got: ${ex.message}",
            ex.message!!.startsWith("INFERENCE_FAILED:")
        )
    }
}
