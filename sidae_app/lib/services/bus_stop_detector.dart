import 'package:geolocator/geolocator.dart';
import '../models/route_model.dart';

/// 버스 정류장 감지 정보
class BusStopInfo {
  final String busNumber;
  final String stationName;
  final double lat;
  final double lng;

  BusStopInfo({
    required this.busNumber,
    required this.stationName,
    required this.lat,
    required this.lng,
  });
}

/// 버스 정류장 근접 감지 서비스
class BusStopDetector {
  static const double proximityThreshold = 20.0; // 20m 이내

  List<RouteSegment> routes = [];
  Function(BusStopInfo)? onBusStopDetected;

  // 이미 감지된 정류장 추적 (중복 감지 방지)
  static final Set<String> _detectedStops = {};

  BusStopDetector({required this.routes, this.onBusStopDetected});

  /// GPS 위치 업데이트 시 호출
  void checkBusStopProximity(Position position) {
    for (var segment in routes) {
      // BUS 타입만 처리
      if (segment.moveType != 'BUS') continue;

      // 버스 번호와 시작 정류장 정보 확인
      final busNumber = segment.transportName;
      final stationName = segment.startStation;

      if (busNumber == null || stationName == null) continue;

      // stations에서 첫 번째 (승차) 정류장 좌표 가져오기
      if (segment.stations.isEmpty) continue;

      final startStation = segment.stations.first;

      // 현재 위치와 정류장 위치 간의 거리 계산
      double distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        startStation.lat,
        startStation.lng,
      );

      // 20m 이내 근접 시
      if (distance <= proximityThreshold) {
        String stopId = '${startStation.lat}_${startStation.lng}';

        // 이미 감지된 정류장이 아니면 콜백 호출
        if (!_detectedStops.contains(stopId)) {
          _detectedStops.add(stopId);

          final busStopInfo = BusStopInfo(
            busNumber: busNumber,
            stationName: stationName,
            lat: startStation.lat,
            lng: startStation.lng,
          );

          onBusStopDetected?.call(busStopInfo);
          return; // 한 번에 하나만 처리
        }
      }
    }
  }

  /// 감지 기록 초기화
  void reset() {
    _detectedStops.clear();
  }
}
