import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import '../models/route_model.dart';
import '../services/route_tracker.dart';
import '../services/crosswalk_detector.dart';
import '../services/tts_service.dart';
import '../services/navigation_service.dart';
import '../services/bus_stop_detector.dart';
import '../services/bus_arrival_service.dart';
import '../models/bus_info_model.dart';
import '../widgets/progress_indicator_widget.dart';
import '5.dart';
import '6.dart';

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
  CrosswalkDetector? _crosswalkDetector;
  BusStopDetector? _busStopDetector;
  final BusArrivalService _busArrivalService = BusArrivalService();
  bool _isNavigatingToCrosswalk = false; // 카메라 중복 실행 방지 플래그

  double _distanceToTarget = 0.0;
  DateTime _lastVibrationTime = DateTime.now();

  // 버스 도착 정보
  BusArrivalInfo? _busArrivalInfo;
  String? _busArrivalError;

  @override
  void initState() {
    super.initState();
    _initializePathPoints();
    _initCrosswalkDetector();
    _initBusStopDetector();
    _ttsService.initialize();
    _navService.initSensor();
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
    _busArrivalService.dispose();
    _busStopDetector?.dispose();
    super.dispose();
  }

  // 횡단보도 근접 감지
  void _checkCrosswalk(Position position) {
    if (_isNavigatingToCrosswalk) return; // 이미 카메라로 이동 중이면 체크하지 않음
    if (_crosswalkDetector == null) return;
    _crosswalkDetector!.checkCrosswalkProximity(position);
  }

  // 버스 정류장 감지기 초기화
  void _initBusStopDetector() {
    _busStopDetector = BusStopDetector(
      routes: widget.routes,
      onBusStopDetected: (BusStopInfo busStopInfo) async {
        if (!mounted) return;
        await _ttsService.speak(
          "${busStopInfo.busNumber}번 버스 정류장에 도착했습니다. 버스 도착 정보를 확인하세요.",
        );
        HapticFeedback.vibrate();

        // 버스 도착 정보 polling 시작
        _busArrivalService.startPolling(
          busNumber: busStopInfo.busNumber,
          stationName: busStopInfo.stationName,
          onUpdate: (BusArrivalInfo arrivalInfo) {
            if (!mounted) return;
            setState(() {
              _busArrivalInfo = arrivalInfo;
              _busArrivalError = null;
            });
          },
          onError: (String error) {
            if (!mounted) return;
            setState(() {
              _busArrivalError = error;
            });
          },
        );
      },
    );
  }

  // 버스 정류장 근접 감지
  void _checkBusStop(Position position) {
    if (_busStopDetector == null) return;
    _busStopDetector!.checkBusStopProximity(position);
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

    debugPrint(
      "현재 목표: ${_tracker.currentTargetIndex}, 가장 가까운 점: $closestIndex, 거리: ${closestDistance.toStringAsFixed(1)}m",
    );

    // 가장 가까운 점이 임계값 이내면 해당 점까지 모두 통과 처리
    if (closestIndex >= 0 && closestDistance <= passThreshold) {
      setState(() {
        // 가장 가까운 점까지의 모든 점을 통과 처리
        _tracker.markAllPassedUpTo(closestIndex);
        // 다음 목표를 가장 가까운 점 다음으로 설정
        if (closestIndex + 1 < _tracker.allPathPoints.length) {
          _tracker.currentTargetIndex = closestIndex + 1;
        }
        debugPrint(
          "지점 $closestIndex까지 통과! 다음 목표: ${_tracker.currentTargetIndex}",
        );
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
        Transform.rotate(
          angle: angle,
          child: Icon(Icons.arrow_upward_rounded, size: 100, color: color),
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
    double currentDirection = _navService.travelingBearing >= 0
        ? _navService.travelingBearing
        : _navService.deviceHeading;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("실시간 길안내"),
        backgroundColor: Colors.black,
        foregroundColor: Colors.yellow, // 고대비: 노란색
      ),
      body: Column(
        children: [
          ProgressIndicatorWidget(tracker: _tracker),
          // 상단 절반: 화살표 & 거리 정보 (Arrow Section)
          Expanded(
            flex: 1,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey.shade800)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "남은 거리: ${_distanceToTarget.toStringAsFixed(0)}m",
                    style: const TextStyle(
                      color: Colors.yellow, // 고대비: 노란색
                      fontSize: 26,
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
                        angle: targetDirection * (math.pi / 180),
                        degrees: targetDirection.toStringAsFixed(0),
                        color: Colors.yellowAccent,
                      ),
                      // 진행 방향
                      _buildDirectionWidget(
                        label: "진행 방향",
                        angle: currentDirection * (math.pi / 180),
                        degrees: currentDirection.toStringAsFixed(0),
                        color: Colors.greenAccent,
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),
                  Text(
                    _navService.travelingBearing >= 0 ? "(GPS 기반)" : "(센서 기반)",
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),

          // ---------------------------------------------------------
          // 1.5. 버스 도착 정보 카드 (버스 정류장 도착 시 표시)
          // ----------------------------------------------------------
          if (_busArrivalInfo != null || _busArrivalError != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A), // 고대비: 어두운 회색
                border: Border.all(color: Colors.yellow, width: 2),
              ),
              child: _busArrivalInfo != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.directions_bus,
                              color: Colors.yellowAccent,
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${_busArrivalInfo!.busNumber}번 버스 도착 정보',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(
                              Icons.access_time,
                              color: Colors.greenAccent,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _busArrivalInfo!.statusMsg,
                              style: const TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '차량번호: ${_busArrivalInfo!.plateNo}',
                          style: TextStyle(
                            color: Colors.grey.shade300,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '정류장: ${_busArrivalInfo!.stationName}',
                          style: TextStyle(
                            color: Colors.grey.shade300,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.refresh,
                              color: Colors.grey.shade400,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '1분마다 자동 갱신',
                              style: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Colors.redAccent,
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              '버스 도착 정보 오류',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _busArrivalError ?? '알 수 없는 오류',
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 14,
                          ),
                        ),
                      ],
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
                        bottom: BorderSide(color: Colors.yellow, width: 2),
                      ),
                      color: const Color(0xFF2A2A2A), // 고대비: 어두운 회색
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "상세 경로 안내",
                          style: TextStyle(
                            color: Colors.yellow, // 고대비: 노란색
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Icon(
                          Icons.format_list_numbered,
                          color: Colors.yellow, // 고대비: 노란색
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
                            itemCount: widget.routes[0].stepDescription.length,
                            separatorBuilder: (context, index) =>
                                Divider(color: Colors.grey.shade800),
                            itemBuilder: (context, index) {
                              final stepDesc =
                                  widget.routes[0].stepDescription[index];

                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
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
              backgroundColor: Colors.yellow, // 고대비: 노란색 배경
              foregroundColor: Colors.black, // 고대비: 검은색 텍스트
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
