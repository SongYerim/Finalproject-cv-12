import 'package:flutter_naver_map/flutter_naver_map.dart';

// RouteStep: 경로의 세부 단계 정보
class RouteStep {
  final String description;
  final double lat;
  final double lng;
  final int turnType;
  final String facilityType; // "15" = 횡단보도
  final int roadType;
  final int time;
  final int distance;
  final List<List<double>> path; // 이 구간의 경로선 좌표

  RouteStep({
    required this.description,
    required this.lat,
    required this.lng,
    required this.turnType,
    required this.facilityType,
    required this.roadType,
    required this.time,
    required this.distance,
    required this.path,
  });

  // 횡단보도 여부 확인
  bool get isCrosswalk => facilityType == "15";

  // Dart 객체 -> JSON 변환
  Map<String, dynamic> toJson() {
    return {
      'description': description,
      'lat': lat,
      'lng': lng,
      'turnType': turnType,
      'facilityType': facilityType,
      'roadType': roadType,
      'time': time,
      'distance': distance,
      'path': path,
    };
  }

  // JSON -> Dart 객체 변환
  factory RouteStep.fromJson(Map<String, dynamic> json) {
    List<List<double>> pathCoords = [];
    if (json['path'] != null) {
      pathCoords = (json['path'] as List)
          .map((point) => List<double>.from(point))
          .toList();
    }

    return RouteStep(
      description: json['description'] ?? '',
      lat: (json['lat'] ?? 0.0).toDouble(),
      lng: (json['lng'] ?? 0.0).toDouble(),
      turnType: json['turnType'] ?? json['turn_type'] ?? 0,
      facilityType: json['facilityType'] ?? json['facility_type'] ?? '',
      roadType: json['roadType'] ?? json['road_type'] ?? 0,
      time: json['time'] ?? 0,
      distance: json['distance'] ?? 0,
      path: pathCoords,
    );
  }
}

class RouteSegment {
  final int segmentIndex;
  final String moveType; // WALK, BUS, SUBWAY
  final String description;
  final List<String> stepDescription;
  final List<RouteStep> steps; // 세부 단계 정보
  final int distance;
  final int duration;
  final List<NLatLng> pathCoordinates;

  RouteSegment({
    required this.segmentIndex,
    required this.moveType,
    required this.description,
    required this.stepDescription,
    required this.steps,
    required this.distance,
    required this.duration,
    required this.pathCoordinates,
  });

  // Dart 객체 -> JSON 변환
  Map<String, dynamic> toJson() {
    return {
      'segment_index': segmentIndex,
      'move_type': moveType,
      'description': description,
      'step_description': stepDescription,
      'steps': steps.map((step) => step.toJson()).toList(),
      'distance': distance,
      'duration': duration,
      'path_coordinates': pathCoordinates.map((coord) => [coord.latitude, coord.longitude]).toList(),
    };
  }

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

    // steps 파싱
    List<RouteStep> stepsList = [];
    if (json['steps'] != null) {
      stepsList = (json['steps'] as List)
          .map((step) => RouteStep.fromJson(step))
          .toList();
    }

    return RouteSegment(
      segmentIndex: json['segment_index'],
      moveType: json['move_type'],
      description: json['description'],
      stepDescription: stepDesc,
      steps: stepsList,
      distance: json['distance'] ?? 0,
      duration: json['duration'] ?? 0,
      pathCoordinates: coords, // 저장
    );
  }
}