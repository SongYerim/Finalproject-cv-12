/// VLM에 전달할 앱 컨텍스트 빌더
///
/// 네비게이션 상태, 버스 정보, 위치 등을 JSON 형태로 생성하여
/// VLM Function Calling에서 활용할 수 있도록 합니다.

import 'dart:convert';
import 'route_tracker.dart';
import '../models/route_model.dart';

class ContextBuilder {
  /// VLM에 전달할 컨텍스트 JSON 생성
  ///
  /// [tracker]: 현재 경로 추적 상태
  /// [destinationName]: 최종 목적지 이름
  /// [busNumber]: 탑승해야 할 버스 번호 (override용)
  /// [destinationStop]: 하차 정류장 이름 (override용)
  static String buildContextJson({
    required RouteTracker tracker,
    String? destinationName,
    String? busNumber,
    String? destinationStop,
  }) {
    final segment = tracker.getCurrentSegment();
    final segments = tracker.routes; // RouteTracker의 routes 필드 사용

    // 현재 segment의 steps에서 현재 step description 가져오기
    String currentStepDescription = '';
    if (segment != null && segment.steps.isNotEmpty) {
      final stepIndex = tracker.currentStepIndex;
      if (stepIndex >= 0 && stepIndex < segment.steps.length) {
        currentStepDescription = segment.steps[stepIndex].description;
      }
    }

    // 버스 정보 찾기: 현재 구간 또는 다음 버스 구간에서 가져오기
    String? targetBusNumber = busNumber;
    String? targetDestinationStop = destinationStop;
    String? targetStartStation;
    RouteSegment? busSegment; // 버스 구간 참조용

    // 1. 파라미터로 전달된 값이 없으면 경로에서 찾기
    if (targetBusNumber == null || targetBusNumber.isEmpty) {
      // 현재 구간이 BUS면 현재 구간 사용
      if (segment?.moveType == 'BUS') {
        busSegment = segment;
        targetBusNumber = segment?.transportName;
        targetDestinationStop = segment?.endStation;
        targetStartStation = segment?.startStation;
      } else {
        // 현재 구간이 WALK 등이면, 다음 BUS 구간 찾기
        final nextBusSegment = _findNextBusSegment(
          segments,
          tracker.currentSegmentIndex,
        );
        if (nextBusSegment != null) {
          busSegment = nextBusSegment;
          targetBusNumber = nextBusSegment.transportName;
          targetDestinationStop = nextBusSegment.endStation;
          targetStartStation = nextBusSegment.startStation;
        }
      }
    }

    // 정류장 정보 계산
    int totalStops = 0;
    int remainingStops = 0;
    List<String> stationNames = [];

    if (busSegment != null && busSegment.stations.isNotEmpty) {
      totalStops = busSegment.stations.length;
      stationNames = busSegment.stations.map((s) => s.name).toList();

      // 버스 탑승 중일 때만 남은 정거장 계산
      if (tracker.isOnBus && segment?.moveType == 'BUS') {
        // 현재 구간이 버스이고 탑승 중이면, 비례 계산
        // (실제로는 GPS 기반 정류장 감지가 필요하지만, 간단히 진행률로 추정)
        final segmentProgress =
            tracker.currentStepIndex /
            (segment!.steps.isNotEmpty ? segment.steps.length : 1);
        final passedStops = (totalStops * segmentProgress).floor();
        remainingStops = totalStops - passedStops - 1; // 현재 정류장 제외
        if (remainingStops < 0) remainingStops = 0;
      } else {
        // 아직 탑승 전이면 전체 정류장이 남음
        remainingStops = totalStops > 0 ? totalStops - 1 : 0; // 승차 정류장 제외
      }
    }

    final context = <String, dynamic>{
      // 목적지 정보
      'destination': destinationName ?? '',

      // 진행률 (0-100)
      'progress': (tracker.getProgress() * 100).toInt(),

      // 현재 단계 설명
      'current_step': currentStepDescription,

      // 이동 수단 (WALK, BUS, SUBWAY 등)
      'transport_type': segment?.moveType ?? 'WALK',

      // 버스 정보 (현재 또는 다음 버스 구간)
      'bus_number': targetBusNumber ?? '',
      'start_station': targetStartStation ?? '', // 승차 정류장
      'destination_stop': targetDestinationStop ?? '', // 하차 정류장
      'is_on_bus': tracker.isOnBus,

      // 정류장 정보 추가
      'total_stops': totalStops, // 전체 정류장 수
      'remaining_stops': remainingStops, // 남은 정류장 수
      'station_names': stationNames, // 정류장 이름 목록
    };

    return jsonEncode(context);
  }

  /// 현재 구간 이후의 다음 BUS 구간 찾기
  static RouteSegment? _findNextBusSegment(
    List<RouteSegment>? segments,
    int currentIndex,
  ) {
    if (segments == null) return null;

    for (int i = currentIndex; i < segments.length; i++) {
      if (segments[i].moveType == 'BUS') {
        return segments[i];
      }
    }
    return null;
  }
}
