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

  double _distanceToTarget = 0.0;
  DateTime _lastVibrationTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _initializePathPoints();
    _initCrosswalkDetector();
    _ttsService.initialize();
    _navService.initSensor();
    _navService.startLocationTracking(onUpdate: _onPositionUpdate);
  }

  void _initializePathPoints() {
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
      onCrosswalkDetected: (RouteStep crosswalkStep) async {
        if (!mounted) return;
        await _ttsService.speak("횡단보도 앞입니다. 카메라를 신호등쪽으로 돌려달라");
        HapticFeedback.vibrate();
        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const YoloTestScreen()),
        );
      },
    );
  }

  void _onPositionUpdate(Position position) {
    if (!mounted) return;
    _checkCrosswalk(position);
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
    if (_crosswalkDetector == null) return;
    _crosswalkDetector!.checkCrosswalkProximity(position);
  }

  // 현재 위치를 기준으로 지나간 점들을 체크 (5.dart와 동일)
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

    // 15미터 이내에 들어왔으면 "지나감"으로 표시
    const double passThreshold = 15.0;
    if (distance <= passThreshold) {
      setState(() {
        _tracker.markAsPassed(_tracker.currentTargetIndex);
        _tracker.moveToNextTarget();
        debugPrint("지점 ${_tracker.currentTargetIndex} 통과! 다음 목표: ${_tracker.currentTargetIndex}");
      });

      // 뒤처진 점들도 자동으로 지나감 처리
      _skipNearbyPassedPoints(position);
    }
  }

  // 현재 위치 근처의 이미 지나쳤을 수 있는 점들을 자동으로 "지나감" 처리
  void _skipNearbyPassedPoints(Position position) {
    const double passThreshold = 15.0;
    for (int i = 0; i < _tracker.currentTargetIndex && i < _tracker.allPathPoints.length; i++) {
      if (_tracker.pointsPassed[i]) continue;
      
      double distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        _tracker.allPathPoints[i].latitude,
        _tracker.allPathPoints[i].longitude,
      );
      
      if (distance <= passThreshold) {
        _tracker.markAsPassed(i);
      }
    }
  }

  void _checkDirectionAndVibrate() {
    double targetDir = _navService.routeBearing >= 0 ? _navService.routeBearing : _navService.targetBearing;
    double currentDir = _navService.travelingBearing >= 0 ? _navService.travelingBearing : _navService.deviceHeading;
    
    double diff = (targetDir - currentDir).abs();
    if (diff > 180) diff = 360 - diff;

    if (diff < 15 && DateTime.now().difference(_lastVibrationTime).inSeconds >= 1) {
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
          child: Icon(
            Icons.arrow_upward_rounded,
            size: 100,
            color: color,
          ),
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
    double targetDirection = _navService.routeBearing >= 0 ? _navService.routeBearing : _navService.targetBearing;
    double currentDirection = _navService.travelingBearing >= 0 ? _navService.travelingBearing : _navService.deviceHeading;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("실시간 길안내"),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
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
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 24, fontWeight: FontWeight.bold),
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
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.grey.shade800)),
                      color: Colors.grey.shade900,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "상세 경로 안내",
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Icon(Icons.format_list_numbered, color: Colors.grey.shade400),
                      ],
                    ),
                  ),

                  // 실제 리스트 (스크롤 가능)
                  Expanded(
                    child: widget.routes.isEmpty
                        ? const Center(child: Text("경로 정보가 없습니다.", style: TextStyle(color: Colors.grey)))
                        : ListView.separated(
                            padding: const EdgeInsets.all(20),
                            // 첫 번째 경로 세그먼트의 stepDescription 사용
                            itemCount: widget.routes[0].stepDescription.length,
                            separatorBuilder: (context, index) => Divider(color: Colors.grey.shade800),
                            itemBuilder: (context, index) {
                              final stepDesc = widget.routes[0].stepDescription[index];
                              
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
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RouteTrackingMapScreen(
                    routes: widget.routes,
                    destinationName: widget.destinationName,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.map),
            label: const Text("경로 추적 지도 보기"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }
}