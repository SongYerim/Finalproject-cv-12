package com.ctrlcv.sidae_app.navigation

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.location.Location
import android.os.Looper
import android.util.Log
import androidx.core.app.ActivityCompat
import com.google.android.gms.location.*
import com.ctrlcv.sidae_app.utils.GeoUtils

/**
 * 네비게이션 데이터 리스너
 */
interface NavigationListener {
    /**
     * 네비게이션 데이터 업데이트 콜백
     * 
     * @param deviceHeading 기기 방향 (0-360도)
     * @param routeBearing 목표 방향 (0-360도, -1이면 미설정)
     * @param travelingBearing 진행 방향 (0-360도, -1이면 미설정)
     * @param targetLat 목표 위도
     * @param targetLng 목표 경도
     */
    fun onNavigationUpdate(
        deviceHeading: Double,
        routeBearing: Double,
        travelingBearing: Double,
        targetLat: Double?,
        targetLng: Double?
    )
}

/**
 * 네비게이션 관리자
 * 
 * 센서(자기장)와 GPS를 통합하여 네비게이션 데이터를 제공합니다.
 * - 기기 방향 (나침반)
 * - 목표 방향
 * - 진행 방향
 */
class NavigationManager(private val context: Context) {
    
    companion object {
        private const val TAG = "NavigationManager"
        private const val UPDATE_INTERVAL_MS = 500L
        private const val MIN_DISTANCE_FOR_BEARING = 1.0 // 1m 이상 이동해야 진행 방향 계산
    }
    
    private var sensorManager: SensorManager? = null
    private var magnetometer: Sensor? = null
    private var sensorEventListener: SensorEventListener? = null
    private var fusedLocationClient: FusedLocationProviderClient? = null
    private var locationCallback: LocationCallback? = null
    
    // 방향 관련 변수
    @Volatile private var deviceHeading = 0.0
    @Volatile private var routeBearing = -1.0
    @Volatile private var travelingBearing = -1.0
    private val recentPositions = mutableListOf<Location>()
    
    // 목표 좌표
    private var targetLat: Double? = null
    private var targetLng: Double? = null
    
    private var listener: NavigationListener? = null
    
    /**
     * 리스너 설정
     */
    fun setListener(listener: NavigationListener) {
        this.listener = listener
    }
    
    /**
     * 네비게이션 시작
     * 
     * @return 성공 여부
     */
    fun start(): Boolean {
        Log.d(TAG, "🧭 네비게이션 시작")
        
        // 위치 권한 확인
        if (ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            Log.e(TAG, "❌ 위치 권한 없음")
            return false
        }
        
        // 1. 센서 초기화 (자기장 센서)
        initializeSensor()
        
        // 2. GPS 추적 시작
        initializeLocationTracking()
        
        Log.d(TAG, "✅ 네비게이션 시작됨")
        return true
    }
    
    private fun initializeSensor() {
        sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        magnetometer = sensorManager?.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)
        
        sensorEventListener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent?) {
                event?.let {
                    // 나침반 방향 계산
                    var heading = Math.atan2(it.values[1].toDouble(), it.values[0].toDouble())
                    heading = heading * (180 / Math.PI)
                    heading = 90 - heading
                    if (heading < 0) heading += 360
                    if (heading >= 360) heading -= 360
                    
                    deviceHeading = heading
                    sendNavigationUpdate()
                }
            }
            
            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
        }
        
        magnetometer?.let { sensor ->
            sensorManager?.registerListener(sensorEventListener, sensor, SensorManager.SENSOR_DELAY_GAME)
            Log.d(TAG, "✅ 자기장 센서 리스너 등록됨")
        }
    }
    
    private fun initializeLocationTracking() {
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(context)
        
        val locationRequest = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, UPDATE_INTERVAL_MS)
            .setMinUpdateIntervalMillis(UPDATE_INTERVAL_MS)
            .setMinUpdateDistanceMeters(0f)
            .build()
        
        locationCallback = object : LocationCallback() {
            override fun onLocationResult(locationResult: LocationResult) {
                val location = locationResult.lastLocation ?: return
                
                // 최근 위치 저장 (진행 방향 계산용)
                recentPositions.add(location)
                if (recentPositions.size > 2) {
                    recentPositions.removeAt(0)
                }
                
                // 진행 방향 계산
                calculateTravelingBearing()
                
                // 목표 방향 계산
                calculateRouteBearing(location)
                
                // 업데이트 전송
                sendNavigationUpdate()
            }
        }
        
        try {
            fusedLocationClient?.requestLocationUpdates(locationRequest, locationCallback!!, Looper.getMainLooper())
            Log.d(TAG, "✅ GPS 추적 시작됨")
        } catch (e: SecurityException) {
            Log.e(TAG, "❌ GPS 권한 오류: ${e.message}")
        }
    }
    
    /**
     * 네비게이션 중지
     */
    fun stop() {
        try {
            // 센서 리스너 해제
            sensorEventListener?.let { listener ->
                sensorManager?.unregisterListener(listener)
            }
            sensorEventListener = null
            sensorManager = null
            magnetometer = null
            
            // GPS 추적 중지
            locationCallback?.let { callback ->
                fusedLocationClient?.removeLocationUpdates(callback)
            }
            locationCallback = null
            fusedLocationClient = null
            
            // 변수 초기화
            recentPositions.clear()
            deviceHeading = 0.0
            routeBearing = -1.0
            travelingBearing = -1.0
            targetLat = null
            targetLng = null
            
            Log.d(TAG, "✅ 네비게이션 중지됨")
        } catch (e: Exception) {
            Log.e(TAG, "❌ 네비게이션 중지 실패: ${e.message}")
        }
    }
    
    /**
     * 목표 좌표 업데이트
     * 
     * @param lat 목표 위도
     * @param lng 목표 경도
     */
    fun updateTarget(lat: Double, lng: Double) {
        targetLat = lat
        targetLng = lng
        Log.d(TAG, "🎯 목표 좌표 업데이트: ($lat, $lng)")
    }
    
    /**
     * 진행 방향 계산 (GPS 기반)
     */
    private fun calculateTravelingBearing() {
        if (recentPositions.size < 2) return
        
        val prev = recentPositions[0]
        val curr = recentPositions[1]
        
        val distance = GeoUtils.calculateDistance(prev.latitude, prev.longitude, curr.latitude, curr.longitude)
        if (distance < MIN_DISTANCE_FOR_BEARING) return
        
        var bearing = GeoUtils.calculateBearing(prev.latitude, prev.longitude, curr.latitude, curr.longitude)
        if (bearing < 0) bearing += 360
        
        travelingBearing = bearing
    }
    
    /**
     * 목표 방향 계산
     */
    private fun calculateRouteBearing(currentLocation: Location) {
        val tLat = targetLat ?: return
        val tLng = targetLng ?: return
        
        var bearing = GeoUtils.calculateBearing(currentLocation.latitude, currentLocation.longitude, tLat, tLng)
        if (bearing < 0) bearing += 360
        
        routeBearing = bearing
    }
    

    
    /**
     * 네비게이션 데이터 전송
     */
    private fun sendNavigationUpdate() {
        listener?.onNavigationUpdate(
            deviceHeading,
            routeBearing,
            travelingBearing,
            targetLat,
            targetLng
        )
    }
    
    /**
     * 현재 기기 방향 반환
     */
    fun getDeviceHeading(): Double = deviceHeading
    
    /**
     * 현재 목표 방향 반환
     */
    fun getRouteBearing(): Double = routeBearing
    
    /**
     * 현재 진행 방향 반환
     */
    fun getTravelingBearing(): Double = travelingBearing
    
    /**
     * 네비게이션 활성화 여부
     */
    fun isActive(): Boolean = locationCallback != null
    
    /**
     * 리소스 해제
     */
    fun release() {
        stop()
        listener = null
    }
}
