package com.ctrlcv.sidae_app.yolo

import android.content.Context
import android.media.Image
import android.util.Log
import org.tensorflow.lite.Interpreter
import org.tensorflow.lite.gpu.GpuDelegate
import org.tensorflow.lite.support.image.ImageProcessor
import org.tensorflow.lite.support.image.ops.ResizeOp
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel
import kotlin.math.max
import kotlin.math.min

/**
 * YOLO 객체 감지 프로세서
 * 
 * TFLite 모델을 사용하여 객체 감지를 수행합니다.
 * - 모델 초기화 (GPU/NNAPI/CPU 자동 선택)
 * - 이미지 전처리 (YUV→RGB, Letterbox 리사이즈)
 * - 모델 추론
 * - 후처리 (NMS, 좌표 변환)
 */
class YoloProcessor(private val context: Context) {
    
    companion object {
        private const val TAG = "YoloProcessor"
        private const val TARGET_SIZE = 640
    }
    
    private val interpreterLock = Object()
    private var interpreter: Interpreter? = null
    private var gpuDelegate: GpuDelegate? = null
    private var labels: List<String> = emptyList()
    private var modelFileInputStream: FileInputStream? = null
    
    // 성능 최적화: 버퍼 재사용
    private var inputBuffer: ByteBuffer? = null
    private var outputBuffer: ByteBuffer? = null
    
    // ImageProcessor (리사이징 최적화)
    private var imageProcessor: ImageProcessor? = null
    
    // 전처리 파라미터 (후처리에서 사용)
    @Volatile var letterboxScale = 1.0f
        private set
    @Volatile var letterboxPadX = 0f
        private set
    @Volatile var letterboxPadY = 0f
        private set
    
    /**
     * 모델 초기화 결과
     */
    data class InitResult(
        val success: Boolean,
        val engineType: String,
        val errorMessage: String? = null
    )
    
    /**
     * YOLO 모델 초기화
     * 
     * @param modelBytes 모델 바이트 배열
     * @param labelsText 라벨 텍스트 (줄바꿈으로 구분)
     * @param modelPath 모델 경로 (INT8 감지용)
     * @return 초기화 결과
     */
    fun initialize(modelBytes: ByteArray, labelsText: String, modelPath: String): InitResult {
        return try {
            val modelBuffer = loadModelFromBytes(modelBytes)
            
            labels = labelsText.split("\n").filter { it.isNotBlank() }
            Log.d(TAG, "라벨 로드 완료: ${labels.size}개")
            
            // 기존 리소스 해제
            synchronized(interpreterLock) {
                gpuDelegate?.close()
                gpuDelegate = null
                interpreter?.close()
                interpreter = null
            }
            
            val isInt8Model = modelPath.contains("int8", ignoreCase = true)
            var initSuccess = false
            var engineType = "UNKNOWN"
            
            if (isInt8Model) {
                // INT8 모델은 CPU만 사용
                Log.d(TAG, "INT8 모델 감지: CPU만 사용")
                
                try {
                    val cpuOptions = Interpreter.Options().apply {
                        setNumThreads(4)
                        try {
                            setUseXNNPACK(true)
                            Log.d(TAG, "✅ XNNPACK 활성화")
                        } catch (e: Exception) {
                            Log.w(TAG, "⚠️ XNNPACK 활성화 실패: ${e.message}")
                        }
                    }
                    interpreter = Interpreter(modelBuffer, cpuOptions)
                    initSuccess = true
                    engineType = "CPU"
                    Log.d(TAG, "✅ CPU로 모델 로드 성공 (INT8)")
                } catch (e: Exception) {
                    Log.e(TAG, "CPU 모델 로드 실패: ${e.message}")
                    return InitResult(false, "UNKNOWN", "모델 로드 실패: ${e.message}")
                }
            } else {
                // FP16/FP32 모델: GPU → NNAPI → CPU 순서
                Log.d(TAG, "FP16/FP32 모델 감지: GPU → NNAPI → CPU 순서")
                
                // 1. GPU Delegate 시도
                if (!initSuccess) {
                    try {
                        Log.d(TAG, "GPU Delegate 생성 시도...")
                        val newGpuDelegate = GpuDelegate()
                        val gpuOptions = Interpreter.Options().apply {
                            addDelegate(newGpuDelegate)
                        }
                        interpreter = Interpreter(modelBuffer, gpuOptions)
                        gpuDelegate = newGpuDelegate
                        initSuccess = true
                        engineType = "GPU"
                        Log.d(TAG, "✅ GPU Delegate로 모델 로드 성공")
                    } catch (e: Exception) {
                        Log.w(TAG, "GPU Delegate 실패: ${e.message}")
                        gpuDelegate?.close()
                        gpuDelegate = null
                    }
                }
                
                // 2. NNAPI 시도
                if (!initSuccess) {
                    try {
                        Log.d(TAG, "NNAPI 초기화 시도...")
                        val nnapiOptions = Interpreter.Options().apply {
                            setUseNNAPI(true)
                        }
                        interpreter = Interpreter(modelBuffer, nnapiOptions)
                        initSuccess = true
                        engineType = "NNAPI"
                        Log.d(TAG, "✅ NNAPI로 모델 로드 성공")
                    } catch (e: Exception) {
                        Log.w(TAG, "NNAPI 실패: ${e.message}")
                    }
                }
                
                // 3. CPU 폴백
                if (!initSuccess) {
                    try {
                        val cpuOptions = Interpreter.Options().apply {
                            setNumThreads(4)
                            try {
                                setUseXNNPACK(true)
                                Log.d(TAG, "✅ XNNPACK 활성화")
                            } catch (e: Exception) {
                                Log.w(TAG, "⚠️ XNNPACK 활성화 실패: ${e.message}")
                            }
                        }
                        interpreter = Interpreter(modelBuffer, cpuOptions)
                        initSuccess = true
                        engineType = "CPU"
                        Log.d(TAG, "✅ CPU로 모델 로드 성공")
                    } catch (e: Exception) {
                        Log.e(TAG, "CPU 모델 로드 실패: ${e.message}")
                        return InitResult(false, "UNKNOWN", "모델 로드 실패: ${e.message}")
                    }
                }
            }
            
            // ImageProcessor 초기화
            try {
                imageProcessor = ImageProcessor.Builder()
                    .add(ResizeOp(TARGET_SIZE, TARGET_SIZE, ResizeOp.ResizeMethod.BILINEAR))
                    .build()
                Log.d(TAG, "✅ ImageProcessor 초기화 완료")
            } catch (e: Exception) {
                Log.w(TAG, "⚠️ ImageProcessor 초기화 실패: ${e.message}")
                imageProcessor = null
            }
            
            // 버퍼 초기화
            initializeBuffers()
            
            InitResult(true, engineType)
        } catch (e: Exception) {
            Log.e(TAG, "YOLO 초기화 실패", e)
            InitResult(false, "UNKNOWN", e.message)
        }
    }
    
    private fun initializeBuffers() {
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
    }
    
    /**
     * 추론 실행
     * 
     * @param image YUV_420_888 형식의 이미지
     * @param width 이미지 너비
     * @param height 이미지 높이
     * @return 감지 결과 리스트
     */
    fun runInference(image: Image, width: Int, height: Int): List<Map<String, Any>> {
        synchronized(interpreterLock) {
            val currentInterpreter = this.interpreter ?: return emptyList()
            
            try {
                // 1. 전처리
                val inputTensor = preprocessImage(image, width, height, TARGET_SIZE)
                
                // 2. 추론
                val inputShape: IntArray
                val outputShape: IntArray
                try {
                    inputShape = currentInterpreter.getInputTensor(0).shape()
                    outputShape = currentInterpreter.getOutputTensor(0).shape()
                } catch (e: Exception) {
                    Log.w(TAG, "⚠️ Tensor 접근 실패: ${e.message}")
                    return emptyList()
                }
                
                val inputBuf = inputBuffer
                val outputBuf = outputBuffer
                
                if (inputBuf == null || outputBuf == null) {
                    Log.w(TAG, "⚠️ 버퍼가 초기화되지 않음")
                    return emptyList()
                }
                
                inputBuf.clear()
                inputBuf.asFloatBuffer().put(inputTensor)
                outputBuf.clear()
                
                currentInterpreter.run(inputBuf, outputBuf)
                
                // 3. 후처리
                return postprocessOutput(outputBuf, outputShape)
            } catch (e: Exception) {
                Log.e(TAG, "❌ 추론 실패: ${e.message}", e)
                return emptyList()
            }
        }
    }
    
    /**
     * 이미지 전처리
     * YUV → RGB 변환, 90도 회전, Letterbox 리사이즈
     */
    private fun preprocessImage(image: Image, srcWidth: Int, srcHeight: Int, targetSize: Int): FloatArray {
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
        
        val yArray = ByteArray(yBuffer.remaining())
        val uArray = ByteArray(uBuffer.remaining())
        val vArray = ByteArray(vBuffer.remaining())
        
        val yPos = yBuffer.position()
        val uPos = uBuffer.position()
        val vPos = vBuffer.position()
        
        yBuffer.get(yArray)
        uBuffer.get(uArray)
        vBuffer.get(vArray)
        
        yBuffer.position(yPos)
        uBuffer.position(uPos)
        vBuffer.position(vPos)
        
        // 90도 회전 후 크기
        val rotatedWidth = srcHeight
        val rotatedHeight = srcWidth
        
        // Letterbox 스케일 계산
        val scale = targetSize.toDouble() / maxOf(rotatedHeight, rotatedWidth)
        val nw = Math.round(rotatedWidth * scale).toInt()
        val nh = Math.round(rotatedHeight * scale).toInt()
        val padX = (targetSize - nw) / 2
        val padY = (targetSize - nh) / 2
        
        // 전처리 파라미터 저장
        letterboxScale = scale.toFloat()
        letterboxPadX = padX.toFloat()
        letterboxPadY = padY.toFloat()
        
        val inv255 = 1.0f / 255.0f
        val padColor = 114f * inv255
        
        val output = FloatArray(targetSize * targetSize * 3)
        
        for (dstY in 0 until targetSize) {
            val baseIdx = dstY * targetSize * 3
            
            if (dstY < padY || dstY >= padY + nh) {
                java.util.Arrays.fill(output, baseIdx, baseIdx + targetSize * 3, padColor)
                continue
            }
            
            val rotYf = (dstY - padY) / scale
            val rotY0 = rotYf.toInt().coerceIn(0, rotatedHeight - 1)
            
            for (dstX in 0 until targetSize) {
                val outIdx = baseIdx + (dstX * 3)
                
                if (dstX < padX || dstX >= padX + nw) {
                    output[outIdx] = padColor
                    output[outIdx + 1] = padColor
                    output[outIdx + 2] = padColor
                    continue
                }
                
                val rotXf = (dstX - padX) / scale
                val rotX0 = rotXf.toInt().coerceIn(0, rotatedWidth - 1)
                
                // 90도 회전 역변환
                val srcX = rotY0
                val srcY = rotatedWidth - 1 - rotX0
                
                val yIdx = srcY * yRowStride + srcX * yPixelStride
                val uvX = srcX / 2
                val uvY = srcY / 2
                val uIdx = uvY * uRowStride + uvX * uPixelStride
                val vIdx = uvY * vRowStride + uvX * vPixelStride
                
                val yVal = (if (yIdx in yArray.indices) yArray[yIdx].toInt() and 0xFF else 0).toFloat()
                val uVal = (if (uIdx in uArray.indices) uArray[uIdx].toInt() and 0xFF else 128).toFloat()
                val vVal = (if (vIdx in vArray.indices) vArray[vIdx].toInt() and 0xFF else 128).toFloat()
                
                val uS = uVal - 128f
                val vS = vVal - 128f
                
                output[outIdx] = (yVal + 1.402f * vS).coerceIn(0f, 255f) * inv255
                output[outIdx + 1] = (yVal - 0.344136f * uS - 0.714136f * vS).coerceIn(0f, 255f) * inv255
                output[outIdx + 2] = (yVal + 1.772f * uS).coerceIn(0f, 255f) * inv255
            }
        }
        
        return output
    }
    
    /**
     * 출력 후처리 (모델 출력 형식에 따라 분기)
     */
    private fun postprocessOutput(outputBuffer: ByteBuffer, outputShape: IntArray): List<Map<String, Any>> {
        val confidenceThreshold = 0.5f
        val iouThreshold = 0.45f
        
        outputBuffer.rewind()
        val floatBuffer = outputBuffer.asFloatBuffer()
        floatBuffer.rewind()
        
        if (outputShape.size < 2) {
            Log.e(TAG, "출력 shape이 너무 짧습니다: ${outputShape.contentToString()}")
            return emptyList()
        }
        
        Log.d(TAG, "📊 모델 출력 shape: ${outputShape.contentToString()}, labels.size: ${labels.size}")
        
        val rows: Int
        val columns: Int
        
        if (outputShape.size == 3) {
            rows = outputShape[1]
            columns = outputShape[2]
            
            if (rows == 7 && columns >= 8400 && labels.size == 3) {
                return postprocessCustom3Class(floatBuffer, rows, columns, confidenceThreshold, iouThreshold)
            } else if (rows == 7 && columns >= 8400) {
                return postprocessYolo7Format(floatBuffer, rows, columns, confidenceThreshold, iouThreshold)
            } else if (rows >= 84 && columns >= 8400) {
                return postprocessYolo11n(floatBuffer, rows, columns, confidenceThreshold, iouThreshold)
            } else if (rows == 6 && columns <= 300) {
                return postprocessYolo26n(floatBuffer, rows, columns, confidenceThreshold)
            }
        } else if (outputShape.size == 2) {
            rows = outputShape[0]
            columns = outputShape[1]
            
            if (rows == 7 && columns >= 8400 && labels.size == 3) {
                return postprocessCustom3Class(floatBuffer, rows, columns, confidenceThreshold, iouThreshold)
            } else if (rows == 7 && columns >= 8400) {
                return postprocessYolo7Format(floatBuffer, rows, columns, confidenceThreshold, iouThreshold)
            } else if (rows >= 84 && columns >= 8400) {
                return postprocessYolo11n(floatBuffer, rows, columns, confidenceThreshold, iouThreshold)
            } else if (rows == 6 && columns <= 300) {
                return postprocessYolo26n(floatBuffer, rows, columns, confidenceThreshold)
            }
        }
        
        Log.e(TAG, "출력 shape을 처리할 수 없습니다: ${outputShape.contentToString()}")
        return emptyList()
    }
    
    // YOLO11n 후처리
    private fun postprocessYolo11n(
        floatBuffer: java.nio.FloatBuffer,
        rows: Int,
        columns: Int,
        confidenceThreshold: Float,
        iouThreshold: Float
    ): List<Map<String, Any>> {
        val totalFloats = rows * columns
        if (floatBuffer.remaining() < totalFloats) return emptyList()
        
        val outputArray = FloatArray(totalFloats)
        floatBuffer.get(outputArray)
        
        val tempDetections = mutableListOf<YoloBox>()
        
        for (c in 0 until columns) {
            var maxScore = 0f
            var classId = -1
            
            for (r in 4 until rows) {
                val score = outputArray[r * columns + c]
                if (score > maxScore) {
                    maxScore = score
                    classId = r - 4
                }
            }
            
            if (maxScore < confidenceThreshold) continue
            if (classId < 0 || classId >= labels.size) continue
            
            // 버스만 탐지 (COCO 데이터셋에서 bus는 classId 5)
            if (classId != 5) continue
            
            var cx = outputArray[0 * columns + c]
            var cy = outputArray[1 * columns + c]
            var w = outputArray[2 * columns + c]
            var h = outputArray[3 * columns + c]
            
            if (cx < 2.0f && w < 2.0f) {
                cx *= 640f
                cy *= 640f
                w *= 640f
                h *= 640f
            }
            
            val x1_640 = cx - w / 2f
            val y1_640 = cy - h / 2f
            
            val x1_orig = (x1_640 - letterboxPadX) / letterboxScale
            val y1_orig = (y1_640 - letterboxPadY) / letterboxScale
            val w_orig = w / letterboxScale
            val h_orig = h / letterboxScale
            
            val x2_orig = x1_orig + w_orig
            val y2_orig = y1_orig + h_orig
            
            if (x2_orig <= x1_orig || y2_orig <= y1_orig) continue
            
            tempDetections.add(YoloBox(x1_orig, y1_orig, x2_orig, y2_orig, maxScore, classId))
        }
        
        val nmsResults = applyNMS(tempDetections, iouThreshold)
        return nmsResults.map { box ->
            mapOf(
                "label" to labels[box.classId],
                "confidence" to box.score.toDouble(),
                "bbox" to listOf(box.x1.toDouble(), box.y1.toDouble(), box.x2.toDouble(), box.y2.toDouble())
            )
        }
    }
    
    // 커스텀 3클래스 모델 후처리
    private fun postprocessCustom3Class(
        floatBuffer: java.nio.FloatBuffer,
        rows: Int,
        columns: Int,
        confidenceThreshold: Float,
        iouThreshold: Float
    ): List<Map<String, Any>> {
        val totalFloats = rows * columns
        if (floatBuffer.remaining() < totalFloats) return emptyList()
        
        val outputArray = FloatArray(totalFloats)
        floatBuffer.get(outputArray)
        
        val tempDetections = mutableListOf<YoloBox>()
        val numClasses = 3
        
        for (c in 0 until columns) {
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
            
            var cx = outputArray[0 * columns + c]
            var cy = outputArray[1 * columns + c]
            var w = outputArray[2 * columns + c]
            var h = outputArray[3 * columns + c]
            
            if (cx < 2.0f && w < 2.0f) {
                cx *= 640f
                cy *= 640f
                w *= 640f
                h *= 640f
            }
            
            val x1_640 = cx - w / 2f
            val y1_640 = cy - h / 2f
            
            val x1_orig = (x1_640 - letterboxPadX) / letterboxScale
            val y1_orig = (y1_640 - letterboxPadY) / letterboxScale
            val w_orig = w / letterboxScale
            val h_orig = h / letterboxScale
            
            val x2_orig = x1_orig + w_orig
            val y2_orig = y1_orig + h_orig
            
            if (x2_orig <= x1_orig || y2_orig <= y1_orig) continue
            
            tempDetections.add(YoloBox(x1_orig, y1_orig, x2_orig, y2_orig, maxScore, classId))
        }
        
        Log.d(TAG, "🔍 NMS 전 탐지: ${tempDetections.size}개")
        
        val nmsResults = applyNMS(tempDetections, iouThreshold)
        
        Log.d(TAG, "✅ NMS 후 탐지: ${nmsResults.size}개")
        
        return nmsResults.map { box ->
            mapOf(
                "label" to labels[box.classId],
                "confidence" to box.score.toDouble(),
                "bbox" to listOf(box.x1.toDouble(), box.y1.toDouble(), box.x2.toDouble(), box.y2.toDouble())
            )
        }
    }
    
    // YOLO [1, 7, 8400] 형식 후처리
    private fun postprocessYolo7Format(
        floatBuffer: java.nio.FloatBuffer,
        rows: Int,
        columns: Int,
        confidenceThreshold: Float,
        iouThreshold: Float
    ): List<Map<String, Any>> {
        val totalFloats = rows * columns
        if (floatBuffer.remaining() < totalFloats) return emptyList()
        
        val outputArray = FloatArray(totalFloats)
        floatBuffer.get(outputArray)
        
        val tempDetections = mutableListOf<YoloBox>()
        
        for (c in 0 until columns) {
            val x = outputArray[0 * columns + c]
            val y = outputArray[1 * columns + c]
            val w = outputArray[2 * columns + c]
            val h = outputArray[3 * columns + c]
            val conf = outputArray[4 * columns + c]
            val classId = outputArray[5 * columns + c].toInt()
            
            if (conf < confidenceThreshold) continue
            if (classId < 0 || classId >= labels.size) continue
            
            val isPixelCoordinates = (x > 1.0f || y > 1.0f || w > 1.0f || h > 1.0f) &&
                    (x <= 640f && y <= 640f && w <= 640f && h <= 640f)
            
            val normalizedX: Float
            val normalizedY: Float
            val normalizedW: Float
            val normalizedH: Float
            
            if (isPixelCoordinates) {
                normalizedX = x / 640f
                normalizedY = y / 640f
                normalizedW = w / 640f
                normalizedH = h / 640f
            } else {
                normalizedX = x
                normalizedY = y
                normalizedW = w
                normalizedH = h
            }
            
            val x1: Float
            val y1: Float
            val x2: Float
            val y2: Float
            
            if (normalizedW <= 1.0f && normalizedH <= 1.0f) {
                x1 = (normalizedX - normalizedW / 2f).coerceIn(0f, 1f)
                y1 = (normalizedY - normalizedH / 2f).coerceIn(0f, 1f)
                x2 = (normalizedX + normalizedW / 2f).coerceIn(0f, 1f)
                y2 = (normalizedY + normalizedH / 2f).coerceIn(0f, 1f)
            } else {
                x1 = normalizedX.coerceIn(0f, 1f)
                y1 = normalizedY.coerceIn(0f, 1f)
                x2 = normalizedW.coerceIn(0f, 1f)
                y2 = normalizedH.coerceIn(0f, 1f)
            }
            
            if (x2 <= x1 || y2 <= y1) continue
            
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
        
        val nmsResults = applyNMS(tempDetections, iouThreshold)
        return nmsResults.map { box ->
            mapOf(
                "label" to labels[box.classId],
                "confidence" to box.score.toDouble(),
                "bbox" to listOf(box.x1.toDouble(), box.y1.toDouble(), box.x2.toDouble(), box.y2.toDouble())
            )
        }
    }
    
    // YOLO26n 후처리
    private fun postprocessYolo26n(
        floatBuffer: java.nio.FloatBuffer,
        numFeatures: Int,
        numDetections: Int,
        confidenceThreshold: Float
    ): List<Map<String, Any>> {
        val detections = mutableListOf<Map<String, Any>>()
        val totalFloats = numDetections * numFeatures
        
        if (floatBuffer.remaining() < totalFloats) return emptyList()
        
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
                "bbox" to listOf(x1_orig.toDouble(), y1_orig.toDouble(), x2_orig.toDouble(), y2_orig.toDouble())
            ))
        }
        
        return detections
    }
    
    // NMS (Non-Maximum Suppression)
    private fun applyNMS(boxes: List<YoloBox>, iouThres: Float): List<YoloBox> {
        val sortedBoxes = boxes.sortedByDescending { it.score }.toMutableList()
        val selectedBoxes = mutableListOf<YoloBox>()
        
        while (sortedBoxes.isNotEmpty()) {
            val first = sortedBoxes.removeAt(0)
            selectedBoxes.add(first)
            
            val iterator = sortedBoxes.iterator()
            while (iterator.hasNext()) {
                val next = iterator.next()
                if (first.classId == next.classId && calculateIoU(first, next) > iouThres) {
                    iterator.remove()
                }
            }
        }
        return selectedBoxes
    }
    
    // IoU 계산
    private fun calculateIoU(a: YoloBox, b: YoloBox): Float {
        val x1 = max(a.x1, b.x1)
        val y1 = max(a.y1, b.y1)
        val x2 = min(a.x2, b.x2)
        val y2 = min(a.y2, b.y2)
        
        val intersection = max(0f, x2 - x1) * max(0f, y2 - y1)
        val union = a.area + b.area - intersection
        
        return if (union > 0f) intersection / union else 0f
    }
    
    private fun loadModelFromBytes(modelBytes: ByteArray): MappedByteBuffer {
        val file = File(context.cacheDir, "model.tflite")
        
        FileOutputStream(file).use { outputStream ->
            outputStream.write(modelBytes)
        }
        
        modelFileInputStream?.close()
        
        val fis = FileInputStream(file)
        modelFileInputStream = fis
        val fileChannel = fis.channel
        return fileChannel.map(FileChannel.MapMode.READ_ONLY, 0, fileChannel.size())
    }
    
    /**
     * 리소스 해제
     */
    fun release() {
        synchronized(interpreterLock) {
            interpreter?.close()
            interpreter = null
            gpuDelegate?.close()
            gpuDelegate = null
        }
        modelFileInputStream?.close()
        modelFileInputStream = null
    }
    
    /**
     * 라벨 목록 반환
     */
    fun getLabels(): List<String> = labels
}
