import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'spatial_audio_service.dart';

/// 횡단보도 방향 안내 서비스
///
/// IMU 센서와 GPS를 사용하여 기기 방향 대비 횡단보도 끝지점의
/// 상대 각도를 계산하고, 공간음향으로 방향을 안내합니다.
///
/// 주의: 이 서비스는 EventChannel을 직접 구독하지 않습니다.
/// 외부에서 handleHeadingEvent()를 호출하여 heading 데이터를 전달해야 합니다.
/// (EventChannel 충돌 방지를 위함)
class CrosswalkDirectionService {
  // 상수
  static const int _headingHistorySize = 5; // Moving average 크기

  // 네이티브 채널 (메소드 호출용)
  static const MethodChannel _channel = MethodChannel(
    'com.ctrlcv.sidae_app/yolo_native',
  );

  final SpatialAudioService _audioService = SpatialAudioService.instance;

  // 횡단보도 끝지점 좌표
  double? _exitLat;
  double? _exitLng;

  // 스트림 구독 (GPS만 - EventChannel은 외부에서 처리)
  StreamSubscription<Position>? _positionSubscription;

  // 현재 상태
  double _deviceHeading = 0.0; // 기기 방향 (0-360도)
  final List<double> _headingHistory = []; // 최근 heading 저장 (moving average용)
  double _exitBearing = 0.0; // 끝지점 방향 (0-360도)
  double _angleDiff = 0.0; // 각도 차이 (-180 ~ 180도)
  Position? _currentPosition;

  // 콜백 (UI 업데이트용)
  Function(double deviceHeading, double exitBearing, double angleDiff)?
  onDirectionUpdate;

  bool _isRunning = false;

  /// 서비스 시작
  ///
  /// [exitLat], [exitLng]: 횡단보도 끝지점 좌표
  /// [useEventChannel]: false면 EventChannel 구독을 하지 않음 (외부에서 heading 이벤트 전달)
  Future<bool> start({
    required double exitLat,
    required double exitLng,
    bool useEventChannel = false, // 기본값 false - 외부에서 heading 이벤트 전달
  }) async {
    if (_isRunning) {
      return true;
    }

    _exitLat = exitLat;
    _exitLng = exitLng;

    // 1. 공간음향 서비스 초기화
    await _audioService.initialize();

    // 2. 센서 시작 (네이티브 ROTATION_VECTOR) - EventChannel 구독 없이 메소드만 호출
    try {
      await _channel.invokeMethod('startRotationVector');
    } catch (e) {
      // 무시
    }

    // 3. GPS 위치 추적 시작
    _startLocationTracking();

    // 4. 공간음향은 신호등 상태에 따라 별도로 제어 (start()에서는 초기화만)
    // await _audioService.start(); // 제거 - 신호등 상태에 따라 제어

    _isRunning = true;
    return true;
  }

  /// 공간음향 재생 시작 (신호등이 초록불일 때 호출)
  Future<void> startSpatialAudio() async {
    if (!_isRunning) return;
    await _audioService.start();
  }

  /// 공간음향 재생 중지 (신호등이 빨간불일 때 호출)
  Future<void> stopSpatialAudio() async {
    if (!_isRunning) return;
    await _audioService.stop();
  }

  /// 외부에서 heading 이벤트를 전달받아 처리
  /// YoloTestScreen의 EventChannel 리스너에서 호출해야 함
  void handleHeadingEvent(double heading) {
    if (!_isRunning) return;
    _handleHeadingUpdate(heading);
  }

  /// Heading 업데이트 처리 (Moving Average 적용)
  void _handleHeadingUpdate(double heading) {
    // Heading 스무딩 (Moving Average)
    _headingHistory.add(heading);
    if (_headingHistory.length > _headingHistorySize) {
      _headingHistory.removeAt(0);
    }

    // 원형 평균 계산 (0-360도 고려)
    final smoothedHeading = _calculateCircularMean(_headingHistory);
    _deviceHeading = smoothedHeading;

    // 각도 차이 재계산
    _updateAngleDiff();
  }

  /// 각도의 원형 평균 계산 (0-360도 고려)
  double _calculateCircularMean(List<double> angles) {
    if (angles.isEmpty) return 0;

    double sinSum = 0;
    double cosSum = 0;

    for (final angle in angles) {
      final rad = angle * math.pi / 180;
      sinSum += math.sin(rad);
      cosSum += math.cos(rad);
    }

    final meanRad = math.atan2(sinSum, cosSum);
    double meanDeg = meanRad * 180 / math.pi;

    if (meanDeg < 0) meanDeg += 360;
    return meanDeg;
  }

  /// GPS 위치 추적 시작
  void _startLocationTracking() {
    // getPositionStream 사용 (폴링 방식보다 효율적)
    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 1, // 1m 이동시에만 업데이트
          ),
        ).listen(
          (Position position) {
            _currentPosition = position;
            _updateExitBearing(position);
          },
          onError: (error) {
            // 무시
          },
        );
  }

  /// 끝지점 방향 계산 (현재 위치 → 끝지점)
  void _updateExitBearing(Position position) {
    if (_exitLat == null || _exitLng == null) return;

    // Geolocator의 bearingBetween 사용
    double bearing = Geolocator.bearingBetween(
      position.latitude,
      position.longitude,
      _exitLat!,
      _exitLng!,
    );

    // 0-360 범위로 정규화
    if (bearing < 0) bearing += 360;

    _exitBearing = bearing;

    // 각도 차이 재계산
    _updateAngleDiff();
  }

  /// 각도 차이 계산 및 공간음향 업데이트
  void _updateAngleDiff() {
    // 끝지점 방향 - 기기 방향 = 상대 각도
    // 양수 = 오른쪽, 음수 = 왼쪽
    double diff = _exitBearing - _deviceHeading;

    // -180 ~ 180 범위로 정규화
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;

    // 부호 반전 제거: 안드로이드 네이티브 센서 사용으로 정방향 계산
    _angleDiff = diff;

    // 공간음향 패닝 업데이트 (재생 중일 때만)
    if (_audioService.isPlaying) {
      _audioService.updateDirection(_angleDiff);
    }

    // 콜백 호출 (UI 업데이트용)
    onDirectionUpdate?.call(_deviceHeading, _exitBearing, _angleDiff);
  }

  /// 서비스 중지
  Future<void> stop() async {
    if (!_isRunning) return;

    try {
      await _channel.invokeMethod('stopRotationVector');
    } catch (e) {
      // 무시
    }

    await _positionSubscription?.cancel();
    _positionSubscription = null;

    // 공간음향 중지
    await _audioService.stop();

    _isRunning = false;
  }

  /// 리소스 해제
  void dispose() {
    stop();
    _audioService.dispose();
  }

  // Getters
  bool get isRunning => _isRunning;
  double get deviceHeading => _deviceHeading;
  double get exitBearing => _exitBearing;
  double get angleDiff => _angleDiff;
  Position? get currentPosition => _currentPosition;
}
