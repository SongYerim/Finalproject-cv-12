import 'dart:async';
import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../services/route_tracker.dart';

/// GPS 및 센서 기반 네비게이션 서비스
class NavigationService {
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;
  StreamSubscription<Position>? _positionSubscription;

  final RouteTracker _tracker = RouteTracker.instance;

  // 방향 관련 변수
  double deviceHeading = 0.0;
  double targetBearing = 0.0;
  double routeBearing = -1.0;
  double travelingBearing = -1.0;

  // GPS 기반 방향 계산용
  List<Position> _recentPositions = [];
  static const double _minDistanceForBearing = 1.0;

  // 콜백 함수들
  Function(Position)? onPositionUpdate;
  Function()? onBearingUpdate;

  /// 센서 초기화 (나침반)
  void initSensor() {
    _magnetometerSubscription = magnetometerEvents.listen((MagnetometerEvent event) {
      double heading = math.atan2(event.y, event.x);
      heading = heading * (180 / math.pi);
      heading = 90 - heading;
      if (heading < 0) heading += 360;
      if (heading >= 360) heading -= 360;

      deviceHeading = heading;
      onBearingUpdate?.call();
    });
  }

  /// GPS 위치 추적 시작
  void startLocationTracking({
    required Function(Position) onUpdate,
  }) {
    onPositionUpdate = onUpdate;

    _positionSubscription = Stream.periodic(
      const Duration(milliseconds: 500),
      (count) => count,
    ).asyncMap((_) async {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    }).listen((Position position) {
      _updateRecentPositions(position);
      _calculateTravelingBearing();
      _updateRouteBearing(position);
      onPositionUpdate?.call(position);
    });
  }

  /// 최근 GPS 좌표 저장
  void _updateRecentPositions(Position position) {
    _recentPositions.add(position);
    if (_recentPositions.length > 2) {
      _recentPositions.removeAt(0);
    }
  }

  /// 진행 방향 계산 (GPS 기반)
  void _calculateTravelingBearing() {
    if (_recentPositions.length < 2) return;

    final prev = _recentPositions[0];
    final curr = _recentPositions[1];

    double distance = Geolocator.distanceBetween(
      prev.latitude,
      prev.longitude,
      curr.latitude,
      curr.longitude,
    );

    if (distance < _minDistanceForBearing) return;

    double bearing = Geolocator.bearingBetween(
      prev.latitude,
      prev.longitude,
      curr.latitude,
      curr.longitude,
    );
    if (bearing < 0) bearing += 360;

    travelingBearing = bearing;
  }

  /// 경로상 가야 할 방향 계산
  void _updateRouteBearing(Position currentPosition) {
    if (_tracker.allPathPoints.isEmpty) return;

    final targetPoint = _tracker.getCurrentTarget();
    if (targetPoint == null) return;

    double bearing = Geolocator.bearingBetween(
      currentPosition.latitude,
      currentPosition.longitude,
      targetPoint.latitude,
      targetPoint.longitude,
    );
    if (bearing < 0) bearing += 360;

    routeBearing = bearing;
    targetBearing = bearing;
  }

  /// 현재 목표까지의 거리 계산
  double getDistanceToTarget(Position position) {
    final targetPoint = _tracker.getCurrentTarget();
    if (targetPoint == null) return 0.0;

    return Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      targetPoint.latitude,
      targetPoint.longitude,
    );
  }

  /// 리소스 정리
  void dispose() {
    _magnetometerSubscription?.cancel();
    _positionSubscription?.cancel();
    _magnetometerSubscription = null;
    _positionSubscription = null;
  }
}
