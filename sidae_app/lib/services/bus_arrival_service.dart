import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/bus_info_model.dart';

/// 버스 도착 정보를 주기적으로 조회하는 서비스
class BusArrivalService {
  Timer? _pollingTimer;
  String? _currentBusNumber;
  String? _currentStationName;

  // 데스크탑 IP (api_service.dart와 동일하게 설정)
  static const String baseUrl = 'http://192.168.0.15:8000';

  /// polling 시작 (1분 주기)
  void startPolling({
    required String busNumber,
    required String stationName,
    required Function(BusArrivalInfo) onUpdate,
    required Function(String) onError,
  }) {
    // 이미 같은 버스/정류장에 대해 polling 중이면 중복 방지
    if (_pollingTimer != null &&
        _currentBusNumber == busNumber &&
        _currentStationName == stationName) {
      debugPrint('[BusArrivalService] 이미 polling 중: $busNumber @ $stationName');
      return;
    }

    // 기존 polling 중지
    stopPolling();

    _currentBusNumber = busNumber;
    _currentStationName = stationName;

    debugPrint('[BusArrivalService] Polling 시작: $busNumber @ $stationName');

    // 즉시 한 번 호출
    _fetchBusArrival(busNumber, stationName, onUpdate, onError);

    // 1분(60초) 주기로 반복 호출
    _pollingTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _fetchBusArrival(busNumber, stationName, onUpdate, onError);
    });
  }

  /// polling 중지
  void stopPolling() {
    if (_pollingTimer != null) {
      debugPrint('[BusArrivalService] Polling 중지');
      _pollingTimer?.cancel();
      _pollingTimer = null;
      _currentBusNumber = null;
      _currentStationName = null;
    }
  }

  /// 버스 도착 정보 API 호출
  Future<void> _fetchBusArrival(
    String busNumber,
    String stationName,
    Function(BusArrivalInfo) onUpdate,
    Function(String) onError,
  ) async {
    try {
      final url = Uri.parse(
        '$baseUrl/bus/arrival?bus_number=$busNumber&station_name=$stationName',
      );

      debugPrint('[BusArrivalService] API 호출: $url');

      final response = await http
          .get(url)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException('요청 시간 초과');
            },
          );

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final arrivalInfo = BusArrivalInfo.fromJson(data);

        debugPrint('[BusArrivalService] 도착 정보: ${arrivalInfo.statusMsg}');
        onUpdate(arrivalInfo);
      } else {
        final errorData = json.decode(utf8.decode(response.bodyBytes));
        final errorMsg = errorData['detail'] ?? 'HTTP ${response.statusCode}';
        debugPrint('[BusArrivalService] API 오류: $errorMsg');
        onError(errorMsg);
      }
    } catch (e) {
      debugPrint('[BusArrivalService] 네트워크 오류: $e');
      onError('네트워크 오류: $e');
    }
  }

  /// 현재 polling 중인지 확인
  bool get isPolling => _pollingTimer != null && _pollingTimer!.isActive;

  /// dispose (메모리 누수 방지)
  void dispose() {
    stopPolling();
  }
}
