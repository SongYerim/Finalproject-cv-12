import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import '../models/route_model.dart';
import '../services/route_tracker.dart';
import '../services/crosswalk_detector.dart';
import '../services/bus_stop_detector.dart';
import '../services/bus_arrival_service.dart';
import '../services/bus_popup_state_service.dart';
import '../services/tts_service.dart';
import '../services/navigation_service.dart';
import '../widgets/progress_indicator_widget.dart';
import '5.dart';
import '6.dart';
import '7.dart';

class Screen4 extends StatefulWidget {
  final List<RouteSegment> routes;
  final String destinationName;

  const Screen4({
    super.key,
    required this.routes,
    required this.destinationName,
  });

  @override
  State<Screen4> createState() => _Screen4State();
}

class _Screen4State extends State<Screen4> {
  final RouteTracker _tracker = RouteTracker.instance;
  final NavigationService _navService = NavigationService();
  final TtsService _ttsService = TtsService.instance;
  final BusPopupStateService _popupState = BusPopupStateService.instance;
  final BusArrivalService _busArrivalService = BusArrivalService.instance;
  CrosswalkDetector? _crosswalkDetector;
  BusStopDetector? _busStopDetector;
  bool _isNavigatingToCrosswalk = false; // 카메라 중복 실행 방지 플래그

  double _distanceToTarget = 0.0;
  DateTime _lastVibrationTime = DateTime.now();

  // 360-0 wrap-around 처리를 위한 이전 각도
  double _prevTargetAngle = 0.0;
  double _prevCurrentAngle = 0.0;

  /// "곧 도착" 상태인지 확인
  bool _isBusApproachingStatus(String statusMsg) {
    return statusMsg.contains('곧 도착') ||
        statusMsg.contains('잠시 후') ||
        statusMsg.contains('1분') ||
        statusMsg.contains('2분');
  }

  @override
  void initState() {
    super.initState();
    _initializePathPoints();
    _initCrosswalkDetector();
    _initBusStopDetector();
    _ttsService.initialize();
    _navService.initSensor();

    // 센서 방향 업데이트 시 UI 갱신 (60Hz)
    _navService.onBearingUpdate = () {
      if (mounted) {
        setState(() {}); // 센서 데이터 변경 시 즉시 UI 갱신
      }
    };

    // 팝업 상태 변경 리스너 등록
    _popupState.onStateChanged = () {
      if (mounted) {
        setState(() {}); // 팝업 상태 변경 시 UI 갱신
      }
    };

    _navService.startLocationTracking(onUpdate: _onPositionUpdate);
  }

  void _initializePathPoints() {
    // 이미 초기화되었으면 건너뛰기 (Screen5에서 돌아온 경우)
    if (_tracker.allPathPoints.isNotEmpty) return;

    List<NLatLng> allPathPoints = [];
    for (var route in widget.routes) {
      allPathPoints.addAll(route.pathCoordinates);
    }
    if (allPathPoints.isNotEmpty) {
      _tracker.initialize(allPathPoints);
    }
  }

  void _initCrosswalkDetector() {
    _crosswalkDetector = CrosswalkDetector(
      routes: widget.routes,
      onCrosswalkDetected: (CrosswalkInfo crosswalkInfo) async {
        if (_isNavigatingToCrosswalk) return; // 이미 카메라로 이동 중이면 무시
        _isNavigatingToCrosswalk = true; // 플래그 설정

        if (!mounted) return;
        await _ttsService.speak("횡단보도 앞입니다. 카메라를 신호등쪽으로 돌려주세요.");
        HapticFeedback.vibrate();
        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => YoloTestScreen(
              exitLat: crosswalkInfo.exitLat,
              exitLng: crosswalkInfo.exitLng,
            ),
          ),
        ).then((_) {
          if (mounted) _isNavigatingToCrosswalk = false; // 카메라에서 돌아오면 플래그 해제
        });
      },
    );
  }

  void _onPositionUpdate(Position position) {
    if (!mounted) return;
    _checkCrosswalk(position);
    _checkBusStop(position);
    _checkAndUpdatePassedPoints(position);
    _distanceToTarget = _navService.getDistanceToTarget(position);
    _checkDirectionAndVibrate();
    setState(() {});
  }

  @override
  void dispose() {
    _navService.dispose();
    super.dispose();
  }

  // 횡단보도 근접 감지
  void _checkCrosswalk(Position position) {
    if (_isNavigatingToCrosswalk) return; // 이미 카메라로 이동 중이면 체크하지 않음
    if (_crosswalkDetector == null) return;
    _crosswalkDetector!.checkCrosswalkProximity(position);
  }

  // 버스 정류장 근접 감지
  void _checkBusStop(Position position) {
    if (_popupState.isNavigatingToBusStop) return;
    if (_busStopDetector == null) return;
    _busStopDetector!.checkBusStopProximity(position);
  }

  // 버스 정류장 감지기 초기화
  void _initBusStopDetector() {
    _busStopDetector = BusStopDetector(
      routes: widget.routes,
      onBusStopDetected: (BusStopInfo busStopInfo) async {
        if (_popupState.isNavigatingToBusStop) return;

        if (!mounted) return;
        await _ttsService.speak("버스 정류장에 도착했습니다.");
        HapticFeedback.vibrate();

        // 버스 도착 정보 오버레이 표시 (전역 상태)
        _popupState.openPopup(busStopInfo.stationName);

        // 버스 도착 정보 조회 시작
        _busArrivalService.onArrivalUpdate = (arrival) {
          if (!mounted) return;
          // BusPopupStateService로 데이터 업데이트 (모든 화면에서 공유)
          _popupState.updateBusArrival(arrival);
          if (arrival != null) {
            // 응답이 올 때마다 오버레이 다시 표시 (사용자가 닫아도 자동으로 다시 켜짐)
            _popupState.openPopup(busStopInfo.stationName);
          }
          if (arrival != null) {
            _ttsService.speak("${arrival.busNumber}번 버스, ${arrival.statusMsg}");

            // "곧 도착" 상태 감지 시 BusArrivalScreen으로 화면 전환
            if (_isBusApproachingStatus(arrival.statusMsg)) {
              // 곧 도착 상태일 때 추적 종료
              _busArrivalService.stopTracking();
              _closeBusArrivalOverlay();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => BusArrivalScreen(
                    busNumber: arrival.busNumber,
                    stationName: busStopInfo.stationName,
                    enableCamera: true, // 카메라 모드 활성화
                  ),
                ),
              ).then((_) {
                if (mounted) {
                  _popupState.closePopup();
                }
              });
            }
          }
        };
        await _busArrivalService.startTracking(
          busStopInfo.busNumber,
          busStopInfo.stationName,
        );
      },
    );
  }

  // 버스 도착 오버레이 닫기 (추적은 계속)
  void _closeBusArrivalOverlay() {
    // stopTracking() 호출 제거 - 팝업 닫어도 백그라운드에서 계속 갱신
    _popupState.closePopup();
  }

  // 버스 도착 정보 오버레이 위젯 (간소화)
  Widget _buildBusArrivalOverlay() {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 100,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).primaryColor, width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 간소화된 헤더
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _popupState.busStationName ?? '버스 정류장',
                  style: TextStyle(
                    color: Theme.of(context).primaryColor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _closeBusArrivalOverlay,
                ),
              ],
            ),
            if (_popupState.busArrival != null) ...[
              // 버스 번호 + 남은 시간 (한 줄로)
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _popupState.busArrival!.busNumber,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _popupState.busArrival!.statusMsg,
                    style: const TextStyle(
                      color: Colors.orange,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ] else
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(
                    color: Colors.blue,
                    strokeWidth: 2,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // 현재 위치를 기준으로 지나간 점들을 체크
  void _checkAndUpdatePassedPoints(Position position) {
    if (_tracker.allPathPoints.isEmpty) return;

    const double passThreshold = 15.0;

    // 현재 목표부터 끝까지 모든 점들을 스캔하여 가장 가까운 점 찾기
    int closestIndex = -1;
    double closestDistance = double.infinity;

    for (
      int i = _tracker.currentTargetIndex;
      i < _tracker.allPathPoints.length;
      i++
    ) {
      double distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        _tracker.allPathPoints[i].latitude,
        _tracker.allPathPoints[i].longitude,
      );

      if (distance < closestDistance) {
        closestDistance = distance;
        closestIndex = i;
      }
    }

    // 가장 가까운 점이 임계값 이내면 해당 점까지 모두 통과 처리
    if (closestIndex >= 0 && closestDistance <= passThreshold) {
      setState(() {
        // 가장 가까운 점까지의 모든 점을 통과 처리
        _tracker.markAllPassedUpTo(closestIndex);
        // 다음 목표를 가장 가까운 점 다음으로 설정
        if (closestIndex + 1 < _tracker.allPathPoints.length) {
          _tracker.currentTargetIndex = closestIndex + 1;
        }
      });
    }
  }

  void _checkDirectionAndVibrate() {
    double targetDir = _navService.routeBearing >= 0
        ? _navService.routeBearing
        : _navService.targetBearing;
    double currentDir = _navService.travelingBearing >= 0
        ? _navService.travelingBearing
        : _navService.deviceHeading;

    double diff = (targetDir - currentDir).abs();
    if (diff > 180) diff = 360 - diff;

    if (diff < 15 &&
        DateTime.now().difference(_lastVibrationTime).inSeconds >= 1) {
      HapticFeedback.heavyImpact();
      _lastVibrationTime = DateTime.now();
    }
  }

  // 각도 정규화: 360도 wrap-around 시 짧은 경로로 회전
  double _normalizeAngle(double newAngle, double prevAngle) {
    double diff = newAngle - prevAngle;
    // 180도 이상 차이나면 반대 방향이 더 짧음
    if (diff > math.pi) {
      newAngle -= 2 * math.pi; // 360도 빼기
    } else if (diff < -math.pi) {
      newAngle += 2 * math.pi; // 360도 더하기
    }
    return newAngle;
  }

  // 방향 위젯 빌더
  Widget _buildDirectionWidget({
    required String label,
    required double angle,
    required String degrees,
    required Color color,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 15),
        // 부드러운 회전을 위한 애니메이션
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: angle, end: angle),
          duration: const Duration(milliseconds: 100), // 부드러운 전환
          curve: Curves.easeOut,
          builder: (context, value, child) {
            return Transform.rotate(
              angle: value,
              child: Icon(Icons.arrow_upward_rounded, size: 100, color: color),
            );
          },
        ),
        const SizedBox(height: 10),
        Text(
          "$degrees°",
          style: TextStyle(
            color: color,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    double targetDirection = _navService.routeBearing >= 0
        ? _navService.routeBearing
        : _navService.targetBearing;
    // 센서 기반으로 통일 - GPS 오차 제거하여 안정적인 방향 표시
    double currentDirection = _navService.deviceHeading;

    // 라디안으로 변환
    double targetAngle = targetDirection * (math.pi / 180);
    double currentAngle = currentDirection * (math.pi / 180);

    // 360-0 wrap-around 처리 (짧은 경로로 회전)
    targetAngle = _normalizeAngle(targetAngle, _prevTargetAngle);
    currentAngle = _normalizeAngle(currentAngle, _prevCurrentAngle);

    // 다음 프레임을 위해 저장
    _prevTargetAngle = targetAngle;
    _prevCurrentAngle = currentAngle;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("실시간 길안내"),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              ProgressIndicatorWidget(tracker: _tracker),
              // 상단 절반: 화살표 & 거리 정보 (Arrow Section)
              Expanded(
                flex: 1,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade800),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "남은 거리: ${_distanceToTarget.toStringAsFixed(0)}m",
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 30),

                      // 두 방향 동시 표시
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // 가야할 방향
                          _buildDirectionWidget(
                            label: "가야할 방향",
                            angle: targetAngle, // 이미 정규화된 라디안 값
                            degrees: targetDirection.toStringAsFixed(0),
                            color: Colors.yellowAccent,
                          ),
                          // 진행 방향
                          _buildDirectionWidget(
                            label: "진행 방향",
                            angle: currentAngle, // 이미 정규화된 라디안 값
                            degrees: currentDirection.toStringAsFixed(0),
                            color: Colors.greenAccent,
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),
                      Text(
                        _navService.travelingBearing >= 0
                            ? "(GPS 기반)"
                            : "(센서 기반)",
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ---------------------------------------------------------
              // 2. 하단 절반: 상세 경로 단계 리스트 (Steps List)
              // ---------------------------------------------------------
              Expanded(
                flex: 1,
                child: Container(
                  width: double.infinity,
                  color: Colors.black,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 리스트 헤더
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 15,
                        ),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Colors.grey.shade800),
                          ),
                          color: Colors.grey.shade900,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "상세 경로 안내",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Icon(
                              Icons.format_list_numbered,
                              color: Colors.grey.shade400,
                            ),
                          ],
                        ),
                      ),

                      // 실제 리스트 (스크롤 가능)
                      Expanded(
                        child: widget.routes.isEmpty
                            ? const Center(
                                child: Text(
                                  "경로 정보가 없습니다.",
                                  style: TextStyle(color: Colors.grey),
                                ),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.all(20),
                                // 첫 번째 경로 세그먼트의 stepDescription 사용
                                itemCount:
                                    widget.routes[0].stepDescription.length,
                                separatorBuilder: (context, index) =>
                                    Divider(color: Colors.grey.shade800),
                                itemBuilder: (context, index) {
                                  final stepDesc =
                                      widget.routes[0].stepDescription[index];

                                  return Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // 노란색 번호 원
                                      Container(
                                        width: 28,
                                        height: 28,
                                        alignment: Alignment.center,
                                        decoration: const BoxDecoration(
                                          color: Colors.yellowAccent,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Text(
                                          "${index + 1}",
                                          style: const TextStyle(
                                            color: Colors.black,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 15),

                                      // 설명 텍스트
                                      Expanded(
                                        child: Text(
                                          stepDesc,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 18,
                                            height: 1.4,
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // 버스 도착 정보 오버레이
          if (_popupState.showPopup) _buildBusArrivalOverlay(),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        color: Colors.black,
        child: SafeArea(
          child: ElevatedButton.icon(
            onPressed: () {
              _navService.stopLocationTracking(); // Screen5로 이동 전 GPS 추적 중지
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RouteTrackingMapScreen(
                    routes: widget.routes,
                    destinationName: widget.destinationName,
                  ),
                ),
              ).then((_) {
                // Screen5에서 돌아오면 GPS 추적 재개
                if (mounted) {
                  _navService.startLocationTracking(
                    onUpdate: _onPositionUpdate,
                  );
                }
              });
            },
            icon: const Icon(Icons.map),
            label: const Text("경로 추적 지도 보기"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
