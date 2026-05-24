package expo.modules.contentsafety

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.SystemClock
import android.util.Log
import org.tensorflow.lite.Interpreter
import org.tensorflow.lite.gpu.GpuDelegate
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel

private const val TAG = "ImageAnalyzer"
private const val MODEL_FILE = "nsfw_image.tflite"
private const val INPUT_SIZE = 224
private const val NUM_CLASSES = 5

// Interface for dependency injection / testability
interface ImageInferenceBackend {
    fun runInference(input: ByteBuffer): FloatArray
    fun close()
}

class TFLiteInferenceBackend(context: Context) : ImageInferenceBackend {
    private val interpreter: Interpreter

    init {
        val model = loadModelBuffer(context)
        val options = Interpreter.Options()
        try {
            val gpuDelegate = GpuDelegate()
            options.addDelegate(gpuDelegate)
        } catch (e: Exception) {
            Log.w(TAG, "GPU delegate unavailable, using CPU: ${e.message}")
        }
        interpreter = Interpreter(model, options)
    }

    private fun loadModelBuffer(context: Context): MappedByteBuffer {
        val fd = context.assets.openFd(MODEL_FILE)
        return FileInputStream(fd.fileDescriptor).channel
            .map(FileChannel.MapMode.READ_ONLY, fd.startOffset, fd.declaredLength)
    }

    override fun runInference(input: ByteBuffer): FloatArray {
        val output = Array(1) { FloatArray(NUM_CLASSES) }
        interpreter.run(input, output)
        return output[0]
    }

    override fun close() {
        interpreter.close()
    }
}

class ImageAnalyzer(
    private val context: Context,
    private val backendFactory: (Context) -> ImageInferenceBackend = { TFLiteInferenceBackend(it) }
) {
    @Volatile private var backend: ImageInferenceBackend? = null

    fun loadModel() {
        if (backend == null) {
            synchronized(this) {
                if (backend == null) {
                    backend = try {
                        backendFactory(context)
                    } catch (e: Exception) {
                        throw RuntimeException("MODEL_LOAD_FAILED: ${e.message}", e)
                    }
                }
            }
        }
    }

    fun analyze(uri: String, threshold: Double): Map<String, Any> {
        loadModel()

        if (uri.isEmpty()) throw IllegalArgumentException("INVALID_INPUT: uri must be a non-empty string")
        val parsed = try { Uri.parse(uri) } catch (e: Exception) {
            throw IllegalArgumentException("INVALID_INPUT: malformed uri: $uri")
        }
        if (parsed.scheme != "file") throw IllegalArgumentException("INVALID_INPUT: uri must be a file:// URL, got: $uri")

        val path = parsed.path ?: throw IllegalArgumentException("INVALID_INPUT: uri has no path: $uri")
        val bitmap = decodeBitmap(path)
            ?: throw IllegalArgumentException("INVALID_INPUT: file not found or unreadable: $path")

        return try {
            runAnalysis(bitmap, threshold)
        } catch (e: IllegalArgumentException) {
            throw e
        } catch (e: Exception) {
            throw RuntimeException("INFERENCE_FAILED: ${e.message}", e)
        } finally {
            bitmap.recycle()
        }
    }

    private fun decodeBitmap(path: String): Bitmap? {
        return try {
            val opts = BitmapFactory.Options().apply {
                inJustDecodeBounds = true
                BitmapFactory.decodeFile(path, this)
                inSampleSize = calculateInSampleSize(outWidth, outHeight, 1024, 1024)
                inJustDecodeBounds = false
            }
            BitmapFactory.decodeFile(path, opts)
        } catch (e: Exception) {
            null
        }
    }

    private fun calculateInSampleSize(width: Int, height: Int, maxWidth: Int, maxHeight: Int): Int {
        var inSampleSize = 1
        if (width > maxWidth || height > maxHeight) {
            val halfWidth = width / 2
            val halfHeight = height / 2
            while (halfWidth / inSampleSize >= maxWidth && halfHeight / inSampleSize >= maxHeight) {
                inSampleSize *= 2
            }
        }
        return inSampleSize
    }

    private fun runAnalysis(bitmap: Bitmap, threshold: Double): Map<String, Any> {
        val scaled = Bitmap.createScaledBitmap(bitmap, INPUT_SIZE, INPUT_SIZE, true)
        val input = bitmapToByteBuffer(scaled)
        if (scaled != bitmap) scaled.recycle()

        val start = SystemClock.elapsedRealtime()
        val scores = backend!!.runInference(input)
        val durationMs = (SystemClock.elapsedRealtime() - start).toInt()

        val drawings = scores[0].toDouble()
        val hentai   = scores[1].toDouble()
        val neutral  = scores[2].toDouble()
        val porn     = scores[3].toDouble()
        val sexy     = scores[4].toDouble()

        val nsfwScore = maxOf(porn, hentai, sexy)

        return mapOf(
            "isNSFW"     to (nsfwScore >= threshold),
            "confidence" to nsfwScore,
            "threshold"  to threshold,
            "categories" to mapOf(
                "drawings" to drawings,
                "hentai"   to hentai,
                "neutral"  to neutral,
                "porn"     to porn,
                "sexy"     to sexy,
            ),
            "source"     to "tflite-image",
            "durationMs" to durationMs,
        )
    }

    private fun bitmapToByteBuffer(bitmap: Bitmap): ByteBuffer {
        val buf = ByteBuffer.allocateDirect(4 * INPUT_SIZE * INPUT_SIZE * 3)
        buf.order(ByteOrder.nativeOrder())
        val pixels = IntArray(INPUT_SIZE * INPUT_SIZE)
        bitmap.getPixels(pixels, 0, INPUT_SIZE, 0, 0, INPUT_SIZE, INPUT_SIZE)
        for (pixel in pixels) {
            buf.putFloat(((pixel shr 16) and 0xFF) / 255.0f) // R
            buf.putFloat(((pixel shr 8)  and 0xFF) / 255.0f) // G
            buf.putFloat((pixel          and 0xFF) / 255.0f) // B
        }
        buf.rewind()
        return buf
    }

    fun close() {
        backend?.close()
        backend = null
    }
}
