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
      HapticFeedback.vibrate();

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

  // 로딩 화면: "경로 탐색 처리용" 화면 (첨부 이미지 형태 + Accessibility)
  Widget _buildRouteSearchingView() {
    // 화면 전체 여백/배치용
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24), // 패딩 약간 증가
      child: Column(
        // 위-가운데-아래로 배치
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 1) 상단 아이콘 3개 (도보/버스/지하철) - 크기 증가
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.directions_walk,
                size: 36, // 28 -> 36
                color: Theme.of(context).primaryColor,
              ),
              const SizedBox(width: 30),
              Icon(
                Icons.directions_bus_filled,
                size: 36, // 28 -> 36
                color: Theme.of(context).primaryColor,
              ),
              const SizedBox(width: 30),
              Icon(
                Icons.train,
                size: 36, // 28 -> 36
                color: Theme.of(context).primaryColor,
              ),
            ],
          ),

          const SizedBox(height: 40),

          // 2) 가운데 정보 표시 (스타일 유지하되 가독성 강화)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            decoration: BoxDecoration(
              color: Colors.black, // 고대비
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Theme.of(context).primaryColor,
                width: 3, // 두께 증가
              ),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).primaryColor.withValues(
                    alpha: 0.3,
                  ), // withOpacity -> withValues(alpha:)
                  blurRadius: 15,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 출발 (강조)
                Column(
                  children: [
                    const Text(
                      "출발",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "내 위치",
                      style: TextStyle(
                        fontSize: 32, // 글자 크기 대폭 증가
                        fontWeight: FontWeight.w900,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                  ],
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Icon(
                    Icons.arrow_downward,
                    color: Colors.white,
                    size: 30,
                  ),
                ),

                // 도착 (강조)
                Column(
                  children: [
                    const Text(
                      "목적지",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.destinationName,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 32, // 글자 크기 대폭 증가
                        fontWeight: FontWeight.w900,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 50),

          // 3) 하단 안내 문구 + 로딩
          Column(
            children: [
              Text(
                "최단 경로를 찾는 중...",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22, // 16 -> 22
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: 70,
                height: 70,
                child: CircularProgressIndicator(
                  strokeWidth: 8,
                  valueColor: AlwaysStoppedAnimation(
                    Theme.of(context).primaryColor,
                  ),
                  backgroundColor: Colors.grey[300],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // 실패/에러 화면 (기존 기능 유지, UI는 심플하게)
  // 실패/에러 화면 (screens/1.dart 스타일 적용)
  Widget _buildErrorView() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min, // Center 정렬을 위해 min
        children: [
          Icon(Icons.error_outline, size: 80, color: Colors.redAccent),
          const SizedBox(height: 20),
          Text(
            _errorText ?? "알 수 없는 오류",
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 40),

          // 다시 시도 버튼 (확대)
          SizedBox(
            width: double.infinity,
            height: 70,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: _fetchRoute,
              child: const Text(
                "다시 시도",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 이전 화면으로 버튼 (확대)
          SizedBox(
            width: double.infinity,
            height: 70,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey[800],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "이전 화면으로",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
