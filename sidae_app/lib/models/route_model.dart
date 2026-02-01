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

  // BUS/SUBWAY용 필드
  final String? transportName; // 버스 번호 또는 지하철 노선
  final String? startStation; // 승차 정류장
  final String? endStation; // 하차 정류장
  final List<BusStation> stations; // 정류장 목록

  RouteSegment({
    required this.segmentIndex,
    required this.moveType,
    required this.description,
    required this.stepDescription,
    required this.steps,
    required this.distance,
    required this.duration,
    required this.pathCoordinates,
    this.transportName,
    this.startStation,
    this.endStation,
    this.stations = const [],
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
      'path_coordinates': pathCoordinates
          .map((coord) => [coord.latitude, coord.longitude])
          .toList(),
      'transport_name': transportName,
      'start_station': startStation,
      'end_station': endStation,
      'stations': stations.map((s) => s.toJson()).toList(),
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

    // stations 파싱
    List<BusStation> stationsList = [];
    if (json['stations'] != null) {
      stationsList = (json['stations'] as List)
          .map((s) => BusStation.fromJson(s))
          .toList();
    }

    // [데이터 보정] BUS인데 정보가 없으면 description에서 파싱 ("역전우체국에서 588 승차")
    String? transportName = json['transport_name'];
    String? startStation = json['start_station'];
    String? endStation = json['end_station'];
    final moveType = json['move_type'] as String? ?? "WALK";
    final description = json['description'] as String? ?? "";

    if (moveType == 'BUS' && (transportName == null || startStation == null)) {
      // 정규식: "(장소)에서 (번호) 승차"
      final regex = RegExp(r'(.*?)에서 (.*?) 승차');
      final match = regex.firstMatch(description);
      if (match != null) {
        startStation ??= match.group(1); // "뉴서울3차아파트"
        transportName ??= match.group(2); // "588"
      }
    }

    // [데이터 보정] stations가 비어있는데 BUS이고 path_coordinates가 있으면 가상 정류장 생성
    // (BusStopDetector가 stations.first를 사용하므로 필수)
    if (stationsList.isEmpty && moveType == 'BUS' && coords.isNotEmpty) {
      if (startStation != null) {
        // 승차 정류장 (path의 시작점)
        stationsList.add(
          BusStation(
            index: 0,
            name: startStation,
            lat: coords.first.latitude,
            lng: coords.first.longitude,
          ),
        );
      }
      if (endStation != null) {
        // 하차 정류장 (path의 끝점)
        stationsList.add(
          BusStation(
            index: 1,
            name: endStation,
            lat: coords.last.latitude,
            lng: coords.last.longitude,
          ),
        );
      } else if (stationsList.isNotEmpty) {
        // 하차 정류장 이름을 모르면 "하차 정류장"으로 추가
        stationsList.add(
          BusStation(
            index: 1,
            name: "하차 정류장",
            lat: coords.last.latitude,
            lng: coords.last.longitude,
          ),
        );
      }
    }

    return RouteSegment(
      segmentIndex: json['segment_index'],
      moveType: moveType,
      description: description,
      stepDescription: stepDesc,
      steps: stepsList,
      distance: json['distance'] ?? 0,
      duration: json['duration'] ?? 0,
      pathCoordinates: coords,
      transportName: transportName,
      startStation: startStation,
      endStation: endStation,
      stations: stationsList,
    );
  }
}

/// 버스/지하철 정류장 정보
class BusStation {
  final int index;
  final String name;
  final double lat;
  final double lng;

  BusStation({
    required this.index,
    required this.name,
    required this.lat,
    required this.lng,
  });

  Map<String, dynamic> toJson() {
    return {'index': index, 'name': name, 'lat': lat, 'lng': lng};
  }

  factory BusStation.fromJson(Map<String, dynamic> json) {
    return BusStation(
      index: json['index'] ?? 0,
      name: json['name'] ?? '',
      lat: (json['lat'] ?? 0.0).toDouble(),
      lng: (json['lng'] ?? 0.0).toDouble(),
    );
  }
}
