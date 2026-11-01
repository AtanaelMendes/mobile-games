package com.example.mobile_games

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Matrix
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.Surface
import androidx.camera.core.CameraSelector
import androidx.camera.core.Camera
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.core.ImageProxy
import androidx.camera.core.resolutionselector.AspectRatioStrategy
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.camera2.interop.Camera2CameraInfo
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
    private var front = false
    private var mirror = false
    private var selectedCameraId: String? = null
    private var requestedZoom = 1f
    private var activeCamera: Camera? = null
    private var active = false
    private var generation = 0
    private var loggedFrameSize = false
    private val soundPool by lazy {
        SoundPool.Builder().setMaxStreams(4).setAudioAttributes(
            AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
        ).build()
    }
    private val popSound by lazy { soundPool.load(this, R.raw.pop, 1) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        popSound
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "mobile_games/camera_view", object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
                override fun create(context: android.content.Context, viewId: Int, args: Any?): PlatformView {
                    val view = PreviewView(context)
                    view.implementationMode = PreviewView.ImplementationMode.COMPATIBLE
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
                        front = call.argument<Boolean>("front") ?: false
                        mirror = call.argument<Boolean>("mirror") ?: false
                        selectedCameraId = call.argument<String>("cameraId")
                        requestedZoom = (call.argument<Double>("zoom") ?: 1.0).toFloat()
                        if (active) bindCamera()
                        result.success(null)
                    }
                    "listCameras" -> listCameras(result)
                    "setZoom" -> {
                        val zoom = (call.argument<Double>("zoom") ?: 1.0).toFloat()
                        applyZoom(zoom, result)
                    }
                    "start" -> start(result)
                    "stop" -> {
                        stopCamera()
                        result.success(null)
                    }
                    "playPop" -> {
                        soundPool.play(popSound, 0.6f, 0.6f, 1, 0, 1f)
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
            bindCamera()
            result?.success(null)
        } else result?.error("camera_permission", "Permissão da câmera negada", null)
    }

    private fun bindCamera() {
        val view = previewView ?: return
        if (!active) return
        loggedFrameSize = false
        val token = ++generation
        val future: ListenableFuture<ProcessCameraProvider> = ProcessCameraProvider.getInstance(this)
        future.addListener({
            if (!active || token != generation) return@addListener
            try {
                val cameraProvider = future.get()
                provider = cameraProvider
                cameraProvider.unbindAll()
                val defaultSelector = CameraSelector.Builder().requireLensFacing(
                    if (front) CameraSelector.LENS_FACING_FRONT else CameraSelector.LENS_FACING_BACK
                ).build()
                if (!cameraProvider.hasCamera(defaultSelector)) {
                    sendError("Câmera selecionada indisponível")
                    return@addListener
                }
                val selectedInfo = cameraProvider.availableCameraInfos.firstOrNull { info ->
                    Camera2CameraInfo.from(info).cameraId == selectedCameraId
                }
                val selector = if (selectedInfo != null) {
                    val facing = Camera2CameraInfo.from(selectedInfo).getCameraCharacteristic(
                        CameraCharacteristics.LENS_FACING)
                    CameraSelector.Builder().requireLensFacing(if (facing ==
                        CameraCharacteristics.LENS_FACING_FRONT) CameraSelector.LENS_FACING_FRONT
                        else CameraSelector.LENS_FACING_BACK)
                        .addCameraFilter { infos ->
                            infos.filter { Camera2CameraInfo.from(it).cameraId == selectedCameraId }
                        }.build()
                } else defaultSelector
                val usingFront = selectedInfo?.let { info ->
                    Camera2CameraInfo.from(info).getCameraCharacteristic(
                        CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_FRONT
                } ?: front
                // PreviewView mirrors front cameras by default. Match the requested display image.
                view.scaleX = if (usingFront == mirror) 1f else -1f
                val rotation = view.display?.rotation ?: Surface.ROTATION_90
                val wideAspect = AspectRatioStrategy.RATIO_16_9_FALLBACK_AUTO_STRATEGY
                val preview = Preview.Builder()
                    .setResolutionSelector(ResolutionSelector.Builder()
                        .setAspectRatioStrategy(wideAspect).build())
                    .setTargetRotation(rotation)
                    .build()
                preview.surfaceProvider = view.surfaceProvider
                val analysis = ImageAnalysis.Builder()
                    .setResolutionSelector(ResolutionSelector.Builder()
                        .setAspectRatioStrategy(wideAspect)
                        .setResolutionStrategy(ResolutionStrategy(
                            android.util.Size(640, 360),
                            ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER))
                        .build())
                    .setTargetRotation(rotation)
                    .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()
                analysis.setAnalyzer(executor) { image -> analyze(image) }
                val camera = cameraProvider.bindToLifecycle(this, selector, preview, analysis)
                activeCamera = camera
                val zoomState = camera.cameraInfo.zoomState.value
                val safeZoom = requestedZoom.coerceIn(
                    zoomState?.minZoomRatio ?: 1f, zoomState?.maxZoomRatio ?: 1f)
                camera.cameraControl.setZoomRatio(safeZoom)
                sendStatus("${if (usingFront) "Frontal" else "Traseira"} · câmera ${Camera2CameraInfo.from(camera.cameraInfo).cameraId} · ${safeZoom}×")
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
            if (!loggedFrameSize) {
                android.util.Log.i("MobileGamesCamera", "Quadro orientado: ${display.width}x${display.height}")
                loggedFrameSize = true
            }
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

    private fun sendStatus(message: String) {
        mainHandler.post { eventSink?.success(mapOf("type" to "status", "message" to message)) }
    }

    private fun listCameras(result: MethodChannel.Result) {
        val future = ProcessCameraProvider.getInstance(this)
        future.addListener({
            try {
                val usable = future.get().availableCameraInfos.associateBy {
                    Camera2CameraInfo.from(it).cameraId
                }
                val manager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
                val cameras = manager.cameraIdList.map { id ->
                    val characteristics = manager.getCameraCharacteristics(id)
                    val facing = characteristics.get(CameraCharacteristics.LENS_FACING)
                    val focal = characteristics.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
                        ?.minOrNull() ?: 0f
                    val sensor = characteristics.get(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE)
                    val field = if (focal > 0 && sensor != null) sensor.width / focal else 0f
                    val zoomRange = if (android.os.Build.VERSION.SDK_INT >= 30) {
                        characteristics.get(CameraCharacteristics.CONTROL_ZOOM_RATIO_RANGE)
                    } else null
                    mapOf(
                        "id" to id,
                        "facing" to if (facing == CameraCharacteristics.LENS_FACING_FRONT) "front" else "back",
                        "field" to field.toDouble(),
                        "minZoom" to (zoomRange?.lower ?: 1f).toDouble(),
                        "maxZoom" to (zoomRange?.upper ?: characteristics.get(
                            CameraCharacteristics.SCALER_AVAILABLE_MAX_DIGITAL_ZOOM) ?: 1f).toDouble(),
                        "usable" to usable.containsKey(id),
                    )
                }
                android.util.Log.i("MobileGamesCamera", "Câmeras do app: " +
                    cameras.joinToString { "${it["id"]}:${it["facing"]},zoom=${it["minZoom"]}-${it["maxZoom"]},usável=${it["usable"]}" })
                result.success(cameras)
            } catch (e: Exception) {
                result.error("camera_list", e.message, null)
            }
        }, ContextCompat.getMainExecutor(this))
    }

    private fun applyZoom(zoom: Float, result: MethodChannel.Result) {
        val camera = activeCamera
        val state = camera?.cameraInfo?.zoomState?.value
        if (camera == null || state == null) {
            result.error("camera_not_ready", "Câmera ainda não está pronta", null)
            return
        }
        requestedZoom = zoom.coerceIn(state.minZoomRatio, state.maxZoomRatio)
        val future = camera.cameraControl.setZoomRatio(requestedZoom)
        future.addListener({
            try {
                future.get()
                result.success(requestedZoom.toDouble())
                sendStatus("Câmera ${Camera2CameraInfo.from(camera.cameraInfo).cameraId} · ${requestedZoom}×")
            } catch (e: Exception) {
                result.error("camera_zoom", e.message, null)
            }
        }, ContextCompat.getMainExecutor(this))
    }

    private fun stopCamera() {
        active = false
        generation++
        activeCamera = null
        provider?.unbindAll()
        executor.execute {
            landmarker?.close()
            landmarker = null
        }
    }

    override fun onDestroy() {
        stopCamera()
        executor.shutdown()
        soundPool.release()
        super.onDestroy()
    }
}
