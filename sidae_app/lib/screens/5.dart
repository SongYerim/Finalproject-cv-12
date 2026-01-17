// lib/5.dart
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_tts/flutter_tts.dart'; // TTS 추가
import 'package:flutter/services.dart'; // HapticFeedback 추가
import 'dart:async';
import 'dart:math' as math;
import '../models/route_model.dart';
import '../services/route_tracker.dart';
import '../services/crosswalk_detector.dart'; // CrosswalkDetector 추가
import '6.dart'; // YOLO 화면

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
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;
  
  // RouteTracker 사용
  final RouteTracker _tracker = RouteTracker.instance;
  
  // 횡단보도 감지기
  CrosswalkDetector? _crosswalkDetector;
  final FlutterTts _tts = FlutterTts();
  
  // 현재 위치
  Position? _currentPosition;
  
  // 지나간 것으로 판단하는 반경 (미터)
  static const double _passThreshold = 15.0;
  
  // 방향 관련 변수 (4.dart와 동일)
  double _deviceHeading = 0.0;       // 나침반 방향
  double _targetBearing = 0.0;       // 목표 방향
  List<Position> _recentPositions = []; // 최근 2개 GPS 좌표
  double _travelingBearing = -1.0;   // 진행 방향 (GPS 기반)
  double _routeBearing = -1.0;       // 경로상 가야할 방향
  static const double _minDistanceForBearing = 1.0;

  @override
  void initState() {
    super.initState();
    _initializePathPoints();
    _initCrosswalkDetector(); // 횡단보도 감지 초기화
    _initTts(); // TTS 초기화
    _initSensor();
    // _startLocationTracking()은 지도 초기화 후 호출됨
  }
  
  // 횡단보도 감지기 초기화
  void _initCrosswalkDetector() {
    _crosswalkDetector = CrosswalkDetector(
      routes: widget.routes,
      onCrosswalkDetected: (RouteStep crosswalkStep) async {
        if (!mounted) return;
        
        // 횡단보도 감지 시 TTS 안내
        await _tts.speak("횡단보도 앞입니다. 카메라를 신호등쪽으로 돌려달라");
        HapticFeedback.vibrate(); // 진동 알림
        debugPrint("🚶 횡단보도 감지: ${crosswalkStep.description}");
        
        // TTS 완료 후 YOLO 화면으로 전환
        await Future.delayed(const Duration(milliseconds: 500)); // TTS 시작 대기
        if (!mounted) return;
        
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const YoloTestScreen(),
          ),
        );
      },
    );
  }
  
  // TTS 초기화
  void _initTts() async {
    await _tts.setLanguage("ko-KR");
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _magnetometerSubscription?.cancel();
    super.dispose();
  }

  // 경로상의 모든 점들을 하나의 리스트로 합치기
  void _initializePathPoints() {
    List<NLatLng> allPathPoints = [];
    for (var route in widget.routes) {
      allPathPoints.addAll(route.pathCoordinates);
    }
    
    // RouteTracker에 경로 초기화
    _tracker.initialize(allPathPoints);
    
    debugPrint("총 경로 점 개수: ${_tracker.allPathPoints.length}");
  }

  // 센서 초기화 (4.dart와 동일)
  void _initSensor() {
    _magnetometerSubscription = magnetometerEvents.listen((MagnetometerEvent event) {
      if (!mounted) return;
      double heading = math.atan2(event.y, event.x);
      heading = heading * (180 / math.pi);
      heading = 90 - heading; // 북쪽 기준으로 보정
      if (heading < 0) heading += 360;
      if (heading >= 360) heading -= 360;

      setState(() {
        _deviceHeading = heading;
      });
    });
  }

  // 최근 GPS 좌표 저장 (4.dart와 동일)
  void _updateRecentPositions(Position position) {
    _recentPositions.add(position);
    if (_recentPositions.length > 2) {
      _recentPositions.removeAt(0);
    }
  }

  // 최근 2개 GPS 좌표로 진행 방향 계산 (4.dart와 동일)
  void _calculateTravelingBearing() {
    if (_recentPositions.length < 2) return;

    final prev = _recentPositions[0];
    final curr = _recentPositions[1];

    double distance = Geolocator.distanceBetween(
      prev.latitude,
      prev.longitude,
      curr.latitude,
      curr.longitude,
    );

    if (distance < _minDistanceForBearing) return;

    double bearing = Geolocator.bearingBetween(
      prev.latitude,
      prev.longitude,
      curr.latitude,
      curr.longitude,
    );
    if (bearing < 0) bearing += 360;

    setState(() {
      _travelingBearing = bearing;
    });
  }

  // 경로상 다음 목표 좌표 찾기 및 가야 할 방향 계산 (4.dart와 동일)
  void _updateRouteBearing(Position currentPosition) {
    if (_tracker.allPathPoints.isEmpty) return;

    final currentLat = currentPosition.latitude;
    final currentLng = currentPosition.longitude;

    // 현재 목표 좌표 가져오기
    final targetPoint = _tracker.getCurrentTarget();
    if (targetPoint == null) return;

    // 현재 목표까지의 방향 계산
    double bearing = Geolocator.bearingBetween(
      currentLat,
      currentLng,
      targetPoint.latitude,
      targetPoint.longitude,
    );
    if (bearing < 0) bearing += 360;

    setState(() {
      _routeBearing = bearing;
      _targetBearing = bearing;
    });
  }

  // GPS 위치 추적 시작
  void _startLocationTracking() {
    // 0.5초마다 GPS 위치 업데이트
    _positionSubscription = Stream.periodic(
      const Duration(milliseconds: 500), // 0.5초 간격
      (count) => count,
    ).asyncMap((_) async {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    }).listen((Position position) {
      if (!mounted) return;
      
      setState(() {
        _currentPosition = position;
      });
      
      // 방향 계산 (4.dart와 동일)
      _updateRecentPositions(position);
      _calculateTravelingBearing();
      _updateRouteBearing(position);
      
      // 횡단보도 감지
      _checkCrosswalk(position);
      
      _checkAndUpdatePassedPoints(position);
      _updateMapMarkers();
    });
  }
  
  // 횡단보도 근접 감지
  void _checkCrosswalk(Position position) {
    if (_crosswalkDetector == null) return;
    _crosswalkDetector!.checkCrosswalkProximity(position);
  }

  // 현재 위치를 기준으로 지나간 점들을 체크
  void _checkAndUpdatePassedPoints(Position position) {
    final targetPoint = _tracker.getCurrentTarget();
    if (targetPoint == null) return;

    // 현재 목표 점과의 거리 계산
    double distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      targetPoint.latitude,
      targetPoint.longitude,
    );

    debugPrint("현재 목표 인덱스: ${_tracker.currentTargetIndex}, 거리: ${distance.toStringAsFixed(1)}m");

    // 반경 이내에 들어왔으면 "지나감"으로 표시
    if (distance <= _passThreshold) {
      setState(() {
        _tracker.markAsPassed(_tracker.currentTargetIndex);
        _tracker.moveToNextTarget();
        debugPrint("지점 ${_tracker.currentTargetIndex} 통과! 다음 목표: ${_tracker.currentTargetIndex}");
      });

      // 다음 목표 인덱스가 여러 개의 점을 건너뛰어야 하는 경우 처리
      // (예: GPS가 부정확해서 중간 점을 건너뛴 경우)
      _skipNearbyPassedPoints(position);
    }
  }

  // 현재 위치 근처의 이미 지나쳤을 수 있는 점들을 자동으로 "지나감" 처리
  void _skipNearbyPassedPoints(Position position) {
    // 현재 목표 이전의 점들 중 가까운 점들을 찾아서 지나감 처리
    for (int i = 0; i < _tracker.currentTargetIndex && i < _tracker.allPathPoints.length; i++) {
      if (_tracker.pointsPassed[i]) continue; // 이미 지나간 점은 건너뛰기
      
      double distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        _tracker.allPathPoints[i].latitude,
        _tracker.allPathPoints[i].longitude,
      );
      
      // 뒤쪽 점이라도 매우 가까우면 지나간 것으로 처리
      if (distance <= _passThreshold) {
        _tracker.markAsPassed(i);
      }
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
        position: NLatLng(_currentPosition!.latitude, _currentPosition!.longitude),
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

    _mapController!.addOverlayAll({startMarker, endMarker, startCircle, endCircle});

    // 카메라를 경로에 맞춤
    final cameraUpdate = NCameraUpdate.fitBounds(
      NLatLngBounds.from(_tracker.allPathPoints),
      padding: const EdgeInsets.all(60),
    );
    _mapController!.updateCamera(cameraUpdate);
  }

  @override
  Widget build(BuildContext context) {
    // 진행률 계산
    int passedCount = _tracker.pointsPassed.where((passed) => passed).length;
    double progress = _tracker.getProgress();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.destinationName),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // 진행 상황 표시
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade900,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "진행 상황",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      "$passedCount / ${_tracker.allPathPoints.length} 지점 통과",
                      style: const TextStyle(
                        color: Colors.yellowAccent,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: Colors.grey.shade700,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
                  ),
                ),
              ],
            ),
          ),

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
                Positioned(
                  top: 16,
                  left: 16,
                  child: _buildDirectionInfo(),
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

  // 방향 정보 위젯
  Widget _buildDirectionInfo() {
    // 가야할 방향: GPS 기반이 있으면 사용, 없으면 계산된 목표 방향 사용
    double targetDirection = _routeBearing >= 0 ? _routeBearing : _targetBearing;
    
    // 진행 방향: GPS 기반이 있으면 사용, 없으면 센서 기반 사용
    double currentDirection = _travelingBearing >= 0 ? _travelingBearing : _deviceHeading;
    
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
            _travelingBearing >= 0 ? "(GPS 기반)" : "(센서 기반)",
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 11,
            ),
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
        Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ],
    );
  }
}
