import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../models/route_model.dart';
import 'proximity_detector.dart';

/// 횡단보도 정보 (감지된 횡단보도 + 반대편 좌표)
class CrosswalkInfo {
  final RouteStep step;
  final double exitLat; // 횡단보도 반대편 위도
  final double exitLng; // 횡단보도 반대편 경도

  CrosswalkInfo({
    required this.step,
    required this.exitLat,
    required this.exitLng,
  });
}

/// 횡단보도 감지 서비스
///
/// ProximityDetector를 상속받아 횡단보도 근접 감지 기능을 제공합니다.
class CrosswalkDetector extends ProximityDetector<RouteStep> {
  List<RouteSegment> routes = [];
  Function(CrosswalkInfo)? onCrosswalkDetected;

  CrosswalkDetector({required this.routes, this.onCrosswalkDetected})
    : super(proximityThreshold: 10.0); // 10m 이내

  @override
  String getItemId(RouteStep item) {
    return ProximityUtils.createCoordinateId(item.lat, item.lng);
  }

  /// GPS 위치 업데이트 시 호출
  void checkCrosswalkProximity(Position position) {
    // 디버그: 현재 위치와 routes 확인
    debugPrint(
      '🔍 [CrosswalkDetector] 현재 위치: (${position.latitude}, ${position.longitude})',
    );
    debugPrint('🔍 [CrosswalkDetector] routes 개수: ${routes.length}');

    int totalCrosswalks = 0;

    for (var segment in routes) {
      // WALK 타입만 횡단보도가 있을 수 있음
      if (segment.moveType != 'WALK') {
        debugPrint(
          '🔍 [CrosswalkDetector] segment ${segment.segmentIndex}: moveType=${segment.moveType} (스킵)',
        );
        continue;
      }

      debugPrint(
        '🔍 [CrosswalkDetector] segment ${segment.segmentIndex}: WALK, steps=${segment.steps.length}개',
      );

      for (var step in segment.steps) {
        debugPrint(
          '🔍 [CrosswalkDetector] step: facilityType="${step.facilityType}", isCrosswalk=${step.isCrosswalk}, desc="${step.description}"',
        );

        if (step.isCrosswalk) {
          totalCrosswalks++;

          // 현재 위치와 횡단보도 위치 간의 거리 확인
          final distance = calculateDistance(position, step.lat, step.lng);
          final alreadyDetected = isAlreadyDetected(step);

          debugPrint(
            '🚶 [CrosswalkDetector] 횡단보도 발견! 거리=${distance.toStringAsFixed(1)}m, 임계값=${proximityThreshold}m, 이미감지=$alreadyDetected',
          );

          // 근접 범위 내 & 이미 감지되지 않은 경우
          if (distance <= proximityThreshold && !alreadyDetected) {
            markAsDetected(step);

            debugPrint('✅ [CrosswalkDetector] 횡단보도 감지됨! 콜백 호출');

            // 횡단보도 반대편 좌표 계산
            final exitCoords = _calculateExitCoordinates(step, segment.steps);

            final crosswalkInfo = CrosswalkInfo(
              step: step,
              exitLat: exitCoords.$1,
              exitLng: exitCoords.$2,
            );

            onCrosswalkDetected?.call(crosswalkInfo);
            return; // 한 번에 하나만 처리
          } else if (alreadyDetected) {
            debugPrint('⚠️ [CrosswalkDetector] 이미 감지된 횡단보도입니다');
          }
        }
      }
    }

    debugPrint('🔍 [CrosswalkDetector] 총 횡단보도 수: $totalCrosswalks');
  }

  /// 횡단보도 반대편 좌표 계산
  (double, double) _calculateExitCoordinates(
    RouteStep step,
    List<RouteStep> steps,
  ) {
    double exitLat = step.lat;
    double exitLng = step.lng;

    // 1순위: path의 마지막 점 사용 (횡단보도 반대편)
    if (step.path.isNotEmpty && step.path.length >= 2) {
      final lastPoint = step.path.last;
      exitLat = lastPoint[0]; // lat
      exitLng = lastPoint[1]; // lng
      debugPrint(
        '✅ [CrosswalkDetector] exit 좌표 (path 사용): ($exitLat, $exitLng)',
      );
    }
    // 2순위 (폴백): 다음 step 좌표 사용
    else {
      int stepIndex = steps.indexOf(step);
      if (stepIndex >= 0 && stepIndex + 1 < steps.length) {
        final nextStep = steps[stepIndex + 1];
        exitLat = nextStep.lat;
        exitLng = nextStep.lng;
        debugPrint(
          '✅ [CrosswalkDetector] exit 좌표 (다음 step 사용): ($exitLat, $exitLng)',
        );
      }
    }

    return (exitLat, exitLng);
  }

  /// 모든 횡단보도 위치 가져오기
  List<RouteStep> getAllCrosswalks() {
    List<RouteStep> crosswalks = [];
    for (var segment in routes) {
      if (segment.moveType == 'WALK') {
        crosswalks.addAll(segment.steps.where((step) => step.isCrosswalk));
      }
    }
    return crosswalks;
  }

  /// 가장 가까운 횡단보도 찾기
  RouteStep? getNearestCrosswalk(Position position) {
    RouteStep? nearest;
    double minDistance = double.infinity;

    for (var segment in routes) {
      if (segment.moveType != 'WALK') continue;

      for (var step in segment.steps) {
        if (step.isCrosswalk) {
          final distance = calculateDistance(position, step.lat, step.lng);

          if (distance < minDistance) {
            minDistance = distance;
            nearest = step;
          }
        }
      }
    }

    return nearest;
  }
}
