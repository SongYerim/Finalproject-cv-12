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

    await _tts.setLanguage("ko-KR");
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);

    // iOS 오디오 세션 설정
    await _tts.setIosAudioCategory(
      IosTextToSpeechAudioCategory.playAndRecord,
      [
        IosTextToSpeechAudioCategoryOptions.allowBluetooth,
        IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
      ],
    );

    try {
      await _tts.awaitSpeakCompletion(true);
    } catch (_) {}

    _isInitialized = true;
  }

  /// 텍스트 읽기
  Future<void> speak(String text) async {
    if (!_isInitialized) await initialize();
    await _tts.stop();
    await _tts.speak(text);
  }

  /// TTS 중지
  Future<void> stop() async {
    await _tts.stop();
  }
}
