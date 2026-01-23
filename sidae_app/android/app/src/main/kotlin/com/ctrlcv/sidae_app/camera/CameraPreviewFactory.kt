package com.ctrlcv.sidae_app.camera

import android.content.Context
import android.graphics.Color
import android.util.Log
import android.view.View
import android.widget.FrameLayout
import androidx.camera.view.PreviewView
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * 카메라 프리뷰 뷰 제공을 위한 콜백 인터페이스
 */
interface CameraPreviewCallback {
    fun onPreviewViewCreated(previewView: PreviewView, overlayView: BoundingBoxOverlayView)
}

/**
 * Flutter PlatformView를 위한 카메라 프리뷰 팩토리
 * 
 * CameraX PreviewView와 BoundingBoxOverlayView를 포함하는 뷰를 생성합니다.
 */
class CameraPreviewFactory(
    private val callback: CameraPreviewCallback
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    
    companion object {
        private const val TAG = "CameraPreviewFactory"
    }
    
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        // PreviewView 생성 및 설정
        val previewView = PreviewView(context).apply {
            try {
                // COMPATIBLE 모드 (TextureView 사용)
                implementationMode = PreviewView.ImplementationMode.COMPATIBLE
                Log.d(TAG, "✅ PreviewView를 COMPATIBLE 모드로 설정")
                
                // FIT_CENTER 스케일 타입
                scaleType = PreviewView.ScaleType.FIT_CENTER
                Log.d(TAG, "✅ PreviewView scaleType: FIT_CENTER")
            } catch (e: Exception) {
                Log.w(TAG, "⚠️ PreviewView 설정 실패: ${e.message}")
            }
        }
        
        previewView.layoutParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        )
        
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP) {
            previewView.elevation = 0f
        }
        
        // 바운딩 박스 오버레이 뷰 생성
        val overlayView = BoundingBoxOverlayView(context).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
            setBackgroundColor(Color.TRANSPARENT)
            isClickable = false
            isFocusable = false
            visibility = View.VISIBLE
        }
        
        // FrameLayout 컨테이너 생성
        val container = FrameLayout(context)
        
        Log.d(TAG, "📐 View 계층 구조 생성")
        Log.d(TAG, "  - PreviewView elevation: ${previewView.elevation}")
        Log.d(TAG, "  - OverlayView elevation: ${overlayView.elevation}")
        
        container.addView(previewView)
        container.addView(overlayView)
        
        overlayView.bringToFront()
        container.requestLayout()
        container.invalidate()
        
        Log.d(TAG, "✅ PlatformView 생성 완료")
        
        // 콜백으로 뷰 전달
        callback.onPreviewViewCreated(previewView, overlayView)
        
        return CameraPreviewView(container)
    }
}

/**
 * PlatformView 구현
 */
class CameraPreviewView(private val container: FrameLayout) : PlatformView {
    override fun getView(): View = container
    
    override fun dispose() {
        // 리소스 해제는 MainActivity에서 관리
    }
}
