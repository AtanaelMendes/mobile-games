package com.example.mobile_games

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Matrix
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.Surface
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.core.ImageProxy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.common.util.concurrent.ListenableFuture
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.plugin.common.StandardMessageCodec
import java.util.concurrent.Executors
import java.util.concurrent.ExecutorService

class MainActivity : FlutterActivity() {
    private val channelName = "mobile_games/camera"
    private val eventName = "mobile_games/poses"
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private var previewView: PreviewView? = null
    private var provider: ProcessCameraProvider? = null
    private var landmarker: PoseLandmarker? = null
    private var eventSink: EventChannel.EventSink? = null
    private var startResult: MethodChannel.Result? = null
    private var requested = false
    private var front = true
    private var mirror = true
    private var active = false
    private var generation = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "mobile_games/camera_view", object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
                override fun create(context: android.content.Context, viewId: Int, args: Any?): PlatformView {
                    val view = PreviewView(context)
                    view.scaleType = PreviewView.ScaleType.FIT_CENTER
                    previewView = view
                    if (active) mainHandler.post { bindCamera() }
                    return object : PlatformView {
                        override fun getView(): View = view
                        override fun dispose() {
                            if (previewView === view) previewView = null
                        }
                    }
                }
            })
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }
                override fun onCancel(arguments: Any?) { eventSink = null }
            })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "configure" -> {
                        front = call.argument<Boolean>("front") ?: true
                        mirror = call.argument<Boolean>("mirror") ?: true
                        if (active) bindCamera()
                        result.success(null)
                    }
                    "start" -> start(result)
                    "stop" -> {
                        stopCamera()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun start(result: MethodChannel.Result) {
        if (active) { result.success(null); return }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
            != PackageManager.PERMISSION_GRANTED) {
            startResult = result
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.CAMERA), 501)
            return
        }
        active = true
        requested = true
        bindCamera()
        result.success(null)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>,
                                            grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != 501) return
        val result = startResult
        startResult = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            active = true
            requested = true
            bindCamera()
            result?.success(null)
        } else result?.error("camera_permission", "Permissão da câmera negada", null)
    }

    private fun bindCamera() {
        val view = previewView ?: return
        if (!active) return
        val token = ++generation
        val future: ListenableFuture<ProcessCameraProvider> = ProcessCameraProvider.getInstance(this)
        future.addListener({
            if (!active || token != generation) return@addListener
            try {
                val cameraProvider = future.get()
                provider = cameraProvider
                cameraProvider.unbindAll()
                val selector = CameraSelector.Builder().requireLensFacing(
                    if (front) CameraSelector.LENS_FACING_FRONT else CameraSelector.LENS_FACING_BACK
                ).build()
                if (!cameraProvider.hasCamera(selector)) {
                    sendError("Câmera selecionada indisponível")
                    return@addListener
                }
                // PreviewView mirrors front cameras by default. Match the requested display image.
                view.scaleX = if (front == mirror) 1f else -1f
                val rotation = view.display?.rotation ?: Surface.ROTATION_90
                val preview = Preview.Builder().setTargetRotation(rotation).build()
                preview.surfaceProvider = view.surfaceProvider
                val analysis = ImageAnalysis.Builder()
                    .setTargetResolution(android.util.Size(640, 480))
                    .setTargetRotation(rotation)
                    .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()
                analysis.setAnalyzer(executor) { image -> analyze(image) }
                cameraProvider.bindToLifecycle(this, selector, preview, analysis)
            } catch (e: Exception) {
                sendError("Falha ao abrir a câmera: ${e.message}")
            }
        }, ContextCompat.getMainExecutor(this))
    }

    private fun analyze(image: ImageProxy) {
        try {
            if (!active) return
            if (landmarker == null) {
                landmarker = PoseLandmarker.createFromOptions(this,
                    PoseLandmarker.PoseLandmarkerOptions.builder()
                        .setBaseOptions(BaseOptions.builder()
                            .setModelAssetPath("pose_landmarker_lite.task").build())
                        .setRunningMode(RunningMode.IMAGE)
                        .setNumPoses(1)
                        .setMinPoseDetectionConfidence(0.5f)
                        .setMinPosePresenceConfidence(0.5f)
                        .build())
            }
            val source = bitmapFrom(image)
            val matrix = Matrix().apply {
                postRotate(image.imageInfo.rotationDegrees.toFloat())
            }
            val oriented = Bitmap.createBitmap(source, 0, 0, source.width, source.height, matrix, true)
            if (oriented !== source) source.recycle()
            val display = if (mirror) {
                val flip = Matrix().apply { postScale(-1f, 1f) }
                Bitmap.createBitmap(oriented, 0, 0, oriented.width, oriented.height, flip, true)
            } else oriented
            if (display !== oriented) oriented.recycle()
            val half = display.width / 2
            val timestamp = System.currentTimeMillis()
            for (region in 0..1) {
                val startNs = System.nanoTime()
                val crop = Bitmap.createBitmap(display, region * half, 0,
                    if (region == 0) half else display.width - half, display.height)
                val result = landmarker!!.detect(BitmapImageBuilder(crop).build())
                val joints = HashMap<String, List<Float>>()
                val pose = result.landmarks().firstOrNull()
                pose?.forEachIndexed { index, point ->
                    val confidence = point.visibility().orElse(0f)
                    joints[index.toString()] = listOf(point.x(), point.y(), confidence)
                }
                crop.recycle()
                val event = mapOf(
                    "player" to if (region == 0) "player1" else "player2",
                    "timestampMs" to timestamp,
                    "processingMs" to (System.nanoTime() - startNs) / 1_000_000.0,
                    "width" to display.width,
                    "height" to display.height,
                    "joints" to joints
                )
                mainHandler.post { if (active) eventSink?.success(event) }
            }
            display.recycle()
        } catch (e: Exception) {
            sendError("Falha na detecção: ${e.message}")
        } finally {
            image.close()
        }
    }

    private fun bitmapFrom(image: ImageProxy): Bitmap {
        val plane = image.planes[0]
        val buffer = plane.buffer
        val rowBytes = image.width * 4
        val pixels = ByteArray(rowBytes * image.height)
        for (row in 0 until image.height) {
            buffer.position(row * plane.rowStride)
            buffer.get(pixels, row * rowBytes, rowBytes)
        }
        val bitmap = Bitmap.createBitmap(image.width, image.height, Bitmap.Config.ARGB_8888)
        bitmap.copyPixelsFromBuffer(java.nio.ByteBuffer.wrap(pixels))
        return bitmap
    }

    private fun sendError(message: String) {
        mainHandler.post { eventSink?.error("camera_error", message, null) }
    }

    private fun stopCamera() {
        active = false
        generation++
        provider?.unbindAll()
        executor.execute {
            landmarker?.close()
            landmarker = null
        }
    }

    override fun onDestroy() {
        stopCamera()
        executor.shutdown()
        super.onDestroy()
    }
}
