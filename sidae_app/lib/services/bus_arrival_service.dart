import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// 버스 도착 정보
class BusArrival {
  final String busNumber;
  final String stationName;
  final String statusMsg;
  final String plateNo;
  final String vehId;
  final String stationSeq;

  BusArrival({
    required this.busNumber,
    required this.stationName,
    required this.statusMsg,
    required this.plateNo,
    required this.vehId,
    required this.stationSeq,
  });

  factory BusArrival.fromJson(Map<String, dynamic> json) {
    return BusArrival(
      busNumber: json['bus_number'] ?? '',
      stationName: json['station_name'] ?? '',
      statusMsg: json['status_msg'] ?? '정보 없음',
      plateNo: json['plate_no'] ?? '',
      vehId: json['veh_id'] ?? '',
      stationSeq: json['station_seq'] ?? '',
    );
  }
}

/// 버스 도착 정보 조회 서비스
class BusArrivalService {
  static const String baseUrl = 'http://192.168.0.15:8000';

  Timer? _refreshTimer;
  Function(BusArrival?)? onArrivalUpdate;
  String? _currentBusNumber;
  String? _currentStationName;

  /// 버스 도착 정보 조회
  Future<BusArrival?> getBusArrival(
    String busNumber,
    String stationName,
  ) async {
    try {
      final uri = Uri.parse('$baseUrl/bus/arrival').replace(
        queryParameters: {'bus_number': busNumber, 'station_name': stationName},
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return BusArrival.fromJson(json);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// 버스 도착 정보 조회 시작 (1분마다 자동 갱신)
  Future<void> startTracking(String busNumber, String stationName) async {
    _currentBusNumber = busNumber;
    _currentStationName = stationName;

    // 즉시 첫 조회
    final arrival = await getBusArrival(busNumber, stationName);
    onArrivalUpdate?.call(arrival);

    // 1분마다 자동 갱신
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (_currentBusNumber == null || _currentStationName == null) return;
      final arrival = await getBusArrival(
        _currentBusNumber!,
        _currentStationName!,
      );
      onArrivalUpdate?.call(arrival);
    });
  }

  /// 수동 새로고침
  Future<BusArrival?> refresh() async {
    if (_currentBusNumber == null || _currentStationName == null) return null;
    final arrival = await getBusArrival(
      _currentBusNumber!,
      _currentStationName!,
    );
    onArrivalUpdate?.call(arrival);
    return arrival;
  }

  /// 버스 도착 정보 조회 중지
  void stopTracking() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _currentBusNumber = null;
    _currentStationName = null;
  }

  void dispose() {
    stopTracking();
  }
}
