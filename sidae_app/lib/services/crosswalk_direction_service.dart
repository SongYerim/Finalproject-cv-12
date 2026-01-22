import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'spatial_audio_service.dart';

/// 횡단보도 방향 안내 서비스
///
/// IMU 센서와 GPS를 사용하여 기기 방향 대비 횡단보도 끝지점의
/// 상대 각도를 계산하고, 공간음향으로 방향을 안내합니다.
class CrosswalkDirectionService {
  final SpatialAudioService _audioService = SpatialAudioService.instance;

  // 횡단보도 끝지점 좌표
  double? _exitLat;
  double? _exitLng;

  // 센서 및 GPS 스트림 구독
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;
  StreamSubscription<Position?>? _positionSubscription;

  // 현재 상태
  double _deviceHeading = 0.0; // 기기 방향 (0-360도)
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
  Future<bool> start({
    required double exitLat,
    required double exitLng,
  }) async {
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

    // 2. 자기장 센서 시작 (기기 방향)
    _startMagnetometerListening();

    // 3. GPS 위치 추적 시작
    _startLocationTracking();

    // 4. 공간음향 재생 시작
    await _audioService.start();

    _isRunning = true;
    return true;
  }

  /// 자기장 센서 리스닝 시작
  void _startMagnetometerListening() {
    _magnetometerSubscription = magnetometerEventStream(
      samplingPeriod: const Duration(milliseconds: 100),
    ).listen(
      (MagnetometerEvent event) {
        _updateDeviceHeading(event);
      },
      onError: (error) {
        debugPrint('❌ 자기장 센서 에러: $error');
      },
    );
    debugPrint('✅ 자기장 센서 리스닝 시작');
  }

  /// 기기 방향 계산 (자기장 센서 기반)
  void _updateDeviceHeading(MagnetometerEvent event) {
    // 나침반 방향 계산
    // atan2(y, x)로 각도 계산 후 북쪽(0도) 기준으로 변환
    double heading = math.atan2(event.y, event.x);
    heading = heading * (180 / math.pi); // 라디안 → 도
    heading = 90 - heading; // 북쪽 기준으로 변환

    // 0-360 범위로 정규화
    if (heading < 0) heading += 360;
    if (heading >= 360) heading -= 360;

    _deviceHeading = heading;

    // 각도 차이 재계산
    _updateAngleDiff();
  }

  /// GPS 위치 추적 시작
  void _startLocationTracking() {
    // 500ms 간격으로 위치 업데이트
    _positionSubscription = Stream.periodic(
      const Duration(milliseconds: 500),
      (count) => count,
    ).asyncMap((_) async {
      try {
        return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
      } catch (e) {
        debugPrint('❌ GPS 위치 가져오기 실패: $e');
        return null;
      }
    }).listen((Position? position) {
      if (position != null) {
        _currentPosition = position;
        _updateExitBearing(position);
      }
    });
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
    double diff = _exitBearing - _deviceHeading;

    // -180 ~ 180 범위로 정규화
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;

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
    await _magnetometerSubscription?.cancel();
    _magnetometerSubscription = null;

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
