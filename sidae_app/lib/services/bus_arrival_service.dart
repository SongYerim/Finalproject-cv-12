import 'dart:async';
import 'dart:convert';
// import 'dart:developer' as developer;
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
  // Singleton 패턴
  static final BusArrivalService _instance = BusArrivalService._internal();
  factory BusArrivalService() => _instance;
  static BusArrivalService get instance => _instance;
  BusArrivalService._internal();

  static String? baseUrl = dotenv.env['SIDAE_SERVER_CLOUD_URL'];

  // 30초 갱신 주기
  static const int UPDATE_INTERVAL_SEC = 30;

  Timer? _tickTimer;
  int _remainingSeconds = UPDATE_INTERVAL_SEC;

  // 카운트다운 스트림
  final _countdownController = StreamController<int>.broadcast();
  Stream<int> get countdownStream => _countdownController.stream;

  Function(BusArrival?)? onArrivalUpdate;
  String? _currentBusNumber;
  String? _currentStationName;
  BusArrival? _lastArrival; // 마지막 조회 결과 캐싱

  /// 버스 도착 정보 조회
  Future<BusArrival?> getBusArrival(
    String busNumber,
    String stationName,
  ) async {
    try {
      final uri = Uri.parse('$baseUrl/bus/arrival').replace(
        queryParameters: {'bus_number': busNumber, 'station_name': stationName},
      );

      // print('[BusArrival] 요청 시작: $uri');
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      // print('[BusArrival] 응답 상태코드: ${response.statusCode}');

      if (response.statusCode == 200) {
        // print('[BusArrival] 응답 바디: ${response.body}');
        final json = jsonDecode(response.body);
        return BusArrival.fromJson(json);
      } else {
        // print('[BusArrival] 에러 응답: ${response.body}');
      }
      return null;
    } catch (e) {
      // print('[BusArrival] 예외 발생: $e');
      return null;
    }
  }

  /// 버스 도착 정보 조회 시작 (30초마다 자동 갱신)
  Future<void> startTracking(String busNumber, String stationName) async {
    // developer.log(
    //   '📍 [BusArrivalService] startTracking 호출 (버스: $busNumber, 정류장: $stationName)',
    //   name: 'BusArrivalService',
    // );

    // 이미 동일한 버스/정류장을 추적 중이면 중복 호출 방지
    if (_currentBusNumber == busNumber &&
        _currentStationName == stationName &&
        _tickTimer != null) {
      // developer.log(
      //   '⏭️ [BusArrivalService] 이미 추적 중 - 중복 호출 스킵',
      //   name: 'BusArrivalService',
      // );
      // 기존 캐시된 데이터가 있으면 즉시 콜백 호출
      if (_lastArrival != null) {
        // developer.log('  - 캐시된 데이터 반환', name: 'BusArrivalService');
        onArrivalUpdate?.call(_lastArrival);
      }
      return;
    }

    // 이전 추적 중지
    stopTracking();

    _currentBusNumber = busNumber;
    _currentStationName = stationName;

    // 즉시 첫 조회
    // developer.log('  - 첫 조회 시작', name: 'BusArrivalService');
    final arrival = await getBusArrival(busNumber, stationName);
    _lastArrival = arrival; // 캐싱
    onArrivalUpdate?.call(arrival);

    // 타이머 시작
    _startTimer();
  }

  /// 타이머 시작 (1초마다 틱)
  void _startTimer() {
    _stopTimer();
    _remainingSeconds = UPDATE_INTERVAL_SEC;
    _countdownController.add(_remainingSeconds);

    _tickTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      _remainingSeconds--;
      _countdownController.add(_remainingSeconds);

      if (_remainingSeconds <= 0) {
        // 0초 도달 시 갱신
        if (_currentBusNumber != null && _currentStationName != null) {
          // developer.log('  - 자동 갱신 중...', name: 'BusArrivalService');
          final arrival = await getBusArrival(
            _currentBusNumber!,
            _currentStationName!,
          );
          _lastArrival = arrival;
          onArrivalUpdate?.call(arrival);
        }
        // 시간 리셋
        _remainingSeconds = UPDATE_INTERVAL_SEC;
        _countdownController.add(_remainingSeconds);
      }
    });
  }

  void _stopTimer() {
    _tickTimer?.cancel();
    _tickTimer = null;
  }

  /// 수동 새로고침
  Future<BusArrival?> refresh() async {
    if (_currentBusNumber == null || _currentStationName == null) return null;

    // 타이머 리셋
    _startTimer();

    // 즉시 요청
    final arrival = await getBusArrival(
      _currentBusNumber!,
      _currentStationName!,
    );
    _lastArrival = arrival;
    onArrivalUpdate?.call(arrival);
    return arrival;
  }

  /// 버스 도착 정보 조회 중지
  void stopTracking() {
    // developer.log(
    //   '🛑 [BusArrivalService] stopTracking 호출',
    //   name: 'BusArrivalService',
    // );
    _stopTimer();
    _currentBusNumber = null;
    _currentStationName = null;
    _lastArrival = null; // 캐시 초기화
    // developer.log(
    //   '✅ [BusArrivalService] stopTracking 완료',
    //   name: 'BusArrivalService',
    // );
  }

  void dispose() {
    // developer.log(
    //   '🗑️ [BusArrivalService] dispose 호출',
    //   name: 'BusArrivalService',
    // );
    stopTracking();
    onArrivalUpdate = null;
    _countdownController.close();
    // developer.log(
    //   '✅ [BusArrivalService] dispose 완료',
    //   name: 'BusArrivalService',
    // );
  }
}
