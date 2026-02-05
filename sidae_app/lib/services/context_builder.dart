/// VLM에 전달할 앱 컨텍스트 빌더
///
/// 네비게이션 상태, 버스 정보, 위치 등을 JSON 형태로 생성하여
/// VLM Function Calling에서 활용할 수 있도록 합니다.

import 'dart:convert';
import 'route_tracker.dart';

class ContextBuilder {
  /// VLM에 전달할 컨텍스트 JSON 생성
  ///
  /// [tracker]: 현재 경로 추적 상태
  /// [destinationName]: 최종 목적지 이름
  /// [busNumber]: 탑승해야 할 버스 번호 (segment에서 가져옴)
  /// [destinationStop]: 하차 정류장 이름 (segment에서 가져옴)
  static String buildContextJson({
    required RouteTracker tracker,
    String? destinationName,
    String? busNumber,
    String? destinationStop,
  }) {
    final segment = tracker.getCurrentSegment();

    // 현재 segment의 steps에서 현재 step description 가져오기
    String currentStepDescription = '';
    if (segment != null && segment.steps.isNotEmpty) {
      final stepIndex = tracker.currentStepIndex;
      if (stepIndex >= 0 && stepIndex < segment.steps.length) {
        currentStepDescription = segment.steps[stepIndex].description;
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

      // 버스 정보 - segment에서 가져오거나 파라미터 사용
      'bus_number': busNumber ?? segment?.transportName ?? '',
      'destination_stop': destinationStop ?? segment?.endStation ?? '',
      'is_on_bus': tracker.isOnBus,
    };

    return jsonEncode(context);
  }
}
