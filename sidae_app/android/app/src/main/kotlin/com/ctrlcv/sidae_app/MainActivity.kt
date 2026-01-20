/// YOLO v26 s (small) FP16 온디바이스 객체 감지 테스트 화면
/// 
/// 네이티브 전체 파이프라인 방식:
/// - Android: CameraX + Kotlin에서 전처리+추론+후처리
/// - iOS: AVFoundation + Swift에서 전처리+추론+후처리
/// - Flutter: UI만 담당 (Method Channel + EventChannel)

package com.ctrlcv.sidae_app


import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ImageFormat
import android.graphics.Paint
import android.graphics.RectF
import android.media.Image
import android.util.Log
import android.view.View
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.concurrent.futures.await
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import com.google.common.util.concurrent.ListenableFuture
import io.flutter.embedding.android.FlutterActivity

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.plugin.common.StandardMessageCodec
import android.widget.FrameLayout
import kotlinx.coroutines.*
import kotlin.coroutines.CoroutineContext
import org.tensorflow.lite.Interpreter
import org.tensorflow.lite.gpu.GpuDelegate
import org.tensorflow.lite.support.image.ImageProcessor
import org.tensorflow.lite.support.image.TensorImage
import org.tensorflow.lite.support.image.ops.ResizeOp
import org.tensorflow.lite.support.image.ops.Rot90Op
import org.tensorflow.lite.DataType
import org.tensorflow.lite.support.tensorbuffer.TensorBuffer
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.min

// YOLO 박스 데이터 클래스
data class YoloBox(
    val x1: Float,
    val y1: Float,
    val x2: Float,
    val y2: Float,
    val score: Float,
    val classId: Int
) {
    val area: Float
        get() = (x2 - x1) * (y2 - y1)
}

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.ctrlcv.sidae_app/yolo_native"
    private val EVENT_CHANNEL = "com.ctrlcv.sidae_app/yolo_detections"
    private val TAG = "YOLONative"
    
    private var cameraProvider: ProcessCameraProvider? = null
    private var imageAnalysis: ImageAnalysis? = null
    private var preview: Preview? = null
    private var previewView: PreviewView? = null
    private var boundingBoxOverlayView: BoundingBoxOverlayView? = null
    private var camera: Camera? = null
    private var interpreter: Interpreter? = null
    private var gpuDelegate: GpuDelegate? = null
    private var labels: List<String> = emptyList()
    @Volatile private var isProcessing = false
    private var frameCount = 0
    private var lastFpsUpdate = System.currentTimeMillis()
    private var fps = 0.0
    @Volatile private var cameraWidth = 640
    @Volatile private var cameraHeight = 480
    
    private var eventSink: EventChannel.EventSink? = null
    private lateinit var cameraExecutor: ExecutorService
    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())
    
    // 성능 최적화: 버퍼 재사용 (매 프레임 할당 방지)
    private var inputBuffer: ByteBuffer? = null
    private var outputBuffer: ByteBuffer? = null
    
    // 성능 최적화: ImageProcessor 사용 (네이티브 레벨 YUV→RGB 변환)
    private var imageProcessor: org.tensorflow.lite.support.image.ImageProcessor? = null
    
    // 전처리 파라미터 (Python과 동일하게 후처리에서 사용)
    @Volatile private var letterboxScale = 1.0f
    @Volatile private var letterboxPadX = 0f
    @Volatile private var letterboxPadY = 0f
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        cameraExecutor = Executors.newSingleThreadExecutor()
        
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    val args = call.arguments as? Map<*, *>
                    val modelBytes = args?.get("modelBytes") as? ByteArray
                    val labelsText = args?.get("labelsText") as? String
                    val modelPath = args?.get("modelPath") as? String ?: ""
                    if (modelBytes != null && labelsText != null) {
                        initializeYolo(modelBytes, labelsText, modelPath, result)
                    } else {
                        result.error("INVALID_ARGUMENTS", "modelBytes and labelsText are required", null)
                    }
                }
                "startCamera" -> {
                    startCamera(result)
                }
                "stopCamera" -> {
                    stopCamera(result)
                }
                "getFps" -> {
                    result.success(fps)
                }
                else -> result.notImplemented()
            }
        }
        
        // EventChannel로 실시간 감지 결과 전송
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }
                
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
        
        // PlatformView 등록 (카메라 프리뷰용)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "cameraPreview",
            CameraPreviewFactory(this)
        )
    }
    
    private fun initializeYolo(modelBytes: ByteArray, labelsText: String, modelPath: String, result: MethodChannel.Result) {
        try {
            // Flutter에서 전달받은 모델과 라벨 사용
            val modelBuffer = loadModelFromBytes(modelBytes)
            
            labels = labelsText.split("\n").filter { it.isNotBlank() }
            Log.d(TAG, "라벨 로드 완료: ${labels.size}개")
            
            // 기존 리소스 해제
            gpuDelegate?.close()
            gpuDelegate = null
            interpreter?.close()
            interpreter = null
            
            // INT8 모델인지 확인 (best_int8.tflite)
            val isInt8Model = modelPath.contains("int8", ignoreCase = true)
            
            // TFLite Interpreter 초기화
            var initSuccess = false
            var engineType = "UNKNOWN"
            
            if (isInt8Model) {
                // INT8 모델은 CPU만 사용 (GPU Delegate와 NNAPI는 INT8을 지원하지 않음)
                Log.d(TAG, "INT8 모델 감지: CPU만 사용")
                
                try {
                    val cpuOptions = Interpreter.Options()
                    cpuOptions.setNumThreads(4)
                    // XNNPACK 활성화 (CPU 가속)
                    try {
                        cpuOptions.setUseXNNPACK(true)
                        Log.d(TAG, "✅ XNNPACK 활성화")
                    } catch (e: Exception) {
                        Log.w(TAG, "⚠️ XNNPACK 활성화 실패 (정상일 수 있음): ${e.message}")
                    }
                    interpreter = Interpreter(modelBuffer, cpuOptions)
                    initSuccess = true
                    engineType = "CPU"
                    Log.d(TAG, "✅ CPU로 모델 로드 성공")
                    Log.i(TAG, "🖥️ 추론 엔진: CPU 사용 중 (스레드: 4개, INT8 모델, XNNPACK 활성화)")
                } catch (e: Exception) {
                    Log.e(TAG, "CPU 모델 로드 실패: ${e.message}")
                    result.error("INIT_ERROR", "모델 로드 실패: ${e.message}", null)
                    return
                }
            } else {
                // FP16/FP32 모델은 GPU → NNAPI → CPU 순서
                Log.d(TAG, "FP16/FP32 모델 감지: GPU → NNAPI → CPU 순서")
                
                // 1. GPU Delegate 시도
                if (!initSuccess) {
                    try {
                        Log.d(TAG, "GPU Delegate 생성 시도...")
                        val newGpuDelegate = GpuDelegate()
                        val gpuOptions = Interpreter.Options()
                        gpuOptions.addDelegate(newGpuDelegate)
                        Log.d(TAG, "Interpreter 생성 시도 (GPU)...")
                        interpreter = Interpreter(modelBuffer, gpuOptions)
                        gpuDelegate = newGpuDelegate
                        initSuccess = true
                        engineType = "GPU"
                        Log.d(TAG, "✅ GPU Delegate로 모델 로드 성공")
                        Log.i(TAG, "🚀 추론 엔진: GPU Delegate 사용 중")
                    } catch (e: NoClassDefFoundError) {
                        Log.w(TAG, "GPU Delegate 초기화 실패 (NoClassDefFoundError), NNAPI 시도: ${e.message}")
                        Log.w(TAG, "GPU Delegate가 현재 환경에서 지원되지 않습니다 (에뮬레이터 또는 API 호환성 문제)")
                        gpuDelegate?.close()
                        gpuDelegate = null
                    } catch (e: ClassNotFoundException) {
                        Log.w(TAG, "GPU Delegate 클래스를 찾을 수 없음, NNAPI 시도: ${e.message}")
                        gpuDelegate?.close()
                        gpuDelegate = null
                    } catch (e: Exception) {
                        Log.w(TAG, "GPU Delegate 실패, NNAPI 시도: ${e.message}")
                        Log.w(TAG, "예외 타입: ${e.javaClass.name}")
                        gpuDelegate?.close()
                        gpuDelegate = null
                    }
                }
                
                // 2. NNAPI 시도
                if (!initSuccess) {
                    try {
                        Log.d(TAG, "NNAPI 초기화 시도...")
                        val nnapiOptions = Interpreter.Options()
                        nnapiOptions.setUseNNAPI(true)
                        interpreter = Interpreter(modelBuffer, nnapiOptions)
                        initSuccess = true
                        engineType = "NNAPI"
                        Log.d(TAG, "✅ NNAPI로 모델 로드 성공")
                        Log.i(TAG, "⚡ 추론 엔진: NNAPI 사용 중")
                    } catch (e: Exception) {
                        Log.w(TAG, "NNAPI 실패, CPU로 폴백: ${e.message}")
                        Log.w(TAG, "NNAPI 예외 타입: ${e.javaClass.name}")
                    }
                }
                
                // 3. CPU 폴백 (XNNPACK 활성화)
                if (!initSuccess) {
                    try {
                        val cpuOptions = Interpreter.Options()
                        cpuOptions.setNumThreads(4)
                        // XNNPACK 활성화 (CPU 가속)
                        try {
                            cpuOptions.setUseXNNPACK(true)
                            Log.d(TAG, "✅ XNNPACK 활성화")
                        } catch (e: Exception) {
                            Log.w(TAG, "⚠️ XNNPACK 활성화 실패 (정상일 수 있음): ${e.message}")
                        }
                        interpreter = Interpreter(modelBuffer, cpuOptions)
                        initSuccess = true
                        engineType = "CPU"
                        Log.d(TAG, "✅ CPU로 모델 로드 성공")
                        Log.i(TAG, "🖥️ 추론 엔진: CPU 사용 중 (스레드: 4개, XNNPACK 활성화)")
                    } catch (e2: Exception) {
                        Log.e(TAG, "CPU 모델 로드도 실패: ${e2.message}")
                        result.error("INIT_ERROR", "모델 로드 실패: ${e2.message}", null)
                        return
                    }
                }
            }
            
            // ImageProcessor 초기화 (YUV → RGB 변환 및 리사이징 최적화)
            try {
                // 640x640으로 리사이징하는 ImageProcessor 생성
                // 주의: ImageProcessor는 RGB 이미지를 처리하므로, YUV → RGB 변환은 별도로 처리해야 함
                // 하지만 리사이징과 정규화는 ImageProcessor로 최적화 가능
                imageProcessor = ImageProcessor.Builder()
                    .add(ResizeOp(640, 640, ResizeOp.ResizeMethod.BILINEAR))
                    .build()
                Log.d(TAG, "✅ ImageProcessor 초기화 완료 (640x640 리사이징)")
            } catch (e: Exception) {
                Log.w(TAG, "⚠️ ImageProcessor 초기화 실패, 기존 방식 사용: ${e.message}")
                imageProcessor = null
            }
            
            // 입력/출력 버퍼 초기화 (재사용을 위해 한 번만 할당)
            try {
                val inputShape = interpreter?.getInputTensor(0)?.shape()
                val outputShape = interpreter?.getOutputTensor(0)?.shape()
                
                if (inputShape != null) {
                    val inputSize = inputShape.fold(1) { acc, dim -> acc * dim }
                    inputBuffer = ByteBuffer.allocateDirect(4 * inputSize)
                        .order(ByteOrder.nativeOrder())
                    Log.d(TAG, "✅ 입력 버퍼 할당 완료: ${inputSize * 4} bytes")
                }
                
                if (outputShape != null) {
                    val outputSize = outputShape.fold(1) { acc, dim -> acc * dim }
                    outputBuffer = ByteBuffer.allocateDirect(4 * outputSize)
                        .order(ByteOrder.nativeOrder())
                    Log.d(TAG, "✅ 출력 버퍼 할당 완료: ${outputSize * 4} bytes")
                }
            } catch (e: Exception) {
                Log.w(TAG, "⚠️ 버퍼 초기화 실패: ${e.message}")
            }
            
            // GPU/CPU 사용 여부를 Flutter에 전달
            result.success(mapOf(
                "initialized" to true,
                "engineType" to engineType
            ))
        } catch (e: Exception) {
            Log.e(TAG, "YOLO 초기화 실패", e)
            result.error("INIT_ERROR", e.message, null)
        }
    }
    
    private fun startCamera(result: MethodChannel.Result) {
        // GlobalScope 대신 MainScope 사용 (더 안전)
        val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
        scope.launch {
            try {
                val cameraProviderFuture: ListenableFuture<ProcessCameraProvider> = 
                    ProcessCameraProvider.getInstance(this@MainActivity)
                cameraProvider = cameraProviderFuture.await()
                
                // 카메라의 최대 해상도를 사용하도록 요청 (실제 해상도는 카메라가 결정)
                val imageAnalysis = ImageAnalysis.Builder()
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888)
                    .setTargetResolution(android.util.Size(1920, 1080))  // Full HD 요청
                    .build()
                
                imageAnalysis.setAnalyzer(cameraExecutor) { imageProxy ->
                    processImage(imageProxy)
                }
                
                // Preview UseCase 생성 (ImageAnalysis와 동일한 해상도 요청)
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
                    Log.d(TAG, "✅ 카메라 시작 완료 (Preview + ImageAnalysis)")
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
    
    private fun stopCamera(result: MethodChannel.Result) {
        try {
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
    
    private fun processImage(imageProxy: ImageProxy) {
        val currentInterpreter = interpreter
        if (isProcessing || currentInterpreter == null) {
            imageProxy.close()
            return
        }
        
        isProcessing = true
        
        try {
            val image = imageProxy.image
            if (image != null && image.format == ImageFormat.YUV_420_888) {
                // 실제 카메라 해상도 저장
                val currentWidth = imageProxy.width
                val currentHeight = imageProxy.height
                if (cameraWidth != currentWidth || cameraHeight != currentHeight) {
                    cameraWidth = currentWidth
                    cameraHeight = currentHeight
                    Log.d(TAG, "📐 카메라 해상도 업데이트: ${cameraWidth}x${cameraHeight}")
                    // 오버레이 뷰에 해상도 업데이트
                    mainHandler.post {
                        boundingBoxOverlayView?.setCameraSize(cameraWidth, cameraHeight)
                    }
                }
                
                // YUV 프레임 처리 (예외 처리 강화)
                try {
                    val detections = runInference(image, imageProxy.width, imageProxy.height)
                    
                    // FPS 업데이트
                    frameCount++
                    val now = System.currentTimeMillis()
                    if (now - lastFpsUpdate >= 1000) {
                        fps = frameCount / ((now - lastFpsUpdate) / 1000.0)
                        frameCount = 0
                        lastFpsUpdate = now
                        Log.d(TAG, "📊 FPS: ${String.format("%.1f", fps)}")
                    }
                    
                    // Flutter로 결과 전송
                    sendDetectionsToFlutter(detections)
                } catch (e: OutOfMemoryError) {
                    Log.e(TAG, "메모리 부족: ${e.message}")
                    System.gc() // 가비지 컬렉션 시도
                } catch (e: IllegalStateException) {
                    Log.e(TAG, "상태 오류 (이미지가 이미 닫힘): ${e.message}")
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
    
    private fun runInference(image: Image, width: Int, height: Int): List<Map<String, Any>> {
        val currentInterpreter = this.interpreter ?: return emptyList()
        
        // 1. 전처리: YUV → RGB → Letterbox → 텐서
        val inputTensor = preprocessImage(image, width, height, 640)
        
        // 2. 추론
        val inputShape = currentInterpreter.getInputTensor(0).shape()
        val outputShape = currentInterpreter.getOutputTensor(0).shape()
        
        
        // 성능 최적화: 전역 버퍼 재사용 (매 프레임 할당 방지)
        val inputBuf = inputBuffer
        val outputBuf = outputBuffer
        
        if (inputBuf == null || outputBuf == null) {
            Log.w(TAG, "⚠️ 버퍼가 초기화되지 않음, 임시 버퍼 사용")
            // 임시 버퍼 사용 (초기화 실패 시)
            val tempInputBuffer = ByteBuffer.allocateDirect(4 * inputTensor.size)
                .order(ByteOrder.nativeOrder())
            tempInputBuffer.asFloatBuffer().put(inputTensor)
            
            if (outputShape.size < 2) {
                Log.e(TAG, "출력 텐서 shape이 올바르지 않습니다: ${outputShape.contentToString()}")
                return emptyList()
            }
            
            val outputSize = outputShape.fold(1) { acc, dim -> acc * dim }
            val tempOutputBuffer = ByteBuffer.allocateDirect(4 * outputSize)
                .order(ByteOrder.nativeOrder())
            
            currentInterpreter.run(tempInputBuffer, tempOutputBuffer)
            val detections = postprocessOutput(tempOutputBuffer, outputShape)
            return detections
        }
        
        // 전역 버퍼 재사용
        inputBuf.clear()
        inputBuf.asFloatBuffer().put(inputTensor)
        
        outputBuf.clear()
        
        // 추론 실행
        currentInterpreter.run(inputBuf, outputBuf)
        
        // 3. 후처리: NMS 출력 파싱
        val detections = postprocessOutput(outputBuf, outputShape)
        
        return detections
    }
    
    private fun preprocessImage(image: Image, srcWidth: Int, srcHeight: Int, targetSize: Int): FloatArray {
        // 성능 최적화: ImageProcessor 사용 시도
        // 주의: ImageProcessor는 RGB 이미지를 처리하므로, YUV → RGB 변환은 여전히 필요
        // 하지만 리사이징과 정규화는 ImageProcessor로 최적화 가능
        
        // 현재는 YUV → RGB 변환이 필수이므로, 기존 방식 유지하되 최적화
        // 향후 YUV → RGB 변환을 네이티브 레벨에서 처리하는 방법으로 개선 가능
        
        val yPlane = image.planes[0]
        val uPlane = image.planes[1]
        val vPlane = image.planes[2]
        
        val yBuffer = yPlane.buffer
        val uBuffer = uPlane.buffer
        val vBuffer = vPlane.buffer
        
        val yRowStride = yPlane.rowStride
        val uRowStride = uPlane.rowStride
        val vRowStride = vPlane.rowStride
        val yPixelStride = yPlane.pixelStride
        val uPixelStride = uPlane.pixelStride
        val vPixelStride = vPlane.pixelStride
        
        // 버퍼를 배열로 변환 (안전하게)
        val yArray = ByteArray(yBuffer.remaining())
        val uArray = ByteArray(uBuffer.remaining())
        val vArray = ByteArray(vBuffer.remaining())
        
        val yPos = yBuffer.position()
        val uPos = uBuffer.position()
        val vPos = vBuffer.position()
        
        yBuffer.get(yArray)
        uBuffer.get(uArray)
        vBuffer.get(vArray)
        
        // position 복원
        yBuffer.position(yPos)
        uBuffer.position(uPos)
        vBuffer.position(vPos)
        
        // 90도 회전 후 크기 (Python: h, w = img.shape[:2])
        val rotatedWidth = srcHeight  // Python의 w
        val rotatedHeight = srcWidth  // Python의 h
        
        // Letterbox 스케일 계산 (Python: scale = new_size / max(h, w))
        val scale = targetSize.toDouble() / maxOf(rotatedHeight, rotatedWidth)
        
        // Python: nw = int(round(w * scale)), nh = int(round(h * scale))
        val nw = Math.round(rotatedWidth * scale).toInt()
        val nh = Math.round(rotatedHeight * scale).toInt()
        
        // Python: pad_w = new_size - nw, pad_h = new_size - nh
        // Python: left = pad_w // 2, top = pad_h // 2
        val padX = (targetSize - nw) / 2
        val padY = (targetSize - nh) / 2
        
        // 전처리 파라미터 저장 (Python과 동일하게 후처리에서 사용)
        letterboxScale = scale.toFloat()
        letterboxPadX = padX.toFloat()
        letterboxPadY = padY.toFloat()
        
        // YUV→RGB 상수 (BT.601 표준, OpenCV와 동일)
        val inv255 = 1.0f / 255.0f
        val padColor = 114f * inv255  // Python: color=(114, 114, 114)
        
        // 출력 텐서: [1, targetSize, targetSize, 3]
        val output = FloatArray(targetSize * targetSize * 3)
        
        // Nearest Neighbor (최근접 이웃) 보간법으로 최적화 및 루프 최적화 (객체 생성 제거)
        for (dstY in 0 until targetSize) {
            val baseIdx = dstY * targetSize * 3
            
            // 상하 패딩 영역 처리
            if (dstY < padY || dstY >= padY + nh) {
                java.util.Arrays.fill(output, baseIdx, baseIdx + targetSize * 3, padColor)
                continue
            }
            
            val rotYf = (dstY - padY) / scale
            val rotY0 = rotYf.toInt().coerceIn(0, rotatedHeight - 1)
            
            for (dstX in 0 until targetSize) {
                val outIdx = baseIdx + (dstX * 3)
                
                // 좌우 패딩 영역 처리
                if (dstX < padX || dstX >= padX + nw) {
                    output[outIdx] = padColor
                    output[outIdx + 1] = padColor
                    output[outIdx + 2] = padColor
                    continue
                }
                
                // Nearest Neighbor 샘플링: 하나의 픽셀만 계산
                val rotXf = (dstX - padX) / scale
                val rotX0 = rotXf.toInt().coerceIn(0, rotatedWidth - 1)
                
                // 90도 회전 역변환: srcX = rotY, srcY = srcHeight - 1 - rotX
                val srcX = rotY0
                val srcY = rotatedWidth - 1 - rotX0
                
                // YUV 데이터 직접 접근 (getYuvPixel 인라인화)
                val yIdx = srcY * yRowStride + srcX * yPixelStride
                val uvX = srcX / 2
                val uvY = srcY / 2
                val uIdx = uvY * uRowStride + uvX * uPixelStride
                val vIdx = uvY * vRowStride + uvX * vPixelStride
                
                // 안전한 인덱스 체크 후 값 추출
                val yVal = (if (yIdx in yArray.indices) yArray[yIdx].toInt() and 0xFF else 0).toFloat()
                val uVal = (if (uIdx in uArray.indices) uArray[uIdx].toInt() and 0xFF else 128).toFloat()
                val vVal = (if (vIdx in vArray.indices) vArray[vIdx].toInt() and 0xFF else 128).toFloat()
                
                // YUV -> RGB 변환 인라인화 (Triple 생성 방지 및 직접 대입)
                val uS = uVal - 128f
                val vS = vVal - 128f
                
                output[outIdx] =     (yVal + 1.402f * vS).coerceIn(0f, 255f) * inv255
                output[outIdx + 1] = (yVal - 0.344136f * uS - 0.714136f * vS).coerceIn(0f, 255f) * inv255
                output[outIdx + 2] = (yVal + 1.772f * uS).coerceIn(0f, 255f) * inv255
            }
        }
        
        return output
    }
    
    private fun postprocessOutput(outputBuffer: ByteBuffer, outputShape: IntArray): List<Map<String, Any>> {
        val detections = mutableListOf<Map<String, Any>>()
        val confidenceThreshold = 0.25f
        val iouThreshold = 0.45f // NMS용 중복 제거 임계값
        
        outputBuffer.rewind()
        val floatBuffer = outputBuffer.asFloatBuffer()
        floatBuffer.rewind()
        
        // 출력 shape 확인
        if (outputShape.size < 2) {
            Log.e(TAG, "출력 shape이 너무 짧습니다: ${outputShape.contentToString()}")
            return emptyList()
        }
        
        // 디버그: 출력 shape 로깅
        Log.d(TAG, "📊 모델 출력 shape: ${outputShape.contentToString()}, labels.size: ${labels.size}")
        
        // YOLO11n 출력 구조: [1, 84, 8400] 또는 [1, 25200, 84] 등
        // shape[1] = rows (84 = 4 coordinates + 80 classes)
        // shape[2] = columns (8400 = boxes)
        val rows: Int
        val columns: Int
        
        if (outputShape.size == 3) {
            // [1, rows, columns] 형식
            rows = outputShape[1]
            columns = outputShape[2]
            
            // 커스텀 모델 (3클래스): [1, 7, 8400] 형식
            // rows = 4 (좌표) + 3 (클래스 점수) = 7
            if (rows == 7 && columns >= 8400 && labels.size == 3) {
                Log.d(TAG, "✅ 커스텀 모델 (3클래스) 후처리 사용")
                return postprocessCustom3Class(floatBuffer, rows, columns, confidenceThreshold, iouThreshold)
            } else if (rows == 7 && columns >= 8400) {
                return postprocessYolo7Format(floatBuffer, rows, columns, confidenceThreshold, iouThreshold)
            } else if (rows >= 84 && columns >= 8400) {
                return postprocessYolo11n(floatBuffer, rows, columns, confidenceThreshold, iouThreshold)
            } else if (rows == 6 && columns <= 300) {
                return postprocessYolo26n(floatBuffer, rows, columns, confidenceThreshold)
            }
        } else if (outputShape.size == 2) {
            // [rows, columns] 형식
            rows = outputShape[0]
            columns = outputShape[1]
            
            if (rows == 7 && columns >= 8400 && labels.size == 3) {
                Log.d(TAG, "✅ 커스텀 모델 (3클래스) 후처리 사용")
                return postprocessCustom3Class(floatBuffer, rows, columns, confidenceThreshold, iouThreshold)
            } else if (rows == 7 && columns >= 8400) {
                return postprocessYolo7Format(floatBuffer, rows, columns, confidenceThreshold, iouThreshold)
            } else if (rows >= 84 && columns >= 8400) {
                return postprocessYolo11n(floatBuffer, rows, columns, confidenceThreshold, iouThreshold)
            } else if (rows == 6 && columns <= 300) {
                return postprocessYolo26n(floatBuffer, rows, columns, confidenceThreshold)
            }
        } else {
            Log.e(TAG, "지원하지 않는 출력 shape: ${outputShape.contentToString()}")
            return emptyList()
        }
        
        Log.e(TAG, "출력 shape을 처리할 수 없습니다: ${outputShape.contentToString()}")
        return emptyList()
    }
    
    // YOLO11n 후처리 (전치된 데이터 구조)
    private fun postprocessYolo11n(
        floatBuffer: java.nio.FloatBuffer,
        rows: Int,
        columns: Int,
        confidenceThreshold: Float,
        iouThreshold: Float
    ): List<Map<String, Any>> {
        val totalFloats = rows * columns
        if (floatBuffer.remaining() < totalFloats) {
            Log.e(TAG, "버퍼 크기 부족: ${floatBuffer.remaining()} < $totalFloats")
            return emptyList()
        }
        
        val outputArray = FloatArray(totalFloats)
        floatBuffer.get(outputArray)
        
        val tempDetections = mutableListOf<YoloBox>()
        
        // 각 박스(column)에 대해 처리
        for (c in 0 until columns) {
            // 1. 각 박스에서 가장 높은 클래스 점수 찾기
            var maxScore = 0f
            var classId = -1
            
            // rows = 84: 인덱스 0~3은 좌표, 4~83은 클래스 점수
            for (r in 4 until rows) {
                val score = outputArray[r * columns + c] // 전치된 인덱스 접근
                if (score > maxScore) {
                    maxScore = score
                    classId = r - 4
                }
            }
            
            if (maxScore < confidenceThreshold) continue
            if (classId < 0 || classId >= labels.size) continue
            
            // 2. 좌표 추출 (YOLO 출력은 중심점 x, y, 너비 w, 높이 h)
            var cx = outputArray[0 * columns + c]
            var cy = outputArray[1 * columns + c]
            var w = outputArray[2 * columns + c]
            var h = outputArray[3 * columns + c]
            
            // Python과 동일: 정규화된 값(0~1)이면 640을 곱해줌
            if (cx < 2.0f && w < 2.0f) {
                cx *= 640f
                cy *= 640f
                w *= 640f
                h *= 640f
            }
            
            // Python과 동일: x1_640 = cx - w / 2, y1_640 = cy - h / 2
            val x1_640 = cx - w / 2f
            val y1_640 = cy - h / 2f
            
            // Python과 동일: NMS 전에 패딩 제거 및 스케일 역변환 수행
            // x = (x1_640 - pad_x) / scale
            val x1_orig = (x1_640 - letterboxPadX) / letterboxScale
            val y1_orig = (y1_640 - letterboxPadY) / letterboxScale
            val w_orig = w / letterboxScale
            val h_orig = h / letterboxScale
            
            val x2_orig = x1_orig + w_orig
            val y2_orig = y1_orig + h_orig
            
            if (x2_orig <= x1_orig || y2_orig <= y1_orig) continue
            
            // bbox를 원본 좌표로 저장 (Python과 동일)
            tempDetections.add(YoloBox(x1_orig, y1_orig, x2_orig, y2_orig, maxScore, classId))
        }
        
        // 3. NMS (중복 박스 제거) 로직 실행
        val nmsResults = applyNMS(tempDetections, iouThreshold)
        
        val detections = mutableListOf<Map<String, Any>>()
        for (box in nmsResults) {
            detections.add(mapOf(
                "label" to labels[box.classId],
                "confidence" to box.score.toDouble(),
                "bbox" to listOf(
                    box.x1.toDouble(),
                    box.y1.toDouble(),
                    box.x2.toDouble(),
                    box.y2.toDouble()
                )
            ))
        }
        
        return detections
    }
    
    // 커스텀 모델 (3클래스: Zebra_Cross, R_Signal, G_Signal) 후처리
    // 출력 형식: [1, 7, 8400]
    // row 0~3: x, y, w, h (좌표)
    // row 4~6: 각 클래스 점수 (Zebra_Cross, R_Signal, G_Signal)
    private fun postprocessCustom3Class(
        floatBuffer: java.nio.FloatBuffer,
        rows: Int, // 7
        columns: Int, // 8400
        confidenceThreshold: Float,
        iouThreshold: Float
    ): List<Map<String, Any>> {
        val totalFloats = rows * columns
        if (floatBuffer.remaining() < totalFloats) {
            Log.e(TAG, "버퍼 크기 부족: ${floatBuffer.remaining()} < $totalFloats")
            return emptyList()
        }
        
        val outputArray = FloatArray(totalFloats)
        floatBuffer.get(outputArray)
        
        val tempDetections = mutableListOf<YoloBox>()
        val numClasses = 3 // Zebra_Cross, R_Signal, G_Signal
        
        // 각 박스(column)에 대해 처리
        for (c in 0 until columns) {
            // 1. 각 박스에서 가장 높은 클래스 점수 찾기
            // row 4 = Zebra_Cross, row 5 = R_Signal, row 6 = G_Signal
            var maxScore = 0f
            var classId = -1
            
            for (r in 4 until 4 + numClasses) {
                val score = outputArray[r * columns + c]
                if (score > maxScore) {
                    maxScore = score
                    classId = r - 4
                }
            }
            
            if (maxScore < confidenceThreshold) continue
            if (classId < 0 || classId >= labels.size) continue
            
            // 2. 좌표 추출 (YOLO 출력은 중심점 x, y, 너비 w, 높이 h)
            var cx = outputArray[0 * columns + c]
            var cy = outputArray[1 * columns + c]
            var w = outputArray[2 * columns + c]
            var h = outputArray[3 * columns + c]
            
            // 정규화된 값(0~1)이면 640을 곱해줌
            if (cx < 2.0f && w < 2.0f) {
                cx *= 640f
                cy *= 640f
                w *= 640f
                h *= 640f
            }
            
            // x1_640 = cx - w / 2, y1_640 = cy - h / 2
            val x1_640 = cx - w / 2f
            val y1_640 = cy - h / 2f
            
            // 패딩 제거 및 스케일 역변환
            val x1_orig = (x1_640 - letterboxPadX) / letterboxScale
            val y1_orig = (y1_640 - letterboxPadY) / letterboxScale
            val w_orig = w / letterboxScale
            val h_orig = h / letterboxScale
            
            val x2_orig = x1_orig + w_orig
            val y2_orig = y1_orig + h_orig
            
            if (x2_orig <= x1_orig || y2_orig <= y1_orig) continue
            
            tempDetections.add(YoloBox(x1_orig, y1_orig, x2_orig, y2_orig, maxScore, classId))
        }
        
        Log.d(TAG, "🔍 NMS 전 탐지: ${tempDetections.size}개 (Zebra_Cross: ${tempDetections.count { it.classId == 0 }}, R_Signal: ${tempDetections.count { it.classId == 1 }}, G_Signal: ${tempDetections.count { it.classId == 2 }})")
        
        // 3. NMS (중복 박스 제거)
        val nmsResults = applyNMS(tempDetections, iouThreshold)
        
        Log.d(TAG, "✅ NMS 후 탐지: ${nmsResults.size}개")
        
        val detections = mutableListOf<Map<String, Any>>()
        for (box in nmsResults) {
            detections.add(mapOf(
                "label" to labels[box.classId],
                "confidence" to box.score.toDouble(),
                "bbox" to listOf(
                    box.x1.toDouble(),
                    box.y1.toDouble(),
                    box.x2.toDouble(),
                    box.y2.toDouble()
                )
            ))
        }
        
        return detections
    }
    
    // YOLO [1, 7, 8400] 형식 후처리
    // 형식: [x, y, w, h, conf, class_id, 추가필드]
    private fun postprocessYolo7Format(
        floatBuffer: java.nio.FloatBuffer,
        rows: Int, // 7
        columns: Int, // 8400
        confidenceThreshold: Float,
        iouThreshold: Float
    ): List<Map<String, Any>> {
        val totalFloats = rows * columns
        if (floatBuffer.remaining() < totalFloats) {
            Log.e(TAG, "버퍼 크기 부족: ${floatBuffer.remaining()} < $totalFloats")
            return emptyList()
        }
        
        val outputArray = FloatArray(totalFloats)
        floatBuffer.get(outputArray)
        
        val tempDetections = mutableListOf<YoloBox>()
        
        // 각 박스(column)에 대해 처리
        for (c in 0 until columns) {
            // 인덱스 접근: outputArray[row * columns + column]
            // row 0: x (또는 x1)
            // row 1: y (또는 y1)
            // row 2: w (또는 x2)
            // row 3: h (또는 y2)
            // row 4: confidence
            // row 5: class_id
            // row 6: 추가 필드 (무시)
            
            val x = outputArray[0 * columns + c]
            val y = outputArray[1 * columns + c]
            val w = outputArray[2 * columns + c]
            val h = outputArray[3 * columns + c]
            val conf = outputArray[4 * columns + c]
            val classId = outputArray[5 * columns + c].toInt()
            
            if (conf < confidenceThreshold) continue
            if (classId < 0 || classId >= labels.size) continue
            
            // 좌표 형식 확인: 픽셀 좌표(0~640)인지 정규화된 좌표(0.0~1.0)인지
            // 모델 입력 크기가 640x640이므로, 픽셀 좌표 범위는 0~640
            val isPixelCoordinates = (x > 1.0f || y > 1.0f || w > 1.0f || h > 1.0f) && 
                                     (x <= 640f && y <= 640f && w <= 640f && h <= 640f)
            
            val normalizedX: Float
            val normalizedY: Float
            val normalizedW: Float
            val normalizedH: Float
            
            if (isPixelCoordinates) {
                // 픽셀 좌표를 정규화 (640으로 나누기)
                normalizedX = x / 640f
                normalizedY = y / 640f
                normalizedW = w / 640f
                normalizedH = h / 640f
            } else {
                // 이미 정규화된 좌표
                normalizedX = x
                normalizedY = y
                normalizedW = w
                normalizedH = h
            }
            
            // 좌표 형식 확인: cx,cy,w,h 형식인지 x1,y1,x2,y2 형식인지
            val x1: Float
            val y1: Float
            val x2: Float
            val y2: Float
            
            // w와 h가 1보다 작거나 같으면 cx,cy,w,h 형식으로 가정
            if (normalizedW <= 1.0f && normalizedH <= 1.0f) {
                // cx, cy, w, h 형식 (정규화된 좌표)
                x1 = (normalizedX - normalizedW / 2f).coerceIn(0f, 1f)
                y1 = (normalizedY - normalizedH / 2f).coerceIn(0f, 1f)
                x2 = (normalizedX + normalizedW / 2f).coerceIn(0f, 1f)
                y2 = (normalizedY + normalizedH / 2f).coerceIn(0f, 1f)
            } else {
                // x1, y1, x2, y2 형식 (이미 정규화됨)
                x1 = normalizedX.coerceIn(0f, 1f)
                y1 = normalizedY.coerceIn(0f, 1f)
                x2 = normalizedW.coerceIn(0f, 1f)
                y2 = normalizedH.coerceIn(0f, 1f)
            }
            
            if (x2 <= x1 || y2 <= y1) continue
            
            // Python과 동일: 정규화된 좌표를 640 기준 좌표로 변환 후 패딩 제거 및 스케일 역변환
            val x1_640 = x1 * 640f
            val y1_640 = y1 * 640f
            val x2_640 = x2 * 640f
            val y2_640 = y2 * 640f
            
            val x1_orig = (x1_640 - letterboxPadX) / letterboxScale
            val y1_orig = (y1_640 - letterboxPadY) / letterboxScale
            val x2_orig = (x2_640 - letterboxPadX) / letterboxScale
            val y2_orig = (y2_640 - letterboxPadY) / letterboxScale
            
            tempDetections.add(YoloBox(x1_orig, y1_orig, x2_orig, y2_orig, conf, classId))
        }
        
        // NMS (중복 박스 제거) 로직 실행
        val nmsResults = applyNMS(tempDetections, iouThreshold)
        
        val detections = mutableListOf<Map<String, Any>>()
        for (box in nmsResults) {
            detections.add(mapOf(
                "label" to labels[box.classId],
                "confidence" to box.score.toDouble(),
                "bbox" to listOf(
                    box.x1.toDouble(),
                    box.y1.toDouble(),
                    box.x2.toDouble(),
                    box.y2.toDouble()
                )
            ))
        }
        
        return detections
    }
    
    // YOLO26n 후처리 (기존 로직 유지)
    private fun postprocessYolo26n(
        floatBuffer: java.nio.FloatBuffer,
        numFeatures: Int,
        numDetections: Int,
        confidenceThreshold: Float
    ): List<Map<String, Any>> {
        val detections = mutableListOf<Map<String, Any>>()
        val totalFloats = numDetections * numFeatures
        
        if (floatBuffer.remaining() < totalFloats) {
            Log.e(TAG, "버퍼 크기 부족: ${floatBuffer.remaining()} < $totalFloats")
            return emptyList()
        }
        
        val outputArray = FloatArray(totalFloats)
        floatBuffer.get(outputArray)
        
        for (i in 0 until numDetections) {
            val baseIdx = i * numFeatures
            val x1 = outputArray[baseIdx + 0]
            val y1 = outputArray[baseIdx + 1]
            val x2 = outputArray[baseIdx + 2]
            val y2 = outputArray[baseIdx + 3]
            val confidence = outputArray[baseIdx + 4]
            val classId = outputArray[baseIdx + 5].toInt()
            
            if (confidence < confidenceThreshold) continue
            if (x2 <= x1 || y2 <= y1) continue
            if (classId < 0 || classId >= labels.size) continue
            
            // Python과 동일: 정규화된 좌표를 640 기준 좌표로 변환 후 패딩 제거 및 스케일 역변환
            val x1_640 = x1.coerceIn(0.0f, 1.0f) * 640f
            val y1_640 = y1.coerceIn(0.0f, 1.0f) * 640f
            val x2_640 = x2.coerceIn(0.0f, 1.0f) * 640f
            val y2_640 = y2.coerceIn(0.0f, 1.0f) * 640f
            
            val x1_orig = (x1_640 - letterboxPadX) / letterboxScale
            val y1_orig = (y1_640 - letterboxPadY) / letterboxScale
            val x2_orig = (x2_640 - letterboxPadX) / letterboxScale
            val y2_orig = (y2_640 - letterboxPadY) / letterboxScale
            
            detections.add(mapOf(
                "label" to labels[classId],
                "confidence" to confidence.toDouble(),
                "bbox" to listOf(
                    x1_orig.toDouble(),
                    y1_orig.toDouble(),
                    x2_orig.toDouble(),
                    y2_orig.toDouble()
                )
            ))
        }
        
        return detections
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
    
    private var modelFileInputStream: FileInputStream? = null
    
    private fun loadModelFromBytes(modelBytes: ByteArray): MappedByteBuffer {
        val file = File(cacheDir, "model.tflite")
        
        // 파일에 모델 저장
        FileOutputStream(file).use { outputStream ->
            outputStream.write(modelBytes)
        }
        
        // 기존 스트림 닫기
        modelFileInputStream?.close()
        
        // MappedByteBuffer 생성 (스트림은 열어둬야 함)
        val fis = FileInputStream(file)
        modelFileInputStream = fis
        val fileChannel = fis.channel
        return fileChannel.map(FileChannel.MapMode.READ_ONLY, 0, fileChannel.size())
    }
    
    override fun onDestroy() {
        super.onDestroy()
        cameraProvider?.unbindAll()
        interpreter?.close()
        interpreter = null
        gpuDelegate?.close()
        gpuDelegate = null
        modelFileInputStream?.close()
        modelFileInputStream = null
        cameraExecutor.shutdown()
    }
    
    fun setPreviewView(view: PreviewView, overlayView: BoundingBoxOverlayView) {
        previewView = view
        boundingBoxOverlayView = overlayView
        Log.d(TAG, "✅ PreviewView 및 BoundingBoxOverlayView 설정 완료")
        // 이미 카메라가 시작되어 있다면 Preview 다시 바인딩
        preview?.let { prev ->
            prev.setSurfaceProvider(view.surfaceProvider)
        }
    }
    
    // NMS (Non-Maximum Suppression) 적용
    private fun applyNMS(boxes: List<YoloBox>, iouThres: Float): List<YoloBox> {
        val sortedBoxes = boxes.sortedByDescending { it.score }.toMutableList()
        val selectedBoxes = mutableListOf<YoloBox>()
        
        while (sortedBoxes.isNotEmpty()) {
            val first = sortedBoxes.removeAt(0)
            selectedBoxes.add(first)
            
            val iterator = sortedBoxes.iterator()
            while (iterator.hasNext()) {
                val next = iterator.next()
                // 같은 클래스만 NMS 적용
                if (first.classId == next.classId && calculateIoU(first, next) > iouThres) {
                    iterator.remove()
                }
            }
        }
        return selectedBoxes
    }
    
    // IoU (Intersection over Union) 계산
    private fun calculateIoU(a: YoloBox, b: YoloBox): Float {
        val x1 = max(a.x1, b.x1)
        val y1 = max(a.y1, b.y1)
        val x2 = min(a.x2, b.x2)
        val y2 = min(a.y2, b.y2)
        
        val intersection = max(0f, x2 - x1) * max(0f, y2 - y1)
        val areaA = a.area
        val areaB = b.area
        val union = areaA + areaB - intersection
        
        return if (union > 0f) intersection / union else 0f
    }
}

// 바운딩 박스 오버레이 뷰
class BoundingBoxOverlayView(context: Context) : View(context) {
    
    init {
        visibility = View.VISIBLE
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP) {
            elevation = 20f
        }
        isClickable = false
        isFocusable = false
        setWillNotDraw(false)
    }
    
    private val boxPaint = Paint().apply {
        color = Color.RED
        style = Paint.Style.STROKE
        strokeWidth = 4f
        isAntiAlias = true
    }
    
    private val textPaint = Paint().apply {
        color = Color.WHITE
        textSize = 32f
        isAntiAlias = true
        style = Paint.Style.FILL
    }
    
    private val textBgPaint = Paint().apply {
        color = Color.RED
        style = Paint.Style.FILL
        alpha = 200
    }
    
    private var detections: List<Map<String, Any>> = emptyList()
    @Volatile private var cameraWidth = 640f
    @Volatile private var cameraHeight = 480f
    
    fun setCameraSize(width: Int, height: Int) {
        cameraWidth = width.toFloat()
        cameraHeight = height.toFloat()
        postInvalidate()
    }
    
    fun updateDetections(newDetections: List<Map<String, Any>>) {
        detections = newDetections
        postInvalidate()
    }
    
    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        
        val viewWidth = width.toFloat()
        val viewHeight = height.toFloat()
        
        if (visibility != View.VISIBLE) return
        if (viewWidth <= 0 || viewHeight <= 0) return
        if (detections.isEmpty()) return
        
        // 바운딩 박스 좌표 변환 (Python 코드와 동일한 로직)
        // bbox는 이미 원본 좌표 (postprocessYolo11n에서 패딩 제거 및 스케일 역변환 완료)
        
        // 90도 회전 후 크기
        val rotatedWidth = cameraHeight.toFloat()
        val rotatedHeight = cameraWidth.toFloat()
        
        // 화면 표시 크기 계산 (PreviewView FIT_CENTER와 동일)
        val displayScaleX = viewWidth / rotatedWidth
        val displayScaleY = viewHeight / rotatedHeight
        val displayScale = minOf(displayScaleX, displayScaleY)
        
        val displayWidth = rotatedWidth * displayScale
        val displayHeight = rotatedHeight * displayScale
        val offsetX = (viewWidth - displayWidth) / 2f
        val offsetY = (viewHeight - displayHeight) / 2f
        
        for (detection in detections) {
            val bbox = detection["bbox"] as? List<*> ?: continue
            val label = detection["label"] as? String ?: "Unknown"
            val confidence = (detection["confidence"] as? Number)?.toFloat() ?: 0f
            
            if (bbox.size < 4) continue
            
            val x1_orig = (bbox[0] as Number).toFloat()
            val y1_orig = (bbox[1] as Number).toFloat()
            val x2_orig = (bbox[2] as Number).toFloat()
            val y2_orig = (bbox[3] as Number).toFloat()
            
            // 화면 좌표로 변환
            val x1 = x1_orig * displayScale + offsetX
            val y1 = y1_orig * displayScale + offsetY
            val x2 = x2_orig * displayScale + offsetX
            val y2 = y2_orig * displayScale + offsetY
            
            if (x1 >= x2 || y1 >= y2) continue
            
            // 바운딩 박스 그리기
            canvas.drawRect(x1, y1, x2, y2, boxPaint)
            
            // 라벨 텍스트 그리기
            val labelText = "$label ${(confidence * 100).toInt()}%"
            val textWidth = textPaint.measureText(labelText)
            val textHeight = textPaint.fontMetrics.let { it.descent - it.ascent }
            
            // 텍스트 배경 그리기
            val textBgRect = RectF(
                x1,
                y1 - textHeight - 8,
                x1 + textWidth + 16,
                y1
            )
            canvas.drawRect(textBgRect, textBgPaint)
            
            // 텍스트 그리기
            canvas.drawText(labelText, x1 + 8, y1 - 8, textPaint)
        }
    }
}

// PlatformView를 위한 Factory
class CameraPreviewFactory(private val activity: MainActivity) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        // PreviewView 생성 및 TextureView 모드 설정
        // COMPATIBLE 모드는 TextureView를 사용하여 Flutter 위젯과 자연스럽게 섞일 수 있음
        val previewView = PreviewView(context).apply {
            try {
                // COMPATIBLE 모드로 설정 (TextureView 사용)
                // 이렇게 하면 SurfaceView의 "구멍 뚫기" 문제를 해결하고
                // Flutter 위젯과 자연스럽게 섞이며 Z-order를 존중함
                implementationMode = PreviewView.ImplementationMode.COMPATIBLE
                Log.d("CameraPreviewFactory", "✅ PreviewView를 COMPATIBLE 모드로 설정 (TextureView 사용)")
                
                // 스케일 타입 설정: FIT_CENTER로 설정하여 contain 방식과 일치
                // FIT_CENTER는 이미지가 화면 안에 완전히 들어가고 중앙에 배치됨 (contain 방식)
                // 이렇게 하면 바운딩 박스 계산과 일치하여 정확한 위치에 표시됨
                scaleType = PreviewView.ScaleType.FIT_CENTER
                Log.d("CameraPreviewFactory", "✅ PreviewView scaleType: FIT_CENTER (contain 방식과 일치)")
            } catch (e: Exception) {
                Log.w("CameraPreviewFactory", "⚠️ PreviewView 설정 실패 (기본 모드 사용): ${e.message}")
                // 설정 실패 시 기본 모드로 동작 (SurfaceView 사용)
            }
        }
        
        previewView.layoutParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        )
        
        // PreviewView의 elevation을 낮게 설정 (0으로)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP) {
            previewView.elevation = 0f
        }
        
        Log.d("CameraPreviewFactory", "✅ PreviewView 생성 (elevation=${previewView.elevation})")
        
        // 바운딩 박스 오버레이 뷰 생성
        val overlayView = BoundingBoxOverlayView(context)
        val overlayParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        )
        overlayView.layoutParams = overlayParams
        overlayView.setBackgroundColor(Color.TRANSPARENT)
        // 터치 이벤트를 받을 수 있도록 설정 (하지만 투과)
        overlayView.isClickable = false
        overlayView.isFocusable = false
        // elevation 설정하여 z-order 보장 (API 21+)
        // PreviewView보다 훨씬 높은 elevation 설정
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP) {
            overlayView.elevation = 20f // PreviewView(0f)보다 높은 elevation
        }
        overlayView.visibility = View.VISIBLE
        
        // FrameLayout으로 감싸기
        val container = FrameLayout(context)
        
        // View 계층 구조 로그 추가
        Log.d("CameraPreviewFactory", "📐 View 계층 구조 생성 시작")
        Log.d("CameraPreviewFactory", "  - PreviewView: elevation=${previewView.elevation}")
        Log.d("CameraPreviewFactory", "  - BoundingBoxOverlayView: elevation=${overlayView.elevation}")
        
        container.addView(previewView)
        Log.d("CameraPreviewFactory", "  ✅ PreviewView 추가됨 (index=${container.indexOfChild(previewView)})")
        
        container.addView(overlayView) // 오버레이 뷰를 위에 추가
        Log.d("CameraPreviewFactory", "  ✅ BoundingBoxOverlayView 추가됨 (index=${container.indexOfChild(overlayView)})")
        
        // 오버레이 뷰를 맨 앞으로 가져오기
        overlayView.bringToFront()
        container.requestLayout()
        container.invalidate()
        
        // View 계층 구조 최종 확인
        Log.d("CameraPreviewFactory", "📐 View 계층 구조 최종 상태:")
        for (i in 0 until container.childCount) {
            val child = container.getChildAt(i)
            val elevation = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP) {
                child.elevation
            } else {
                0f
            }
            Log.d("CameraPreviewFactory", "  [$i] ${child.javaClass.simpleName}: elevation=$elevation, visibility=${child.visibility}")
        }
        
        Log.d("CameraPreviewFactory", "✅ PlatformView 생성 완료: PreviewView + BoundingBoxOverlayView")
        
        activity.setPreviewView(previewView, overlayView)
        return CameraPreviewView(container)
    }
}

// PlatformView 구현
class CameraPreviewView(private val container: FrameLayout) : PlatformView {
    override fun getView(): View = container
    
    override fun dispose() {
        // Container는 MainActivity에서 관리하므로 여기서는 아무것도 하지 않음
    }
}
