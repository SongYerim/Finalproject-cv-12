import 'dart:convert';
import 'dart:io'; // Platform 확인용
import 'dart:async'; // TimeoutException 사용
import 'package:http/http.dart' as http;
import '../models/route_model.dart';

class ApiService {
  // 에뮬레이터 환경에 따른 주소 설정
  static final String baseUrl = Platform.isAndroid
      ? 'http://10.0.2.2:8000/' // 에뮬레이터용 (localhost)
      : 'http://127.0.0.1:8000/'; // Windows용

  // 1. 목적지 검색 (텍스트 -> 좌표)
  Future<Map<String, dynamic>?> searchPlace(String query) async {
    final url = Uri.parse('$baseUrl/search/place?query=$query');

    try {
      final response = await http
          .get(url)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException('요청 시간 초과', const Duration(seconds: 10));
            },
          );

      if (response.statusCode == 200) {
        final result = json.decode(utf8.decode(response.bodyBytes));
        return result;
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  // 2. 경로 탐색 (좌표 -> 경로 리스트)
  Future<List<RouteSegment>> getRoute(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) async {
    final url = Uri.parse(
      '$baseUrl/route/search?start_lat=$startLat&start_lng=$startLng&end_lat=$endLat&end_lng=$endLng',
    );

    try {
      final response = await http
          .get(url)
          .timeout(
            const Duration(seconds: 30), // 경로 검색은 시간이 더 걸릴 수 있음
            onTimeout: () {
              throw TimeoutException('요청 시간 초과', const Duration(seconds: 30));
            },
          );

      if (response.statusCode == 200) {
        final List<dynamic> jsonData = json.decode(
          utf8.decode(response.bodyBytes),
        );
        final routes = jsonData
            .map((item) => RouteSegment.fromJson(item))
            .toList();

        return routes;
      } else {
        return [];
      }
    } catch (e) {
      return [];
    }
  }
}
