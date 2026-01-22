package com.ctrlcv.sidae_app.camera

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.view.View

/**
 * 바운딩 박스 오버레이 뷰
 * 
 * YOLO 객체 감지 결과를 카메라 프리뷰 위에 오버레이로 그립니다.
 * - 바운딩 박스 그리기
 * - 라벨 및 신뢰도 표시
 * - 원본 이미지 좌표를 화면 좌표로 변환
 */
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
    
    /**
     * 카메라 해상도 설정
     * 
     * @param width 카메라 너비
     * @param height 카메라 높이
     */
    fun setCameraSize(width: Int, height: Int) {
        cameraWidth = width.toFloat()
        cameraHeight = height.toFloat()
        postInvalidate()
    }
    
    /**
     * 감지 결과 업데이트
     * 
     * @param newDetections 새로운 감지 결과 리스트
     */
    fun updateDetections(newDetections: List<Map<String, Any>>) {
        detections = newDetections
        postInvalidate()
    }
    
    /**
     * 박스 색상 설정
     * 
     * @param color 색상 값
     */
    fun setBoxColor(color: Int) {
        boxPaint.color = color
        textBgPaint.color = color
        postInvalidate()
    }
    
    /**
     * 텍스트 크기 설정
     * 
     * @param size 텍스트 크기 (sp)
     */
    fun setTextSize(size: Float) {
        textPaint.textSize = size
        postInvalidate()
    }
    
    /**
     * 박스 선 두께 설정
     * 
     * @param width 선 두께 (px)
     */
    fun setStrokeWidth(width: Float) {
        boxPaint.strokeWidth = width
        postInvalidate()
    }
    
    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        
        val viewWidth = width.toFloat()
        val viewHeight = height.toFloat()
        
        if (visibility != View.VISIBLE) return
        if (viewWidth <= 0 || viewHeight <= 0) return
        if (detections.isEmpty()) return
        
        // 90도 회전 후 크기
        val rotatedWidth = cameraHeight
        val rotatedHeight = cameraWidth
        
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
            
            // 라벨에 따라 색상 변경
            updatePaintColors(label)
            
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
    
    /**
     * 라벨에 따라 색상 업데이트
     */
    private fun updatePaintColors(label: String) {
        val color = when {
            label.contains("R_Signal", ignoreCase = true) -> Color.RED
            label.contains("G_Signal", ignoreCase = true) -> Color.GREEN
            label.contains("Zebra", ignoreCase = true) -> Color.YELLOW
            else -> Color.RED
        }
        boxPaint.color = color
        textBgPaint.color = color
    }
    
    /**
     * 감지 결과 초기화
     */
    fun clearDetections() {
        detections = emptyList()
        postInvalidate()
    }
}
