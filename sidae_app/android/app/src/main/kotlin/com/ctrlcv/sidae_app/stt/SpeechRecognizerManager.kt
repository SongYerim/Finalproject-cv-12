package com.ctrlcv.sidae_app.stt

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log

/**
 * 음성인식 이벤트 타입
 */
enum class SttEventType {
    STATUS,   // 상태 변경
    RESULT,   // 최종 결과
    PARTIAL,  // 부분 결과
    ERROR     // 오류
}

/**
 * 음성인식 리스너
 */
interface SpeechRecognizerListener {
    /**
     * 음성인식 이벤트 콜백
     * 
     * @param eventType 이벤트 타입
     * @param data 이벤트 데이터
     */
    fun onSttEvent(eventType: SttEventType, data: String)
}

/**
 * 음성인식 관리자
 * 
 * Android SpeechRecognizer를 래핑하여 음성인식 기능을 제공합니다.
 */
class SpeechRecognizerManager(private val context: Context) {
    
    companion object {
        private const val TAG = "SpeechRecognizerManager"
        private const val LANGUAGE = "ko-KR" // 한국어
    }
    
    private var speechRecognizer: SpeechRecognizer? = null
    private var sttIntent: Intent? = null
    @Volatile private var isListening = false
    private var listener: SpeechRecognizerListener? = null
    
    /**
     * 리스너 설정
     */
    fun setListener(listener: SpeechRecognizerListener) {
        this.listener = listener
    }
    
    /**
     * 음성인식 초기화
     * 
     * @return 성공 여부
     */
    fun initialize(): Boolean {
        if (speechRecognizer != null) {
            Log.d(TAG, "이미 초기화됨")
            return true
        }
        
        if (!SpeechRecognizer.isRecognitionAvailable(context)) {
            Log.e(TAG, "❌ 음성인식이 이 기기에서 지원되지 않습니다")
            return false
        }
        
        speechRecognizer = SpeechRecognizer.createSpeechRecognizer(context)
        speechRecognizer?.setRecognitionListener(createRecognitionListener())
        
        // STT Intent 초기화
        sttIntent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, LANGUAGE)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }
        
        Log.d(TAG, "✅ SpeechRecognizer 초기화 완료")
        return true
    }
    
    private fun createRecognitionListener(): RecognitionListener {
        return object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {
                Log.d(TAG, "🎤 음성 입력 준비됨")
                listener?.onSttEvent(SttEventType.STATUS, "ready")
            }
            
            override fun onBeginningOfSpeech() {
                Log.d(TAG, "🎤 음성 입력 시작")
                listener?.onSttEvent(SttEventType.STATUS, "listening")
            }
            
            override fun onRmsChanged(rmsdB: Float) {
                // 볼륨 레벨 변화 (필요시 처리)
            }
            
            override fun onBufferReceived(buffer: ByteArray?) {
                // 오디오 버퍼 수신
            }
            
            override fun onEndOfSpeech() {
                Log.d(TAG, "🎤 음성 입력 종료")
                isListening = false
            }
            
            override fun onError(error: Int) {
                val errorMsg = getErrorMessage(error)
                Log.e(TAG, "❌ STT 오류: $errorMsg")
                isListening = false
                listener?.onSttEvent(SttEventType.ERROR, errorMsg)
            }
            
            override fun onResults(results: Bundle?) {
                val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                val text = matches?.firstOrNull() ?: ""
                Log.d(TAG, "✅ STT 결과: $text")
                isListening = false
                listener?.onSttEvent(SttEventType.RESULT, text)
            }
            
            override fun onPartialResults(partialResults: Bundle?) {
                val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                val text = matches?.firstOrNull() ?: ""
                if (text.isNotEmpty()) {
                    Log.d(TAG, "🔄 STT 부분 결과: $text")
                    listener?.onSttEvent(SttEventType.PARTIAL, text)
                }
            }
            
            override fun onEvent(eventType: Int, params: Bundle?) {
                // 추가 이벤트 처리
            }
        }
    }
    
    /**
     * 오류 코드를 메시지로 변환
     */
    private fun getErrorMessage(error: Int): String {
        return when (error) {
            SpeechRecognizer.ERROR_AUDIO -> "오디오 녹음 오류"
            SpeechRecognizer.ERROR_CLIENT -> "클라이언트 오류"
            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "권한 부족"
            SpeechRecognizer.ERROR_NETWORK -> "네트워크 오류"
            SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "네트워크 타임아웃"
            SpeechRecognizer.ERROR_NO_MATCH -> "일치하는 결과 없음"
            SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "인식기 사용 중"
            SpeechRecognizer.ERROR_SERVER -> "서버 오류"
            SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "음성 입력 타임아웃"
            else -> "알 수 없는 오류 ($error)"
        }
    }
    
    /**
     * 음성인식 시작
     * 
     * @return 성공 여부
     */
    fun startListening(): Boolean {
        if (isListening) {
            Log.w(TAG, "⚠️ 이미 음성인식 중입니다")
            return true
        }
        
        // 초기화 확인
        if (speechRecognizer == null) {
            if (!initialize()) {
                return false
            }
        }
        
        if (sttIntent == null) {
            Log.e(TAG, "❌ STT Intent가 초기화되지 않음")
            return false
        }
        
        return try {
            isListening = true
            speechRecognizer?.startListening(sttIntent)
            Log.d(TAG, "🎤 음성인식 시작")
            true
        } catch (e: Exception) {
            Log.e(TAG, "❌ 음성인식 시작 실패: ${e.message}")
            isListening = false
            false
        }
    }
    
    /**
     * 음성인식 중지
     */
    fun stopListening() {
        try {
            speechRecognizer?.stopListening()
            isListening = false
            Log.d(TAG, "🛑 음성인식 중지")
        } catch (e: Exception) {
            Log.e(TAG, "❌ 음성인식 중지 실패: ${e.message}")
        }
    }
    
    /**
     * 음성인식 취소
     */
    fun cancel() {
        try {
            speechRecognizer?.cancel()
            isListening = false
            Log.d(TAG, "❌ 음성인식 취소")
        } catch (e: Exception) {
            Log.e(TAG, "❌ 음성인식 취소 실패: ${e.message}")
        }
    }
    
    /**
     * 현재 음성인식 중인지 확인
     */
    fun isListening(): Boolean = isListening
    
    /**
     * 리소스 해제
     */
    fun release() {
        try {
            speechRecognizer?.destroy()
            speechRecognizer = null
            sttIntent = null
            isListening = false
            listener = null
            Log.d(TAG, "✅ SpeechRecognizer 리소스 해제")
        } catch (e: Exception) {
            Log.e(TAG, "❌ 리소스 해제 실패: ${e.message}")
        }
    }
}
