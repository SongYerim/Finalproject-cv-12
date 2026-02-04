// import 'dart:developer' as developer;
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_tts/flutter_tts.dart';

/// TTS (Text-to-Speech) 공통 서비스
class TtsService {
  static TtsService? _instance;
  static TtsService get instance => _instance ??= TtsService._();
  TtsService._();

  final FlutterTts _tts = FlutterTts();
  bool _isInitialized = false;

  // TTS 대기열 아이템
  final List<QueueItem> _queue = [];
  bool _isPlaying = false; // 현재 재생 중 여부

  /// TTS 초기화 (한 번만 수행)
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await _tts.setLanguage("ko-KR");
    } catch (e) {}

    await _tts.setSpeechRate(1.2);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);

    // iOS 오디오 세션 설정
    try {
      await _tts
          .setIosAudioCategory(IosTextToSpeechAudioCategory.playAndRecord, [
            IosTextToSpeechAudioCategoryOptions.allowBluetooth,
            IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
          ]);
    } catch (e) {}

    // Android/iOS 완료 핸들러 설정
    _tts.setCompletionHandler(() {
      // awaitSpeakCompletion(true)를 쓰더라도 안전장치로 둠
      // _processQueue에서 완료 처리를 하므로 여기서는 플래그만 관리하거나 비워둬도 됨
      // 하지만 비정상 종료 시 복구를 위해 _processQueue 호출은 유지하되,
      // _isPlaying이 false가 된 상태에서만 호출하도록?
      // 일단 awaitSpeakCompletion(true)가 주 로직이므로 여기는 비워두거나 단순화 가능
    });

    try {
      await _tts.awaitSpeakCompletion(true);
    } catch (e) {}

    _isInitialized = true;
  }

  /// 텍스트 읽기 (큐에 추가, 완료 콜백 지원)
  Future<void> speak(String text, {VoidCallback? onCompleted}) async {
    if (text.isEmpty) {
      onCompleted?.call();
      return;
    }

    if (!_isInitialized) {
      await initialize();
    }

    // 중복 방지: 큐의 마지막 메시지와 같으면 추가하지 않음 (선택 사항)
    // 단, 콜백이 있는 경우는 중복이라도 실행해야 할 수 있으므로 체크 로직 주의
    if (_queue.isNotEmpty && _queue.last.text == text && onCompleted == null) {
      return;
    }

    // 큐에 추가
    _queue.add(QueueItem(text, onCompleted));

    // 재생 중이 아니면 큐 처리 시작
    if (!_isPlaying) {
      _processQueue();
    }
  }

  /// 대기열 처리 (재귀적으로 호출됨)
  Future<void> _processQueue() async {
    if (_queue.isEmpty) {
      _isPlaying = false;
      return;
    }

    _isPlaying = true;
    final item = _queue.removeAt(0); // FIFO

    try {
      await _tts.speak(item.text);

      // 말하기 완료 후 콜백 실행
      item.onCompleted?.call();

      _processQueue();
    } catch (e) {
      _isPlaying = false;
      _processQueue();
    }
  }

  /// TTS 중지 (대기열 비우기 + 즉시 중지)
  Future<void> stop() async {
    _queue.clear(); // 대기열 삭제
    _isPlaying = false;
    await _tts.stop();
  }
}

class QueueItem {
  final String text;
  final VoidCallback? onCompleted;
  QueueItem(this.text, this.onCompleted);
}
