import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'spatial_audio_service.dart';

/// 횡단보도 방향 안내 서비스
///
/// IMU 센서와 GPS를 사용하여 기기 방향 대비 횡단보도 끝지점의
/// 상대 각도를 계산하고, 공간음향으로 방향을 안내합니다.
class CrosswalkDirectionService {
  // 상수
  static const int _headingHistorySize = 5; // Moving average 크기

  // 네이티브 채널
  static const MethodChannel _channel = MethodChannel(
    'com.ctrlcv.sidae_app/yolo_native',
  );
  static const EventChannel _eventChannel = EventChannel(
    'com.ctrlcv.sidae_app/yolo_detections',
  );

  final SpatialAudioService _audioService = SpatialAudioService.instance;

  // 횡단보도 끝지점 좌표
  double? _exitLat;
  double? _exitLng;

  // 스트림 구독
  StreamSubscription? _nativeEventSubscription;
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
  Future<bool> start({required double exitLat, required double exitLng}) async {
    if (_isRunning) {
      debugPrint('⚠️ 방향 안내 서비스가 이미 실행 중');
      return true;
    }

    _exitLat = exitLat;
    _exitLng = exitLng;

    debugPrint('🧭 횡단보도 방향 안내 시작');
    debugPrint('📍 끝지점: ($exitLat, $exitLng)');

    // 1. 공간음향 서비스 초기화
    final audioInitialized = await _audioService.initialize();
    if (!audioInitialized) {
      debugPrint('❌ 공간음향 초기화 실패');
      // 오디오 없이도 계속 진행 (방향 계산은 가능)
    }

    // 2. 센서 시작 (네이티브 ROTATION_VECTOR)
    _startNativeSensor();

    // 3. GPS 위치 추적 시작
    _startLocationTracking();

    // 4. 공간음향 재생 시작
    await _audioService.start();

    _isRunning = true;
    return true;
  }

  /// 네이티브 센서 시작 및 리스닝
  Future<void> _startNativeSensor() async {
    try {
      await _channel.invokeMethod('startRotationVector');
      debugPrint('✅ ROTATION_VECTOR 센서 시작됨');
    } catch (e) {
      debugPrint('❌ ROTATION_VECTOR 시작 실패: $e');
    }

    _nativeEventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Map && event['type'] == 'heading') {
          final heading = (event['heading'] as num).toDouble();
          _handleHeadingUpdate(heading);
        }
      },
      onError: (error) {
        debugPrint('❌ EventChannel 에러: $error');
      },
    );
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
            debugPrint('❌ GPS 에러: $error');
          },
        );
    debugPrint('✅ GPS 위치 추적 시작');
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

    // 공간음향 패닝 업데이트
    _audioService.updateDirection(_angleDiff);

    // 콜백 호출 (UI 업데이트용)
    onDirectionUpdate?.call(_deviceHeading, _exitBearing, _angleDiff);
  }

  /// 서비스 중지
  Future<void> stop() async {
    if (!_isRunning) return;

    debugPrint('🛑 횡단보도 방향 안내 중지');

    // 스트림 구독 해제
    await _nativeEventSubscription?.cancel();
    _nativeEventSubscription = null;

    try {
      await _channel.invokeMethod('stopRotationVector');
      debugPrint('🛑 ROTATION_VECTOR 센서 중지됨');
    } catch (e) {
      debugPrint('❌ ROTATION_VECTOR 중지 실패: $e');
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
