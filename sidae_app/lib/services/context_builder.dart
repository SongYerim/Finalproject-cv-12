/// VLM에 전달할 앱 컨텍스트 빌더
///
/// 네비게이션 상태, 버스 정보, 위치 등을 JSON 형태로 생성하여
/// VLM Function Calling에서 활용할 수 있도록 합니다.

import 'dart:convert';
import 'route_tracker.dart';
import 'navigation_service.dart';
import '../models/route_model.dart';

class ContextBuilder {
  /// VLM에 전달할 컨텍스트 JSON 생성
  ///
  /// [tracker]: 현재 경로 추적 상태
  /// [navService]: 네비게이션 서비스 (방향, 위치 정보용)
  /// [destinationName]: 최종 목적지 이름
  /// [busNumber]: 탑승해야 할 버스 번호 (override용)
  /// [destinationStop]: 하차 정류장 이름 (override용)
  static String buildContextJson({
    required RouteTracker tracker,
    required NavigationService navService,
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

    // 거리/시간 계산 로직 개선
    // 1. 현재 세그먼트의 남은 거리
    int currentSegmentRemainingDistance = 0;
    int currentSegmentRemainingTime = 0;

    if (segment != null) {
      double progress = 0.0;
      if (segment.steps.isNotEmpty) {
        progress = tracker.currentStepIndex / segment.steps.length;
      }
      currentSegmentRemainingDistance = (segment.distance * (1 - progress))
          .toInt();
      currentSegmentRemainingTime = (segment.duration * (1 - progress)).toInt();
    }

    // 2. 전체 남은 거리 (현재 세그먼트 잔여 + 이후 모든 세그먼트)
    int totalRemainingDistance = currentSegmentRemainingDistance;
    int totalRemainingTime = currentSegmentRemainingTime;

    for (int i = tracker.currentSegmentIndex + 1; i < segments.length; i++) {
      totalRemainingDistance += segments[i].distance;
      totalRemainingTime += segments[i].duration;
    }

    // 3. 탑승/하차 거리 계산
    int? distanceToBoarding;
    int? distanceToAlighting;

    if (tracker.isOnBus) {
      // 이미 버스 탑승 중: 탑승 거리는 0 또는 의미 없음
      distanceToBoarding = 0;
      // 하차까지 남은 거리 = 현재 버스 구간의 남은 거리
      distanceToAlighting = currentSegmentRemainingDistance;
    } else {
      // 탑승 전 (도보 중)
      if (busSegment != null) {
        // 탑승까지 = 현재 구간 남은 거리 + 탑승 전까지의 중간 도보 구간들 합
        int distToStart = currentSegmentRemainingDistance;

        // 현재 구간 다음부터 ~ 버스 구간 전까지의 거리 합산
        for (
          int i = tracker.currentSegmentIndex + 1;
          i < busSegment.segmentIndex;
          i++
        ) {
          distToStart += segments[i].distance;
        }
        distanceToBoarding = distToStart;

        // 하차까지 = 탑승까지 거리 + 버스 구간 전체 거리
        distanceToAlighting = distToStart + busSegment.distance;
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
      // 거리/시간 정보 추가
      // 거리/시간 정보 (세분화)
      'distance_to_destination': totalRemainingDistance,
      'distance_to_boarding_stop': distanceToBoarding,
      'distance_to_alighting_stop': distanceToAlighting,

      // 하위 호환성 유지 (또는 제거 가능)
      'remaining_distance': totalRemainingDistance,
      'remaining_time': totalRemainingTime,

      // 도구용 데이터 추가
      'next_step_description': _getNextStepDescription(tracker),

      // Orientation Info (방향)
      'device_heading': navService.deviceHeading,
      'target_bearing': navService.targetBearing,
      'clock_direction': _getClockDirection(
        navService.deviceHeading,
        navService.targetBearing,
      ),
      'target_direction': _getTextDirection(
        navService.deviceHeading,
        navService.targetBearing,
      ),

      // Upcoming Path (미래 경로)
      'upcoming_segments': _getUpcomingSegments(tracker),

      // Deviation (이탈 여부 - 간단히 구현)
      'is_off_path': false, // 현재 isOffPath 로직 부재 (추후 구현)
      'deviation_distance': 0,
    };

    return jsonEncode(context);
  }

  /// 현재 구간 이후의 다음 BUS 구간 찾기
  static RouteSegment? _findNextBusSegment(
    List<RouteSegment> segments,
    int currentIndex,
  ) {
    for (int i = currentIndex; i < segments.length; i++) {
      if (segments[i].moveType == 'BUS') {
        return segments[i];
      }
    }
    return null;
  }

  /// 다음 단계 설명 가져오기
  static String _getNextStepDescription(RouteTracker tracker) {
    final segment = tracker.getCurrentSegment();
    if (segment == null) return "도착 또는 경로 없음";

    // 현재 세그먼트 내 다음 스텝이 있는지 확인
    if (tracker.currentStepIndex + 1 < segment.steps.length) {
      return segment.steps[tracker.currentStepIndex + 1].description;
    }

    // 다음 세그먼트의 첫 스텝 확인
    final segments = tracker.routes;
    if (tracker.currentSegmentIndex + 1 < segments.length) {
      final nextSegment = segments[tracker.currentSegmentIndex + 1];
      if (nextSegment.steps.isNotEmpty) {
        return nextSegment.steps[0].description;
      }
      return nextSegment.description; // 스텝 없으면 세그먼트 설명 (예: "버스 승차")
    }

    return "목적지 도착 예정";
  }

  /// 시계 방향 계산 (예: "2시 방향")
  static String _getClockDirection(double heading, double bearing) {
    double diff = (bearing - heading + 360) % 360;
    int clock = ((diff + 15) ~/ 30);
    if (clock == 0) clock = 12;
    return "$clock시 방향";
  }

  /// 텍스트 방향 계산
  static String _getTextDirection(double heading, double bearing) {
    double diff = (bearing - heading + 360) % 360;
    if (diff >= 315 || diff < 45) return "정면";
    if (diff >= 45 && diff < 135) return "오른쪽";
    if (diff >= 135 && diff < 225) return "뒤쪽";
    if (diff >= 225 && diff < 315) return "왼쪽";
    return "알 수 없음";
  }

  /// 남은 구간 목록 생성
  static List<String> _getUpcomingSegments(RouteTracker tracker) {
    final segments = tracker.routes;

    List<String> upcoming = [];
    for (int i = tracker.currentSegmentIndex + 1; i < segments.length; i++) {
      final seg = segments[i];
      if (seg.moveType == 'BUS') {
        upcoming.add(
          "${seg.transportName ?? '버스'} (${seg.endStation ?? '하차'} 하차)",
        );
      } else {
        upcoming.add(seg.description); // 예: "도보 이동"
      }
    }
    return upcoming;
  }
}
