import 'package:flutter/services.dart';

/// HRTF 기반 공간음향 서비스 (네이티브 Android)
///
/// Android의 Virtualizer AudioEffect를 사용하여 3D 공간음향을 구현합니다.
/// - 방향에 따라 좌/우 볼륨 및 가상화 효과 적용
/// - 정면에 가까울수록 빠른 비프음
///
/// balance 개념:
/// - angleDiff = -90: 완전히 왼쪽
/// - angleDiff = 0: 정면 (양쪽 동일)
/// - angleDiff = +90: 완전히 오른쪽
class SpatialAudioService {
  static final SpatialAudioService instance = SpatialAudioService._();
  SpatialAudioService._();

  // 네이티브 채널
  static const MethodChannel _channel = MethodChannel(
    'com.ctrlcv.sidae_app/yolo_native',
  );

  bool _isInitialized = false;
  bool _isPlaying = false;

  // 현재 각도 차이
  double _currentAngleDiff = 0.0;

  // 현재 거리 (미터 단위, null이면 거리 무시)
  double? _currentDistance;

  /// 초기화
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      final result = await _channel.invokeMethod<bool>(
        'initializeSpatialAudio',
      );
      _isInitialized = result ?? false;
      return _isInitialized;
    } catch (e) {
      return false;
    }
  }

  /// 방향에 따라 패닝 업데이트
  ///
  /// [angleDiff]: 기기 방향 기준 목표 방향의 각도 차이
  /// - 음수: 왼쪽 (예: -30도 = 왼쪽 30도)
  /// - 양수: 오른쪽 (예: +45도 = 오른쪽 45도)
  /// - 0: 정면
  /// [distance]: 거리 (미터 단위, null이면 거리 무시)
  void updateDirection(double angleDiff, [double? distance]) {
    if (!_isInitialized) return;

    // 값이 크게 변했을 때만 업데이트 (성능 최적화)
    // 각도 차이가 2도 이상이거나, 거리가 1미터 이상 변했을 때 업데이트
    final angleChanged = (angleDiff - _currentAngleDiff).abs() > 2.0;
    final distanceChanged =
        distance != null &&
        _currentDistance != null &&
        (distance - _currentDistance!).abs() > 1.0;
    final distanceSet = distance != null && _currentDistance == null;

    if (angleChanged || distanceChanged || distanceSet) {
      _currentAngleDiff = angleDiff;
      _currentDistance = distance;

      // 네이티브 호출 (비동기, 결과 무시)
      final args = <String, dynamic>{'angleDiff': angleDiff};
      if (distance != null) {
        args['distance'] = distance;
      }

      _channel.invokeMethod('updateSpatialAudioDirection', args).catchError((
        e,
      ) {
        // 무시
      });
    }
  }

  /// 재생 시작
  Future<void> start() async {
    if (!_isInitialized) return;
    if (_isPlaying) return;

    try {
      await _channel.invokeMethod('startSpatialAudio');
      _isPlaying = true;
    } catch (e) {
      // 무시
    }
  }

  /// 재생 중지
  Future<void> stop() async {
    if (!_isInitialized) return;

    try {
      await _channel.invokeMethod('stopSpatialAudio');
      _isPlaying = false;
    } catch (e) {
      // 무시
    }
  }

  /// 볼륨 설정 (0.0 ~ 1.0)
  Future<void> setVolume(double volume) async {
    if (!_isInitialized) return;

    try {
      await _channel.invokeMethod('setSpatialAudioVolume', {
        'volume': volume.clamp(0.0, 1.0),
      });
    } catch (e) {
      // 무시
    }
  }

  /// 현재 재생 중인지 확인
  bool get isPlaying => _isPlaying;

  /// 현재 각도 차이
  double get currentAngleDiff => _currentAngleDiff;

  /// 리소스 해제
  void dispose() {
    if (!_isInitialized) return;

    try {
      _channel.invokeMethod('releaseSpatialAudio');
    } catch (e) {
      // 무시
    }

    _isInitialized = false;
    _isPlaying = false;
  }
}
