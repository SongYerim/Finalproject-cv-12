// lib/services/route_tracker.dart
import 'package:flutter_naver_map/flutter_naver_map.dart';
// import 'dart:developer' as developer;
import '../models/route_model.dart';
import '../constants.dart';

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

  // ========== 구간/단계 추적 (NEW) ==========

  // 전체 경로 세그먼트 (도보/버스 구간)
  List<RouteSegment> routes = [];

  // 현재 진행 중인 구간 인덱스 (도보/버스 세그먼트)
  int currentSegmentIndex = 0;

  // 현재 구간 내 단계 인덱스
  int currentStepIndex = 0;

  // 콜백: 구간/단계 변경 시 알림 (TTS 안내용)
  Function(int segmentIndex, int stepIndex, String description)? onStepChanged;

  // 콜백: 최종 목적지 도착 시 알림
  Function()? onRouteCompleted;

  // 경로 완료 여부 (중복 호출 방지)
  bool _isRouteCompleted = false;
  bool get isRouteCompleted => _isRouteCompleted;

  /// 현재 버스/지하철 구간인지 여부 (도보 경로 감지 건너뛰기용)
  bool get isOnBusSegment {
    final segment = getCurrentSegment();
    final isBus = segment?.moveType == 'BUS' || segment?.moveType == 'SUBWAY';
    // 디버그: 현재 구간 정보 출력
    // if (segment != null) {
    // print(
    //   '🚌 [RouteTracker] 현재 구간: ${segment.segmentIndex}, moveType: ${segment.moveType}, isOnBusSegment: $isBus',
    // );
    // }
    return isBus;
  }

  /// 명시적 버스 탑승 상태 (7.dart에서 승차 시 true, 8.dart에서 하차 시 false)
  bool _isOnBus = false;
  bool get isOnBus => _isOnBus;

  /// 버스 탑승 상태 설정
  void setOnBus(bool value) {
    _isOnBus = value;
    // print('🚌 [RouteTracker] setOnBus($value) - 버스 탑승 상태 변경');
  }

  // 이전에 안내한 단계 (중복 안내 방지)
  int _lastAnnouncedSegment = -1;
  int _lastAnnouncedStep = -1;

  /// 경로 초기화 (이미 초기화되어 있으면 건너뜀)
  void initialize(
    List<NLatLng> pathPoints, {
    List<RouteSegment>? routeSegments,
  }) {
    // 이미 같은 경로가 로드되어 있으면 초기화하지 않음
    if (_isInitialized && _isSameRoute(pathPoints)) {
      return;
    }

    allPathPoints = pathPoints;
    pointsPassed = List.filled(pathPoints.length, false);
    currentTargetIndex = 0;

    // 세그먼트 정보 저장
    if (routeSegments != null) {
      routes = routeSegments;
      currentSegmentIndex = 0;
      currentStepIndex = 0;
      _lastAnnouncedSegment = -1;
      _lastAnnouncedStep = -1;
    }

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
    routes = [];
    currentSegmentIndex = 0;
    currentStepIndex = 0;
    _lastAnnouncedSegment = -1;
    _lastAnnouncedStep = -1;
    _isInitialized = false;
    _isRouteCompleted = false;
    _isOnBus = false; // 버스 탑승 상태 초기화
  }

  /// 진행률 계산
  double getProgress() {
    if (allPathPoints.isEmpty) return 0.0;
    int passedCount = pointsPassed.where((passed) => passed).length;
    return passedCount / allPathPoints.length;
  }

  /// 현재 구간 가져오기
  RouteSegment? getCurrentSegment() {
    if (routes.isEmpty || currentSegmentIndex >= routes.length) return null;
    return routes[currentSegmentIndex];
  }

  /// 다음 단계로 이동 (TTS 안내 트리거)
  void moveToNextStep() {
    if (routes.isEmpty) return;

    final currentSegment = routes[currentSegmentIndex];

    // 현재 구간 내 단계 이동
    if (currentStepIndex < currentSegment.stepDescription.length - 1) {
      currentStepIndex++;
      _announceCurrentStep();
    }
    // 다음 구간으로 이동
    else if (currentSegmentIndex < routes.length - 1) {
      currentSegmentIndex++;
      currentStepIndex = 0;
      _announceCurrentStep();
    }
  }

  /// 구간 인덱스로 직접 이동
  void moveToSegment(int segmentIndex) {
    if (segmentIndex >= 0 && segmentIndex < routes.length) {
      currentSegmentIndex = segmentIndex;
      currentStepIndex = 0;
      _announceCurrentStep();
    }
  }

  /// 현재 단계 안내 (중복 방지)
  void _announceCurrentStep() {
    if (_lastAnnouncedSegment == currentSegmentIndex &&
        _lastAnnouncedStep == currentStepIndex) {
      return; // 이미 안내함
    }

    _lastAnnouncedSegment = currentSegmentIndex;
    _lastAnnouncedStep = currentStepIndex;

    final segment = getCurrentSegment();
    if (segment == null) return;

    String description;
    if (segment.stepDescription.isNotEmpty &&
        currentStepIndex < segment.stepDescription.length) {
      description = segment.stepDescription[currentStepIndex];
    } else {
      description = segment.description;
    }

    onStepChanged?.call(currentSegmentIndex, currentStepIndex, description);

    // 최종 목적지 도착 체크: 마지막 구간의 마지막 단계
    _checkRouteCompletion();
  }

  /// 경로 완료 여부 체크 및 콜백 호출
  void _checkRouteCompletion() {
    if (_isRouteCompleted) return; // 이미 완료됨
    if (routes.isEmpty) return;

    // 수정: 단순히 마지막 단계(isLastStep)에 진입했다고 해서 완료 처리하면 안 됨.
    // 경로의 마지막 지점(좌표)을 실제로 통과했는지 확인해야 함.
    // developer.log('🚩pointsPassed: $pointsPassed');
    // developer.log('🚩pointsPassed.last: ${pointsPassed.last}');
    if (pointsPassed.isNotEmpty && pointsPassed.last) {
      // developer.log('🚩 [RouteTracker] 최종 목적지 좌표 도달 확인', name: 'RouteTracker');
      _isRouteCompleted = true;
      onRouteCompleted?.call();
    }
  }

  /// 초기 구간 안내 (화면 진입 시)
  void announceInitialStep() {
    if (routes.isEmpty) return;
    _announceCurrentStep();
  }

  /// 현재 위치에서 가장 가까운 점을 찾아 업데이트
  ///
  /// [latitude], [longitude]: 현재 위치
  /// [distanceCalculator]: 두 좌표 간 거리 계산 함수 (Geolocator.distanceBetween)
  /// [passThreshold]: 통과로 인정하는 거리 (미터, 기본값 kProximityThreshold)
  ///
  /// 반환값: 업데이트가 발생했으면 true, 아니면 false
  bool findClosestPointAndUpdate(
    double latitude,
    double longitude,
    double Function(double lat1, double lon1, double lat2, double lon2)
    distanceCalculator, {
    double passThreshold = kProximityThreshold,
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

      // 구간 업데이트 (경로 점과 구간을 매핑)
      _updateSegmentFromPointIndex(closestIndex);

      // 위치가 업데이트되었으므로 완료 여부 체크 (단계 변경이 없어도 체크해야 함)
      _checkRouteCompletion();

      return true;
    }

    return false;
  }

  /// 경로 점 인덱스로부터 구간 및 단계 업데이트
  void _updateSegmentFromPointIndex(int pointIndex) {
    if (routes.isEmpty) return;

    // 각 구간의 경로 점 개수를 누적해서 현재 구간 찾기
    int accumulatedPoints = 0;
    for (int i = 0; i < routes.length; i++) {
      final segment = routes[i];
      final segmentPointCount = segment.pathCoordinates.length;

      if (pointIndex < accumulatedPoints + segmentPointCount) {
        // 구간 내 상대 인덱스
        final pointInSegment = pointIndex - accumulatedPoints;

        // 단계 인덱스 계산: RouteStep의 path 범위 기반
        int newStepIndex = _findStepIndexByPosition(segment, pointInSegment);

        // 구간 또는 단계 변경 감지
        final bool segmentChanged = currentSegmentIndex != i;
        final bool stepChanged = currentStepIndex != newStepIndex;

        if (segmentChanged) {
          currentSegmentIndex = i;
          currentStepIndex = newStepIndex;
          _announceCurrentStep();
        } else if (stepChanged) {
          currentStepIndex = newStepIndex;
          _announceCurrentStep();
        }
        return;
      }
      accumulatedPoints += segmentPointCount;
    }
  }

  /// RouteStep들의 시작점 좌표 기반으로 현재 단계 찾기
  ///
  /// 핵심 로직: 현재 위치가 어떤 step의 시작점(lat/lng)에 도달하면
  /// 해당 step으로 전환하여 description이 시작점에서 안내되도록 함
  int _findStepIndexByPosition(RouteSegment segment, int pointInSegment) {
    // steps 배열이 비어있으면 stepDescription 기반으로 fallback
    if (segment.steps.isEmpty) {
      if (segment.stepDescription.isEmpty) return 0;

      // stepDescription 개수로 균등 분할 (기존 로직)
      final segmentPointCount = segment.pathCoordinates.length;
      final progressInSegment = segmentPointCount > 1
          ? pointInSegment / (segmentPointCount - 1)
          : 0.0;

      int stepIndex = (progressInSegment * segment.stepDescription.length)
          .floor();

      if (stepIndex >= segment.stepDescription.length) {
        stepIndex = segment.stepDescription.length - 1;
      }
      return stepIndex;
    }

    // 현재 좌표 가져오기
    if (pointInSegment < 0 ||
        pointInSegment >= segment.pathCoordinates.length) {
      return 0;
    }
    final currentCoord = segment.pathCoordinates[pointInSegment];

    // [핵심] 각 step의 시작점(lat/lng)과 현재 좌표를 비교
    // 뒤에서부터 검사하여 가장 최근에 지나친 step 시작점 찾기
    for (int stepIdx = segment.steps.length - 1; stepIdx >= 0; stepIdx--) {
      final step = segment.steps[stepIdx];

      // 현재 좌표가 이 step의 시작점과 일치하면 해당 step 반환
      if (_coordsMatch(
        currentCoord.latitude,
        currentCoord.longitude,
        step.lat,
        step.lng,
      )) {
        return stepIdx;
      }
    }

    // 정확히 일치하는 시작점이 없으면: 누적 path 범위로 판단
    // 단, 현재 위치 이후의 step 시작점을 찾아 하나 전 step 반환
    int accumulatedPathPoints = 0;
    for (int stepIdx = 0; stepIdx < segment.steps.length; stepIdx++) {
      final step = segment.steps[stepIdx];
      final stepPathCount = step.path.length;

      // step의 path 시작 인덱스
      final stepStartIdx = accumulatedPathPoints;

      // 현재 포인트가 이 step의 path 범위 시작 이전이면 이전 step
      if (stepIdx > 0 && pointInSegment < stepStartIdx) {
        return stepIdx - 1;
      }

      // 현재 포인트가 이 step의 범위 안에 있으면 이 step 반환
      if (stepPathCount > 0 &&
          pointInSegment >= stepStartIdx &&
          pointInSegment < stepStartIdx + stepPathCount) {
        return stepIdx;
      }

      accumulatedPathPoints += stepPathCount;
    }

    // 모든 범위를 초과한 경우: 마지막 step (도착) 반환
    return segment.steps.length - 1;
  }

  /// 두 좌표가 일치하는지 확인 (부동소수점 비교)
  bool _coordsMatch(double lat1, double lng1, double lat2, double lng2) {
    const double epsilon = 0.0000001; // 약 1cm 정도의 오차 허용
    return (lat1 - lat2).abs() < epsilon && (lng1 - lng2).abs() < epsilon;
  }
}
