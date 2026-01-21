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

  // 이미 감지된 횡단보도 추적 (중복 감지 방지)
  final Set<String> _detectedCrosswalks = {};

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

              // 횡단보도 반대편 좌표 계산 (path의 마지막 점 사용)
              double exitLat = step.lat;
              double exitLng = step.lng;
              if (step.path.isNotEmpty) {
                final lastPoint = step.path.last;
                exitLat = lastPoint[0];
                exitLng = lastPoint[1];
              }

              final crosswalkInfo = CrosswalkInfo(
                step: step,
                exitLat: exitLat,
                exitLng: exitLng,
              );

              onCrosswalkDetected?.call(crosswalkInfo);
              return; // 한 번에 하나만 처리
            }
          } else {
            // 멀어지면 다시 감지 가능하도록 (선택사항)
            String crosswalkId = '${step.lat}_${step.lng}';
            if (distance > proximityThreshold * 2) {
              _detectedCrosswalks.remove(crosswalkId);
            }
          }
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
