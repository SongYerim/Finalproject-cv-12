package com.ctrlcv.sidae_app.gps

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.os.Looper
import android.util.Log
import androidx.core.app.ActivityCompat
import com.google.android.gms.location.*
import com.ctrlcv.sidae_app.utils.GeoUtils

/**
 * 횡단보도 반대편 도달 추적 리스너
 */
interface ExitTrackerListener {
    /**
     * 위치 업데이트 콜백
     * 
     * @param distance 목표까지의 거리 (미터)
     * @param reached 목표 도달 여부
     * @param lat 현재 위도
     * @param lng 현재 경도
     */
    fun onLocationUpdate(distance: Double, reached: Boolean, lat: Double, lng: Double)
}

/**
 * 횡단보도 반대편 도달 감지를 위한 GPS 추적기
 * 
 * 사용자가 횡단보도를 건너 반대편에 도달했는지 감지합니다.
 */
class ExitTracker(private val context: Context) {
    
    companion object {
        private const val TAG = "ExitTracker"
        private const val EXIT_THRESHOLD = 15.0 // 15m 이내면 도달로 판정
        private const val UPDATE_INTERVAL_MS = 500L
    }
    
    private var fusedLocationClient: FusedLocationProviderClient? = null
    private var locationCallback: LocationCallback? = null
    private var exitLat: Double? = null
    private var exitLng: Double? = null
    private var listener: ExitTrackerListener? = null
    
    /**
     * 리스너 설정
     */
    fun setListener(listener: ExitTrackerListener) {
        this.listener = listener
    }
    
    private var exitThreshold = 15.0

    /**
     * GPS 추적 시작
     * 
     * @param lat 목표 위도 (횡단보도 반대편)
     * @param lng 목표 경도 (횡단보도 반대편)
     * @param threshold 도달 판정 거리 (미터)
     * @return 성공 여부
     */
    fun startTracking(lat: Double, lng: Double, threshold: Double = 15.0): Boolean {
        exitLat = lat
        exitLng = lng
        exitThreshold = threshold
        
        Log.d(TAG, "🚶 GPS 추적 시작: ($lat, $lng), 반경: ${threshold}m")
        
        // 위치 권한 확인
        if (ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED &&
            ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            Log.e(TAG, "❌ 위치 권한 없음")
            return false
        }
        
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(context)
        
        val locationRequest = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, UPDATE_INTERVAL_MS)
            .setMinUpdateIntervalMillis(UPDATE_INTERVAL_MS)
            .setMinUpdateDistanceMeters(0f)
            .build()
        
        locationCallback = object : LocationCallback() {
            override fun onLocationResult(locationResult: LocationResult) {
                val location = locationResult.lastLocation ?: return
                
                val targetLat = exitLat ?: return
                val targetLng = exitLng ?: return
                
                val distance = GeoUtils.calculateDistance(
                    location.latitude, location.longitude,
                    targetLat, targetLng
                )
                
                Log.d(TAG, "📍 GPS: (${location.latitude}, ${location.longitude}) → 거리: ${String.format("%.1f", distance)}m")
                
                val reached = distance <= exitThreshold
                
                listener?.onLocationUpdate(distance, reached, location.latitude, location.longitude)
                
                if (reached) {
                    Log.d(TAG, "✅ 횡단보도 반대편 도달! (거리: ${String.format("%.1f", distance)}m)")
                }
            }
        }
        
        fusedLocationClient?.requestLocationUpdates(locationRequest, locationCallback!!, Looper.getMainLooper())
        
        Log.d(TAG, "✅ GPS 추적 시작됨 (반경: ${threshold}m)")
        return true
    }
    
    /**
     * GPS 추적 중지
     */
    fun stopTracking() {
        try {
            locationCallback?.let { callback ->
                fusedLocationClient?.removeLocationUpdates(callback)
            }
            locationCallback = null
            fusedLocationClient = null
            exitLat = null
            exitLng = null
            Log.d(TAG, "✅ GPS 추적 중지됨")
        } catch (e: Exception) {
            Log.e(TAG, "❌ GPS 추적 중지 실패: ${e.message}")
        }
    }
    
    /**
     * 추적 중인지 확인
     */
    fun isTracking(): Boolean = locationCallback != null
    

    
    /**
     * 리소스 해제
     */
    fun release() {
        stopTracking()
        listener = null
    }
}