import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:math' as math;
import '../models/route_model.dart';
import '../services/route_tracker.dart';
import '../services/crosswalk_detector.dart';
import '../services/tts_service.dart';
import '../services/navigation_service.dart';
import '../services/bus_stop_detector.dart';
import '../services/bus_arrival_service.dart';
import '../models/bus_info_model.dart';
import '../widgets/progress_indicator_widget.dart';
import '6.dart';

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
  final NavigationService _navService = NavigationService();
  final TtsService _ttsService = TtsService.instance;
  CrosswalkDetector? _crosswalkDetector;
  BusStopDetector? _busStopDetector;
  final BusArrivalService _busArrivalService = BusArrivalService();
  Position? _currentPosition;
  static const double _passThreshold = 15.0;
  bool _isNavigatingToCrosswalk = false; // 화면 이동 중복 방지

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
    _navService.dispose();
    _busArrivalService.dispose();
    _busStopDetector?.dispose();
    super.dispose();
  }

  // 경로상의 모든 점들을 하나의 리스트로 합치기
  void _initializePathPoints() {
    // 이미 초기화되었으면 건너뛰기 (Screen4에서 이미 초기화된 경우)
    if (_tracker.allPathPoints.isNotEmpty) {
      debugPrint("RouteTracker 이미 초기화됨, 건너뛰기");
      return;
    }

    List<NLatLng> allPathPoints = [];
    for (var route in widget.routes) {
      allPathPoints.addAll(route.pathCoordinates);
    }

    // RouteTracker에 경로 초기화
    _tracker.initialize(allPathPoints);

    debugPrint("총 경로 점 개수: ${_tracker.allPathPoints.length}");
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
    if (closestIndex >= 0 && closestDistance <= _passThreshold) {
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
        circleColor = Colors.grey.withOpacity(0.5);
        radius = 5;
      } else if (i == _tracker.currentTargetIndex) {
        // 현재 목표: 노란색 (더 크게)
        circleColor = Colors.yellowAccent.withOpacity(0.8);
        radius = 10;
      } else {
        // 아직 안 지나간 점: 파란색
        circleColor = Colors.blueAccent.withOpacity(0.6);
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
      color: Colors.green.withOpacity(0.7),
      outlineColor: Colors.white,
      outlineWidth: 3,
    );

    final endCircle = NCircleOverlay(
      id: "end_circle",
      center: _tracker.allPathPoints.last,
      radius: 15,
      color: Colors.red.withOpacity(0.7),
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
                // 오른쪽 위에 버스 도착 정보 표시
                if (_busArrivalInfo != null || _busArrivalError != null)
                  Positioned(
                    top: 16,
                    right: 16,
                    child: _buildBusArrivalOverlay(),
                  ),
              ],
            ),
          ),

          // 범례
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade900,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildLegendItem(Colors.grey, "지나간 지점"),
                _buildLegendItem(Colors.yellowAccent, "현재 목표"),
                _buildLegendItem(Colors.blueAccent, "다음 지점"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectionInfo() {
    double targetDirection = _navService.routeBearing >= 0
        ? _navService.routeBearing
        : _navService.targetBearing;
    double currentDirection = _navService.travelingBearing >= 0
        ? _navService.travelingBearing
        : _navService.deviceHeading;

    // 각 방향의 절대 각도 (북쪽 기준)
    double targetAngle = targetDirection * (math.pi / 180);
    double currentAngle = currentDirection * (math.pi / 180);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.75),
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
              Transform.rotate(
                angle: targetAngle,
                child: const Icon(
                  Icons.arrow_upward_rounded,
                  size: 18,
                  color: Colors.yellowAccent,
                ),
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
              Transform.rotate(
                angle: currentAngle,
                child: const Icon(
                  Icons.arrow_upward_rounded,
                  size: 18,
                  color: Colors.greenAccent,
                ),
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
            _navService.travelingBearing >= 0 ? "(GPS 기반)" : "(센서 기반)",
            style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ],
    );
  }

  Widget _buildBusArrivalOverlay() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 250),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade900.withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.yellowAccent, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: _busArrivalInfo != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.directions_bus,
                      color: Colors.yellowAccent,
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${_busArrivalInfo!.busNumber}번 버스',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.access_time,
                      color: Colors.greenAccent,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _busArrivalInfo!.statusMsg,
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '📍 ${_busArrivalInfo!.stationName}',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  '🚗 ${_busArrivalInfo!.plateNo}',
                  style: TextStyle(color: Colors.grey.shade300, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.refresh, color: Colors.grey.shade400, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      '1분마다 갱신',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.redAccent,
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        '버스 정보 오류',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _busArrivalError ?? '알 수 없는 오류',
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ],
            ),
    );
  }
}
