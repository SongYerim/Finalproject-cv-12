import 'dart:convert';
import 'dart:async'; // TimeoutException 사용
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../models/route_model.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiService {
  // 싱글톤 패턴
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  static ApiService get instance => _instance;
  ApiService._internal();

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

  // ========================================
  // 공통 HTTP 헬퍼 메서드
  // ========================================

  /// GET 요청 공통 메서드
  Future<Map<String, dynamic>?> getJson(
    String path, {
    Map<String, String>? queryParams,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      var uri = Uri.parse('$baseUrl$path');
      if (queryParams != null) {
        uri = uri.replace(queryParameters: queryParams);
      }

      final response = await http
          .get(uri)
          .timeout(
            timeout,
            onTimeout: () {
              throw TimeoutException('요청 시간 초과', timeout);
            },
          );

      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes));
      }
      return null;
    } catch (e) {
      developer.log('❌ [ApiService] GET 오류: $e', name: 'ApiService');
      return null;
    }
  }

  /// POST Multipart 요청 공통 메서드 (이미지 업로드용)
  Future<Map<String, dynamic>?> postMultipart(
    String path, {
    required Uint8List imageBytes,
    required String filename,
    Map<String, String>? fields,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      final uri = Uri.parse('$baseUrl$path');

      final request = http.MultipartRequest('POST', uri);

      // 필드 추가
      if (fields != null) {
        request.fields.addAll(fields);
      }

      // 이미지 파일 추가
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          imageBytes,
          filename: filename,
          contentType: MediaType('image', 'jpeg'),
        ),
      );

      final streamedResponse = await request.send().timeout(
        timeout,
        onTimeout: () {
          throw TimeoutException('요청 시간 초과', timeout);
        },
      );

      if (streamedResponse.statusCode == 200) {
        final response = await http.Response.fromStream(streamedResponse);
        return json.decode(utf8.decode(response.bodyBytes));
      }
      return null;
    } catch (e) {
      developer.log('❌ [ApiService] POST Multipart 오류: $e', name: 'ApiService');
      return null;
    }
  }

  // ========================================
  // 기존 API 메서드
  // ========================================

  // 1. 목적지 검색 (텍스트 -> 좌표)
  Future<Map<String, dynamic>?> searchPlace(String query) async {
    return getJson('/search/place', queryParams: {'query': query});
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

  // ========================================
  // 확장된 API 메서드 (다른 서비스에서 통합)
  // ========================================

  /// 버스 도착 정보 조회
  Future<Map<String, dynamic>?> getBusArrival(
    String busNumber,
    String stationName,
  ) async {
    return getJson(
      '/bus/arrival',
      queryParams: {'bus_number': busNumber, 'station_name': stationName},
    );
  }

  /// OCR 이미지 전송
  Future<Map<String, dynamic>?> sendOcrImage(Uint8List imageBytes) async {
    return postMultipart(
      '/bus-ai/bus-recognition',
      imageBytes: imageBytes,
      filename: 'bus_crop.jpg',
      fields: {'mode': 'bus_number'},
    );
  }

  /// 태그 인식 이미지 전송
  Future<Map<String, dynamic>?> sendTagRecognition(Uint8List imageBytes) async {
    return postMultipart(
      '/bus-ai/bus-recognition',
      imageBytes: imageBytes,
      filename: 'tag_recognition.jpg',
      fields: {'mode': 'tag_'},
    );
  }
}
