import 'dart:convert';
import 'dart:async'; // TimeoutException 사용
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/route_model.dart';

class ApiService {
  // 데스크탑의 로컬 IP 주소로 통일 (에뮬레이터/실제 기기 모두)
  // 서버 실행: uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
  static const String baseUrl = 'http://192.168.0.15:8000';

  // 1. 목적지 검색 (텍스트 -> 좌표)
  Future<Map<String, dynamic>?> searchPlace(String query) async {
    final url = Uri.parse('$baseUrl/search/place?query=$query');
    debugPrint('🔍 목적지 검색 시작: $url');

    try {
      final response = await http
          .get(url)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              debugPrint('⏱️ 목적지 검색 타임아웃 (10초)');
              throw TimeoutException('요청 시간 초과', const Duration(seconds: 10));
            },
          );

      debugPrint('📡 응답 상태: ${response.statusCode}');

      if (response.statusCode == 200) {
        final result = json.decode(utf8.decode(response.bodyBytes));
        debugPrint('✅ 목적지 검색 성공: ${result['name']}');
        return result;
      } else {
        debugPrint('❌ 검색 실패: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ 서버 연결 오류 (Search): $e');
      return null;
    }
  }

  // 2. 경로 탐색 (좌표 -> 경로 리스트) [cite: 60]
  Future<List<RouteSegment>> getRoute(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) async {
    final url = Uri.parse(
      '$baseUrl/route/search?start_lat=$startLat&start_lng=$startLng&end_lat=$endLat&end_lng=$endLng',
    );

    debugPrint('🗺️ 경로 검색 시작: $url');

    try {
      final response = await http
          .get(url)
          .timeout(
            const Duration(seconds: 30), // 경로 검색은 시간이 더 걸릴 수 있음
            onTimeout: () {
              debugPrint('⏱️ 경로 검색 타임아웃 (30초)');
              throw TimeoutException('요청 시간 초과', const Duration(seconds: 30));
            },
          );

      debugPrint('📡 경로 응답 상태: ${response.statusCode}');

      if (response.statusCode == 200) {
        final List<dynamic> jsonData = json.decode(
          utf8.decode(response.bodyBytes),
        );
        final routes = jsonData
            .map((item) => RouteSegment.fromJson(item))
            .toList();

        debugPrint('✅ 경로 검색 성공: ${routes.length}개 구간');

        return routes;
      } else {
        debugPrint('❌ 경로 탐색 실패: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('❌ 서버 연결 오류 (Route): $e');
      return [];
    }
  }
}
