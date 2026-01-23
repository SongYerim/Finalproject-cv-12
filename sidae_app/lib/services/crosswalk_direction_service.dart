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
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<Position?>? _positionSubscription;

  // 센서 데이터 버퍼 (가속도계와 자기장 센서 동기화)
  AccelerometerEvent? _lastAccelerometer;
  MagnetometerEvent? _lastMagnetometer;

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

    // 2. 센서 시작 (가속도계 + 자기장 센서)
    _startAccelerometerListening();
    _startMagnetometerListening();

    // 3. GPS 위치 추적 시작
    _startLocationTracking();

    // 4. 공간음향 재생 시작
    await _audioService.start();

    _isRunning = true;
    return true;
  }

  /// 가속도계 리스닝 시작
  void _startAccelerometerListening() {
    _accelerometerSubscription = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 100),
    ).listen(
      (AccelerometerEvent event) {
        _lastAccelerometer = event;
        _calculateHeadingWithOrientation();
      },
      onError: (error) {
        debugPrint('❌ 가속도계 센서 에러: $error');
      },
    );
    debugPrint('✅ 가속도계 센서 리스닝 시작');
  }

  /// 자기장 센서 리스닝 시작
  void _startMagnetometerListening() {
    _magnetometerSubscription = magnetometerEventStream(
      samplingPeriod: const Duration(milliseconds: 100),
    ).listen(
      (MagnetometerEvent event) {
        _lastMagnetometer = event;
        _calculateHeadingWithOrientation();
      },
      onError: (error) {
        debugPrint('❌ 자기장 센서 에러: $error');
      },
    );
    debugPrint('✅ 자기장 센서 리스닝 시작');
  }

  /// 기기 방향 계산 (가속도계 + 자기장 센서 기반, 자세 보정)
  ///
  /// 가속도계와 자기장 센서를 함께 사용하여 폰의 자세(orientation)와
  /// 상관없이 항상 동일한 지구 좌표계 기준 방향을 계산합니다.
  /// 회전 행렬을 사용하여 기기 좌표계를 지구 좌표계로 변환합니다.
  void _calculateHeadingWithOrientation() {
    if (_lastAccelerometer == null || _lastMagnetometer == null) {
      return;
    }

    // 가속도계 데이터 (중력 방향 포함)
    final accel = _lastAccelerometer!;
    final magnet = _lastMagnetometer!;

    // 회전 행렬 계산을 위한 벡터 정규화
    // 가속도계 벡터 (중력 방향)
    final gravity = [accel.x, accel.y, accel.z];
    final gravityNorm = math.sqrt(
      gravity[0] * gravity[0] +
      gravity[1] * gravity[1] +
      gravity[2] * gravity[2],
    );

    if (gravityNorm < 0.1) {
      // 중력이 너무 작으면 센서 데이터가 불안정
      return;
    }

    // 자기장 벡터
    final magnetic = [magnet.x, magnet.y, magnet.z];
    final magneticNorm = math.sqrt(
      magnetic[0] * magnetic[0] +
      magnetic[1] * magnetic[1] +
      magnetic[2] * magnetic[2],
    );

    if (magneticNorm < 0.1) {
      // 자기장이 너무 작으면 계산 불가
      return;
    }

    // 정규화
    final gx = gravity[0] / gravityNorm;
    final gy = gravity[1] / gravityNorm;
    final gz = gravity[2] / gravityNorm;

    final mx = magnetic[0] / magneticNorm;
    final my = magnetic[1] / magneticNorm;
    final mz = magnetic[2] / magneticNorm;

    // 수평면에서의 자기장 벡터 계산
    // 중력에 수직인 평면에서의 자기장 성분 (수평 성분)
    final dotProduct = mx * gx + my * gy + mz * gz;
    final hx = mx - gx * dotProduct;
    final hy = my - gy * dotProduct;
    final hz = mz - gz * dotProduct;

    final hNorm = math.sqrt(hx * hx + hy * hy + hz * hz);
    if (hNorm < 0.1) {
      return;
    }

    // 정규화된 수평면 자기장 벡터
    final hxNorm = hx / hNorm;
    final hyNorm = hy / hNorm;
    final hzNorm = hz / hNorm;

    // Android SensorManager.getRotationMatrix() 방식으로 회전 행렬 계산
    // 회전 행렬 R: 기기 좌표계 → 지구 좌표계 변환
    // R의 각 행은 지구 좌표계의 단위 벡터를 기기 좌표계로 표현한 것
    
    // Up 벡터 (지구 좌표계의 위쪽) = 중력 방향 (기기 좌표계)
    final upX = gx;
    final upY = gy;
    final upZ = gz;

    // 수평면 자기장 벡터를 사용하여 East 벡터 계산
    // East = Up × 수평면 자기장 (외적)
    final eastX = upY * hzNorm - upZ * hyNorm;
    final eastY = upZ * hxNorm - upX * hzNorm;
    final eastZ = upX * hyNorm - upY * hxNorm;
    
    final eastNorm = math.sqrt(eastX * eastX + eastY * eastY + eastZ * eastZ);
    if (eastNorm < 0.1) {
      // East 벡터가 너무 작으면 계산 불가
      return;
    }

    // 정규화된 East 벡터
    final eastXNorm = eastX / eastNorm;
    final eastYNorm = eastY / eastNorm;
    final eastZNorm = eastZ / eastNorm;

    // North 벡터 = Up × East (외적)
    final northX = upY * eastZNorm - upZ * eastYNorm;
    final northY = upZ * eastXNorm - upX * eastZNorm;
    final northZ = upX * eastYNorm - upY * eastXNorm;

    // North 벡터 정규화
    final northNorm = math.sqrt(northX * northX + northY * northY + northZ * northZ);
    if (northNorm < 0.1) {
      return;
    }
    final northXNorm = northX / northNorm;
    final northYNorm = northY / northNorm;
    final northZNorm = northZ / northNorm;

    // 폰의 Y축(앞 방향)을 지구 좌표계로 변환
    // 폰의 Y축 단위 벡터 (0, 1, 0)
    // 회전 행렬의 전치를 사용하여 변환
    // Y축의 East 성분 = East 벡터의 Y 성분
    // Y축의 North 성분 = North 벡터의 Y 성분
    final yAxisEast = eastYNorm;
    final yAxisNorth = northYNorm;

    // 방향 계산 (atan2(-East, North))
    // 표준 나침반 방향: 북=0°, 동=90°, 남=180°, 서=270°
    // 왼쪽으로 돌리면 heading 감소, 오른쪽으로 돌리면 heading 증가
    double heading = math.atan2(-yAxisEast, yAxisNorth);

    // 라디안 → 도 변환
    heading = heading * (180 / math.pi);

    // 0-360 범위로 정규화
    if (heading < 0) heading += 360;
    if (heading >= 360) heading -= 360;

    // 디버깅: 값이 변하는지 확인
    debugPrint('🧭 방향 계산: yAxisEast=${yAxisEast.toStringAsFixed(3)}, yAxisNorth=${yAxisNorth.toStringAsFixed(3)}, heading=${heading.toStringAsFixed(1)}°');

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

    await _accelerometerSubscription?.cancel();
    _accelerometerSubscription = null;

    await _positionSubscription?.cancel();
    _positionSubscription = null;

    // 센서 데이터 버퍼 초기화
    _lastAccelerometer = null;
    _lastMagnetometer = null;

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
