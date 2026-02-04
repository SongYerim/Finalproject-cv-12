import 'package:flutter/foundation.dart';
import 'dart:developer' as developer;
import 'bus_arrival_service.dart';

/// 버스 정류장 팝업 상태를 전역으로 관리하는 Singleton 서비스
///
/// 4.dart와 5.dart가 동일한 팝업 상태를 공유하도록 합니다.
/// Observer 패턴을 적용하여 여러 화면에서 상태 변화를 감지할 수 있습니다.
class BusPopupStateService {
  // Singleton 패턴
  static final BusPopupStateService _instance =
      BusPopupStateService._internal();
  factory BusPopupStateService() => _instance;
  static BusPopupStateService get instance => _instance;
  BusPopupStateService._internal();

  // 팝업 상태
  bool _showPopup = false;
  String? _busStationName;
  bool _isNavigatingToBusStop = false;

  // 버스 도착 정보 (전역 공유)
  BusArrival? _busArrival;

  // 버스 도착 서비스 인스턴스
  final BusArrivalService _busArrivalService = BusArrivalService.instance;

  // 리스너 목록
  final List<VoidCallback> _listeners = [];

  // Getters
  bool get showPopup => _showPopup;
  String? get busStationName => _busStationName;
  bool get isNavigatingToBusStop => _isNavigatingToBusStop;
  BusArrival? get busArrival => _busArrival;

  /// 리스너 등록
  void addListener(VoidCallback listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  /// 리스너 제거
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  /// 상태 변경 알림
  void notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }

  /// 팝업 열기
  void openPopup(String stationName) {
    developer.log(
      '📂 [BusPopupStateService] 팝업 열기: $stationName',
      name: 'BusPopupStateService',
    );
    _showPopup = true;
    _busStationName = stationName;
    _isNavigatingToBusStop = true;
    notifyListeners();
  }

  /// 버스 도착 정보 업데이트 (내부 호출용)
  void _updateBusArrival(BusArrival? arrival) {
    developer.log(
      '🚌 [BusPopupStateService] 버스 도착 정보 업데이트: ${arrival?.statusMsg}',
      name: 'BusPopupStateService',
    );
    _busArrival = arrival;
    notifyListeners();
  }

  /// 버스 도착 추적 시작 (중앙 집중식 관리)
  Future<void> startBusTracking(String busNumber, String stationName) async {
    developer.log(
      '🚀 [BusPopupStateService] 버스 추적 시작 요청: $busNumber @ $stationName',
      name: 'BusPopupStateService',
    );

    // 팝업 먼저 열기
    openPopup(stationName);

    // BusArrivalService 콜백 연결
    _busArrivalService.onArrivalUpdate = (arrival) {
      _updateBusArrival(arrival);

      // 갱신 시마다 팝업이 닫혀있다면 다시 열기 (요구사항: 계속 떠있어야 함)
      if (!_showPopup && arrival != null) {
        _showPopup = true;
        _busStationName = stationName;
        // _isNavigatingToBusStop 은 여기서 건드리지 않음 (초기 진입시에만 true)
        notifyListeners();
      }
    };

    // 추적 시작
    await _busArrivalService.startTracking(busNumber, stationName);
  }

  /// 버스 도착 추적 중지
  void stopBusTracking() {
    developer.log(
      '🛑 [BusPopupStateService] 버스 추적 중지 요청',
      name: 'BusPopupStateService',
    );
    _busArrivalService.stopTracking();
    closePopup();
  }

  /// 팝업 닫기
  void closePopup() {
    developer.log(
      '📁 [BusPopupStateService] 팝업 닫기',
      name: 'BusPopupStateService',
    );
    _showPopup = false;
    _busStationName = null;
    _isNavigatingToBusStop = false;
    _busArrival = null;
    notifyListeners();
  }

  /// 상태 초기화 (화면 완전 종료 시)
  void reset() {
    developer.log(
      '🔄 [BusPopupStateService] 상태 초기화',
      name: 'BusPopupStateService',
    );
    _showPopup = false;
    _busStationName = null;
    _isNavigatingToBusStop = false;
    _busArrival = null;
    _listeners.clear();
    // 서비스 중지
    _busArrivalService.stopTracking();
  }
}
