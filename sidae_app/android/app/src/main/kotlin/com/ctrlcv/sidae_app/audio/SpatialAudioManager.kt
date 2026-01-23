package com.ctrlcv.sidae_app.audio

import android.content.Context
import android.content.res.AssetFileDescriptor
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.SoundPool
import android.media.Spatializer
import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import android.media.audiofx.Virtualizer
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin

/**
 * 공간음향 서비스 (Spatializer + EQ + BassBoost + 향상된 공간감)
 * 
 * SoundPool을 사용하여 저지연 공간음향을 구현합니다.
 * - Spatializer (Android 12+) 또는 Virtualizer (이전 버전) 사용
 * - Equalizer: Head Shadow Effect 시뮬레이션 (측면/뒤에서 고주파 감쇠)
 * - 거리 기반 고주파 필터링 (공기 흡수 효과)
 * - Frequency-dependent Panning (고주파는 더 날카로운 방향성)
 * - BassBoost: 근접 효과 (가까울수록 저음 풍부)
 * - 방향에 따라 좌/우 볼륨 조절 (Equal Power Panning)
 * - 거리에 따른 볼륨 감쇠
 * - 뒤방향 감지 및 볼륨 감소
 */
class SpatialAudioManager(private val context: Context) {
    
    companion object {
        private const val TAG = "SpatialAudioManager"
        private const val VIRTUALIZER_STRENGTH: Short = 1000  // 최대 강도
        private const val BASS_BOOST_DEFAULT: Short = 500
        private const val PAN_SHARPNESS = 1.2f  // 패닝 날카로움 (1.0 = 기본, >1.0 = 더 날카름)
    }
    
    private var soundPool: SoundPool? = null
    
    // AudioEffect
    private var spatializer: Spatializer? = null      // Android 12+ 공간음향
    private var virtualizer: Virtualizer? = null       // Android 12 미만 대체
    private var equalizer: Equalizer? = null           // Head Shadow Effect
    private var bassBoost: BassBoost? = null           // 근접 효과
    
    // SoundPool 관련
    private var soundId: Int = 0
    private var streamId: Int = 0
    private var audioSessionId: Int = 0
    
    private var isInitialized = false
    private var isPlaying = false
    
    // 현재 방향 각도 (-180 ~ 180)
    private var currentAngleDiff = 0f
    
    // 현재 거리 (미터 단위, null이면 거리 무시)
    private var currentDistance: Float? = null
    
    // 기본 볼륨 (0.0 ~ 1.0)
    private var baseVolume = 0.7f
    
    // 거리 감쇠 설정
    private var maxDistance = 100f
    private var minVolumeAtMaxDistance = 0.1f
    
    // EQ 설정
    private var eqMinLevel: Short = -1500
    private var eqMaxLevel: Short = 1500
    private var numEqBands: Int = 5
    
    // 비프 간격 제어
    private val handler = Handler(Looper.getMainLooper())
    private var beepInterval = 3500L  // 기본 3.5초
    
    /**
     * 초기화
     */
    fun initialize(): Boolean {
        if (isInitialized) {
            Log.d(TAG, "이미 초기화됨")
            return true
        }
        
        try {
            // SoundPool 생성
            val audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            
            soundPool = SoundPool.Builder()
                .setMaxStreams(1)
                .setAudioAttributes(audioAttributes)
                .build()
            
            // Asset에서 비프음 로드
            var assetLoaded = false
            val assetPaths = listOf(
                "flutter_assets/assets/sounds/direction_beep.mp3",
                "sounds/direction_beep.mp3",
                "assets/sounds/direction_beep.mp3"
            )
            
            for (path in assetPaths) {
                try {
                    val afd: AssetFileDescriptor = context.assets.openFd(path)
                    soundId = soundPool?.load(afd, 1) ?: 0
                    afd.close()
                    if (soundId > 0) {
                        Log.d(TAG, "✅ Asset 비프음 로드 성공: $path (soundId: $soundId)")
                        assetLoaded = true
                        break
                    }
                } catch (e: Exception) {
                    Log.v(TAG, "Asset 경로 실패: $path (${e.message})")
                }
            }
            
            if (!assetLoaded || soundId == 0) {
                Log.w(TAG, "Asset 로드 실패")
                release()
                return false
            }
            
            // 사운드 로드 완료 후 AudioEffect 초기화
            soundPool?.setOnLoadCompleteListener { _, sampleId, status ->
                if (status == 0 && sampleId == soundId) {
                    Log.d(TAG, "✅ 사운드 로드 완료, AudioEffect 초기화")
                    initializeAudioEffects()
                }
            }
            
            isInitialized = true
            Log.d(TAG, "✅ 공간음향 서비스 초기화 완료")
            return true
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ 초기화 실패: ${e.message}")
            release()
            return false
        }
    }
    
    /**
     * AudioEffect 초기화
     */
    private fun initializeAudioEffects() {
        // Spatializer (Android 12+) 또는 Virtualizer
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            initializeSpatializer()
        } else {
            initializeVirtualizer()
        }
        
        // Equalizer
        initializeEqualizer()
        
        // BassBoost
        initializeBassBoost()
    }
    
    /**
     * Spatializer 초기화 (Android 12+)
     */
    private fun initializeSpatializer() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        
        try {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            spatializer = audioManager.spatializer
            
            if (spatializer != null) {
                val isAvailable = spatializer?.isAvailable ?: false
                val isEnabled = spatializer?.isEnabled ?: false
                Log.d(TAG, "✅ Spatializer 확인 - 사용가능: $isAvailable, 활성화: $isEnabled")
                
                if (!isAvailable) {
                    Log.w(TAG, "⚠️ Spatializer 사용 불가, Virtualizer로 대체")
                    initializeVirtualizer()
                }
            } else {
                Log.w(TAG, "⚠️ Spatializer null, Virtualizer로 대체")
                initializeVirtualizer()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Spatializer 초기화 실패: ${e.message}, Virtualizer로 대체")
            initializeVirtualizer()
        }
    }
    
    /**
     * Virtualizer 초기화 (Spatializer 대체)
     */
    private fun initializeVirtualizer() {
        try {
            virtualizer = Virtualizer(0, audioSessionId).apply {
                setStrength(VIRTUALIZER_STRENGTH)
                enabled = true
            }
            Log.d(TAG, "✅ Virtualizer 활성화 (강도: $VIRTUALIZER_STRENGTH)")
        } catch (e: Exception) {
            Log.e(TAG, "Virtualizer 초기화 실패: ${e.message}")
        }
    }
    
    /**
     * Equalizer 초기화 (Head Shadow Effect)
     */
    private fun initializeEqualizer() {
        try {
            equalizer = Equalizer(0, audioSessionId).apply {
                numEqBands = numberOfBands.toInt()
                val range = bandLevelRange
                eqMinLevel = range[0]
                eqMaxLevel = range[1]
                
                // 초기값: 중립
                for (i in 0 until numEqBands) {
                    setBandLevel(i.toShort(), 0)
                }
                enabled = true
            }
            Log.d(TAG, "✅ Equalizer 활성화 (밴드: $numEqBands, 범위: $eqMinLevel ~ $eqMaxLevel)")
        } catch (e: Exception) {
            Log.e(TAG, "Equalizer 초기화 실패: ${e.message}")
        }
    }
    
    /**
     * BassBoost 초기화 (근접 효과)
     */
    private fun initializeBassBoost() {
        try {
            bassBoost = BassBoost(0, audioSessionId).apply {
                setStrength(BASS_BOOST_DEFAULT)
                enabled = true
            }
            Log.d(TAG, "✅ BassBoost 활성화 (강도: $BASS_BOOST_DEFAULT)")
        } catch (e: Exception) {
            Log.e(TAG, "BassBoost 초기화 실패: ${e.message}")
        }
    }
    
    /**
     * 방향에 따른 EQ 조절 (Head Shadow Effect 시뮬레이션)
     * 
     * 소리가 측면/뒤에서 올 때 고주파가 감쇠되는 효과
     * 거리에 따른 공기 흡수 효과도 함께 적용
     */
    private fun applyDirectionalEQ(angleDiff: Float, distance: Float? = null) {
        val eq = equalizer ?: return
        
        val absAngle = abs(angleDiff)
        
        try {
            // 정면(0도): EQ 중립
            // 측면(90도): 고주파 감쇠
            // 뒤(180도): 더 많은 고주파 감쇠 + 전체 감쇠
            
            val sideRatio = (absAngle / 90f).coerceIn(0f, 2f)
            
            // 거리에 따른 고주파 감쇠 (공기 흡수 효과)
            // 멀수록 고주파가 더 많이 감쇠됨
            val distanceHighFreqAttenuation = if (distance != null) {
                val normalizedDist = (distance / maxDistance).coerceIn(0f, 1f)
                // 최대 거리에서 고주파 -800dB 감쇠
                normalizedDist * 800f
            } else {
                0f
            }
            
            for (i in 0 until numEqBands) {
                // 밴드 번호가 높을수록 고주파
                val bandRatio = i.toFloat() / (numEqBands - 1).coerceAtLeast(1)
                
                // 방향에 따른 감쇠
                val directionalAttenuation = if (absAngle > 90) {
                    // 뒤에서: 전체 감쇠 + 고주파 더 감쇠
                    val behindRatio = (absAngle - 90f) / 90f
                    -(bandRatio * 600 + behindRatio * 400)  // 더 강한 감쇠
                } else {
                    // 측면: 고주파만 감쇠 (더 정교하게)
                    val angleFactor = absAngle / 90f  // 0 ~ 1
                    // 측면 각도에 따라 고주파 감쇠 강도 조절
                    -(bandRatio * bandRatio * sideRatio * 450)  // 제곱으로 더 날카로운 감쇠
                }
                
                // 거리 기반 고주파 감쇠 추가 (고주파 밴드에만 적용)
                val distanceAttenuation = -(bandRatio * bandRatio * distanceHighFreqAttenuation)
                
                // 총 감쇠량
                val totalAttenuation = directionalAttenuation + distanceAttenuation
                
                val level = totalAttenuation.toInt().toShort().coerceIn(eqMinLevel, eqMaxLevel)
                eq.setBandLevel(i.toShort(), level)
            }
            
            Log.v(TAG, "EQ 적용: 각도=${angleDiff}°, 거리=${distance?.let { "%.1fm".format(it) } ?: "N/A"}")
            
        } catch (e: Exception) {
            Log.e(TAG, "EQ 적용 실패: ${e.message}")
        }
    }
    
    /**
     * 거리에 따른 BassBoost 조절 (근접 효과)
     * 
     * 가까울수록 저음이 풍부하게
     */
    private fun applyDistanceBass(distance: Float?) {
        val bb = bassBoost ?: return
        
        try {
            val strength = if (distance == null) {
                BASS_BOOST_DEFAULT
            } else {
                // 가까울수록 강한 저음 (1000), 멀수록 약한 저음 (100)
                val normalizedDist = (distance / maxDistance).coerceIn(0f, 1f)
                (100 + 900 * (1f - normalizedDist)).toInt().toShort()
            }
            
            bb.setStrength(strength)
            Log.v(TAG, "BassBoost: 거리=${distance}m, 강도=$strength")
            
        } catch (e: Exception) {
            Log.e(TAG, "BassBoost 적용 실패: ${e.message}")
        }
    }
    
    /**
     * 방향 업데이트
     */
    fun updateDirection(angleDiff: Float, distance: Float? = null) {
        if (!isInitialized || soundPool == null || soundId == 0) return
        
        currentAngleDiff = angleDiff
        currentDistance = distance
        
        // 거리에 따른 볼륨 감쇠 계산
        val distanceAttenuatedVolume = if (distance != null) {
            calculateDistanceAttenuation(distance)
        } else {
            baseVolume
        }
        
        // 뒤방향 감지 (90도 이상 벗어남)
        val absAngle = abs(angleDiff)
        val isBehind = absAngle > 90f
        
        // 각도를 스테레오 패닝으로 변환
        val normalizedAngle = angleDiff.coerceIn(-90f, 90f)
        val pan = normalizedAngle / 90f
        
        // Frequency-dependent Panning (고주파는 더 날카로운 패닝)
        // 고주파는 더 강한 방향성을 가지므로 패닝을 더 강하게 적용
        val sharpPan = pan * PAN_SHARPNESS
        
        // Equal Power Panning (정면에서 양쪽 동일)
        val theta = (sharpPan.coerceIn(-1f, 1f) + 1f) * Math.PI / 4.0
        
        // 뒤방향일 때 볼륨 감소
        val behindAttenuation = if (isBehind) {
            val behindAngle = absAngle - 90f
            val behindRatio = behindAngle / 90f
            1.0f - (behindRatio * 0.7f)
        } else {
            1.0f
        }
        
        val finalVolume = distanceAttenuatedVolume * behindAttenuation
        val leftVolume = (cos(theta) * finalVolume).toFloat().coerceIn(0f, 1f)
        val rightVolume = (sin(theta) * finalVolume).toFloat().coerceIn(0f, 1f)
        
        try {
            if (streamId > 0) {
                soundPool?.setVolume(streamId, leftVolume, rightVolume)
            }
            
            // === 방향성 EQ 적용 (Head Shadow Effect + 거리 기반 필터링) ===
            applyDirectionalEQ(angleDiff, distance)
            
            // === 거리 Bass 적용 (근접 효과) ===
            applyDistanceBass(distance)
            
            // 비프 간격 조절
            val distanceFactor = if (distance != null) {
                val normalizedDist = (distance / maxDistance).coerceIn(0f, 1f)
                1.0f - (normalizedDist * 0.5f)
            } else {
                1.0f
            }
            
            val baseInterval = when {
                absAngle < 15 -> 1500L   // 정면: 1.5초
                absAngle < 45 -> 2000L   // 약간 벗어남: 2.8초
                absAngle < 90 -> 2500L   // 중간: 3.8초
                else -> 5000L            // 많이 벗어남: 5초
            }
            
            beepInterval = (baseInterval * distanceFactor).toLong()
            
            Log.v(TAG, "방향: $angleDiff°${if (isBehind) " (뒤)" else ""}, " +
                    "거리: ${distance?.let { "%.1fm".format(it) } ?: "N/A"}, " +
                    "L=${"%.2f".format(leftVolume)}, R=${"%.2f".format(rightVolume)}, " +
                    "간격=${beepInterval}ms")
            
        } catch (e: Exception) {
            Log.e(TAG, "방향 업데이트 실패: ${e.message}")
        }
    }
    
    /**
     * 거리에 따른 볼륨 감쇠 계산 (역제곱 법칙)
     */
    private fun calculateDistanceAttenuation(distance: Float): Float {
        if (distance <= 0f) return baseVolume
        
        val referenceDistance = maxDistance * 0.3f
        val normalizedDistance = distance / referenceDistance
        val attenuation = 1.0f / (1.0f + normalizedDistance * normalizedDistance)
        val finalVolume = baseVolume * attenuation.coerceIn(minVolumeAtMaxDistance / baseVolume, 1.0f)
        
        return finalVolume.coerceIn(0f, 1f)
    }
    
    /**
     * 재생 시작
     */
    fun start() {
        if (!isInitialized) {
            Log.w(TAG, "초기화되지 않음")
            return
        }
        
        if (isPlaying) {
            Log.d(TAG, "이미 재생 중")
            return
        }
        
        isPlaying = true
        startBeepLoop()
        Log.d(TAG, "▶️ 공간음향 재생 시작")
    }
    
    /**
     * 비프 반복 재생 시작
     */
    private fun startBeepLoop() {
        playBeep()
        Log.d(TAG, "🔊 비프 루프 시작 (간격: ${beepInterval}ms)")
    }
    
    /**
     * 단일 비프 재생
     */
    private fun playBeep() {
        if (!isPlaying || soundPool == null || soundId == 0) return
        
        try {
            // 현재 볼륨 계산 (Frequency-dependent Panning 적용)
            val normalizedAngle = currentAngleDiff.coerceIn(-90f, 90f)
            val pan = normalizedAngle / 90f
            val sharpPan = pan * PAN_SHARPNESS
            val theta = (sharpPan.coerceIn(-1f, 1f) + 1f) * Math.PI / 4.0
            
            val distanceAttenuatedVolume = if (currentDistance != null) {
                calculateDistanceAttenuation(currentDistance!!)
            } else {
                baseVolume
            }
            
            val absAngle = abs(currentAngleDiff)
            val isBehind = absAngle > 90f
            val behindAttenuation = if (isBehind) {
                val behindAngle = absAngle - 90f
                val behindRatio = behindAngle / 90f
                1.0f - (behindRatio * 0.7f)
            } else {
                1.0f
            }
            
            val finalVolume = distanceAttenuatedVolume * behindAttenuation
            val leftVolume = (cos(theta) * finalVolume).toFloat().coerceIn(0f, 1f)
            val rightVolume = (sin(theta) * finalVolume).toFloat().coerceIn(0f, 1f)
            
            // SoundPool 재생
            streamId = soundPool?.play(soundId, leftVolume, rightVolume, 1, 0, 1f) ?: 0
            
            if (streamId > 0) {
                val beepDuration = 150L
                val totalDelay = beepDuration + beepInterval
                handler.postDelayed({
                    if (isPlaying) {
                        playBeep()
                    }
                }, totalDelay)
                
                Log.v(TAG, "🔔 비프 재생 (streamId: $streamId, 다음 재생까지: ${totalDelay}ms, 간격: ${beepInterval}ms)")
            }
        } catch (e: Exception) {
            Log.e(TAG, "비프 재생 실패: ${e.message}")
        }
    }
    
    /**
     * 재생 중지
     */
    fun stop() {
        isPlaying = false
        handler.removeCallbacksAndMessages(null)
        
        try {
            if (streamId > 0) {
                soundPool?.stop(streamId)
                streamId = 0
            }
        } catch (e: Exception) {
            Log.e(TAG, "중지 실패: ${e.message}")
        }
        
        Log.d(TAG, "⏹️ 공간음향 재생 중지")
    }
    
    /**
     * 기본 볼륨 설정
     */
    fun setVolume(vol: Float) {
        baseVolume = vol.coerceIn(0f, 1f)
        updateDirection(currentAngleDiff, currentDistance)
    }
    
    /**
     * 최대 거리 설정
     */
    fun setMaxDistance(distance: Float) {
        maxDistance = distance.coerceIn(1f, 1000f)
        updateDirection(currentAngleDiff, currentDistance)
    }
    
    /**
     * 현재 재생 중인지 확인
     */
    fun isPlaying(): Boolean = isPlaying
    
    /**
     * 리소스 해제
     */
    fun release() {
        stop()
        
        try {
            equalizer?.release()
            equalizer = null
        } catch (e: Exception) {
            Log.e(TAG, "Equalizer 해제 실패: ${e.message}")
        }
        
        try {
            bassBoost?.release()
            bassBoost = null
        } catch (e: Exception) {
            Log.e(TAG, "BassBoost 해제 실패: ${e.message}")
        }
        
        try {
            virtualizer?.release()
            virtualizer = null
        } catch (e: Exception) {
            Log.e(TAG, "Virtualizer 해제 실패: ${e.message}")
        }
        
        // Spatializer는 시스템 리소스이므로 해제 불필요
        spatializer = null
        
        try {
            if (soundId > 0) {
                soundPool?.unload(soundId)
                soundId = 0
            }
            soundPool?.release()
            soundPool = null
        } catch (e: Exception) {
            Log.e(TAG, "SoundPool 해제 실패: ${e.message}")
        }
        
        isInitialized = false
        Log.d(TAG, "🗑️ 공간음향 서비스 해제됨")
    }
}
