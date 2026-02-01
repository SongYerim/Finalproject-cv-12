import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sidae_app/screens/3.dart';
import '../services/api_service.dart';
import '../models/route_model.dart';

class RouteSearchScreen extends StatefulWidget {
  final double startLat;
  final double startLng;
  final double endLat;
  final double endLng;
  final String destinationName;

  const RouteSearchScreen({
    super.key,
    required this.startLat,
    required this.startLng,
    required this.endLat,
    required this.endLng,
    required this.destinationName,
  });

  @override
  State<RouteSearchScreen> createState() => _RouteSearchScreenState();
}

class _RouteSearchScreenState extends State<RouteSearchScreen> {
  final ApiService _apiService = ApiService();

  bool _loading = true;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _fetchRoute();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _fetchRoute() async {
    setState(() {
      _loading = true;
      _errorText = null;
    });

    try {
      // 3) 경로 탐색 (내 위치 -> 목적지 좌표)
      final List<RouteSegment> routes = await _apiService.getRoute(
        widget.startLat,
        widget.startLng,
        widget.endLat,
        widget.endLng,
      );

      // 서버가 빈 리스트를 반환할 수 있으므로 방어
      if (routes.isEmpty) {
        setState(() {
          _loading = false;
          _errorText = "경로를 찾을 수 없습니다.";
        });
        return;
      }

      // 경로 찾음 - 바로 화면 전환
      HapticFeedback.heavyImpact();

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MapResultScreen(
            routes: routes,
            destinationName: widget.destinationName,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _errorText = "경로 탐색 중 오류가 발생했습니다.\n$e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // AppBar 제거 (이미지처럼 상단에 타이틀 바가 없음)
      body: SafeArea(
        child: Center(
          child: _loading
              // ✅ 로딩 화면 (첨부 이미지 스타일)
              ? _buildRouteSearchingView()
              // ✅ 실패 화면 (기존 기능 유지: 다시 시도/뒤로)
              : _buildErrorView(),
        ),
      ),
    );
  }

  // 로딩 화면: "경로 탐색 처리용" 화면 (첨부 이미지 형태)
  Widget _buildRouteSearchingView() {
    // 화면 전체 여백/배치용
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        // 위-가운데-아래로 배치
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 1) 상단 아이콘 3개 (도보/버스/지하철)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.directions_walk,
                size: 28,
                color: Theme.of(context).primaryColor,
              ),
              const SizedBox(width: 26),
              Icon(
                Icons.directions_bus_filled,
                size: 28,
                color: Theme.of(context).primaryColor,
              ),
              const SizedBox(width: 26),
              Icon(
                Icons.train,
                size: 28,
                color: Theme.of(context).primaryColor,
              ),
            ],
          ),

          const SizedBox(height: 36),

          // 2) 가운데 카드 (연보라 느낌 + 라운드)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            decoration: BoxDecoration(
              // 이미지의 "연한 보라색 카드" 느낌 -> 고대비 테마박스
              color: Colors.black,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Theme.of(context).primaryColor,
                width: 2,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 출발: 내 위치 (강조)
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: const TextStyle(color: Colors.white),
                    children: [
                      const TextSpan(
                        text: "출발: ",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextSpan(
                        text: "내 위치",
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // 도착: 목적지 (목적지 이름 강조)
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: const TextStyle(color: Colors.white),
                    children: [
                      const TextSpan(
                        text: "도착: ",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextSpan(
                        text: widget.destinationName,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // 안내 문구 (이미지 문구에 맞춤)
                const Text(
                  "최단 경로를 찾고있습니다.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),

          const SizedBox(height: 44),

          // 3) 하단 큰 로딩 인디케이터
          SizedBox(
            width: 90,
            height: 90,
            child: CircularProgressIndicator(
              // 좀 더 “두꺼운 링” 느낌
              strokeWidth: 9,
              // 기본 테마 색을 쓰고 싶으면 Theme.colorScheme.primary로도 가능
              valueColor: AlwaysStoppedAnimation(
                Theme.of(context).primaryColor,
              ),
              backgroundColor: Colors.grey[800],
            ),
          ),

          // (선택) 상태 텍스트를 디버깅/유지하고 싶으면 아래처럼 숨겨둘 수도 있어요.
          // const SizedBox(height: 18),
          // Text(_statusText, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // 실패/에러 화면 (기존 기능 유지, UI는 심플하게)
  Widget _buildErrorView() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _errorText ?? "알 수 없는 오류",
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _fetchRoute, child: const Text("다시 시도")),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("이전 화면으로"),
          ),
        ],
      ),
    );
  }
}
