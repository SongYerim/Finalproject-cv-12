import 'dart:developer' as developer;
import 'bus_arrival_service.dart';

/// 버스 정류장 팝업 상태를 전역으로 관리하는 Singleton 서비스
///
/// 4.dart와 5.dart가 동일한 팝업 상태를 공유하도록 합니다.
/// 한 화면에서 팝업을 닫으면 다른 화면에서도 즉시 반영됩니다.
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

  // 상태 변경 콜백 (여러 화면에서 구독 가능)
  Function()? onStateChanged;

  // Getters
  bool get showPopup => _showPopup;
  String? get busStationName => _busStationName;
  bool get isNavigatingToBusStop => _isNavigatingToBusStop;
  BusArrival? get busArrival => _busArrival;

  /// 팝업 열기
  void openPopup(String stationName) {
    developer.log(
      '📂 [BusPopupStateService] 팝업 열기: $stationName',
      name: 'BusPopupStateService',
    );
    _showPopup = true;
    _busStationName = stationName;
    _isNavigatingToBusStop = true;
    onStateChanged?.call();
  }

  /// 버스 도착 정보 업데이트
  void updateBusArrival(BusArrival? arrival) {
    developer.log(
      '🚌 [BusPopupStateService] 버스 도착 정보 업데이트: ${arrival?.statusMsg}',
      name: 'BusPopupStateService',
    );
    _busArrival = arrival;
    onStateChanged?.call();
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
    onStateChanged?.call();
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
    // 초기화 시에는 콜백 호출하지 않음 (화면이 이미 dispose된 상태)
  }
}
