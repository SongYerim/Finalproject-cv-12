package com.ctrlcv.sidae_app.utils

/**
 * 지리 계산 유틸리티
 * 
 * GPS 관련 거리 및 방향 계산을 위한 공통 함수 모음
 */
object GeoUtils {
    
    /**
     * 두 좌표 간 거리 계산 (Haversine 공식)
     * 
     * @param lat1 시작 위도
     * @param lng1 시작 경도
     * @param lat2 끝 위도
     * @param lng2 끝 경도
     * @return 거리 (미터)
     */
    fun calculateDistance(lat1: Double, lng1: Double, lat2: Double, lng2: Double): Double {
        val R = 6371000.0 // 지구 반경 (미터)
        val dLat = Math.toRadians(lat2 - lat1)
        val dLng = Math.toRadians(lng2 - lng1)
        val a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) *
                Math.sin(dLng / 2) * Math.sin(dLng / 2)
        val c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
        return R * c
    }
    
    /**
     * 두 좌표 간 방향 계산
     * 
     * @param lat1 시작 위도
     * @param lng1 시작 경도
     * @param lat2 끝 위도
     * @param lng2 끝 경도
     * @return 방향 (도)
     */
    fun calculateBearing(lat1: Double, lng1: Double, lat2: Double, lng2: Double): Double {
        val dLng = Math.toRadians(lng2 - lng1)
        val lat1Rad = Math.toRadians(lat1)
        val lat2Rad = Math.toRadians(lat2)
        
        val x = Math.sin(dLng) * Math.cos(lat2Rad)
        val y = Math.cos(lat1Rad) * Math.sin(lat2Rad) - Math.sin(lat1Rad) * Math.cos(lat2Rad) * Math.cos(dLng)
        
        var bearing = Math.atan2(x, y)
        bearing = Math.toDegrees(bearing)
        
        return bearing
    }
}
