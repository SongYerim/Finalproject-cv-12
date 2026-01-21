import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import '../services/route_tracker.dart';

/// GPS 및 센서 기반 네비게이션 서비스 (하이브리드: 센서=네이티브, GPS=Geolocator)
class NavigationService {
  // 네이티브 채널
  static const MethodChannel _channel = MethodChannel(
    'com.ctrlcv.sidae_app/yolo_native',
  );
  static const EventChannel _eventChannel = EventChannel(
    'com.ctrlcv.sidae_app/yolo_detections',
  );

  StreamSubscription? _nativeEventSubscription;
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

  /// 센서 초기화 (네이티브 Magnetometer 사용)
  void initSensor() {
    _startNativeNavigation();
    _startNativeEventListening();
  }

  /// 네이티브 Navigation 시작
  Future<void> _startNativeNavigation() async {
    try {
      await _channel.invokeMethod('startNavigation');
      print('✅ 네이티브 센서 Navigation 시작됨');
    } catch (e) {
      print('❌ 네이티브 센서 Navigation 시작 실패: $e');
    }
  }

  /// 네이티브 EventChannel 리스닝 시작
  void _startNativeEventListening() {
    _nativeEventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (result) {
        if (result is Map && result['type'] == 'navigation') {
          deviceHeading = (result['deviceHeading'] as num?)?.toDouble() ?? 0.0;
          // routeBearing과 travelingBearing은 Flutter에서 계산 (기존 로직 유지)
          onBearingUpdate?.call();
        }
      },
      onError: (error) {
        print('❌ Navigation EventChannel 에러: $error');
      },
    );
  }

  /// GPS 위치 추적 시작 (Geolocator 사용 - 기존 호환성 유지)
  void startLocationTracking({required Function(Position) onUpdate}) {
    onPositionUpdate = onUpdate;

    _positionSubscription =
        Stream.periodic(const Duration(milliseconds: 500), (count) => count)
            .asyncMap((_) async {
              return await Geolocator.getCurrentPosition(
                desiredAccuracy: LocationAccuracy.high,
              );
            })
            .listen((Position position) {
              _updateRecentPositions(position);
              _calculateTravelingBearing();
              _updateRouteBearing(position);
              onPositionUpdate?.call(position);
            });
  }

  /// GPS 위치 추적 중지 (센서는 유지)
  void stopLocationTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _recentPositions.clear();
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

  /// 목표 좌표 업데이트 (네이티브)
  Future<void> updateTarget(NLatLng target) async {
    try {
      await _channel.invokeMethod('updateNavigationTarget', {
        'targetLat': target.latitude,
        'targetLng': target.longitude,
      });
    } catch (e) {
      print('❌ Navigation 타겟 업데이트 실패: $e');
    }
  }

  /// 리소스 정리
  void dispose() {
    _positionSubscription?.cancel();
    _nativeEventSubscription?.cancel();
    _positionSubscription = null;
    _nativeEventSubscription = null;

    // 네이티브 Navigation 중지
    _channel.invokeMethod('stopNavigation').catchError((e) {
      print('❌ 네이티브 Navigation 중지 실패: $e');
    });
  }
}
