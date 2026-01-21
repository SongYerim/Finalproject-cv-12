import 'package:geolocator/geolocator.dart';
import '../models/route_model.dart';

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
class CrosswalkDetector {
  static const double proximityThreshold = 20.0; // 20m 이내

  List<RouteSegment> routes = [];
  Function(CrosswalkInfo)? onCrosswalkDetected;

  // 이미 감지된 횡단보도 추적 (중복 감지 방지) - static으로 모든 인스턴스가 공유
  static final Set<String> _detectedCrosswalks = {};

  CrosswalkDetector({required this.routes, this.onCrosswalkDetected});

  /// GPS 위치 업데이트 시 호출
  void checkCrosswalkProximity(Position position) {
    for (var segment in routes) {
      // WALK 타입만 횡단보도가 있을 수 있음
      if (segment.moveType != 'WALK') continue;

      for (var step in segment.steps) {
        if (step.isCrosswalk) {
          // 현재 위치와 횡단보도 위치 간의 거리 계산
          double distance = Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            step.lat,
            step.lng,
          );

          // 20m 이내 근접 시
          if (distance <= proximityThreshold) {
            String crosswalkId = '${step.lat}_${step.lng}';

            // 이미 감지된 횡단보도가 아니면 콜백 호출
            if (!_detectedCrosswalks.contains(crosswalkId)) {
              _detectedCrosswalks.add(crosswalkId);

              // 횡단보도 반대편 좌표 계산
              double exitLat = step.lat;
              double exitLng = step.lng;

              // 1순위: path의 마지막 점 사용 (횡단보도 반대편)
              if (step.path.isNotEmpty && step.path.length >= 2) {
                final lastPoint = step.path.last;
                exitLat = lastPoint[0]; // lat
                exitLng = lastPoint[1]; // lng
              }
              // 2순위 (폴백): 다음 step 좌표 사용
              else {
                int stepIndex = segment.steps.indexOf(step);
                if (stepIndex >= 0 && stepIndex + 1 < segment.steps.length) {
                  final nextStep = segment.steps[stepIndex + 1];
                  exitLat = nextStep.lat;
                  exitLng = nextStep.lng;
                }
              }

              final crosswalkInfo = CrosswalkInfo(
                step: step,
                exitLat: exitLat,
                exitLng: exitLng,
              );

              // 디버그 로그: exit 좌표 확인
              print('🎯 횡단보도 exit 좌표 계산됨: ($exitLat, $exitLng)');
              print('📍 횡단보도 시작점: (${step.lat}, ${step.lng})');

              onCrosswalkDetected?.call(crosswalkInfo);
              return; // 한 번에 하나만 처리
            }
          }
          // 한 번 감지된 횡단보도는 영구적으로 감지 목록에 유지
          // (횡단보도를 건넌 후 다시 카메라가 열리는 것을 방지)
        }
      }
    }
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
          double distance = Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            step.lat,
            step.lng,
          );

          if (distance < minDistance) {
            minDistance = distance;
            nearest = step;
          }
        }
      }
    }

    return nearest;
  }

  /// 감지 기록 초기화
  void reset() {
    _detectedCrosswalks.clear();
  }
}
