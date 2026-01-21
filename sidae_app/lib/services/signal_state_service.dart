import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'tts_service.dart';

/// 신호등 상태 상수 정의
enum SignalState {
  /// 앱 시작 직후 상태
  init,

  /// 빨간불 확인 후 파란불 대기 상태
  waitForGreen,

  /// 파란불 확인 후 건너는 중 상태
  crossing,
}

/// 과반수 판정 결과
enum SignalConsensus { red, green, unknown }

/// 신호등 감지 결과를 처리하고 상태 머신 기반 음성 안내를 제공하는 서비스
///
/// Python 로직을 Dart로 변환:
/// - 최근 10개 프레임의 감지 결과를 버퍼에 저장
/// - 6개 이상 동일한 신호가 감지되면 과반수로 판정
/// - 상태 전이에 따라 음성 안내 제공
class SignalStateService {
  /// 싱글톤 인스턴스
  static SignalStateService? _instance;
  static SignalStateService get instance =>
      _instance ??= SignalStateService._();
  SignalStateService._();

  /// 신호 버퍼 (최근 10개 프레임)
  final Queue<String> _signalBuffer = Queue<String>();
  static const int _bufferSize = 10;
  static const int _consensusThreshold = 6;

  /// 현재 앱 상태
  SignalState _currentState = SignalState.init;
  SignalState get currentState => _currentState;

  /// TTS 서비스
  final TtsService _ttsService = TtsService.instance;

  /// 상태 변경 콜백 (UI 업데이트용)
  Function(SignalState, SignalConsensus)? onStateChanged;

  /// 서비스 상태 초기화 (화면이 열릴 때 호출)
  void reset() {
    _signalBuffer.clear();
    _currentState = SignalState.init;
    debugPrint('🔄 SignalStateService 초기화됨');
  }

  /// 감지 결과 처리
  ///
  /// [detections]는 YOLO 모델의 감지 결과 리스트로,
  /// 각 감지 결과는 'label'과 'confidence' 키를 포함해야 합니다.
  void processDetections(List<Map<String, dynamic>> detections) {
    // 디버그: 전달받은 모든 라벨 확인
    final allLabels = detections.map((d) => d['label']).toList();
    debugPrint('📥 전달받은 라벨들: $allLabels');

    // 1. R_Signal과 G_Signal만 필터링 (trim()으로 줄바꿈 제거)
    final signalCandidates = detections.where((det) {
      final label = (det['label'] as String?)?.trim();
      final isSignal = label == 'R_Signal' || label == 'G_Signal';
      if (isSignal) {
        debugPrint('   ✓ 신호 감지: "$label"');
      }
      return isSignal;
    }).toList();

    debugPrint('🔎 필터링된 신호: ${signalCandidates.length}개');

    // 2. 감지된 신호가 있다면 confidence가 가장 높은 것 선택
    String targetLabel = 'NONE';
    if (signalCandidates.isNotEmpty) {
      // confidence 기준 내림차순 정렬 후 첫 번째 요소 선택
      signalCandidates.sort(
        (a, b) =>
            (b['confidence'] as double).compareTo(a['confidence'] as double),
      );
      final bestSignal = signalCandidates.first;
      final bestLabel = (bestSignal['label'] as String).trim();

      // 라벨 단순화 (R_Signal -> RED, G_Signal -> GREEN)
      if (bestLabel == 'R_Signal') {
        targetLabel = 'RED';
      } else {
        targetLabel = 'GREEN';
      }
      debugPrint('✅ 선택된 신호: $targetLabel (${bestSignal['confidence']})');
    }

    // 3. 최선의 결과를 버퍼에 삽입
    _signalBuffer.add(targetLabel);
    if (_signalBuffer.length > _bufferSize) {
      _signalBuffer.removeFirst();
    }

    // 4. 판단을 위한 과반수 데이터 확보 확인 (10개)
    if (_signalBuffer.length < _bufferSize) {
      debugPrint('🔄 신호 버퍼 수집 중: ${_signalBuffer.length}/$_bufferSize');
      return;
    }

    // 5. 과반수 판정 (6개 이상 동일할 때)
    final consensus = _getConsensus();

    // 6. 상태 머신 로직 기반 음성 안내
    _handleStateTransition(consensus);
  }

  /// 과반수 판정
  SignalConsensus _getConsensus() {
    int redCount = _signalBuffer.where((s) => s == 'RED').length;
    int greenCount = _signalBuffer.where((s) => s == 'GREEN').length;

    debugPrint('📊 신호 버퍼: RED=$redCount, GREEN=$greenCount');

    if (redCount >= _consensusThreshold) {
      return SignalConsensus.red;
    } else if (greenCount >= _consensusThreshold) {
      return SignalConsensus.green;
    }
    return SignalConsensus.unknown;
  }

  /// 상태 전이 처리 및 음성 안내
  void _handleStateTransition(SignalConsensus consensus) {
    final previousState = _currentState;

    switch (_currentState) {
      // --- [상태 1] 앱 시작 직후 (INIT) ---
      case SignalState.init:
        if (consensus == SignalConsensus.green) {
          // 처음부터 초록불이면 건너지 않음
          _playVoice('건너가지 마세요. 다음 신호를 기다리세요.');
          // 상태 유지 (빨간불을 확인해야 '건너' 단계로 갈 수 있음)
          _currentState = SignalState.crossing;
        } else if (consensus == SignalConsensus.red) {
          _playVoice('빨간불입니다. 잠시 기다려 주세요.');
          _currentState = SignalState.waitForGreen;
        }

        break;

      // --- [상태 2] 빨간불 확인 후 초록불 대기 (WAIT_FOR_GREEN) ---
      case SignalState.waitForGreen:
        if (consensus == SignalConsensus.green) {
          _playVoice('초록불로 바뀌었습니다. 이제 건너가도 좋습니다.');
          _currentState = SignalState.crossing;
        }
        // RED일 때는 이미 안내했으므로 아무것도 하지 않음
        break;

      // --- [상태 3] 초록불 확인 후 건너는 중 (CROSSING) ---
      case SignalState.crossing:
        if (consensus == SignalConsensus.red) {
          _playVoice('빨간불로 바뀌었습니다. 건너가지 마세요.');
          // 다음 사이클을 위해 다시 대기 상태로 복귀
          _currentState = SignalState.waitForGreen;
        }
        break;
    }

    // 상태 변경 시 콜백 호출
    if (previousState != _currentState ||
        consensus != SignalConsensus.unknown) {
      debugPrint('🚦 상태: $previousState → $_currentState (판정: $consensus)');
      onStateChanged?.call(_currentState, consensus);
    }
  }

  /// 음성 안내 재생
  Future<void> _playVoice(String text) async {
    debugPrint('🔊 [음성 안내]: $text');
    await _ttsService.speak(text);
  }

  /// 현재 버퍼 상태 (디버그용)
  String get bufferStatus {
    int redCount = _signalBuffer.where((s) => s == 'RED').length;
    int greenCount = _signalBuffer.where((s) => s == 'GREEN').length;
    int noneCount = _signalBuffer.where((s) => s == 'NONE').length;
    return 'R:$redCount G:$greenCount N:$noneCount';
  }
}
