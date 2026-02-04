import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import '../models/route_model.dart';
import '../services/tts_service.dart';
import '4.dart'; // 4.dart 파일 임포트 (파일 경로 확인 필요)

class MapResultScreen extends StatefulWidget {
  final List<RouteSegment> routes;
  final String destinationName;

  const MapResultScreen({
    super.key,
    required this.routes,
    required this.destinationName,
  });

  @override
  State<MapResultScreen> createState() => _MapResultScreenState();
}

class _MapResultScreenState extends State<MapResultScreen> {
  NaverMapController? _mapController;
  StreamSubscription<Position>? _positionSubscription;
  NMarker? _currentLocationMarker;
  final TtsService _ttsService = TtsService.instance;
  Timer? _autoStartTimer;

  @override
  void initState() {
    super.initState();
    _ttsService.initialize();
    // 화면 로드 후 경로 요약 TTS
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _announceRouteSummary();
    });
  }

  @override
  void dispose() {
    _autoStartTimer?.cancel();
    _ttsService.stop();
    _positionSubscription?.cancel();
    super.dispose();
  }

  /// 경로 요약 TTS 안내
  Future<void> _announceRouteSummary() async {
    if (widget.routes.isEmpty) return;

    final segments = widget.routes;
    final segmentCount = segments.length;

    // 각 구간 설명 생성
    List<String> segmentDescriptions = [];
    for (final segment in segments) {
      if (segment.moveType == "WALK") {
        // 도보 구간: 시간만 표시
        final minutes = (segment.duration / 60).ceil();
        segmentDescriptions.add("도보 ${minutes}분");
      } else {
        // 버스/지하철 구간: 노선번호 + 정거장 수 + 하차 정류장
        final transportName = segment.transportName ?? "버스";
        final stationCount = segment.stations.length;
        final endStation = segment.endStation;

        if (stationCount > 0 && endStation != null) {
          segmentDescriptions.add(
            "$transportName번 ${stationCount}정거장, $endStation 하차",
          );
        } else if (stationCount > 0) {
          segmentDescriptions.add("$transportName번 ${stationCount}정거장");
        } else if (endStation != null) {
          segmentDescriptions.add("$transportName번, $endStation 하차");
        } else {
          final minutes = (segment.duration / 60).ceil();
          segmentDescriptions.add("$transportName번 ${minutes}분");
        }
      }
    }

    // TTS 메시지 생성
    final summary = segmentDescriptions.join(", ");
    final message = "목적지까지 총 $segmentCount개 구간입니다. $summary.";
    // 안내 시작 버튼 안내 제거 (자동 시작 멘트로 대체)

    await _ttsService.speak(message);

    // 5초 자동 시작 안내
    if (!mounted) return;
    await _ttsService.speak(
      "5초 뒤 자동으로 안내를 시작합니다.",
      onCompleted: () {
        if (!mounted) return;
        // 타이머 시작 (TTS 종료 시점부터 5초)
        _autoStartTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) {
            _navigateToScreen4();
          }
        });
      },
    );
  }

  void _navigateToScreen4() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Screen4(
          routes: widget.routes,
          destinationName: widget.destinationName,
        ),
      ),
    );
  }

  void _initLocationTracking() {
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // 5m마다 업데이트
    );

    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (Position position) {
            if (!mounted || _mapController == null) return;

            _updateCurrentLocationMarker(position);
          },
        );
  }

  void _updateCurrentLocationMarker(Position position) {
    final currentPos = NLatLng(position.latitude, position.longitude);

    // 기존 마커가 있으면 제거
    if (_currentLocationMarker != null) {
      _mapController!.deleteOverlay(_currentLocationMarker!.info);
    }

    // 새 마커 생성
    _currentLocationMarker = NMarker(
      id: "current_location",
      position: currentPos,
      icon: const NOverlayImage.fromAssetImage('assets/sidae_logo.png'),
      size: const Size(40, 40),
      caption: NOverlayCaption(
        text: "내 위치",
        color: Colors.white,
        haloColor: Colors.blue,
      ),
    );

    // 마커 추가
    _mapController!.addOverlay(_currentLocationMarker!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.destinationName),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // 1. 상단 절반: 네이버 지도
          Expanded(
            flex: 1,
            child: NaverMap(
              options: const NaverMapViewOptions(
                locale: NLocale('ko'),
                indoorEnable: true,
                locationButtonEnable: true,
                consumeSymbolTapEvents: false,
                contentPadding: EdgeInsets.only(bottom: 20),
              ),
              onMapReady: (controller) {
                _mapController = controller;
                _drawRouteOnMap();
                _initLocationTracking(); // GPS 위치 추적 시작
              },
            ),
          ),

          // 2. 하단 절반: 경로 정보 및 안내 시작 버튼
          Expanded(
            flex: 1,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24), // 패딩 설정
              color: Colors.black,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "경로 안내",
                    style: TextStyle(
                      color: Theme.of(context).primaryColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 타임라인 형태 경로 표시
                  Expanded(
                    child: SingleChildScrollView(
                      child: widget.routes.isNotEmpty
                          ? _buildRouteTimeline()
                          : const Center(
                              child: Text(
                                "안내 정보를 불러오는 중...",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                ),
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 안내 시작 버튼 (박스)
                  GestureDetector(
                    onTap: () {
                      _autoStartTimer?.cancel(); // 수동 시작 시 타이머 취소
                      _navigateToScreen4();
                    },
                    child: Container(
                      width: double.infinity, // 가로 꽉 차게
                      height: 80, // 버튼 높이 (터치하기 편하게 큼직하게)
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor, // 눈에 잘 띄는 노란색
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        "안내 시작",
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 28, // 글자 크게
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // (이하 _drawRouteOnMap 함수는 기존과 동일하므로 생략 가능, 혹은 그대로 유지)
  void _drawRouteOnMap() {
    if (_mapController == null || widget.routes.isEmpty) return;

    // 1. 카메라 이동 범위를 계산하기 위해 모든 좌표를 모을 리스트
    final allBoundsCoords = <NLatLng>[];

    // 오버레이를 한 번에 추가하기 위한 Set
    final Set<NAddableOverlay> overlays = {};

    for (int i = 0; i < widget.routes.length; i++) {
      final segment = widget.routes[i];
      if (segment.pathCoordinates.isEmpty) continue;

      // 카메라 범위 계산용 좌표 수집
      allBoundsCoords.addAll(segment.pathCoordinates);

      // 2. 이동 수단에 따른 색상 분기 처리
      Color routeColor;
      Color outlineColor;

      if (segment.moveType == "WALK") {
        // 도보: 초록색 (또는 회색 점선 등 원하는 스타일)
        routeColor = Colors.green;
        outlineColor = Colors.white;
      } else {
        // 버스 (또는 기타): 파란색
        routeColor = Colors.blueAccent;
        outlineColor = Colors.white;
      }

      // 3. 개별 경로 오버레이 생성
      // id는 유니크해야 하므로 인덱스를 활용합니다.
      final path = NPathOverlay(
        id: "route_path_$i",
        coords: segment.pathCoordinates,
        color: routeColor,
        width: 10,
        outlineColor: outlineColor,
        // 도보인 경우 패턴을 주고 싶다면 아래 속성 활용 가능 (선택사항)
        // patternInterval: segment.move_type == "WALK" ? 10 : 0,
      );

      overlays.add(path);
    }

    // 4. 모든 경로 오버레이를 지도에 추가
    if (overlays.isNotEmpty) {
      _mapController!.addOverlayAll(overlays);

      // 5. 출발/도착 마커 추가 (기존 로직 유지)
      final startMarker = NMarker(
        id: "start",
        position: allBoundsCoords.first,
        caption: NOverlayCaption(text: "출발"),
      );
      final endMarker = NMarker(
        id: "end",
        position: allBoundsCoords.last,
        caption: NOverlayCaption(text: "도착"),
      );
      _mapController!.addOverlayAll({startMarker, endMarker});

      // 6. 모든 경로가 보이도록 카메라 이동
      final cameraUpdate = NCameraUpdate.fitBounds(
        NLatLngBounds.from(allBoundsCoords),
        padding: const EdgeInsets.all(40),
      );
      _mapController!.updateCamera(cameraUpdate);
    }
  }

  /// 타임라인 형태로 경로 표시
  Widget _buildRouteTimeline() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 출발 지점
        _buildTimelinePoint("출발", isStart: true),

        // 각 구간 표시
        for (int i = 0; i < widget.routes.length; i++) ...[
          _buildTimelineSegment(
            widget.routes[i],
            isLast: i == widget.routes.length - 1,
          ),
        ],

        // 도착 지점
        _buildTimelinePoint("도착", isEnd: true),
      ],
    );
  }

  /// 타임라인 시작/끝 지점
  Widget _buildTimelinePoint(
    String label, {
    bool isStart = false,
    bool isEnd = false,
  }) {
    return Row(
      children: [
        // 원형 포인트
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isStart ? Colors.green : (isEnd ? Colors.red : Colors.grey),
            border: Border.all(color: Colors.white, width: 2),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  /// 타임라인 구간 (도보/버스)
  Widget _buildTimelineSegment(RouteSegment segment, {bool isLast = false}) {
    final isWalk = segment.moveType == "WALK";
    final color = isWalk ? Colors.green : Colors.blue;
    final icon = isWalk ? Icons.directions_walk : Icons.directions_bus;
    final label = isWalk ? "도보" : "버스 ${segment.transportName ?? ''}";

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 왼쪽: 세로 라인 + 아이콘
          SizedBox(
            width: 20,
            child: Column(
              children: [
                // 세로 라인 (위쪽)
                Expanded(child: Container(width: 3, color: color)),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // 오른쪽: 구간 정보 카드
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color, width: 2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 구간 헤더 (아이콘 + 라벨)
                  Row(
                    children: [
                      Icon(icon, color: color, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: TextStyle(
                          color: color,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (segment.description.isNotEmpty) ...[
                        const Spacer(),
                        Text(
                          segment.description,
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ],
                  ),

                  // 버스/지하철인 경우 승하차 정류장 표시
                  if (!isWalk &&
                      (segment.startStation != null ||
                          segment.endStation != null)) ...[
                    const SizedBox(height: 12),
                    // 승차 정류장
                    if (segment.startStation != null)
                      _buildStationRow(
                        icon: Icons.arrow_circle_up,
                        label: "승차",
                        stationName: segment.startStation!,
                        color: Colors.green,
                      ),
                    const SizedBox(height: 6),
                    // 하차 정류장
                    if (segment.endStation != null)
                      _buildStationRow(
                        icon: Icons.arrow_circle_down,
                        label: "하차",
                        stationName: segment.endStation!,
                        color: Colors.red,
                      ),
                  ],

                  // 버스 정류장 목록 표시
                  if (!isWalk && segment.stations.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey[850],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "정류장 (${segment.stations.length}개)",
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ...segment.stations.asMap().entries.map((entry) {
                            final index = entry.key;
                            final station = entry.value;
                            final isFirst = index == 0;
                            final isLast = index == segment.stations.length - 1;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  // 정류장 번호/아이콘
                                  Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isFirst
                                          ? Colors.green
                                          : (isLast
                                                ? Colors.red
                                                : Colors.grey[600]),
                                    ),
                                    child: Center(
                                      child: Text(
                                        "${index + 1}",
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      station.name,
                                      style: TextStyle(
                                        color: isFirst || isLast
                                            ? Colors.white
                                            : Colors.grey[400],
                                        fontSize: 13,
                                        fontWeight: isFirst || isLast
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],

                  // 도보인 경우 세부 단계 표시
                  if (isWalk && segment.stepDescription.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...segment.stepDescription.map(
                      (step) => Padding(
                        padding: const EdgeInsets.only(left: 4, top: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "• ",
                              style: TextStyle(
                                color: Colors.grey[300],
                                fontSize: 14,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                step,
                                style: TextStyle(
                                  color: Colors.grey[300],
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 승하차 정류장 행 위젯
  Widget _buildStationRow({
    required IconData icon,
    required String label,
    required String stationName,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(
          "$label: ",
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        Expanded(
          child: Text(
            stationName,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
      ],
    );
  }
}
