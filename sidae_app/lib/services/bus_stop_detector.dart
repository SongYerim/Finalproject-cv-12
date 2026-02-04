import 'package:geolocator/geolocator.dart';
import '../models/route_model.dart';
import '../constants.dart';
import 'proximity_detector.dart';

/// 버스 정류장 감지 정보
class BusStopInfo {
  final String busNumber;
  final String stationName;
  final double lat;
  final double lng;

  /// 버스 하차 지점 좌표 (버스 구간 끝점)
  final double? exitLat;
  final double? exitLng;

  BusStopInfo({
    required this.busNumber,
    required this.stationName,
    required this.lat,
    required this.lng,
    this.exitLat,
    this.exitLng,
  });
}

/// 버스 정류장 근접 감지 서비스
///
/// ProximityDetector를 상속받아 버스 정류장 근접 감지 기능을 제공합니다.
class BusStopDetector extends ProximityDetector<BusStopInfo> {
  List<RouteSegment> routes = [];
  Function(BusStopInfo)? onBusStopDetected;

  BusStopDetector({required this.routes, this.onBusStopDetected})
    : super(proximityThreshold: kProximityThreshold);

  @override
  String getItemId(BusStopInfo item) {
    return ProximityUtils.createCoordinateId(item.lat, item.lng);
  }

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

      // 현재 위치와 정류장 위치 간의 거리 확인
      if (!isWithinProximity(position, startStation.lat, startStation.lng)) {
        continue;
      }

      // 버스 하차 지점 좌표 (경로 끝점 우선, 없으면 마지막 정류장)
      double? exitLat;
      double? exitLng;

      if (segment.pathCoordinates.isNotEmpty) {
        // 경로 데이터가 있으면 경로의 마지막 지점을 하차 지점으로 사용
        final endPath = segment.pathCoordinates.last;
        exitLat = endPath.latitude;
        exitLng = endPath.longitude;
      } else if (segment.stations.length > 1) {
        // 경로 데이터가 없으면 마지막 정류장 좌표 사용
        final endStation = segment.stations.last;
        exitLat = endStation.lat;
        exitLng = endStation.lng;
      }

      // 버스 정류장 정보 생성 (하차 좌표 포함)
      final busStopInfo = BusStopInfo(
        busNumber: busNumber,
        stationName: stationName,
        lat: startStation.lat,
        lng: startStation.lng,
        exitLat: exitLat,
        exitLng: exitLng,
      );

      // 이미 감지된 정류장이 아니면 콜백 호출
      if (!isAlreadyDetected(busStopInfo)) {
        markAsDetected(busStopInfo);
        onBusStopDetected?.call(busStopInfo);
        return; // 한 번에 하나만 처리
      }
    }
  }
}
