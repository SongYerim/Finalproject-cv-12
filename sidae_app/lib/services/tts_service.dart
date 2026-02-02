import 'dart:developer' as developer;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_tts/flutter_tts.dart';

/// TTS (Text-to-Speech) 공통 서비스
class TtsService {
  static TtsService? _instance;
  static TtsService get instance => _instance ??= TtsService._();
  TtsService._();

  final FlutterTts _tts = FlutterTts();
  bool _isInitialized = false;

  /// TTS 초기화 (한 번만 수행)
  Future<void> initialize() async {
    if (_isInitialized) return;

    developer.log('🔧 [TtsService] TTS 초기화 시작', name: 'TTS');
    
    try {
      await _tts.setLanguage("ko-KR");
      developer.log('✅ [TtsService] 언어 설정: ko-KR', name: 'TTS');
    } catch (e) {
      developer.log('⚠️ [TtsService] 언어 설정 실패: $e', name: 'TTS');
    }
    
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    developer.log('✅ [TtsService] 속도/피치/볼륨 설정 완료', name: 'TTS');

    // iOS 오디오 세션 설정
    try {
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playAndRecord,
        [
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
        ],
      );
      developer.log('✅ [TtsService] iOS 오디오 세션 설정 완료', name: 'TTS');
    } catch (e) {
      developer.log('⚠️ [TtsService] iOS 오디오 세션 설정 실패 (Android일 수 있음): $e', name: 'TTS');
    }

    // Android에서 완료 대기 설정
    try {
      await _tts.awaitSpeakCompletion(true);
      developer.log('✅ [TtsService] awaitSpeakCompletion 설정 완료', name: 'TTS');
    } catch (e) {
      developer.log('⚠️ [TtsService] awaitSpeakCompletion 설정 실패: $e', name: 'TTS');
    }

    _isInitialized = true;
    developer.log('✅ [TtsService] TTS 초기화 완료', name: 'TTS');
  }

  /// 텍스트 읽기
  Future<void> speak(String text) async {
    if (text.isEmpty) {
      developer.log('⚠️ [TtsService] 빈 텍스트, TTS 호출 스킵', name: 'TTS');
      return;
    }
    
    developer.log('🔊 [TtsService] speak 호출: "$text"', name: 'TTS');
    
    if (!_isInitialized) {
      developer.log('⚠️ [TtsService] 초기화되지 않음, 초기화 중...', name: 'TTS');
      await initialize();
    }
    
    try {
      // 기존 TTS 중지
      await _tts.stop();
      developer.log('🛑 [TtsService] 기존 TTS 중지 완료', name: 'TTS');
      
      // TTS 실행
      final result = await _tts.speak(text);
      developer.log('✅ [TtsService] speak 호출 완료, result: $result', name: 'TTS');
      
      // Android에서 완료 대기 (awaitSpeakCompletion이 true일 때)
      if (result == 1) {
        developer.log('✅ [TtsService] TTS 재생 시작됨', name: 'TTS');
      } else {
        developer.log('⚠️ [TtsService] TTS 재생 실패, result: $result', name: 'TTS');
      }
    } catch (e) {
      developer.log('❌ [TtsService] speak 호출 실패: $e', name: 'TTS', error: e);
      rethrow;
    }
  }

  /// TTS 중지
  Future<void> stop() async {
    developer.log('🛑 [TtsService] stop 호출', name: 'TTS');
    await _tts.stop();
  }
}
