import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:math' as math;
import '../models/route_model.dart';
import '../services/route_tracker.dart';
import '../services/crosswalk_detector.dart';
import '../services/bus_stop_detector.dart';
import '../services/bus_arrival_service.dart';
import '../services/bus_popup_state_service.dart';
import '../services/tts_service.dart';
import '../services/navigation_service.dart';
import '../widgets/progress_indicator_widget.dart';
import '../widgets/bus_arrival_overlay.dart';
import '../widgets/route_timeline_widget.dart';
import '../utils/bus_utils.dart' as bus_utils;
import '../utils/math_utils.dart' as math_utils;
import '6.dart';
import '7.dart';
import '9.dart';

class RouteTrackingMapScreen extends StatefulWidget {
  final List<RouteSegment> routes;
  final String destinationName;

  const RouteTrackingMapScreen({
    super.key,
    required this.routes,
    required this.destinationName,
  });

  @override
  State<RouteTrackingMapScreen> createState() => _RouteTrackingMapScreenState();
}

class _RouteTrackingMapScreenState extends State<RouteTrackingMapScreen> {
  NaverMapController? _mapController;
  final RouteTracker _tracker = RouteTracker.instance;
  final NavigationService _navService = NavigationService.instance;
  final TtsService _ttsService = TtsService.instance;
  final BusPopupStateService _popupState = BusPopupStateService.instance;
  final BusArrivalService _busArrivalService = BusArrivalService.instance;
  CrosswalkDetector? _crosswalkDetector;
  BusStopDetector? _busStopDetector;
  Position? _currentPosition;
  static const double _passThreshold = 15.0;
  bool _isNavigatingToCrosswalk = false; // 화면 이동 중복 방지
  double _distanceToTarget = 0.0;

  // 360-0 wrap-around 처리를 위한 이전 각도
  double _prevTargetAngle = 0.0;
  double _prevCurrentAngle = 0.0;

  // _isBusApproachingStatus -> bus_utils.isBusApproachingStatus 로 이동됨

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

    // 단계 변경 TTS 콜백 등록
    _tracker.onStepChanged = (segmentIndex, stepIndex, description) {
      if (mounted) {
        _ttsService.speak(description);
        setState(() {});
      }
    };

    // 도착 완료 콜백 등록
    _tracker.onRouteCompleted = () {
      if (!mounted) return;

      // 도착 화면으로 이동 (스택 교체)
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) =>
              ArrivalScreen(destinationName: widget.destinationName),
        ),
      );
    };

    // 도착 완료 콜백 등록
    _tracker.onRouteCompleted = () {
      if (!mounted) return;
      HapticFeedback.vibrate();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) =>
              ArrivalScreen(destinationName: widget.destinationName),
        ),
      );
    };

    // GPS 위치 추적 시작
    _navService.startLocationTracking(onUpdate: _onPositionUpdate);
  }

  void _initCrosswalkDetector() {
    _crosswalkDetector = CrosswalkDetector(
      routes: widget.routes,
      onCrosswalkDetected: (CrosswalkInfo crosswalkInfo) async {
        // 이미 화면 이동 중이면 무시 (중복 방지)
        if (_isNavigatingToCrosswalk) return;
        _isNavigatingToCrosswalk = true;

        if (!mounted) return;
        await _ttsService.speak("횡단보도 앞입니다. 카메라를 신호등쪽으로 돌려주세요.");
        HapticFeedback.vibrate();
        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
        Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (context) => YoloTestScreen(
              exitLat: crosswalkInfo.exitLat,
              exitLng: crosswalkInfo.exitLng,
            ),
          ),
        ).then((_) {
          // 카메라 화면에서 복귀 시 플래그 초기화
          if (mounted) {
            _isNavigatingToCrosswalk = false;
          }
        });
      },
    );
  }

  @override
  void dispose() {
    // NavigationService는 싱글톤 인스턴스로 dispose 하면 안 됨
    // _navService.dispose(); 제거
    super.dispose();
  }

  // 경로상의 모든 점들을 하나의 리스트로 합치기
  void _initializePathPoints() {
    // 이미 초기화되었으면 건너뛰기 (Screen4에서 이미 초기화된 경우)
    if (_tracker.allPathPoints.isNotEmpty) {
      return;
    }

    List<NLatLng> allPathPoints = [];
    for (var route in widget.routes) {
      allPathPoints.addAll(route.pathCoordinates);
    }

    // RouteTracker에 경로 초기화 (구간 정보 포함)
    _tracker.initialize(allPathPoints, routeSegments: widget.routes);
  }

  void _startLocationTracking() {
    _navService.startLocationTracking(onUpdate: _onPositionUpdate);
  }

  void _onPositionUpdate(Position position) {
    if (!mounted) return;
    setState(() {
      _currentPosition = position;
    });
    _checkCrosswalk(position);
    _checkBusStop(position);
    _checkAndUpdatePassedPoints(position);
    _updateMapMarkers();
  }

  // 횡단보도 근접 감지
  void _checkCrosswalk(Position position) {
    // 이미 카메라 화면으로 이동 중이면 추가 횡단보도 감지 무시
    if (_isNavigatingToCrosswalk) return;
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
            if (bus_utils.isBusApproachingStatus(arrival.statusMsg)) {
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

  // 버스 도착 정보 오버레이 위젯 -> BusArrivalOverlay로 이동됨
  Widget _buildBusArrivalOverlay() {
    return BusArrivalOverlay(
      popupState: _popupState,
      onClose: _closeBusArrivalOverlay,
    );
  }

  // 현재 위치를 기준으로 지나간 점들을 체크 -> RouteTracker로 로직 이동
  void _checkAndUpdatePassedPoints(Position position) {
    final updated = _tracker.findClosestPointAndUpdate(
      position.latitude,
      position.longitude,
      Geolocator.distanceBetween,
      passThreshold: _passThreshold,
    );
    if (updated) {
      setState(() {});
    }
  }

  // 지도에 마커 업데이트
  void _updateMapMarkers() {
    if (_mapController == null) return;

    // 경로 점들을 원으로 표시
    final Set<NAddableOverlay> overlays = {};

    for (int i = 0; i < _tracker.allPathPoints.length; i++) {
      Color circleColor;
      double radius;

      if (_tracker.pointsPassed[i]) {
        // 지나간 점: 회색
        circleColor = Colors.grey.withValues(alpha: 0.5);
        radius = 5;
      } else if (i == _tracker.currentTargetIndex) {
        // 현재 목표: 노란색 (더 크게)
        circleColor = Colors.yellowAccent.withValues(alpha: 0.8);
        radius = 10;
      } else {
        // 아직 안 지나간 점: 파란색
        circleColor = Colors.blueAccent.withValues(alpha: 0.6);
        radius = 6;
      }

      final circle = NCircleOverlay(
        id: "point_$i",
        center: _tracker.allPathPoints[i],
        radius: radius,
        color: circleColor,
        outlineColor: Colors.white,
        outlineWidth: 2,
      );

      overlays.add(circle);
    }

    // 내 위치 마커
    if (_currentPosition != null) {
      final myLocationMarker = NMarker(
        id: "my_location",
        position: NLatLng(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
        ),
        icon: const NOverlayImage.fromAssetImage('assets/sidae_logo.png'),
        size: const Size(40, 40),
      );
      overlays.add(myLocationMarker);
    }

    _mapController!.addOverlayAll(overlays);
  }

  // 경로 선 그리기
  void _drawRoutePath() {
    if (_mapController == null || _tracker.allPathPoints.isEmpty) return;

    final path = NPathOverlay(
      id: "route_path",
      coords: _tracker.allPathPoints,
      color: Colors.blueAccent,
      width: 8,
      outlineColor: Colors.white,
      outlineWidth: 2,
    );

    _mapController!.addOverlay(path);

    // 출발/도착 마커
    final startMarker = NMarker(
      id: "start",
      position: _tracker.allPathPoints.first,
      caption: NOverlayCaption(text: "출발", textSize: 14),
    );

    final endMarker = NMarker(
      id: "end",
      position: _tracker.allPathPoints.last,
      caption: NOverlayCaption(text: "도착", textSize: 14),
    );

    // 출발/도착 위치를 원으로 표시
    final startCircle = NCircleOverlay(
      id: "start_circle",
      center: _tracker.allPathPoints.first,
      radius: 15,
      color: Colors.green.withValues(alpha: 0.7),
      outlineColor: Colors.white,
      outlineWidth: 3,
    );

    final endCircle = NCircleOverlay(
      id: "end_circle",
      center: _tracker.allPathPoints.last,
      radius: 15,
      color: Colors.red.withValues(alpha: 0.7),
      outlineColor: Colors.white,
      outlineWidth: 3,
    );

    _mapController!.addOverlayAll({
      startMarker,
      endMarker,
      startCircle,
      endCircle,
    });

    // 카메라를 경로에 맞춤
    final cameraUpdate = NCameraUpdate.fitBounds(
      NLatLngBounds.from(_tracker.allPathPoints),
      padding: const EdgeInsets.all(60),
    );
    _mapController!.updateCamera(cameraUpdate);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.destinationName),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          ProgressIndicatorWidget(tracker: _tracker),

          // 지도
          Expanded(
            child: Stack(
              children: [
                NaverMap(
                  options: const NaverMapViewOptions(
                    locale: NLocale('ko'),
                    indoorEnable: true,
                    locationButtonEnable: true,
                    consumeSymbolTapEvents: false,
                  ),
                  onMapReady: (controller) {
                    _mapController = controller;
                    _drawRoutePath();
                    _updateMapMarkers();
                    _startLocationTracking();
                  },
                ),
                // 왼쪽 위에 방향 정보 표시
                Positioned(top: 16, left: 16, child: _buildDirectionInfo()),

                // 버스 도착 정보 오버레이
                if (_popupState.showPopup) _buildBusArrivalOverlay(),
              ],
            ),
          ),

          // 하단: 현재 구간 정보 (타임라인 컴팩트 버전)
          Container(
            width: double.infinity,
            color: Colors.grey.shade900,
            child: SafeArea(
              top: false,
              child: RouteTimelineWidget(
                routes: widget.routes,
                currentSegmentIndex: _tracker.currentSegmentIndex,
                currentStepIndex: _tracker.currentStepIndex,
                compact: true,
                onSegmentTap: (index) {
                  // 해당 세그먼트로 이동
                  _tracker.moveToSegment(index);
                  setState(() {});
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // _normalizeAngle -> math_utils.normalizeAngle 로 이동됨

  Widget _buildDirectionInfo() {
    double targetDirection = _navService.routeBearing >= 0
        ? _navService.routeBearing
        : _navService.targetBearing;
    // 센서 기반으로 통일 - GPS 오차 제거하여 안정적인 방향 표시
    double currentDirection = _navService.deviceHeading;

    // 각 방향의 절대 각도 (북쪽 기준)
    double targetAngle = targetDirection * (math.pi / 180);
    double currentAngle = currentDirection * (math.pi / 180);

    // 360-0 wrap-around 처리 (짧은 경로로 회전)
    targetAngle = math_utils.normalizeAngle(targetAngle, _prevTargetAngle);
    currentAngle = math_utils.normalizeAngle(currentAngle, _prevCurrentAngle);

    // 다음 프레임을 위해 저장
    _prevTargetAngle = targetAngle;
    _prevCurrentAngle = currentAngle;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.yellowAccent, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.navigation,
                color: Colors.yellowAccent,
                size: 16,
              ),
              const SizedBox(width: 6),
              const Text(
                "방향 정보",
                style: TextStyle(
                  color: Colors.yellowAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 가야할 방향
          Row(
            children: [
              // 부드러운 회전 애니메이션
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: targetAngle, end: targetAngle),
                duration: const Duration(milliseconds: 100),
                curve: Curves.easeOut,
                builder: (context, value, child) {
                  return Transform.rotate(
                    angle: value,
                    child: const Icon(
                      Icons.arrow_upward_rounded,
                      size: 18,
                      color: Colors.yellowAccent,
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              const Text(
                "가야할 방향:",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                "${targetDirection.toStringAsFixed(0)}°",
                style: const TextStyle(
                  color: Colors.yellowAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // 진행 방향
          Row(
            children: [
              // 부드러운 회전 애니메이션
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: currentAngle, end: currentAngle),
                duration: const Duration(milliseconds: 100),
                curve: Curves.easeOut,
                builder: (context, value, child) {
                  return Transform.rotate(
                    angle: value,
                    child: const Icon(
                      Icons.arrow_upward_rounded,
                      size: 18,
                      color: Colors.greenAccent,
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              const Text(
                "진행 방향:",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                "${currentDirection.toStringAsFixed(0)}°",
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            "(센서 기반)",
            style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
