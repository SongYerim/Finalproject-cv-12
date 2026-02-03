import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import '../services/route_tracker.dart';
import '../services/shared_event_channel.dart';

/// GPS 및 센서 기반 네비게이션 서비스 (싱글톤)
class NavigationService {
  // 싱글톤 인스턴스
  static final NavigationService _instance = NavigationService._internal();
  static NavigationService get instance => _instance;

  // private 생성자
  NavigationService._internal();

  // 네이티브 채널
  static const MethodChannel _channel = MethodChannel(
    'com.ctrlcv.sidae_app/yolo_native',
  );

  StreamSubscription? _nativeEventSubscription;
  StreamSubscription<Position>? _positionSubscription;

  final RouteTracker _tracker = RouteTracker.instance;

  // 방향 관련 변수
  double deviceHeading = 0.0;
  double targetBearing = 0.0;
  double routeBearing = -1.0;
  double travelingBearing = -1.0;

  // GPS 기반 방향 계산 제거 (센서 사용)

  // 콜백 함수들
  Function(Position)? onPositionUpdate;
  Function()? onBearingUpdate;

  // 초기화 상태 플래그
  bool _sensorInitialized = false;

  /// 센서 초기화 (네이티브 Magnetometer 사용)
  void initSensor() {
    // 이미 초기화되었으면 스킵
    if (_sensorInitialized) {
      print('✅ 센서 이미 초기화됨 - 스킵');
      return;
    }
    _sensorInitialized = true;
    _startNativeNavigation();
    _startNativeEventListening();
  }

  /// 센서가 실행 중인지 확인하고 필요 시 재시작 (화면 복귀 시 호출)
  Future<void> ensureSensorRunning() async {
    print('🔄 센서 재시작 (화면 복귀)');

    // 기존 구독 취소 (SharedEventChannel의 브로드캐스트 스트림에서 구독 해제)
    _nativeEventSubscription?.cancel();
    _nativeEventSubscription = null;

    if (!_sensorInitialized) {
      _sensorInitialized = true;
    }

    // 네이티브 Navigation 재시작
    await _startNativeNavigation();

    // EventChannel 리스닝 재시작 (공유 브로드캐스트 스트림 사용)
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

  /// 네이티브 EventChannel 리스닝 시작 (SharedEventChannel 사용)
  void _startNativeEventListening() {
    print('🎧 [NavigationService] SharedEventChannel 구독 시작');
    // 공유 브로드캐스트 스트림 사용 - 여러 리스너가 취소해도 네이티브 onCancel 안 됨
    _nativeEventSubscription = SharedEventChannel.instance.stream.listen(
      (result) {
        if (result is Map && result['type'] == 'navigation') {
          deviceHeading = (result['deviceHeading'] as num?)?.toDouble() ?? 0.0;
          // 진행 방향 = 디바이스 방향 (센서 기반)
          travelingBearing = deviceHeading;
          // 디버그: onBearingUpdate 호출 확인 (60Hz이면 많은 로그가 출력됨)
          // print('🧭 deviceHeading: $deviceHeading, callback: ${onBearingUpdate != null}');
          onBearingUpdate?.call();
        }
      },
      onError: (error) {
        print('❌ Navigation EventChannel 에러: $error');
      },
    );
  }

  /// GPS 위치 추적 시작 (위치와 경로 방향만 계산)
  void startLocationTracking({required Function(Position) onUpdate}) {
    onPositionUpdate = onUpdate;

    // 이미 추적 중이면 콜백만 갱신
    if (_positionSubscription != null) {
      print('✅ GPS 추적 이미 진행 중 - 콜백만 갱신');
      return;
    }

    _positionSubscription = Stream.periodic(const Duration(milliseconds: 500))
        .asyncMap((_) async {
          return await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          );
        })
        .listen((Position position) {
          _updateRouteBearing(position);
          onPositionUpdate?.call(position);
        });
  }

  /// GPS 위치 추적 중지 (센서는 유지)
  void stopLocationTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
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
