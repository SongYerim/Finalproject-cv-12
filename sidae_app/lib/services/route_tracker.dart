// lib/services/route_tracker.dart
import 'package:flutter_naver_map/flutter_naver_map.dart';

/// 4.dart와 5.dart가 공유하는 경로 추적 상태 관리 클래스
class RouteTracker {
  static RouteTracker? _instance;
  static RouteTracker get instance => _instance ??= RouteTracker._();
  RouteTracker._();

  // 경로상의 모든 점들
  List<NLatLng> allPathPoints = [];

  // 각 점의 상태: true = 지나감, false = 아직 안 지나감
  List<bool> pointsPassed = [];

  // 현재 목표 인덱스 (다음에 지나가야 할 점)
  int currentTargetIndex = 0;

  // 초기화 여부 플래그
  bool _isInitialized = false;

  /// 경로 초기화 (이미 초기화되어 있으면 건너뜀)
  void initialize(List<NLatLng> pathPoints) {
    // 이미 같은 경로가 로드되어 있으면 초기화하지 않음
    if (_isInitialized && _isSameRoute(pathPoints)) {
      return;
    }

    allPathPoints = pathPoints;
    pointsPassed = List.filled(pathPoints.length, false);
    currentTargetIndex = 0;
    _isInitialized = true;
  }

  /// 같은 경로인지 확인 (첫 점, 마지막 점, 길이로 비교)
  bool _isSameRoute(List<NLatLng> newPathPoints) {
    if (allPathPoints.isEmpty || newPathPoints.isEmpty) return false;
    if (allPathPoints.length != newPathPoints.length) return false;

    // 첫 점과 마지막 점이 같은지 확인
    final firstSame =
        allPathPoints.first.latitude == newPathPoints.first.latitude &&
        allPathPoints.first.longitude == newPathPoints.first.longitude;
    final lastSame =
        allPathPoints.last.latitude == newPathPoints.last.latitude &&
        allPathPoints.last.longitude == newPathPoints.last.longitude;

    return firstSame && lastSame;
  }

  /// 특정 인덱스를 "지나감"으로 표시
  void markAsPassed(int index) {
    if (index >= 0 && index < pointsPassed.length) {
      pointsPassed[index] = true;
    }
  }

  /// 특정 인덱스까지의 모든 점을 "지나감"으로 표시
  /// (경로를 건너뛰었을 때 이전 점들도 모두 처리)
  void markAllPassedUpTo(int index) {
    for (int i = 0; i <= index && i < pointsPassed.length; i++) {
      pointsPassed[i] = true;
    }
  }

  /// 다음 목표로 이동
  void moveToNextTarget() {
    if (currentTargetIndex < allPathPoints.length - 1) {
      currentTargetIndex++;
    }
  }

  /// 현재 목표 좌표 가져오기
  NLatLng? getCurrentTarget() {
    if (currentTargetIndex >= 0 && currentTargetIndex < allPathPoints.length) {
      return allPathPoints[currentTargetIndex];
    }
    return null;
  }

  /// 상태 초기화 (새로운 경로 시작 시)
  void reset() {
    allPathPoints = [];
    pointsPassed = [];
    currentTargetIndex = 0;
    _isInitialized = false;
  }

  /// 진행률 계산
  double getProgress() {
    if (allPathPoints.isEmpty) return 0.0;
    int passedCount = pointsPassed.where((passed) => passed).length;
    return passedCount / allPathPoints.length;
  }

  /// 현재 위치에서 가장 가까운 점을 찾아 업데이트
  ///
  /// [latitude], [longitude]: 현재 위치
  /// [distanceCalculator]: 두 좌표 간 거리 계산 함수 (Geolocator.distanceBetween)
  /// [passThreshold]: 통과로 인정하는 거리 (미터, 기본값 15.0)
  ///
  /// 반환값: 업데이트가 발생했으면 true, 아니면 false
  bool findClosestPointAndUpdate(
    double latitude,
    double longitude,
    double Function(double lat1, double lon1, double lat2, double lon2)
    distanceCalculator, {
    double passThreshold = 15.0,
  }) {
    if (allPathPoints.isEmpty) return false;

    // 현재 목표부터 끝까지 모든 점들을 스캔하여 가장 가까운 점 찾기
    int closestIndex = -1;
    double closestDistance = double.infinity;

    for (int i = currentTargetIndex; i < allPathPoints.length; i++) {
      double distance = distanceCalculator(
        latitude,
        longitude,
        allPathPoints[i].latitude,
        allPathPoints[i].longitude,
      );

      if (distance < closestDistance) {
        closestDistance = distance;
        closestIndex = i;
      }
    }

    // 가장 가까운 점이 임계값 이내면 해당 점까지 모두 통과 처리
    if (closestIndex >= 0 && closestDistance <= passThreshold) {
      // 가장 가까운 점까지의 모든 점을 통과 처리
      markAllPassedUpTo(closestIndex);
      // 다음 목표를 가장 가까운 점 다음으로 설정
      if (closestIndex + 1 < allPathPoints.length) {
        currentTargetIndex = closestIndex + 1;
      }
      return true;
    }

    return false;
  }
}
