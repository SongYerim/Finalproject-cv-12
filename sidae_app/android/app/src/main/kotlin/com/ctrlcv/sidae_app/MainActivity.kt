/**
 * YOLO 온디바이스 객체 감지 앱
 * 
 * 네이티브 전체 파이프라인:
 * - Android: CameraX + Kotlin에서 전처리+추론+후처리
 * - Flutter: UI만 담당 (Method Channel + EventChannel)
 * 
 * 기능별 모듈 분리:
 * - yolo/YoloProcessor: YOLO 추론, 전처리, 후처리
 * - yolo/YoloBox: 감지 결과 데이터 클래스
 * - camera/BoundingBoxOverlayView: 바운딩 박스 그리기
 * - camera/CameraPreviewFactory: PlatformView Factory
 * - gps/ExitTracker: 횡단보도 반대편 도달 감지
 * - navigation/NavigationManager: 센서+GPS 네비게이션
 * - stt/SpeechRecognizerManager: 음성인식
 */

package com.ctrlcv.sidae_app

import android.graphics.ImageFormat
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.concurrent.futures.await
import com.google.common.util.concurrent.ListenableFuture
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.io.BufferedInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileInputStream
import java.net.HttpURLConnection
import java.net.URL

// 분리된 모듈 import
import com.ctrlcv.sidae_app.yolo.YoloProcessor
import com.ctrlcv.sidae_app.camera.BoundingBoxOverlayView
import com.ctrlcv.sidae_app.camera.CameraPreviewCallback
import com.ctrlcv.sidae_app.camera.CameraPreviewFactory
import com.ctrlcv.sidae_app.gps.ExitTracker
import com.ctrlcv.sidae_app.gps.ExitTrackerListener
import com.ctrlcv.sidae_app.navigation.NavigationManager
import com.ctrlcv.sidae_app.navigation.NavigationListener
import com.ctrlcv.sidae_app.stt.SpeechRecognizerManager
import com.ctrlcv.sidae_app.stt.SpeechRecognizerListener
import com.ctrlcv.sidae_app.stt.SttEventType
import com.ctrlcv.sidae_app.audio.SpatialAudioManager

/**
 * 메인 액티비티
 * 
 * Flutter와 네이티브 모듈 간의 통신을 담당합니다.
 */
class MainActivity : FlutterActivity(), CameraPreviewCallback {
    
    companion object {
        private const val CHANNEL = "com.ctrlcv.sidae_app/yolo_native"
        private const val EVENT_CHANNEL = "com.ctrlcv.sidae_app/yolo_detections"
        private const val TAG = "MainActivity"
    }
    
    // ===== 카메라 관련 =====
    private var cameraProvider: ProcessCameraProvider? = null
    private var imageAnalysis: ImageAnalysis? = null
    private var preview: Preview? = null
    private var previewView: PreviewView? = null
    private var boundingBoxOverlayView: BoundingBoxOverlayView? = null
    private var camera: Camera? = null
    @Volatile private var isProcessing = false
    @Volatile private var cameraWidth = 640
    @Volatile private var cameraHeight = 480
    
    // ===== FPS 계산 =====
    private var frameCount = 0
    private var lastFpsUpdate = System.currentTimeMillis()
    private var fps = 0.0

    // ===== ROTATION_VECTOR 센서 =====
    private var sensorManager: SensorManager? = null
    private var rotationVectorSensor: Sensor? = null
    private var rotationVectorListener: SensorEventListener? = null
    
    // ===== Flutter 통신 =====
    private var eventSink: EventChannel.EventSink? = null
    private lateinit var cameraExecutor: ExecutorService
    private val mainHandler = Handler(Looper.getMainLooper())
    
    // ===== 분리된 모듈 인스턴스 =====
    private lateinit var yoloProcessor: YoloProcessor
    private lateinit var exitTracker: ExitTracker
    private lateinit var navigationManager: NavigationManager
    private lateinit var speechRecognizerManager: SpeechRecognizerManager
    private lateinit var spatialAudioManager: SpatialAudioManager
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        cameraExecutor = Executors.newSingleThreadExecutor()
        
        // 모듈 초기화
        initializeModules()
        
        // MethodChannel 설정
        setupMethodChannel(flutterEngine)
        
        // EventChannel 설정
        setupEventChannel(flutterEngine)
        
        // PlatformView 등록
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "cameraPreview",
            CameraPreviewFactory(this)
        )
    }
    
    /**
     * 모듈 초기화
     */
    private fun initializeModules() {
        yoloProcessor = YoloProcessor(this)
        exitTracker = ExitTracker(this)
        navigationManager = NavigationManager(this)
        speechRecognizerManager = SpeechRecognizerManager(this)
        spatialAudioManager = SpatialAudioManager(this)
        
        // 리스너 설정
        setupExitTrackerListener()
        setupNavigationListener()
        setupSpeechRecognizerListener()
    }
    
    /**
     * MethodChannel 설정
     */
    private fun setupMethodChannel(flutterEngine: FlutterEngine) {
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> handleInitialize(call.arguments as? Map<*, *>, result)
                "startCamera" -> handleStartCamera(result)
                "stopCamera" -> handleStopCamera(result)
                "getFps" -> result.success(fps)
                "startExitTracking" -> handleStartExitTracking(call, result)
                "stopExitTracking" -> handleStopExitTracking(result)
                "startNavigation" -> handleStartNavigation(result)
                "stopNavigation" -> handleStopNavigation(result)
                "updateNavigationTarget" -> handleUpdateNavigationTarget(call, result)
                "startListening" -> handleStartListening(result)
                "stopListening" -> handleStopListening(result)
                "captureAndUploadImage" -> handleCaptureAndUploadImage(call, result)
                // 공간음향 관련
                "initializeSpatialAudio" -> handleInitializeSpatialAudio(result)
                "startSpatialAudio" -> handleStartSpatialAudio(result)
                "stopSpatialAudio" -> handleStopSpatialAudio(result)
                "updateSpatialAudioDirection" -> handleUpdateSpatialAudioDirection(call, result)
                "setSpatialAudioVolume" -> handleSetSpatialAudioVolume(call, result)
                "releaseSpatialAudio" -> handleReleaseSpatialAudio(result)
                "startRotationVector" -> {
                    startRotationVectorSensor()
                    result.success(true)
                }
                "stopRotationVector" -> {
                    stopRotationVectorSensor()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
            }
        }
        
    /**
     * EventChannel 설정
     */
    private fun setupEventChannel(flutterEngine: FlutterEngine) {
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }
                
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }
    
    // ===== MethodChannel 핸들러 =====
    
    private fun handleInitialize(args: Map<*, *>?, result: MethodChannel.Result) {
        val modelBytes = args?.get("modelBytes") as? ByteArray
        val labelsText = args?.get("labelsText") as? String
        val modelPath = args?.get("modelPath") as? String ?: ""
        
        if (modelBytes == null || labelsText == null) {
            result.error("INVALID_ARGUMENTS", "modelBytes and labelsText are required", null)
                    return
                }
        
        // 기존 카메라 중지
        try {
            cameraProvider?.unbindAll()
            camera = null
            imageAnalysis = null
            preview = null
            Log.d(TAG, "📷 기존 카메라 중지됨")
                    } catch (e: Exception) {
            Log.w(TAG, "⚠️ 기존 카메라 중지 중 오류: ${e.message}")
        }
        
        // YOLO 초기화
        val initResult = yoloProcessor.initialize(modelBytes, labelsText, modelPath)
        
        if (initResult.success) {
            result.success(mapOf(
                "initialized" to true,
                "engineType" to initResult.engineType
            ))
        } else {
            result.error("INIT_ERROR", initResult.errorMessage, null)
        }
    }
    
    private fun handleStartCamera(result: MethodChannel.Result) {
        val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
        scope.launch {
            try {
                val cameraProviderFuture: ListenableFuture<ProcessCameraProvider> = 
                    ProcessCameraProvider.getInstance(this@MainActivity)
                cameraProvider = cameraProviderFuture.await()
                
                val imageAnalysis = ImageAnalysis.Builder()
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888)
                    .setTargetResolution(android.util.Size(1920, 1080))
                    .build()
                
                imageAnalysis.setAnalyzer(cameraExecutor) { imageProxy ->
                    processImage(imageProxy)
                }
                
                val preview = Preview.Builder()
                    .setTargetResolution(android.util.Size(1920, 1080))
                    .build()
                preview.setSurfaceProvider(previewView?.surfaceProvider)
                
                val cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA
                
                try {
                    cameraProvider?.unbindAll()
                    camera = cameraProvider?.bindToLifecycle(
                        this@MainActivity,
                        cameraSelector,
                        preview,
                        imageAnalysis
                    )
                    
                    this@MainActivity.imageAnalysis = imageAnalysis
                    this@MainActivity.preview = preview
                    result.success(true)
                    Log.d(TAG, "✅ 카메라 시작 완료")
                } catch (e: Exception) {
                    Log.e(TAG, "카메라 바인딩 실패", e)
                    result.error("CAMERA_ERROR", e.message, null)
                }
            } catch (e: Exception) {
                Log.e(TAG, "카메라 초기화 실패", e)
                result.error("CAMERA_ERROR", e.message, null)
            }
        }
    }
    
    /**
     * 단일 캡처 후 서버 업로드 (버스 전용 화면)
     */
    private fun handleCaptureAndUploadImage(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        val uploadUrl = call.argument<String>("uploadUrl")
        if (uploadUrl.isNullOrBlank()) {
            result.error("INVALID_ARGUMENTS", "uploadUrl is required", null)
            return
        }

        val jpegQuality = call.argument<Int>("jpegQuality") ?: 90
        val useFront = call.argument<Boolean>("useFront") ?: false
        val metadata = call.argument<Map<String, String>>("metadata") ?: emptyMap()
        val keepFile = call.argument<Boolean>("keepFile") ?: false

        val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
        scope.launch {
            try {
                val cameraProviderFuture: ListenableFuture<ProcessCameraProvider> =
                    ProcessCameraProvider.getInstance(this@MainActivity)
                val provider = cameraProviderFuture.await()

                val imageCapture = ImageCapture.Builder()
                    .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
                    .setJpegQuality(jpegQuality)
                    .build()

                val selector = if (useFront) {
                    CameraSelector.DEFAULT_FRONT_CAMERA
                } else {
                    CameraSelector.DEFAULT_BACK_CAMERA
                }

                try {
                    provider.unbindAll()
                    provider.bindToLifecycle(this@MainActivity, selector, imageCapture)
                } catch (e: Exception) {
                    Log.e(TAG, "카메라 바인딩 실패", e)
                    result.error("CAMERA_BIND_ERROR", e.message, null)
                    return@launch
                }

                val photoFile = File(cacheDir, "bus_capture_${System.currentTimeMillis()}.jpg")
                val outputOptions = ImageCapture.OutputFileOptions.Builder(photoFile).build()

                imageCapture.takePicture(
                    outputOptions,
                    cameraExecutor,
                    object : ImageCapture.OnImageSavedCallback {
                        override fun onError(exception: ImageCaptureException) {
                            Log.e(TAG, "이미지 캡처 실패", exception)
                    mainHandler.post {
                                result.error("CAPTURE_ERROR", exception.message, null)
                            }
                        }

                        override fun onImageSaved(outputFileResults: ImageCapture.OutputFileResults) {
                            CoroutineScope(Dispatchers.IO).launch {
                                try {
                                    val uploadResult = uploadImageFile(uploadUrl, photoFile, metadata)
                                    withContext(Dispatchers.Main) {
                                        result.success(
                                            mapOf(
                                                "success" to uploadResult.success,
                                                "statusCode" to uploadResult.statusCode,
                                                "body" to uploadResult.body,
                                                "localPath" to photoFile.absolutePath
                                            )
                                        )
                                    }
                } catch (e: Exception) {
                                    Log.e(TAG, "업로드 실패", e)
                                    withContext(Dispatchers.Main) {
                                        result.success(
                                            mapOf(
                                                "success" to false,
                                                "statusCode" to -1,
                                                "body" to (e.message ?: ""),
                                                "localPath" to photoFile.absolutePath
                                            )
                                        )
                                    }
                                } finally {
                                    // 업로드 완료 후 즉시 카메라 해제
                                    try {
                                        provider.unbindAll()
                                        Log.d(TAG, "✅ 캡처/업로드 후 카메라 해제 완료")
                                    } catch (e: Exception) {
                                        Log.e(TAG, "카메라 해제 실패: ${e.message}")
                                    }
                                    if (!keepFile && photoFile.exists()) {
                                        photoFile.delete()
                                    }
                                }
                            }
                        }
                    }
                )
            } catch (e: Exception) {
                Log.e(TAG, "캡처/업로드 처리 실패", e)
                result.error("CAPTURE_FLOW_ERROR", e.message, null)
            }
        }
    }

    private data class UploadResult(
        val success: Boolean,
        val statusCode: Int,
        val body: String
    )

    private fun uploadImageFile(
        uploadUrl: String,
        photoFile: File,
        metadata: Map<String, String>
    ): UploadResult {
        val boundary = "----SidaeBoundary${System.currentTimeMillis()}"
        val lineEnd = "\r\n"
        val twoHyphens = "--"

        val url = URL(uploadUrl)
        val connection = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            doOutput = true
            doInput = true
            useCaches = false
            setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
        }

        DataOutputStream(connection.outputStream).use { outputStream ->
            for ((key, value) in metadata) {
                outputStream.writeBytes(twoHyphens + boundary + lineEnd)
                outputStream.writeBytes("Content-Disposition: form-data; name=\"$key\"$lineEnd")
                outputStream.writeBytes(lineEnd)
                outputStream.writeBytes(value)
                outputStream.writeBytes(lineEnd)
            }

            outputStream.writeBytes(twoHyphens + boundary + lineEnd)
            outputStream.writeBytes(
                "Content-Disposition: form-data; name=\"image\"; filename=\"capture.jpg\"$lineEnd"
            )
            outputStream.writeBytes("Content-Type: image/jpeg$lineEnd")
            outputStream.writeBytes(lineEnd)

            FileInputStream(photoFile).use { fileInput ->
                BufferedInputStream(fileInput).use { bufferedInput ->
                    val buffer = ByteArray(4096)
                    var bytesRead: Int
                    while (bufferedInput.read(buffer).also { bytesRead = it } != -1) {
                        outputStream.write(buffer, 0, bytesRead)
                    }
                }
            }

            outputStream.writeBytes(lineEnd)
            outputStream.writeBytes(twoHyphens + boundary + twoHyphens + lineEnd)
            outputStream.flush()
        }

        val statusCode = connection.responseCode
        val responseStream = if (statusCode in 200..299) {
            connection.inputStream
        } else {
            connection.errorStream
        }

        val body = responseStream?.bufferedReader()?.use { it.readText() } ?: ""
        return UploadResult(statusCode in 200..299, statusCode, body)
    }
    
    private fun handleStopCamera(result: MethodChannel.Result) {
        try {
            isProcessing = false
            cameraProvider?.unbindAll()
            camera = null
            imageAnalysis = null
            preview = null
            result.success(true)
            Log.d(TAG, "✅ 카메라 중지 완료")
        } catch (e: Exception) {
            Log.e(TAG, "카메라 중지 실패", e)
            result.error("CAMERA_ERROR", e.message, null)
        }
    }
    
    private fun handleStartExitTracking(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        val lat = call.argument<Double>("exitLat")
        val lng = call.argument<Double>("exitLng")
        
        if (lat == null || lng == null) {
            result.error("INVALID_ARGS", "exitLat and exitLng are required", null)
            return
        }
        
        if (exitTracker.startTracking(lat, lng)) {
            result.success(true)
        } else {
            result.error("PERMISSION_DENIED", "Location permission not granted", null)
        }
    }
    
    private fun handleStopExitTracking(result: MethodChannel.Result) {
        exitTracker.stopTracking()
        result.success(true)
    }
    
    private fun handleStartNavigation(result: MethodChannel.Result) {
        if (navigationManager.start()) {
            result.success(true)
            } else {
            result.error("PERMISSION_DENIED", "Location permission not granted", null)
        }
    }
    
    private fun handleStopNavigation(result: MethodChannel.Result) {
        navigationManager.stop()
        result.success(true)
    }
    
    private fun handleUpdateNavigationTarget(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        val lat = call.argument<Double>("targetLat")
        val lng = call.argument<Double>("targetLng")
        
        if (lat == null || lng == null) {
            result.error("INVALID_ARGS", "targetLat and targetLng are required", null)
            return
        }
        
        navigationManager.updateTarget(lat, lng)
        result.success(true)
    }
    
    private fun handleStartListening(result: MethodChannel.Result) {
        if (speechRecognizerManager.startListening()) {
            result.success(true)
        } else {
            result.error("STT_ERROR", "Failed to start listening", null)
        }
    }
    
    private fun handleStopListening(result: MethodChannel.Result) {
        speechRecognizerManager.stopListening()
        result.success(true)
    }

    // ===== ROTATION_VECTOR 센서 메서드 =====

    private fun startRotationVectorSensor() {
        if (sensorManager == null) {
            sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        }
        if (rotationVectorSensor == null) {
            rotationVectorSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
        }

        if (rotationVectorListener == null) {
            rotationVectorListener = object : SensorEventListener {
                override fun onSensorChanged(event: SensorEvent) {
                    if (event.sensor.type == Sensor.TYPE_ROTATION_VECTOR) {
                        try {
                            val rotationMatrix = FloatArray(9)
                            SensorManager.getRotationMatrixFromVector(rotationMatrix, event.values)

                            val orientation = FloatArray(3)
                            SensorManager.getOrientation(rotationMatrix, orientation)

                            // azimuth (rad -> deg)
                            var heading = Math.toDegrees(orientation[0].toDouble())
                            // 0~360 정규화
                            if (heading < 0) heading += 360

                            // Flutter로 전송
                            mainHandler.post {
                                eventSink?.success(mapOf(
                                    "type" to "heading",
                                    "heading" to heading
                                ))
                }
            } catch (e: Exception) {
                            Log.w(TAG, "센서 데이터 처리 오류: ${e.message}")
                        }
                    }
                }

                override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
            }
        }

        rotationVectorSensor?.let { sensor ->
            sensorManager?.registerListener(
                rotationVectorListener,
                sensor,
                SensorManager.SENSOR_DELAY_UI // UI 갱신 속도에 맞춤
            )
            Log.d(TAG, "🧭 ROTATION_VECTOR 센서 시작됨")
        }
    }

    private fun stopRotationVectorSensor() {
        if (sensorManager != null && rotationVectorListener != null) {
            sensorManager?.unregisterListener(rotationVectorListener)
            Log.d(TAG, "🛑 ROTATION_VECTOR 센서 중지됨")
        }
    }
    
    // ===== 공간음향 핸들러 =====
    
    private fun handleInitializeSpatialAudio(result: MethodChannel.Result) {
        val success = spatialAudioManager.initialize()
        if (success) {
            result.success(true)
        } else {
            result.error("SPATIAL_AUDIO_ERROR", "Failed to initialize spatial audio", null)
        }
    }
    
    private fun handleStartSpatialAudio(result: MethodChannel.Result) {
        spatialAudioManager.start()
        result.success(true)
    }
    
    private fun handleStopSpatialAudio(result: MethodChannel.Result) {
        spatialAudioManager.stop()
        result.success(true)
    }
    
    private fun handleUpdateSpatialAudioDirection(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        val angleDiff = call.argument<Double>("angleDiff")?.toFloat()
        val distance = call.argument<Double>("distance")?.toFloat() // 거리 파라미터 추가 (옵션)
        
        if (angleDiff == null) {
            result.error("INVALID_ARGS", "angleDiff is required", null)
            return
        }
        
        spatialAudioManager.updateDirection(angleDiff, distance)
        result.success(true)
    }
    
    private fun handleSetSpatialAudioVolume(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        val volume = call.argument<Double>("volume")?.toFloat()
        
        if (volume == null) {
            result.error("INVALID_ARGS", "volume is required", null)
            return
        }
        
        spatialAudioManager.setVolume(volume)
        result.success(true)
    }
    
    private fun handleReleaseSpatialAudio(result: MethodChannel.Result) {
        spatialAudioManager.release()
        result.success(true)
    }
    
    // ===== 리스너 설정 =====
    
    private fun setupExitTrackerListener() {
        exitTracker.setListener(object : ExitTrackerListener {
            override fun onLocationUpdate(distance: Double, reached: Boolean, lat: Double, lng: Double) {
                mainHandler.post {
                    try {
                        eventSink?.success(mapOf(
                            "type" to "exitDistance",
                            "distance" to distance,
                            "reached" to reached,
                            "lat" to lat,
                            "lng" to lng
                        ))
                    } catch (e: Exception) {
                        Log.w(TAG, "EventChannel 전송 실패: ${e.message}")
                    }
                }
            }
        })
    }
    
    private fun setupNavigationListener() {
        navigationManager.setListener(object : NavigationListener {
            override fun onNavigationUpdate(
                deviceHeading: Double,
                routeBearing: Double,
                travelingBearing: Double,
                targetLat: Double?,
                targetLng: Double?
            ) {
        mainHandler.post {
            try {
                        eventSink?.success(mapOf(
                            "type" to "navigation",
                            "deviceHeading" to deviceHeading,
                            "routeBearing" to routeBearing,
                            "travelingBearing" to travelingBearing,
                            "targetLat" to targetLat,
                            "targetLng" to targetLng
                        ))
            } catch (e: Exception) {
                        Log.w(TAG, "Navigation EventChannel 전송 실패: ${e.message}")
                    }
                }
            }
        })
    }
    
    private fun setupSpeechRecognizerListener() {
        speechRecognizerManager.setListener(object : SpeechRecognizerListener {
            override fun onSttEvent(eventType: SttEventType, data: String) {
                mainHandler.post {
                    try {
                        eventSink?.success(mapOf(
                            "type" to "stt",
                            "eventType" to eventType.name.lowercase(),
                            "data" to data
                        ))
                    } catch (e: Exception) {
                        Log.w(TAG, "STT EventChannel 전송 실패: ${e.message}")
                    }
                }
            }
        })
    }
    
    // ===== 이미지 처리 =====
    
    private fun processImage(imageProxy: ImageProxy) {
        if (isProcessing) {
            imageProxy.close()
            return
        }
        
        isProcessing = true
        
        try {
            val image = imageProxy.image
            if (image != null && image.format == ImageFormat.YUV_420_888) {
                // 카메라 해상도 업데이트
                val currentWidth = imageProxy.width
                val currentHeight = imageProxy.height
                if (cameraWidth != currentWidth || cameraHeight != currentHeight) {
                    cameraWidth = currentWidth
                    cameraHeight = currentHeight
                    Log.d(TAG, "📐 카메라 해상도 업데이트: ${cameraWidth}x${cameraHeight}")
                    mainHandler.post {
                        boundingBoxOverlayView?.setCameraSize(cameraWidth, cameraHeight)
                    }
                }
                
                try {
                    // YOLO 추론 실행
                    val detections = yoloProcessor.runInference(image, imageProxy.width, imageProxy.height)
                    
                    // FPS 업데이트
                    updateFps()
                    
                    // Flutter로 결과 전송
                    sendDetectionsToFlutter(detections)
                } catch (e: OutOfMemoryError) {
                    Log.e(TAG, "메모리 부족: ${e.message}")
                    System.gc()
                } catch (e: Exception) {
                    Log.e(TAG, "추론 실패: ${e.message}", e)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "이미지 처리 실패", e)
        } finally {
            try {
                imageProxy.close()
            } catch (e: Exception) {
                Log.w(TAG, "imageProxy.close() 실패: ${e.message}")
            }
            isProcessing = false
        }
    }
    
    private fun updateFps() {
        frameCount++
        val now = System.currentTimeMillis()
        if (now - lastFpsUpdate >= 1000) {
            fps = frameCount / ((now - lastFpsUpdate) / 1000.0)
            frameCount = 0
            lastFpsUpdate = now
            Log.d(TAG, "📊 FPS: ${String.format("%.1f", fps)}")
        }
    }
    
    private fun sendDetectionsToFlutter(detections: List<Map<String, Any>>) {
        val sink = eventSink ?: return
        val data = mapOf(
            "detections" to detections,
            "fps" to fps
        )
        mainHandler.post {
            try {
                sink.success(data)
                boundingBoxOverlayView?.updateDetections(detections)
            } catch (e: Exception) {
                Log.w(TAG, "EventChannel 전송 실패: ${e.message}")
            }
        }
    }
    
    // ===== CameraPreviewCallback 구현 =====
    
    override fun onPreviewViewCreated(previewView: PreviewView, overlayView: BoundingBoxOverlayView) {
        this.previewView = previewView
        this.boundingBoxOverlayView = overlayView
        Log.d(TAG, "✅ PreviewView 및 BoundingBoxOverlayView 설정 완료")
        
        // 이미 카메라가 시작되어 있다면 Preview 다시 바인딩
        preview?.setSurfaceProvider(previewView.surfaceProvider)
    }
    
    // ===== 라이프사이클 =====
    
    override fun onDestroy() {
        super.onDestroy()
        
        // 카메라 리소스 해제
        cameraProvider?.unbindAll()
        cameraExecutor.shutdown()
        
        // 모듈 리소스 해제
        yoloProcessor.release()
        exitTracker.release()
        navigationManager.release()
        speechRecognizerManager.release()
        stopRotationVectorSensor() // 센서 해제
        spatialAudioManager.release()
        
        Log.d(TAG, "✅ 모든 리소스 해제 완료")
    }
}
