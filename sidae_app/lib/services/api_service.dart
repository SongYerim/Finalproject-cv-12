import 'dart:convert';
import 'dart:io'; // Platform 확인용
import 'dart:async'; // TimeoutException 사용
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import '../models/route_model.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiService {
  // .env 파일에서 서버 URL 로드
  static String get baseUrl {
    final envUrl = dotenv.env['SIDAE_SERVER_CLOUD_URL'];
    final fallbackUrl = 'http://10.0.2.2:8000'; // 기본값 (Android Emulator)

    developer.log('🔍 [ApiService] baseUrl 체크', name: 'ApiService');
    developer.log(
      '  - dotenv.env["SIDAE_SERVER_CLOUD_URL"]: $envUrl',
      name: 'ApiService',
    );
    developer.log(
      '  - dotenv.isInitialized: ${dotenv.isInitialized}',
      name: 'ApiService',
    );
    developer.log('  - 사용할 URL: ${envUrl ?? fallbackUrl}', name: 'ApiService');

    // envUrl이 null이면 fallbackUrl 사용
    return envUrl ?? fallbackUrl;
  }

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
