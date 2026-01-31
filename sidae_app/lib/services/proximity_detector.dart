import 'package:geolocator/geolocator.dart';

/// 근접 감지 기초 클래스
///
/// GPS 기반으로 특정 지점에 근접했는지 감지하는 공통 로직을 제공합니다.
/// BusStopDetector, CrosswalkDetector 등에서 상속받아 사용합니다.
abstract class ProximityDetector<T> {
  /// 근접 거리 임계값 (미터)
  final double proximityThreshold;

  /// 이미 감지된 항목 추적 (중복 감지 방지)
  final Set<String> _detectedItems = {};

  ProximityDetector({required this.proximityThreshold});

  /// 현재 위치와 대상 좌표 사이의 거리 계산 (미터)
  double calculateDistance(
    Position position,
    double targetLat,
    double targetLng,
  ) {
    return Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      targetLat,
      targetLng,
    );
  }

  /// 대상이 근접 범위 내에 있는지 확인
  bool isWithinProximity(
    Position position,
    double targetLat,
    double targetLng,
  ) {
    final distance = calculateDistance(position, targetLat, targetLng);
    return distance <= proximityThreshold;
  }

  /// 항목의 고유 ID 반환 (서브클래스에서 구현)
  String getItemId(T item);

  /// 항목이 이미 감지되었는지 확인
  bool isAlreadyDetected(T item) {
    return _detectedItems.contains(getItemId(item));
  }

  /// 항목을 감지됨으로 표시
  void markAsDetected(T item) {
    _detectedItems.add(getItemId(item));
  }

  /// 특정 항목의 감지 기록 제거
  void unmarkDetected(T item) {
    _detectedItems.remove(getItemId(item));
  }

  /// 감지 기록 초기화
  void reset() {
    _detectedItems.clear();
  }

  /// 감지된 항목 수.
  int get detectedCount => _detectedItems.length;
}

/// 좌표 기반의 고유 ID 생성 유틸리티
class ProximityUtils {
  /// 위도/경도를 기반으로 고유 ID 생성
  static String createCoordinateId(double lat, double lng) {
    return '${lat}_$lng';
  }
}
