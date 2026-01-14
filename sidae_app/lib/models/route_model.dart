import 'package:flutter_naver_map/flutter_naver_map.dart';

class RouteSegment {
  final int segmentIndex;
  final String moveType; // WALK, BUS, SUBWAY
  final String description;
  final List<String> stepDescription;
  final int distance;
  final int duration;
  final List<NLatLng> pathCoordinates;

  RouteSegment({
    required this.segmentIndex,
    required this.moveType,
    required this.description,
    required this.stepDescription,
    required this.distance,
    required this.duration,
    required this.pathCoordinates,
  });

  // JSON -> Dart 객체 변환 (Factory 생성자)
  factory RouteSegment.fromJson(Map<String, dynamic> json) {
    // 좌표 파싱 로직: [[lat, lng], [lat, lng]] -> List<NLatLng>
    List<NLatLng> coords = [];
    if (json['path_coordinates'] != null) {
      json['path_coordinates'].forEach((point) {
        // 백엔드: [lat, lng] 순서 확인 필요 (path_parser.py에서 lat, lng 순서로 줌)
        coords.add(NLatLng(point[0], point[1]));
      });
    }

    // 하위 호환성을 위해 step_description 또는 instructions 필드를 읽도록 처리
    List<String> stepDesc = [];
    if (json['step_description'] != null) {
      stepDesc = List<String>.from(json['step_description']);
    } else if (json['instructions'] != null) {
      stepDesc = List<String>.from(json['instructions']);
    }

    return RouteSegment(
      segmentIndex: json['segment_index'],
      moveType: json['move_type'],
      description: json['description'],
      stepDescription: stepDesc,
      distance: json['distance'] ?? 0,
      duration: json['duration'] ?? 0,
      pathCoordinates: coords, // 저장
    );
  }
}