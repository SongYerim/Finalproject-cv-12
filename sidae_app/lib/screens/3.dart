import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import '../models/route_model.dart';
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

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
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

                  // 설명 텍스트 (남은 공간을 차지하도록 Expanded 사용)
                  Expanded(
                    child: SingleChildScrollView(
                      child: Text(
                        widget.routes.isNotEmpty
                            ? widget.routes
                                  .map((route) {
                                    // 각 Segment 안에 있는 stepDescription(["설명1", "설명2"...])를
                                    // 줄바꿈(\n)으로 합쳐서 문자열로 만듭니다.
                                    return route.stepDescription.join('\n');
                                  })
                                  .join(
                                    '\n\n',
                                  ) // 각 Segment(덩어리) 사이에는 두 줄을 띄웁니다.
                            : "안내 정보를 불러오는 중...",

                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          height: 1.5, // 줄 간격 넉넉하게
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 안내 시작 버튼 (박스)
                  GestureDetector(
                    onTap: () {
                      // 4.dart로 이동
                      // 주의: 'Screen4' 부분을 4.dart에 있는 실제 클래스 이름으로 바꿔주세요.
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => Screen4(
                            routes: widget.routes,
                            destinationName: widget.destinationName,
                          ),
                        ),
                      );
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
}
