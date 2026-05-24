package expo.modules.contentsafety

import android.content.Context
import android.graphics.Bitmap
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.mockito.Mockito.*
import java.nio.ByteBuffer

/**
 * JVM unit tests for ImageAnalyzer.
 *
 * BitmapFactory is an Android framework class that returns null on JVM, so we inject
 * a bitmapLoader lambda into ImageAnalyzer. The Bitmap class is final and is mocked
 * using mockito-inline (which supports mocking final classes).
 */
class ImageAnalyzerTest {

    private lateinit var mockContext: Context
    private lateinit var mockBackend: ImageInferenceBackend
    private lateinit var mockBitmap: Bitmap

    @Before
    fun setUp() {
        mockContext = mock(Context::class.java)
        mockBackend = mock(ImageInferenceBackend::class.java)
        mockBitmap = mock(Bitmap::class.java)

        // bitmapToByteBuffer calls bitmap.getPixels — stub it to be a no-op
        // (it writes to a provided IntArray, nothing to return)
        doNothing().`when`(mockBitmap).getPixels(any(), anyInt(), anyInt(), anyInt(), anyInt(), anyInt(), anyInt())

        // Bitmap.createScaledBitmap is a static call; stub getWidth/getHeight so it
        // does not NPE. Alternatively we stub it via the loader to skip scaling by
        // returning a 224x224 bitmap so createScaledBitmap still works (it delegates
        // to native). Since we can't easily mock static on older Mockito, we set up
        // the mock bitmap to report correct dimensions.
        `when`(mockBitmap.width).thenReturn(224)
        `when`(mockBitmap.height).thenReturn(224)
        // recycle() is a no-op on a mock
    }

    /** Analyzer backed by mockBackend, bitmap decoded via mockBitmap. */
    private fun makeAnalyzer(): ImageAnalyzer =
        ImageAnalyzer(
            context = mockContext,
            backendFactory = { mockBackend },
            bitmapLoader = { mockBitmap }
        )

    /** A plausible file:// URI — the loader is mocked so the file need not exist. */
    private val fakeFileUri = "file:///tmp/fake_test_image.jpg"

    // -------------------------------------------------------------------------
    // 1. Empty URI -> INVALID_INPUT
    // -------------------------------------------------------------------------
    @Test
    fun `empty URI throws INVALID_INPUT`() {
        // loadModel() is called first, then the URI check — the factory still fires.
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
        val result = analyzer.analyze(fakeFileUri, 0.7)

        assertEquals(false, result["isNSFW"])
        assertEquals(0.05, result["confidence"] as Double, 1e-6)
        assertEquals("tflite-image", result["source"])

        @Suppress("UNCHECKED_CAST")
        val categories = result["categories"] as Map<String, Double>
        assertEquals("categories should have 5 keys", 5, categories.size)
        assertTrue(categories.containsKey("drawings"))
        assertTrue(categories.containsKey("hentai"))
        assertTrue(categories.containsKey("neutral"))
        assertTrue(categories.containsKey("porn"))
        assertTrue(categories.containsKey("sexy"))

        @Suppress("UNCHECKED_CAST")
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
        val result = analyzer.analyze(fakeFileUri, 0.7)

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
        val result = analyzer.analyze(fakeFileUri, 0.9)

        assertEquals(0.9, result["threshold"] as Double, 1e-9)
        // nsfwScore=0.05 < threshold=0.9 => isNSFW=false
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
        analyzer.analyze(fakeFileUri, 0.7)

        assertEquals("runInference should be called exactly once", 1, capturedBuffers.size)
        assertEquals(
            "ByteBuffer capacity should be 4*224*224*3",
            expectedCapacity,
            capturedBuffers[0].capacity()
        )
    }

    // -------------------------------------------------------------------------
    // 7. Model load failure -> RuntimeException with MODEL_LOAD_FAILED prefix
    // -------------------------------------------------------------------------
    @Test
    fun `backendFactory failure throws MODEL_LOAD_FAILED`() {
        val failingFactory: (Context) -> ImageInferenceBackend = {
            throw RuntimeException("asset not found")
        }
        val analyzer = ImageAnalyzer(
            context = mockContext,
            backendFactory = failingFactory,
            bitmapLoader = { mockBitmap }
        )

        val ex = assertThrows(RuntimeException::class.java) {
            analyzer.analyze(fakeFileUri, 0.7)
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
            analyzer.analyze(fakeFileUri, 0.7)
        }
        assertTrue(
            "Expected INFERENCE_FAILED prefix, got: ${ex.message}",
            ex.message!!.startsWith("INFERENCE_FAILED:")
        )
    }
}
