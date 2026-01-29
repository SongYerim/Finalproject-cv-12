import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

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
  static String? baseUrl = dotenv.env['SIDAE_SERVER_CLOUD_URL'];
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

      print('[BusArrival] 요청 시작: $uri');
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      print('[BusArrival] 응답 상태코드: ${response.statusCode}');

      if (response.statusCode == 200) {
        print('[BusArrival] 응답 바디: ${response.body}');
        final json = jsonDecode(response.body);
        return BusArrival.fromJson(json);
      } else {
        print('[BusArrival] 에러 응답: ${response.body}');
      }
      return null;
    } catch (e) {
      print('[BusArrival] 예외 발생: $e');
      return null;
    }
  }

  /// 버스 도착 정보 조회 시작 (1분마다 자동 갱신)
  Future<void> startTracking(String busNumber, String stationName) async {
    developer.log(
      '📍 [BusArrivalService] startTracking 호출 (버스: $busNumber, 정류장: $stationName)',
      name: 'BusArrivalService',
    );

    // 이전 추적 중지 (Timer 확실히 정리)
    if (_refreshTimer != null) {
      developer.log('  - 이전 Timer 취소 중...', name: 'BusArrivalService');
      stopTracking();
    }

    _currentBusNumber = busNumber;
    _currentStationName = stationName;

    // 즉시 첫 조회
    developer.log('  - 첫 조회 시작', name: 'BusArrivalService');
    final arrival = await getBusArrival(busNumber, stationName);
    onArrivalUpdate?.call(arrival);

    // 1분마다 자동 갱신
    developer.log('  - 1분 주기 Timer 시작', name: 'BusArrivalService');
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (_currentBusNumber == null || _currentStationName == null) return;
      developer.log('  - 자동 갱신 중...', name: 'BusArrivalService');
      final arrival = await getBusArrival(
        _currentBusNumber!,
        _currentStationName!,
      );
      onArrivalUpdate?.call(arrival);
    });

    developer.log(
      '✅ [BusArrivalService] startTracking 완료',
      name: 'BusArrivalService',
    );
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
    developer.log(
      '🛑 [BusArrivalService] stopTracking 호출',
      name: 'BusArrivalService',
    );
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _currentBusNumber = null;
    _currentStationName = null;
    developer.log(
      '✅ [BusArrivalService] stopTracking 완료',
      name: 'BusArrivalService',
    );
  }

  void dispose() {
    developer.log(
      '🗑️ [BusArrivalService] dispose 호출',
      name: 'BusArrivalService',
    );
    stopTracking();
    onArrivalUpdate = null;
    developer.log(
      '✅ [BusArrivalService] dispose 완료',
      name: 'BusArrivalService',
    );
  }
}
