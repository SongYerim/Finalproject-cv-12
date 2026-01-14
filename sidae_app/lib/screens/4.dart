// lib/4.dart
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart'; // 센서 패키지
import 'package:geolocator/geolocator.dart';     // GPS 패키지
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/services.dart'; // 진동 패키지
import 'package:flutter_naver_map/flutter_naver_map.dart';
import '../models/route_model.dart';
import '../services/route_tracker.dart';
import '5.dart';

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
  // --- 센서 및 위치 관련 변수 ---
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;
  StreamSubscription<Position>? _positionSubscription;

  // RouteTracker 사용 (5.dart와 공유)
  final RouteTracker _tracker = RouteTracker.instance;

  double _deviceHeading = 0.0;    // 내 폰이 바라보는 방향
  double _targetBearing = 0.0;    // 목적지 방향
  double _distanceToTarget = 0.0; // 남은 거리
  
  // 목표 좌표
  double _targetLat = 37.554722; 
  double _targetLng = 126.970833; 

  // GPS 기반 방향 계산용 변수
  List<Position> _recentPositions = []; // 최근 2개 GPS 좌표
  double _travelingBearing = -1.0; // 진행 방향 (최근 2개 GPS로 계산, -1은 미계산 상태)
  double _routeBearing = -1.0; // 경로상 가야 할 방향 (-1은 미계산 상태)

  DateTime _lastVibrationTime = DateTime.now();
  
  // 최소 이동 거리 (미터) - 이 거리 이상 이동해야 방향 계산
  static const double _minDistanceForBearing = 1.0;

  @override
  void initState() {
    super.initState();
    _setTargetFromRoutes(); // 1. 목표 좌표 설정
    _initSensor();          // 2. 나침반 시작
    _initLocation();        // 3. GPS 시작
  }

  // 경로 데이터 초기화
  void _setTargetFromRoutes() {
    // RouteTracker 초기화 (5.dart와 공유)
    List<NLatLng> allPathPoints = [];
    for (var route in widget.routes) {
      allPathPoints.addAll(route.pathCoordinates);
    }
    
    if (allPathPoints.isNotEmpty) {
      _tracker.initialize(allPathPoints);
      final targetPoint = _tracker.getCurrentTarget();
      if (targetPoint != null) {
        _targetLat = targetPoint.latitude;
        _targetLng = targetPoint.longitude;
      }
    }
  }

  @override
  void dispose() {
    _magnetometerSubscription?.cancel();
    _positionSubscription?.cancel();
    super.dispose();
  }

  // --- 센서 로직 ---
  void _initSensor() {
    _magnetometerSubscription = magnetometerEvents.listen((MagnetometerEvent event) {
      if (!mounted) return;
      // 수정: atan2(y, x)로 올바른 나침반 방향 계산
      double heading = math.atan2(event.y, event.x);
      heading = heading * (180 / math.pi);
      // 북쪽 기준으로 보정 (동쪽이 90도가 되도록)
      heading = 90 - heading;
      if (heading < 0) heading += 360;
      if (heading >= 360) heading -= 360;

      setState(() {
        _deviceHeading = heading;
      });
      _checkDirectionAndVibrate();
    });
  }

  void _initLocation() {
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

      // 1. 최근 GPS 좌표 저장 (최대 2개)
      _updateRecentPositions(position);

      // 2. 최근 2개 좌표로 진행 방향 계산
      _calculateTravelingBearing();

      // 3. 경로상 다음 목표 좌표 찾기 및 가야 할 방향 계산
      _updateRouteBearing(position);

      // 4. 경로 점 통과 체크 (5.dart와 동일)
      _checkAndUpdatePassedPoints(position);

      // 목표까지의 거리 계산 (기존 로직 유지)
      double distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        _targetLat,
        _targetLng,
      );

      setState(() {
        _distanceToTarget = distance;
      });
    });
  }

  // 최근 GPS 좌표 저장 (최대 2개)
  void _updateRecentPositions(Position position) {
    _recentPositions.add(position);
    if (_recentPositions.length > 2) {
      _recentPositions.removeAt(0); // 가장 오래된 좌표 제거
    }
  }

  // 최근 2개 GPS 좌표로 진행 방향 계산
  void _calculateTravelingBearing() {
    if (_recentPositions.length < 2) return;

    final prev = _recentPositions[0];
    final curr = _recentPositions[1];

    // 두 좌표 사이의 거리 계산
    double distance = Geolocator.distanceBetween(
      prev.latitude,
      prev.longitude,
      curr.latitude,
      curr.longitude,
    );

    // 최소 이동 거리 이상일 때만 방향 계산 (정지 시 불안정한 값 방지)
    if (distance < _minDistanceForBearing) return;

    // 이전 위치에서 현재 위치로의 방향 계산
    double bearing = Geolocator.bearingBetween(
      prev.latitude,
      prev.longitude,
      curr.latitude,
      curr.longitude,
    );
    if (bearing < 0) bearing += 360;

    _travelingBearing = bearing;
  }

  // 경로상 다음 목표 좌표 찾기 및 가야 할 방향 계산
  void _updateRouteBearing(Position currentPosition) {
    if (_tracker.allPathPoints.isEmpty) return;

    // 현재 위치
    final currentLat = currentPosition.latitude;
    final currentLng = currentPosition.longitude;

    // RouteTracker의 현재 목표 좌표 사용
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
      _targetLat = targetPoint.latitude;
      _targetLng = targetPoint.longitude;
    });
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
    // GPS 기반 방향이 있으면 사용, 없으면 센서 기반 사용
    double targetDir = _routeBearing >= 0 ? _routeBearing : _targetBearing;
    double currentDir = _travelingBearing >= 0 ? _travelingBearing : _deviceHeading;
    
    double diff = (targetDir - currentDir).abs();
    if (diff > 180) diff = 360 - diff;

    // 15도 이내로 방향이 맞으면 진동
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
    // _routeBearing이 유효하면 사용, 아니면 기존 _targetBearing 사용
    double targetDirection = _routeBearing >= 0 ? _routeBearing : _targetBearing;
    
    // 진행 방향(_travelingBearing)이 있으면 사용, 없으면 기존 _deviceHeading 사용
    double currentDirection = _travelingBearing >= 0 ? _travelingBearing : _deviceHeading;

    // 진행률 계산
    int passedCount = _tracker.pointsPassed.where((passed) => passed).length;
    double progress = _tracker.getProgress();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("실시간 길안내"),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // 진행 상황 표시
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            color: Colors.grey.shade900,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "진행 상황",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      "$passedCount / ${_tracker.allPathPoints.length} 지점 통과",
                      style: const TextStyle(
                        color: Colors.yellowAccent,
                        fontSize: 14,
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
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade700,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
                  ),
                ),
              ],
            ),
          ),
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
                    _travelingBearing >= 0 ? "(GPS 기반)" : "(센서 기반)",
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