import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../models/route_model.dart';
import '../models/bus_info_model.dart';

/// 버스 정류장 근처 도착을 감지하는 서비스
class BusStopDetector {
  final List<RouteSegment> routes;
  final Function(BusStopInfo) onBusStopDetected;

  // 이미 감지한 버스 정류장 (중복 방지)
  final Set<int> _triggeredStops = {};

  // 감지 거리 (미터)
  static const double detectionRadius = 50.0;

  BusStopDetector({required this.routes, required this.onBusStopDetected});

  /// 현재 위치를 기준으로 버스 정류장 근처인지 확인
  void checkBusStopProximity(Position position) {
    for (int i = 0; i < routes.length; i++) {
      final route = routes[i];

      // BUS segment만 확인
      if (route.moveType != 'BUS') continue;

      // 이미 감지한 정류장이면 건너뛰기
      if (_triggeredStops.contains(i)) continue;

      // 버스 segment의 시작점 = 버스 정류장 위치
      if (route.pathCoordinates.isEmpty) continue;

      final busStopLat = route.pathCoordinates.first.latitude;
      final busStopLng = route.pathCoordinates.first.longitude;

      // 거리 계산
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        busStopLat,
        busStopLng,
      );

      debugPrint(
        '[BusStopDetector] Segment $i (BUS) 거리: ${distance.toStringAsFixed(1)}m',
      );

      // 50m 이내면 버스 정류장 도착으로 판단
      if (distance <= detectionRadius) {
        _triggeredStops.add(i); // 중복 방지 플래그 설정

        // description에서 버스 번호와 정류장 이름 추출
        final busInfo = _extractBusInfo(route, i, busStopLat, busStopLng);

        if (busInfo != null) {
          debugPrint(
            '[BusStopDetector] 버스 정류장 도착! ${busInfo.busNumber}번 @ ${busInfo.stationName}',
          );
          onBusStopDetected(busInfo);
        }
      }
    }
  }

  /// RouteSegment의 description에서 버스 번호와 정류장 이름 추출
  /// 지원 형식:
  /// - "1711번 버스 승차 (신교동 정류장)"
  /// - "뉴서울3차아파트에서 588 승차"
  /// - "588번 승차"
  BusStopInfo? _extractBusInfo(
    RouteSegment route,
    int segmentIndex,
    double lat,
    double lng,
  ) {
    try {
      final desc = route.description.trim();

      // 버스 번호 추출: 여러 패턴 시도
      String? busNumber;

      // 패턴 1: "1711번" 형태
      var match = RegExp(r'(\d+)번').firstMatch(desc);
      if (match != null) {
        busNumber = match.group(1);
      } else {
        // 패턴 2: "588 승차" 형태 (번 없이 숫자만)
        match = RegExp(r'(\d+)\s*승차').firstMatch(desc);
        if (match != null) {
          busNumber = match.group(1);
        }
      }

      if (busNumber == null) {
        debugPrint('[BusStopDetector] 버스 번호를 찾을 수 없음: $desc');
        return null;
      }

      // 정류장 이름 추출
      String stationName = '';

      // 패턴 1: 괄호 안의 정류장 이름 "(신교동 정류장)"
      final stationMatch = RegExp(r'\((.+?)\s*정류장?\)').firstMatch(desc);
      if (stationMatch != null) {
        stationName = stationMatch.group(1)!.trim();
      } else {
        // 패턴 2: "XXX에서" 형태 추출
        final fromMatch = RegExp(r'(.+?)에서\s+\d').firstMatch(desc);
        if (fromMatch != null) {
          stationName = fromMatch.group(1)!.trim();
        } else {
          // 정류장 이름이 없으면 stepDescription 첫 번째 항목 사용
          if (route.stepDescription.isNotEmpty) {
            stationName = route.stepDescription.first;
          } else {
            // 최후의 수단: description 전체 사용
            stationName = desc;
          }
        }
      }

      debugPrint('[BusStopDetector] 추출 성공 - 버스: $busNumber, 정류장: $stationName');

      return BusStopInfo(
        busNumber: busNumber,
        stationName: stationName,
        lat: lat,
        lng: lng,
        segmentIndex: segmentIndex,
      );
    } catch (e) {
      debugPrint('[BusStopDetector] 버스 정보 추출 실패: $e');
      return null;
    }
  }

  /// 감지 상태 초기화 (새로운 경로 시작 시)
  void reset() {
    _triggeredStops.clear();
  }

  /// dispose
  void dispose() {
    _triggeredStops.clear();
  }
}
