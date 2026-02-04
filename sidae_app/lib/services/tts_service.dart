// import 'dart:developer' as developer;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_tts/flutter_tts.dart';

/// TTS (Text-to-Speech) 공통 서비스
class TtsService {
  static TtsService? _instance;
  static TtsService get instance => _instance ??= TtsService._();
  TtsService._();

  final FlutterTts _tts = FlutterTts();
  bool _isInitialized = false;

  // TTS 대기열 (FIFO)
  final List<String> _queue = [];
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
      _isPlaying = false;
      _processQueue(); // 다음 메시지 재생
    });

    // Android에서 완료 대기 설정 (awaitSpeakCompletion을 true로 하면 await _tts.speak()가 끝날 때까지 기다림)
    // 하지만 큐 시스템에서는 setCompletionHandler로 제어하는 것이 더 유연할 수 있음.
    // 여기서는 awaitSpeakCompletion을 true로 유지하되, 큐 로직은 _processQueue에서 순차 실행하도록 함.
    try {
      await _tts.awaitSpeakCompletion(true);
    } catch (e) {}

    _isInitialized = true;
  }

  /// 텍스트 읽기 (큐에 추가)
  Future<void> speak(String text) async {
    if (text.isEmpty) return;

    if (!_isInitialized) {
      await initialize();
    }

    // 중복 방지: 큐의 마지막 메시지와 같으면 추가하지 않음 (선택 사항)
    if (_queue.isNotEmpty && _queue.last == text) {
      return;
    }
    // 현재 재생 중인 메시지와 같아도 중복 방지 (선택 사항)
    // if (_isPlaying && _currentMessage == text) return;

    // 큐에 추가
    _queue.add(text);

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
    final text = _queue.removeAt(0); // FIFO: 첫 번째 항목 꺼내기

    try {
      // awaitSpeakCompletion(true) 설정 덕분에 재생이 끝날 때까지 여기서 대기함
      // (만약 설정이 안 먹히면 setCompletionHandler가 백업으로 동작)
      await _tts.speak(text);

      // Android에서는 await가 완료되면 재생이 끝난 것임.
      // iOS 등 일관성을 위해 여기서 바로 다음으로 넘어갈 수도 있지만,
      // setCompletionHandler가 호출될 수도 있으므로 플래그 관리에 주의.

      // 여기서는 안전하게: await가 풀리면 바로 다음 곡 재생 시도
      // (만약 setCompletionHandler가 중복 호출되어도 _isPlaying 체크 등이 필요할 수 있음.
      //  하지만 단일 스레드 이벤트 루프라 큰 문제는 없음)

      _processQueue();
    } catch (e) {
      // 에러 발생 시에도 다음 메시지로 진행
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
