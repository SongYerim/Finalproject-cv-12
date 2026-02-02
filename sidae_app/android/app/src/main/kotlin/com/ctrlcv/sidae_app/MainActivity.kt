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

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.YuvImage
import java.io.ByteArrayOutputStream
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
    @Volatile private var isInferenceEnabled = true // YOLO 추론 활성화 여부
    @Volatile private var isSnapshotRequested = false
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
                "setInferenceEnabled" -> handleSetInferenceEnabled(call, result)
                "captureSnapshot" -> handleCaptureSnapshot(result)
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
        // 상태 변수 초기화 (시작 시점에도 확실히 리셋)
        cameraWidth = 0
        cameraHeight = 0

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
                                    // 업로드 완료 후 즉시 카메라 해제 (메인 스레드에서 실행)
                                    withContext(Dispatchers.Main) {
                                        try {
                                            provider.unbindAll()
                                            Log.d(TAG, "✅ 캡처/업로드 후 카메라 해제 완료")
                                        } catch (e: Exception) {
                                            Log.e(TAG, "카메라 해제 실패: ${e.message}", e)
                                        }
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
        // 파일 존재 및 크기 확인
        if (!photoFile.exists()) {
            Log.e(TAG, "❌ 파일이 존재하지 않음: ${photoFile.absolutePath}")
            return UploadResult(false, -1, "File does not exist: ${photoFile.absolutePath}")
        }
        
        val fileSize = photoFile.length()
        if (fileSize == 0L) {
            Log.e(TAG, "❌ 파일 크기가 0: ${photoFile.absolutePath}")
            return UploadResult(false, -1, "File is empty: ${photoFile.absolutePath}")
        }
        
        Log.d(TAG, "📤 파일 업로드 시작: ${photoFile.name}, 크기: $fileSize bytes")
        Log.d(TAG, "📤 업로드 URL: $uploadUrl")
        Log.d(TAG, "📤 메타데이터: $metadata")
        
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
                "Content-Disposition: form-data; name=\"file\"; filename=\"capture.jpg\"$lineEnd"
            )
            outputStream.writeBytes("Content-Type: image/jpeg$lineEnd")
            outputStream.writeBytes(lineEnd)

            var totalBytesWritten = 0L
            FileInputStream(photoFile).use { fileInput ->
                BufferedInputStream(fileInput).use { bufferedInput ->
                    val buffer = ByteArray(4096)
                    var bytesRead: Int
                    while (bufferedInput.read(buffer).also { bytesRead = it } != -1) {
                        outputStream.write(buffer, 0, bytesRead)
                        totalBytesWritten += bytesRead
                    }
                }
            }
            
            Log.d(TAG, "✅ 파일 데이터 전송 완료: $totalBytesWritten bytes")

            outputStream.writeBytes(lineEnd)
            outputStream.writeBytes(twoHyphens + boundary + twoHyphens + lineEnd)
            outputStream.flush()
            
            Log.d(TAG, "✅ Multipart form-data 전송 완료")
        }

        val statusCode = connection.responseCode
        val responseStream = if (statusCode in 200..299) {
            connection.inputStream
        } else {
            connection.errorStream
        }

        val body = responseStream?.bufferedReader()?.use { it.readText() } ?: ""
        Log.d(TAG, "📥 서버 응답: statusCode=$statusCode, body=$body")
        
        if (statusCode !in 200..299) {
            Log.e(TAG, "❌ 업로드 실패: $body")
        }
        
        return UploadResult(statusCode in 200..299, statusCode, body)
    }
    
    private fun handleStopCamera(result: MethodChannel.Result) {
        // 메인 스레드에서 실행
        mainHandler.post {
            try {
                Log.d(TAG, "🛑 handleStopCamera 호출")
                isProcessing = false
                isInferenceEnabled = true  // 카메라 중지 시 추론 활성화 초기화
                
                // 상태 변수 초기화 (중요: 재진입 시 오버레이 좌표 오차 방지)
                cameraWidth = 0
                cameraHeight = 0
                
                // 바운딩 박스 오버레이 초기화
                boundingBoxOverlayView?.clearDetections()
                Log.d(TAG, "  - BoundingBoxOverlay 및 해상도 변수 초기화 완료")
                
                // 카메라 해제 (메인 스레드에서 실행)
                try {
                    if (cameraProvider != null) {
                        cameraProvider?.unbindAll()
                        Log.d(TAG, "  - cameraProvider.unbindAll() 완료")
                    } else {
                        Log.d(TAG, "  - cameraProvider가 이미 null이므로 해제 스킵")
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "  - cameraProvider.unbindAll() 실패: ${e.message}", e)
                }
                
                camera = null
                imageAnalysis = null
                preview = null
                previewView = null  // PreviewView도 null로 설정
                
                result.success(true)
                Log.d(TAG, "✅ 카메라 중지 완료")
            } catch (e: Exception) {
                Log.e(TAG, "카메라 중지 실패", e)
                result.error("CAMERA_ERROR", e.message, null)
            }
        }
    }

    private fun handleCaptureSnapshot(result: MethodChannel.Result) {
        Log.d(TAG, "📸 handleCaptureSnapshot 호출")
        isSnapshotRequested = true
        result.success(true)
    }

    private fun handleSetInferenceEnabled(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        val enabled = call.argument<Boolean>("enabled") ?: true
        isInferenceEnabled = enabled
        Log.d(TAG, "🧠 추론 상태 변경 요청: $enabled")
        
        // 비활성화 시 즉시 오버레이 클리어
        if (!enabled) {
            mainHandler.post {
                boundingBoxOverlayView?.clearDetections()
            }
        }
        result.success(true)
    }
    
    private fun handleStartExitTracking(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        val lat = call.argument<Double>("exitLat")
        val lng = call.argument<Double>("exitLng")
        val threshold = call.argument<Double>("exitThreshold") ?: 15.0
        
        if (lat == null || lng == null) {
            result.error("INVALID_ARGS", "exitLat and exitLng are required", null)
            return
        }
        
        if (exitTracker.startTracking(lat, lng, threshold)) {
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
                    // YOLO 추론 실행 (활성화된 경우에만)
                    val detections: List<Map<String, Any>> = if (isInferenceEnabled) {
                        yoloProcessor.runInference(image, imageProxy.width, imageProxy.height)
                    } else {
                        emptyList()
                    }
                    
                    // 디버깅: 감지된 모든 객체 로그 출력
                    if (detections.isNotEmpty()) {
                        val detectedList = detections.joinToString(", ") { 
                            "${it["label"]}(${String.format("%.2f", it["confidence"])})" 
                        }
                        Log.d(TAG, "🔍 감지됨: $detectedList")
                    } else {
                        // Log.d(TAG, "🔍 감지된 객체 없음")
                    }

                    // --- 가장 큰 버스 이미지 크롭 ---
                    var croppedBusBytes: ByteArray? = null
                    try {
                        val bestBus = detections.filter { 
                            val rawLabel = it["label"]
                            val label = rawLabel as? String
                            // 상세 디버깅: 라벨 타입과 값 확인
                            // if (rawLabel != null) Log.d(TAG, "🔍 체크 중: '$rawLabel' (${rawLabel.javaClass.simpleName})")
                            
                            label != null && label.trim().equals("bus", ignoreCase = true) 
                        }
                            .maxByOrNull { dict ->
                                val bbox = dict["bbox"] as List<*>
                                val w = (bbox[2] as Number).toFloat() - (bbox[0] as Number).toFloat()
                                val h = (bbox[3] as Number).toFloat() - (bbox[1] as Number).toFloat()
                                w * h
                            }

                        if (bestBus != null) {
                            Log.d(TAG, "🚌 버스 찾음! Confidence: ${bestBus["confidence"]}")
                            val bitmap = imageProxyToBitmap(imageProxy)
                            if (bitmap != null) {
                                val bbox = bestBus["bbox"] as List<*>
                                val x1 = (bbox[0] as Number).toFloat()
                                val y1 = (bbox[1] as Number).toFloat()
                                val x2 = (bbox[2] as Number).toFloat()
                                val y2 = (bbox[3] as Number).toFloat()

                                val left = x1.toInt().coerceIn(0, bitmap.width)
                                val top = y1.toInt().coerceIn(0, bitmap.height)
                                val width = (x2 - x1).toInt().coerceIn(1, bitmap.width - left)
                                val height = (y2 - y1).toInt().coerceIn(1, bitmap.height - top)

                                if (width > 0 && height > 0) {
                                    val croppedBitmap = Bitmap.createBitmap(bitmap, left, top, width, height)
                                    val stream = ByteArrayOutputStream()
                                    // 품질 80으로 압축
                                    croppedBitmap.compress(Bitmap.CompressFormat.JPEG, 80, stream)
                                    croppedBusBytes = stream.toByteArray()
                                }
                            }
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Crop 실패: ${e.message}")
                    }

                    // --- 스냅샷 요청 처리 (전체 화면 캡쳐) ---
                    if (isSnapshotRequested) {
                        try {
                            Log.d(TAG, "📸 스냅샷 캡쳐 중...")
                            val bitmap = imageProxyToBitmap(imageProxy)
                            if (bitmap != null) {
                                val stream = ByteArrayOutputStream()
                                bitmap.compress(Bitmap.CompressFormat.JPEG, 85, stream) // 품질 85
                                val snapshotBytes = stream.toByteArray()
                                
                                // Flutter로 전송
                                mainHandler.post {
                                    eventSink?.success(mapOf(
                                        "type" to "snapshot",
                                        "image" to snapshotBytes
                                    ))
                                    Log.d(TAG, "✅ 스냅샷 전송 완료 (${snapshotBytes.size} bytes)")
                                }
                                isSnapshotRequested = false // 요청 초기화
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "스냅샷 캡쳐 실패: ${e.message}")
                            isSnapshotRequested = false 
                        }
                    }
                    
                    // FPS 업데이트
                    updateFps()
                    
                    // Flutter로 결과 전송
                    sendDetectionsToFlutter(detections, croppedBusBytes)
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
    
    private fun sendDetectionsToFlutter(detections: List<Map<String, Any>>, croppedImage: ByteArray? = null) {
        val sink = eventSink ?: return
        val data = mutableMapOf<String, Any>(
            "detections" to detections,
            "fps" to fps
        )
        if (croppedImage != null) {
            data["croppedImage"] = croppedImage
        }
        
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
    
    /**
     * ImageProxy(YUV) -> Bitmap 변환 (회전 적용)
     */
    /**
     * ImageProxy(YUV) -> Bitmap 변환 (회전 적용)
     * RowStride를 고려하여 안전하게 변환
     */
    private fun imageProxyToBitmap(image: ImageProxy): Bitmap? {
        try {
            val yBuffer = image.planes[0].buffer // Y
            val uBuffer = image.planes[1].buffer // U
            val vBuffer = image.planes[2].buffer // V

            val yRowStride = image.planes[0].rowStride
            val uRowStride = image.planes[1].rowStride
            val vRowStride = image.planes[2].rowStride
            val uPixelStride = image.planes[1].pixelStride
            val vPixelStride = image.planes[2].pixelStride

            val width = image.width
            val height = image.height

            // NV21 포맷 버퍼 생성 (Size: width * height * 3 / 2)
            val nv21 = ByteArray(width * height * 3 / 2)
            
            // 1. Y Plane Copy
            if (yRowStride == width) {
                // Stride가 width와 같으면 한 번에 복사
                yBuffer.get(nv21, 0, width * height)
            } else {
                // Stride가 다르면 행 단위 복사
                for (row in 0 until height) {
                    yBuffer.position(row * yRowStride)
                    yBuffer.get(nv21, row * width, width)
                }
            }
            
            // 2. UV Plane Copy (NV21: V, U 순서 인터리빙)
            // U, V Plane에서 width/2, height/2 만큼 샘플링
            val uvHeight = height / 2
            val uvWidth = width / 2
            val startPos = width * height
            
            for (row in 0 until uvHeight) {
                for (col in 0 until uvWidth) {
                    val uIndex = row * uRowStride + col * uPixelStride
                    val vIndex = row * vRowStride + col * vPixelStride
                    
                    // NV21은 V가 먼저, 그 다음 U
                    val vValue = vBuffer.get(vIndex)
                    val uValue = uBuffer.get(uIndex)
                    
                    val outIndex = startPos + row * width + col * 2
                    if (outIndex + 1 < nv21.size) {
                        nv21[outIndex] = vValue
                        nv21[outIndex + 1] = uValue
                    }
                }
            }

            val yuvImage = YuvImage(nv21, ImageFormat.NV21, width, height, null)
            val out = ByteArrayOutputStream()
            yuvImage.compressToJpeg(Rect(0, 0, width, height), 90, out)
            val imageBytes = out.toByteArray()
            
            // Bitmap 로드
            val bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
            if (bitmap == null) return null

            // 회전 적용
            val rotationDegrees = image.imageInfo.rotationDegrees
            return if (rotationDegrees != 0) {
                val matrix = Matrix()
                matrix.postRotate(rotationDegrees.toFloat())
                Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
            } else {
                bitmap
            }
        } catch (e: Exception) {
            Log.e(TAG, "Bitmap 변환 실패: ${e.message}")
            return null
        }
    }

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
